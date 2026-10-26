#!/usr/bin/env Rscript

suppressMessages({
  library(dplyr)
  library(tibble)
})
source("R/helpers.R")

assert <- function(ok, msg) {
  if (!isTRUE(ok)) stop(msg, call. = FALSE)
}
expect_error <- function(expr, pattern) {
  msg <- tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
  assert(!is.na(msg) && grepl(pattern, msg), paste("expected error matching", shQuote(pattern)))
}

# Two valid sampled plot-bouts (four traps, 20 trap-nights), one of which caught
# no Carabidae. P3 has a catch row but no collected field opportunity and must not
# enter any effort-normalized numerator. The first trap row is duplicated exactly
# to prove physical effort is deduplicated rather than multiplied.
field <- data.frame(
  siteID = rep("TEST", 6),
  plotID = c("P1", "P1", "P1", "P2", "P2", "P3"),
  trapID = c("A", "A", "B", "A", "B", "A"),
  sampleID = c("S1", "S1", "S2", "S3", "S4", "S5"),
  collectDate = as.Date(rep("2024-06-10", 6)),
  sampleCollected = c("Y", "Y", "Y", "Y", "Y", "N"),
  trappingDays = c(5, 5, 5, 5, 5, 5),
  stringsAsFactors = FALSE
)
sorting <- data.frame(
  siteID = c("TEST", "TEST", "TEST"),
  plotID = c("P1", "P1", "P3"),
  sampleID = c("S1", "S2", "S5"),
  subsampleID = c("SS1", "SS2", "SS3"),
  collectDate = as.Date(rep("2024-06-10", 3)),
  sampleType = c("carabid", "common carabid", "other carabid"),
  taxonID = c("T1", "T2", "T3"),
  scientificName = c("Pterostichus sp.", "Carabus nemoralis", "Amara sp."),
  taxonRank = c("genus", "species", "genus"),
  individualCount = c(3, 2, 4),
  stringsAsFactors = FALSE
)
expert <- data.frame(
  individualID = "I1",
  taxonID = "T1E",
  scientificName = "Pterostichus melanarius",
  taxonRank = "species",
  stringsAsFactors = FALSE
)
para <- data.frame(
  subsampleID = "SS1",
  individualID = "I1",
  taxonID = "T1P",
  scientificName = "Pterostichus mutus",
  taxonRank = "species",
  stringsAsFactors = FALSE
)
raw <- list(
  bet_fielddata = field,
  bet_sorting = sorting,
  bet_parataxonomistID = para,
  bet_expertTaxonomistIDProcessed = expert
)

assembled <- assemble_beetles(raw)
d <- clean_beetle(assembled)
assert(nrow(beetle_effort_rows(d)) == 2L, "zero-carabid P2 must remain an effort opportunity")
assert(effort_opportunity_complete(d), "new bundle must advertise explicit effort anchors")
assert(identical(as.numeric(effort_trapnights(d)), 20), "duplicate trap row must not inflate 20 trap-nights")
assert(all(beetle_effort_rows(d)$traps_sampled == 2L), "each valid plot-bout must contain two distinct traps")
assert(any(d$scientificName == "Pterostichus melanarius", na.rm = TRUE), "expert name must override provisional name")
assert(sum(beetle_catches(d)$individualCount) == sum(sorting$individualCount),
       "individual-level taxonomy reconciliation must conserve sorting totals")
expert_count <- d$individualCount[d$record_type == "catch" &
                                  d$scientificName %in% "Pterostichus melanarius"]
residual_count <- d$individualCount[d$record_type == "catch" &
                                    d$scientificName %in% "Pterostichus sp."]
assert(length(expert_count) == 1L && expert_count == 1,
       "one expert specimen must not relabel the entire sorting count")
assert(length(residual_count) == 1L && residual_count == 2,
       "unpinned residual count must retain sorting-level taxonomy")
assert(any(d$record_type == "catch" & d$plotID == "P3" & d$effort_status == "missing"),
       "catch with no collected opportunity must remain visible but effort-ineligible")

