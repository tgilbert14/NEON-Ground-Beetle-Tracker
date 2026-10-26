# ===========================================================================
# refresh_data.R — build the bundled per-site beetle "database"
#
# Downloads each NEON site's ground-beetle record (DP1.10022.001), assembles it
# into the app's tidy long schema (siteID, plotID, collectDate, taxonID,
# scientificName, taxonRank, individualCount, trapnights) via assemble_beetles()
# — taxonRank lets richness cleanly exclude genus/family-only IDs — and
# xz-compresses one .rds per site into data/sites/<SITE>.rds.
#
# RESUMABLE: skips sites whose .rds already exists. The release workflow points
# GBT_SITE_OUT_DIR at an EMPTY staging directory so an incomplete download can
# never replace the committed known-good bundle.
# Run from the project root:   Rscript scripts/refresh_data.R
#
# RELEASE-PINNED: every download asks NEON for exactly one tagged release,
# GBT_RELEASE (default "RELEASE-2026"), with include.provisional = FALSE, so the
# bundle never mixes provisional rows into a release build. The refresh workflow
# sets GBT_RELEASE at workflow level. Downloads need NEON_TOKEN; the script stops
# before the first download when it is empty.
#
# Companion steps that live outside this script:
#   - data/env/<SITE>.rds (precip / air temp / phenology overlays) is synced from
#     the Small Mammal repo by a step in the refresh workflow, not built here.
#   - data/release.rds (release tag, generation date, DOI, citation, data-through
#     date) is written by scripts/record_release.R after the bundle is complete.
#
# Verify table/column names once before a full run:
#   names(neonUtilities::loadByProduct("DP1.10022.001", site="KONZ",
#         startdate="2018-05", enddate="2018-09", check.size="F"))
# ===========================================================================

options(timeout = 1800)
suppressMessages({
  library(neonUtilities)
  library(dplyr)
  library(tibble)
})

source("R/site_metadata.R")  # canonical site list
source("R/helpers.R")        # assemble_beetles()

out_dir <- Sys.getenv("GBT_SITE_OUT_DIR", unset = "")
if (!nzchar(out_dir)) out_dir <- "data/sites"   # an empty value counts as unset
build_only <- identical(Sys.getenv("GBT_REFRESH_BUILD_ONLY", unset = "0"), "1")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

start_d <- "2013-01"
end_d   <- format(Sys.Date(), "%Y-%m")
sites   <- neon_sites$site
GBT_RELEASE <- Sys.getenv("GBT_RELEASE", unset = "RELEASE-2026")
if (!nzchar(GBT_RELEASE)) GBT_RELEASE <- "RELEASE-2026"
if (!grepl("^RELEASE-[0-9]{4}$", GBT_RELEASE))
  stop(sprintf("GBT_RELEASE must look like RELEASE-YYYY, got '%s'", GBT_RELEASE))
neon_token <- Sys.getenv("NEON_TOKEN", unset = "")

cat(sprintf("Refreshing %d sites (%s → %s, %s, no provisional) into %s/\n\n",
            length(sites), start_d, end_d, GBT_RELEASE, out_dir))

