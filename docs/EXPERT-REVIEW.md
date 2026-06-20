# Ground beetles (carabid pitfall trapping) — Expert Review by Cara (NEON DP1.10022.001)
_Devoted product-expert review — June 2026._

> I walked the Ground Beetle Tracker end to end — `global.R`, `R/helpers.R`, `scripts/precompute.R`, `scripts/refresh_data.R`, `server.R`, `ui.R`, and the verified facts in `docs/DATA-TAKEAWAYS.md` — and the headline is: **this is the most scientifically honest carabid app I've reviewed, and it should ship close to as-is.** It does the one thing every pitfall app must do — effort-normalises to catch per 100 trap-nights everywhere, absorbing NEON's 4→3 trap and 10→6 plot protocol changes — and it does the one thing most carabid dashboards *fail* to do: it gates richness on NEON's authoritative `taxonRank` so 9,543 genus/family-stranded individuals can't inflate the species count, and it demotes a loud env-driver verdict to "Apparent" when the rotation-null permutation p ≥ 0.05. The stats are correct; **do not "fix" them.** What's left is honesty polish, not surgery: the activity-density caveat needs to sit where the abundance claim lives, four sites are numerically dominated by *introduced European beetles* and the app never says so, an empty fruiting driver is still in the env dredge, and the build script still ships a non-portable bundle. Five concrete fixes below, each shipped with its patch. — Cara

## Method fidelity (is the NEON protocol represented correctly?)

Strong, and faithfully labelled. The product is named and linked correctly (`DP1.10022.001`, README:5, ui.R:146), the design paper is cited in the right places (Hoekman et al. 2017 *Ecosphere* 8(4):e01744 — README:71, server.R:629), and the sampling mechanics are represented exactly as NEON runs them:

- **The carabid-vs-bycatch filter is present and correct.** `assemble_beetles()` keeps only `sampleType == "carabid"` rows from `bet_sorting` (`R/helpers.R:419–420`). This is the single most important filter in the whole pipeline — pitfalls catch everything that walks — and it is applied first, before anything else. Right.
- **Expert-ID reconciliation is real.** The parataxonomist call from `bet_parataxonomistID` is overwritten by the authoritative `bet_expertTaxonomistIDProcessed` call where one exists, keyed on `taxonID`, carrying the expert's `taxonRank` (`R/helpers.R:430–442`). That override is exactly what makes the rank trustworthy enough to gate richness on.
- **Effort is trap-nights, summed correctly.** `effort_trapnights()` sums over **unique (plotID, collectDate)** trap-nights (`R/helpers.R:130–134`), deliberately *not* multiplied by the number of species sharing a sample — the classic effort double-count, avoided. Effort comes from `bet_fielddata$daysOfTrapping` summed over traps actually set (`R/helpers.R:451–462`), so trap loss and the protocol-era trap/plot changes land in the denominator, not in a fake decline. `DATA-TAKEAWAYS.md` confirms the trapnights NA-rate is **0% at every bundled site**, so the raw-count fallback (`metric_kind == "count"`) never fires — every site is true catch-per-100-trap-nights.

One method-labelling gap, not an error: the README and About describe the trap as a "pitfall" but never name the **propylene-glycol preservative** or the cup-flush-to-soil design — and `Work et al. (2002)` showed trap design (cup diameter, preservative, ramp) itself shifts catch composition. That's a one-line About addition, not a correctness problem.

## Analysis & metrics — defensible? (with the literature)

Every estimator is the textbook-correct one for carabids, implemented in base R, and labelled honestly. I'd sign off each of these to a journal reviewer:

