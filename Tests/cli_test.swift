// Headless test of the data engine (no GUI):
//   swiftc -O -swift-version 5 Sources/Models.swift Sources/IAPCache.swift \
//          Sources/StoreAPI.swift Tests/cli_test.swift -o /tmp/cli_test && /tmp/cli_test
import Foundation

@main
struct CLITest {
    static func main() async {
        print("storefront country: \(StoreAPI.country)")

        // 1. Search: free native Mac candidates for "chess"
        do {
            let results = try await StoreAPI.search(term: "chess")
            print("\nSEARCH 'chess': \(results.count) free native-mac candidates")
            for app in results.prefix(5) {
                print("  - [\(app.id)] \(app.name) — \(app.developer)")
            }
        } catch {
            print("SEARCH failed: \(error)")
        }

        // 2. IAP verification: known clean app and known IAP app
        let cache = IAPCache.shared
        let clean = await StoreAPI.verifyIAP(appId: "937984704", cache: cache) // Amphetamine
        let iap   = await StoreAPI.verifyIAP(appId: "1001018749", cache: cache) // Chess 3D Showdown (has IAP)
        let xcode = await StoreAPI.verifyIAP(appId: "497799835", cache: cache) // Xcode
        print("\nVERIFY Amphetamine (expect clean): \(clean)")
        print("VERIFY Chess 3D Showdown (expect hasIAP): \(iap)")
        print("VERIFY Xcode (expect clean): \(xcode)")

        // 3. Chart: top free overall
        do {
            let seeds = try await StoreAPI.chart(genreId: nil)
            print("\nCHART top-free: \(seeds.count) entries")
            for seed in seeds.prefix(5) {
                print("  - [\(seed.id)] \(seed.name)")
            }
            let metadata = try await StoreAPI.lookup(ids: seeds.map(\.id))
            let ordered = seeds.compactMap { metadata[$0.id] }
            print("LOOKUP resolved \(ordered.count)/\(seeds.count) to free native Mac apps")

            // 4. Verify the first 12 chart entries end to end
            print("\nVERIFYING first 12 chart entries:")
            for app in ordered.prefix(12) {
                let verdict = await StoreAPI.verifyIAP(appId: app.id, cache: cache)
                print("  \(verdict == .clean ? "CLEAN " : verdict == .hasIAP ? "IAP   " : "UNKWN ") \(app.name)")
            }
        } catch {
            print("CHART failed: \(error)")
        }

        print("\ndone")
        exit(0)
    }
}
