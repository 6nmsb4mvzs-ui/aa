import SwiftUI

/// Exactly which services receive requests, and what they receive.
struct PrivacyView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                Text("No account, no login, no analytics, no advertising, no tracking and no crash reporting. Search history, settings and the cache stay on this iPhone. Location is requested only while the app is in use, as a single fix, and never in the background.")
            }
            Section("Who receives requests") {
                PrivacyRow(service: "OpenStreetMap Overpass API", host: "overpass-api.de; fallbacks overpass.private.coffee, ovp.dresel.systems",
                           receives: "The search area (bounding box) and the categories queried.")
                PrivacyRow(service: "Wikidata Query Service", host: "query.wikidata.org",
                           receives: "The search centre and radius.")
                PrivacyRow(service: "Wikipedia & Wikimedia Commons", host: "*.wikipedia.org, commons.wikimedia.org, upload.wikimedia.org",
                           receives: "A place's coordinates or article title when you open its profile, and image downloads.")
                PrivacyRow(service: "Apple Maps (MapKit)", host: "Apple",
                           receives: "Search terms with the map region, city searches, Look Around and maps for the Map tab — under Apple's privacy policy.")
                PrivacyRow(service: "Venue websites", host: "The venue's own site",
                           receives: "A normal page request (and robots.txt) to read published events (up to 10 venues per search) and, when a place without a photo scrolls into view, its preview image. Turn off under Data sources.")
                PrivacyRow(service: "Panoramax", host: "api.panoramax.xyz and its image servers",
                           receives: "A place's coordinates, to find a street-level photo facing it.")
                PrivacyRow(service: "Mapillary (optional)", host: "graph.mapillary.com",
                           receives: "Your token and a place's coordinates — only if you added a token.")
                PrivacyRow(service: "YouTube Data API (optional)", host: "www.googleapis.com",
                           receives: "Your API key and the place/city name as a search term — only if you added a key.")
                PrivacyRow(service: "Links you tap", host: "TikTok, Instagram, Reddit, Pinterest, Google Maps…",
                           receives: "Nothing until you tap a link; then the platform opens like any web link.")
            }
            Section {
                TextField("E-mail or URL (optional)", text: $settings.userAgentContact)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("Contact for API operators")
            } footer: {
                Text("Requests identify the app as “Sidestreet/1.0 (personal iOS urban-discovery app; non-commercial)”. Wikimedia and OpenStreetMap ask apps to include a contact so they can reach you instead of blocking traffic. Leave empty to send none. Changes apply on next launch.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Privacy & network")
        .font(.system(size: 14))
    }
}

private struct PrivacyRow: View {
    var service: String
    var host: String
    var receives: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(service).font(.system(size: 15, weight: .semibold))
            Text(host).font(.system(size: 12).monospaced()).foregroundStyle(Theme.textTertiary)
            Text(receives).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 2)
    }
}