- **Activity-density index** = catch / trap-night (`community_table`, `R/helpers.R:86–107`). Pitfalls sample *encounters*, not area, so the catch is a movement × density product (Lövei & Sunderland 1996; Thiele 1977; Greenslade 1964). The app labels it "catch per 100 trap-nights" *everywhere* — exactly the honest framing.
- **Hill numbers** q0/q1/q2 (Hill 1973; Jost 2006) at `R/helpers.R:140–150`, with the q1/q0 evenness story foregrounded — the right call for carabids, which are routinely dominance-skewed (SRER's *Discoderus robustus* ≈69% of catch; `DATA-TAKEAWAYS.md`).
- **Hurlbert (1971) individual-based rarefaction** with the **Heck et al. (1975)** analytic SD (`rarefaction_curve`, `R/helpers.R:156–175`) — the only honest way to compare a STER (24,765 individuals) against a sparse GUAN.
- **Gotelli & Colwell (2001) sample-based accumulation** over random bout orders (`R/helpers.R:181–203`), x-axis correctly labelled "trapping bouts," not calendar time.
- **Bray–Curtis → PCoA** on site×year communities (`bray_ordination`, `R/helpers.R:477–509`) and **Dufrêne–Legendre (1997) IndVal** (`indicator_species`, `R/helpers.R:527–560`) — the canonical carabid-biogeography pair, in base R, no `vegan`. The aggregation to site×year (≈380 samples) is a defensible legibility/speed choice.

**The headline I most want preserved:** the env-driver→activity link does **not** survive its own permutation null at any tested site. Best-of-dredge correlations look sizeable (SRER precip r=+0.45 @9mo, HARV greenup r=−0.52 @4mo, STER greenup r=−0.53 @10mo) but the rotation-null p-values are **0.29–0.90** over the ~39–65 driver×lag candidates (`env_corr_pvalue`, `R/helpers.R:713–783`). The app *correctly* gates the loud verdict word on this p, demoting "Strong" to "Apparent" when p ≥ 0.05 (`server.R:862–868`). The rotation null is the right null — it preserves each driver's autocorrelation, its deseasonalized structure, and the drivers' shared collinearity, destroying only the true temporal alignment. **This machinery is valid. Redirect effort upstream to the inputs; do not touch the stats.** The Seasonality panel is a hypothesis-*generator*, never evidence of environmental control on carabid activity — and the UI copy says so (ui.R:185).

## What the field would add (collection / analysis / presentation / use)

1. **Name the invader (presentation + use).** Four sites are *numerically dominated by introduced European carabids* — *Pterostichus melanarius* #1 at **STEI/UNDE/WOOD**, *Carabus nemoralis* at **TREE**; at WOOD the invader alone is 979 of 5,156 individuals (`DATA-TAKEAWAYS.md`). The Overview verdict (`server.R:493–504`) and "meet the beetles" cards (`server.R:530–546`) call these "most abundant" / "dominant" with zero flag. To a carabidologist, "dominant European beetle" is the opposite of "intact native fauna" — this is a real ecological caveat, not a footnote. *Fix:* add a one-genus/species `introduced` lookup keyed in `beetle_blurb` (`R/helpers.R:347`) and badge the Overview verdict — "introduced European species" — so "dominant" is read correctly.

2. **Surface the activity-density caveat where the claim lives (presentation).** The Overview community info-pop (ui.R:124–127) explains effort-normalisation but never says the catch is *activity*. *Fix:* one sentence in that `info_pop`: "Pitfall catch ∝ activity × density, so fast, large, surface-active hunters (tiger beetles, *Pasimachus*) score high regardless of true abundance — compare like body plans." Right now that paradigm caveat lives only in my head and the takeaways doc, not in front of the user reading "most abundant: X — 69%."

3. **A seasonal split of the desert sites (analysis — the "one move").** Mirroring the suite's desert-plant insight: annual aggregation at warm-desert sites (SRER, JORN, ONAQ) blends ENSO-anticorrelated winter/monsoon seasons. The beetle response is already monthly cpn and the env drivers are already monthly co-located bundles — a **winter/monsoon seasonal split** is the analogous input-side lever, buildable from existing overlays. This strengthens the *inputs*, not the stats.

4. **Show the species-level individual count at sparse sites (presentation).** TEAK (45.0%), BARR (42.4%), GUAN (40.8%) leave 40–45% of individuals stranded at genus/family before richness is computed (`DATA-TAKEAWAYS.md`). The QA note (`server.R:622–632`) shows the *% excluded* but not the *identified base size*. *Fix:* print the species-level individual count next to richness at these sites so a 9-species arctic count reads as the thin-base floor it is.

5. **Veg-structure as a slow driver (collection/use, suite-level).** Carabid richness is composition, not productivity, and the env dredge leans on phenology %s. The field would add a slow ~5-yr habitat-structure covariate (basal area / litter depth) as a *state* floor rather than asking phenology anomalies to carry an annual link they can't.

## Product-specific honesty & QC traps

- **[HANDLED] The species-gate is rank-aware and consistent.** `resolved_to_species()` prefers NEON's `taxonRank ∈ {species, subspecies, speciesGroup}` and only falls back to the binomial name heuristic when rank is absent (`R/helpers.R:45–51`). Every richness-type metric (richness, Hill, rarefaction, accumulation, ordination, IndVal) uses `species_level == TRUE` only; total abundance counts every beetle. The per-row flag is computed once in `clean_beetle` and reused, so Overview, Diversity, the QA note, ordination and indicators can't disagree (`R/helpers.R:102–104` is the explicit fix for exactly that drift). This is the trap most carabid apps fall into, and it's closed.

- **[HANDLED — keep the caveat] The occupancy denominator is censored.** `occupancy_table` divides by carabid-*positive* plot×bouts because `clean_beetle` drops zero-catch bouts, so occurrence is structurally over-stated (`R/helpers.R:259–280`). This is a documented ceiling, not a bug, and the UI carries a clear "naive + denominator" caveat (ui.R:132–133). Keep "naive" on the label; never read it as range.

- **[OPEN — HIGH] The shipped bundle is still not portable.** `DATA-TAKEAWAYS.md` flags that the `.rds` files carry ALTREP deferred-string columns that segfault a cold `readRDS()` + bulk access, and `collectDate` is a classless numeric day-count. The materialization loop in `refresh_data.R:55–58` does **not** fully fix this: it uses the exact `col[seq_along(col)]` idiom the doc says is insufficient for ALTREP deferred strings, and its `inherits(col, "Date")` branch **never fires on `collectDate`** — `assemble_beetles()` never sets a Date class, so `collectDate` falls through and is saved as a classless day-count, exactly as described. The app survives only because `clean_beetle` runs in a warm session; a downstream `readRDS()` user hits a 139. *Fix:* in that loop, force `as.character()` on string columns (not element-indexing) and explicitly coerce `collectDate` to `Date` before `saveRDS(..., version = 2)`. This is a 4-line change in one file.

- **[OPEN — LOW] An empty driver is still in the dredge.** `fruit` (`fruiting_pct`) ships in the default `ENV_LAYERS` (`global.R:102`), inherited verbatim from the mammal app, but is near-empty (15 non-NA months at SRER). `env_layer_choices` and `env_corr_all` both gate on `any(!is.na(...))` so a *fully* empty column is dropped — but a 15-point column is NOT empty; it can still win the best-of-dredge on noise. *Fix:* drop `fruit` from the beetle default, or gate drivers on a non-NA-month floor (e.g. ≥ 24) in `env_corr_all` (`R/helpers.R:684–697`) so nothing ranks on 15 points.

- **[HANDLED] Trends are honest about small-n.** Sub-5-year series get "read the direction, not the decimal" with the p-value suppressed (`server.R:752–759`); ≥5-year series report direction + an honest p, never a population trajectory. This is *not* an insect-decline verdict, and the copy never claims it is. Good. (The README still calls the Trends tab "the insect-decline view," README:31/46 — I'd soften that one line to "the insect-trend view" so the framing matches the honest verdict the code actually renders.)

- **[HANDLED] Taxonomy is treated as provisional.** Gating on `taxonRank`, the expert override, and the network richness total quoted from a recompute (not hard-coded) all respect that NEON revises IDs across releases.

## Place in the suite / cascade

This is the **consumer rung** of the climate → plants → consumers throughline, and it behaves exactly as the suite's hard-won truths predict. The carabid env-tracking signal is real but statistically weak (best |r| ≈ 0.45–0.53, permutation p ≥ 0.29 everywhere), so ground beetles **cannot carry a confirmed sub-annual cascade link** — like the breeding birds, they are **descriptive corroboration**, not a load-bearing rung. The app already does the right consumer-rung move: it **pools the cross-site structure** (PCoA + IndVal across 46 sites / 372–521 site×year communities) instead of resting on per-site verdicts that n=4–11 site-years can't support.

For the integrator (Cass / Driver Cascade): feed this app's **pooled, species-level activity-density and the per-site green-up overlay — NOT the per-site env correlations** (they don't survive the null). The one robust suite link — temperature → green-up onset — sits *upstream* of this rung; beetles corroborate the plant signal's timing (the clean June–July activity peak, 27 of 46 sites) tracking warm-season green-up, without adding an independent confirmed climate→consumer coupling. I'm the one who keeps that boundary honest: this rung is corroboration, not confirmation.

## Scorecard

| Dimension | Grade | Why |
| --- | --- | --- |
| Method fidelity (DP1.10022.001) | **A** | Carabid filter, expert-ID override, trap-night effort, protocol-change absorption all correct and labelled; only the trap-preservative description is missing. |
| Metric defensibility | **A** | Hill / Hurlbert+Heck / Gotelli-Colwell / Bray-Curtis / IndVal all canonical and honestly labelled; activity-density framing kept throughout. |
| Statistical honesty | **A** | Rotation-null permutation gate, "Apparent" demotion, small-n trend suppression, species-only richness — exemplary; do not touch. |
| Pitfall-bias surfacing | **B** | Effort-normalised everywhere, but the activity-density caveat isn't yet where the "most abundant" claim lives. |
| Ecological caveats | **B−** | Invader dominance at STEI/UNDE/WOOD/TREE is unflagged; sparse-site identified-base size is hidden. |
| Env-overlay hygiene | **B** | Deseasonalized + null-gated correctly; but `fruit` (15 points) can still rank on noise. |
| Data portability / QC build | **C+** | Bundle still ships non-materialized ALTREP strings + a classless `collectDate`; `refresh_data.R:55–58` does not actually fix the documented `readRDS()` segfault. |
| Suite / cascade fit | **A** | Pools cross-site structure, keeps beetles as descriptive corroboration, hands the right artifact to the integrator. |
| Exports / FAIR-ness | **A** | Zip of tidy data + column codebook + provenance README, with a runtime drift-guard — the suite's best download. |

— Cara
