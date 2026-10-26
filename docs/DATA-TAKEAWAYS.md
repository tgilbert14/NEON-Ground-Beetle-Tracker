# NEON Ground Beetle Tracker: Data Takeaways & Critical Review

_Suite audit, June 2026; figures recomputed October 2026. NEON DP1.10022.001 (Ground beetles sampled from pitfall traps)._

Recomputed on 2026-10-22 from the committed bundles (precompute fingerprint ab32503a02a5e027, the first 16 hex characters of the md5 of `precompute_fingerprint()`; the committed `data/precomputed.rds` carries the same fingerprint).

## What the data actually shows

All numbers below were recomputed from the 46 bundled `data/sites/<SITE>.rds` tables and
the cached `data/precomputed.rds` with the app's current code: `clean_beetle()` merges
subspecies and subgenus names into their binomial, and a species-group call counts as a
species only when no member species was caught at that site.

- **Coverage is national and deep.** 46 NEON terrestrial sites, **67,151 catch records**
  plus **33,012 sampled plot-bout effort rows**, **237,841 individuals**, **2013 to 2023**,
  **388 site-years** (median **9 years/site**, range 4 to 11). **687 distinct species**
  network-wide; per-site richness median **48**.
- **Richness follows habitat more than latitude** (Pearson r(richness, |lat|) = **-0.13**).
  The highest observed richness is in the eastern deciduous belt and the northern plains:
  **WOOD 114**, **BLAN 95**, **NOGP 92**, **SCBI 91**, **UKFS 91** species, while the climatic
  extremes are species-poor: arctic **BARR = 7**, tropical **GUAN = 7** and **LAJA = 21**
  (Puerto Rico). These are observed counts on unequal catches, not a ranking (see the HELD
  rule in `docs/SCIENCE-CONTRACT.md`).
- **Abundance and richness diverge.** The sites with the most catch are not the richest:
  **STER** caught 25,583 individuals (**71.4 per 100 trap-nights**, the network high) at 75
  species; **SERC** 12,334 at 89 species. Catch per 100 trap-nights spans **0.1 (GUAN, 49
  individuals over 900 sampled plot-bouts) to 71.4 (STER)**, now that zero-catch plot-bouts
  stay in the denominator.
- **Four sites are led by an introduced European beetle.** `Pterostichus melanarius` is the
  #1 species at **STEI** (3,196 of 8,888 individuals), **UNDE** (1,183 of 4,708) and **WOOD**
  (1,139 of 5,711), and `Carabus nemoralis` at **TREE** (1,040 of 3,672). The app marks an
  introduced #1 species in the Overview and the "meet the beetles" cards, and Search can list
  every introduced taxon-site record.
- **Communities are dominance-skewed.** A single species often takes a large share:
  SRER's `Discoderus robustus` is **7,823 of 10,787** individuals (about 73%); GRSM's
  `Carabus goryi` 6,414 of 11,950; STER's `Cratacanthus dubius` 6,068 of 25,583. The Hill
  q1/q0 evenness read is the useful signal at most sites.
- **The QA/QC chain is mostly clean, but uneven.** Network-wide, **97.4% of individuals are
  resolved to species**; **2.6% (6,188 individuals)** stay at a coarser rank (genus 2,781,
  family 2,080, subgenus 1,151, demoted species-group calls 161, other 15) and are
  **excluded from richness, diversity and ordination**. The coarse-ID load is highest at
  **GUAN 40.8%** (of only 49 individuals), **LAJA 33.2%** and **ONAQ 26.2%**. **BARR** is now
  well resolved at **2.7%** (it was 45% in the June audit). TEAK sits at **0.2%**.
- **Seasonal activity mostly peaks in June or July** (28 of 46 sites), and later (August to
  November) at 13 sites: monsoon deserts (SRER, JORN), subtropical and tropical sites (DSNY,
  OSBS, LAJA) and several others (ABBY, CLBJ, HARV, KONA, OAES, ONAQ, UNDE, WOOD).
- **Effort data is complete.** All 46 bundles carry explicit effort rows (33,012 sampled
  plot-bouts, none with missing trap-nights), so the raw-count fallback
  (`metric_kind == "count"`) never fires on the real bundles and every site uses
  catch per 100 trap-nights with zero-catch bouts kept.

