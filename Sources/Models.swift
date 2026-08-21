import Foundation

// MARK: - Domain model

/// A Mac App Store app that is confirmed to be free of charge.
struct MacApp: Identifiable, Hashable {
    let id: String                 // numeric App Store (adam) id
    let name: String
    let developer: String
    let artworkURL: URL?
    let genre: String
    var rating: Double             // 0 = no ratings yet
    var ratingCount: Int
    let minimumOS: String
    let blurb: String
    let webURL: URL?               // https://apps.apple.com page (fallback)

    /// Deep link that opens the native App Store app on this app's product page.
    var storeURL: URL {
        URL(string: "macappstore://apps.apple.com/app/id\(id)")
            ?? URL(string: "macappstore://apps.apple.com")!
    }

    /// Builds a `MacApp` from an iTunes Search/Lookup API entry.
    /// Only entries that are *free* and *native Mac apps* pass.
    static func from(entry e: SearchEntry) -> MacApp? {
        guard let tid = e.trackId,
              let price = e.price, price == 0,
              e.kind == "mac-software"
        else { return nil }

        let blurb = (e.appDescription ?? "")
            .split(separator: "\n")
            .first
            .map(String.init) ?? ""

        return MacApp(
            id: String(tid),
            name: e.trackName ?? e.trackCensoredName ?? "Unknown",
            developer: e.artistName ?? e.sellerName ?? "",
            artworkURL: e.artworkUrl100.flatMap(URL.init(string:)) ?? e.artworkUrl512.flatMap(URL.init(string:)),
            genre: e.primaryGenreName ?? "",
            rating: e.averageUserRating ?? 0,
            ratingCount: e.userRatingCount ?? 0,
            minimumOS: e.minimumOsVersion ?? "",
            blurb: String(blurb.prefix(240)),
            webURL: e.trackViewUrl.flatMap(URL.init(string:))
        )
    }
}

/// Raw entry shape of the iTunes Search / Lookup API.
struct SearchEntry: Decodable {
    let trackId: Int?
    let trackName: String?
    let trackCensoredName: String?
    let artistName: String?
    let sellerName: String?
    let artworkUrl100: String?
    let artworkUrl512: String?
    let primaryGenreName: String?
    let price: Double?
    let formattedPrice: String?
    let kind: String?
    let averageUserRating: Double?
    let userRatingCount: Int?
    let minimumOsVersion: String?
    let trackViewUrl: String?

    enum CodingKeys: String, CodingKey {
        case trackId, trackName, trackCensoredName, artistName, sellerName
        case artworkUrl100, artworkUrl512, primaryGenreName
        case price, formattedPrice, kind
        case averageUserRating, userRatingCount, minimumOsVersion, trackViewUrl
        case appDescription = "description"
    }
    let appDescription: String?
}

struct SearchAPIResult: Decodable {
    let resultCount: Int
    let results: [SearchEntry]
}

/// A chart entry from Apple's RSS feed (id, name, icon only).
struct ChartSeed: Identifiable {
    let id: String
    let name: String
    let artworkURL: URL?
}

/// A browseable Mac App Store category backed by a top-free chart.
struct StoreCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let genreId: Int?

    static let all: [StoreCategory] = [
        StoreCategory(id: "all",  name: "All Free Apps",     symbol: "infinity",                  genreId: nil),
        StoreCategory(id: "top",  name: "Top Free",          symbol: "chart.line.uptrend.xyaxis", genreId: nil),
        StoreCategory(id: "biz",  name: "Business",          symbol: "briefcase.fill",            genreId: 6000),
        StoreCategory(id: "dev",  name: "Developer Tools",   symbol: "hammer.fill",               genreId: 6026),
        StoreCategory(id: "edu",  name: "Education",         symbol: "graduationcap.fill",        genreId: 6017),
        StoreCategory(id: "ent",  name: "Entertainment",     symbol: "film.fill",                 genreId: 6016),
        StoreCategory(id: "fin",  name: "Finance",           symbol: "dollarsign.circle.fill",    genreId: 6015),
        StoreCategory(id: "food", name: "Food & Drink",      symbol: "fork.knife",                genreId: 6023),
        StoreCategory(id: "games",name: "Games",             symbol: "gamecontroller.fill",       genreId: 6014),
        StoreCategory(id: "gfx",  name: "Graphics & Design", symbol: "paintpalette.fill",         genreId: 6027),
        StoreCategory(id: "hf",   name: "Health & Fitness",  symbol: "heart.fill",                genreId: 6013),
        StoreCategory(id: "life", name: "Lifestyle",         symbol: "leaf.fill",                 genreId: 6012),
        StoreCategory(id: "med",  name: "Medical",           symbol: "cross.case.fill",           genreId: 6020),
        StoreCategory(id: "music",name: "Music",             symbol: "music.note",                genreId: 6011),
        StoreCategory(id: "news", name: "News",              symbol: "newspaper.fill",            genreId: 6009),
        StoreCategory(id: "pv",   name: "Photo & Video",     symbol: "camera.fill",               genreId: 6008),
        StoreCategory(id: "prod", name: "Productivity",      symbol: "checkmark.circle.fill",     genreId: 6007),
        StoreCategory(id: "ref",  name: "Reference",         symbol: "books.vertical.fill",       genreId: 6006),
        StoreCategory(id: "shop", name: "Shopping",          symbol: "cart.fill",                 genreId: 6024),
        StoreCategory(id: "soc",  name: "Social Networking", symbol: "person.2.fill",             genreId: 6005),
        StoreCategory(id: "sport",name: "Sports",            symbol: "figure.run",                genreId: 6004),
        StoreCategory(id: "trav", name: "Travel",            symbol: "airplane",                  genreId: 6003),
        StoreCategory(id: "util", name: "Utilities",         symbol: "wrench.and.screwdriver.fill", genreId: 6002),
        StoreCategory(id: "wx",   name: "Weather",           symbol: "cloud.sun.fill",            genreId: 6001),
    ]
}

/// On-disk shape of the bundled full-catalog index (built by
/// Tools/build_index.py). Every entry is still live-verified for
/// in-app purchases before being shown.
struct IndexFile: Decodable {
    let built: String
    let country: String
    let total: Int
    let apps: [IndexApp]
}

struct IndexApp: Decodable {
    let id: String
    let name: String
    let developer: String?
    let icon: String?
    let genre: String?
    let rating: Double?
    let ratingCount: Int?
    let minOS: String?
    let blurb: String?
    let url: String?

    var macApp: MacApp {
        MacApp(
            id: id,
            name: name,
            developer: developer ?? "",
            artworkURL: icon.flatMap(URL.init(string:)),
            genre: genre ?? "",
            rating: rating ?? 0,
            ratingCount: ratingCount ?? 0,
            minimumOS: minOS ?? "",
            blurb: blurb ?? "",
            webURL: url.flatMap(URL.init(string:))
        )
    }
}

// MARK: - Small helpers

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
