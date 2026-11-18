# Data sources & API documentation

Every integration below was checked for availability, cost, rate limits, terms and attribution in November 2026. Only genuinely free sources are used. No API key is required for the core app; YouTube is optional with your own free key.

## Summary

| Source | Status | Key | Cost | Used for |
|---|---|---|---|---|
| OpenStreetMap — Overpass API | **Integrated** | none | free | Main discovery data |
| Wikidata Query Service | **Integrated** | none | free (CC0) | Architecture, art, venues; fame signal; images |
| Wikipedia REST API | **Integrated** | none | free | Article summaries on profiles |
| Wikimedia Commons | **Integrated** | none | free | Photos (linked + geotagged nearby) |
| Apple MapKit (on device) | **Integrated** | none | free | Local search, city autocomplete, geocoding, Look Around, place card |
| Venue websites (schema.org JSON-LD) | **Integrated** | none | free | Upcoming events |
| Panoramax | **Integrated** | none | free | Street-level photo facing places that have no photo |
| Venue website preview images | **Integrated** | none | free | The venue's own photo (Open Graph / page image) |
| Mapillary | **Optional** | your own token | free | Street-level photo facing the place |
| YouTube Data API v3 | **Optional** | your own | free quota | Videos on profiles, "local buzz" signal |
| TikTok | Link only | — | — | Opens TikTok search |
| Instagram | Link only | — | — | Opens Instagram search |
| Pinterest | Link only | — | — | Opens Pinterest search |
| Reddit | Link only | — | — | Opens Reddit search |
| Google Maps | Link only | — | — | Opens Google Maps (reviews, current hours) |
| Google Places / Yelp / Foursquare | Not used | — | paid / billing | — |

---

## OpenStreetMap — Overpass API

- **Endpoints (tried in order):** `https://overpass-api.de/api/interpreter` (main, FOSSGIS) → `https://overpass.private.coffee/api/interpreter` (no rate limit stated) → for European / North American searches only, the free regional extracts `https://ovp.dresel.systems/api/interpreter` and `…/api-na/interpreter` (no key, ≤ 4 parallel queries per IP, daily updates). An endpoint that just failed is tried last for the next 5 minutes.
- **Cost / key:** free, no key.
- **Usage policy (overpass-api.de):** under ~10,000 queries and 1 GB per day is fine; apps count as the sum of their users; no parallel queries; identify the app with a `User-Agent`; pause ~30 s after HTTP 429; commercial use should self-host. The main server is often overloaded.
- **How Sidestreet complies:** at most 2 queries per discovery run, always sequential (`HostRateLimiter`: 1 concurrent request per Overpass host); results cached 24 h; descriptive User-Agent; back-off after 429/503; automatic fallback to the second instance.
- **Queries** (`OverpassQueryBuilder`): a global `[bbox:…]` (fast spatial index) and client-side circle cut.
  1. *Niche query* — second-hand/charity/vintage/skate/record/tattoo/comics/games/photo shops, skateparks, street art & public art, brutalist/modernist buildings (`building:architecture`), water towers, industrial heritage, nightclubs, music venues, arts/social/community centres, independent cinemas, public bookcases, give boxes, markets, galleries, viewpoints, roasters, breweries, community gardens, named stairs/bridges, ponds/lakes, beaches, peaks, waterfalls.
  2. *Everyday query* — non-branded cafés, bars, pubs, cheap food, vegan/vegetarian/regional restaurants, clothing stores (chains included but ranked low), craft bakeries; each set capped (`out center N`).
- **Exclusions:** `access=private|no`, `disused`/`abandoned`/`demolished`, `shop=vacant`, `opening_hours=closed`, past `end_date` — the app never points to places that can't be entered legally.
- **Attribution:** "© OpenStreetMap contributors", ODbL — shown in the feed footer, profiles and Settings → Attribution.

## Wikidata Query Service

