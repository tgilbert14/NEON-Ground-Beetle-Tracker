# ===========================================================================
# NEON Ground Beetle Tracker — ui.R
# A clean, card-based dashboard for exploring carabid biodiversity across the
# National Ecological Observatory Network.
# ===========================================================================

card_head <- function(icon, title, ...)
  bslib::card_header(class = "with-info", bsicons::bs_icon(icon),
                     tags$span(class = "ch-title", " ", title), ...)

ui <- bslib::page_sidebar(
  theme = app_theme,
  window_title = "NEON Ground Beetle Tracker",
  fillable = FALSE,

  tags$head(
    tags$link(rel = "stylesheet",
      href = "https://fonts.googleapis.com/css2?family=Rubik:wght@400;500;600;700;800&display=swap"),
    tags$link(rel = "stylesheet", href = "styles.css"),
    # Remember the last site across visits, and honour ?site=SRER in the URL so a
    # site is bookmarkable/shareable. Polls until Shiny + jQuery exist (load-order
    # safe); every step is wrapped so a privacy-locked localStorage never breaks boot.
    tags$script(HTML(
      "(function(){function init(){if(!window.Shiny||!window.jQuery){return setTimeout(init,50);} ",
      "jQuery(document).on('shiny:connected',function(){try{",
      "var p=new URLSearchParams(window.location.search).get('site');",
      "var s=p||localStorage.getItem('gbt_site');",
      "if(s){Shiny.setInputValue('restore_site',s,{priority:'event'});}}catch(e){}});",
      "Shiny.addCustomMessageHandler('gbt_remember',function(s){try{if(s){localStorage.setItem('gbt_site',s);}}catch(e){}});",
      "function hideOv(){var o=document.getElementById('bootOverlay');if(o){o.classList.add('is-hidden');setTimeout(function(){if(o&&o.parentNode){o.parentNode.removeChild(o);}},600);}} ",
      "function showWelcome(){try{if(!localStorage.getItem('gbt_seen')){localStorage.setItem('gbt_seen','1');Shiny.setInputValue('first_visit',1,{priority:'event'});}}catch(e){}}",
      # first-visit: the splash mascot waves hello once (mirrors the flagship's localStorage gate)
      "function waveMascot(){try{if(localStorage.getItem('smtMascotSeen')==='1')return;var g=document.querySelector('.splash-guide');if(g){g.classList.add('wave');localStorage.setItem('smtMascotSeen','1');setTimeout(function(){g.classList.remove('wave');},3300);}}catch(e){}}",
      # celebration: a beetle hops up + fades on a legendary find (no confetti in this app — exposed for parity/future use)
      "window.mascotCheer=function(big){try{if(window.matchMedia&&window.matchMedia('(prefers-reduced-motion: reduce)').matches)return;var src=document.querySelector('#bootOverlay .mascot')||document.querySelector('.sg-mascot .mascot');if(!src)return;var wrap=document.createElement('div');wrap.className='mascot-cheer';wrap.appendChild(src.cloneNode(true));document.body.appendChild(wrap);setTimeout(function(){if(wrap.parentNode){wrap.parentNode.removeChild(wrap);}},1700);}catch(e){}};",
      "jQuery(document).one('shiny:idle',function(){hideOv();showWelcome();waveMascot();});setTimeout(hideOv,20000);",   # fallback: overlay only, no modal on half-rendered app
      "}init();})();"))
  ),
  useShinyjs(),

  # ---- sidebar -----------------------------------------------------------
  sidebar = sidebar(
    width = 320, class = "control-deck",
    div(class = "brand",
      div(class = "brand-mark", "\U0001FAB2"),  # beetle
      div(
        div(class = "brand-title", "Ground Beetle Tracker"),
        div(class = "brand-sub", "NEON carabid biodiversity")
      ),
      # light/dark toggle — bslib flips data-bs-theme; charts read input$colorMode
      div(class = "mode-toggle", input_dark_mode(id = "colorMode", mode = "light"))
    ),

    selectInput("stateSel", label = tagList(bs_icon("geo-alt-fill"), " 1 · Pick a state"),
                choices = NULL, width = "100%"),
    selectInput("site", label = tagList(bs_icon("pin-map-fill"), " 2 · Pick a site"),
                choices = NULL, width = "100%"),
    uiOutput("siteBio"),

    dateRangeInput("dateRange", label = tagList(bs_icon("calendar3"), " 3 · Date window"),
                   format = "yyyy-mm", startview = "year",
                   start = "2016-01-01", end = Sys.Date()),

    actionButton("loadBtn", tagList(bs_icon("bug-fill"), " Load this site"),
                 class = "btn-primary btn-lg w-100"),
    actionButton("surpriseBtn", tagList(bs_icon("shuffle"), " Surprise me"),
                 class = "btn-outline-success w-100 mt-2"),
    downloadButton("reportPdf", tagList(bs_icon("file-earmark-pdf"), " Site report (PDF)"),
                   class = "btn-outline-secondary w-100 mt-2"),
    downloadButton("reportCsv", tagList(bs_icon("filetype-csv"), " Data + codebook"),
                   class = "btn-outline-secondary w-100 mt-2"),
    div(class = "demo-hint", bs_icon("info-circle"),
        if (isTRUE(LIVE_FETCH))
          " Picking a site loads it automatically. Bundled sites are instant; live NEON pulls take a moment. Adjust the date window and tap Load to refine."
        else
          " Picking a site loads it automatically. The date window snaps to that site's coverage. Narrow it and tap Load to zoom in."),

    uiOutput("srcNote"),

    div(class = "compare-pick",
      selectInput("compareSite",
        label = tagList(bs_icon("layers-half"), " Compare with (optional)"),
        choices = NULL, width = "100%"),
      div(class = "demo-hint", bs_icon("info-circle"),
          " Overlaid on the Diversity & Seasonality tabs.")),

    hr(class = "deck-hr"),
    div(class = "deck-foot",
      bs_icon("database"), " NEON ", tags$code("DP1.10022.001"),
      br(), tags$a(href = "https://www.neonscience.org/data-collection/ground-beetles",
                   target = "_blank", bs_icon("box-arrow-up-right"), " about the data"),
      br(), tags$a(href = "https://desertdatalabs.com", target = "_blank",
                   bs_icon("box-arrow-up-right"), " Desert Data Labs")
    )
  ),

  # ---- boot / cold-start overlay (removed by JS once Shiny goes idle) -----
  div(id = "bootOverlay", class = "boot-overlay",
    div(class = "load-spin mascot-spin", MASCOT_CRITTER),
    div(class = "boot-msg", "Waking up the Ground Beetle Tracker…"),
    div(class = "boot-sub", "Loading 46 NEON sites")),

  # ---- hero + stats ------------------------------------------------------
  div(class = "app-hero",
    h1(class = "app-title", "NEON Ground Beetle Tracker",
       span(class = "title-tag", "unofficial")),
    p(class = "app-subtitle",
      "Ground beetles (Carabidae) are a textbook bioindicator. Explore who lives where, how diverse each site is, and when beetles are active, across the National Ecological Observatory Network.")
  ),
  uiOutput("heroStats"),
  # ---- splash: the national PICKER map is the front door (flagship pattern) ----
  div(id = "splashHome",
    div(class = "splash-guide",
      div(class = "sg-bubble", "Pick a site to start!"),
      div(class = "sg-mascot", MASCOT_CRITTER)),
    uiOutput("splash"),
    div(class = "splash-picker",
      div(class = "splash-map-hint", bs_icon("hand-index-thumb"),
        " Tap a site to explore it. Dot size is species richness, colour is how many beetles were caught."),
      mapPickerUI("picker", height = "520px", spinner = DDL$forest),
      # Closed-by-default text fallback to the map: every site, one tap away. Each
      # link drives the SAME input$siteExplore the popup's "Explore" button uses,
      # so selection runs the app's normal cascade -> auto-load. Built from
      # SITE_INDEX (real codes/names/state + total individuals).
      local({
        idx <- SITE_INDEX
        if (is.null(idx) || nrow(idx) == 0) NULL else {
          ord <- idx[order(idx$name), , drop = FALSE]
          tags$details(class = "picker-list",
            tags$summary(class = "picker-list-summary",
              tags$span(class = "pls-label", bs_icon("list-ul"),
                        tagList(" Browse all ", nrow(ord), " sites")),
              tags$span(class = "pls-chevron", bs_icon("chevron-down"))),
            div(class = "picker-list-grid",
              lapply(seq_len(nrow(ord)), function(i)
                tags$a(class = "picker-list-link", href = "#",
                  onclick = sprintf("Shiny.setInputValue('siteExplore','%s',{priority:'event'});return false;",
                                    ord$site[i]),
                  tags$b(ord$site[i]), sprintf(" · %s ", ord$name[i]),
                  tags$span(class = "pll-meta",
                    sprintf("%s · %s caught",
                            ord$state[i] %||% "—",
                            format(ord$individuals[i], big.mark = ",")))))))
        }
      }))),

  # ---- tabs --------------------------------------------------------------
  div(id = "mainTabsWrap",
    navset_card_tab(id = "tabs",

      nav_panel(
        title = tagList(bs_icon("collection"), " Overview"), value = "overview",
        uiOutput("overviewVerdict"),
        card(full_screen = TRUE,
          card_head("bar-chart-line-fill", "Carabid community, most abundant first",
            info_pop("Community composition",
              p("Each bar is a species; length is total ", tags$b("individuals"),
                " caught, and the label shows ", tags$b("catch per 100 trap-nights"),
                " so effort is accounted for."),
              p(tags$b("Activity, not density."), " Pitfall catch \U221D activity \U00D7 density, so fast, large, surface-active hunters (tiger beetles, ", tags$em("Pasimachus"), ") score high regardless of true abundance, so compare like body plans, not a tiger beetle against a litter specialist."))),
          spin(plotlyOutput("commBar", height = "460px"))),
        card(full_screen = TRUE,
          card_head("pin-map-fill", "Most widespread species, frequency of occurrence",
            info_pop("Frequency of occurrence (naive occupancy)",
              p("The share of ", tags$b("sampling bouts"), " (a plot on a date) in which each species turned up at least once, that is how ", tags$b("widespread"), " it is, not how abundant. A beetle can be ", tags$em("abundant but patchy"), " (a long bar above, short here) or ", tags$em("sparse but everywhere"), "."),
              p(tags$b("Two caveats."), " It's ", tags$b("naive"), ", not corrected for detection. And the denominator is bouts that caught ", tags$b("at least one ground beetle"), " (bouts with no carabids at all, rare in the active season, aren't in the data), so it slightly over-states how widespread a species is. Species-level IDs only."))),
          spin(plotlyOutput("occupancyPlot", height = "420px"))),
        h4(class = "section-title", bs_icon("binoculars"), " Meet the beetles"),
        uiOutput("meetBeetles")
      ),

      nav_panel(
        title = tagList(bs_icon("diagram-3-fill"), " Diversity"), value = "diversity",
        uiOutput("diversityVerdict"),
        uiOutput("qaNote"),
        layout_columns(col_widths = c(5, 7),
          card(full_screen = TRUE,
            card_head("diagram-3-fill", "Diversity profile, effective species",
              info_pop("Hill numbers",
                p("Diversity in one unit, an ", tags$b("effective number of species"), ":"),
                tags$ul(
                  tags$li(tags$b("q0"), " richness (all species count equally)"),
                  tags$li(tags$b("q1"), " exp(Shannon), common species"),
                  tags$li(tags$b("q2"), " inverse Simpson, dominant species")),
                p("When q1 sits near q0 the community is even; far below = a few species dominate."))),
            spin(plotlyOutput("hillPlot", height = "300px")),
            uiOutput("hillNote")),
          card(full_screen = TRUE,
            card_head("graph-up", "Rarefaction, richness at equal sample size",
              info_pop("Rarefaction",
                p("Expected species in a random subsample of ", tags$b("n individuals"),
                  " (Hurlbert 1971), with a ±1 SD band. Comparing at equal n stops a site that simply caught more beetles from looking falsely richer."))),
            spin(plotlyOutput("rarePlot", height = "300px")))
        ),
        card(full_screen = TRUE,
          card_head("graph-up-arrow", "Species accumulation across bouts",
            info_pop("Accumulation",
              p("As pitfall ", tags$b("bouts"), " accumulate, how many species have appeared? A flattening curve means the site's fauna is well sampled (averaged over random bout orders; Gotelli & Colwell 2001)."))),
          spin(plotlyOutput("accumPlot", height = "360px"))),
        card(full_screen = TRUE,
          card_head("bar-chart-steps", "Rank-abundance, the dominance curve",
            info_pop("Rank-abundance (Whittaker)",
              p("Species ranked from most to least abundant (log scale). The ", tags$b("shape"), " is the evenness story: a steep drop means a few species dominate; a shallow line means an even community, the same signal the Hill numbers above put into one number."))),
          spin(plotlyOutput("rankAbundance", height = "360px")))
      ),

      nav_panel(
        title = tagList(bs_icon("calendar-heart"), " Seasonality"), value = "seasonality",
        div(class = "tab-intro", bs_icon("info-circle"),
            " Beetle activity isn't constant. Pitfall catch tracks the warm season and each species' own peak."),
        uiOutput("seasonVerdict"),
        conditionalPanel("output.hasEnv == true",
          card(full_screen = TRUE,
            card_head("bar-chart-steps", "Which environmental driver does beetle activity track best?",
              info_pop("Driver comparison",
                p("For every co-located NEON driver, we scan lags 0–12 months and keep the ", tags$b("strongest correlation"), " with monthly catch-per-effort, after ", tags$b("deseasonalizing"), " both (so r reflects year-to-year anomalies, not the shared summer peak)."),
                p(tags$b("Reading r:"), " it runs −1…+1, where sign is the direction and size is how tightly they move together. It is ", tags$b("not"), " the % of activity explained (that's r²). Colour encodes the driver's identity; bar side-of-0 encodes the sign."),
                p(class = "qa-cite", bs_icon("exclamation-triangle"), " Correlation, not cause. Drivers co-vary and many lags are scanned, so read it as a lead to investigate."))),
            uiOutput("envCorrNote"),
            spin(plotlyOutput("envDriverRank", height = "300px"))),
          div(class = "env-pop-bar",
            div(class = "env-pop-row",
              div(class = "env-pop-sel",
                selectInput("envLayer", label = tagList(bs_icon("cloud-drizzle-fill"), " Overlay a driver on the activity curve"),
                            choices = c("None" = "none"), width = "100%"),
                uiOutput("envSplitNote")),
              div(class = "env-pop-lag",
                sliderInput("envLag", tagList(bs_icon("hourglass-split"), " Lead time (months)"),
                            min = 0, max = 12, value = 0, step = 1, width = "100%"),
                div(class = "env-lag-hint", "0 = same month · 3 = driver leads by 3 months"))),
            uiOutput("envSourceNote"))),
        card(full_screen = TRUE,
          card_head("activity", "Activity-density by month (catch per 100 trap-nights)",
            info_pop("Seasonality",
              p("Mean ", tags$b("catch per 100 trap-nights"), " by calendar month, the whole-community activity curve, pooling ", tags$b("every ground beetle (Carabidae) trapped"), " at this site, including records left at genus/family. Toggle to split it by the top species."))),
          div(class = "season-toggle",
            checkboxInput("seasonBySpecies", "Split by species", value = FALSE)),
          spin(plotlyOutput("seasonPlot", height = "440px"))),
        card(full_screen = TRUE,
          card_head("grid-3x3", "Phenology heatmap, each species' active months",
            info_pop("Phenology heatmap",
              p("Top species (rows) × calendar month (columns); each cell is that month's ", tags$b("catch per 100 trap-nights"), ", darker = more active. A month sampled but with none of that species is a real ", tags$b("0"), "; a month never sampled is left ", tags$b("blank"), " (a gap, not a zero). The pooled activity curve above hides that species peak at different times."))),
          spin(plotlyOutput("phenoHeat", height = "420px"))),
        conditionalPanel("input.envLayer && input.envLayer != 'none'",
          card(full_screen = TRUE,
            card_head("bullseye", "Environmental response, activity vs the driver",
              info_pop("Response scatter",
                p("Each point is one month: its ", tags$b("catch per 100 trap-nights"), " against the selected driver's value (with your ", tags$b("lag"), " applied). A rising cloud means more beetles when the driver is high; the dashed line is an OLS fit, the same signal as the ranking above, shown as a shape so you can spot thresholds."))),
            spin(plotlyOutput("envScatter", height = "400px"))))
      ),

      nav_panel(
        title = tagList(bs_icon("graph-up-arrow"), " Trends"), value = "trends",
        div(class = "tab-intro", bs_icon("info-circle"),
            " Are the beetles holding steady, booming, or declining? NEON's standardized effort makes year-to-year catch comparable, the backbone of insect-decline science."),
        uiOutput("trendVerdict"),
        card(full_screen = TRUE,
          card_head("graph-up-arrow", "Catch-per-effort by year, with fitted trend",
            info_pop("Inter-annual trend",
              p("Annual ", tags$b("catch per 100 trap-nights"), " (or raw counts when a bundle lacks effort), with an ordinary-least-squares trend line."),
              p("The slope and its p-value drive the verdict above. Short series (a few years) are noisy, so read the direction, not the decimal."))),
          spin(plotlyOutput("trendPlot", height = "440px")))
      ),

      nav_panel(
        title = tagList(bs_icon("map-fill"), " Biogeography"), value = "biogeo",
        div(class = "tab-head",
          div(class = "tab-head-text",
            h4("Carabid richness across NEON"),
            p("Each marker is a NEON site with beetle data. With no species picked, markers size by total richness; choose a species to map its range, sized by local abundance. Tap a site to load it.")),
          div(class = "map-controls",
            selectInput("rangeSpecies", tagList(bs_icon("search"), " Map a species' range"),
                        choices = NULL, width = "280px"))),
        uiOutput("biogeoVerdict"),
        spin(leafletOutput("map", height = "540px")),
        card(full_screen = TRUE,
          card_head("diagram-2", "Community ordination, who resembles whom",
            info_pop("PCoA ordination",
              p("Every point is a ", tags$b("site × year"), " beetle community, placed by ",
                tags$b("Bray–Curtis"), " dissimilarity (PCoA) so similar communities sit close together."),
              p("Points from the same site/biome cluster, the carabid biogeography signal. Computed across all bundled sites."))),
          spin(plotlyOutput("ordPlot", height = "440px"))),
        card(full_screen = TRUE,
          card_head("award", "Indicator species, each site's signature beetles",
            info_pop("Indicator value (IndVal)",
              p("The ", tags$b("Dufrêne–Legendre IndVal"), " (0–100) flags species that are both ",
                tags$b("concentrated in"), " and ", tags$b("reliably found at"), " one site."),
              tags$ul(
                tags$li(tags$b("Specificity"), ": share of the species' abundance that's at that site"),
                tags$li(tags$b("Fidelity"), ": share of that site's samples where it turns up")),
              p("High on both = a genuine signature of that place. Computed across all bundled sites; samples are plot × year."))),
          spin(DT::DTOutput("indicatorTable"))),
        card(card_head("table", "Site comparison"),
             spin(DT::DTOutput("siteTable")))
      ),

      nav_panel(
        title = tagList(bs_icon("info-circle"), " About"), value = "about",
        uiOutput("aboutPanel")
      )
    )
  ),

  # ---- footer ------------------------------------------------------------
  div(class = "ddl-footer",
    p(HTML("Built by <strong>Desert Data Labs</strong> · Tucson, AZ · get in touch →"),
      tags$a(href = "mailto:desertdatalabs@gmail.com?subject=NEON%20Ground%20Beetle%20Tracker",
             "desertdatalabs@gmail.com")),
    p(style = "font-size:12px;opacity:.85",
      "Data: NEON Ground Beetles sampled from pitfall traps (DP1.10022.001). Not affiliated with NEON, Battelle, or the NSF. An educational data-exploration tool.")
  )
)
