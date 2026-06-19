# ===========================================================================
# report_pdf.R — deploy-safe server-side PDF site report (Ground Beetle Tracker).
#
# A TRUE vector PDF from base grDevices + grid + ggplot2 (already deps), streamed
# by a Shiny downloadHandler. NO LaTeX, NO headless Chrome, NO extra packages.
# Composer primitives ported from the Small Mammal Tracker; content is beetle
# count-data (community / diversity / seasonality / trends) — no mark-recapture.
# Verify without Shiny:
#   Rscript -e 'source("global.R"); source("R/report_pdf.R");
#     d <- clean_beetle(readRDS("data/sites/GRSM.rds"));
#     render_beetle_report("test.pdf", d, "GRSM · Great Smoky Mountains", FALSE)'
# ===========================================================================
suppressPackageStartupMessages(library(grid))

PDF_DEV <- if (isTRUE(capabilities("cairo"))) grDevices::cairo_pdf else grDevices::pdf

PG <- list(w = 8.5, h = 11, margin = 0.75, lineH = 0.165,
           navy = DDL$navy, forest = DDL$forest, green = DDL$green, gold = DDL$gold2,
           cardinal = DDL$cardinal, sky = DDL$sky, ink = DDL$ink, muted = DDL$muted,
           line = DDL$line, tint = "#eef5ef", zebra = "#f4f8f4")
PG$cw <- PG$w - 2 * PG$margin
PG$ch <- PG$h - 2 * PG$margin

ascii <- function(x) {
  x <- gsub("—|–", "-", x); x <- gsub("·", " | ", x); x <- gsub("≈", "~", x)
  x <- gsub("±", "+/-", x); x <- gsub("≥", ">=", x); x <- gsub("≤", "<=", x)
  x <- gsub("→", "to", x); x <- gsub("×", "x", x)
  enc2utf8(iconv(x, "UTF-8", "latin1", sub = ""))
}
gy <- function(yTop) unit(1, "npc") - unit(yTop, "in")