- **Endpoint:** `https://query.wikidata.org/sparql` (POST).
- **Cost / key:** free, no key. Data CC0.
- **Limits:** User-Agent required; per-IP query-time budget (≈60 s of query time per minute) and a small number of concurrent queries.
- **Queries** (`WikidataProvider`):
  - *Around query:* items within the radius whose architectural style (P149) is brutalist (Q994776), modern (Q245188), constructivist (Q841977), postmodern (Q595448), expressionist (Q1148060), International Style (Q162324), Metabolism (Q1503425), deconstructivism (Q238255), Neues Bauen (Q11784483), high-tech (Q845318), Stalinist (Q1134824); or that are instances (P31) of skatepark (Q909906), mural (Q219423), graffiti (Q17514), street art (Q17516), music venue (Q8719053), nightclub (Q622425), record shop (Q2243978), arthouse cinema (Q27921531), social center (Q8536775), flea market (Q385870), water tower (Q274153), observation tower (Q1440300), scenic viewpoint (Q6017969), public bookcase (Q294297), community garden (Q251958), amusement arcade (Q260676), comics shop (Q16590780), artist-run space (Q4034417), urban beach (Q7900097), footbridge (Q1068842). All IDs were verified against live Wikidata. Items with a dissolution/demolition date (P576) or closure date (P3999) are excluded; venue-type items described as "former…" are dropped.
  - *Enrichment query:* for OSM places that carry a `wikidata` tag — number of Wikipedia editions (sitelinks, used as a fame signal), image (P18), description.
- **Known limitation:** Wikidata often lacks closure dates for clubs and shops. Businesses known *only* from Wikidata are labelled **Unverified** and score lower until OSM or Apple Maps confirms them.
- **Evaluated and not used:** Wikidata as an *events* source — almost no upcoming local events with exact dates exist there.

## Wikipedia & Wikimedia Commons

- **Endpoints:** `https://{lang}.wikipedia.org/api/rest_v1/page/summary/{title}`; `https://commons.wikimedia.org/w/api.php` (`generator=geosearch`, `prop=imageinfo`); images from `upload.wikimedia.org`.
- **Cost / key:** free, no key.
- **Limits (2026 Wikimedia rate limits):** clients with a compliant User-Agent get ~200 requests/min, unidentified clients ~10/min; ≤ 3 concurrent requests; respect `Retry-After`. The User-Agent should contain contact info — the app sends none by default (privacy) and lets you add one in *Settings → Privacy & network*.
- **How Sidestreet complies:** profile lookups only when you expand a profile; ≤ 2 concurrent API requests and ≤ 3 image downloads; thumbnails are computed from file names (MD5 path) at Wikimedia's *standard* widths (960 px), avoiding API calls; responses cached.
- **Attribution:** Commons photos show author and licence from Commons metadata and link to the file page. Wikipedia text CC BY-SA 4.0.

## Apple MapKit (on device)

- **APIs:** `MKLocalSearch`, `MKLocalSearchCompleter`, `CLGeocoder`, `MKLookAroundSceneRequest`/`MKLookAroundSnapshotter`, `mapItemDetailSheet` (iOS 18+), SwiftUI `Map`.
- **Cost / key:** free for apps, no key, no developer membership needed.
- **Limits:** Apple throttles apps that search too frequently (`MKError.loadingThrottled`). Sidestreet issues 12 fixed queries per run, sequentially, and stops on throttling.
- **Use:** adds independent businesses missing from OSM and cross-confirms OSM records (raising confidence); generic-query hits mark a place as "prominent in mainstream search" (lowers obscurity). Apple's place card shows hours/photos/prices where Apple has them — the only free route to verified price levels.
- **Why not MapKit JS / Apple Maps Server API:** they require a paid Apple Developer Program membership.

## Venue websites (events)

