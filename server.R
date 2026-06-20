# ===========================================================================
# NEON Ground Beetle Tracker — server.R
# Data flow + all outputs (community, diversity, seasonality, biogeography).
# ===========================================================================

function(input, output, session) {

  # ---- small plot helpers -------------------------------------------------
  # is the dark theme active? Driven by the sidebar input_dark_mode("colorMode").
  # Reading it inside the shared plot helpers makes every chart that calls them
  # take a reactive dependency on the toggle, so they re-render on theme switch.
  is_dark <- function() identical(input$colorMode, "dark")

  plotly_theme <- function(p, legend = TRUE) {
    dark <- is_dark()
    ink  <- if (dark) "#e7efe9" else "#1f2a30"
    grid <- if (dark) "rgba(220,235,225,0.10)" else "rgba(31,42,48,0.08)"
    zero <- if (dark) "rgba(220,235,225,0.22)" else "rgba(31,42,48,0.15)"
    legc <- if (dark) "#bcd0c4" else "#344049"
    p %>% plotly::layout(
      paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
      font = list(color = ink, family = "Rubik"),
      xaxis = list(gridcolor = grid, zerolinecolor = zero),
      yaxis = list(gridcolor = grid, zerolinecolor = zero),
      margin = list(l = 55, r = 30, t = 36, b = 46),
      showlegend = legend,
      legend = list(bgcolor = "rgba(0,0,0,0)", orientation = "h", x = 0.5, xanchor = "center",
                    y = -0.16, font = list(color = legc)),
      hoverlabel = list(bgcolor = if (dark) "rgba(14,29,64,0.96)" else "rgba(20,144,134,0.96)",
                        bordercolor = if (dark) "#36d98a" else "#ffd24a",
                        font = list(color = "#fff", family = "Rubik", size = 13))) %>%
      plotly::config(displayModeBar = FALSE, responsive = TRUE)
  }
  note_plot <- function(msg, icon = "\U0001FAB2") {
    plotly::plot_ly(type = "scatter", mode = "markers") %>% plotly::layout(
      paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
      xaxis = list(visible = FALSE), yaxis = list(visible = FALSE),
      annotations = list(list(text = paste0(icon, "<br>", msg), showarrow = FALSE,
        font = list(color = if (is_dark()) "#9fb0a6" else "#6b7a85", size = 15), align = "center"))) %>%
      plotly::config(displayModeBar = FALSE)
  }

  rv <- reactiveValues(data = NULL, label = NULL, pal = NULL, ctx = NULL)
  # Debounce the lag slider so dragging 0→12 doesn't fire 12 plotly re-renders.
  envLag_d <- debounce(reactive(input$envLag), 250)

  # ---- memoized heavy computes -------------------------------------------
  # Each depends only on the loaded data/env, NOT on is_dark(), so the plots read
  # the cached result and the dark-mode toggle becomes a pure recolor: it no
  # longer re-runs community_table (read by ~5 outputs), the 5x13 env dredge
  # (formerly 3x per load), or the permutation-averaged accumulation curve.
  ct_rx    <- reactive({ d <- rv$data; if (is.null(d)) NULL else community_table(d) })
  env_rank <- reactive({ d <- rv$data; e <- rv$env
    if (is.null(d) || is.null(e)) NULL else tryCatch(env_corr_all(d, e), error = function(x) NULL) })
  env_pval <- reactive({ d <- rv$data; e <- rv$env
    if (is.null(d) || is.null(e)) NULL else tryCatch(env_corr_pvalue(d, e), error = function(x) NULL) })
  accum_rx <- reactive({ d <- rv$data; if (is.null(d)) NULL else accumulation_by_bout(d) })

  # ---- cascading state -> site picker ------------------------------------
  .states <- state_choices()
  # Open on the richest site so the first thing a user sees is real data — not an
  # arbitrary "Kansas" default, and not an empty splash. The site-change auto-load
  # (below) then drives every subsequent pick.
  .firstSite <- if (!is.null(SITE_INDEX) && nrow(SITE_INDEX))
                  SITE_INDEX$site[which.max(SITE_INDEX$richness)] else NULL
  .firstState <- if (!is.null(.firstSite)) neon_sites$state[neon_sites$site == .firstSite][1]
                 else unname(.states)[1]
  rv$pendingSite <- .firstSite
  updateSelectInput(session, "stateSel", choices = .states, selected = .firstState)
  observeEvent(input$stateSel, {
    sites <- sites_in_state(input$stateSel)
    sel <- if (!is.null(rv$pendingSite) && rv$pendingSite %in% sites) rv$pendingSite
           else if (length(sites)) sites[[1]] else NULL
    rv$pendingSite <- NULL
    updateSelectInput(session, "site", choices = sites, selected = sel)
  }, ignoreNULL = TRUE)

  # ---- compare-site picker (optional second site to contrast) -------------
  .siteChoices <- function(exclude = NULL) {
    sc <- available_sites(); sc <- sc[sc != (exclude %||% "")]
    labs <- vapply(sc, function(s) { m <- neon_sites[neon_sites$site == s, ]
      if (nrow(m)) sprintf("%s · %s", s, m$name) else s }, character(1))
    c("(no comparison)" = "", stats::setNames(sc, labs))
  }
  updateSelectInput(session, "compareSite", choices = .siteChoices(.firstSite), selected = "")
  observeEvent(input$site, {
    keep <- if (!is.null(input$compareSite) && nzchar(input$compareSite) &&
                !identical(input$compareSite, input$site)) input$compareSite else ""
    updateSelectInput(session, "compareSite", choices = .siteChoices(input$site), selected = keep)
  }, ignoreInit = TRUE)

  output$siteBio <- renderUI({
    req(input$site); b <- site_bio(input$site)
    if (is.null(b)) return(NULL)
    div(class = "site-bio", bs_icon("info-circle-fill"), span(b))
  })

  shinyjs::hide("mainTabsWrap")

  # ---- load a site --------------------------------------------------------
  # snap = TRUE (a freshly picked site) resets the date window to THAT site's real
  # coverage, since a fixed default would silently hide data for sites whose years
  # fall outside it. snap = FALSE (the Load button) honours the user's window but
  # still auto-widens rather than scolding if it excludes every record.
  load_site <- function(site, snap = FALSE) {
    if (is.null(site) || site == "") return(invisible())
    if (isTRUE(rv$loading)) return(invisible())     # ignore re-taps / overlapping loads
    rv$loading <- TRUE

    # Visible feedback the moment a load starts. shiny::Progress flushes over the
    # websocket immediately (unlike showNotification) so the bar shows even during a
    # synchronous bundle read and persists through a slow live pull. on.exit()
    # guarantees the bar closes, the button re-enables, and the guard clears on
    # every return path below.
    shinyjs::disable("loadBtn")
    prog <- shiny::Progress$new(session)
    on.exit({ prog$close(); shinyjs::enable("loadBtn"); rv$loading <- FALSE }, add = TRUE)
    prog$set(message = sprintf("Loading %s…", site), value = 0.15)

    d0 <- load_site_bundle(site)
    if (is.null(d0) || !nrow(d0)) {
      # try a live fetch when no bundle/demo exists
      if (LIVE_FETCH) {
        prog$set(value = 0.35, message = sprintf("Downloading %s from NEON…", site),
                 detail = "first live pull can take a minute")
        d0 <- tryCatch(fetch_neon_beetles(site, input$dateRange[1], input$dateRange[2]),
                       error = function(e) { showNotification(paste("NEON fetch failed:",
                         conditionMessage(e)), type = "error"); NULL })
      }
      if (is.null(d0) || !nrow(d0)) {
        showNotification(sprintf("No beetle data bundled for %s yet — run scripts/refresh_data.R to pull it.", site),
                         type = "warning")
        return(invisible())
      }
    }
    prog$set(value = 0.7, detail = "summarising the community…")
    src <- attr(d0, "source") %||% "neon"

    cover <- range(d0$date, na.rm = TRUE)
    if (snap) {
      win <- cover
      updateDateRangeInput(session, "dateRange", start = cover[1], end = cover[2])
    } else {
      win <- as.Date(c(input$dateRange[1], input$dateRange[2]))
    }
    d <- filter_window(d0, win[1], win[2])
    if (is.null(d) || !nrow(d)) {
      d <- d0      # never dead-end on an empty window — show the site's full range
      updateDateRangeInput(session, "dateRange", start = cover[1], end = cover[2])
      showNotification(sprintf("No records in that window — showing %s's full range (%s–%s).",
        site, format(cover[1], "%Y"), format(cover[2], "%Y")), type = "message")
    }
    attr(d, "source") <- src
    rv$data  <- d
    rv$pal   <- make_species_pal(d)
    rv$label <- site_label(site); rv$siteCode <- site
    y1 <- format(min(d$date, na.rm = TRUE), "%Y"); y2 <- format(max(d$date, na.rm = TRUE), "%Y")
    rv$ctx <- paste0(site, " · ", if (y1 == y2) y1 else paste0(y1, "–", y2))
    # co-located environmental overlays for THIS site (reused from the mammal app)
    rv$env <- load_site_env(site)
    ch <- env_layer_choices(rv$env)
    # default the overlay to the MOST-correlated driver at its best lag (the
    # ranking's #1), so the env story shows on load instead of a blank "None".
    rk0 <- tryCatch(env_corr_all(d, rv$env), error = function(e) NULL)
    sel0 <- if (!is.null(rk0) && nrow(rk0)) rk0$layer[1] else "none"
    lag0 <- if (!is.null(rk0) && nrow(rk0)) as.integer(rk0$lag[1]) else 0L
    updateSelectInput(session, "envLayer", choices = ch, selected = if (sel0 %in% ch) sel0 else "none")
    updateSliderInput(session, "envLag", value = lag0)
    prog$set(value = 1, detail = "done")
    shinyjs::show("mainTabsWrap"); shinyjs::hide("splash"); shinyjs::hide("splashHome")
    session$sendCustomMessage("gbt_remember", site)   # persist last site for next visit
  }
  # The Load button re-applies the current (possibly narrowed) date window.
  observeEvent(input$loadBtn, load_site(input$site, snap = FALSE))
  # Picking a site (directly, via the state cascade, or via a map tap that drives
  # the dropdowns) auto-loads it — one mental model, no "why is nothing happening".
  # ignoreInit keeps the intro splash visible on first launch.
  # Skip the ONE boot-time auto-load so a new visitor lands on the national picker
  # map (the flagship front door, on par with the Small Mammal Tracker); every later
  # pick — dropdown change, map tap, or the remembered-site restore — loads normally.
  observeEvent(input$site, {
    if (!isTRUE(rv$siteReady)) { rv$siteReady <- TRUE; return(invisible()) }
    load_site(input$site, snap = TRUE)
  }, ignoreInit = TRUE, ignoreNULL = TRUE)

  # ---- splash national PICKER map (the flagship front door) ----------------
  # size = species richness, colour = total individuals (forest sequential ramp).
  # Tapping a marker drives the state+site dropdowns; the input$site observer above
  # does the single load (no race), matching the Biogeography-tab map's pattern.
  local({
    st <- picker_site_table
    if (!is.null(st) && nrow(st)) {
      mx <- suppressWarnings(max(st$individuals, na.rm = TRUE)); if (!is.finite(mx) || mx <= 0) mx <- 1
      pal <- leaflet::colorNumeric(c("#d6f3e4", "#36d98a", "#1f8a5a"), domain = c(0, mx), na.color = "#c9d3bb")
      picked <- mapPickerServer("picker", site_table = st, radius_metric = "richness",
        color_fn = function(s) pal(ifelse(is.finite(s$individuals), s$individuals, 0)),
        label_fn = function(r) sprintf(
          "<b>%s</b> · %s, %s<br><b>%s</b> species · <b>%s</b> individuals<br>dominant: <i>%s</i>%s",
          r$site, r$name %||% r$site, r$state %||% "", r$richness %||% "?",
          fmt_int(r$individuals %||% 0), r$dominant %||% "?",
          if (identical(r$source, "demo")) "<br><b>demo data</b>" else ""))
      # load in the MAIN server context (the module session would namespace inputs)
      observeEvent(picked(), {
        s <- picked(); if (is.null(s) || !nzchar(s)) return()
        m <- neon_sites[neon_sites$site == s, ]; if (!nrow(m)) return()
        if (identical(input$stateSel, m$state)) updateSelectInput(session, "site", selected = s)
        else { rv$pendingSite <- s; updateSelectInput(session, "stateSel", selected = m$state) }
      }, ignoreInit = TRUE)
    }
  })

  # Restore the last-used site (localStorage) or a ?site=SRER URL param on connect.
  observeEvent(input$restore_site, {
    s <- input$restore_site
    if (is.null(s) || !(s %in% available_sites())) return()
    m <- neon_sites[neon_sites$site == s, ]
    if (!nrow(m)) return()
    if (identical(input$stateSel, m$state))
      updateSelectInput(session, "site", selected = s)            # same state → triggers auto-load
    else {
      rv$pendingSite <- s
      updateSelectInput(session, "stateSel", selected = m$state)  # cascade → site → auto-load
    }
  }, once = TRUE)

  # Optional comparison site, loaded over its full coverage. Effort-normalised
  # metrics (catch per 100 trap-nights) keep the contrast fair across year spans.
  compareData <- reactive({
    s <- input$compareSite
    if (is.null(s) || !nzchar(s)) return(NULL)
    d <- load_site_bundle(s)
    if (is.null(d) || !nrow(d)) return(NULL)
    d
  })

  # Picking a comparison only changes the Diversity & Seasonality charts, so give
  # immediate feedback: hop to a compare-enabled tab (if not already on one) and
  # announce what's being compared — no submit button needed, it's live.
  observeEvent(input$compareSite, {
    s <- input$compareSite
    if (is.null(s) || !nzchar(s)) return()
    showNotification(sprintf("Comparing %s vs %s — shown on the Diversity & Seasonality tabs.",
      input$site, s), type = "message", duration = 5)
  }, ignoreInit = TRUE)

  # ---- Surprise me: hop to a random site (fun, low-friction exploration) ---
  do_surprise <- function() {
    pool <- setdiff(available_sites(), input$site %||% "")
    if (!length(pool)) pool <- available_sites()
    if (!length(pool)) return()
    s <- if (length(pool) == 1) pool else sample(pool, 1)
    m <- neon_sites[neon_sites$site == s, ]
    if (!nrow(m)) return()
    if (identical(input$stateSel, m$state)) updateSelectInput(session, "site", selected = s)
    else { rv$pendingSite <- s; updateSelectInput(session, "stateSel", selected = m$state) }
  }
  observeEvent(input$surpriseBtn, do_surprise())
  observeEvent(input$welcomeSurprise, { removeModal(); do_surprise() })

  # ---- first-visit welcome (once per browser; gated client-side) -----------
  observeEvent(input$first_visit, {
    showModal(modalDialog(
      title = NULL, easyClose = TRUE, footer = NULL,
      div(class = "welcome",
        div(class = "welcome-bug", "\U0001FAB2"),
        h3("Welcome to the Ground Beetle Tracker"),
        p("Explore ground-beetle (Carabidae) biodiversity across ", tags$b("46 NEON sites"),
          " — who lives where, how diverse each site is, when beetles are active, and whether they're holding steady. Real data, instant loads."),
        tags$ul(class = "welcome-list",
          tags$li(tags$b("Pick a state & site"), " at left — it loads automatically."),
          tags$li(tags$b("Open Biogeography"), " and tap any site on the national map."),
          tags$li(tags$b("Compare two sites"), " to contrast a desert with a forest.")),
        div(class = "welcome-cta",
          actionButton("welcomeSurprise", tagList(bs_icon("shuffle"), " Surprise me"), class = "btn-success"),
          modalButton("Start exploring →")))
    ))
  }, once = TRUE)

  output$srcNote <- renderUI({
    if (is.null(rv$data)) return(NULL)
    if (identical(attr(rv$data, "source"), "demo"))
      div(class = "env-source env-demo", bs_icon("info-circle-fill"),
          tags$span(HTML(" <b>Demo data</b> — illustrative, <b>not</b> NEON records. Run <code>scripts/refresh_data.R</code> to bundle the real product.")))
    else
      div(class = "env-source env-real", bs_icon("patch-check-fill"),
          tags$span(" NEON ground-beetle records for this site."))
  })

  # ---- splash + hero ------------------------------------------------------
  output$splash <- renderUI({
    if (!is.null(rv$data)) return(NULL)
    div(class = "splash",
      div(class = "splash-icon", "\U0001FAB2"),
      h3("Pick a site to begin"),
      p("Choose a state and site at left — it ", tags$b("loads automatically"),
        " — or open the Biogeography map and tap a marker."),
      if (!is.null(SITE_INDEX))
        p(class = "splash-sub", sprintf("%d site%s with beetle data available.",
          nrow(SITE_INDEX), if (nrow(SITE_INDEX) == 1) "" else "s")))
  })

  output$heroStats <- renderUI({
    d <- rv$data; if (is.null(d)) return(NULL)
    ct <- ct_rx(); if (is.null(ct)) return(NULL)
    sp <- ct[ct$species_level %in% TRUE, , drop = FALSE]   # richness = species only
    hn <- hill_numbers(sp$individuals)
    tn <- effort_trapnights(d)
    bouts <- length(unique(paste(d$plotID, d$collectDate)))
    stat <- function(v, l) div(class = "hero-stat", div(class = "hs-v", v), div(class = "hs-l", l))
    div(class = "hero-stats",
      stat(fmt_int(sum(ct$individuals)), "individuals"),
      stat(nrow(sp), "species"),
      stat(hn$q1, "effective species (q1)"),
      stat(fmt_int(bouts), "trap bouts"),
      stat(fmt_int(round(tn)), "trap-nights"))
  })

  # ---- Overview: community bar -------------------------------------------
  # ---- server-side PDF site report ----------------------------------------
  output$reportPdf <- downloadHandler(
    filename = function() sprintf("NEON-beetles-%s-%s.pdf",
      rv$siteCode %||% "site", format(Sys.Date(), "%Y%m%d")),
    content = function(file) {
      d <- rv$data; req(d)
      is_demo <- identical(attr(d, "source") %||% "neon", "demo")
      render_beetle_report(file, d, rv$label %||% (rv$siteCode %||% "Site"), is_demo, rv$env)
    }
  )

  # ---- tidy long-table export, bundled with a codebook + provenance --------
  # The loaded site's records as one row per plot x bout x species, plus a derived
  # catch-per-100-trap-nights so the effort-normalised metric travels with the raw
  # counts. Loads straight into R/pandas. We ship it as a .zip carrying the data,
  # a column codebook, and a README provenance stamp so the download is
  # self-documenting (a researcher can use it cold). When no zip binary exists
  # (some minimal images), we fall back to the plain tidy CSV — never error.
  .zip_available <- function() nzchar(Sys.which(Sys.getenv("R_ZIPCMD", "zip")))
  .build_export_df <- function(d) {
    tn <- suppressWarnings(as.numeric(d$trapnights))
    out <- data.frame(
      siteID                 = d$siteID %||% (rv$siteCode %||% NA_character_),
      plotID                 = d$plotID,
      collectDate            = as.character(d$date),
      year                   = d$year,
      month                  = d$mon,
      taxonID                = d$taxonID,
      scientificName         = d$scientificName,
      taxonRank              = d$taxonRank,
      species_level          = d$species_level,
      individualCount        = d$individualCount,
      trapnights             = tn,
      cpn_per_100_trapnights = ifelse(!is.na(tn) & tn > 0, round(100 * d$individualCount / tn, 3), NA_real_),
      source                 = attr(d, "source") %||% "neon",
      stringsAsFactors = FALSE)
    out[order(out$collectDate, -out$individualCount), , drop = FALSE]
  }
  output$reportCsv <- downloadHandler(
    filename = function() sprintf("NEON-beetles-%s-%s.%s",
      rv$siteCode %||% "site", format(Sys.Date(), "%Y%m%d"),
      if (.zip_available()) "zip" else "csv"),
    content = function(file) {
      d <- rv$data; req(d)
      out <- .build_export_df(d)
      cb  <- beetle_export_codebook()
      if (!setequal(names(out), cb$column))   # drift guard: codebook ↔ data columns
        warning("CSV export codebook out of sync: ",
                paste(setdiff(names(out), cb$column), collapse = ", "))
      site <- rv$siteCode %||% "site"
      if (!.zip_available()) { utils::write.csv(out, file, row.names = FALSE, na = ""); return(invisible()) }

      base <- sprintf("NEON-beetles-%s-%s", site, format(Sys.Date(), "%Y%m%d"))
      tmp  <- tempfile("gbtcsv"); dir.create(tmp); on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
      f_data <- file.path(tmp, paste0(base, ".csv"))
      f_cb   <- file.path(tmp, paste0(base, "-codebook.csv"))
      f_rm   <- file.path(tmp, "README.txt")
      utils::write.csv(out, f_data, row.names = FALSE, na = "")
      utils::write.csv(cb,  f_cb,   row.names = FALSE, na = "")
      win <- tryCatch(as.character(as.Date(c(input$dateRange[1], input$dateRange[2]))),
                      error = function(e) c(NA, NA))
      writeLines(c(
        "NEON Ground Beetle Tracker — data export",
        "========================================",
        sprintf("Site:         %s", rv$label %||% site),
        "Data product: NEON DP1.10022.001 (Ground beetles sampled from pitfall traps)",
        sprintf("Coverage:     %s", rv$ctx %||% ""),
        sprintf("Date window:  %s to %s", win[1], win[2]),
        sprintf("Rows:         %d", nrow(out)),
        sprintf("Source:       %s", attr(d, "source") %||% "neon"),
        sprintf("Exported:     %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        "",
        "Files",
        "-----",
        sprintf("%s.csv          tidy data, one row per plot x bout x taxon", base),
        sprintf("%s-codebook.csv column dictionary (name, type, units, definition)", base),
        "",
        "Method notes",
        "------------",
        "- Effort-normalised catch (cpn_per_100_trapnights) absorbs NEON's 2018 trap-count",
        "  and 2023 plot-count protocol changes, so years and sites compare fairly.",
        "- scientificName reconciles parataxonomist IDs with authoritative expert IDs;",
        "  species_level flags binomial resolution (Hoekman et al. 2017, Ecosphere 8(4):e01744).",
        "- Richness / diversity / ordination / indicators use species_level == TRUE only;",
        "  total abundance keeps every beetle trapped.",
        "",
        "An educational data-exploration tool by Desert Data Labs. Not affiliated with",
        "NEON, Battelle, or the NSF."
      ), f_rm)
      ok <- tryCatch({
        utils::zip(file, files = c(f_data, f_cb, f_rm), flags = "-j -q")
        file.exists(file) && file.size(file) > 0
      }, error = function(e) FALSE)
      if (!isTRUE(ok)) utils::write.csv(out, file, row.names = FALSE, na = "")  # last-ditch
    }
  )

  # "answer up front" banner for the Overview — the community-composition story
  output$overviewVerdict <- renderUI({
    d <- rv$data; req(d)
    ct <- ct_rx(); req(!is.null(ct), nrow(ct))
    sp <- ct[ct$species_level %in% TRUE, , drop = FALSE]
    if (!nrow(sp)) return(NULL)
    top <- sp[which.max(sp$individuals), ]
    share <- round(100 * top$individuals / sum(sp$individuals))
    cls <- if (share >= 50) "trend-flat" else "trend-up"   # one species dominating = amber, not "good"
    div(class = paste("trend-verdict", cls), bs_icon("bar-chart-line-fill"),
      HTML(sprintf(" <b>%d</b> carabid species identified here. Most abundant: <b><i>%s</i></b> — <b>%d%%</b> of named individuals (%s per 100 trap-nights).",
        nrow(sp), top$scientificName, share, top$cpn)))
  })

  output$commBar <- renderPlotly({
    d <- rv$data; req(d)
    ct <- ct_rx(); if (is.null(ct) || !nrow(ct)) return(note_plot("No community data"))
    ct <- ct[ct$species_level %in% TRUE, , drop = FALSE]   # name species, not genera
    if (!nrow(ct)) return(note_plot("No species-level identifications yet"))
    ct <- ct[order(ct$individuals), ]   # plotly bars: bottom = first
    pal <- rv$pal
    cols <- unname(pal[ct$scientificName]); cols[is.na(cols)] <- DDL$forest
    plot_ly(ct, x = ~individuals, y = ~factor(scientificName, levels = scientificName),
            type = "bar", orientation = "h",
            marker = list(color = cols),
            text = ~paste0(cpn, " /100TN"), textposition = "outside",
            hovertemplate = ~paste0("<b>", scientificName, "</b><br>",
              individuals, " individuals · ", bouts, " bouts<br>",
              cpn, " per 100 trap-nights<extra></extra>")) %>%
      plotly_theme(legend = FALSE) %>%
      plotly::layout(xaxis = list(title = "individuals"),
                     yaxis = list(title = "", automargin = TRUE),  # fits names; shrinks on phones
                     margin = list(l = 10, r = 70)) %>%             # r: room for outside /100TN labels
      plotly::add_annotations(text = rv$ctx, x = 1, y = 1.04, xref = "paper", yref = "paper",
        xanchor = "right", showarrow = FALSE,
        font = list(color = if (is_dark()) "#9fb0a6" else "#6b7a89", size = 11))
  })

  output$meetBeetles <- renderUI({
    d <- rv$data; req(d)
    ct <- ct_rx(); req(!is.null(ct))
    ct <- utils::head(ct[ct$species_level %in% TRUE, , drop = FALSE], 6)
    if (!nrow(ct)) return(NULL)
    cards <- lapply(seq_len(nrow(ct)), function(i) {
      sp <- ct$scientificName[i]
      div(class = "meet-card",
        div(class = "meet-ico", "\U0001FAB2"),
        div(class = "meet-body",
          div(class = "meet-name", sp),
          div(class = "meet-stat", sprintf("%s individuals · %s per 100 trap-nights",
              fmt_int(ct$individuals[i]), ct$cpn[i])),
          div(class = "meet-blurb", beetle_blurb(sp))))
    })
    div(class = "meet-grid", cards)
  })

  # ---- occupancy: how WIDESPREAD each species is (abundant != everywhere) ---
  output$occupancyPlot <- renderPlotly({
    d <- rv$data; req(d)
    oc <- occupancy_table(d)
    if (is.null(oc) || !nrow(oc)) return(note_plot("Not enough plot×bout samples<br>to estimate occupancy here", "\U0001F4CD"))
    n_samp <- attr(oc, "n_samp")
    oc <- utils::head(oc, 12); oc <- oc[order(oc$occ), ]
    cols <- unname(rv$pal[oc$scientificName]); cols[is.na(cols)] <- DDL$forest
    plot_ly(oc, x = ~occ, y = ~factor(scientificName, levels = scientificName),
            type = "bar", orientation = "h", marker = list(color = cols),
            text = ~paste0(occ, "%"), textposition = "outside",
            hovertemplate = ~paste0("<b>", scientificName, "</b><br>caught in ", present,
              " of ", n_samp, " sampling bouts (", occ, "%)<extra></extra>")) %>%
      plotly_theme(legend = FALSE) %>%
      plotly::layout(xaxis = list(title = "% of sampling bouts present", range = c(0, 100)),
                     yaxis = list(title = "", automargin = TRUE), margin = list(l = 10, r = 55)) %>%
      plotly::add_annotations(text = rv$ctx, x = 1, y = 1.04, xref = "paper", yref = "paper",
        xanchor = "right", showarrow = FALSE,
        font = list(color = if (is_dark()) "#9fb0a6" else "#6b7a89", size = 11))
  })

  # ---- phenology heatmap: each species' own activity window -----------------
  output$phenoHeat <- renderPlotly({
    d <- rv$data; req(d)
    pm <- phenology_matrix(d)
    if (is.null(pm)) return(note_plot("Not enough species-level catch<br>for a phenology heatmap"))
    dark <- is_dark()
    scale <- if (dark) list(c(0, "#16231d"), c(0.5, "#2e7d4e"), c(1, "#7fe0a3"))
             else      list(c(0, "#f1f7f2"), c(0.5, "#5aa873"), c(1, "#0f5325"))
    yrs <- suppressWarnings(range(d$year, na.rm = TRUE))
    # the subtitle rides ON the figure (survives a screenshot) so a pooled cell
    # is never mistaken for a single year; shading is anchored at 0 but its top
    # is per-site (this site's busiest cell), noted in the info-pop.
    sub <- if (all(is.finite(yrs)))
      sprintf("monthly avg /100 trap-nights · %s pooled",
              if (yrs[1] == yrs[2]) yrs[1] else paste0(yrs[1], "\U2013", yrs[2]))
      else "monthly avg /100 trap-nights"
    plot_ly(x = pm$months, y = pm$species, z = pm$z, type = "heatmap",
            colorscale = scale, zmin = 0, xgap = 1, ygap = 1,
            hovertemplate = "<b>%{y}</b><br>%{x}: %{z} per 100 trap-nights<extra></extra>",
            colorbar = list(title = list(text = "/100TN", font = list(size = 11)), thickness = 12)) %>%
      plotly_theme(legend = FALSE) %>%
      plotly::layout(xaxis = list(title = "", side = "top", tickfont = list(size = 11)),
                     yaxis = list(title = "", automargin = TRUE, autorange = "reversed"),
                     margin = list(l = 10, t = 58),
                     annotations = list(list(text = sub, x = 0, y = 1.12, xref = "paper", yref = "paper",
                       xanchor = "left", showarrow = FALSE,
                       font = list(size = 11, color = if (dark) "#9fb0a6" else "#6b7a89"))))
  })

  # ---- rank-abundance (Whittaker): the dominance/evenness shape -------------
  output$rankAbundance <- renderPlotly({
    d <- rv$data; req(d)
    ra <- rank_abundance(d)
    ra <- if (is.null(ra)) NULL else ra[is.finite(ra$rel) & ra$rel > 0, , drop = FALSE]   # log axis drops 0/NA silently
    if (is.null(ra) || nrow(ra) < 2) return(note_plot("Too few species<br>for a rank-abundance curve"))
    col <- if (is_dark()) "#36d98a" else DDL$forest
    plot_ly(ra, x = ~rank, y = ~rel, type = "scatter", mode = "lines+markers",
            line = list(color = col, width = 2), marker = list(color = col, size = 6),
            hovertemplate = ~paste0("#", rank, "  <b>", scientificName, "</b><br>",
              rel, "% of species-level individuals (", individuals, ")<extra></extra>")) %>%
      plotly_theme(legend = FALSE) %>%
      plotly::layout(xaxis = list(title = "species rank (most → least abundant)"),
                     yaxis = list(title = "% of species-level individuals (log)", type = "log"))
  })

  # ---- Diversity ----------------------------------------------------------
  # species-level abundance vector — the input every richness metric must use
  sp_counts <- function(d) {
    ct <- community_table(d); if (is.null(ct)) return(numeric(0))
    ct$individuals[ct$species_level %in% TRUE]
  }

  # data-quality note: how much of the catch is named to species vs. higher taxa
  output$qaNote <- renderUI({
    d <- rv$data; req(d)
    qa <- attr(ct_rx(), "qa")
    if (is.null(qa) || qa$higher_taxa == 0)
      return(div(class = "qa-note qa-clean", bs_icon("patch-check-fill"),
        HTML(sprintf(" All %d taxa here are identified to species — richness counts are clean.", qa$species %||% 0))))
    div(class = "qa-note qa-flag", bs_icon("funnel-fill"),
      HTML(sprintf(" Richness counts <b>%d species</b>. %d record-type%s identified only to genus/family (%s individuals, %.1f%% of the catch) are <b>excluded from richness, diversity and ordination</b> — they'd otherwise inflate the species count — but still counted in total abundance. <span class='qa-cite'>(NEON beetle design: Hoekman et al. 2017)</span>",
        qa$species, qa$higher_taxa, if (qa$higher_taxa == 1) "" else "s",
        fmt_int(qa$ind_higher), qa$pct_ind_higher)))
  })

  output$hillPlot <- renderPlotly({
    d <- rv$data; req(d)
    hn <- hill_numbers(sp_counts(d))
    if (is.na(hn$q0)) return(note_plot("Not enough data for diversity<br><span style='font-size:13px'>try widening the date window at left</span>"))
    qlab <- c("q0\nrichness", "q1\ncommon", "q2\ndominant")
    cmp <- compareData()
    if (!is.null(cmp)) {                       # two-site grouped comparison
      hb <- hill_numbers(sp_counts(cmp))
      # Hill q0/q1/q2 scale with sample size and are NOT rarefied here, and the
      # compare site loads over its FULL coverage while the main site honours the
      # date window — so put each side's individuals + year span on the figure,
      # making the asymmetry visible instead of reading as a fair diversity contest.
      nA <- sum(sp_counts(d)); nB <- sum(sp_counts(cmp))
      span <- function(x) { yr <- suppressWarnings(range(x$year, na.rm = TRUE))
        if (!all(is.finite(yr))) "" else if (yr[1] == yr[2]) as.character(yr[1]) else paste0(yr[1], "\U2013", yr[2]) }
      cap <- sprintf("%s: %s ind \U00B7 %s     %s: %s ind \U00B7 %s   \U2014   richness (q0) rises with sample size; sites are not rarefied to equal n",
        input$site, fmt_int(nA), span(d), input$compareSite, fmt_int(nB), span(cmp))
      return(plot_ly() %>%
        add_trace(x = qlab, y = c(hn$q0, hn$q1, hn$q2), type = "bar", name = input$site,
                  marker = list(color = "#36d98a"), text = round(c(hn$q0, hn$q1, hn$q2), 1),
                  textposition = "outside",
                  hovertemplate = paste0("<b>", input$site, "</b><br>%{x}: %{y:.2f}<extra></extra>")) %>%
        add_trace(x = qlab, y = c(hb$q0, hb$q1, hb$q2), type = "bar", name = input$compareSite,
                  marker = list(color = "#d98a3c"), text = round(c(hb$q0, hb$q1, hb$q2), 1),
                  textposition = "outside",
                  hovertemplate = paste0("<b>", input$compareSite, "</b><br>%{x}: %{y:.2f}<extra></extra>")) %>%
        plotly_theme() %>%
        plotly::layout(barmode = "group", xaxis = list(title = ""),
                       yaxis = list(title = "effective species"), margin = list(t = 56),
                       annotations = list(list(text = cap, x = 0, y = 1.16, xref = "paper", yref = "paper",
                         xanchor = "left", showarrow = FALSE,
                         font = list(size = 10.5, color = if (is_dark()) "#9fb0a6" else "#6b7a89")))))
    }
    df <- data.frame(q = qlab, v = c(hn$q0, hn$q1, hn$q2))
    plot_ly(df, x = ~q, y = ~v, type = "bar",
            marker = list(color = c("#36d98a", "#6ef0b0", "#a8f0cf")),
            text = ~round(v, 1), textposition = "outside",
            hovertemplate = ~paste0("%{x}: %{y:.2f} effective species<extra></extra>")) %>%
      plotly_theme(legend = FALSE) %>%
      plotly::layout(xaxis = list(title = ""), yaxis = list(title = "effective species"))
  })

  output$hillNote <- renderUI({
    d <- rv$data; req(d)
    hn <- hill_numbers(sp_counts(d))
    if (is.na(hn$even)) return(NULL)
    word <- if (hn$even >= 0.6) "an even community" else if (hn$even >= 0.35)
              "a moderately uneven community" else "a community dominated by a few species"
    div(class = "hill-note", bs_icon("info-circle"),
      HTML(sprintf(" Evenness q1/q0 = <b>%.2f</b> — %s.", hn$even, word)))
  })

  # plain-English verdict banner (same pattern as the Trends banner)
  output$diversityVerdict <- renderUI({
    d <- rv$data; req(d)
    hn <- hill_numbers(sp_counts(d))
    if (is.na(hn$q0)) return(NULL)
    even_word <- if (is.na(hn$even)) "a single-species catch"
                 else if (hn$even >= 0.6) "an even community"
                 else if (hn$even >= 0.35) "a moderately uneven community"
                 else "a community dominated by a few species"
    cls <- if (is.na(hn$even) || hn$even < 0.35) "trend-flat"
           else if (hn$even >= 0.6) "trend-up" else "trend-info"
    div(class = paste("trend-verdict", cls), bs_icon("diagram-3-fill"),
      HTML(sprintf(" <b>%d</b> beetle species here — q1 = <b>%.1f</b> common, q2 = <b>%.1f</b> dominant — %s.",
        as.integer(hn$q0), hn$q1, hn$q2, even_word)))
  })

  output$rarePlot <- renderPlotly({
    d <- rv$data; req(d)
    rc <- rarefaction_curve(sp_counts(d))
    if (is.null(rc)) return(note_plot("Not enough individuals to rarefy<br><span style='font-size:13px'>try widening the date window at left</span>"))
    plot_ly() %>%
      add_trace(x = rc$n, y = rc$hi, type = "scatter", mode = "lines",
                line = list(width = 0), showlegend = FALSE, hoverinfo = "skip") %>%
      add_trace(x = rc$n, y = rc$lo, type = "scatter", mode = "lines", fill = "tonexty",
                fillcolor = "rgba(19,99,43,0.14)", line = list(width = 0),
                name = "±1 SD", hoverinfo = "skip") %>%
      add_trace(x = rc$n, y = rc$richness, type = "scatter", mode = "lines",
                line = list(color = "#36d98a", width = 3), name = "expected species",
                hovertemplate = "%{x} individuals<br>%{y:.1f} species<extra></extra>") %>%
      plotly_theme(legend = FALSE) %>%
      plotly::layout(xaxis = list(title = "individuals sampled"),
                     yaxis = list(title = "expected species"))
  })

  output$accumPlot <- renderPlotly({
    d <- rv$data; req(d)
    ac <- accum_rx()
    if (is.null(ac)) return(note_plot("Not enough bouts for accumulation<br><span style='font-size:13px'>try widening the date window at left</span>"))
    plot_ly() %>%
      add_trace(x = ac$bouts, y = ac$richness + ac$sd, type = "scatter", mode = "lines",
                line = list(width = 0), showlegend = FALSE, hoverinfo = "skip") %>%
      add_trace(x = ac$bouts, y = pmax(0, ac$richness - ac$sd), type = "scatter",
                mode = "lines", fill = "tonexty", fillcolor = "rgba(47,127,181,0.14)",
                line = list(width = 0), name = "±1 SD", hoverinfo = "skip") %>%
      add_trace(x = ac$bouts, y = ac$richness, type = "scatter", mode = "lines+markers",
                line = list(color = "#43b8e8", width = 3), marker = list(size = 5),
                name = "species found",
                hovertemplate = "after %{x} bouts<br>%{y:.1f} species<extra></extra>") %>%
      plotly_theme(legend = FALSE) %>%
      plotly::layout(xaxis = list(title = "trapping bouts"),
                     yaxis = list(title = "cumulative species"))
  })

  # ---- Trends (inter-annual) ----------------------------------------------
  trend_data <- reactive({ d <- rv$data; req(d); annual_trend(d) })

  output$trendVerdict <- renderUI({
    t <- trend_data()
    if (is.null(t) || nrow(t) < 2) return(NULL)
    slope <- attr(t, "slope"); p <- attr(t, "p"); pct <- attr(t, "pct_per_yr")
    if (is.null(slope) || is.null(p) || !is.finite(slope)) {
      return(div(class = "trend-verdict trend-flat", bs_icon("dash-circle"),
        HTML(sprintf(" Only %d years of data — too few to fit a trend yet.", nrow(t)))))
    }
    # Under ~5 years a regression p-value is noise — show the apparent direction
    # but don't dress it up with a decimal the info-popover itself says to ignore.
    if (nrow(t) < 5) {
      appdir <- if (slope > 0) "an apparent rise" else if (slope < 0) "an apparent decline" else "little change"
      pcttxt <- if (is.finite(pct) && abs(pct) <= 40) sprintf(" (~%+.0f%%/yr)", pct) else ""
      return(div(class = "trend-verdict trend-flat", bs_icon("dash-circle"),
        HTML(sprintf(" Over %d years, catch-per-effort shows <b>%s</b>%s — but %d years is too few to test reliably; read the direction, not the decimal.%s",
          nrow(t), appdir, pcttxt, nrow(t),
          if (identical(attr(t, "metric_kind"), "count")) " <i>(raw counts — no effort data)</i>" else ""))))
    }
    sig <- is.finite(p) && p < 0.05
    dir <- if (!sig) "flat" else if (slope > 0) "up" else "down"
    word <- switch(dir, up = "rising", down = "declining", flat = "roughly flat")
    icon <- switch(dir, up = "arrow-up-right-circle-fill",
                   down = "arrow-down-right-circle-fill", flat = "dash-circle")
    pcttxt <- if (is.finite(pct) && abs(pct) <= 40) sprintf(" (~%+.0f%%/yr)", pct) else ""
    sigtxt <- if (sig) sprintf("statistically clear (p = %.3f)", p)
              else if (is.finite(p)) sprintf("not statistically distinguishable from no change (p = %.2f)", p)
              else "not statistically distinguishable from no change"
    div(class = paste("trend-verdict", paste0("trend-", dir)), bs_icon(icon),
      HTML(sprintf(" Over %d years, catch-per-effort is <b>%s</b>%s — %s. %s",
        nrow(t), word, pcttxt, sigtxt,
        if (identical(attr(t, "metric_kind"), "count"))
          "<i>(raw counts — this bundle has no effort data)</i>" else "")))
  })

  output$trendPlot <- renderPlotly({
    t <- trend_data()
    if (is.null(t) || nrow(t) < 2)
      return(note_plot("Need at least two years of data for a trend<br><span style='font-size:13px'>try widening the date window at left</span>"))
    kind <- attr(t, "metric_kind") %||% "cpn"
    ytitle <- if (kind == "cpn") "catch per 100 trap-nights" else "individuals caught"
    p <- plot_ly(x = ~t$year, y = ~t$metric, type = "scatter", mode = "lines+markers",
      name = "observed", line = list(color = "#36d98a", width = 3),
      marker = list(size = 9, color = "#36d98a"),
      hovertemplate = paste0("%{x}: %{y:.1f} ", ytitle, "<extra></extra>"))
    pred <- attr(t, "pred")
    if (!is.null(pred) && length(pred) == nrow(t) && nrow(t) >= 5) {
      p <- p %>% add_trace(x = t$year, y = pred, mode = "lines", name = "trend",
        line = list(color = "#e0b43a", width = 2, dash = "dash"),
        hoverinfo = "skip", inherit = FALSE)
    }
    plotly_theme(p) %>% plotly::layout(
      xaxis = list(title = "", dtick = 1),
      yaxis = list(title = ytitle, rangemode = "tozero"))
  })

  # ---- Seasonality --------------------------------------------------------
  # ---- environmental overlays (which driver does beetle activity track?) ----
  output$hasEnv <- reactive({ e <- rv$env; !is.null(e) && nrow(e) > 0 && length(env_layer_choices(e)) > 1 })
  outputOptions(output, "hasEnv", suspendWhenHidden = FALSE)

  output$envSourceNote <- renderUI({
    e <- rv$env; if (is.null(e)) return(NULL)
    if (identical(attr(e, "source") %||% "neon", "demo"))
      div(class = "env-source env-demo", bs_icon("exclamation-triangle"),
          HTML(" Illustrative <b>demo</b> environment — not real NEON values."))
    else
      div(class = "env-source env-real", bs_icon("patch-check"),
          HTML(" Co-located NEON env products for this site (precip / air temperature / plant phenology)."))
  })

  output$envDriverRank <- renderPlotly({
    d <- rv$data; e <- rv$env; req(d, !is.null(e))
    rk <- env_rank()
    if (is.null(rk) || !nrow(rk)) return(note_plot("Not enough overlapping months<br>to rank drivers here", "\U0001F326"))
    rk <- rk[order(abs(rk$r)), ]
    cols <- vapply(seq_len(nrow(rk)), function(i) ec_corr_color(rk$layer[i], rk$r[i], is_dark()), character(1))
    plot_ly(rk, x = ~r, y = ~factor(label, levels = label), type = "bar", orientation = "h",
            marker = list(color = cols),
            text = ~sprintf("r=%.2f · lag %d", r, lag), textposition = "outside",
            hovertemplate = ~paste0("<b>", label, "</b><br>r = ", r, " at ", lag,
              "-mo lag<br>n = ", n, " months<extra></extra>")) %>%
      plotly_theme(legend = FALSE) %>%
      plotly::layout(xaxis = list(title = "deseasonalized correlation r (−1…+1)", range = c(-1, 1), zeroline = TRUE),
                     yaxis = list(title = "", automargin = TRUE), margin = list(l = 10, r = 78))
  })

  # switching the overlay driver snaps the lag slider to THAT driver's best match
  # (the slider still lets you explore any other lag). ignoreInit so it doesn't
  # fight load_site's initial best-driver default.
  observeEvent(input$envLayer, {
    if (is.null(input$envLayer) || input$envLayer == "none" || is.null(rv$env)) return()
    sc <- tryCatch(env_corr_scan(rv$data, rv$env, input$envLayer), error = function(e) NULL)
    updateSliderInput(session, "envLag", value = if (!is.null(sc) && !is.na(sc$lag)) as.integer(sc$lag) else 0L)
  }, ignoreInit = TRUE)

  # The env overlay only renders on the POOLED activity curve (the per-species
  # branch has no second axis), so when "Split by species" is ticked, grey out
  # the driver picker and say why — instead of the line vanishing with the picker
  # still active, which reads as a bug.
  observeEvent(input$seasonBySpecies, {
    if (isTRUE(input$seasonBySpecies)) shinyjs::disable("envLayer") else shinyjs::enable("envLayer")
  })
  output$envSplitNote <- renderUI({
    if (!isTRUE(input$seasonBySpecies)) return(NULL)
    div(class = "env-lag-hint", style = "margin-top:4px;",
        bs_icon("info-circle"), " Overlay pauses while ", tags$b("Split by species"),
        " is on — untick it to compare a driver on the pooled curve.")
  })

  # styled "answer up front" — eyebrow · hero sentence + hero r-value · metadata
  # (same .ec design as the Small Mammal Tracker: strength drives the rail + verdict
  # word, SIGN drives the r-value colour + arrow + more/fewer, on separate channels).
  output$envCorrNote <- renderUI({
    rk <- env_rank(); if (is.null(rk) || !nrow(rk)) return(NULL)
    e <- rv$env; pv <- env_pval()
    top <- rk[1, ]
    strength <- abs(top$r); pos <- top$r >= 0; dir <- if (pos) "more" else "fewer"
    # Gate the loud verdict word on the permutation p: the strongest correlation
    # out of the whole driver x lag dredge earns "Strong/Moderate" only when it
    # beats chance alignment. p >= 0.05 -> demote to "Apparent" however big |r| is.
    not_sig <- !is.null(pv) && is.finite(pv$p) && pv$p >= 0.05
    if (not_sig) { slabel <- "Apparent"; rail <- "rail-weak" }
    else {
      rail <- if (strength >= 0.6) "rail-strong" else if (strength >= 0.35) "rail-mod" else "rail-weak"
      slabel <- if (strength >= 0.6) "Strong" else if (strength >= 0.35) "Moderate"
                else if (strength >= 0.2) "Weak" else "Negligible"
    }
    glyph <- if (pos) "arrow-up-right" else "arrow-down-right"
    demo <- identical(attr(e, "source") %||% "neon", "demo")
    n_search <- if (!is.null(pv)) pv$n_search else nrow(rk) * 13L
    ptxt <- if (!is.null(pv) && is.finite(pv$p)) {
      if (pv$p < 0.01) "p < 0.01" else sprintf("p = %.2f", pv$p)
    } else NULL
    div(class = paste("ec", rail),
      style = sprintf("--ec-driver-hue:%s;", ENV_LAYERS[[top$layer]]$color %||% "#8a97a8"),
      div(class = "ec-eyebrow", bs_icon("graph-up-arrow"), tags$span("environmental tracking"),
        if (demo) tags$span(class = "ec-demo", "demo overlay") else NULL),
      div(class = "ec-hero",
        div(class = "ec-hero-text",
          tags$span(class = "ec-strength", slabel), " link with ",
          tags$span(class = "ec-driver", tolower(top$label))),
        div(class = paste("ec-rvalue", if (pos) "ec-sgn-pos" else "ec-sgn-neg"),
          title = "correlation coefficient, -1 to +1 — see the (i) above for what it means",
          bs_icon(glyph), HTML(sprintf("r&nbsp;%+.2f", top$r)))),
      div(class = "ec-foot",
        tags$span(class = "ec-meta", bs_icon("clock-history"),
          if (top$lag == 0) "same-month signal" else HTML(sprintf("<b>%d-mo</b> lead", top$lag))),
        tags$span(class = "ec-meta-dot"),
        tags$span(class = "ec-meta", bs_icon("calendar3"), HTML(sprintf("<b>%d</b> months matched", top$n))),
        tags$span(class = "ec-meta-dot"),
        tags$span(class = "ec-meta", bs_icon("search"),
          HTML(sprintf("best of <b>%d</b> driver\U00D7lag%s", n_search,
            if (!is.null(ptxt)) paste0(" \U00B7 ", ptxt) else ""))),
        tags$span(class = paste("ec-meta ec-dir", if (pos) "ec-sgn-pos" else "ec-sgn-neg"),
          HTML(sprintf("higher \U2192 <b>%s</b> beetles", dir)))))
  })

  output$envScatter <- renderPlotly({
    d <- rv$data; e <- rv$env; req(d, !is.null(e))
    layer <- input$envLayer
    if (is.null(layer) || layer == "none") return(note_plot("Pick a driver above<br>to see the response", "\U0001F326"))
    lag <- envLag_d() %||% 0
    pts <- env_response_points(d, e, layer, lag)
    if (is.null(pts) || nrow(pts) < 3) return(note_plot("Not enough matched months<br>at this lag"))
    meta <- ENV_LAYERS[[layer]]; col <- if (is_dark()) "#36d98a" else DDL$forest
    p <- plot_ly(pts, x = ~value, y = ~cpue, type = "scatter", mode = "markers",
            marker = list(color = meta$color, size = 9, line = list(color = "#fff", width = 1)),
            hovertemplate = ~paste0("%{x} ", meta$unit, " · %{y:.1f} /100TN<br>", format(date, "%b %Y"), "<extra></extra>"))
    # fit only when there's enough signal: >=8 months AND |r|>=0.2. Guard the cor()
    # against a constant driver (sd 0 -> cor NA -> if(NA) would crash the chart).
    rr <- if (stats::sd(pts$value) > 0 && stats::sd(pts$cpue) > 0)
            abs(suppressWarnings(stats::cor(pts$value, pts$cpue))) else NA_real_
    if (nrow(pts) >= 8 && is.finite(rr) && rr >= 0.2) {
      fit <- stats::lm(cpue ~ value, pts); xr <- range(pts$value)
      yy <- stats::predict(fit, newdata = data.frame(value = xr))
      p <- p %>% add_trace(x = xr, y = yy, type = "scatter", mode = "lines", inherit = FALSE,
        line = list(color = col, width = 2, dash = "dash"), hoverinfo = "skip", showlegend = FALSE)
    }
    p %>% plotly_theme(legend = FALSE) %>%
      plotly::layout(xaxis = list(title = sprintf("%s (%s, lag %d mo)", meta$label, meta$unit, lag)),
                     yaxis = list(title = "catch per 100 trap-nights"))
  })

  output$seasonPlot <- renderPlotly({
    d <- rv$data; req(d)
    cmp <- compareData()
    if (!is.null(cmp)) {                       # contrast two sites' activity curves
      sA <- seasonality(d, by_species = FALSE)
      sB <- seasonality(cmp, by_species = FALSE)
      if ((is.null(sA) || !nrow(sA)) && (is.null(sB) || !nrow(sB)))
        return(note_plot("No seasonal data<br><span style='font-size:13px'>try widening the date window at left</span>"))
      p <- plot_ly()
      if (!is.null(sA) && nrow(sA))
        p <- p %>% add_trace(x = month.abb[sA$mon], y = sA$cpn, type = "scatter",
          mode = "lines+markers", name = input$site,
          line = list(color = "#36d98a", width = 3), marker = list(size = 7, color = "#36d98a"),
          hovertemplate = paste0("<b>", input$site, "</b><br>%{x}: %{y:.1f} /100TN<extra></extra>"))
      if (!is.null(sB) && nrow(sB))
        p <- p %>% add_trace(x = month.abb[sB$mon], y = sB$cpn, type = "scatter",
          mode = "lines+markers", name = input$compareSite,
          line = list(color = "#d98a3c", width = 3, dash = "dot"), marker = list(size = 7, color = "#d98a3c"),
          hovertemplate = paste0("<b>", input$compareSite, "</b><br>%{x}: %{y:.1f} /100TN<extra></extra>"))
      return(plotly_theme(p) %>% plotly::layout(
        xaxis = list(title = "", categoryorder = "array", categoryarray = month.abb),
        yaxis = list(title = "catch per 100 trap-nights")))
    }
    if (isTRUE(input$seasonBySpecies)) {
      s <- seasonality(d, by_species = TRUE)
      if (is.null(s) || !nrow(s)) return(note_plot("No seasonal data<br><span style='font-size:13px'>try widening the date window at left</span>"))
      pal <- rv$pal; p <- plot_ly()
      for (sp in unique(s$scientificName)) {
        ss <- s[s$scientificName == sp, ]
        p <- p %>% add_trace(x = month.abb[ss$mon], y = ss$cpn, type = "scatter",
          mode = "lines+markers", name = sp,
          line = list(color = pal[[sp]] %||% "#36d98a", width = 2),
          marker = list(size = 6, color = pal[[sp]] %||% "#36d98a"),
          hovertemplate = paste0("<b>", sp, "</b><br>%{x}: %{y:.1f} /100TN<extra></extra>"))
      }
      return(plotly_theme(p) %>% plotly::layout(
        xaxis = list(title = "", categoryorder = "array", categoryarray = month.abb),
        yaxis = list(title = "catch per 100 trap-nights")))
    }
    s <- seasonality(d, by_species = FALSE)
    if (is.null(s) || !nrow(s)) return(note_plot("No seasonal data<br><span style='font-size:13px'>try widening the date window at left</span>"))
    p <- plot_ly(x = month.abb[s$mon], y = s$cpn, type = "scatter", mode = "lines+markers",
            name = "all ground beetles", fill = "tozeroy", fillcolor = "rgba(19,99,43,0.16)",
            line = list(color = "#36d98a", width = 3), marker = list(size = 7, color = "#36d98a"),
            hovertemplate = "%{x}: %{y:.1f} per 100 trap-nights<extra></extra>")
    # optional environmental overlay (calendar-month climatology) on a right axis
    layer <- input$envLayer; has_ov <- !is.null(layer) && layer != "none" && !is.null(rv$env)
    if (has_ov) {
      lag <- envLag_d() %||% 0
      clim <- env_climatology(rv$env, layer, lag); meta <- ENV_LAYERS[[layer]]
      if (!is.null(clim) && nrow(clim)) {
        nm <- meta$label; if (lag != 0L) nm <- sprintf("%s · lag %d mo", nm, as.integer(lag))
        hov <- paste0(meta$label, "<br>%{x}: %{y} ", meta$unit, "<extra></extra>")
        # inherit = FALSE: don't pick up the base activity trace's fill/markers
        # (a default-inherited fill = "tozeroy" was the bug that filled the temp line).
        if (isTRUE(meta$fillable)) {       # non-negative driver: fill the area to zero
          p <- p %>% add_trace(x = month.abb[clim$mon], y = clim$value, yaxis = "y2", type = "scatter",
            mode = "lines", fill = "tozeroy", name = nm, inherit = FALSE,
            line = list(color = meta$color, width = 1.6, shape = "spline"),
            fillcolor = paste0(meta$color, "1f"), hovertemplate = hov)
        } else {                            # can go negative (temperature): plain line, no fill
          p <- p %>% add_trace(x = month.abb[clim$mon], y = clim$value, yaxis = "y2", type = "scatter",
            mode = "lines", name = nm, fill = "none", inherit = FALSE,
            line = list(color = meta$color, width = 2.2, shape = "spline"), hovertemplate = hov)
        }
      } else has_ov <- FALSE
    }
    p %>% plotly_theme(legend = TRUE) %>%
      plotly::layout(xaxis = list(title = "", categoryorder = "array", categoryarray = month.abb),
                     yaxis = list(title = "catch per 100 trap-nights"),
                     yaxis2 = if (has_ov) env_axis_spec(layer)
                              else list(overlaying = "y", side = "right", visible = FALSE))
  })

  # plain-English seasonality verdict (peak month + active window)
  output$seasonVerdict <- renderUI({
    d <- rv$data; req(d)
    if (!is.null(compareData())) return(NULL)   # verdict is per-site; hidden while comparing
    s <- seasonality(d, by_species = FALSE)
    if (is.null(s) || !nrow(s)) return(NULL)
    peak <- s$mon[which.max(s$cpn)]
    act <- sort(s$mon[s$cpn >= 0.2 * max(s$cpn, na.rm = TRUE)])
    win <- if (length(act) >= 2) sprintf("%s–%s", month.abb[min(act)], month.abb[max(act)]) else month.abb[peak]
    div(class = "trend-verdict trend-info", bs_icon("calendar-heart"),
      HTML(sprintf(" Activity peaks in <b>%s</b>; the warm-season window runs <b>%s</b>.",
        month.abb[peak], win)))
  })

  # ---- Biogeography -------------------------------------------------------
  updateSelectInput(session, "rangeSpecies",
                    choices = c("All species (richness)" = "", species_choices()))

  # "answer up front" banner for Biogeography — where this site sits nationally
  output$biogeoVerdict <- renderUI({
    req(input$site)
    si <- SITE_INDEX
    if (is.null(si) || !nrow(si)) return(NULL)
    row <- si[si$site == input$site, , drop = FALSE]
    if (!nrow(row) || is.na(row$richness[1])) return(NULL)
    M <- nrow(si); r <- row$richness[1]
    rank <- sum(si$richness > r, na.rm = TRUE) + 1L
    pct <- rank / M
    cls <- if (pct <= 0.34) "trend-up" else if (pct >= 0.67) "trend-flat" else "trend-info"
    div(class = paste("trend-verdict", cls), bs_icon("geo-alt-fill"),
      HTML(sprintf(" <b>%s</b> ranks <b>#%d of %d</b> NEON sites for carabid richness — <b>%d</b> species recorded across all years.",
        row$name[1], rank, M, as.integer(r))))
  })

  output$map <- renderLeaflet({
    si <- SITE_INDEX
    # match the basemap to the theme — every plotly chart re-themes, so a blinding
    # white map in dark mode is the one surface that fought the toggle. The gold
    # "you are here" ring reads clearly on both tiles.
    tiles <- if (is_dark()) "CartoDB.DarkMatter" else "CartoDB.Positron"
    base <- leaflet() %>% addProviderTiles(tiles) %>% setView(-98, 39, zoom = 3)
    if (is.null(si)) return(base)
    si <- si[!is.na(si$lat), ]
    sp <- input$rangeSpecies %||% ""
    if (sp != "" && !is.null(SPECIES_SITES)) {
      rng <- SPECIES_SITES[SPECIES_SITES$scientificName == sp, ]
      rng <- merge(rng, si[, c("site", "name", "lat", "lng")],
                   by.x = "siteID", by.y = "site")
      if (!nrow(rng)) return(base)
      return(base %>% addCircleMarkers(data = rng, lng = ~lng, lat = ~lat, layerId = ~siteID,
        radius = ~pmax(12, sqrt(individualCount) * 2.2), color = "#36d98a",
        fillOpacity = 0.75, stroke = TRUE, weight = 1.5,
        label = ~lapply(sprintf("<b>%s</b><br><i>%s</i>: %s individuals",
          siteID, sp, fmt_int(individualCount)), htmltools::HTML)))
    }
    pal <- c(neon = "#36d98a", demo = "#e0b43a")
    m <- base %>% addCircleMarkers(data = si, lng = ~lng, lat = ~lat, layerId = ~site,
        radius = ~pmax(12, sqrt(richness) * 4), color = ~unname(pal[source]),
        fillOpacity = 0.7, stroke = TRUE, weight = 1.5,
        label = ~lapply(sprintf("<b>%s</b> · %s<br>%d species · %s individuals<br>dominant: <i>%s</i>%s",
          site, name, richness, fmt_int(individuals), dominant,
          ifelse(source == "demo", "<br><b>demo data</b>", "")), htmltools::HTML))
    cur <- isolate(rv$siteCode)   # ring the loaded site so the map ↔ single-site view connect
    if (!is.null(cur)) {
      cs <- si[si$site == cur, , drop = FALSE]
      if (nrow(cs) && !is.na(cs$lat))
        m <- m %>% addCircleMarkers(lng = cs$lng, lat = cs$lat, radius = 15, color = "#ffd24a",
          weight = 3, fill = FALSE, opacity = 1, group = "currentSite",
          options = pathOptions(interactive = FALSE))
    }
    m
  })

  # keep the gold "you are here" ring in sync as sites load (no full re-render)
  observeEvent(rv$siteCode, {
    req(rv$siteCode); si <- SITE_INDEX; if (is.null(si)) return()
    if (!is.null(input$rangeSpecies) && nzchar(input$rangeSpecies)) return()  # skip in species-range mode
    cs <- si[si$site == rv$siteCode, , drop = FALSE]
    if (!nrow(cs) || is.na(cs$lat)) return()
    leafletProxy("map") %>% clearGroup("currentSite") %>%
      addCircleMarkers(lng = cs$lng, lat = cs$lat, radius = 15, color = "#ffd24a",
        weight = 3, fill = FALSE, opacity = 1, group = "currentSite",
        options = pathOptions(interactive = FALSE))
  })

  # cross-site community ordination (PCoA on Bray-Curtis)
  output$ordPlot <- renderPlotly({
    o <- ORDINATION
    if (is.null(o) || nrow(o) < 4)
      return(note_plot("Not enough sites/samples to ordinate<br><span style='font-size:13px'>Bundle more sites with scripts/refresh_data.R</span>"))
    pal <- grDevices::colorRampPalette(RColorBrewer::brewer.pal(8, "Dark2"))(length(unique(o$site)))
    pal <- stats::setNames(pal, sort(unique(o$site)))
    ve <- attr(o, "var_explained")
    p <- plot_ly()
    for (s in sort(unique(o$site))) {
      os <- o[o$site == s, ]
      p <- p %>% add_trace(data = os, x = ~x, y = ~y, type = "scatter", mode = "markers",
        name = s, marker = list(size = 9, color = pal[[s]], opacity = 0.8,
                                line = list(color = "#fff", width = 1)),
        hovertemplate = paste0("<b>", s, "</b><br>%{text}<extra></extra>"), text = ~sample)
    }
    plotly_theme(p) %>% plotly::layout(
      xaxis = list(title = if (!is.na(ve[1])) sprintf("PCoA 1 (%d%%)", ve[1]) else "PCoA 1"),
      yaxis = list(title = if (!is.na(ve[2])) sprintf("PCoA 2 (%d%%)", ve[2]) else "PCoA 2"))
  })
  observeEvent(input$map_marker_click, {
    s <- input$map_marker_click$id; req(s)
    m <- neon_sites[neon_sites$site == s, ]
    if (!nrow(m)) return()
    # drive the pickers; the cascade / site-change observer does the single load,
    # so the dropdowns and the loaded charts can't disagree (no race).
    if (identical(input$stateSel, m$state))
      updateSelectInput(session, "site", selected = s)
    else {
      rv$pendingSite <- s
      updateSelectInput(session, "stateSel", selected = m$state)
    }
  })

  output$siteTable <- DT::renderDT({
    si <- SITE_INDEX; if (is.null(si)) return(NULL)
    tab <- si[order(-si$richness), c("site", "name", "state", "richness", "individuals", "dominant", "source")]
    names(tab) <- c("Site", "Name", "State", "Species", "Individuals", "Dominant species", "Source")
    DT::datatable(tab, rownames = FALSE, selection = "none",
                  options = list(pageLength = 10, dom = "tp", scrollX = TRUE)) %>%
      DT::formatCurrency("Individuals", currency = "", interval = 3, mark = ",", digits = 0)
  })

  output$indicatorTable <- DT::renderDT({
    ind <- INDICATORS
    if (is.null(ind) || !nrow(ind))
      return(DT::datatable(data.frame(Note = "Need ≥2 sites bundled to rank indicators."),
                           rownames = FALSE, options = list(dom = "t")))
    tab <- ind[, c("scientificName", "indicator_site", "indval", "specificity", "fidelity", "total")]
    names(tab) <- c("Species", "Indicator of", "IndVal", "Specificity %", "Fidelity %", "Total caught")
    DT::datatable(tab, rownames = FALSE, selection = "none",
                  options = list(pageLength = 12, dom = "tp", scrollX = TRUE, order = list(list(2, "desc")))) %>%
      DT::formatStyle("Species", fontStyle = "italic") %>%
      DT::formatStyle("IndVal",
        background = DT::styleColorBar(c(0, 100), "#cfe6d6"),
        backgroundSize = "98% 70%", backgroundRepeat = "no-repeat",
        backgroundPosition = "center")
  })

  # ---- About --------------------------------------------------------------
  output$aboutPanel <- renderUI({
    div(class = "about",
      h3("About this app"),
      p("The ", tags$b("NEON Ground Beetle Tracker"), " explores carabid beetle biodiversity from ",
        tags$a(href = "https://data.neonscience.org/data-products/DP1.10022.001", target = "_blank",
               "NEON DP1.10022.001 — Ground beetles sampled from pitfall traps"), "."),
      p("Ground beetles are a classic ", tags$b("bioindicator"),
        ": they respond quickly to habitat, disturbance, and climate, so their richness, diversity, and seasonal activity tell a rich story about each NEON site."),
      h4("What you can explore"),
      tags$ul(
        tags$li(tags$b("Community"), " — which species dominate, by abundance and per-trap-night effort."),
        tags$li(tags$b("Diversity"), " — Hill numbers, rarefaction at equal sample size, and species accumulation."),
        tags$li(tags$b("Seasonality"), " — activity-density by month, overall and per species."),
        tags$li(tags$b("Trends"), " — inter-annual catch-per-effort with a fitted trend and decline/increase verdict."),
        tags$li(tags$b("Biogeography"), " — a richness/range map, a Bray–Curtis community ordination, and indicator species (IndVal) per site.")),
      h4("Methods"),
      tags$ul(
        tags$li("Abundance is normalised to ", tags$b("catch per 100 trap-nights"),
                " (effort = unique plot × bout trap-night totals) so sites compare fairly."),
        tags$li(tags$b("Species vs. higher taxa (QA/QC)."),
                " Not every beetle is named to species — some are left at genus (\"",
                tags$em("Bembidion"), " sp.\") or family (\"Carabidae\"). Counting those as if each were its own species ",
                tags$b("inflates richness and diversity"), ", so all richness-type metrics (richness, Hill numbers, rarefaction, accumulation, ordination, indicator species) use ",
                tags$b("species-level records only"), ". Total ", tags$b("abundance"),
                " still counts every beetle trapped. The Diversity tab shows exactly how many records this excludes."),
        tags$li("Hill numbers (Hill 1973; Jost 2006); Hurlbert (1971) rarefaction; Gotelli & Colwell (2001) accumulation; Dufrêne & Legendre (1997) indicator value; NEON ground-beetle sampling design (Hoekman et al. 2017, ", tags$em("Ecosphere"), " 8(4):e01744)."),
        tags$li("Real bundles reconcile parataxonomist IDs with authoritative ", tags$b("expert IDs"),
                " and normalise the 2018 trap-count and 2023 plot-count protocol changes via per-trap-night effort."),
        tags$li(tags$b("Download the data."), " The ", tags$b("Data + codebook"),
                " button exports the loaded site as a tidy one-row-per-plot×bout×species table, bundled with a column ",
                tags$b("codebook"), " and a provenance README so it loads straight into R/pandas and documents itself.")),
      local({
        demo_sites <- if (!is.null(SITE_INDEX)) SITE_INDEX$site[SITE_INDEX$source == "demo"] else character(0)
        if (length(demo_sites))
          div(class = "about-note", bs_icon("exclamation-triangle"),
            HTML(sprintf(" %s shown from <b>illustrative demo data — not real NEON records</b>; run <code>scripts/refresh_data.R</code> to replace with the real product.",
              paste(demo_sites, collapse = ", "))))
        else
          div(class = "about-note", bs_icon("patch-check-fill"),
            sprintf(" All %d bundled sites use real NEON records (DP1.10022.001).",
                    if (!is.null(SITE_INDEX)) nrow(SITE_INDEX) else 0L))
      }),
      p(style = "margin-top:16px", "An educational data-exploration tool by Desert Data Labs. Not affiliated with NEON, Battelle, or the NSF.")
    )
  })
}
