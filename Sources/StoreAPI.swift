import Foundation

enum StoreAPIError: LocalizedError {
    case badURL
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid request URL."
        case .http(let code): return "The App Store returned HTTP \(code)."
        }
    }
}

/// Read-only access to Apple's public App Store endpoints.
enum StoreAPI {

    /// Storefront country derived from the user's locale (e.g. "us").
    static let country: String =
        (Locale.current.region?.identifier ?? "US").lowercased()

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// The legacy customer-reviews endpoint only serves the iTunes desktop
    /// client identity together with a storefront header; browser-style UAs
    /// get bounced to a JS interstitial.
    private static let legacyUserAgent = "iTunes/12.13 (Macintosh; OS X 14.0)"

    /// iTunes storefront ids by country code (fallback: United States).
    private static let storefrontIds: [String: String] = [
        "us": "143441", "gb": "143444", "de": "143443", "fr": "143442",
        "it": "143450", "es": "143454", "nl": "143452", "be": "143446",
        "at": "143445", "ch": "143459", "se": "143456", "no": "143457",
        "dk": "143458", "fi": "143447", "ie": "143449", "pt": "143453",
        "lu": "143451", "ca": "143455", "mx": "143468", "br": "143503",
        "au": "143460", "nz": "143464", "jp": "143462", "kr": "143466",
        "cn": "143465", "hk": "143463", "tw": "143470", "sg": "143464",
        "in": "143467", "za": "143472", "ru": "143469", "pl": "143478",
        "tr": "143480", "ae": "143481", "sa": "143483", "ar": "143505",
    ]

    private static var storefrontHeader: String {
        let id = storefrontIds[country] ?? "143441"
        return "\(id),12"
    }

