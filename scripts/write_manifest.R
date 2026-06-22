# ===========================================================================
# write_manifest.R — (re)generate manifest.json for Posit Connect Cloud.
#
# RUN THIS after ANY change to runtime dependencies or the committed data set,
# then COMMIT manifest.json — Connect Cloud reads the committed manifest, so a
# stale manifest restores the OLD package set or serves yesterday's data.
#
#   Rscript scripts/write_manifest.R
#
# The appFiles set is scoped to the app sources only: global/ui/server + R/ +
# www/ + data/*.rds (recursive: data/sites + data/env) + data-sample. scripts/
# is DELIBERATELY excluded so neonUtilities (a refresh-only dependency, referenced
# in global.R via a split string + requireNamespace) can never be scanned into the
# manifest — the deployed app runs off the committed bundles, never a live fetch.
#
# HARD GATE: after writing, this parses manifest.json and stop()s with a non-zero
# error if neonUtilities / arrow / data.table appears as a package key, so a
# leaked (heavy) manifest can never commit silently.
# ===========================================================================
if (!requireNamespace("rsconnect", quietly = TRUE)) stop("install.packages('rsconnect') first")
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite') first")

app_files <- c(
  "global.R", "ui.R", "server.R",
  list.files("R",           full.names = TRUE, recursive = TRUE),
  list.files("www",         full.names = TRUE, recursive = TRUE),
  list.files("data",        full.names = TRUE, recursive = TRUE),
  list.files("data-sample", full.names = TRUE, recursive = TRUE)
)
app_files <- app_files[file.exists(app_files)]

rsconnect::writeManifest(appDir = ".", appFiles = app_files)

m    <- jsonlite::fromJSON("manifest.json")
pkgs <- names(m$packages)
cat(sprintf("manifest.json written: %d app files, %d packages.\n",
            length(app_files), length(pkgs)))

# HARD GATE. neonUtilities + arrow are the heavy refresh-only / fetch deps that
# must NEVER reach a runtime deploy — their presence means the global.R guard
# (split string + requireNamespace) failed or scripts/ leaked into appFiles.
banned <- c("neonUtilities", "arrow", "data.table")
hit    <- banned[tolower(banned) %in% tolower(pkgs)]

# data.table is a GENUINE hard Imports dependency of plotly (a runtime package
# here), so when plotly is in the manifest, data.table is legitimately required
# and is NOT a leak. Only treat it as a leak when plotly is absent (i.e. it crept
# in some other way). neonUtilities/arrow are never excused.
if ("data.table" %in% tolower(hit) && "plotly" %in% tolower(pkgs)) {
  hit <- setdiff(hit, "data.table")
  cat("note: data.table is present as a runtime Imports dependency of plotly (expected, not a leak).\n")
}

if (length(hit)) {
  stop(sprintf(
    "manifest.json leaked a heavy/refresh-only package: %s. A lean Connect deploy must NOT carry it. Check the global.R guard (neonUtilities must stay behind a split string + requireNamespace) and that scripts/ is excluded from appFiles.",
    paste(hit, collapse = ", ")))
}
cat("OK: manifest is lean (no neonUtilities / arrow; data.table only via plotly).\n")
