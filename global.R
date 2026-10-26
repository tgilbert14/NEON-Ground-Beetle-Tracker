# ===========================================================================
# NEON Ground Beetle Tracker — global.R
# Loaded once per session: libraries, theme, helpers, and the bundled data.
#
# Sibling app to the NEON Small Mammal Tracker, same Desert Data Labs house
# style and bundle-first data pattern, but for ground beetles (Carabidae),
# NEON data product DP1.10022.001 — "Ground beetles sampled from pitfall traps".
# ===========================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(bsicons)
  library(dplyr)
  library(tidyr)
  library(plotly)
  library(leaflet)
  library(DT)
  library(shinyjs)
  library(shinycssloaders)
  library(RColorBrewer)
  library(htmltools)
})

# ---- basemap --------------------------------------------------------------
# CARTO watermarks unauthenticated basemaps.cartocdn.com raster tiles ("API KEY
# REQUIRED", since 2026-08-26; suite record: NEON-Driver-Cascade
# docs/SUITE-BASEMAP-INCIDENT-2026-08.md). The key rides in the tile URL, so it
# is a public rate-limited identifier, not a credential; Sys.getenv keeps it out
# of git and makes rotation a Connect Cloud setting. addProviderTiles() cannot
# carry it (the bundled CartoDB template has no {apikey} slot), hence addTiles().
# Without the key this falls back to Esri's keyless grey canvas — clean, but
# content-free past z16 at rural sites, so the cap keeps the zoom control honest.
add_suite_basemap <- function(map, variant = "light_all", noWrap = FALSE) {
  key <- Sys.getenv("CARTO_BASEMAP_KEY", "")
  if (nzchar(key)) {
    leaflet::addTiles(map,
      urlTemplate = sprintf(
        "https://{s}.basemaps.cartocdn.com/%s/{z}/{x}/{y}{r}.png?key=%s", variant, key),
      attribution = paste(
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
        '&copy; <a href="https://carto.com/attributions">CARTO</a>'),
      options = leaflet::tileOptions(subdomains = "abcd", maxZoom = 20, noWrap = noWrap))
  } else {
    leaflet::addTiles(map,
      urlTemplate = sprintf(
        "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_%s_Gray_Base/MapServer/tile/{z}/{y}/{x}",
        if (identical(variant, "dark_all")) "Dark" else "Light"),
      attribution = 'Tiles &copy; Esri: Esri, HERE, Garmin, &copy; OpenStreetMap contributors',
      options = leaflet::tileOptions(maxNativeZoom = 16, maxZoom = 19, noWrap = noWrap))
  }
}

# ---- helpers + metadata ---------------------------------------------------
source("R/site_metadata.R", local = FALSE)
source("R/helpers.R", local = FALSE)
source("R/seasonal_env.R", local = FALSE) # the cascade's seasonal-aggregate driver read (beetles: lag-0 fast responder)
source("R/map_picker.R", local = FALSE)   # reusable national site-picker map (flagship front door)

# ---- NEON data product ----------------------------------------------------
NEON_DPID <- "DP1.10022.001"   # Ground beetles sampled from pitfall traps

# ---- live-fetch toggle (optional; bundle-first like the mammal app) --------
# Live downloads are OPTIONAL. neonUtilities is referenced by a computed name so
# the rsconnect/renv scanner doesn't pin it; the deployed showcase is bundle-only.
.NEON_PKG <- paste0("neon", "Utilities")
# An empty GBT_LIVE (for example a copied .env.example) counts as unset.
.gbt_live <- Sys.getenv("GBT_LIVE", "")
LIVE_FETCH <- (!nzchar(.gbt_live) || .gbt_live != "0") &&
  requireNamespace(.NEON_PKG, quietly = TRUE)

# ---- bundled per-site data ------------------------------------------------
# scripts/refresh_data.R pre-downloads + aggregates each site's carabid record
# into data/sites/<SITE>.rds (a tidy long table). The app loads it instantly.
SITE_DIR <- "data/sites"