ct <- community_table(d)
assert(ct$individuals[ct$scientificName == "Pterostichus melanarius"] == 1,
       "expert-reconciled individual must remain visible")
assert(ct$cpn[ct$scientificName == "Pterostichus melanarius"] == 5,
       "activity-density must use all 20 trap-nights")
assert(ct$cpn[ct$scientificName == "Pterostichus sp."] == 10,
       "unpinned sorting-level individuals retain an honest coarse-ID rate")
assert(ct$cpn[ct$scientificName == "Carabus nemoralis"] == 10,
       "legacy common-carabid sampleType must be retained")
assert(is.na(ct$cpn[ct$scientificName == "Amara sp."]),
       "catch without matched effort must not receive a fabricated rate")

seas <- seasonality(d)
assert(nrow(seas) == 1L && abs(seas$cpn - 25) < 1e-10,
       "pooled activity must be 5 eligible individuals / 20 trap-nights x 100")
occ <- occupancy_table(d, min_samples = 1)
assert(attr(occ, "opportunity_complete"), "detection denominator must be opportunity-complete")
assert(attr(occ, "n_samp") == 2L, "detection denominator must include zero-carabid P2")
assert(all(occ$occ == 50), "each eligible species occurred in one of two sampled plot-bouts")

qc <- beetle_qc(d)
assert("noeffort" %in% names(qc$sets), "unmatched positive catch must remain in QC")

# Historical `other carabid` rows kept fine-scale enumerated individuals in the
# parataxonomist table, including records with a blank placeholder sorting count.
raw_historical <- raw
raw_historical$bet_sorting <- sorting[1, , drop = FALSE]
raw_historical$bet_sorting$sampleType <- "other carabid"
raw_historical$bet_sorting$individualCount <- NA
raw_historical$bet_parataxonomistID <- rbind(
  para,
  transform(para, individualID = "I2", taxonID = "T2P",
            scientificName = "Pterostichus adstrictus")
)
raw_historical$bet_expertTaxonomistIDProcessed <- NULL
historical <- resolve_beetle_catches(raw_historical)
assert(sum(historical$individualCount) == 2,
       "enumerated historical other-carabid individuals must supply the legacy count")

# Modern sorting totals remain authoritative if child pin rows conflict.
raw_overflow <- raw_historical
raw_overflow$bet_sorting$sampleType <- "carabid"
raw_overflow$bet_sorting$individualCount <- 1
modern <- resolve_beetle_catches(raw_overflow)
assert(nrow(modern) == 1L && modern$scientificName == "Pterostichus sp." &&
         modern$individualCount == 1,
       "modern pin/count conflicts must fall back to the authoritative sorting row")

# Conflicting expert rows are ambiguous; retain the para determination instead
# of allowing either expert row to relabel the specimen.
raw_ambiguous_expert <- raw
raw_ambiguous_expert$bet_expertTaxonomistIDProcessed <- rbind(
  expert,
  transform(expert, taxonID = "T1X", scientificName = "Pterostichus adstrictus")
)
ambiguous <- resolve_beetle_catches(raw_ambiguous_expert)
assert(any(ambiguous$scientificName == "Pterostichus mutus"),
       "ambiguous duplicate expert determinations must fall back to para taxonomy")
assert(!any(ambiguous$scientificName %in% c("Pterostichus melanarius", "Pterostichus adstrictus")),
       "ambiguous expert determinations must not override the specimen")

raw_zero <- raw
raw_zero$bet_sorting <- sorting[0, , drop = FALSE]
raw_zero$bet_expertTaxonomistIDProcessed <- NULL
zero_d <- clean_beetle(assemble_beetles(raw_zero))
assert(nrow(zero_d) == 2L && all(zero_d$record_type == "effort"),
       "an all-zero-carabid site still has sampled effort opportunities")
assert(is.null(community_table(zero_d)), "effort anchors must never become taxa")
assert(effort_trapnights(zero_d) == 20, "all-zero site must retain its denominator")

raw_conflict <- raw
raw_conflict$bet_fielddata$trappingDays[2] <- 6
expect_error(build_beetle_effort(raw_conflict), "conflicting effort")

