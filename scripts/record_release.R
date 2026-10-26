#!/usr/bin/env Rscript
# ===========================================================================
# record_release.R - write data/release.rds, the release identity of the bundle
#
# The site bundle is pinned to ONE tagged NEON release (GBT_RELEASE, default
# "RELEASE-2026") with provisional data excluded. This script asks NEON's public
# product endpoint (no token needed) for that release's generation date and
# product DOI, reads the data-through date and site count from data/sites/*.rds,
# and saves a plain list to data/release.rds.
#
# Deterministic by design: no access date, run time or other clock value is
# written, so the same release and bundle always give the same bytes.
# Fails loudly when the release or its DOI is missing from the API response.
#
# Run from the project root after the site bundle is complete:
#   Rscript --vanilla scripts/record_release.R
# ===========================================================================

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

PRODUCT <- "DP1.10022.001"
release <- Sys.getenv("GBT_RELEASE", unset = "RELEASE-2026")
if (!nzchar(release)) release <- "RELEASE-2026"
if (!grepl("^RELEASE-[0-9]{4}$", release))
  stop(sprintf("GBT_RELEASE must look like RELEASE-YYYY, got '%s'", release), call. = FALSE)

site_dir <- Sys.getenv("GBT_SITE_OUT_DIR", unset = "")
if (!nzchar(site_dir)) site_dir <- "data/sites"   # an empty value counts as unset
out_file <- file.path("data", "release.rds")

api <- sprintf("https://data.neonscience.org/api/v0/products/%s", PRODUCT)
meta <- tryCatch(jsonlite::fromJSON(api, simplifyVector = FALSE),
                 error = function(e) stop(sprintf("NEON product API request failed: %s",
                                                  conditionMessage(e)), call. = FALSE))
releases <- meta$data$releases
if (is.null(releases) || !length(releases))
  stop(sprintf("NEON product API lists no releases for %s", PRODUCT), call. = FALSE)
hit <- Filter(function(r) identical(r$release, release), releases)
if (length(hit) != 1L)
  stop(sprintf("%s not found exactly once in the NEON release list for %s (found %d)",
               release, PRODUCT, length(hit)), call. = FALSE)
hit <- hit[[1]]
generated <- as.character(hit$generationDate %||% "")
doi <- as.character(hit$productDoi$url %||% "")
if (!nzchar(generated))
  stop(sprintf("%s has no generationDate in the NEON product API", release), call. = FALSE)
if (!grepl("^https://doi[.]org/10[.]48443/", doi))
  stop(sprintf("%s has no product DOI in the NEON product API (got '%s')", release, doi),
       call. = FALSE)

files <- sort(list.files(site_dir, pattern = "[.]rds$", full.names = TRUE))
if (!length(files)) stop(sprintf("no site bundles in %s", site_dir), call. = FALSE)
last_dates <- vapply(files, function(f) {
  d <- readRDS(f)$collectDate
  d <- as.Date(substr(as.character(d), 1, 10))
  if (all(is.na(d))) NA_real_ else as.numeric(max(d, na.rm = TRUE))
}, numeric(1))
if (all(is.na(last_dates))) stop("no collectDate values in the site bundles", call. = FALSE)
data_through <- format(as.Date(max(last_dates, na.rm = TRUE), origin = "1970-01-01"), "%Y-%m-%d")

record <- list(
  product = PRODUCT,
  release = release,
  release_generated = generated,
  doi = doi,
  provisional_included = FALSE,
  data_through = data_through,
  n_sites = length(files),
  citation = sprintf(paste0(
    "NEON (National Ecological Observatory Network). Ground beetles sampled from ",
    "pitfall traps (%s), %s. %s"), PRODUCT, release, doi)
)

dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
saveRDS(record, out_file, version = 2, compress = "xz")
cat(sprintf("Wrote %s: %s generated %s, DOI %s, %d sites, data through %s\n",
            out_file, release, generated, doi, record$n_sites, data_through))
