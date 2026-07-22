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
