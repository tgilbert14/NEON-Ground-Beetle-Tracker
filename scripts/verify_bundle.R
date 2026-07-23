#!/usr/bin/env Rscript
# Fail-closed offline verifier for site bundles, derived indexes, and manifest.

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
problems <- character(0)
note <- function(message) problems[[length(problems) + 1L]] <<- message

source("R/site_metadata.R")
expected_sites <- sort(unique(as.character(neon_sites$site)))
required <- c(
  "siteID", "plotID", "collectDate", "taxonID", "scientificName", "taxonRank",
  "individualCount", "trapnights", "traps_sampled", "effort_records",
  "record_type", "sampled_opportunity", "effort_status", "source"
)

site_files <- list.files("data/sites", pattern = "[.]rds$", full.names = TRUE)
site_codes <- sub("[.]rds$", "", basename(site_files))
missing_sites <- setdiff(expected_sites, site_codes)
extra_sites <- setdiff(site_codes, expected_sites)
if (length(missing_sites) || length(extra_sites)) {
  note(sprintf("site set mismatch: missing=[%s] extra=[%s]",
               paste(missing_sites, collapse = ","), paste(extra_sites, collapse = ",")))
}

bundle_rows <- integer(0)
anchor_rows <- integer(0)
catch_rows <- integer(0)
for (file in site_files) {
  code <- sub("[.]rds$", "", basename(file))
  object <- tryCatch(readRDS(file), error = function(e) e)
  if (inherits(object, "error")) {
    note(sprintf("%s cannot load: %s", code, conditionMessage(object)))
    next
  }
  if (!is.data.frame(object) || !nrow(object)) {
    note(sprintf("%s is not a non-empty data frame", code))
    next
  }
  missing_cols <- setdiff(required, names(object))
  if (length(missing_cols)) {
    note(sprintf("%s missing schema columns: %s", code, paste(missing_cols, collapse = ",")))
    next
  }
  if (!inherits(object$collectDate, "Date")) note(sprintf("%s collectDate is not Date", code))
  if (!all(object$siteID == code, na.rm = TRUE)) note(sprintf("%s contains another siteID", code))
  if (!all(object$record_type %in% c("catch", "effort"))) note(sprintf("%s has invalid record_type", code))

  anchors <- object[object$record_type == "effort", , drop = FALSE]
  catches <- object[object$record_type == "catch", , drop = FALSE]
  if (!nrow(anchors)) note(sprintf("%s has no explicit effort anchors", code))
  if (any(!anchors$sampled_opportunity %in% TRUE) ||
      any(!is.finite(anchors$trapnights) | anchors$trapnights <= 0) ||
      any(!is.finite(anchors$traps_sampled) | anchors$traps_sampled <= 0) ||
      any(!is.finite(anchors$effort_records) | anchors$effort_records <= 0) ||
      any(anchors$individualCount != 0, na.rm = TRUE) ||
      any(!is.na(anchors$scientificName)) ||
      any(anchors$effort_status != "valid_sample_collected"))
    note(sprintf("%s has malformed effort anchors", code))
  anchor_key <- paste(anchors$siteID, anchors$plotID, anchors$collectDate, sep = "|")
  if (anyDuplicated(anchor_key)) note(sprintf("%s has duplicate plot-bout effort anchors", code))

  if (nrow(catches)) {
    if (any(catches$sampled_opportunity %in% TRUE) ||
        any(!is.finite(catches$individualCount) | catches$individualCount <= 0) ||
        any(is.na(catches$scientificName) | !nzchar(catches$scientificName)))
      note(sprintf("%s has malformed catch rows", code))
    catch_key <- paste(catches$siteID, catches$plotID, catches$collectDate, sep = "|")
    unmatched <- catches$effort_status != "valid_sample_collected" | !(catch_key %in% anchor_key)
    if (any(unmatched)) note(sprintf("%s has %d catch rows without a valid opportunity anchor", code, sum(unmatched)))
  }
  bundle_rows[code] <- nrow(object)
  anchor_rows[code] <- nrow(anchors)
  catch_rows[code] <- nrow(catches)
}
cat(sprintf("bundles: %d files, %d rows, %d opportunity anchors, %d catch rows\n",
            length(site_files), sum(bundle_rows), sum(anchor_rows), sum(catch_rows)))

precomputed <- tryCatch(readRDS("data/precomputed.rds"), error = function(e) e)
if (inherits(precomputed, "error") || !is.list(precomputed)) {
  note("data/precomputed.rds is missing, unreadable, or not a list")
} else {
  for (name in c("site_index", "ordination", "indicators", "species_sites")) {
    value <- precomputed[[name]]
    if (is.null(value) || !is.data.frame(value) || !nrow(value))
      note(sprintf("precomputed index %s is absent or empty", name))
  }
  if (is.data.frame(precomputed$site_index)) {
    got <- sort(unique(as.character(precomputed$site_index$site)))
    if (!identical(got, expected_sites)) note("precomputed site_index does not match expected site roster")
  }
}