## How it's built

`scripts/refresh_data.R` pulls DP1.10022.001 per site → `assemble_beetles()` in `R/helpers.R`
(carabid rows from `bet_sorting` where `sampleType == "carabid"`; **expert-taxonomist override**
of the parataxonomist call via `bet_expertTaxonomistIDProcessed`; trap-night effort per
plot x bout from `bet_fielddata`, kept as explicit effort rows so zero-catch bouts count) to one
tidy long `.rds` per site with columns including `siteID, plotID, collectDate, taxonID,
scientificName, taxonRank, individualCount, trapnights, record_type`.

`scripts/precompute.R` sources `global.R` and runs `build_national_index()` once, caching the
site index, **Bray-Curtis PCoA ordination** (`bray_ordination`, site x year unit, 379 points),
**IndVal indicators** (`indicator_species`, 501 rows), and the species x site range table to
`data/precomputed.rds` (25 KB, content-fingerprinted so a stale cache auto-invalidates).

The app (`server.R`) renders Overview (community bar + naive occupancy + phenology heatmap +
rank-abundance), Diversity (Hill q0/q1/q2, Hurlbert rarefaction, bout accumulation), Seasonality
(monthly cpn + co-located NEON env overlays with a deseasonalized driver×lag scan), Trends
(annual cpn OLS with a small-n-aware verdict), and Biogeography (richness/range map, PCoA,
IndVal table). **Metric definition:** abundance = **catch per 100 trap-nights**
(`effort = Σ unique(plotID, collectDate) trapnights`) — an **activity-density index, not true
density**. Richness-type metrics use `species_level == TRUE` only; abundance counts every beetle.

## Critical findings by lens

### NEONize (suite cohesion / parity)
- **[resolved] Non-native dominants.** STEI/UNDE/WOOD/TREE lead with introduced European
  species; the app now marks an introduced #1 species in the Overview and the species cards.
- **[resolved] Near-empty env layers.** `fruiting_pct` is still near-empty, but the dredge and
  the overlay picker share a 24-month coverage floor (`env_has_min_coverage`), so it never
  ranks on a handful of points. Rainfall (`precip_mm`) is missing at 27 of 46 sites in the
  bundled environment data, and the app says so on the env source note.
- **[good] Parity is otherwise strong:** map-picker front door, codebook+README zip export,
  PDF report, permutation null, content-fingerprinted precompute cache — all on par with the suite.

### Ecological (carabid pitfall domain)
- **[high] "Abundance" is activity-density, surfaced honestly but easy to misread.** Pitfall catch
  conflates true density with movement/activity — a fast-running `Pasimachus` or `Cicindela` is
  over-represented vs a sedentary species. The app says "catch per 100 trap-nights" everywhere
  (good) but the verdict banners ("most abundant: X — 69%") still read as abundance. *Fix:* one
  sentence in the Overview info-pop: "pitfall catch ∝ activity × density, so active surface
  hunters score high."
- **[resolved] Detection-frequency denominator.** `occupancy_table` now divides by every
  sampled plot-bout from the effort rows, including bouts with no carabid catch. It is still a
  naive detection frequency, not detection-corrected occupancy.
- **[med] Species-poor sites lean on the thinnest ID base.** GUAN (40.8% of 49 individuals)
  and LAJA (33.2%) leave a large share at a coarser rank before richness is computed.
  *Fix:* show the species-level **individual count** (not just the % excluded) next to
  richness at these sites so users see the small base.

### Data science (Quinn — analysis-readiness)
- **[not reproduced] Bundle portability.** The June audit saw a fresh `readRDS()` crash on
  ALTREP string columns. On the current bundles a vanilla `Rscript` reads every site, `nrow()`
  and `names()` work, and `collectDate` is a `Date`.
- **[good] The CSV export is genuinely FAIR:** zip of tidy data + column codebook
  (`beetle_export_codebook`) + provenance README, with a runtime drift-guard asserting codebook
  columns == data columns. This is the suite's best download.

