# Sidestreet

**A native iOS app for discovering the other city** — thrift and vintage stores, skate spots, street art, brutalist blocks, record stores, DIY spaces, independent cafés, flea markets and quiet viewpoints that standard guides and map searches skip.

- Native **Swift + SwiftUI**, iOS 17+, iPhone. MapKit + CoreLocation. No web views.
- **No account, no backend, no analytics, no paid APIs.** Everything runs on your phone against free, open data sources.
- Installs with a **free Apple Account** (Personal Team) — see **[docs/INSTALL.md](docs/INSTALL.md)**.

## What it does

| Tab | |
|---|---|
| **Discover** | Image-led feed of places and upcoming events around your GPS position or any city worldwide. Continuous radius slider (0.5–25 km), on/off category filters, progressive loading, pull to refresh. Tap a card for a compact preview, swipe up for the full profile. |
| **Map** | Apple Maps with your location, the search radius and colour-coded pins. Tap a pin for the same preview. |
| **History** | Cities and areas you searched — stored only on the phone. |
| **Settings** | Radius & units, data sources and photo sources, optional YouTube key and Mapillary token, cache, privacy, attribution, demo mode. |

**Categories:** Fashion (thrift, vintage, streetwear, skate, sneakers, designer, chains) · Flea & Markets · Skate · Street Art · Urban Explore (brutalism, industrial relics, water towers, bridges, stairs) · Photo Spots · Bars & Music (bars, pubs, clubs, venues, record stores) · Alt Culture (tattoo, galleries, comics, retro games, analogue photo, indie cinemas, hackerspaces, social centres) · Cafés · Food · Hidden Gems · Nature · Events.

**Profiles** show only real data: address, distance, opening hours with live open/closed status (in the city's time zone), price/affordability (sourced, or clearly marked as an estimate), photos with attribution (linked photos, the venue's own website image, street-level views from Panoramax/Mapillary), Look Around street imagery, a transparent niche-score breakdown, sources and confidence — plus links to search the place on TikTok, Instagram, Reddit, YouTube, Pinterest and Google Maps.

## How discovery works

1. **Sources** (all free): OpenStreetMap via Overpass (the backbone — community-mapped independent places), Wikidata (architecture by style, murals, venues; fame signal), Wikipedia & Wikimedia Commons (summaries, photos), Apple Maps local search (extra businesses, cross-checks), venues' own websites (schema.org events), optional YouTube Data API.
2. **Validation & de-duplication** across sources (identifiers + location + name similarity).
3. **Automatic niche score** — independence, obscurity, uniqueness, subculture relevance, community, source diversity, local buzz — damped by data confidence so unreliable obscurities can't win. See **[docs/SCORING.md](docs/SCORING.md)**.
4. **Hybrid feed ranking** — niche, quality, affordability, distance, relevance — with a variety pass so similar places don't cluster.
5. **Hotspots** — streets where independent fashion stores, street art or nightlife cluster ("Oranienstraße — 6 independent fashion stores") are detected and shown as walkable districts.

TikTok, Instagram, Pinterest and Reddit have **no usable public API** for a personal app (details in **[docs/DATA_SOURCES.md](docs/DATA_SOURCES.md)**), so the app never scrapes them; it links to their own search instead.

## Project layout

See **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**. In short: `Sidestreet/Core` is a platform-independent discovery engine (tested with `swift test` on any machine), `Sidestreet/Services` adapts Apple frameworks, `Sidestreet/Features` holds the SwiftUI screens.

## Build & test

- **Install on iPhone:** [docs/INSTALL.md](docs/INSTALL.md) (Xcode → free Apple Account → Personal Team → Run).
- **Tests in Xcode:** pick an iPhone simulator, press ⌘U.
- **Engine tests anywhere:** `swift test` (macOS or Linux, Swift 6+).
- **Live source check:** `LIVE_SOURCES=1 swift test --filter LiveSourcesTests` prints a real ranked discovery report.
- **CI:** `.github/workflows/ci.yml` builds the app with Xcode, runs the tests on a simulator, runs the engine tests on Linux and checks the live data sources.

## Privacy

Location is used only while the app is open, as a single fix to centre the radius — never in the background. Search history, settings and the temporary cache stay on the device. The exact list of services that receive requests (and what they receive) is in the app under *Settings → Privacy & network* and in [docs/DATA_SOURCES.md](docs/DATA_SOURCES.md).

## Attribution

Map data © OpenStreetMap contributors (ODbL). Wikidata (CC0). Wikipedia text (CC BY-SA 4.0). Wikimedia Commons images per their individual licences (shown in the app). Maps, search and Look Around © Apple.
