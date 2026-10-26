#!/usr/bin/env node

// Static shell contracts from the 2026-10-18 suite audit (items 17, 18, 21, 23
// and the SRER boot / deep-link fixes). Each check names the regression it blocks.

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const read = (file) => readFileSync(resolve(root, file), "utf8");
const server = read("server.R");
const ui = read("ui.R");
const picker = read("R/map_picker.R");
const css = read("www/styles.css");

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exitCode = 1;
}

function count(pattern, source) {
  return (source.match(pattern) || []).length;
}

// Return the brace-balanced body that opens at the first "{" at or after `from`
// (exclusive of the outer braces). Quote- and comment-aware for R source, so a
// brace inside a string or a # comment does not end the block early.
function braceBody(source, from) {
  const open = source.indexOf("{", from);
  if (open < 0) return "";
  let depth = 0;
  let quote = null;
  for (let i = open; i < source.length; i++) {
    const c = source[i];
    if (quote) {
      if (c === "\\") { i++; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === "'" || c === "`") { quote = c; continue; }
    if (c === "#") { const nl = source.indexOf("\n", i); if (nl < 0) break; i = nl; continue; }
    if (c === "{") depth++;
    else if (c === "}") {
      depth--;
      if (depth === 0) return source.slice(open + 1, i);
    }
  }
  return "";
}

// Every observer body that opens with `marker` (several observers may share a trigger).
function observerBodies(source, marker) {
  const out = [];
  let at = source.indexOf(marker);
  while (at >= 0) {
    out.push(braceBody(source, at + marker.length - 1));
    at = source.indexOf(marker, at + marker.length);
  }
  return out;
}

// Item 18: keepInView pins an open popup to a map that later shrinks to 0 px.
for (const [name, source] of [["R/map_picker.R", picker], ["server.R", server]]) {
  if (/keepInView\s*=\s*TRUE/.test(source)) fail(`${name} must not set keepInView = TRUE on a popup`);
}

// The resize path must not invalidate a hidden (0 px) map.
const onRender = (picker.match(/htmlwidgets::onRender\("([\s\S]*?)"\)/) || [])[1] || "";
if (!onRender) fail("R/map_picker.R onRender block not found");
// The guard must be the first thing each path does, so it cannot sit in dead code.
if (!/addEventListener\(\s*'resize'\s*,\s*function\s*\(\s*\)\s*\{\s*if\s*\(\s*el\.clientWidth\s*>\s*0\s*\)/.test(onRender)) {
  fail("R/map_picker.R resize listener must guard invalidateSize on el.clientWidth > 0");
}
if (!/function\s+kick\s*\(\s*\)\s*\{\s*try\s*\{\s*if\s*\(\s*el\.clientWidth\s*>\s*0\s*\)/.test(onRender)) {
  fail("R/map_picker.R timed kicks must guard on el.clientWidth > 0");
}

// Item 21: window_title lands on <body>; the page needs a real <title> and lang.
// Both are read from the page_fillable() call itself (up to its tags$head), so a
// hreflang elsewhere, or a title in some other tag, cannot satisfy the check.
if (/window_title/.test(ui)) fail("ui.R must not use window_title (it renders as a body attribute)");
const pageStart = ui.indexOf("bslib::page_fillable(");
const pageHead = pageStart < 0 ? -1 : ui.indexOf("tags$head(", pageStart);
const pageArgs = pageStart < 0 || pageHead < 0 ? "" : ui.slice(pageStart, pageHead);
if (!pageArgs) fail("ui.R bslib::page_fillable( ... tags$head( call not found");
if (!/(^|[^A-Za-z0-9_.$])title\s*=\s*"NEON Ground Beetle Tracker"/.test(pageArgs)) {
  fail('ui.R page_fillable() must set title = "NEON Ground Beetle Tracker"');
}
if (!/(^|[^A-Za-z0-9_.$])lang\s*=\s*"en"/.test(pageArgs)) fail('ui.R page_fillable() must set lang = "en"');
if (/fillable\s*=/.test(pageArgs.replace("bslib::page_fillable(", ""))) {
  fail("ui.R page_fillable() must not pass fillable = (it is not an argument and lands on <body>)");
}

// Item 17: banner text wraps as one prose child beside the icon.
const verdictCount = count(/class\s*=\s*"verdict-text"/g, server);
if (verdictCount !== 9) fail(`server.R must have 9 class = "verdict-text" banner spans; found ${verdictCount}`);
if (!/\.verdict-text\s*\{[^}]*min-width:\s*0/.test(css)) fail("www/styles.css must define a .verdict-text rule with min-width: 0");

// Item 23: Space on a role=button QC flag must not scroll the page. One delegated
// keydown handler in ui.R covers every flag; no inline onkeydown on the flags.
const qcHandler = ui.split("\n").find((line) =>
  /addEventListener\(\s*'keydown'/.test(line) && /qc-flag-click/.test(line)) || "";
if (!qcHandler) fail("ui.R must define one delegated document keydown handler for .qc-flag-click");
else {
  if (!/preventDefault\(\)/.test(qcHandler)) fail("ui.R QC keydown handler must call preventDefault()");
  if (!/'Enter'/.test(qcHandler) || !/' '/.test(qcHandler)) fail("ui.R QC keydown handler must handle Enter and Space");
  if (!/\.click\(\)/.test(qcHandler)) fail("ui.R QC keydown handler must click the flag");
}
if (/onkeydown\s*=/.test(server)) fail("server.R must not put an inline onkeydown on QC flags (use the delegated handler)");
if (!/qc-flag-click[\s\S]{0,400}onclick\s*=\s*sprintf\("Shiny\.setInputValue\('beetleQcInspect'/.test(server)) {
  fail("server.R QC flags must keep the beetleQcInspect onclick");
}

// Item 18: marker-bound popups must close before a map is hidden. leaflet's
// clearPopups() does not touch them, so the client helper must exist, run on
// every tab switch, and run from load_site before the splash hides.
if (!/window\.gbtClosePopups\s*=\s*function/.test(ui)) fail("ui.R must define window.gbtClosePopups");
if (!/hide\.bs\.tab[^;]*gbtClosePopups/.test(ui)) fail("ui.R must close map popups on every tab switch (hide.bs.tab)");
if (!/runjs\([^)]*gbtClosePopups/.test(server)) fail("server.R load_site must call gbtClosePopups before the splash hides");
if (/clearPopups\(/.test(server)) fail("server.R must not rely on leaflet::clearPopups for marker-bound popups");

// Boot default and deep links.
if (!/"SRER"\s*%in%\s*available_sites\(\)/.test(server)) fail('server.R must default the boot site to SRER when bundled');
if (!/updateQueryString\(/.test(server)) fail("server.R must write a shareable ?site= URL after a load");
if (!/rv\$restoreReq/.test(server)) fail("server.R must track the restore request (rv$restoreReq) past the boot skip");

// Item 17 boot skip: the one-shot skip on input$site must be conditional on the
// restore request, and the observer must still load the picked site.
const siteObservers = observerBodies(server, "observeEvent(input$site, {")
  .filter((body) => /rv\$siteReady/.test(body));
if (siteObservers.length !== 1) {
  fail(`server.R must have exactly one observeEvent(input$site) with the siteReady boot skip; found ${siteObservers.length}`);
} else {
  const body = siteObservers[0];
  const readyAt = body.search(/if\s*\(\s*!isTRUE\(rv\$siteReady\)\s*\)\s*\{/);
  const ready = readyAt < 0 ? "" : braceBody(body, readyAt);
  if (!ready) fail("server.R input$site observer must open with an if (!isTRUE(rv$siteReady)) { ... } branch");
  if (!/identical\(\s*input\$site\s*,\s*rv\$restoreReq\s*\)/.test(ready)) {
    fail("server.R boot skip must be conditional on identical(input$site, rv$restoreReq)");
  }
  // Every return in the skip branch must be the conditional one.
  for (const line of ready.split("\n")) {
    if (/return\(/.test(line) && !/if\s*\(\s*!identical\(\s*input\$site\s*,\s*rv\$restoreReq\s*\)\s*\)\s*return\(/.test(line)) {
      fail(`server.R boot skip has an unconditional return: ${line.trim()}`);
    }
  }
  const rest = ready ? body.replace(ready, "") : body;
  if (!/load_site\(\s*input\$site/.test(rest)) fail("server.R input$site observer must still call load_site(input$site, ...)");
}

// Same-site picks fire no input$site change, so the popup Explore and the
// restore paths must each load the site directly when it is already selected.
const sameSite = /identical\(\s*input\$site\s*,\s*s\s*\)\s*\)\s*load_site\(\s*s/;
for (const [label, marker] of [["siteExplore", "observeEvent(input$siteExplore"],
                               ["restore_site", "observeEvent(input$restore_site"]]) {
  const bodies = observerBodies(server, marker);
  if (bodies.length !== 1) { fail(`server.R must have exactly one observeEvent(input$${label}); found ${bodies.length}`); continue; }
  if (!sameSite.test(bodies[0])) fail(`server.R observeEvent(input$${label}) must load directly when the site is already selected`);
  if (label === "restore_site" && !/rv\$restoreReq\s*<-\s*s\b/.test(bodies[0])) {
    fail("server.R observeEvent(input$restore_site) must set rv$restoreReq <- s");
  }
}

// HELD: cross-site rankings stay HELD (docs/SCIENCE-CONTRACT.md), so no
// richness-scaled mark, rank text or richest-first legend may come back.
if (/sqrt\(\s*richness\s*\)/.test(server)) fail("server.R must not size marks by sqrt(richness) (HELD cross-site ranking)");
// (The pre-fix banner read "ranks <b>#%d of %d</b> NEON sites"; the species-range
// lines "found at <b>%d of %d</b> NEON sites" are occupancy counts, not ranks.)
if (/ranks\s*<b>\s*#/.test(server) || /#%d of %d<\/b> NEON sites/.test(server)) {
  fail("server.R must not print a cross-site rank (HELD)");
}
const pickerCall = (server.match(/mapPickerServer\(\s*"picker"[\s\S]*?radius_metric\s*=\s*([^,\n]+)/) || [])[1] || "";
if (pickerCall.trim() !== "NULL") fail('server.R mapPickerServer("picker", ...) must pass radius_metric = NULL (fixed-size dots)');
if (/Dot size is species richness/.test(ui)) fail("ui.R must not describe dot size as species richness (HELD)");
if (/fewer \\U2192 more species|fewer → more species/.test(ui)) fail("ui.R must not carry the richness dot-size legend (HELD)");

// HELD: the two Search tables default to state then site order, never to an
// activity-density or richness ordering (the columns stay sortable by click).
for (const name of ["search_taxon_rows", "search_thresh_rows"]) {
  const at = server.indexOf(`${name} <- reactive(`);
  const body = at < 0 ? "" : braceBody(server, at);
  if (!body) { fail(`server.R ${name} reactive not found`); continue; }
  if (/order\([^\n]*(activity_density|richness|individuals)/.test(body) ||
      /(arrange|desc)\([^\n]*(activity_density|richness)/.test(body)) {
    fail(`server.R ${name} must not order by activity-density or richness (HELD)`);
  }
  if (!/order\(\s*r\$state\s*,\s*r\$siteID/.test(body)) {
    fail(`server.R ${name} must default to state then site order`);
  }
}
for (const name of ["searchTaxonTable", "searchThreshTable"]) {
  const at = server.indexOf(`output$${name} <- DT::renderDT(`);
  const body = at < 0 ? "" : braceBody(server, at);
  if (!body) { fail(`server.R output$${name} not found`); continue; }
  if (/order\s*=\s*list\(\s*list\(/.test(body)) {
    fail(`server.R output$${name} must not set a default DT column order (HELD)`);
  }
  if (!/order\s*=\s*list\(\s*\)/.test(body)) {
    fail(`server.R output$${name} must pass order = list() so the row order is kept`);
  }
}

if (!process.exitCode) console.log("OK: Ground Beetle shell contracts passed");