/// What each source provides and its known limitations.
struct DataSourcesView: View {
    var body: some View {
        List {
            source("OpenStreetMap (Overpass API)", status: "Integrated",
                   detail: "The backbone: thrift, vintage and skate shops, skateparks, street art, brutalist buildings, record stores, social centres, viewpoints, markets with opening hours. Free, no key. Community data — quality varies by city. Public servers are sometimes slow; a second server is used as a fallback.")
            source("Wikidata", status: "Integrated",
                   detail: "Architecture by style (brutalist, modernist…), murals, clubs, record shops, arthouse cinemas, public bookcases. Also tells how famous a place is (number of Wikipedia editions), used to keep mainstream landmarks from dominating.")
            source("Wikipedia & Wikimedia Commons", status: "Integrated",
                   detail: "Article summaries and openly licensed photos, including photos geotagged near a place (labelled “nearby”).")
            source("Apple Maps (MapKit)", status: "Integrated",
                   detail: "Local business search to add and cross-check places, city autocomplete, Look Around imagery, and Apple's own place card (iOS 18+) for hours, photos and prices where Apple has them.")
            source("Venue websites", status: "Integrated",
                   detail: "Events published as schema.org data on venues' own websites, and each venue's own preview photo. robots.txt is respected; only events with explicit dates and locations are shown.")
            source("Panoramax", status: "Integrated",
                   detail: "Open street-level imagery (free, no key) used as a photo for places that have none. Coverage varies by city.")
            source("Mapillary", status: "Optional (your free token)",
                   detail: "Street-level photos for most streets in Europe and North America; the app picks a picture whose camera faces the place.")
            source("YouTube Data API v3", status: "Optional (your free key)",
                   detail: "Related videos on place profiles and a local-buzz signal for the niche score.")
            source("TikTok", status: "Link only",
                   detail: "TikTok's Research API is limited to approved academic researchers; there is no public search API for personal apps.")
            source("Instagram", status: "Link only",
                   detail: "No public search or location API; the Basic Display API was shut down in December 2024.")
            source("Pinterest", status: "Link only",
                   detail: "No public pin search for unapproved third-party apps.")
            source("Reddit", status: "Link only",
                   detail: "Self-service Data API access closed in November 2025; new access requires approval under Reddit's Responsible Builder Policy.")
            source("Google Places, Yelp, Foursquare", status: "Not used",
                   detail: "Review counts and price levels require paid plans or billing accounts. Google Maps is offered as a free outbound link instead.")
            Section("Known limitations") {
                Text("• Review counts and verified price levels are not available from free sources. Prices shown as “estimate” are based on the type of place.")
                Text("• Opening hours come from OpenStreetMap and are only evaluated when the format is fully understood.")
                Text("• Upcoming events depend on venues publishing machine-readable dates; many don't.")
                Text("• Coverage is strongest in cities with active OpenStreetMap communities.")
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.textSecondary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Data sources")
    }

    private func source(_ name: String, status: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(status).font(.system(size: 11, weight: .semibold)).foregroundStyle(status.hasPrefix("Integrated") ? Theme.positive : Theme.textTertiary)
            }
            Text(detail).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 2)
    }
}

struct AttributionView: View {
    var body: some View {
        List {
            Section {
                Text("Map data © OpenStreetMap contributors, available under the Open Database License (ODbL).")
                Link("openstreetmap.org/copyright", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            }
            Section {
                Text("Wikidata content is available under CC0.")
                Text("Wikipedia text is available under CC BY-SA 4.0.")
                Text("Wikimedia Commons images are shown with the author and licence provided by Commons; tap a photo to open its licence page.")
            }
            Section {
                Text("Maps, search and Look Around imagery © Apple.")
                Text("YouTube content © its creators, shown via the YouTube Data API.")
            }
        }
        .font(.system(size: 14))
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Attribution")
    }
}

/// Plain-language explanation of the automatic niche score.
struct ScoringExplainerView: View {
    var body: some View {
        List {
            Section {
                Text("Every place gets an automatic niche score from 0 to 100. There is no niche slider: the app combines several signals, and you can see the breakdown in each place's profile under “Why it's here”.")
            }
            Section("Signals") {
                row("Independence", "Brand data from OpenStreetMap, chains with a Wikidata brand entry, and how often the same name appears nearby. Community and co-operative spaces score highest.")
                row("Off the radar", "The inverse of fame: number of Wikipedia language editions, tourist-attraction tags and prominence in generic map searches.")
                row("Uniqueness", "How distinctive the type of place is (a DIY skatepark vs. a generic café) and how rare it is in this area.")
                row("Subculture relevance", "Skate, graffiti, vintage, vinyl, DIY and club-culture relevance from the type of place and keywords.")
                row("Community", "Run by a collective, co-op or non-profit.")
                row("Source diversity", "How many independent sources confirm the place.")
                row("Local buzz", "Only with a YouTube key: moderate video mentions count more than none or huge numbers.")
            }
            Section("Confidence damping") {
                Text("The weighted score is multiplied by 0.55 + 0.45 × data confidence. An obscure place with unreliable data can't outrank a well-documented independent gem — low popularity alone never makes a place score highly.")
            }
            Section("Feed order") {
                Text("The feed mixes niche score (42%), data quality (17%), affordability (9%), distance (17%) and filter relevance (15%), then re-orders to avoid several similar places in a row.")
            }
        }
        .font(.system(size: 14))
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Niche score")
    }

    private func row(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        }
    }
}
