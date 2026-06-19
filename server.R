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
      hoverlabel = list(bgcolor = if (dark) "rgba(9,28,18,0.96)" else "rgba(19,99,43,0.96)",
                        bordercolor = "#FFD200",
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
    prog$set(value = 1, detail = "done")
    shinyjs::show("mainTabsWrap"); shinyjs::hide("splash")
    nav_select("tabs", "overview")
    session$sendCustomMessage("gbt_remember", site)   # persist last site for next visit
  }
  # The Load button re-applies the current (possibly narrowed) date window.
  observeEvent(input$loadBtn, load_site(input$site, snap = FALSE))
  # Picking a site (directly, via the state cascade, or via a map tap that drives
  # the dropdowns) auto-loads it — one mental model, no "why is nothing happening".
  # ignoreInit keeps the intro splash visible on first launch.
  observeEvent(input$site, load_site(input$site, snap = TRUE),
               ignoreInit = TRUE, ignoreNULL = TRUE)

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
    if (!isTRUE(input$tabs %in% c("diversity", "seasonality")))
      nav_select("tabs", "diversity")
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
    ct <- community_table(d)
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
  output$commBar <- renderPlotly({
    d <- rv$data; req(d)
    ct <- community_table(d); if (is.null(ct) || !nrow(ct)) return(note_plot("No community data"))
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
        xanchor = "right", showarrow = FALSE, font = list(color = "#6b7a89", size = 11))
  })

  output$meetBeetles <- renderUI({
    d <- rv$data; req(d)
    ct <- community_table(d)
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

  # ---- Diversity ----------------------------------------------------------
  # species-level abundance vector — the input every richness metric must use
  sp_counts <- function(d) {
    ct <- community_table(d); if (is.null(ct)) return(numeric(0))
    ct$individuals[ct$species_level %in% TRUE]
  }

  # data-quality note: how much of the catch is named to species vs. higher taxa
  output$qaNote <- renderUI({
    d <- rv$data; req(d)
    qa <- attr(community_table(d), "qa")
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
      return(plot_ly() %>%
        add_trace(x = qlab, y = c(hn$q0, hn$q1, hn$q2), type = "bar", name = input$site,
                  marker = list(color = "#13632b"), text = round(c(hn$q0, hn$q1, hn$q2), 1),
                  textposition = "outside",
                  hovertemplate = paste0("<b>", input$site, "</b><br>%{x}: %{y:.2f}<extra></extra>")) %>%
        add_trace(x = qlab, y = c(hb$q0, hb$q1, hb$q2), type = "bar", name = input$compareSite,
                  marker = list(color = "#AB0520"), text = round(c(hb$q0, hb$q1, hb$q2), 1),
                  textposition = "outside",
                  hovertemplate = paste0("<b>", input$compareSite, "</b><br>%{x}: %{y:.2f}<extra></extra>")) %>%
        plotly_theme() %>%
        plotly::layout(barmode = "group", xaxis = list(title = ""),
                       yaxis = list(title = "effective species")))
    }
    df <- data.frame(q = qlab, v = c(hn$q0, hn$q1, hn$q2))
    plot_ly(df, x = ~q, y = ~v, type = "bar",
            marker = list(color = c("#13632b", "#1a7f37", "#5cb56e")),
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
                line = list(color = "#13632b", width = 3), name = "expected species",
                hovertemplate = "%{x} individuals<br>%{y:.1f} species<extra></extra>") %>%
      plotly_theme(legend = FALSE) %>%
      plotly::layout(xaxis = list(title = "individuals sampled"),
                     yaxis = list(title = "expected species"))
  })

  output$accumPlot <- renderPlotly({
    d <- rv$data; req(d)
    ac <- accumulation_by_bout(d)
    if (is.null(ac)) return(note_plot("Not enough bouts for accumulation<br><span style='font-size:13px'>try widening the date window at left</span>"))
    plot_ly() %>%
      add_trace(x = ac$bouts, y = ac$richness + ac$sd, type = "scatter", mode = "lines",
                line = list(width = 0), showlegend = FALSE, hoverinfo = "skip") %>%
      add_trace(x = ac$bouts, y = pmax(0, ac$richness - ac$sd), type = "scatter",
                mode = "lines", fill = "tonexty", fillcolor = "rgba(47,127,181,0.14)",
                line = list(width = 0), name = "±1 SD", hoverinfo = "skip") %>%
      add_trace(x = ac$bouts, y = ac$richness, type = "scatter", mode = "lines+markers",
                line = list(color = "#2f7fb5", width = 3), marker = list(size = 5),
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
      pcttxt <- if (is.finite(pct)) sprintf(" (~%+.0f%%/yr)", pct) else ""
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
    pcttxt <- if (is.finite(pct)) sprintf(" (~%+.0f%%/yr)", pct) else ""
    sigtxt <- if (sig) sprintf("statistically clear (p = %.3f)", p)
              else sprintf("not statistically distinguishable from no change (p = %.2f)",
                           if (is.finite(p)) p else NA)
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
      name = "observed", line = list(color = "#13632b", width = 3),
      marker = list(size = 9, color = "#13632b"),
      hovertemplate = paste0("%{x}: %{y:.1f} ", ytitle, "<extra></extra>"))
    pred <- attr(t, "pred")
    if (!is.null(pred) && length(pred) == nrow(t)) {
      p <- p %>% add_trace(x = t$year, y = pred, mode = "lines", name = "trend",
        line = list(color = "#c9a300", width = 2, dash = "dash"),
        hoverinfo = "skip", inherit = FALSE)
    }
    plotly_theme(p) %>% plotly::layout(
      xaxis = list(title = "", dtick = 1),
      yaxis = list(title = ytitle, rangemode = "tozero"))
  })

  # ---- Seasonality --------------------------------------------------------
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
          line = list(color = "#13632b", width = 3), marker = list(size = 7, color = "#13632b"),
          hovertemplate = paste0("<b>", input$site, "</b><br>%{x}: %{y:.1f} /100TN<extra></extra>"))
      if (!is.null(sB) && nrow(sB))
        p <- p %>% add_trace(x = month.abb[sB$mon], y = sB$cpn, type = "scatter",
          mode = "lines+markers", name = input$compareSite,
          line = list(color = "#AB0520", width = 3, dash = "dot"), marker = list(size = 7, color = "#AB0520"),
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
          line = list(color = pal[[sp]] %||% "#13632b", width = 2),
          marker = list(size = 6, color = pal[[sp]] %||% "#13632b"),
          hovertemplate = paste0("<b>", sp, "</b><br>%{x}: %{y:.1f} /100TN<extra></extra>"))
      }
      return(plotly_theme(p) %>% plotly::layout(
        xaxis = list(title = "", categoryorder = "array", categoryarray = month.abb),
        yaxis = list(title = "catch per 100 trap-nights")))
    }
    s <- seasonality(d, by_species = FALSE)
    if (is.null(s) || !nrow(s)) return(note_plot("No seasonal data<br><span style='font-size:13px'>try widening the date window at left</span>"))
    plot_ly(x = month.abb[s$mon], y = s$cpn, type = "scatter", mode = "lines+markers",
            name = "all ground beetles", fill = "tozeroy", fillcolor = "rgba(19,99,43,0.16)",
            line = list(color = "#13632b", width = 3), marker = list(size = 7, color = "#13632b"),
            hovertemplate = "%{x}: %{y:.1f} per 100 trap-nights<extra></extra>") %>%
      plotly_theme(legend = TRUE) %>%   # single labelled series: it's the whole carabid catch, all taxa pooled
      plotly::layout(xaxis = list(title = "", categoryorder = "array", categoryarray = month.abb),
                     yaxis = list(title = "catch per 100 trap-nights"))
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

  output$map <- renderLeaflet({
    si <- SITE_INDEX
    base <- leaflet() %>% addProviderTiles("CartoDB.Positron") %>% setView(-98, 39, zoom = 3)
    if (is.null(si)) return(base)
    si <- si[!is.na(si$lat), ]
    sp <- input$rangeSpecies %||% ""
    if (sp != "" && !is.null(SPECIES_SITES)) {
      rng <- SPECIES_SITES[SPECIES_SITES$scientificName == sp, ]
      rng <- merge(rng, si[, c("site", "name", "lat", "lng")],
                   by.x = "siteID", by.y = "site")
      if (!nrow(rng)) return(base)
      return(base %>% addCircleMarkers(data = rng, lng = ~lng, lat = ~lat, layerId = ~siteID,
        radius = ~pmax(6, sqrt(individualCount) * 2.2), color = "#13632b",
        fillOpacity = 0.75, stroke = TRUE, weight = 1.5,
        label = ~lapply(sprintf("<b>%s</b><br><i>%s</i>: %s individuals",
          siteID, sp, fmt_int(individualCount)), htmltools::HTML)))
    }
    pal <- c(neon = "#13632b", demo = "#c9a300")
    m <- base %>% addCircleMarkers(data = si, lng = ~lng, lat = ~lat, layerId = ~site,
        radius = ~pmax(6, sqrt(richness) * 4), color = ~unname(pal[source]),
        fillOpacity = 0.7, stroke = TRUE, weight = 1.5,
        label = ~lapply(sprintf("<b>%s</b> · %s<br>%d species · %s individuals<br>dominant: <i>%s</i>%s",
          site, name, richness, fmt_int(individuals), dominant,
          ifelse(source == "demo", "<br><b>demo data</b>", "")), htmltools::HTML))
    cur <- isolate(rv$siteCode)   # ring the loaded site so the map ↔ single-site view connect
    if (!is.null(cur)) {
      cs <- si[si$site == cur, , drop = FALSE]
      if (nrow(cs) && !is.na(cs$lat))
        m <- m %>% addCircleMarkers(lng = cs$lng, lat = cs$lat, radius = 15, color = "#FFD200",
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
      addCircleMarkers(lng = cs$lng, lat = cs$lat, radius = 15, color = "#FFD200",
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
                " and normalise the 2018 trap-count and 2023 plot-count protocol changes via per-trap-night effort.")),
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