legacy <- clean_beetle(data.frame(
  siteID = "TEST", plotID = "P1", collectDate = as.Date("2024-06-10"),
  taxonID = "T1", scientificName = "Carabus nemoralis", taxonRank = "species",
  individualCount = 2, trapnights = 5, stringsAsFactors = FALSE
))
assert(!effort_opportunity_complete(legacy), "legacy catch-only bundle must remain explicitly incomplete")
assert(effort_trapnights(legacy) == 5, "legacy display fallback remains readable during migration")

# Species key merge (audit item 15, 2026-10-21): subspecies and subgenus variants
# collapse to one binomial, and a species-group call with a member present at the
# site is demoted out of richness but kept in abundance.
assert(species_binomial("Pterostichus (Morphnosoma) melanarius melanarius") ==
         "Pterostichus melanarius", "subgenus and subspecies must collapse to the binomial")
merge_names <- c("Pterostichus melanarius",
                 "Pterostichus (Morphnosoma) melanarius melanarius",
                 "Harpalus pensylvanicus", "Harpalus pensylvanicus/texanus",
                 "Amara aenea/cupreolata", "Bembidion sp.")
merge_ranks <- c("species", "subspecies", "species", "speciesGroup", "speciesGroup", "genus")
merge_counts <- c(4, 3, 5, 2, 1, 6)
merge_fx <- data.frame(
  siteID = "TEST", plotID = "P1", collectDate = as.Date("2024-06-10"),
  taxonID = paste0("T", seq_along(merge_names)), scientificName = merge_names,
  taxonRank = merge_ranks, individualCount = merge_counts, trapnights = 10,
  record_type = "catch", traps_sampled = 3L, effort_records = 3L,
  effort_status = "valid_sample_collected", stringsAsFactors = FALSE)
merge_fx <- rbind(merge_fx, data.frame(
  siteID = "TEST", plotID = "P1", collectDate = as.Date("2024-06-10"),
  taxonID = NA, scientificName = NA, taxonRank = NA, individualCount = 0,
  trapnights = 10, record_type = "effort", traps_sampled = 3L, effort_records = 3L,
  effort_status = "valid_sample_collected", stringsAsFactors = FALSE))
merged <- clean_beetle(merge_fx)
merged_catch <- merged[merged$record_type == "catch", , drop = FALSE]
assert(identical(merged_catch$scientificName_verbatim, merge_names),
       "scientificName_verbatim must preserve every published name")
assert(identical(merged_catch$taxonID, paste0("T", seq_along(merge_names))),
       "taxonID must not change in the species merge")
merged_ct <- community_table(merged)
assert(sum(merged_ct$species_level %in% TRUE) == 3L,
       "species richness must count P. melanarius, H. pensylvanicus and the Amara group once each")
assert(setequal(merged_ct$scientificName[merged_ct$species_level %in% TRUE],
                c("Pterostichus melanarius", "Harpalus pensylvanicus", "Amara aenea/cupreolata")),
       "species-level set must be the merged binomials plus the member-free group")
assert(sum(merged_ct$individuals) == sum(merge_counts),
       "total abundance must be unchanged by the species merge")
assert(merged_ct$individuals[merged_ct$scientificName == "Pterostichus melanarius"] == 7,
       "subspecies catch must merge into its species")
harp_grp <- merged_catch$scientificName == "Harpalus pensylvanicus/texanus"
assert(any(harp_grp) && all(!merged_catch$species_level[harp_grp]),
       "a species group with a member present must be demoted from species level")
assert(merged_ct$individuals[merged_ct$scientificName == "Harpalus pensylvanicus/texanus"] == 2,
       "a demoted species group must still count toward abundance")
assert(taxon_qa(merged)$species == 3L, "taxon QA must agree with the merged species count")
assert(identical(species_group_members("Amara cupreolata group"), "Amara cupreolata"),
       "a 'Genus epithet group' call must resolve to its named member")
assert(setequal(species_group_members("Harpalus paratus/pensylvanicus"),
                c("Harpalus paratus", "Harpalus pensylvanicus")),
       "slash species groups must expand every member epithet")