search <- tryCatch(readRDS("data/search_index.rds"), error = function(e) e)
if (inherits(search, "error") || !is.list(search) ||
    is.null(search$taxa) || !is.data.frame(search$taxa) || !nrow(search$taxa))
  note("data/search_index.rds is missing, unreadable, or has no taxa table")

R_PLATFORM <- "4.5.2"
RSPM <- "https://packagemanager.posit.co/cran/__linux__/jammy/2026-07-15"
RUNTIME <- c(
  "shiny", "bslib", "bsicons", "dplyr", "tidyr", "tibble", "plotly",
  "leaflet", "DT", "shinyjs", "shinycssloaders", "RColorBrewer",
  "htmltools", "ggplot2"
)
GEO <- c(
  terra = "1.8-50", sf = "1.1-1", s2 = "1.1.11", units = "1.0-1",
  wk = "0.9.5", classInt = "0.4-11", raster = "3.6-32", sp = "2.2-1"
)
GEO_URLS <- c(
  terra = "https://cran.r-project.org/src/contrib/Archive/terra/terra_1.8-50.tar.gz",
  sf = "https://packagemanager.posit.co/cran/2026-07-15/src/contrib/sf_1.1-1.tar.gz",
  s2 = "https://packagemanager.posit.co/cran/2026-07-15/src/contrib/s2_1.1.11.tar.gz",
  units = "https://packagemanager.posit.co/cran/2026-07-15/src/contrib/units_1.0-1.tar.gz",
  wk = "https://packagemanager.posit.co/cran/2026-07-15/src/contrib/wk_0.9.5.tar.gz",
  classInt = "https://packagemanager.posit.co/cran/2026-07-15/src/contrib/classInt_0.4-11.tar.gz",
  raster = "https://packagemanager.posit.co/cran/2026-07-15/src/contrib/raster_3.6-32.tar.gz",
  sp = "https://packagemanager.posit.co/cran/2026-07-15/src/contrib/sp_2.2-1.tar.gz"
)

manifest <- tryCatch(jsonlite::fromJSON("manifest.json", simplifyVector = FALSE), error = function(e) e)
if (inherits(manifest, "error")) {
  note("manifest.json is missing or invalid JSON")
} else {
  files <- manifest$files
  if (is.null(files) || !length(files)) {
    note("manifest lists no files")
  } else {
    missing <- names(files)[!file.exists(names(files))]
    if (length(missing)) note(sprintf("manifest references %d missing files", length(missing)))
    present <- setdiff(names(files), missing)
    mismatch <- vapply(present, function(path) {
      expected <- tolower(as.character(files[[path]]$checksum %||% ""))
      actual <- tolower(unname(tools::md5sum(path)))
      !nzchar(expected) || !identical(expected, actual)
    }, logical(1))
    if (any(mismatch))
      note(sprintf("manifest checksum mismatch for %d files: %s", sum(mismatch),
                   paste(utils::head(present[mismatch], 12), collapse = ",")))
  }
  packages <- manifest$packages
  keys <- names(packages)
  if (!identical(as.character(manifest$platform %||% ""), R_PLATFORM))
    note(sprintf("manifest platform is not %s", R_PLATFORM))
  if (length(setdiff(RUNTIME, keys))) note("manifest lacks required runtime packages")
  if (length(intersect(c("neonUtilities", "arrow"), keys))) note("manifest contains live-fetch-only packages")
  for (pkg in keys) {
    item <- packages[[pkg]]
    version <- as.character(item$description$Version %||% "")
    declared <- as.character(item$description$Package %||% "")
    repo <- as.character(item$Repository %||% "")
    source <- as.character(item$Source %||% "")
    if (!nzchar(version) || !identical(declared, pkg) || !identical(source, "CRAN"))
      note(sprintf("manifest identity invalid for %s", pkg))
    if (pkg %in% names(GEO)) {
      expected_ref <- paste0("url::", unname(GEO_URLS[[pkg]]))
      if (!identical(version, unname(GEO[[pkg]])) ||
          !identical(repo, "https://cran.r-project.org") ||
          !identical(as.character(item$description$RemoteType %||% ""), "url") ||
          !identical(as.character(item$description$RemotePkgRef %||% ""), expected_ref) ||
          nzchar(as.character(item$description$Built %||% "")))
        note(sprintf("manifest geospatial provenance invalid for %s", pkg))
    } else if (!identical(repo, RSPM)) note(sprintf("manifest repository invalid for %s", pkg))
  }
  for (pkg in names(GEO)) if (!pkg %in% keys) note(sprintf("manifest missing geospatial package %s", pkg))
}

if (length(problems)) {
  for (problem in unique(problems)) cat(sprintf("::error title=Ground Beetle verification::%s\n", problem))
  stop(sprintf("Ground Beetle verification FAILED with %d problem(s)", length(unique(problems))), call. = FALSE)
}
cat("OK: Ground Beetle bundles, opportunities, indexes, and manifest passed.\n")
