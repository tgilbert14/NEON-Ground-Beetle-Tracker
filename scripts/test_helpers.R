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
assert(d$individualCount[d$scientificName == "Pterostichus melanarius"] == 1,
       "one expert specimen must not relabel the entire sorting count")
assert(d$individualCount[d$scientificName == "Pterostichus sp."] == 2,
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

cat("OK: Ground Beetle effort, zero-catch, taxonomy, detection, QC, and legacy contracts passed.\n")
