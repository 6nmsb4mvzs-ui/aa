# Architecture

Sidestreet is a native SwiftUI app (iOS 17+, iPhone) with a platform-independent discovery engine. There is no backend: every request goes from the phone straight to the free data sources.

```
Sidestreet.xcodeproj          ← open this in Xcode
Package.swift                 ← test harness: builds Sidestreet/Core + SidestreetTests with `swift test`
Config/Info.plist             ← background refresh, launch screen (merged with generated keys)
Sidestreet/
├── App/                      SidestreetApp (entry), RootView (tabs), AppModel (state), AppSettings, AppEnvironment (DI)
├── Core/                     Foundation-only — compiles on iOS, macOS and Linux
│   ├── Models/               Place, PlaceKind (taxonomy + priors), DiscoveryCategory, DiscoveryEvent, SearchArea, snapshot
│   ├── Geo/                  GeoCoordinate, haversine distance, radius maths
│   ├── Location/             LocationResolver — pure "where is the centre?" logic for every permission state
│   ├── Networking/           HTTPClient abstraction, URLSession client, per-host rate limiter, robots.txt
│   ├── OpeningHours/         OSM opening_hours parser + open/closed evaluation (time-zone aware)
│   ├── Providers/            OpenStreetMap (Overpass), Wikidata, Wikipedia, Commons, venue events, YouTube
│   ├── Engine/               DiscoveryEngine, PlaceValidator, Deduplicator, NicheScorer, FeedRanker, HotspotDetector
│   ├── Storage/              DiscoveryCache (temporary), SearchHistoryStore (local), ResponseCache
│   ├── Links/                Outbound links to TikTok / Instagram / Reddit / YouTube / Pinterest / Google Maps
│   └── Text/                 Name normalisation, fuzzy matching, subculture lexicon, MD5
├── Services/                 Apple-framework adapters: LocationService (CoreLocation), CitySearchService and
│                             AppleMapsProvider (MapKit), LookAroundService, ImagePipeline, KeychainStore,
│                             BackgroundRefresh (BGTaskScheduler), PlaceDetailService (lazy profile lookups)
├── Features/                 SwiftUI screens: Discover, Map, Place (preview → profile), Location picker, History, Settings
├── DesignSystem/             Theme tokens (dark urban palette, typography) and shared components
├── Support/                  Formatting helpers, SampleData (clearly-labelled fictional data), SwiftUI previews
├── Assets.xcassets           App icon, accent and launch colours
└── PrivacyInfo.xcprivacy     Privacy manifest (no tracking, no data collection)
SidestreetTests/              XCTest suites — run both in Xcode (⌘U) and with `swift test`
docs/                         This documentation
```

## Layers

1. **UI (SwiftUI, `Features/`, `DesignSystem/`)** — views read state from `AppModel` via the Observation framework (`@Observable`, `@Environment`). Views never call the network directly.
2. **App state (`App/AppModel`)** — main-actor orchestrator: resolves the search centre, starts discovery runs, ranks results off the main thread, paginates the feed, records history, reacts to settings.
3. **Platform services (`Services/`)** — thin adapters around CoreLocation, MapKit, Keychain and BackgroundTasks. `AppleMapsProvider` conforms to the core `PlaceSearchProvider` protocol, so the engine treats Apple Maps like any other source.
4. **Discovery core (`Core/`)** — pure Swift + Foundation. Contains all logic worth testing: providers and parsing, validation, de-duplication, scoring, ranking, caching, opening hours and location decisions. Because it has no UIKit/MapKit dependency it is compiled by the Swift Package for fast tests on any machine (and in CI on Linux).

## Discovery pipeline

```
          ┌──────────── OSM niche query ──→ OSM everyday query (sequential, same host)
area ──→  ├──────────── Wikidata around-query             (concurrent)
          └──────────── Apple Maps local search (12 queries, sequential)
                                │  each result → emit snapshot (progressive)
                                ▼
          validate → sanitise → de-duplicate → score   (DiscoveryEngine.assemble)
                                ▼
          Wikidata enrichment (fame, images) → recurring market events → venue-website events
                                ▼
          final snapshot → DiscoveryCache (24 h) → AppModel → FeedRanker + HotspotDetector (detached task) → feed pages of 20
```

