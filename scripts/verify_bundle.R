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
if (length(missing_sites)) {
  note(sprintf(paste0(
    "site roster in R/site_metadata.R lists %d site(s) with no bundle in data/sites: [%s]; ",
    "run the release-pinned refresh to fetch them"),
    length(missing_sites), paste(missing_sites, collapse = ",")))
}
if (length(extra_sites)) {
  note(sprintf("data/sites has %d bundle(s) not in the R/site_metadata.R roster: [%s]",
               length(extra_sites), paste(extra_sites, collapse = ",")))
}

# ---- independent headline-metric oracle -------------------------------------
# Written here on purpose, without sourcing R/helpers.R, so a bug in the app's
# own metric code cannot also hide in the check. Mirrors the science contract:
#   individuals = sum of individualCount over catch rows
#   richness    = distinct species keys: species/subspecies rows reduced to
#                 "Genus epithet" after removing "(Subgenus)" tags, plus each
#                 speciesGroup name none of whose member binomials is present
#   years       = distinct calendar years of explicit effort rows
#   trapnights  = sum of trapnights over unique effort anchors
#                 (siteID, plotID, collectDate)
#   cpn         = 100 x (sum of individualCount over catch rows whose plot-bout
#                 has a valid effort anchor) / trapnights
oracle_binomial <- function(x) {
  x <- gsub("[(][^)]*[)]", " ", as.character(x))
  x <- trimws(gsub("[[:space:]]+", " ", x))
  m <- regmatches(x, regexpr("^[A-Z][a-z]+ [a-z][a-z-]+", x))
  out <- rep(NA_character_, length(x))
  out[grepl("^[A-Z][a-z]+ [a-z][a-z-]+", x)] <- m
  out
}
oracle_group_members <- function(name) {
  x <- trimws(gsub("[[:space:]]+", " ", gsub("[(][^)]*[)]", " ", name)))
  if (grepl("/", x, fixed = TRUE)) {
    parts <- trimws(strsplit(x, "/", fixed = TRUE)[[1]])
    parts <- parts[nzchar(parts)]
    if (!length(parts)) return(character(0))
    genus <- strsplit(parts[1], " ", fixed = TRUE)[[1]][1]
    full <- ifelse(grepl(" ", parts), parts, paste(genus, parts))
    full[1] <- parts[1]
    return(unique(stats::na.omit(oracle_binomial(full))))
  }
  if (grepl(" (group|complex)$", x, ignore.case = TRUE))
    return(stats::na.omit(oracle_binomial(sub(" (group|complex)$", "", x, ignore.case = TRUE))))
  character(0)
}
oracle_metrics <- function(b) {
  catch <- b[b$record_type == "catch" & !is.na(b$scientificName) &
               is.finite(b$individualCount) & b$individualCount > 0, , drop = FALSE]
  rank <- as.character(catch$taxonRank)
  sp_keys <- unique(stats::na.omit(oracle_binomial(catch$scientificName[rank %in% c("species", "subspecies")])))
  groups <- unique(trimws(catch$scientificName[rank %in% "speciesGroup"]))
  kept <- groups[vapply(groups, function(g) !any(oracle_group_members(g) %in% sp_keys), logical(1))]
  eff_dates <- b$collectDate[b$record_type == "effort" & !is.na(b$collectDate)]
  eff <- b[b$record_type == "effort" & is.finite(b$trapnights) & b$trapnights > 0 &
             !is.na(b$plotID) & !is.na(b$collectDate), , drop = FALSE]
  eff_key <- paste(eff$siteID, eff$plotID, as.character(eff$collectDate), sep = "|")
  eff <- eff[!duplicated(eff_key), , drop = FALSE]
  eff_key <- eff_key[!duplicated(eff_key)]
  tn <- if (nrow(eff)) sum(eff$trapnights) else NA_real_
  catch_key <- paste(catch$siteID, catch$plotID, as.character(catch$collectDate), sep = "|")
  matched <- sum(catch$individualCount[catch_key %in% eff_key])
  c(individuals = sum(catch$individualCount),
    richness = length(sp_keys) + length(kept),
    years = length(unique(format(as.Date(eff_dates), "%Y"))),
    trapnights = tn,
    cpn = if (is.finite(tn) && tn > 0) 100 * matched / tn else NA_real_)
}
oracle <- list()

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
  oracle[[code]] <- oracle_metrics(object)
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
    si <- precomputed$site_index
    got <- sort(unique(as.character(si$site)))
    if (!identical(got, expected_sites))
      note(sprintf("precomputed site_index does not match the site roster: missing=[%s] extra=[%s]",
                   paste(setdiff(expected_sites, got), collapse = ","),
                   paste(setdiff(got, expected_sites), collapse = ",")))
    checked <- 0L
    for (code in names(oracle)) {
      row <- si[as.character(si$site) == code, , drop = FALSE]
      if (nrow(row) != 1L) {
        note(sprintf("oracle: %s has %d site_index rows (expected 1)", code, nrow(row)))
        next
      }
      want <- oracle[[code]]
      for (metric in c("individuals", "richness", "years")) {
        have <- suppressWarnings(as.numeric(row[[metric]]))
        if (length(have) != 1L || is.na(have) || have != unname(want[[metric]]))
          note(sprintf("oracle: %s %s mismatch: site_index=%s, recomputed=%s",
                       code, metric, format(have), format(unname(want[[metric]]))))
      }
      if (!all(c("trapnights", "cpn") %in% names(row))) {
        note(sprintf("oracle: %s site_index lacks trapnights/cpn columns (rebuild data/precomputed.rds)", code))
      } else {
        have_tn <- suppressWarnings(as.numeric(row$trapnights))
        want_tn <- unname(want[["trapnights"]])
        if (length(have_tn) != 1L || !identical(is.na(have_tn), is.na(want_tn)) ||
            (!is.na(want_tn) && have_tn != want_tn))
          note(sprintf("oracle: %s trapnights mismatch: site_index=%s, recomputed=%s",
                       code, format(have_tn), format(want_tn)))
        have_cpn <- suppressWarnings(as.numeric(row$cpn))
        want_cpn <- unname(want[["cpn"]])
        if (length(have_cpn) != 1L || !identical(is.na(have_cpn), is.na(want_cpn)) ||
            (!is.na(want_cpn) && abs(have_cpn - want_cpn) > 1e-9))
          note(sprintf("oracle: %s cpn mismatch: site_index=%s, recomputed=%s",
                       code, format(have_cpn, digits = 12), format(want_cpn, digits = 12)))
      }
      checked <- checked + 1L
    }
    cat(sprintf("oracle: recomputed individuals, richness, years, trap-nights and cpn for %d site(s)\n", checked))
  }
}