### Statistics (small-n honesty / null validity)
- **[high, and a headline] The environmental driver to activity link does not survive its own
  permutation null at any of the 46 sites.** Best-of-dredge correlations look sizeable
  (|r| 0.22 to 0.91; SRER green-up r = -0.50 at 12 months, HARV green-up r = -0.61 at 4 months,
  STER air temperature r = +0.22 at 8 months) but the rotation-null permutation p-values run
  **0.06 to 1.00**; none beats chance over the 13 to 65 driver x lag candidates. The app **correctly** gates the loud verdict word on this p (demotes to
  "Apparent"). *Keep this machinery; do not "fix" the stats — the inputs are weak, as expected for
  consumers in this cascade.*
- **[med] Trend p-values are suppressed below 6 years (SOAP, TEAK, YELL); 43/46 sites are
  trend-testable.** A trend reads "statistically clear" only when it also holds without the
  2023 value and on the season-standardised series with partial-season years and 2023 left
  out together; a check with fewer than 6 comparable years reads "cannot be confirmed". On
  the current bundles (2026-10-26) that leaves 2 clear declines (BLAN, DELA), 1 clear rise
  (OSBS), 8 apparent changes (ABBY, BARR, DEJU, DSNY, HEAL, JORN, MLBS, UNDE), 3 sites with
  too few years (SOAP, TEAK, YELL) and 32 flat. A 6 to 11 year OLS on annual cpn is still a
  low-power, autocorrelated series.
- **[med] PCoA axes explain only 7% / 5% of variance.** The ordination is legible but the first two
  axes carry little structure; biome clustering is weak in 2-D. *Fix:* print the var-explained on the
  plot (already computed in `attr(o,"var_explained")`) and add one line that low % = high
  community turnover, not a failed ordination.

## Honest-stats & caveats — what this app must NOT be read to claim

- **Not "beetles are declining/booming here."** A 6 to 11 year, autocorrelated annual series is
  underpowered; the verdict is direction and a p-value, never a population trajectory.
- **Not "this driver controls beetle activity."** Every site's best env correlation fails its
  permutation null (p >= 0.06 at all 46 sites). The Seasonality "tracking" panel is a hypothesis-generator, not
  evidence of an environmental control on carabid activity.
- **Not "true abundance/density."** Every count is **activity-density** (pitfall catch) — biased
  toward active, large, surface-active species. Comparisons across very different body plans
  (tiger beetles vs litter specialists) are not density comparisons.
- **Not "intact native richness" at STEI/UNDE/WOOD/TREE** — those communities are
  numerically dominated by introduced European carabids.
- **Richness at GUAN and LAJA rests on a small identified base** (about 41% and 33% of
  individuals never reach species); treat those counts as lower-confidence.

## Place in the cascade

This is the **consumer rung** of the climate → plants → consumers throughline, and it behaves
exactly as the suite's hard-won truths predict:

- The carabid env-tracking signal is **statistically weak**: best |r| 0.22 to 0.91 yet
  permutation p >= 0.06 at all 46 sites. Ground beetles cannot carry a confirmed sub-annual
  cascade link; like birds, they are **descriptive corroboration**, not a load-bearing rung.
- The app already does the right consumer-rung move the cascade memory calls for: it **pools the
  cross-site structure** (PCoA, IndVal across 46 sites / 379 site x year communities) rather than
  resting on per-site verdicts that n=4–11 site-years can't support.
- Where it can **strengthen the cascade**, the inputs (not the stats) are the lever, mirroring the
  desert-seasonal-split insight: the beetle response is monthly cpn, the env drivers are monthly
  precip/temp/greenup co-located bundles. The app now has that **winter/monsoon/spring seasonal
  split** (the seasonal climate card). It now correlates only comparable years (partial
  seasons and 2023 left out), and at SRER only 3 such years have the seasonal climate inputs,
  so the card reads "too few years to read a link". Rainfall is also
  missing from the bundled environment data at 27 of 46 sites, including JORN.
- **For the integrator (Driver Cascade):** feed this app's *pooled, species-level* activity-density
  and the per-site green-up overlay, NOT the per-site env correlations (they don't survive the null).
  The one robust suite link — **temperature → green-up onset** — sits upstream of this rung; beetles
  corroborate the plant signal's timing (June–July activity peak tracking warm-season green-up)
  without adding an independent confirmed climate→consumer coupling.
