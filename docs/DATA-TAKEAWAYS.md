# NEON Ground Beetle Tracker — Data Takeaways & Critical Review

_Suite audit — June 2026. NEON DP1.10022.001 (Ground beetles sampled from pitfall traps)._

## What the data actually shows

All numbers below were recomputed directly from the 46 bundled `data/sites/<SITE>.rds`
tables and the cached `data/precomputed.rds`, using the app's own species-level
rule (`is_species_level` / `taxonRank ∈ {species, subspecies, speciesGroup}`).

- **Coverage is genuinely national and deep.** 46 NEON terrestrial sites, **64,652 records**,
  **233,027 individuals**, **2014–2023**, **385 site-years** (median **9 years/site**,
  range 4–11). **731 distinct species** network-wide; per-site richness median **51**.
  This is a real, large carabid dataset — not a scaffold.
- **Richness is biome-driven, NOT latitudinal** (Pearson r(richness, |lat|) = **−0.10**).
  The peak is the eastern deciduous/Appalachian belt — **ORNL 113**, **WOOD 109**,
  **SERC 103**, **BLAN 98**, **SCBI 96** species — while the climatic extremes are species-poor:
  arctic **BARR = 9**, tropical **GUAN = 7** and **LAJA = 19** (Puerto Rico). The latitudinal-
  diversity-gradient story does not appear in carabid richness here; habitat does.
- **Abundance and richness diverge.** The most *abundant* sites are not the *richest*:
  **STER** caught 24,765 individuals (cpn **70.9 /100 trap-nights**, the network high) at only
  71 species; **SERC** 12,334 at 103 species. Catch-per-100-trap-nights spans **2.8 (GUAN)
  to 70.9 (STER)** — a 25× effort-normalised range.
- **Four sites are dominated by a non-native European beetle** — a major ecological caveat
  the app never surfaces. `Pterostichus melanarius` is the #1 species at **STEI, UNDE, WOOD**
  and `Carabus nemoralis` at **TREE**. At WOOD the invader alone is 979 of 5,156 individuals.
  These "dominant species" are introduced, not signatures of intact native fauna.
- **Communities are dominance-skewed.** A single species routinely takes a large share:
  SRER's `Discoderus robustus` is **7,471 of 10,787** individuals (≈69%); GRSM's `Carabus goryi`
  6,416 of 11,950; STER's `Cratacanthus dubius` 6,026 of 24,765. The Hill q1/q0 evenness story
  is the real signal at most sites.
- **The QA/QC chain is real and mostly clean, but not free.** Network-wide, **95.9% of
  individuals are resolved to species**; **4.1% (≈9,543 individuals)** are stranded at
  genus (3,102) or family (3,866) and correctly **excluded from richness/diversity/ordination**.
  But the higher-taxon load is very uneven: **TEAK 45.0%**, **GUAN 40.8%**, **BARR 42.4%** of
  individuals are NOT named to species — exactly the species-poor, hard-to-key sites, where the
  "richness" number rests on the smallest identified base.
- **Seasonal activity peaks in June–July** (27 of 46 sites peak in month 6 or 7; the warm-season
  pitfall signal), shifting later (Aug–Oct) at cold/montane sites (e.g. OAES, HARV, RMNP) — a
  clean, defensible phenology.
- **Effort data is complete: trapnights NA rate is 0% at every site.** The "raw counts when a
  bundle lacks effort" fallback (`metric_kind == "count"`) therefore never fires on the real
  bundle — every site uses true catch-per-100-trap-nights.

## How it's built

`scripts/refresh_data.R` pulls DP1.10022.001 per site → `assemble_beetles()` in `R/helpers.R`
(carabid rows from `bet_sorting` where `sampleType == "carabid"`; **expert-taxonomist override**
of the parataxonomist call via `bet_expertTaxonomistIDProcessed`; trap-night effort per
plot×bout from `bet_fielddata$daysOfTrapping`) → one tidy long `.rds` per site with columns
`siteID, plotID, collectDate, taxonID, scientificName, taxonRank, individualCount, trapnights`.

