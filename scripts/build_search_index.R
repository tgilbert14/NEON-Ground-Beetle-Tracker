#!/usr/bin/env Rscript
# ===========================================================================
# build_search_index.R — build the small, bundled "Search the network" index.
#
# Reads the COMMITTED per-site bundles (data/sites/*.rds) — NO live fetch — and
# writes data/search_index.rds, a tiny .rds the app loads once at boot (like the
# precompute cache) and filters in memory. Two tables:
#
#   $taxa  — one row per (taxon × site): scientificName, taxonID, taxonRank,
#            siteID + site name/state, the per-site MEASURE (activity-density =
#            catch per 100 trap-nights), individuals, the site trap-night effort,
#            year_min/year_max, is_introduced, species_level.
#   $sites — the site-level table (reused from the precompute site_index) so the
#            threshold query ("activity-density > X", "introduced species & where")
#            and the go-to-site jump have site metadata to hand.
#
# Activity-density is the app's honest within-site effort-normalised unit
# (100 × individualCount / trap-nights summed over unique plot×bout), NOT an
# absolute density — labelled as such in the UI. It is the SAME `cpn` the rest
# of the app uses (community_table / annual_trend).
#
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" scripts/build_search_index.R
# ===========================================================================

suppressMessages(suppressWarnings(source("global.R")))

sites <- available_sites()
if (!length(sites)) stop("no bundled sites found in data/sites/ — run scripts/refresh_data.R first")

taxa_rows <- list()
for (s in sites) {
  d <- load_site_bundle(s)
  if (is.null(d) || !nrow(d)) next
  tn <- effort_trapnights(d)                       # site total trap-night effort
  meta <- neon_sites[neon_sites$site == s, , drop = FALSE]

  # one row per (taxon × site): sum individuals, earliest/latest year, rank.
  agg <- d %>%
    dplyr::group_by(.data$scientificName, .data$taxonID) %>%
    dplyr::summarise(
      individuals   = sum(.data$individualCount, na.rm = TRUE),
      year_min      = suppressWarnings(min(.data$year, na.rm = TRUE)),
      year_max      = suppressWarnings(max(.data$year, na.rm = TRUE)),
      species_level = any(.data$species_level %in% TRUE),
      taxonRank     = .data$taxonRank[1],
      .groups = "drop")
  if (!nrow(agg)) next
  agg$year_min[!is.finite(agg$year_min)] <- NA_integer_
  agg$year_max[!is.finite(agg$year_max)] <- NA_integer_

  agg$siteID    <- s
  agg$site_name <- if (nrow(meta)) meta$name  else s
  agg$state     <- if (nrow(meta)) meta$state else NA_character_
  # activity-density = catch per 100 trap-nights (within-site index, NOT absolute)
  agg$activity_density <- if (is.finite(tn) && tn > 0)
    round(100 * agg$individuals / tn, 2) else NA_real_
  agg$trapnights   <- tn
  agg$is_introduced <- is_introduced(agg$scientificName)
  taxa_rows[[s]] <- agg
}

taxa <- dplyr::bind_rows(taxa_rows)
taxa <- taxa[, c("scientificName", "taxonID", "taxonRank", "species_level",
                 "siteID", "site_name", "state",
                 "activity_density", "individuals", "trapnights",
                 "year_min", "year_max", "is_introduced")]
taxa <- taxa[order(taxa$scientificName, -taxa$activity_density %in% NA,
                   dplyr::desc(taxa$activity_density)), , drop = FALSE]

# Site-level table for the threshold query + go-to-site jump (reuse precompute).
site_tab <- SITE_INDEX

idx <- list(
  taxa        = tibble::as_tibble(taxa),
  sites       = tibble::as_tibble(site_tab),
  fingerprint = precompute_fingerprint(),
  built       = as.character(Sys.time()))

out <- file.path("data", "search_index.rds")
saveRDS(idx, out, compress = "xz")

cat(sprintf("search_index.rds written: %d taxon×site rows · %d distinct taxa · %d sites · %.3f MB\n",
            nrow(idx$taxa), dplyr::n_distinct(idx$taxa$scientificName),
            dplyr::n_distinct(idx$taxa$siteID), file.size(out) / 1e6))
cat(sprintf("  introduced taxon×site rows: %d (%d distinct introduced spp)\n",
            sum(idx$taxa$is_introduced),
            dplyr::n_distinct(idx$taxa$scientificName[idx$taxa$is_introduced])))