wrap_to_width <- function(txt, fontsize, width_in, fontface = 1) {
  gp <- gpar(fontsize = fontsize, fontface = fontface)
  words <- strsplit(txt, " ")[[1]]; lines <- character(0); cur <- ""
  for (w in words) {
    test <- if (nzchar(cur)) paste(cur, w) else w
    wpx <- convertWidth(grobWidth(textGrob(test, gp = gp)), "in", valueOnly = TRUE)
    if (wpx > width_in && nzchar(cur)) { lines <- c(lines, cur); cur <- w } else cur <- test
  }
  c(lines, cur)
}
draw_para <- function(txt, yTop, fontsize = 10, col = PG$ink, fontface = 1, gapAfter = 0.10) {
  for (ln in wrap_to_width(ascii(txt), fontsize, PG$cw, fontface)) {
    grid.text(ln, x = unit(0, "npc"), y = gy(yTop), just = c("left", "top"),
              gp = gpar(fontsize = fontsize, col = col, fontface = fontface))
    yTop <- yTop + PG$lineH
  }
  yTop + gapAfter
}
draw_h4 <- function(txt, yTop) {
  grid.text(ascii(txt), x = unit(0, "npc"), y = gy(yTop), just = c("left", "top"),
            gp = gpar(fontsize = 11, fontface = "bold", col = PG$forest))
  yTop + 0.24
}
draw_stat_grid <- function(cells, yTop, ncol, cellH = 0.5, gap = 0.10) {
  n <- length(cells); cwn <- 1 / ncol
  for (i in seq_len(n)) {
    r <- (i - 1) %/% ncol; cc <- (i - 1) %% ncol
    x0 <- cc * cwn; yc <- yTop + r * (cellH + gap)
    grid.rect(x = unit(x0, "npc") + unit(2, "pt"), y = gy(yc),
              width = unit(cwn, "npc") - unit(4, "pt"), height = unit(cellH, "in"),
              just = c("left", "top"), gp = gpar(fill = PG$tint, col = NA))
    grid.rect(x = unit(x0, "npc") + unit(2, "pt"), y = gy(yc),
              width = unit(3, "pt"), height = unit(cellH, "in"),
              just = c("left", "top"), gp = gpar(fill = PG$forest, col = NA))
    grid.text(ascii(cells[[i]][1]), x = unit(x0, "npc") + unit(11, "pt"), y = gy(yc + 0.12),
              just = c("left", "top"), gp = gpar(fontsize = 17, fontface = "bold", col = PG$forest))
    grid.text(ascii(cells[[i]][2]), x = unit(x0, "npc") + unit(11, "pt"), y = gy(yc + 0.40),
              just = c("left", "top"), gp = gpar(fontsize = 8.5, col = PG$muted))
  }
  yTop + ceiling(n / ncol) * (cellH + gap) + 0.04
}
draw_table <- function(cols, rows, colx, yTop, faces = rep(1, length(cols)),
                       fs = 9, rowH = 0.205, repeat_header) {
  draw_header <- function(yT) {
    for (j in seq_along(cols))
      grid.text(ascii(cols[j]), x = unit(colx[j], "npc"), y = gy(yT), just = c("left", "top"),
                gp = gpar(fontface = "bold", fontsize = fs, col = PG$forest))
    grid.lines(x = unit(c(0, 1), "npc"), y = gy(yT + 0.17), gp = gpar(col = PG$line, lwd = 1))
    yT + 0.26
  }
  yTop <- draw_header(yTop)
  for (i in seq_along(rows)) {
    if (yTop + rowH > PG$ch - 0.45) yTop <- draw_header(repeat_header())
    if (i %% 2 == 0)
      grid.rect(x = unit(0, "npc"), y = gy(yTop), width = unit(1, "npc"), height = unit(rowH, "in"),
                just = c("left", "top"), gp = gpar(fill = PG$zebra, col = NA))
    r <- rows[[i]]
    for (j in seq_along(r))
      grid.text(ascii(r[j]), x = unit(colx[j], "npc"), y = gy(yTop + 0.02), just = c("left", "top"),
                gp = gpar(fontsize = fs, fontface = faces[j]))
    yTop <- yTop + rowH
  }
  yTop + 0.12
}

theme_report <- function(base = 9) {
  ggplot2::theme_minimal(base_size = base) + ggplot2::theme(
    plot.title    = ggplot2::element_text(face = "bold", colour = PG$forest, size = base + 2),
    plot.subtitle = ggplot2::element_text(colour = PG$muted, size = base - 1),
    plot.caption  = ggplot2::element_text(colour = PG$muted, size = base - 2, hjust = 0),
    plot.title.position = "plot", plot.caption.position = "plot",
    axis.title = ggplot2::element_text(colour = PG$ink, size = base - 1),
    axis.text  = ggplot2::element_text(colour = PG$ink),
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major = ggplot2::element_line(colour = PG$line, linewidth = 0.3),
    legend.position = "none")
}
note_gg <- function(msg = "Not enough data for this window") {
  ggplot2::ggplot() + ggplot2::annotate("text", 0, 0, label = msg, colour = PG$muted, size = 4) +
    ggplot2::theme_void()
}
scope_cap <- function(d) {
  tn <- tryCatch(effort_trapnights(d), error = function(e) NA_real_)
  dr <- range(d$date, na.rm = TRUE)
  ascii(sprintf("NEON ground-beetle pitfall trapping  |  %s to %s  |  %s trap-nights",
                format(dr[1], "%b %Y"), format(dr[2], "%b %Y"),
                if (is.finite(tn)) format(round(tn), big.mark = ",") else "?"))
}