`scripts/precompute.R` sources `global.R` and runs `build_national_index()` once, caching the
site index, **Bray–Curtis PCoA ordination** (`bray_ordination`, site×year unit, 372 points),
**IndVal indicators** (`indicator_species`, 521 rows), and the species×site range table to
`data/precomputed.rds` (24 KB, content-fingerprinted so a stale cache auto-invalidates).

The app (`server.R`) renders Overview (community bar + naive occupancy + phenology heatmap +
rank-abundance), Diversity (Hill q0/q1/q2, Hurlbert rarefaction, bout accumulation), Seasonality
(monthly cpn + co-located NEON env overlays with a deseasonalized driver×lag scan), Trends
(annual cpn OLS with a small-n-aware verdict), and Biogeography (richness/range map, PCoA,
IndVal table). **Metric definition:** abundance = **catch per 100 trap-nights**
(`effort = Σ unique(plotID, collectDate) trapnights`) — an **activity-density index, not true
density**. Richness-type metrics use `species_level == TRUE` only; abundance counts every beetle.

## Critical findings by lens

### NEONize (suite cohesion / parity)
- **[low] Non-native dominants unflagged.** STEI/UNDE/WOOD/TREE lead with introduced European
  species. *Fix:* add an `introduced` flag to `beetle_blurb`/`site_metadata` and badge it in the
  Overview verdict and "meet the beetles" cards — the flagship-quality move is to name the invader.
- **[low] Env overlays are inherited verbatim from the mammal app** and ship `flower/greenup/
  fruit` phenophases as beetle drivers, but `fruiting_pct` is near-empty (15 non-NA months at SRER).
  *Fix:* drop `fruit` from the beetle `ENV_LAYERS` default, or gate it on a non-NA-count floor so it
  never ranks on 15 points.
- **[good] Parity is otherwise strong:** map-picker front door, codebook+README zip export,
  PDF report, permutation null, content-fingerprinted precompute cache — all on par with the suite.

### Ecological (carabid pitfall domain)
- **[high] "Abundance" is activity-density, surfaced honestly but easy to misread.** Pitfall catch
  conflates true density with movement/activity — a fast-running `Pasimachus` or `Cicindela` is
  over-represented vs a sedentary species. The app says "catch per 100 trap-nights" everywhere
  (good) but the verdict banners ("most abundant: X — 69%") still read as abundance. *Fix:* one
  sentence in the Overview info-pop: "pitfall catch ∝ activity × density, so active surface
  hunters score high."
- **[med] Naive occupancy denominator bias is documented but structural.** `occupancy_table` divides
  by carabid-*positive* plot×bouts (zero-catch bouts are dropped at `clean_beetle`), over-stating how
  widespread a species is. Honest caveat is in the UI; flagged here as a known ceiling, not a bug.
- **[med] Species-poor sites lean on the thinnest ID base.** TEAK/GUAN/BARR exclude 40–45% of
  individuals as higher taxa before computing richness. *Fix:* show the species-level **individual
  count** (not just the % excluded) next to richness at these sites so users see the small base.

### Data science (Quinn — analysis-readiness)
- **[high] Bundle `.rds` files carry ALTREP deferred-string columns that segfault a fresh
  `readRDS()` + bulk access** (vanilla Rscript crashes on `nrow`/`names` until columns are
  materialized element-wise; `collectDate` is stored as a classless numeric day-count). The app
  survives because `clean_beetle` runs inside a warm session, but the bundle is **not portable** —
  a downstream user doing `readRDS()` hits a 139. *Fix:* in `refresh_data.R`, fully materialize
  with `data.frame`/`as.character` (not `col[seq_along(col)]`) and re-`saveRDS` with `version=2`;
  restore the `Date` class on `collectDate`.