# 2023 design break: a trend is "statistically clear" only if it survives
# dropping the 2023 value (NEON cut plots from 10 to 6 per site that year).
# Minimal legacy-shape annual series: one plot-bout per year, 100 trap-nights,
# so catch per 100 trap-nights equals the count.
trend_fixture <- function(years, counts) {
  data.frame(siteID = "TEST", plotID = "P1",
             collectDate = as.Date(sprintf("%d-07-01", years)),
             trapnights = 100, individualCount = counts,
             scientificName = "Carabus nemoralis", stringsAsFactors = FALSE)
}
yrs_23 <- 2015:2023
noise <- c(1.2, -0.8, 0.6, -1.4, 1.0, -0.4, 0.8, -1.0, 0)
# 2015-2022: a faint drift that is not significant on its own (p ~ 0.12); the
# 2023 value 5 below 2022 tips the all-years fit to p ~ 0.03.
rest_vals <- 50 - 0.2 * (0:7) + noise[1:8]
rest_vals <- c(rest_vals, rest_vals[8] - 5)
t_rest <- annual_trend(trend_fixture(yrs_23, rest_vals))
tc_rest <- trend_call(t_rest)
assert(identical(tc_rest$kind, "fit") && tc_rest$has2023, "2023 series must be a fitted call with has2023")
assert(tc_rest$sig_all, "fixture: the all-years slope must be significant because of 2023")
assert(identical(tc_rest$n_ex2023, 8L), "n_ex2023 must count the years without 2023")
assert(isFALSE(tc_rest$clear) && isTRUE(tc_rest$rests_on_2023),
       "a slope that is significant only because of 2023 must rest on 2023, not be clear")
assert(isTRUE(all.equal(t_rest$metric, rest_vals)) && is.finite(attr(t_rest, "p_ex2023")) &&
         attr(t_rest, "p_ex2023") >= 0.05,
       "the 2023 refit must not change the plotted series")
t_steady <- annual_trend(trend_fixture(yrs_23, 100 - 8 * (yrs_23 - 2015) + noise))
tc_steady <- trend_call(t_steady)
assert(isTRUE(tc_steady$clear) && isFALSE(tc_steady$rests_on_2023) && tc_steady$slope < 0,
       "a steady decline through 2023 must stay statistically clear")
yrs_old <- 2012:2020
t_old <- annual_trend(trend_fixture(yrs_old, 100 - 8 * (yrs_old - 2012) + noise))
tc_old <- trend_call(t_old)
assert(!tc_old$has2023 && is.null(attr(t_old, "p_ex2023")),
       "a series without 2023 must not get ex-2023 attrs")
assert(identical(tc_old$clear, tc_old$sig_all) && isTRUE(tc_old$clear),
       "without 2023 the call must equal the all-years significance")
t_flat_old <- annual_trend(trend_fixture(yrs_old, 50 + noise))
assert(isFALSE(trend_call(t_flat_old)$clear), "a flat series without 2023 must not be clear")
assert(identical(trend_call(annual_trend(trend_fixture(2019:2022, c(5, 8, 9, 12))))$kind, "few"),
       "under six years must stay the 'few' call")
assert(identical(trend_call(annual_trend(trend_fixture(2016:2020, 100 - 10 * (0:4))))$kind, "few"),
       "five years is below the suite gate of six and must be the 'few' call")

# Partial seasons: a year that sampled only part of the core season is flagged
# `partial`, keeps its plotted value, and is left out of the season check.
season_fixture <- function(rows) {
  data.frame(siteID = "TEST", plotID = "P1",
             collectDate = as.Date(sprintf("%d-%02d-15", rows$year, rows$mon)),
             trapnights = 100, individualCount = rows$count,
             scientificName = "Carabus nemoralis", stringsAsFactors = FALSE)
}
full_mon <- data.frame(mon = 5:8, base = c(20, 80, 80, 20))
season_rows <- do.call(rbind, lapply(2012:2019, function(y)
  data.frame(year = y, mon = full_mon$mon, count = full_mon$base + c(1, -1, 2, -2) * ((y %% 3) - 1))))