# Community composition bar (species-level, by catch per 100 trap-nights).
chart_community <- function(d) {
  ct <- tryCatch(community_table(d), error = function(e) NULL)
  if (is.null(ct)) return(note_gg())
  ct <- utils::head(ct[ct$species_level %in% TRUE, , drop = FALSE], 12)
  if (!nrow(ct)) return(note_gg("No species-level identifications"))
  ct$sci <- factor(ct$scientificName, levels = rev(ct$scientificName))
  ggplot2::ggplot(ct, ggplot2::aes(.data$cpn, .data$sci)) +
    ggplot2::geom_col(fill = PG$green, width = 0.72) +
    ggplot2::geom_text(ggplot2::aes(label = format(.data$individuals, big.mark = ",")),
      hjust = -0.12, size = 3, colour = PG$muted) +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0, 0.18))) +
    ggplot2::labs(title = "Carabid community — most abundant first",
      subtitle = "Bar = catch per 100 trap-nights; label = individuals",
      x = "catch per 100 trap-nights", y = NULL, caption = scope_cap(d)) +
    theme_report() + ggplot2::theme(panel.grid.major.y = ggplot2::element_blank(),
      axis.text.y = ggplot2::element_text(face = "italic", colour = PG$ink))
}
# Monthly activity-density curve.
chart_season <- function(d) {
  s <- tryCatch(seasonality(d, by_species = FALSE), error = function(e) NULL)
  if (is.null(s) || !nrow(s)) return(note_gg())
  s$month <- factor(month.abb[s$mon], levels = month.abb)
  ggplot2::ggplot(s, ggplot2::aes(.data$month, .data$cpn, group = 1)) +
    ggplot2::geom_area(fill = "#cfe6d6", colour = NA) +
    ggplot2::geom_line(colour = PG$forest, linewidth = 0.9) +
    ggplot2::geom_point(colour = PG$forest, size = 1.6) +
    ggplot2::expand_limits(y = 0) +
    ggplot2::labs(title = "Seasonal activity-density", subtitle = "Mean catch per 100 trap-nights by month",
      x = NULL, y = "catch / 100 trap-nights", caption = scope_cap(d)) +
    theme_report()
}

FOOT <- paste("Data: NEON Ground Beetles sampled from pitfall traps (DP1.10022.001).",
  "Generated by the NEON Ground Beetle Tracker - Desert Data Labs.",
  "Unofficial educational summary; not affiliated with NEON, Battelle, or NSF.")
new_page <- function(page_i, title, footer_full = FALSE) {
  grid.newpage()
  pushViewport(viewport(width = unit(PG$cw, "in"), height = unit(PG$ch, "in"), name = "content"))
  if (page_i > 1) {
    hl <- ascii(title); if (nchar(hl) > 50) hl <- paste0(substr(hl, 1, 49), "…")
    grid.text(hl, x = unit(0, "npc"), y = gy(0), just = c("left", "top"),
              gp = gpar(fontsize = 10, fontface = "bold", col = PG$forest))
    grid.text("NEON Ground Beetle Report", x = unit(1, "npc"), y = gy(0),
              just = c("right", "top"), gp = gpar(fontsize = 8.5, col = PG$muted))
    grid.lines(x = unit(c(0, 1), "npc"), y = gy(0.24), gp = gpar(col = PG$line, lwd = 1))
  }
  ftxt <- if (footer_full)
    paste(FOOT, "Hill numbers (Jost 2006); rarefaction (Hurlbert 1971); accumulation",
          "(Gotelli & Colwell 2001). Richness counts species-level IDs only; abundance keeps all taxa.") else FOOT
  fl <- wrap_to_width(ascii(ftxt), 7, PG$cw)
  for (k in seq_along(fl))
    grid.text(fl[k], x = unit(0, "npc"), y = unit((length(fl) - k) * 0.12 + 0.04, "in"),
              just = c("left", "bottom"), gp = gpar(fontsize = 7, col = PG$muted))
}
embed_chart <- function(p, yTop, height_in) {
  vp <- viewport(x = unit(0, "npc"), y = gy(yTop), width = unit(PG$cw, "in"),
                 height = unit(height_in, "in"), just = c("left", "top"))
  tryCatch(print(p, vp = vp),
           error = function(e) grid.text("(chart unavailable)", y = gy(yTop + height_in / 2),
                                          gp = gpar(col = PG$muted, fontsize = 9)))
  yTop + height_in + 0.18
}

