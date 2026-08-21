import Foundation

/// The result of checking an app's product page for hidden purchases.
enum IAPVerdict: String, Codable {
    case clean      // confirmed free, no in-app purchases
    case hasIAP     // offers in-app purchases (or is not actually free)
    case unknown    // could not be verified (fail closed: app is not shown)
}

/// On-disk cache of IAP verdicts so we don't refetch product pages
/// that were already verified. Lives in ~/Library/Caches/FreeAppStore.
actor IAPCache {
    static let shared = IAPCache()

    private struct Record: Codable {
        let v: IAPVerdict
        var t: TimeInterval
        var r: Double?     // average rating (from published reviews / API)
        var rc: Int?       // number of ratings the average is based on
    }

    private var records: [String: Record] = [:]
    private let fileURL: URL

    init() {
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FreeAppStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("iap-verdicts.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        }
    }

    /// Verdicts expire: solid answers after 7 days, "unknown" after 30
    /// minutes (so transient failures get retried reasonably soon).
    func verdict(for id: String) -> IAPVerdict? {
        guard let r = records[id] else { return nil }
        let ttl: TimeInterval = (r.v == .unknown) ? 30 * 60 : 7 * 86400
        guard Date().timeIntervalSince1970 - r.t < ttl else { return nil }
        return r.v
    }

    func store(_ v: IAPVerdict, for id: String) {
        records[id] = Record(v: v, t: Date().timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Cached rating average, if fresh (7 days).
    func rating(for id: String) -> (average: Double, count: Int)? {
        guard let rec = records[id],
              let avg = rec.r, let count = rec.rc, count > 0
        else { return nil }
        guard Date().timeIntervalSince1970 - rec.t < 7 * 86400 else { return nil }
        return (avg, count)
    }

    func storeRating(_ average: Double, count: Int, for id: String) {
        let now = Date().timeIntervalSince1970
        if var rec = records[id] {
            rec.r = average
            rec.rc = count
            rec.t = now
            records[id] = rec
        } else {
            records[id] = Record(v: .unknown, t: now, r: average, rc: count)
        }
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
