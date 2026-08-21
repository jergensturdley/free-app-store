# Free App Store (macOS)

A native macOS app that mirrors the free side of the Mac App Store: every app
shown is **$0 with no in-app purchases (IAP)**. Clicking any app opens the real
App Store app directly on that app's page, ready to install.

## Why this exists

The Mac App Store's "free" charts are full of apps that are free to download but
packed with in-app purchases. This app re-checks every candidate against Apple's
own product-page data and **only shows apps without in-app purchases** — anything
that can't be confirmed clean is excluded (fail closed).

## Features

- **All Free Apps** — a bundled, best-effort index of the entire free native-Mac
  catalog (thousands of apps, built by crawling Apple's Search API; see
  "Full-catalog index" below); every entry is re-verified live before display
- **Browse** the Top Free Mac Apps chart plus 22 categories (Business, Developer
  Tools, Games, Graphics & Design, Productivity, Utilities, …)
- **Search** the entire Mac App Store catalog (search box, top right, or ⌘F)
- **Strict filtering** — each candidate's product page is checked for
  `hasInAppPurchases` and `isFree`; only `free + no IAP` apps are listed
- **One click** opens the native App Store app on that app's page
  (`macappstore://` deep link); right-click for web page / copy link
- **Live verification UI** — clean apps appear as they're verified, with a
  progress indicator for the rest
- **Verdict cache** — verification results are cached for 7 days in
  `~/Library/Caches/FreeAppStore`, so browsing is instant after the first pass
- **Ratings** — live star ratings on every card. Cross-platform apps get
  Apple's official aggregate from the Lookup API; Mac-only apps get a live
  average computed from Apple's published recent reviews (see "Ratings" below)
- Developer names, app icons, and genres from Apple's Search and Lookup APIs

## Run it

```bash
./build.sh          # compiles Sources/ into FreeAppStore.app (Swift, no deps)
open FreeAppStore.app
```

Requires Apple Silicon or Intel Mac with macOS 14+ and the Command Line Tools
(`xcode-select --install`). The build is ad-hoc signed and runs locally.

## Ratings — why Mac ratings are hard

Apple's public Search/Lookup APIs return **no rating aggregate for Mac-only
apps** (`averageUserRating` is always 0; it only carries values for apps that
share an iOS catalog entry), the web product pages load theirs through a
token-gated client API, and the legacy review RSS feeds are dead. The one
remaining token-free public source is Apple's legacy customer-reviews page
(`itunes.apple.com/{cc}/customer-reviews/id{id}`), which publishes the 20 most
recent reviews with star values.

So the app enriches ratings in a background pass after the grid loads:

- cards appear immediately after IAP verification (no rating delay)
- ratings then "light up" one app at a time, throttled to ~1 fetch / 350 ms and
  capped at 200 network fetches per browse session; cached ratings always apply
  and cost nothing, and each fresh result is cached for 7 days
- the legacy endpoint requires the iTunes desktop client identity
  (`iTunes/12.13` user agent + `X-Apple-Store-Front: <storefront>,12`);
  browser-style user agents get bounced to a JS interstitial
- counts shown as `(N recent)` for review-derived ratings vs `(18.4M)` for
  official aggregates
- if Apple's bot-gating interstitial kicks in anyway, the app leaves stars
  empty and picks them up on a later visit (a failed fetch is never cached)

Verified while building: Amphetamine ≈ 4.7 from its 20 most recent reviews;
Microsoft Word/Outlook/Excel all resolve too. The full per-storefront
aggregates Apple shows in the App Store app are private to Apple — this is the
closest a public client can get.

## How it works

| Step | Source |
|---|---|
| Search | iTunes Search API (`entity=macSoftware`, storefront = your locale) |
| Charts | Apple's legacy RSS feed `topfreemacapps` (overall + per genre) |
| Metadata | iTunes Lookup API (batched by 100 ids) |
| IAP check | The app's page on `apps.apple.com` — the embedded page data contains the app's own offer block (`offerDisplayProperties.adamId`) with the authoritative `hasInAppPurchases` / `isFree` flags |
| Open in App Store | `macappstore://apps.apple.com/app/id<id>` via `NSWorkspace` |

Only **native Mac apps** (`kind == "mac-software"`) at price 0 are considered;
"Designed for iPhone/iPad" apps that appear on Apple-Silicon Macs are skipped.

## Full-catalog index ("All Free Apps")

There is **no maintained third-party mirror** of the Mac App Store. I checked:

- `appgoblin-dev/appgoblin-data` (GitHub, 3.1M apps w/ IAP flags) — iOS/Android only, zero Mac apps
- Apple's own `apps.apple.com` sitemaps (1,344 shards) — iOS apps only; Mac apps excluded
- `marzzzello/appstore_crawler` — dead (Apple removed the genre pages it crawled)
- MacUpdate — sitemap broken, crawling disallowed

So the index is built from Apple's own **iTunes Search API**: a single query is
relevance-truncated even under the 200-result cap, so the builder enumerates a
broad set of search terms (every letter/digit, all 676 letter bigrams, plus
trigram refinement of capped terms), dedupes by `trackId`, and keeps only
`price == 0` + `kind == "mac-software"`. IDs are stable, so the app reconstructs
each `macappstore://` deep link from the index. Every indexed app is still
live-verified for in-app purchases before it is shown.

```bash
python3 Tools/build_index.py   # ~40 min, writes Resources/free-mac-index.json
./build.sh                     # bundles the index into the app
```

### Notes & honest limits

- The index is best-effort: search enumeration reaches the large majority of the
  catalog but can't prove completeness (Apple exposes no full-catalog listing).
- Verification costs one product-page fetch per never-seen app; the cache makes
  repeat visits free. Batches run 5-wide with retry/backoff to keep load light.
- The index storefront is `us`; the app re-checks every entry against your own
  storefront at runtime, so regional availability stays correct.

## Project layout

```
Sources/            Swift sources (SwiftUI + Foundation only, no dependencies)
  Models.swift        domain types + category list + index schema
  StoreAPI.swift      Apple API client + bundled-index loader + IAP page verifier
  IAPCache.swift      on-disk verdict cache (actor)
  StoreViewModel.swift ordered, cancellable verify-and-publish pipeline
  Views.swift         sidebar, card grid, index banner, status bar
  AppMain.swift       app entry point
Resources/Info.plist
Resources/free-mac-index.json  bundled catalog index (generated)
Tools/make_icon.swift  generates the app icon at build time
Tools/build_index.py   builds the full-catalog index from Apple's Search API
Tests/cli_test.swift   headless engine test (search / chart / verdicts)
build.sh               builds FreeAppStore.app
```

### Headless engine test

```bash
swiftc -O -swift-version 5 -module-cache-path .build/module-cache \
  Sources/Models.swift Sources/IAPCache.swift Sources/StoreAPI.swift \
  Tests/cli_test.swift -o .build/cli_test && .build/cli_test
```