    // MARK: - Transport

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw StoreAPIError.http(http.statusCode)
        }
        return data
    }

    // MARK: - Search (iTunes Search API)

    /// Full-text search of the Mac App Store. Returns only apps that are
    /// free of charge and native Mac apps; IAP filtering happens later.
    static func search(term: String) async throws -> [MacApp] {
        guard var comps = URLComponents(string: "https://itunes.apple.com/search") else {
            throw StoreAPIError.badURL
        }
        comps.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "macSoftware"),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "limit", value: "200"),
        ]
        guard let url = comps.url else { throw StoreAPIError.badURL }

        let data = try await get(url)
        let decoded = try JSONDecoder().decode(SearchAPIResult.self, from: data)

        var seen = Set<String>()
        var apps: [MacApp] = []
        for entry in decoded.results {
            if let app = MacApp.from(entry: entry), seen.insert(app.id).inserted {
                apps.append(app)
            }
        }
        return apps
    }

    // MARK: - Charts (legacy iTunes RSS)

    /// The current "Top Free Mac Apps" chart, overall or per genre.
    static func chart(genreId: Int?) async throws -> [ChartSeed] {
        var urlString = "https://itunes.apple.com/\(country)/rss/topfreemacapps/limit=200"
        if let genreId { urlString += "/genre=\(genreId)" }
        urlString += "/json"
        guard let url = URL(string: urlString) else { throw StoreAPIError.badURL }

        let data = try await get(url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = root["feed"] as? [String: Any]
        else { return [] }

        // "entry" is an array, except when the feed has a single entry.
        var entries: [[String: Any]] = []
        if let arr = feed["entry"] as? [[String: Any]] { entries = arr }
        else if let one = feed["entry"] as? [String: Any] { entries = [one] }

        var seeds: [ChartSeed] = []
        var seen = Set<String>()
        for entry in entries {
            guard let id = ((entry["id"] as? [String: Any])?["attributes"] as? [String: Any])?["im:id"] as? String,
                  seen.insert(id).inserted
            else { continue }
            let name = (entry["im:name"] as? [String: Any])?["label"] as? String ?? ""
            var artwork: URL?
            if let images = entry["im:image"] as? [[String: Any]],
               let largest = images.last,
               let s = largest["label"] as? String {
                artwork = URL(string: s)
            }
            seeds.append(ChartSeed(id: id, name: name, artworkURL: artwork))
        }
        return seeds
    }

    // MARK: - Lookup (iTunes Lookup API)

    /// Batch-resolves chart ids into full metadata.
    /// Returned map is keyed by app id; missing ids were removed from sale
    /// or are not native Mac apps.
    static func lookup(ids: [String]) async throws -> [String: MacApp] {
        var map: [String: MacApp] = [:]
        for chunk in ids.chunked(into: 100) {
            guard var comps = URLComponents(string: "https://itunes.apple.com/lookup") else {
                continue
            }
            comps.queryItems = [
                URLQueryItem(name: "id", value: chunk.joined(separator: ",")),
                URLQueryItem(name: "country", value: country),
            ]
            guard let url = comps.url else { continue }
            let data = try await get(url)
            let decoded = try JSONDecoder().decode(SearchAPIResult.self, from: data)
            for entry in decoded.results {
                if let app = MacApp.from(entry: entry) { map[app.id] = app }
            }
        }
        return map
    }

    // MARK: - Bundled full-catalog index

    /// Loads the bundled best-effort index of ALL free native Mac apps
    /// (generated by Tools/build_index.py). Entries are candidates only:
    /// the caller still runs them through live IAP verification.
    static func bundledIndex() -> (apps: [MacApp], built: String, total: Int)? {
        guard let url = Bundle.main.url(forResource: "free-mac-index", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(IndexFile.self, from: data)
        else { return nil }
        return (index.apps.map(\.macApp), index.built, index.total)
    }

    // MARK: - Ratings

    /// Apple's public search/lookup APIs return no rating aggregate for
    /// Mac-only apps, and the web product pages load theirs through a
    /// token-gated client API. The one public, token-free surface that
    /// carries real user ratings is Apple's legacy customer-reviews page,
    /// which lists recent reviews with star values (20 per page).
    ///
    /// Returns the average of those published reviews and the sample size,
    /// or nil when the app has no public reviews.
    static func fetchReviewRating(appId: String) async -> (average: Double, count: Int)? {
        guard let html = await fetchReviewPage(appId: appId) else { return nil }

        guard let regex = try? NSRegularExpression(pattern: "aria-label='(\\d) stars?'") else {
            return nil
        }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var sum = 0
        var count = 0
        for match in matches {
            guard let r = Range(match.range(at: 1), in: html), let stars = Int(html[r]) else {
                continue
            }
            sum += stars
            count += 1
        }
        guard count > 0 else { return nil }
        return (Double(sum) / Double(count), count)
    }

    /// This legacy WebObjects endpoint hangs under URLSession for reasons
    /// that don't reproduce with curl, so it is fetched with the system curl
    /// (the app runs unsandboxed; every other endpoint uses URLSession).
    private static func fetchReviewPage(appId: String) async -> String? {
        let urlString = "https://itunes.apple.com/\(country)/customer-reviews/id\(appId)?displayable-kind=11&page=1"

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = [
                "-s", "--max-time", "20",
                "-A", legacyUserAgent,
                "-H", "X-Apple-Store-Front: \(storefrontHeader)",
                urlString,
            ]
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }

            // Drain the pipe on a background thread: the page is larger
            // than the pipe buffer, so reading only after exit deadlocks.
            DispatchQueue.global().async {
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0,
                      let text = String(data: data, encoding: .utf8),
                      !text.isEmpty
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: text)
            }
        }
    }

    /// Best available rating for an app: cached value, otherwise a fresh
    /// review sample (which is then cached).
    static func rating(appId: String, cache: IAPCache) async -> (average: Double, count: Int)? {
        if let cached = await cache.rating(for: appId) { return cached }
        guard let fresh = await fetchReviewRating(appId: appId) else { return nil }
        await cache.storeRating(fresh.average, count: fresh.count, for: appId)
        return fresh
    }

    // MARK: - In-app purchase verification

    /// Verifies whether an app offers in-app purchases by reading the
    /// app's own product page on apps.apple.com. The embedded page data
    /// carries the app's authoritative offer block:
    /// `offerDisplayProperties.adamId == <id>` with `hasInAppPurchases`.
    /// Anything that cannot be confirmed clean is reported as `.unknown`
    /// (the UI then excludes the app — fail closed).
    static func verifyIAP(appId: String, cache: IAPCache) async -> IAPVerdict {
        if let cached = await cache.verdict(for: appId) { return cached }

        var verdict: IAPVerdict = .unknown
        var attempt = 0
        while attempt < 3 {
            if attempt > 0 {
                // Back off before retrying: ~1.5s, then ~4s (plus jitter).
                let base: Double = (attempt == 1) ? 1.5 : 4.0
                let delay = UInt64((base * 1_000_000_000))
                    + UInt64.random(in: 0...500_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
            attempt += 1

            guard let url = URL(string: "https://apps.apple.com/\(country)/app/id\(appId)") else {
                break
            }
            do {
                let data = try await get(url)
                let parsed = parseVerdict(page: data, appId: appId)
                if parsed != .unknown {
                    verdict = parsed
                    break
                }
                verdict = .unknown
            } catch {
                verdict = .unknown
            }
        }

        await cache.store(verdict, for: appId)
        return verdict
    }

    static func parseVerdict(page: Data, appId: String) -> IAPVerdict {
        guard let text = String(data: page, encoding: .utf8) else { return .unknown }

        let marker = "id=\"serialized-server-data\""
        guard let markerRange = text.range(of: marker),
              let openTagEnd = text.range(of: ">", range: markerRange.upperBound..<text.endIndex),
              let scriptEnd = text.range(of: "</script>", range: openTagEnd.upperBound..<text.endIndex)
        else { return .unknown }

        var payload = String(text[openTagEnd.upperBound..<scriptEnd.lowerBound])
        var root = try? JSONSerialization.jsonObject(with: Data(payload.utf8))
        if root == nil {
            payload = payload
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
            root = try? JSONSerialization.jsonObject(with: Data(payload.utf8))
        }
        guard let json = root else { return .unknown }
        guard let offer = findOffer(in: json, appId: appId) else { return .unknown }

        return (offer.isFree && !offer.hasIAP) ? .clean : .hasIAP
    }

    /// Recursively finds the offer block belonging to `appId` itself
    /// (the page also embeds offer blocks for related apps).
    private static func findOffer(in node: Any, appId: String)
        -> (hasIAP: Bool, isFree: Bool)? {
        if let dict = node as? [String: Any] {
            if let offer = dict["offerDisplayProperties"] as? [String: Any] {
                let adam = (offer["adamId"] as? String)
                    ?? (offer["adamId"] as? Int).map(String.init)
                if adam == appId {
                    let hasIAP = (offer["hasInAppPurchases"] as? Bool) ?? true
                    let isFree = (offer["isFree"] as? Bool) ?? false
                    return (hasIAP, isFree)
                }
            }
            for value in dict.values {
                if let found = findOffer(in: value, appId: appId) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = findOffer(in: value, appId: appId) { return found }
            }
        }
        return nil
    }
}
