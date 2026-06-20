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

# ---- helpers + metadata ---------------------------------------------------
source("R/site_metadata.R", local = FALSE)
source("R/helpers.R", local = FALSE)
source("R/map_picker.R", local = FALSE)   # reusable national site-picker map (flagship front door)

# ---- NEON data product ----------------------------------------------------
NEON_DPID <- "DP1.10022.001"   # Ground beetles sampled from pitfall traps

# ---- live-fetch toggle (optional; bundle-first like the mammal app) --------
# Live downloads are OPTIONAL. neonUtilities is referenced by a computed name so
# the rsconnect/renv scanner doesn't pin it; the deployed showcase is bundle-only.
.NEON_PKG <- paste0("neon", "Utilities")
LIVE_FETCH <- (Sys.getenv("GBT_LIVE", "1") != "0") &&
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
    col %in% names(env) && any(!is.na(env[[col]]))
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
    ct <- community_table(d)
    sp <- ct[ct$species_level %in% TRUE, , drop = FALSE]   # richness = species only
    meta <- neon_sites[neon_sites$site == s, , drop = FALSE]
    rows[[s]] <- tibble::tibble(
      site = s,
      name = if (nrow(meta)) meta$name else s,
      lat  = if (nrow(meta)) meta$lat else NA_real_,
      lng  = if (nrow(meta)) meta$lng else NA_real_,
      state = if (nrow(meta)) meta$state else NA_character_,
      richness = nrow(sp),
      individuals = sum(ct$individuals),
      dominant = if (nrow(sp)) sp$scientificName[1] else ct$scientificName[1],
      source = attr(d, "source") %||% "neon")
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

species_choices <- function() {
  if (is.null(SPECIES_SITES)) return(NULL)
  sp <- SPECIES_SITES %>% dplyr::group_by(.data$scientificName) %>%
    dplyr::summarise(sites = dplyr::n(), inds = sum(.data$individualCount), .groups = "drop") %>%
    dplyr::arrange(dplyr::desc(.data$sites), dplyr::desc(.data$inds))
  stats::setNames(sp$scientificName, sprintf("%s — %d site%s", sp$scientificName,
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
  navy = "#0e1d40", navy2 = "#1b2e5c", cardinal = "#fb8a7e", gold = "#ffd24a",
  gold2 = "#e0b43a", sky = "#43b8e8", green = "#5fb56a", forest = "#2dd4bf",
  ink = "#eaf2ff", muted = "#9fb0cf", bg = "#070d1f", paper = "#0e1d40",
  line = "rgba(255,255,255,0.12)"
)

# Light "desert-day" base (DEFAULT). styles.css [data-bs-theme="dark"] carries the
# full desert-night system; the toggle defaults to light, so this is what shows.
app_theme <- bs_theme(
  version = 5, bg = "#ffffff", fg = "#16243a",
  primary = "#149086", secondary = "#e0685a",
  success = "#3f9a52", info = "#2f8fc4", warning = "#d6a31c", danger = "#e0685a",
  base_font = font_google("Rubik"), heading_font = font_google("Rubik"),
  "border-radius" = "10px"
)

# ---- small UI utilities (shared by ui.R and server.R) ---------------------
spin <- function(x) shinycssloaders::withSpinner(x, color = DDL$forest,
                                                 proxy.height = "300px", hide.ui = FALSE)

info_pop <- function(title, ..., placement = "auto")
  bslib::popover(tags$span(class = "info-dot", bsicons::bs_icon("info-circle")),
                 ..., title = title, placement = placement)

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

# Server-side PDF site report (sourced last — needs DDL + helpers + ENV_LAYERS).
source("R/report_pdf.R", local = FALSE)

invisible(gc())