- **[good] The CSV export is genuinely FAIR:** zip of tidy data + column codebook
  (`beetle_export_codebook`) + provenance README, with a runtime drift-guard asserting codebook
  columns == data columns. This is the suite's best download.

### Statistics (small-n honesty / null validity)
- **[high — and a headline] The environmental driver→activity link does not survive its own
  permutation null at any tested site.** Best-of-dredge correlations look sizeable
  (SRER precip r=+0.45 @9mo, HARV greenup r=−0.52 @4mo, STER greenup r=−0.53 @10mo) but the
  rotation-null permutation p-values are **0.29–0.90** — none beats chance over the ~39–65
  driver×lag candidates. The app **correctly** gates the loud verdict word on this p (demotes to
  "Apparent"). *Keep this machinery; do not "fix" the stats — the inputs are weak, as expected for
  consumers in this cascade.*
- **[med] Trend p-values are suppressed below 5 years (only YELL, TEAK qualify for suppression);
  44/46 sites are trend-testable** — but a 5–11 year OLS on annual cpn is still a low-power,
  autocorrelated series. The "read the direction, not the decimal" copy is the right honesty rail.
- **[med] PCoA axes explain only 6% / 5% of variance.** The ordination is legible but the first two
  axes carry little structure; biome clustering is weak in 2-D. *Fix:* print the var-explained on the
  plot (already computed in `attr(o,"var_explained")`) and add one line that low % = high
  community turnover, not a failed ordination.

## Honest-stats & caveats — what this app must NOT be read to claim

- **Not "beetles are declining/booming here."** A 5–11 year, autocorrelated annual series is
  underpowered; the verdict is direction + an honest p, never a population trajectory.
- **Not "this driver controls beetle activity."** Every site's best env correlation fails its
  permutation null (p ≥ 0.29). The Seasonality "tracking" panel is a hypothesis-generator, not
  evidence of an environmental control on carabid activity.
- **Not "true abundance/density."** Every count is **activity-density** (pitfall catch) — biased
  toward active, large, surface-active species. Comparisons across very different body plans
  (tiger beetles vs litter specialists) are not density comparisons.
- **Not "intact native richness" at STEI/UNDE/WOOD/TREE** — those communities are
  numerically dominated by introduced European carabids.
- **Richness at TEAK/GUAN/BARR rests on a small identified base** (40–45% of individuals never
  reach species); treat those counts as lower-confidence.

## Place in the cascade

This is the **consumer rung** of the climate → plants → consumers throughline, and it behaves
exactly as the suite's hard-won truths predict:

- The carabid env-tracking signal is **real but statistically weak** — best |r| ≈ 0.45–0.53 yet
  permutation p ≥ 0.29 at every tested site. Ground beetles cannot carry a confirmed sub-annual
  cascade link; like birds, they are **descriptive corroboration**, not a load-bearing rung.
- The app already does the right consumer-rung move the cascade memory calls for: it **pools the
  cross-site structure** (PCoA, IndVal across 46 sites / 372 site×year communities) rather than
  resting on per-site verdicts that n=4–11 site-years can't support.
- Where it can **strengthen the cascade**, the inputs (not the stats) are the lever, mirroring the
  desert-seasonal-split insight: the beetle response is monthly cpn, the env drivers are monthly
  precip/temp/greenup co-located bundles — a **winter/monsoon seasonal split of the desert sites
  (SRER, JORN, ONAQ)** is the analogous "one move" worth testing here, since annual aggregation
  blends ENSO-anticorrelated seasons exactly as it does for desert plant richness.
- **For the integrator (Driver Cascade):** feed this app's *pooled, species-level* activity-density
  and the per-site green-up overlay, NOT the per-site env correlations (they don't survive the null).
  The one robust suite link — **temperature → green-up onset** — sits upstream of this rung; beetles
  corroborate the plant signal's timing (June–July activity peak tracking warm-season green-up)
  without adding an independent confirmed climate→consumer coupling.
