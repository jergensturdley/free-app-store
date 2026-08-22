import Foundation
import SwiftUI

/// Drives the UI: loads chart/search candidates, verifies each one against
/// its product page, and publishes only apps confirmed to have no in-app purchases.
@MainActor
final class StoreViewModel: ObservableObject {

    @Published var apps: [MacApp] = []
    @Published var isWorking = false
    @Published var pending = 0
    @Published var searchText = ""
    @Published var selection: String? = "all"
    @Published var errorMessage: String?
    @Published var indexInfo: String?

    let categories = StoreCategory.all

    private enum Mode: Equatable {
        case category(String)
        case search(String)
    }

    private var mode: Mode = .category("all")
    private var pipeline: Task<Void, Never>?
    private var ratingWorker: Task<Void, Never>?
    private var ratingBacklog: [String] = []
    private var ratingBudget = 0
    private static let ratingBudgetPerRun = 200
    private var searchDebounce: Task<Void, Never>?

    // MARK: - Public intents

    /// (Re)load whatever mode is active.
    func refresh() {
        let isSearching = if case .search = mode { !searchText.isEmpty } else { false }
        if !isSearching {
            mode = .category(selection ?? "all")
        }
        run()
    }

    /// Called when the sidebar selection changes.
    func selectionChanged() {
        guard searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        mode = .category(selection ?? "all")
        run()
    }

    /// Called on every keystroke of the search field (debounced inside).
    func searchTextChanged() {
        searchDebounce?.cancel()
        let term = searchText.trimmingCharacters(in: .whitespaces)
        if term.isEmpty {
            mode = .category(selection ?? "all")
            run()
            return
        }
        searchDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.mode = .search(term)
            self?.run()
        }
    }

    // MARK: - Pipeline

    private func run() {
        pipeline?.cancel()
        ratingWorker?.cancel()
        ratingWorker = nil
        ratingBacklog = []
        ratingBudget = Self.ratingBudgetPerRun
        apps = []
        pending = 0
        errorMessage = nil
        isWorking = true

        let mode = self.mode
        pipeline = Task { [weak self] in
            guard let self else { return }
            do {
                let candidates: [MacApp]
                switch mode {
                case .category(let id) where id == "all":
                    if let index = StoreAPI.bundledIndex() {
                        candidates = index.apps
                        let day = String(index.built.prefix(10))
                        self.indexInfo = "Catalog index of \(index.total) free apps (built \(day)). Each one re-verified live below."
                    } else {
                        self.indexInfo = nil
                        candidates = []
                        self.errorMessage = "The bundled catalog index is missing. Rebuild it with: python3 Tools/build_index.py"
                        self.isWorking = false
                        return
                    }

                case .category(let id):
                    self.indexInfo = nil
                    let category = self.categories.first { $0.id == id } ?? self.categories[0]
                    let seeds = try await StoreAPI.chart(genreId: category.genreId)
                    try Task.checkCancellation()
                    let metadata = try await StoreAPI.lookup(ids: seeds.map(\.id))
                    var merged = seeds.compactMap { metadata[$0.id] }

                    // Apple's chart feed caps at ~100 entries per genre, so
                    // append the rest of the genre from the bundled catalog
                    // index: chart order leads, then full depth. ("top" stays
                    // chart-only by design.)
                    if category.genreId != nil, let index = StoreAPI.bundledIndex() {
                        let chartIds = Set(merged.map(\.id))
                        let rest = index.apps.filter {
                            $0.genre == category.name && !chartIds.contains($0.id)
                        }
                        merged.append(contentsOf: rest)
                    }
                    candidates = merged

                case .search(let term):
                    self.indexInfo = nil
                    candidates = try await StoreAPI.search(term: term)
                }

                try Task.checkCancellation()
                await self.verifyAndPublish(candidates)

                if !Task.isCancelled {
                    self.isWorking = false
                    self.pending = 0
                }
            } catch is CancellationError {
                // superseded by a newer pipeline; state already reset there
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = "Couldn't reach the App Store right now. Check your internet connection and try again."
                    self.isWorking = false
                    self.pending = 0
                }
            }
        }
    }

    /// Verifies candidates in small parallel batches, publishing confirmed
    /// clean apps in their original (relevance) order as batches settle.
    private func verifyAndPublish(_ candidates: [MacApp]) async {
        var seen = Set<String>()
        let ordered = candidates.filter { seen.insert($0.id).inserted }
        pending = ordered.count

        let batchSize = 5
        var index = 0
        while index < ordered.count {
            if Task.isCancelled { return }
            let batch = Array(ordered[index..<Swift.min(index + batchSize, ordered.count)])

            let verdicts: [String: IAPVerdict] =
                await withTaskGroup(of: (String, IAPVerdict).self) { group in
                    for app in batch {
                        let id = app.id
                        group.addTask {
                            (id, await StoreAPI.verifyIAP(appId: id, cache: IAPCache.shared))
                        }
                    }
                    var collected: [String: IAPVerdict] = [:]
                    for await (id, verdict) in group { collected[id] = verdict }
                    return collected
                }

            if Task.isCancelled { return }

            let clean = batch.filter { verdicts[$0.id] == .clean }
            if !clean.isEmpty {
                apps.append(contentsOf: clean)
                enqueueRatingWork(for: clean)
            }

            index += batch.count
            pending = ordered.count - index
        }
    }

    // MARK: - Ratings

    /// Apple's public APIs return no rating aggregate for Mac-only apps, so a
    /// throttled background worker fills stars in from Apple's published
    /// recent reviews as clean apps are published. Cards appear immediately;
    /// stars light up as they arrive. Network fetches are bounded by a
    /// per-run budget so a full-catalog browse can't hammer Apple; cached
    /// ratings always apply and cost nothing.
    private func enqueueRatingWork(for cleanApps: [MacApp]) {
        let ids = cleanApps.filter { $0.rating <= 0 }.map(\.id)
        guard !ids.isEmpty else { return }
        let known = Set(ratingBacklog)
        ratingBacklog.append(contentsOf: ids.filter { !known.contains($0) })
        ensureRatingWorker()
    }

    private func ensureRatingWorker() {
        if let worker = ratingWorker, !worker.isCancelled { return }
        ratingWorker = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard !self.ratingBacklog.isEmpty else { return }
                let id = self.ratingBacklog.removeFirst()

                if let cached = await IAPCache.shared.rating(for: id) {
                    self.apply(average: cached.average, count: cached.count, to: id)
                    continue
                }

                guard self.ratingBudget > 0 else { return }
                self.ratingBudget -= 1

                if let fresh = await StoreAPI.fetchReviewRating(appId: id) {
                    await IAPCache.shared.storeRating(fresh.average, count: fresh.count, for: id)
                    self.apply(average: fresh.average, count: fresh.count, to: id)
                }
                // Stay polite to the legacy endpoint (and its bot limits).
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }

    private func apply(average: Double, count: Int, to id: String) {
        guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
        apps[index].rating = average
        apps[index].ratingCount = count
    }
}