season_rows <- rbind(season_rows, data.frame(year = 2020, mon = c(6, 7), count = c(80, 80)))
t_part <- annual_trend(season_fixture(season_rows))
assert(identical(attr(t_part, "years_partial"), 2020L) && isTRUE(t_part$partial[t_part$year == 2020]) &&
         all(t_part$partial[t_part$year != 2020] %in% FALSE),
       "a year with only two sampled months must be the only partial year")
assert(isTRUE(all.equal(t_part$cpn[t_part$year == 2020], 80)) &&
         isTRUE(all.equal(t_part$cpn[t_part$year == 2012], 100 * sum(season_rows$count[season_rows$year == 2012]) / 400)),
       "the partial flag must leave the plotted calendar-year cpn unchanged")
assert(identical(attr(t_part, "n_core"), 8L), "n_core must count the full-season years")
assert(identical(trend_call(t_part)$years_partial, 2020L) &&
         grepl("here: 2020", trend_partial_note(trend_call(t_part))),
       "the verdict must name the partial year")
# A significant all-years decline that comes only from two short final seasons
# (sampled in the low shoulder months) is apparent, not clear.
drop_rows <- do.call(rbind, lapply(2012:2017, function(y)
  data.frame(year = y, mon = full_mon$mon, count = full_mon$base + c(3, -3, 2, -2) * ((y %% 3) - 1))))
drop_rows <- rbind(drop_rows,
  data.frame(year = c(2018, 2018, 2019, 2019), mon = c(5, 8, 5, 8), count = c(19, 21, 20, 18)))
t_drop <- annual_trend(season_fixture(drop_rows))
tc_drop <- trend_call(t_drop)
assert(identical(tc_drop$kind, "fit") && isTRUE(tc_drop$sig_all) && tc_drop$slope < 0,
       "fixture: the all-years decline must be significant")
assert(identical(attr(t_drop, "years_partial"), c(2018L, 2019L)) && identical(tc_drop$n_core, 6L),
       "both short seasons must be partial, leaving six full-season years")
assert(isFALSE(tc_drop$clear) && isTRUE(tc_drop$partial_fail) && isFALSE(tc_drop$holds_core) &&
         isFALSE(tc_drop$rests_on_2023),
       "a slope that disappears without the partial years must not be clear")
assert(grepl("partial season are left out", trend_fail_clause(tc_drop)),
       "the verdict must name the failed season check")

assert(identical(tc_drop$check_season, "fail") && !grepl("cannot be confirmed", trend_fail_clause(tc_drop)),
       "a season check that ran and failed must read as a failure")

# Both exclusions together (audit wave 2 review): with 2023 in the series the
# season check refits on full-season years other than 2023. Here each check
# passes on its own (the calendar series without 2023, and the full-season
# series with 2023), but the full-season series without 2023 does not, so the
# call is not clear. The two early partial years sampled only peak months.
both_v <- 50 - 0.2 * (0:8) + noise
both_v <- c(both_v, both_v[9] - 6)
both_rows <- rbind(
  data.frame(year = rep(2012:2013, each = 2), mon = c(6, 7, 6, 7), count = 80),
  do.call(rbind, lapply(seq_along(2014:2023), function(i)
    data.frame(year = (2014:2023)[i], mon = full_mon$mon, count = full_mon$base * both_v[i] / 50))))
t_both <- annual_trend(season_fixture(both_rows))
tc_both <- trend_call(t_both)
assert(isTRUE(tc_both$sig_all) && is.finite(tc_both$p_ex2023) && tc_both$p_ex2023 < 0.05 &&
         sign(tc_both$slope_ex2023) == sign(tc_both$slope),
       "fixture: the 2023 check must pass on its own")
assert(is.finite(attr(t_both, "p_core")) && attr(t_both, "p_core") < 0.05 &&
         sign(attr(t_both, "slope_core")) == sign(tc_both$slope) && attr(t_both, "n_core") >= 6,
       "fixture: the season check with 2023 kept must pass on its own")
