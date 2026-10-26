# Ground Beetle Tracker science contract

This contract separates sampling opportunities from biological outcomes and defines
what the application may claim. It is the scientific source of truth for tests,
bundles, labels, exports, and Driver integration.

## Source and scope

- NEON data product: `DP1.10022.001`, Ground beetles sampled from pitfall traps.
- Intended population: observations made under NEON's pitfall-trapping protocol at
  the terrestrial sites and dates represented by the committed source data.
- Primary outcome: Carabidae individuals caught, reconciled to the authoritative
  expert taxonomic identification where available.
- Release policy: the bundle holds released data only, pinned to one NEON release
  (`GBT_RELEASE`, today RELEASE-2026, DOI https://doi.org/10.48443/q9ne-6b77) with
  `include.provisional = FALSE`. Expert identifications arrive after NEON's
  provisional window, so provisional records stay out until a release includes
  them. Adopting a newer release is a reviewed change to `GBT_RELEASE`; the refresh
  workflow's release watch opens an issue when NEON publishes one.
- Interpretation: effort-normalized catch is **activity-density**, not absolute
  population density, site health, habitat quality, or a causal climate response.

## Opportunity and outcome grains

The physical sampling opportunity is a valid pitfall-trap deployment represented
by the field-effort table. Its most specific available identity is:

`siteID x plotID x collection bout x trap identity`

The application may aggregate that to plot-bout or site-time grains only after the
physical opportunities are resolved. A valid sampled opportunity with no carabid
catch contributes effort and a zero outcome. Missing, invalid, or indeterminate
effort contributes neither a zero nor an estimated denominator.

The biological outcome grain is a taxon catch record within a sampled opportunity.
Positive sorting records cannot, by themselves, enumerate zero-catch sampling
opportunities.

## Required estimator behavior

### Activity-density

For an eligible scope:

`100 x sum(Carabidae individuals caught) / sum(valid attempted trap-nights)`

- Deduplicate physical effort before summing it across taxa.
- Include valid zero-carabid opportunities in the denominator.
- Do not silently fall back to raw counts in a panel labelled catch per 100
  trap-nights.
- Suppress or label unavailable when the denominator cannot be established.

### Species richness and composition

- Reconcile parataxonomist records to the authoritative expert identification.
- Count richness only for accepted species-level ranks. Coarser identifications may
  remain in total catch/activity summaries but never count as species.
- The species key is the binomial. Subgenus tags are stripped and every trinomial
  (nominal or not) is merged into its species, so one species never counts twice
  under two names. A species-group call ("Genus a/b") counts as one species only
  when no member species was caught at that site; otherwise it stays in abundance
  with `species_level = FALSE`. The verbatim NEON name travels in the export as
  `scientificName_verbatim`. (Lead ruling 2026-10-21, audit item 15.)
- Richness is observed/minimum richness unless an explicitly tested estimator and
  its uncertainty/support diagnostics are shown.

### Occupancy-like summaries

- The denominator is sampled opportunity units at the stated grain, including
  valid non-detections.
- A ratio formed only from units containing positive carabid records is a
  catch-conditioned detection share and must not be called occupancy.
- No detection-probability correction is implied unless a separate reviewed model
  supports it.

### Temporal trends

- Annual values must share the same effort-opportunity contract as activity-density.
- Per-trap-night effort absorbs the 2018 change from 4 to 3 traps per plot. It does
  not absorb the 2023 cut from 10 plots to 6 per site: the kept plots can catch more
  or fewer beetles than the old set, so the 2023 value is not directly comparable
  with earlier years. Trend charts and the PDF carry design-change markers at 2018
  and 2023 and the copy must not claim the 2023 change is normalised away. A
  plot-matched estimator is a separate HK-reviewed methods decision.
- A trend is tested only with at least 6 years (the suite standard); fewer years
  get a direction-only reading.
- A trend verdict may say "statistically clear" only when the fit also holds,
  with the same sign, after dropping the 2023 value (and at least 6 years remain),
  and when it also holds on a season-standardised series: core months are those
  sampled in at least 75% of years, a year missing a core month is a partial
  season (for example 2020, when NEON reduced sampling for COVID), and the check
  refits on full-coverage years only (at least 6). When 2023 is in the series the
  season check also leaves 2023 out, so both exclusions apply together. A check
  that lacks 6 comparable years is reported as "cannot be confirmed", not as a
  failure.
- The seasonal climate card correlates only comparable years: partial-season
  years and 2023 are left out of its annual response before the n >= 6 and
  adjusted-p gates apply.
  When significance rests on 2023 the verdict reads as an apparent change that
  depends on a non-comparable year; the plotted values and the slope are unchanged.
- Preserve the existing small-series gate and show the number of supported years.
- OLS trend language is descriptive; it does not establish population change or a
  causal driver.

### Environmental relationships

- Preserve the deseasonalization, support floors, candidate-search disclosure, and
  circular-shift/permutation null.
- Label surviving or non-surviving associations as exploratory. Never present the
  best lag/correlation from a scan as causal evidence.

## Claims matrix

### CAN

- Describe which expert-reconciled carabid taxa were caught in supported samples.
- Compare within-site activity-density through time when opportunity-complete
  effort and support gates pass.
- Show species-level observed richness, composition, introduced-species context,
  seasonal activity, and exploratory environmental associations with their stated
  gates and caveats.
- Treat PUUM (Hawaii, NEON domain D20) richness as a floor: NEON reports some
  state-listed taxa there only above species rank.

### CANNOT

- Estimate absolute beetle abundance or population density from pitfall catch.
- Treat catch-conditioned effort as complete sampling opportunity.
- Infer ecosystem/site health from carabid catch alone.
- Claim environmental causation from an observational best-lag correlation.
- Turn missing sampling into a biological zero.

### HELD

- Cross-site rankings and occupancy-like outputs remain held until committed
  bundles include opportunity-complete field-effort rows and adversarial fixtures
  prove zero-catch, missing-effort, duplicate-effort, and protocol-change behavior.
  The effort-row half is met (46 of 46 bundles carry explicit effort anchors); the
  protocol-change fixture half is not, and raw observed richness moves up to 18
  rank places once rarefied to a common catch. So on 2026-10-21 the Biogeography
  "#N of 46" rank banner, the richness-sized dots on both maps (the front-door
  picker and the Biogeography map) and the richest-first default order of the site
  comparison table were removed rather than the gate cleared. Any future rank must
  first clear this gate in writing here and then rank on rarefied richness with
  per-site coverage shown.
- Driver metric adoption remains held until the same source definition passes the
  pinned build, bundle, manifest, and deployed semantic-health gates.

## Required fixtures

1. A valid field opportunity with no carabid catch contributes trap-nights and zero
   catch.
2. Multiple taxa from one trap/bout do not multiply the effort denominator.
3. Missing or invalid effort is unavailable, not zero.
4. Expert ID overrides the provisional name/rank without duplicating catch.
5. Genus/family records do not inflate species richness.
6. Introduced-species flags survive aggregation and export.
7. Protocol-era changes remain comparable through actual attempted effort, not a
   hard-coded trap count.
8. Short time series and under-supported environmental scans fail closed.
9. Bundle, UI, codebook, CSV, card, and PDF labels agree with this contract.