for (s in sites) {
  out <- file.path(out_dir, paste0(s, ".rds"))
  if (file.exists(out)) { cat(sprintf("• %-5s skip (exists, %.2f MB)\n", s, file.size(out)/1e6)); next }

  if (!nzchar(neon_token)) stop("NEON_TOKEN is unset: data downloads need a token")
  cat(sprintf("• %-5s downloading…\n", s))
  raw <- tryCatch(
    loadByProduct(dpID = "DP1.10022.001", site = s, startdate = start_d, enddate = end_d,
                  package = "basic", release = GBT_RELEASE,
                  include.provisional = FALSE, check.size = "F",
                  token = neon_token),
    error = function(e) { cat(sprintf("    ERROR %s: %s\n", s, conditionMessage(e))); NULL })
  if (is.null(raw)) next

  d <- tryCatch(assemble_beetles(raw), error = function(e) {
    cat(sprintf("    assemble error %s: %s\n", s, conditionMessage(e))); NULL })
  # A site with effort anchors but no Carabidae catch is a real sampled-zero site
  # and is saved; only a table with neither effort nor catch rows is skipped (and
  # then fails the roster check below).
  if (is.null(d) || !nrow(d)) { cat(sprintf("    no effort or catch rows for %s\n", s)); next }

  # Materialize EVERY column to a plain base vector before save. assemble_beetles()
  # returns arrow/ALTREP-backed columns: a cold readRDS() + bulk access (nrow/names)
  # on those deferred-string columns segfaults a vanilla Rscript (exit 139), and
  # `col[seq_along(col)]` does NOT force a deferred string — it stays an ALTREP
  # promise. Coerce by TYPE: as.character() collapses every string column to a real
  # CHARSXP vector, as.Date() gives collectDate a true Date class (assemble_beetles
  # never sets one, so an inherits(col,"Date") test would never fire), and as.numeric()
  # realizes the count/effort columns. saveRDS(version = 2) keeps the bundle readable
  # by the broadest set of R installs.
  date_cols <- "collectDate"
  num_cols  <- intersect(c("individualCount", "trapnights", "traps_sampled",
                           "effort_records"), names(d))
  for (nm in names(d)) {
    col <- d[[nm]]
    d[[nm]] <-
      if (nm %in% date_cols) as.Date(substr(as.character(col), 1, 10))
      else if (nm %in% num_cols) as.numeric(as.character(col))
      else if (is.character(col) || is.factor(col)) as.character(col)
      else col[seq_along(col)]
  }
  saveRDS(tibble::as_tibble(d), out, version = 2, compress = "xz")
  cat(sprintf("    saved %s: %d rows, %d species, %.2f MB\n",
              s, nrow(d), dplyr::n_distinct(d$scientificName), file.size(out)/1e6))
}

n_ok <- length(list.files(out_dir, pattern = "\\.rds$"))
cat(sprintf("\nDone. Bundle now has %d site files.\n", n_ok))

# Fail closed on the canonical roster. A partial refresh is not a release
# candidate, even if most sites downloaded successfully.
built_sites <- sort(sub("[.]rds$", "", list.files(out_dir, pattern = "[.]rds$")))
expected_sites <- sort(unique(as.character(sites)))
if (!identical(built_sites, expected_sites)) {
  stop(sprintf(
    "Site roster incomplete — missing=[%s] extra=[%s]; keeping the committed bundle untouched.",
    paste(setdiff(expected_sites, built_sites), collapse = ","),
    paste(setdiff(built_sites, expected_sites), collapse = ",")
  ))
}
# Every site file must carry explicit effort anchors. Zero catch rows is allowed:
# a site whose valid sampled opportunities caught no Carabidae is a real
# sampled-zero site, not a failed download.
no_effort <- character(0)
for (s in built_sites) {
  b <- readRDS(file.path(out_dir, paste0(s, ".rds")))
  rt <- if ("record_type" %in% names(b)) as.character(b$record_type) else character(0)
  if (!any(rt == "effort", na.rm = TRUE)) no_effort <- c(no_effort, s)
  else if (!any(rt == "catch", na.rm = TRUE))
    cat(sprintf("  note: %s has effort anchors and no carabid catch (sampled-zero site)\n", s))
}
if (length(no_effort)) {
  stop(sprintf(
    "Site files without explicit effort anchors: [%s]; keeping the committed bundle untouched.",
    paste(no_effort, collapse = ",")))
}

if (build_only) {
  cat("Validated staged site roster; derived indexes and manifest are rebuilt after promotion.\n")
  quit(save = "no", status = 0L)
}

# ---- rebuild cross-site cache + deploy manifest ---------------------------
# A data refresh that stopped here would ship a STALE precomputed.rds (wrong
# ordination / indicators) and an unregenerated manifest.json. Do both now so the
# bundle, the cross-site cache, and the deploy manifest are always in lockstep.
cat("\nRebuilding cross-site precompute cache…\n")
tryCatch(source("scripts/precompute.R"),
         error = function(e) cat("  precompute FAILED:", conditionMessage(e), "\n"))

if (requireNamespace("rsconnect", quietly = TRUE)) {
  cat("Regenerating manifest.json via scripts/write_manifest.R (lean appFiles + hard gate)…\n")
  # Defer to the single gated builder so the manifest is always written the same
  # way AND the hard gate (stop on neonUtilities / arrow) runs on every refresh.
  source("scripts/write_manifest.R")
} else {
  cat("rsconnect not installed — skipping manifest regen (run scripts/write_manifest.R yourself).\n")
}

cat("\nLocal refresh complete. Review generated data and manifest changes before publishing.\n")