assert(identical(attr(t_both, "n_core_ex2023"), 9L) && attr(t_both, "p_core_ex2023") >= 0.05,
       "the season refit without 2023 must count 9 full-season years and not be significant")
assert(isFALSE(tc_both$clear) && isTRUE(tc_both$partial_fail) && identical(tc_both$check_2023, "pass") &&
         identical(tc_both$check_season, "fail"),
       "a trend that fails only with both exclusions applied must not be clear")
assert(grepl("partial season and 2023 are left out", trend_fail_clause(tc_both)),
       "the verdict must name the combined season check")
assert(is.null(attr(t_part, "n_core_ex2023")) && identical(trend_call(t_part)$season_n, 8L),
       "without 2023 the season check must use the core fit")

# A check that could not run reads as "cannot be confirmed", not as a failure:
# six years with 2023 leave five without it, too few to test.
t_six <- annual_trend(trend_fixture(2018:2023, 100 - 10 * (0:5) + noise[1:6]))
tc_six <- trend_call(t_six)
assert(isTRUE(tc_six$sig_all) && identical(tc_six$check_2023, "unconfirmed") &&
         identical(tc_six$check_season, "unconfirmed") && isFALSE(tc_six$clear),
       "six years with 2023 must leave both checks unconfirmed")
six_txt <- trend_fail_clause(tc_six)
assert(grepl("^which cannot be confirmed without the 2023 value", six_txt) &&
         grepl("too few comparable years remain$", six_txt) && !grepl("does not hold up", six_txt),
       "an unrun check must read as cannot be confirmed, not as a failure")

# Sampled-zero site (effort rows, no carabid catch): community_table() is NULL
# and the precomputed site_index row still builds, with zeros and no dominant.
zero_row <- site_index_row(zero_d, "TEST")
assert(nrow(zero_row) == 1L && zero_row$richness == 0L && zero_row$individuals == 0 &&
         zero_row$individuals_species == 0 && is.na(zero_row$dominant) &&
         identical(zero_row$years, 1L),
       "a sampled-zero bundle must give richness 0, individuals 0, no dominant, years from effort")
assert(zero_row$trapnights == 20 && zero_row$cpn == 0,
       "a sampled-zero site keeps its trap-nights and a real zero catch rate")
d_row <- site_index_row(d, "TEST")
assert(d_row$trapnights == 20 && abs(d_row$cpn - 25) < 1e-10 && d_row$individuals == 9,
       "site_index cpn counts only eligible catch over the unique effort anchors")

# Accumulation and per-species seasonality with an effort-only bout: three
# sampled plot-bouts, catch in one, so the curve runs over 3 bouts and July (a
# sampled month with no catch) reads 0 for each species.
acc_fx <- data.frame(
  siteID = "TEST", plotID = c("P1", "P1", "P1", "P2", "P1"),
  collectDate = as.Date(c("2024-06-10", "2024-06-10", "2024-06-10", "2024-06-10", "2024-07-10")),
  taxonID = c("T1", "T2", NA, NA, NA),
  scientificName = c("Carabus nemoralis", "Harpalus pensylvanicus", NA, NA, NA),
  taxonRank = c("species", "species", NA, NA, NA),
  individualCount = c(3, 2, 0, 0, 0), trapnights = 10,
  record_type = c("catch", "catch", "effort", "effort", "effort"),
  traps_sampled = 3L, effort_records = 3L,
  effort_status = "valid_sample_collected", stringsAsFactors = FALSE)
acc_d <- clean_beetle(acc_fx)
acc <- accumulation_by_bout(acc_d)
assert(!is.null(acc) && nrow(acc) == 3L && max(acc$richness) == 2,
       "accumulation must count every sampled plot-bout, including effort-only ones")
seas_sp <- seasonality(acc_d, by_species = TRUE)
jul <- seas_sp[seas_sp$mon == 7L, , drop = FALSE]
assert(nrow(jul) == 2L && all(jul$cpn == 0),
       "a sampled month with no catch of a species must read 0, not a missing row")

cat("OK: Ground Beetle effort, zero-catch, taxonomy, detection, QC, and legacy contracts passed.\n")
