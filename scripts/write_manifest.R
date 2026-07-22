#!/usr/bin/env Rscript
# Generate the lean, deterministic Connect manifest from the pinned validator.
# This script verifies what is actually installed; it never fabricates a version.

suppressMessages({
  library(rsconnect)
  library(jsonlite)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

RSPM_SNAPSHOT <- "https://packagemanager.posit.co/cran/__linux__/jammy/2026-07-15"
R_PLATFORM_PIN <- "4.5.2"
RUNTIME_PKGS <- c(
  "shiny", "bslib", "bsicons", "dplyr", "tidyr", "tibble", "plotly",
  "leaflet", "DT", "shinyjs", "shinycssloaders", "RColorBrewer",
  "htmltools", "ggplot2"
)
DROP_PKGS <- c("neonUtilities", "arrow")
GEO_PINS <- c(
  terra = "1.8-50", sf = "1.1-1", s2 = "1.1.11", units = "1.0-1",
  wk = "0.9.5", classInt = "0.4-11", raster = "3.6-32", sp = "2.2-1"
)
GEO_URLS <- c(
  terra = "https://cran.r-project.org/src/contrib/Archive/terra/terra_1.8-50.tar.gz",
  sf = "https://cran.r-project.org/src/contrib/sf_1.1-1.tar.gz",
  s2 = "https://cran.r-project.org/src/contrib/s2_1.1.11.tar.gz",
  units = "https://cran.r-project.org/src/contrib/units_1.0-1.tar.gz",
  wk = "https://cran.r-project.org/src/contrib/wk_0.9.5.tar.gz",
  classInt = "https://cran.r-project.org/src/contrib/classInt_0.4-11.tar.gz",
  raster = "https://cran.r-project.org/src/contrib/raster_3.6-32.tar.gz",
  sp = "https://cran.r-project.org/src/contrib/sp_2.2-1.tar.gz"
)

app_files <- c(
  "global.R", "ui.R", "server.R",
  list.files("R", pattern = "[.]R$", full.names = TRUE),
  list.files("www", recursive = TRUE, full.names = TRUE),
  list.files("data", recursive = TRUE, full.names = TRUE),
  list.files("data-sample", recursive = TRUE, full.names = TRUE)
)
app_files <- sort(unique(app_files[file.exists(app_files) & !dir.exists(app_files)]))
cat(sprintf("Writing manifest for %d runtime files.\n", length(app_files)))
rsconnect::writeManifest(appDir = ".", appFiles = app_files)

# Keep only the dependency closure reachable from actual runtime roots. The
# optional live NEON client and its unique heavy dependencies are build-only.
manifest <- jsonlite::fromJSON("manifest.json", simplifyVector = FALSE)
packages <- manifest$packages
dep_names <- function(info) {
  description <- info$description
  if (is.null(description)) return(character(0))
  fields <- paste(c(description$Imports, description$Depends, description$LinkingTo), collapse = ",")
  fields <- gsub("[\r\n]", " ", fields)
  tokens <- trimws(unlist(strsplit(fields, ",")))
  tokens <- trimws(sub("[ (].*$", "", tokens))
  intersect(tokens[nzchar(tokens) & tokens != "R"], names(packages))
}
reachable <- character(0)
frontier <- setdiff(intersect(RUNTIME_PKGS, names(packages)), DROP_PKGS)
while (length(frontier)) {
  reachable <- union(reachable, frontier)
  next_names <- unique(unlist(lapply(frontier, function(pkg) dep_names(packages[[pkg]]))))
  frontier <- setdiff(next_names, c(reachable, DROP_PKGS))
}
missing_roots <- setdiff(RUNTIME_PKGS, reachable)
if (length(missing_roots)) stop("manifest missing runtime roots: ", paste(missing_roots, collapse = ", "))
manifest$packages <- packages[reachable]
jsonlite::write_json(manifest, "manifest.json", auto_unbox = TRUE, pretty = TRUE, null = "null")

# Freeze ordinary packages to a dated snapshot without reserializing after the
# canonical package edit below.
text <- readLines("manifest.json", warn = FALSE)
for (moving in c(
  "https://packagemanager.posit.co/cran/latest",
  "https://packagemanager.posit.co/cran/__linux__/jammy/latest",
  "https://cloud.r-project.org"
)) text <- gsub(moving, RSPM_SNAPSHOT, text, fixed = TRUE)
writeLines(text, "manifest.json")

# Exact URL builds have non-semantic wall-clock Built timestamps. Remove those
# only for the pinned geospatial closure and put them on Connect's deployable CRAN
# lane while retaining the exact tarball in RemotePkgRef.
canonical <- jsonlite::fromJSON("manifest.json", simplifyVector = FALSE)
for (pkg in names(GEO_PINS)) {
  if (!is.null(canonical$packages[[pkg]]$description)) {
    canonical$packages[[pkg]]$description$Built <- NULL
    canonical$packages[[pkg]]$Source <- "CRAN"
    canonical$packages[[pkg]]$Repository <- "https://cran.r-project.org"
  }
}
jsonlite::write_json(canonical, "manifest.json", auto_unbox = TRUE, pretty = TRUE, null = "null")

check <- jsonlite::fromJSON("manifest.json", simplifyVector = FALSE)
problems <- character(0)
if (!identical(as.character(check$platform %||% ""), R_PLATFORM_PIN))
  problems <- c(problems, sprintf("platform=%s", check$platform %||% "<missing>"))
keys <- names(check$packages)
leaked <- intersect(DROP_PKGS, keys)
if (length(leaked)) problems <- c(problems, paste("live-only package leak", paste(leaked, collapse = ",")))

for (pkg in keys) {
  item <- check$packages[[pkg]]
  version <- as.character(item$description$Version %||% "")
  declared <- as.character(item$description$Package %||% "")
  repo <- as.character(item$Repository %||% "")
  source <- as.character(item$Source %||% "")
  if (!nzchar(version) || !identical(declared, pkg) || !identical(source, "CRAN"))
    problems <- c(problems, paste("invalid package identity", pkg))
  if (pkg %in% names(GEO_PINS)) {
    expected_ref <- paste0("url::", unname(GEO_URLS[[pkg]]))
    if (!identical(version, unname(GEO_PINS[[pkg]])) ||
        !identical(repo, "https://cran.r-project.org") ||
        !identical(as.character(item$description$RemoteType %||% ""), "url") ||
        !identical(as.character(item$description$RemotePkgRef %||% ""), expected_ref) ||
        nzchar(as.character(item$description$Built %||% "")))
      problems <- c(problems, paste("invalid geospatial provenance", pkg))
  } else if (!identical(repo, RSPM_SNAPSHOT)) {
    problems <- c(problems, paste("ordinary package outside dated snapshot", pkg))
  }
}
missing_geo <- setdiff(names(GEO_PINS), keys)
if (length(missing_geo)) problems <- c(problems, paste("missing geospatial packages", paste(missing_geo, collapse = ",")))
if (length(problems)) stop("MANIFEST GATE FAILED: ", paste(unique(problems), collapse = "; "), call. = FALSE)

cat(sprintf("OK: manifest records %d files, %d packages, pinned R and exact geospatial provenance.\n",
            length(check$files), length(keys)))