# Illustrative demo bundle (clearly badged in the UI as NOT real NEON data) so
# the app is fully demonstrable without a live pull. Real data/sites/*.rds win.
BEETLE_DEMO <- local({
  f <- "data-sample/beetle_demo.csv"
  if (!file.exists(f)) return(NULL)
  d <- tryCatch(utils::read.csv(f, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(d) || !nrow(d)) return(NULL)
  tibble::as_tibble(d)
})

# Read a site's bundle (real first, then demo), tagged with its source.
load_site_bundle <- function(site) {
  if (is.null(site) || site == "") return(NULL)
  f <- file.path(SITE_DIR, paste0(site, ".rds"))
  if (file.exists(f)) {
    d <- clean_beetle(readRDS(f)); attr(d, "source") <- "neon"; return(d)
  }
  if (!is.null(BEETLE_DEMO) && "siteID" %in% names(BEETLE_DEMO)) {
    sub <- BEETLE_DEMO[BEETLE_DEMO$siteID == site, , drop = FALSE]
    if (nrow(sub)) { d <- clean_beetle(sub); attr(d, "source") <- "demo"; return(d) }
  }
  NULL
}

# Filter a cleaned table to a [start, end] date window.
filter_window <- function(d, start_date, end_date) {
  if (is.null(d) || !"date" %in% names(d)) return(d)
  lo <- as.Date(start_date); hi <- as.Date(end_date)
  d[!is.na(d$date) & d$date >= lo & d$date <= hi, , drop = FALSE]
}

# Which sites have any data (real bundle or demo) — drives the picker + map.
available_sites <- function() {
  bundled <- sub("\\.rds$", "", list.files(SITE_DIR, pattern = "\\.rds$"))
  demo <- if (!is.null(BEETLE_DEMO)) unique(BEETLE_DEMO$siteID) else character(0)
  sort(unique(c(bundled, demo)))
}

# ---- environmental overlays (co-located NEON products) --------------------
# Reused verbatim from the Small Mammal Tracker: the SAME monthly per-site env
# bundles (data/env/<SITE>.rds — precip / air temp / plant phenology) work here,
# because beetle and mammal sites are the same NEON terrestrial network. The
# registry the UI + plots read; `lead` flags drivers expected to LEAD activity.
ENV_DIR <- "data/env"
# `fillable` = the driver is non-negative, so the overlay can fill the area to
# zero and the y2 axis can be anchored at 0. Temperature can go BELOW zero
# (HARV winters), where a to-zero fill and a forced-zero axis are meaningless and
# visually invert the encoding — so temp draws as a plain line on a free axis.
ENV_LAYERS <- list(
  precip  = list(col = "precip_mm",     label = "Precipitation",       unit = "mm/mo",
                 dpid = "DP1.00044.001", agg = "sum",   color = "#2f7fb5", lead = TRUE,  dig = 0, fillable = TRUE),
  temp    = list(col = "temp_c",        label = "Air temperature",     unit = "°C",
                 dpid = "DP1.00002.001", agg = "mean",  color = "#d9480f", lead = FALSE, dig = 1, fillable = FALSE),
  flower  = list(col = "flowering_pct", label = "Plants flowering",    unit = "% in flower",
                 dpid = "DP1.10055.001", agg = "share", color = "#d6336c", lead = TRUE,  dig = 0, fillable = TRUE),
  greenup = list(col = "greenup_pct",   label = "Green-up (leaf-out)", unit = "% leafing out",
                 dpid = "DP1.10055.001", agg = "share", color = "#2f9e44", lead = TRUE,  dig = 0, fillable = TRUE),
  fruit   = list(col = "fruiting_pct",  label = "Plants fruiting",     unit = "% in fruit",
                 dpid = "DP1.10055.001", agg = "share", color = "#9c6644", lead = TRUE,  dig = 0, fillable = TRUE)
)
# Overlay-picker choices: only layers that actually have data for the loaded site.
env_layer_choices <- function(env) {
  base <- c("None" = "none")
  if (is.null(env) || !nrow(env)) return(base)
  have <- vapply(names(ENV_LAYERS), function(k) {
    col <- ENV_LAYERS[[k]]$col
    # same coverage floor the driver dredge uses, so the overlay picker never offers
    # a near-empty driver (e.g. fruiting_pct, ~15 months) the ranking has dropped.
    col %in% names(env) && env_has_min_coverage(env[[col]])
  }, logical(1))
  if (!any(have)) return(base)
  labs <- vapply(ENV_LAYERS[have], function(m) sprintf("%s (%s)", m$label, m$unit), character(1))
  c(base, stats::setNames(names(ENV_LAYERS)[have], labs))
}
ENV_DEMO <- local({
  f <- "data-sample/env_demo.csv"
  if (!file.exists(f)) return(NULL)
  d <- tryCatch(utils::read.csv(f, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(d) || !nrow(d)) return(NULL)
  tibble::as_tibble(d)
})
# Load a site's monthly env table, or NULL. Real bundle first, then demo fallback.
load_site_env <- function(site) {
  if (is.null(site) || site == "") return(NULL)
  f <- file.path(ENV_DIR, paste0(site, ".rds"))
  if (file.exists(f)) {
    e <- tryCatch(readRDS(f), error = function(e) NULL)
    if (!is.null(e) && nrow(e)) { e$date <- as.Date(e$date); attr(e, "source") <- "neon"; return(tibble::as_tibble(e)) }
  }
  if (!is.null(ENV_DEMO) && "siteID" %in% names(ENV_DEMO)) {
    e <- ENV_DEMO[ENV_DEMO$siteID == site, , drop = FALSE]
    if (nrow(e)) { e$date <- as.Date(e$date); attr(e, "source") <- "demo"; return(tibble::as_tibble(e)) }
  }
  NULL
}

# ---- cross-site national views (computed once, cached) --------------------
# Four objects power the Biogeography map, PCoA ordination, indicator table and
# species range picker. Building them scans every bundled site and runs the
# Bray-Curtis ordination + IndVal, so the result is cached to data/precomputed.rds
# and reused on later boots — an instant cold start instead of a multi-second one.
# Committed alongside the bundle, it makes the DEPLOYED app boot fast too.
#
# The cache auto-invalidates at cold boot: it is rebuilt whenever the set of
# bundled sites changes, or any bundle's md5 differs from the fingerprint stored
# in the cache (see precompute_fingerprint / cache_is_fresh). Authoritatively, a
# data refresh always force-rebuilds it via scripts/precompute.R, so the cache is
# never left out of sync with data/sites/ after a refresh.
PRECOMP_FILE <- file.path("data", "precomputed.rds")

# A content fingerprint of the bundle: sorted "<file>:<md5>" over every site rds.
# file.mtime was the old freshness signal, but git does NOT preserve mtimes — on
# a fresh Connect Cloud checkout that made the cache either rebuild every cold
# boot or (worse) trust a stale file. We hash the .rds bundles instead: they are
# BINARY (git stores them byte-for-byte, no line-ending munging), so the md5 is
# identical across clones AND changes whenever a bundle's content changes — even
# an in-place edit that preserves byte size. Reading 46 xz bundles (~0.7 MB total)
# to md5 them is sub-50 ms, and only happens when a fingerprinted cache exists.
# The demo CSV is deliberately NOT hashed: it is a text file (line-ending /
# autocrlf sensitive, so not clone-stable), and demo sites already show up in
# available_sites(), so adding/removing one is caught by the site-set check below.
precompute_fingerprint <- function() {
  rds <- sort(list.files(SITE_DIR, pattern = "\\.rds$", full.names = TRUE))
  if (!length(rds)) return("")
  sums <- unname(tools::md5sum(rds))
  paste(sprintf("%s:%s", basename(rds), sums), collapse = "|")
}

build_national_index <- function() {
  sites <- available_sites()
  empty <- list(sites = character(0), site_index = NULL, ordination = NULL,
                indicators = NULL, species_sites = NULL, fingerprint = precompute_fingerprint())
  if (!length(sites)) return(empty)
  # one pass over the bundles: per-site headline row + a bound all-sites table
  rows <- list(); all <- list()
  for (s in sites) {
    d <- load_site_bundle(s); if (is.null(d) || !nrow(d)) next
    meta <- neon_sites[neon_sites$site == s, , drop = FALSE]
    rows[[s]] <- site_index_row(d, s, meta)
    d$siteID <- s; all[[s]] <- d
  }
  all_data <- if (!length(all)) NULL else dplyr::bind_rows(all)
  list(
    sites         = sites,
    site_index    = if (!length(rows)) NULL else dplyr::bind_rows(rows),
    ordination    = if (!is.null(all_data)) bray_ordination(all_data) else NULL,
    indicators    = if (!is.null(all_data)) indicator_species(all_data) else NULL,
    species_sites = if (!is.null(all_data)) species_site_table(all_data) else NULL,
    fingerprint   = precompute_fingerprint())
}

# Is a cached index still valid for the current bundle?
cache_is_fresh <- function(idx) {
  if (is.null(idx) || is.null(idx$sites)) return(FALSE)
  if (!setequal(idx$sites, available_sites())) return(FALSE)
  fp <- idx$fingerprint
  # legacy cache (built before fingerprints existed): a matching site set is the
  # best we can check — accept it rather than rebuilding on every cold boot. The
  # next scripts/precompute.R run writes a fingerprinted cache and this goes strict.
  if (is.null(fp)) return(TRUE)
  identical(fp, precompute_fingerprint())
}

NATIONAL_INDEX <- local({
  cached <- if (file.exists(PRECOMP_FILE))
    tryCatch(readRDS(PRECOMP_FILE), error = function(e) NULL) else NULL
  if (cache_is_fresh(cached)) return(cached)
  idx <- build_national_index()
  tryCatch(saveRDS(idx, PRECOMP_FILE, compress = "xz"), error = function(e) NULL)  # read-only deploy: just recompute next boot
  idx
})

SITE_INDEX    <- NATIONAL_INDEX$site_index
ORDINATION    <- NATIONAL_INDEX$ordination
INDICATORS    <- NATIONAL_INDEX$indicators
SPECIES_SITES <- NATIONAL_INDEX$species_sites

# national site-picker table for the splash map (dot size = species richness,
# colour = total individuals). Drops coord-less sites so the map can't blank.
picker_site_table <- if (!is.null(SITE_INDEX))
  SITE_INDEX[is.finite(SITE_INDEX$lat) & is.finite(SITE_INDEX$lng), , drop = FALSE] else NULL

# ---- "Search the network" index (small, bundled, precomputed) -------------
# data/search_index.rds (scripts/build_search_index.R) is a tiny table the
# "Search" tab filters in memory: one row per (taxon × site) with the within-site
# activity-density measure + years + an is_introduced flag. Loaded once at boot,
# like the precompute cache. If absent (never built), the tab falls back to the
# live SPECIES_SITES table so it still works, just without the years/measure.
SEARCH_INDEX <- local({
  f <- file.path("data", "search_index.rds")
  if (file.exists(f)) tryCatch(readRDS(f), error = function(e) NULL) else NULL
})
SEARCH_TAXA <- if (!is.null(SEARCH_INDEX)) SEARCH_INDEX$taxa else NULL

# ---- release identity of the bundle ----------------------------------------
# data/release.rds (scripts/record_release.R) names the one NEON release the
# bundle is pinned to: release tag, generation date, DOI, citation, data-through
# date and site count. NULL when absent, so the app still boots without it.
BUNDLE_RELEASE <- tryCatch(readRDS(file.path("data", "release.rds")), error = function(e) NULL)

# ---- runtime build digest ---------------------------------------------------
# A short content digest of the files that decide what the deployed app shows.
# DDL_BUILD is the first 12 hex characters of the md5 of the concatenated md5
# hex of each file below, in this order, with no separators and no newline; a
# missing file contributes the literal "missing". scripts/build_digest.sh prints
# the same value from a shell, so a deployed build can be matched to a commit.
# Keep this list and the array in scripts/build_digest.sh identical. After the
# fixed list come every data/env/*.rds bundle, sorted by name in C order (the
# Small Mammal sync step can change them).
DDL_DIGEST_FILES <- c("global.R", "ui.R", "server.R", "R/helpers.R", "R/map_picker.R",
                      "R/report_pdf.R", "R/seasonal_env.R", "R/site_metadata.R",
                      "www/styles.css", "www/pincards.js", "data/precomputed.rds",
                      "data/search_index.rds", "data/release.rds",
                      file.path("data/env", sort(list.files("data/env", pattern = "[.]rds$"),
                                                 method = "radix")))
DDL_BUILD <- local({
  sums <- vapply(DDL_DIGEST_FILES, function(f) {
    if (file.exists(f)) tolower(unname(tools::md5sum(f))) else "missing"
  }, character(1))
  tmp <- tempfile("ddl-digest-")
  on.exit(unlink(tmp), add = TRUE)
  cat(sums, file = tmp, sep = "")
  substr(tolower(unname(tools::md5sum(tmp))), 1, 12)
})

# Autocomplete choices for the Search tab: every taxon in the index, labelled with
# how many sites it occurs at so the picker doubles as a quick range hint.
search_taxon_choices <- function() {
  if (is.null(SEARCH_TAXA) || !nrow(SEARCH_TAXA)) return(NULL)
  sp <- SEARCH_TAXA %>% dplyr::group_by(.data$scientificName) %>%
    dplyr::summarise(sites = dplyr::n_distinct(.data$siteID),
                     inds = sum(.data$individuals, na.rm = TRUE), .groups = "drop") %>%
    dplyr::arrange(dplyr::desc(.data$sites), dplyr::desc(.data$inds))
  stats::setNames(sp$scientificName, sprintf("%s · %d site%s", sp$scientificName,
                  sp$sites, ifelse(sp$sites == 1, "", "s")))
}

species_choices <- function() {
  if (is.null(SPECIES_SITES)) return(NULL)
  sp <- SPECIES_SITES %>% dplyr::group_by(.data$scientificName) %>%
    dplyr::summarise(sites = dplyr::n(), inds = sum(.data$individualCount), .groups = "drop") %>%
    dplyr::arrange(dplyr::desc(.data$sites), dplyr::desc(.data$inds))
  stats::setNames(sp$scientificName, sprintf("%s · %d site%s", sp$scientificName,
                  sp$sites, ifelse(sp$sites == 1, "", "s")))
}

# ---- live NEON fetch (optional) -------------------------------------------
# Pulls DP1.10022.001, reconciles parataxonomist with authoritative expert IDs,
# and normalises to the app's long schema (one row per plot/bout/species).
fetch_neon_beetles <- function(site, start_date, end_date) {
  if (!requireNamespace(.NEON_PKG, quietly = TRUE))
    stop("Live NEON download needs the neonUtilities package, which isn't in this build.")
  loadByProduct <- get("loadByProduct", envir = asNamespace(.NEON_PKG))
  raw <- loadByProduct(dpID = NEON_DPID, site = site,
                       startdate = format(as.Date(start_date), "%Y-%m"),
                       enddate   = format(as.Date(end_date), "%Y-%m"),
                       package = "basic", check.size = "F",
                       token = Sys.getenv("NEON_TOKEN", unset = ""))
  assemble_beetles(raw)   # see scripts/refresh_data.R for the shared assembler
}

# ---- theme (Desert Data Labs DESERT-NIGHT house style) --------------------
# Key NAMES kept (server.R references DDL$forest/$gold2/etc.), VALUES remapped to
# the desert-night creative system (teal/coral/gold on a dark sky) so the charts
# re-theme from one edit. `forest` (the beetle primary) -> teal. The app DEFAULTS
# to LIGHT (ui.R input_dark_mode mode="light"); styles.css carries the full
# desert-day base + the [data-bs-theme="dark"] desert-night system. The PDF
# report keeps the LIGHT house palette (see R/report_pdf.R — it prints on paper).
DDL <- list(
  navy = "#12241a", navy2 = "#1b3a28", cardinal = "#d98a3c", gold = "#ffd24a",
  gold2 = "#e0b43a", sky = "#2f93a0", green = "#6ef0b0", forest = "#36d98a",
  ink = "#e9f6ee", muted = "#9fc0ad", bg = "#07100b", paper = "#12241a",
  line = "rgba(255,255,255,0.12)"
)

# Light "desert-day" base (DEFAULT). styles.css [data-bs-theme="dark"] carries the
# full desert-night system; the toggle defaults to light, so this is what shows.
# Rubik is named as a plain CSS family, never as font_google("Rubik"). The app does
# not fetch web fonts: a visitor with Rubik installed can use it, while every other
# client and every offline/restricted host falls through to the local UI stack.
rubik_stack <- bslib::font_collection(
  "Rubik", "system-ui", "-apple-system", "Segoe UI", "Roboto", "Helvetica Neue", "Arial", "sans-serif")
app_theme <- bs_theme(
  version = 5, bg = "#ffffff", fg = "#16243a",
  # primary/secondary/success carry white button text: each clears WCAG AA 4.5:1
  # (#1a7a4f 5.33:1, #9a5a1c 5.45:1).
  primary = "#1a7a4f", secondary = "#9a5a1c",
  success = "#1a7a4f", info = "#2f93a0", warning = "#c79a1c", danger = "#c47a2c",
  base_font = rubik_stack, heading_font = rubik_stack,
  "border-radius" = "10px"
)

# ---- small UI utilities (shared by ui.R and server.R) ---------------------
spin <- function(x) shinycssloaders::withSpinner(x, color = DDL$forest,
                                                 proxy.height = "300px", hide.ui = FALSE)

info_pop <- function(title, ..., placement = "auto")
  bslib::popover(tags$span(class = "info-dot", `aria-label` = paste("About:", title),
                           bsicons::bs_icon("info-circle")),
                 ..., title = title, placement = placement)

# Says whether a card shows the loaded site or every bundled site. The count
# comes from SITE_INDEX so it follows the bundle.
scope_chip <- function(all = FALSE) {
  n <- if (!is.null(SITE_INDEX)) nrow(SITE_INDEX) else 0L
  tags$span(class = paste("scope-chip", if (all) "scope-all" else "scope-site"),
            if (all) sprintf("All %d sites", n) else "This site")
}

# modalDialog() renders its title in a plain h4 and gives the dialog no name.
# This wraps the title in an id'd span (or uses `label_id` for a heading already
# in the body) and points the dialog's aria-labelledby at it.
labelled_modal <- function(..., title = NULL, label_id = "gbt-modal-title") {
  m <- shiny::modalDialog(..., title = if (!is.null(title)) tags$span(id = label_id, title))
  htmltools::tagAppendAttributes(m, `aria-labelledby` = label_id)
}

# ---- release identity for display ------------------------------------------
# Every value comes from BUNDLE_RELEASE (data/release.rds); each helper returns a
# usable fallback when the file is absent.
release_tag <- function() {
  r <- BUNDLE_RELEASE$release
  if (is.character(r) && length(r) == 1 && nzchar(r)) r else NA_character_
}
release_doi <- function() {
  d <- BUNDLE_RELEASE$doi
  if (is.character(d) && length(d) == 1 && nzchar(d)) d else NA_character_
}
release_through <- function() {
  x <- tryCatch(as.Date(BUNDLE_RELEASE$data_through), error = function(e) NA)
  if (length(x) == 1 && !is.na(x)) x else as.Date(NA)
}
release_through_label <- function(fmt = "%B %Y") {
  x <- release_through(); if (is.na(x)) NA_character_ else format(x, fmt)
}
release_citation <- function() {
  c0 <- BUNDLE_RELEASE$citation
  if (is.character(c0) && length(c0) == 1 && nzchar(c0)) c0 else
    "NEON (National Ecological Observatory Network). Ground beetles sampled from pitfall traps (DP1.10022.001)."
}
# "Release: RELEASE-2026 (DOI); provisional records not included; data through <date>"
release_line_ui <- function() {
  rel <- release_tag(); doi <- release_doi(); thr <- release_through_label("%d %B %Y")
  if (is.na(rel)) return(tags$p(class = "release-line",
    "Release: NEON's released data for DP1.10022.001; provisional records not included."))
  esc <- htmltools::htmlEscape
  doi_html <- if (!is.na(doi)) sprintf(' (<a href="%s" target="_blank" rel="noopener">%s</a>)',
                                       esc(doi, attribute = TRUE), esc(sub("^https://doi.org/", "doi:", doi))) else ""
  tags$p(class = "release-line", HTML(sprintf(
    "<b>Release:</b> %s%s; provisional records not included%s.",
    esc(rel), doi_html, if (!is.na(thr)) paste0("; data through ", esc(thr)) else "")))
}
# Both "How current is this?" copies share this sentence.
release_currency_text <- function() {
  rel <- release_tag(); thr <- release_through()
  yr <- if (!is.na(thr)) format(thr, "%Y") else NA_character_
  first <- if (!is.na(rel) && !is.na(yr))
    sprintf("This uses NEON's yearly release (%s), which runs through the %s trapping season.", rel, yr)
  else "This uses NEON's yearly release of this product."
  paste(first, "NEON also posts newer provisional records, but their IDs can still change, so they stay out until a release includes them.")
}

# A small clickable "introduced" badge for non-native European carabids. Reuses
# the bslib popover so provenance and interpretation stay beside the label.
introduced_marker <- function(scientificName, placement = "auto")
  bslib::popover(
    tags$span(class = "intro-badge", title = "introduced. Click for why this matters",
              bsicons::bs_icon("globe-americas"), " introduced"),
    tags$p(tags$b(tags$em(scientificName)), " is an ", tags$b("introduced European carabid"),
           ", not native here."),
    tags$p("“Dominant” describes this pitfall catch only. The record adds non-native context but does not, by itself, diagnose habitat condition or site health."),
    title = "Introduced (non-native) species", placement = placement)

# state pickers reused from the mammal app's metadata
state_choices <- function() {
  sites <- available_sites()
  st <- neon_sites[neon_sites$site %in% sites, ]
  if (!nrow(st)) return(NULL)
  s <- sort(unique(st$state))
  stats::setNames(s, state_names[s] %||% s)
}
sites_in_state <- function(state) {
  sites <- available_sites()
  st <- neon_sites[neon_sites$site %in% sites & neon_sites$state == state, ]
  if (!nrow(st)) return(NULL)
  stats::setNames(st$site, sprintf("%s · %s", st$site, st$name))
}
site_label <- function(site) {
  m <- neon_sites[neon_sites$site == site, ]
  if (nrow(m)) sprintf("%s · %s", site, m$name) else site
}
site_bio <- function(site) {
  m <- neon_sites[neon_sites$site == site, ]
  if (nrow(m)) m$bio else NULL
}

# The app mascot — a flat (no-gradient, no-id so it's safely reusable) cute beetle
# in the carabid green/copper accent. Used as the loading spinner, the splash
# guide, and the celebration hop. Parts are classed so the CSS can wiggle the
# antennae (mascot-ear-l/-r) and blink the eyes (mascot-eyes).
MASCOT_CRITTER <- htmltools::HTML(paste0(
  '<svg class="mascot" viewBox="0 0 120 120" aria-hidden="true">',
  '<g class="mascot-ear-l"><path d="M50,40 Q40,22 32,16" fill="none" stroke="#d98a3c" stroke-width="3" stroke-linecap="round"/><circle cx="32" cy="16" r="4" fill="#e8a24a"/></g>',
  '<g class="mascot-ear-r"><path d="M70,40 Q80,22 88,16" fill="none" stroke="#d98a3c" stroke-width="3" stroke-linecap="round"/><circle cx="88" cy="16" r="4" fill="#e8a24a"/></g>',
  '<g stroke="#c47a2c" stroke-width="3" stroke-linecap="round"><path d="M30,62 L16,62"/><path d="M30,78 L18,88"/><path d="M90,62 L104,62"/><path d="M90,78 L102,88"/></g>',
  '<ellipse cx="60" cy="64" rx="31" ry="34" fill="#36d98a"/>',
  '<path d="M60,32 L60,96" stroke="#176b46" stroke-width="2" opacity=".5"/>',
  '<ellipse cx="60" cy="34" rx="14" ry="10" fill="#176b46"/>',
  '<g class="mascot-eyes"><circle cx="50" cy="58" r="6.5" fill="#0c2a1c"/><circle cx="70" cy="58" r="6.5" fill="#0c2a1c"/>',
  '<circle cx="48" cy="55.5" r="2.4" fill="#ffffff"/><circle cx="68" cy="55.5" r="2.4" fill="#ffffff"/></g>',
  '</svg>'))

# ---- the NEON suite registry (in-app sibling links) -----------------------
# The ten NEON explorers (the nine siblings plus this app, marked current), with
# the URLs of the suite registry. Rendered in the About panel and, before a site
# loads, under the landing picker, so every sibling is one tap away.
SUITE_SIBLINGS <- list(
  list(name = "NEON Cross-Product Response Atlas",   emoji = "\U0001F517", url = "https://tgilbert14.github.io/NEON-Driver-Cascade/",                  blurb = "How weather ripples up through plants, bugs, and animals."),
  list(name = "Small Mammals",    emoji = "\U0001F42D", url = "https://tgilbert14.github.io/NEON-Small-Mammal-Tracker-App/",        blurb = "Who's scurrying around each site, and how the populations shift."),
  list(name = "Breeding Birds",   emoji = "\U0001F426", url = "https://tgilbert14.github.io/NEON-Breeding-Birds/",                  blurb = "The dawn-chorus point counts, mapped and tracked over the years."),
  list(name = "Plant Diversity",  emoji = "\U0001F33F", url = "https://tgilbert14.github.io/NEON-Plant-Diversity/",                 blurb = "How many plant species share each plot, and which ones."),
  list(name = "Plant Phenology",  emoji = "\U0001F331", url = "https://tgilbert14.github.io/NEON-Plant-Phenology-Explorer/",        blurb = "When leaves, flowers, and fruit appear through the seasons."),
  list(name = "Veg Structure",    emoji = "\U0001F333", url = "https://tgilbert14.github.io/NEON-Vegetation-Structure-Explorer/",   blurb = "How tall and how dense the vegetation stands at each site."),
  list(name = "Water Chemistry",  emoji = "\U0001F4A7", url = "https://tgilbert14.github.io/NEON-WaterChemistry-Analyte-Viewer-App/", blurb = "What's dissolved in the streams, analyte by analyte."),
  list(name = "Mosquito Pulse",   emoji = "\U0001F99F", url = "https://tgilbert14.github.io/NEON-Mosquito-Pulse/",                  blurb = "When and where mosquitoes are active, by genus and sex."),
  list(name = "Little Inverts",   emoji = "\U0001F990", url = "https://tgilbert14.github.io/NEON-My-Little-Inverts/",              blurb = "The little animals on the bottom of NEON's streams, and the clean-water signal they carry."),
  list(name = "Ground Beetles",   emoji = "\U0001FAB2", url = "https://tgilbert14.github.io/NEON-Ground-Beetle-Tracker/",       blurb = "This app: ground beetles from NEON pitfall traps.", current = TRUE)
)

# The ten explorers as a card grid. The current app is a plain card (no link to
# itself). Used by the About tab and the landing's "More NEON explorers".
suite_sibling_grid <- function() {
  div(class = "suite-grid",
    lapply(SUITE_SIBLINGS, function(s) {
      body <- tagList(
        tags$span(class = "suite-emoji", `aria-hidden` = "true", s$emoji),
        div(class = "suite-card-body",
          div(class = "suite-name", s$name,
            if (isTRUE(s$current)) tags$span(class = "suite-here", "you are here")
            else bsicons::bs_icon("box-arrow-up-right")),
          div(class = "suite-blurb", s$blurb)))
      if (isTRUE(s$current)) div(class = "suite-card suite-current", `aria-current` = "page", body)
      else tags$a(class = "suite-card", href = s$url, target = "_blank", rel = "noopener", body)
    }))
}

# Server-side PDF site report (sourced last — needs DDL + helpers + ENV_LAYERS).
source("R/report_pdf.R", local = FALSE)

invisible(gc())
