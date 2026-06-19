#!/usr/bin/env Rscript
# ===========================================================================
# precompute.R — rebuild the cross-site national index cache.
#
# Run after refresh_data.R changes data/sites/*.rds (refresh_data.R calls this
# automatically as its final step). It sources the app's global.R so it uses the
# EXACT same builders the app does — no risk of the cache drifting from the
# runtime code — then forces a fresh, fingerprinted write of data/precomputed.rds
# so the deployed app boots instantly and never serves an ordination, indicator
# table, or site index out of sync with the bundles.
#
#   Rscript scripts/precompute.R
# ===========================================================================

suppressMessages(suppressWarnings(source("global.R")))

idx <- build_national_index()                       # the real builder, same as the app
saveRDS(idx, PRECOMP_FILE, compress = "xz")         # carries idx$fingerprint

cat(sprintf("precomputed.rds rebuilt: %d sites · ordination %s · indicators %s · %.3f MB\n",
            length(idx$sites),
            if (is.null(idx$ordination)) "—" else paste0(nrow(idx$ordination), " pts"),
            if (is.null(idx$indicators)) "—" else paste0(nrow(idx$indicators), " spp"),
            file.size(PRECOMP_FILE) / 1e6))
cat(sprintf("fingerprint: %s\n", substr(idx$fingerprint, 1, 72)))