# ---- the composer ----------------------------------------------------------
render_beetle_report <- function(file, d, label, is_demo = FALSE, env = NULL) {
  PDF_DEV(file, width = PG$w, height = PG$h, onefile = TRUE)
  on.exit(grDevices::dev.off(), add = TRUE)

  qa <- tryCatch(taxon_qa(d), error = function(e) NULL)
  ct <- tryCatch(community_table(d), error = function(e) NULL)
  spct <- if (!is.null(ct)) ct[ct$species_level %in% TRUE, , drop = FALSE] else NULL
  counts <- if (!is.null(spct)) spct$individuals else numeric(0)
  hn <- tryCatch(hill_numbers(counts), error = function(e) list(q0 = NA, q1 = NA, q2 = NA, even = NA))
  tn <- tryCatch(effort_trapnights(d), error = function(e) NA_real_)
  dr <- range(d$date, na.rm = TRUE)
  n_ind <- if (!is.null(ct)) sum(ct$individuals) else 0
  n_sp  <- if (!is.null(spct)) nrow(spct) else 0

  # ---------- PAGE 1 ----------
  new_page(1, label)
  grid.text("NEON Ground Beetle Tracker", x = unit(0, "npc"), y = gy(0.0), just = c("left", "top"),
            gp = gpar(fontsize = 20, fontface = "bold", col = PG$forest))
  sub <- ascii(sprintf("%s   |   %s to %s%s", label, format(dr[1], "%b %Y"), format(dr[2], "%b %Y"),
                       if (is_demo) "   |   DEMO (illustrative)" else ""))
  grid.text(sub, x = unit(0, "npc"), y = gy(0.34), just = c("left", "top"),
            gp = gpar(fontsize = 10.5, col = PG$muted))
  y <- 0.72
  y <- draw_stat_grid(list(
    c(format(n_sp, big.mark = ","), "species (species-level)"),
    c(format(n_ind, big.mark = ","), "individuals caught"),
    c(if (is.na(hn$q1)) "-" else format(round(hn$q1, 1)), "q1 effective species"),
    c(if (is.finite(tn)) format(round(tn), big.mark = ",") else "-", "trap-nights")), y, ncol = 4)

  y <- draw_h4("Diversity", y)
  even_word <- if (is.na(hn$even)) "a single-species catch"
               else if (hn$even >= 0.6) "an even community"
               else if (hn$even >= 0.35) "a moderately uneven community"
               else "a community dominated by a few species"
  y <- draw_para(sprintf(paste("Hill numbers are effective species counts (q0 >= q1 >= q2): q0 = %s species,",
    "q1 = %s common species, q2 = %s dominant species - %s. Evenness (q1/q0) = %s."),
    if (is.na(hn$q0)) "-" else as.integer(hn$q0), if (is.na(hn$q1)) "-" else round(hn$q1, 1),
    if (is.na(hn$q2)) "-" else round(hn$q2, 1), even_word, if (is.na(hn$even)) "-" else hn$even),
    y, 9.5, gapAfter = 0.06)
  if (!is.null(qa))
    y <- draw_para(sprintf(paste("Of %s individuals, %s%% are left at genus/family; richness counts the",
      "%s species-level taxa only, abundance keeps every beetle trapped."),
      format(qa$ind_total, big.mark = ","), qa$pct_ind_higher, format(qa$species, big.mark = ",")),
      y, 8.5, PG$muted, gapAfter = 0.12)
  y <- embed_chart(chart_community(d), y, height_in = 4.3)

  # ---------- PAGE 2 ----------
  new_page(2, label); y <- 0.5
  y <- draw_h4("Species recorded", y)
  if (!is.null(spct) && nrow(spct)) {
    occ <- tryCatch(occupancy_table(d), error = function(e) NULL)
    sp_show <- utils::head(spct, 16)
    rows <- lapply(seq_len(nrow(sp_show)), function(i) {
      o <- if (!is.null(occ)) occ$occ[match(sp_show$scientificName[i], occ$scientificName)] else NA
      c(sp_show$scientificName[i], format(sp_show$individuals[i], big.mark = ","),
        if (is.na(sp_show$cpn[i])) "-" else as.character(sp_show$cpn[i]),
        if (is.na(o)) "-" else paste0(o, "%"))
    })
    rh <- function() { new_page(2, label); 0.5 }
    y <- draw_table(c("Species", "Individuals", "/100 TN", "Occupancy"), rows,
                    colx = c(0.00, 0.50, 0.68, 0.85), yTop = y, faces = c(3, 1, 1, 1), repeat_header = rh)
    more_n <- nrow(spct) - nrow(sp_show)
    if (more_n > 0) y <- draw_para(sprintf("+ %d more species recorded", more_n), y, 9, PG$muted, 3)
    y <- draw_para(paste("Catch per 100 trap-nights (/100 TN) makes effort comparable; occupancy is the share",
      "of sampling bouts a species appears in (naive frequency of occurrence)."), y, 8.5, PG$muted)
  } else y <- draw_para("No species-level identifications in this window.", y, 9.5, PG$muted)

  # seasonality + trend
  y <- draw_h4("Seasonality", y)
  s <- tryCatch(seasonality(d, by_species = FALSE), error = function(e) NULL)
  if (!is.null(s) && nrow(s)) {
    pk <- s$mon[which.max(s$cpn)]; thr <- 0.2 * max(s$cpn, na.rm = TRUE)
    act <- month.abb[sort(s$mon[s$cpn >= thr])]
    y <- draw_para(sprintf("Activity peaks in %s; the active window (months >= 20%% of peak catch) spans %s.",
      month.name[pk], if (length(act)) paste(act, collapse = ", ") else month.abb[pk]), y, 9.5, gapAfter = 0.06)
  } else y <- draw_para("Not enough monthly data to characterise seasonality.", y, 9.5, PG$muted)

  y <- draw_h4("Inter-annual trend", y)
  yr <- d[!is.na(d$year), , drop = FALSE]
  if (nrow(yr) && length(unique(yr$year)) >= 2) {
    cap <- stats::aggregate(individualCount ~ year, yr, sum)
    eff <- unique(yr[, c("plotID", "collectDate", "year", "trapnights")])
    eff <- stats::aggregate(trapnights ~ year, eff, sum)
    m <- merge(cap, eff, by = "year"); m <- m[m$trapnights > 0, , drop = FALSE]
    if (nrow(m) >= 2) {
      m$cpn <- 100 * m$individualCount / m$trapnights
      fit <- stats::lm(cpn ~ year, m); sl <- stats::coef(fit)[2]
      pv <- tryCatch(summary(fit)$coefficients[2, 4], error = function(e) NA_real_)
      dir <- if (is.na(pv) || pv > 0.1) "roughly flat" else if (sl > 0) "rising" else "declining"
      y <- draw_para(sprintf(paste("Across %d years, effort-adjusted catch is %s (%+.1f per 100 trap-nights/yr%s).",
        "Short series are noisy - read the direction, not the decimal."),
        length(unique(m$year)), dir, sl,
        if (is.na(pv)) "" else sprintf(", p = %.2f", pv)), y, 9.5, gapAfter = 0.06)
    }
  } else y <- draw_para("Fewer than two years in this window - no trend.", y, 9.5, PG$muted)

  # environmental driver (if env available)
  if (!is.null(env)) {
    rk <- tryCatch(env_corr_all(d, env), error = function(e) NULL)
    if (!is.null(rk) && nrow(rk)) {
      top <- rk[1, ]
      y <- draw_h4("Environmental driver", y)
      y <- draw_para(sprintf(paste("Beetle activity tracks %s most closely (deseasonalized r = %.2f at a %d-month",
        "lag). A correlation, not a cause - a lead worth investigating."),
        top$label, top$r, top$lag), y, 9.5, PG$muted)
    }
  }
  y <- embed_chart(chart_season(d), y, height_in = 2.9)
  invisible(file)
}