- **Progressive loading:** the engine yields an `AsyncStream<DiscoveryUpdate>` (`initial` → `expanded` → `complete`, or `cached`). The feed shows the first results as soon as any source answers.
- **Cancellation:** changing city, GPS position or radius cancels the previous stream (and its network tasks).
- **Radius changes** are debounced (650 ms). A smaller radius around the same centre is answered from the cache with no network request; a larger radius fetches again.
- **Stale-while-revalidate:** cached results older than 6 h are shown immediately and refreshed quietly.

## Hotspots ("clusters worth a walk")

`HotspotDetector` looks for streets where several independent fashion stores (thrift, vintage, streetwear, skate, sneaker, designer, boutiques), street-art pieces or bars/clubs/venues cluster within ~220 m. Clusters of four or more are named after their dominant street (or district) and shown as an expandable feed card. Chains and repeated brand names are excluded. This answers "where should I go shopping/walking?" with data, beyond a flat list of stores. Brands stocked and local designers are not available from any free source; profiles link to Instagram/TikTok searches for those.

## Previews & sample data

`Support/Previews.swift` defines SwiftUI previews (whole app, cards, profile) driven by `SampleData` — fictional places flagged `isSample`, prefixed "Sample ·", rejected by the validator and always shown with a "SAMPLE DATA" banner. The same data powers *Settings → Demo mode*.

## Concurrency

- `DiscoveryEngine` runs its work in a detached task; providers are `Sendable` value types.
- `DiscoveryCache`, `SearchHistoryStore`, `HostRateLimiter`, `ImagePipeline` and `ResponseCache` are actors.
- `AppModel`, `AppSettings`, `LocationService` and `CitySearchService` are `@MainActor`; CoreLocation/MapKit delegate callbacks hop to the main actor explicitly.
- Ranking (up to a few thousand places) runs in a detached task; the main thread only swaps the result in.
- The core compiles warning-free with Swift 6 strict concurrency checking (`swift build`); the app target uses Swift 5 language mode for maximum compatibility across Xcode versions.

## Data quality

- **Validation** (`PlaceValidator`): valid coordinates inside the radius, real names (no placeholders), at least one source, safe URLs, HTML stripped; events must be upcoming, dated and located. Sample data can never pass validation.
- **De-duplication** (`Deduplicator`): union-find over identifier matches (same OSM element / Wikidata QID) and spatial-grid candidates; proximity *and* name similarity are both required; same-provider records need near-identical names; chain branches far apart never merge; inferred names never match.
- **Confidence** (`NicheScorer.confidence`): verified / partially verified / unverified, from data completeness, mapper check dates and source agreement. Businesses known only from encyclopaedic sources stay unverified.
- **No fabrication:** opening hours, prices, addresses and photos are shown only when a source provides them; price estimates are labelled as estimates; gaps are stated in the profile.

## Privacy

No accounts, analytics, ads, tracking or crash reporting. Location: when-in-use, single fixes, never in the background. History and settings stay on the device (history is excluded from iCloud backup). See *Settings → Privacy & network* in the app and [DATA_SOURCES.md](DATA_SOURCES.md).

## Testing

`SidestreetTests/` (≈ 115 tests) covers niche scoring, radius maths, category filtering, duplicate detection, feed ranking and variety, cache behaviour (expiry, radius reuse, persistence, eviction), validation, location permission handling, API failure handling (fail-over, rate limits, HTML error pages, partial failures), opening-hours parsing, JSON-LD events, robots.txt and provider parsing. `LiveSourcesTests` (opt-in, `LIVE_SOURCES=1`) exercises the real services and prints a ranked discovery report; CI runs it on every push and weekly.

Test files compile in both environments thanks to:

```swift
#if SWIFT_PACKAGE
@testable import SidestreetCore
#else
@testable import Sidestreet
#endif
```

## Continuous integration

`.github/workflows/ci.yml`:

- **Core unit tests** — Linux, Swift 6.1 container, `swift test`.
- **Live data sources** — real Overpass/Wikidata/Commons/Wikipedia/venue requests and a printed feed report.
- **iOS app build + tests** — macOS runner, newest Xcode, builds the app and runs the XCTest suite on an iPhone simulator.