# ---- release identity ---------------------------------------------------------
rel <- tryCatch(readRDS("data/release.rds"), error = function(e) e)
if (inherits(rel, "error") || !is.list(rel)) {
  note("data/release.rds is missing or unreadable (run scripts/record_release.R)")
} else {
  bundle_dates <- unlist(lapply(site_files, function(f) {
    d <- tryCatch(readRDS(f)$collectDate, error = function(e) NULL)
    if (is.null(d)) return(NULL)
    as.character(max(as.Date(substr(as.character(d), 1, 10)), na.rm = TRUE))
  }))
  max_date <- if (length(bundle_dates)) max(bundle_dates) else NA_character_
  if (!is.character(rel$release) || !grepl("^RELEASE-[0-9]{4}$", rel$release %||% ""))
    note("data/release.rds release is not of the form RELEASE-YYYY")
  if (!is.character(rel$doi) || !startsWith(rel$doi %||% "", "https://doi.org/10.48443/"))
    note("data/release.rds doi does not start with https://doi.org/10.48443/")
  if (!identical(rel$provisional_included, FALSE))
    note("data/release.rds provisional_included is not FALSE")
  if (!identical(as.character(rel$data_through %||% ""), as.character(max_date)))
    note(sprintf("data/release.rds data_through=%s but the bundles end %s",
                 as.character(rel$data_through %||% "NA"), max_date))
  if (!identical(as.integer(rel$n_sites %||% NA), length(site_files)))
    note(sprintf("data/release.rds n_sites=%s but data/sites has %d bundles",
                 as.character(rel$n_sites %||% "NA"), length(site_files)))
  cat(sprintf("release: %s (%s), data through %s, %s sites\n",
              rel$release %||% "?", rel$doi %||% "?", rel$data_through %||% "?",
              as.character(rel$n_sites %||% "?")))
}

search <- tryCatch(readRDS("data/search_index.rds"), error = function(e) e)
if (inherits(search, "error") || !is.list(search) ||
    is.null(search$taxa) || !is.data.frame(search$taxa) || !nrow(search$taxa))
  note("data/search_index.rds is missing, unreadable, or has no taxa table")
if (!inherits(search, "error") && is.list(search) &&
    !identical(search$built, NA_character_))
  note("data/search_index.rds embeds an unreviewed or nondeterministic build time")

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
