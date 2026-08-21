import SwiftUI
import AppKit

// MARK: - Root view

struct ContentView: View {
    @StateObject private var vm = StoreViewModel()

    var body: some View {
        NavigationSplitView {
            List(vm.categories, selection: $vm.selection) { category in
                Label(category.name, systemImage: category.symbol)
                    .tag(category.id)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 260)
        } detail: {
            detailView
                .navigationTitle(titleText)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            vm.refresh()
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        .keyboardShortcut("r", modifiers: .command)
                        .help("Reload the current list")
                    }
                }
        }
        .searchable(
            text: $vm.searchText,
            placement: .toolbar,
            prompt: "Search every Mac App Store app"
        )
        .onChange(of: vm.searchText) { _, _ in vm.searchTextChanged() }
        .onChange(of: vm.selection) { _, _ in vm.selectionChanged() }
        .task {
            if vm.apps.isEmpty && !vm.isWorking { vm.refresh() }
        }
        .frame(minWidth: 980, minHeight: 640)
    }

    private var titleText: String {
        let trimmed = vm.searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return "Search" }
        let id = vm.selection ?? "top"
        return vm.categories.first { $0.id == id }?.name ?? "Free App Store"
    }

    // MARK: - Detail states

    @ViewBuilder
    private var detailView: some View {
        if let message = vm.errorMessage {
            ContentUnavailableView {
                Label("Connection Problem", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { vm.refresh() }
            }
        } else if vm.apps.isEmpty && vm.isWorking {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Fetching apps and checking each one for hidden purchases…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.apps.isEmpty && !vm.isWorking {
            ContentUnavailableView {
                Label("Nothing Genuinely Free Found", systemImage: "tray")
            } description: {
                Text(emptyExplanation)
            }
        } else {
            VStack(spacing: 0) {
                if let info = vm.indexInfo {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text(info)
                        Spacer()
                    }
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.accentColor.opacity(0.08))
                }

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 255), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(vm.apps) { app in
                            AppCard(app: app)
                        }
                    }
                    .padding(16)

                    if vm.isWorking {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Verifying \(vm.pending) more app\(vm.pending == 1 ? "" : "s") for in-app purchases…")
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .padding(.bottom, 14)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        }
    }

    private var emptyExplanation: String {
        let trimmed = vm.searchText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "Every app in this chart contains in-app purchases."
        }
        return "Every free result for “\(trimmed)” contains in-app purchases, so nothing is shown. Try different keywords."
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text("\(vm.apps.count) app\(vm.apps.count == 1 ? "" : "s") · verified free, no in-app purchases")
            Spacer()
            if vm.isWorking {
                ProgressView().controlSize(.small)
                Text("checking \(vm.pending)…")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - App card

struct AppCard: View {
    let app: MacApp
    @State private var hovering = false

    var body: some View {
        Button(action: openInAppStore) {
            HStack(spacing: 12) {
                artwork
                    .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(app.developer.isEmpty ? app.genre : app.developer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ratingRow
                }

                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovering ? Color.accentColor.opacity(0.13) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open in App Store") { openInAppStore() }
            Button("Open Web Page") {
                if let url = app.webURL { NSWorkspace.shared.open(url) }
            }
            .disabled(app.webURL == nil)
            Button("Copy App Store Link") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(app.storeURL.absoluteString, forType: .string)
            }
        }
        .help("\(app.name)\nFree — no in-app purchases.\nRating from Apple's published recent reviews (Apple keeps full Mac aggregates private).\nClick to open in the App Store.")
    }

    @ViewBuilder
    private var artwork: some View {
        AsyncImage(url: app.artworkURL) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.quaternary)
                    .overlay(
                        Image(systemName: "app")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    )
            }
        }
    }

    @ViewBuilder
    private var ratingRow: some View {
        HStack(spacing: 6) {
            if app.rating > 0 {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text(String(format: "%.1f", app.rating))
                    .font(.caption)
                Text(app.ratingCount <= 20
                     ? "(\(app.ratingCount) recent)"
                     : "(\(app.ratingCount.formatted()))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text(app.genre.isEmpty ? "No ratings yet" : app.genre)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Label("No IAP", systemImage: "checkmark.seal.fill")
                .font(.caption2)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.green)
        }
    }

    /// Opens the native App Store app on this app's page.
    private func openInAppStore() {
        if !NSWorkspace.shared.open(app.storeURL), let web = app.webURL {
            NSWorkspace.shared.open(web)
        }
    }
}
