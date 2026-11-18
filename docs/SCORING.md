# Niche scoring & feed ranking

The niche score is automatic — there is no user-adjustable niche level. Every component is normalised to 0…1 and shown in the app under **"Why it's here"** on each profile.

## Components

| Component | Weight | Inputs |
|---|---:|---|
| **Independence** | 0.22 | Brand tags (`brand`, `brand:wikidata`), same name repeated in the area (≥ 3 → chain-like), community/co-op operator, public non-commercial spaces |
| **Off the radar** (obscurity) | 0.15 | 1 − fame, where fame = log-scaled number of Wikipedia editions (Wikidata sitelinks), `tourism=attraction`, prominence in generic Apple Maps searches |
| **Uniqueness** | 0.23 | 0.72 × intrinsic niche of the place type + 0.28 × rarity of that type in the current result set |
| **Subculture relevance** | 0.18 | 0.8 × type affinity (skate, graffiti, vintage, vinyl, DIY, club culture…) + multilingual keyword hits in name/description/tags (capped) |
| **Community** | 0.07 | Community-run, co-operative or non-profit; community-oriented types |
| **Source diversity** | 0.07 | 1 source → 0.35, 2 → 0.75, 3+ → 1.0 |
| **Local buzz** | 0.08 | Only when measured (YouTube key): 0 mentions 0.35 · 1–5 → 0.9 · 6–15 → 0.65 · more → 0.35 (mainstream) |

Weights of unavailable components are dropped and the rest renormalised to sum to 1.

The intrinsic niche values and subculture affinities per place type live in `PlaceKind` (e.g. DIY skatepark 0.95, record store 0.82, vintage store 0.82, café 0.30, fashion chain 0.05). They are editorial priors about *types*, never claims about a specific place.

## Confidence damping

```
score = raw × (0.55 + 0.45 × confidence)
```

Confidence (0…1) rises with a real name, tag richness, a recent mapper check date (`check_date`, `survey:date`), agreement of two or more independent sources, and presence of address/hours/website/photo. Businesses known only from Wikidata/Wikipedia are multiplied by 0.6 (they may have closed).

Consequences:

- An obscure place with unreliable data cannot outrank a well-documented independent gem.
- Low popularity alone never produces a high score — obscurity is 15 % of the raw score.
- Mainstream chains are still included (the brief asks for them, e.g. Zara, H&M, Bershka) but sit far down the feed.

Confidence labels: **Verified** (≥ 0.62 and either two sources or a check date within 2 years), **Partially verified** (≥ 0.38), **Unverified** (below, or a business confirmed only by encyclopaedic sources).

## Feed ranking

```
base = 0.38 niche + 0.17 quality + 0.10 affordability + 0.20 distance + 0.15 relevance
```

- *quality* = 0.6 × confidence + 0.4 × completeness (photo, hours, address).
- *affordability* = from source price data, `fee=no`, or labelled category estimates; unknown = neutral 0.5.
- *distance* = exp(−d / (0.45 × radius)).
- *relevance* = 1.0 if the primary category matches the active filter, 0.7 for a secondary category, 0.6 with no filter.

Events: 0.30 urgency (decays over ~3 weeks) + 0.15 confidence + 0.20 distance + 0.20 venue niche score + 0.15 relevance.

### Variety re-ranking

A greedy pass picks, at each position, the best of the next 40 candidates after penalties:

| Penalty | Value |
|---|---:|
| Same primary category as the previous card | 0.10 |
| Same place type within the last 4 cards | 0.08 |
| Category already appears twice in the last 4 cards | 0.06 |
| Within 80 m of the previous card | 0.04 |

This keeps the feed varied (no five cafés in a row) without any manual configuration. Ranking is deterministic for the same input.