- **What:** many clubs, galleries, cinemas and markets publish their programme as schema.org `Event` JSON-LD for search engines. Sidestreet reads it from the venue's own public website.
- **Rules:** robots.txt is fetched and respected (RFC 9309 subset); at most 10 venues per run, ≤ 3 concurrently, ≤ 1 request/s per host; at most one same-site "events/programme" link is followed; 3 MB page limit.
- **Validation:** only events with an explicit `startDate`, a confirmed location (coordinates, address, or the venue itself), not cancelled/postponed/online-only, not in the past, within 120 days.

## Photos for places without one

Each card asks `PhotoFinder` (results cached for a week), in this order:

1. **Linked photos** from the data itself — OSM `image`, `wikimedia_commons`, `panoramax` tags; Wikidata P18.
2. **The venue's own website** — its Open Graph / Twitter-card preview image, a schema.org business `image`, or the first real photo on the page (logos, icons, avatars and banners are skipped; robots.txt respected).
3. **Wikimedia Commons** geotagged photos within 35 m — only for street art, architecture, viewpoints and other public spaces, where a nearby photo usually shows the place itself.
4. **Mapillary** (optional, your free token from mapillary.com/dashboard/developers) — a recent, non-panoramic picture 4–45 m away whose camera faces the place. CC BY-SA 4.0.
5. **Panoramax** (`api.panoramax.xyz/api/search?place_position=…`) — open street-level imagery looking at the place; free, no key. Coverage varies.
6. **Apple Look Around** snapshot (on device), then a neutral placeholder.

Every non-linked photo is labelled on the card (WEBSITE · STREET VIEW · NEARBY PHOTO · LOOK AROUND) and credited in the profile. In a Trier test, venue websites and Commons alone lifted photo coverage of the top 40 places from 10 to 20; Apple-provided websites, Look Around and Mapillary add more on the phone.

## Recurring markets (OpenStreetMap)

Flea markets and markets with a machine-readable `opening_hours` schedule become dated events for the next 31 days (weekly-ish schedules only). If the schedule can't be parsed exactly, no dates are shown.

## YouTube Data API v3 (optional)

- **Endpoint:** `https://www.googleapis.com/youtube/v3/search`.
- **Cost / key:** free default quota of 10,000 units/day per Google Cloud project; `search.list` costs 100 units (≈ 100 searches/day). No billing account needed for this API. Get a key in Google Cloud Console → enable *YouTube Data API v3* → *Credentials → API key*. Stored in the iPhone Keychain, never in source code.
- **Use:** up to 6 related videos per profile (cached 12 h); mention count feeds the "local buzz" component.
- **Without a key:** profiles link to YouTube search instead.

## Social platforms — why they are links only

| Platform | Finding (Nov 2026) |
|---|---|
| **TikTok** | Research API is restricted to approved non-profit academic researchers; the Display API only returns the authorising user's own videos. No public search for personal apps. |
| **Instagram** | No public search or location search API. The Basic Display API was shut down on 4 Dec 2024; hashtag search requires a Business account, App Review and is limited to 30 hashtags/week. |
| **Pinterest** | API v5 offers no public pin search for unapproved third-party apps. |
| **Reddit** | Self-service Data API access ended in November 2025 (Responsible Builder Policy — new access needs approval); logged-out `.json` endpoints are blocked. |

Sidestreet therefore never scrapes, never bypasses logins, and never pretends these integrations exist. It opens each platform's own search page for the place or city, so you see real, original content.

## Not used

- **Google Places API** — requires a billing account (credit card), per-call pricing beyond free caps.
- **Yelp Fusion** — no longer free.
- **Foursquare Places** — price/rating/photo fields are premium; the open FSQ OS Places dataset is a bulk download unsuitable for on-device use.
- **Bing Web Search** — retired (2025). **Google Custom Search JSON API** — closed to new customers.
- **Nominatim** for city search — its usage policy forbids autocomplete; Apple's completer is used instead.
- **Eventbrite / Songkick / Resident Advisor** — no public event search API available to new personal apps.

## Identification

All requests carry `User-Agent: Sidestreet/<version> (personal iOS urban-discovery app; non-commercial[; your optional contact])`. No personal data is included unless you add a contact.
