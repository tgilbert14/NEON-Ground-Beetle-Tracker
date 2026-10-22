#!/usr/bin/env Rscript
# Regression test for the boot skip and the deep-link / remembered-site restore
# (2026-10-18 audit item 17). shiny::testServer drives the real server function;
# the browser is simulated by setting inputs in the orders a client can deliver
# them (MockShinySession never applies updateSelectInput, so each test sets the
# cascade inputs itself, exactly as the browser would after the update).
#
#   Rscript --vanilla scripts/test_server_restore.R

Sys.setenv(GBT_LIVE = "0")
suppressMessages(suppressWarnings(source("global.R")))
server_fn <- source("server.R")$value
stopifnot(is.function(server_fn))

assert <- function(ok, msg) {
  if (!isTRUE(ok)) stop(msg, call. = FALSE)
}

# Count completed loads per site. load_site_env() is called only from load_site(),
# after the bundle has loaded, so wrapping it here (test only, never app code)
# counts real loads without touching the app.
loads <- character(0)
real_load_site_env <- load_site_env
assign("load_site_env", function(site, ...) {
  loads <<- c(loads, site)
  real_load_site_env(site, ...)
}, envir = globalenv())

run_case <- function(label, steps) {
  loads <<- character(0)
  out <- NULL
  suppressWarnings(suppressMessages(shiny::testServer(server_fn, {
    steps(session)
    out <<- list(site = rv$siteCode, loads = loads)
  })))
  cat(sprintf("  %-52s siteCode=%s loads=[%s]\n", label,
              if (is.null(out$site)) "NULL" else out$site, paste(out$loads, collapse = ",")))
  out
}

cat("Server boot / restore cases:\n")

# (i) boot cascade only: the national picker stays the front door.
r1 <- run_case("(i) boot cascade only", function(session) {
  session$setInputs(stateSel = "AZ")
  session$setInputs(site = "SRER")
})
assert(is.null(r1$site) && !length(r1$loads), "(i) the boot cascade alone must not load a site")

# (ii) restore arrives before the cascade, then the cascade lands on the restore.
r2 <- run_case("(ii) restore CPER before cascade", function(session) {
  session$setInputs(restore_site = "CPER")
  session$setInputs(stateSel = "CO")
  session$setInputs(site = "CPER")
})
assert(identical(r2$site, "CPER") && identical(r2$loads, "CPER"),
       "(ii) a restore that arrives first must load CPER once")

# (iii) the boot cascade lands first, then the restore moves the cascade.
r3 <- run_case("(iii) cascade SRER, then restore CPER", function(session) {
  session$setInputs(stateSel = "AZ")
  session$setInputs(site = "SRER")
  session$setInputs(restore_site = "CPER")
  session$setInputs(stateSel = "CO")
  session$setInputs(site = "CPER")
})
assert(identical(r3$site, "CPER") && identical(r3$loads, "CPER"),
       "(iii) a restore after the boot cascade must load CPER once")

# (iv) restore names the site the cascade already selected: no input change fires,
# so the restore observer must load it directly, once.
r4 <- run_case("(iv) cascade SRER, then restore SRER", function(session) {
  session$setInputs(stateSel = "AZ")
  session$setInputs(site = "SRER")
  session$setInputs(restore_site = "SRER")
})
assert(identical(r4$site, "SRER") && identical(r4$loads, "SRER"),
       "(iv) restoring the already-selected site must load it exactly once")

# (v) after the boot skip, the popup Explore on the selected site loads it.
r5 <- run_case("(v) boot cascade, then Explore SRER", function(session) {
  session$setInputs(stateSel = "AZ")
  session$setInputs(site = "SRER")
  session$setInputs(siteExplore = "SRER")
})
assert(identical(r5$site, "SRER") && identical(r5$loads, "SRER"),
       "(v) Explore on the already-selected site must load it exactly once")

cat("OK: Ground Beetle boot skip and restore contracts passed.\n")
