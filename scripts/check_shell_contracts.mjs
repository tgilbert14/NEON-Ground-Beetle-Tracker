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

// Item 18: keepInView pins an open popup to a map that later shrinks to 0 px.
for (const [name, source] of [["R/map_picker.R", picker], ["server.R", server]]) {
  if (/keepInView\s*=\s*TRUE/.test(source)) fail(`${name} must not set keepInView = TRUE on a popup`);
}

// The resize path must not invalidate a hidden (0 px) map.
const onRender = (picker.match(/htmlwidgets::onRender\("([\s\S]*?)"\)/) || [])[1] || "";
if (!onRender) fail("R/map_picker.R onRender block not found");
const resizeListener = (onRender.match(/addEventListener\('resize',\s*function\(\)\{([^}]*)\}/) || [])[1] || "";
if (!/clientWidth\s*>\s*0/.test(resizeListener)) {
  fail("R/map_picker.R resize listener must guard invalidateSize on el.clientWidth > 0");
}
const kick = (onRender.match(/function kick\(\)\{([\s\S]*?)\n/) || [])[1] || "";
if (!/clientWidth\s*>\s*0/.test(kick)) fail("R/map_picker.R timed kicks must guard on el.clientWidth > 0");

// Item 21: window_title lands on <body>; the page needs a real <title> and lang.
if (/window_title/.test(ui)) fail("ui.R must not use window_title (it renders as a body attribute)");
if (!/title\s*=\s*"NEON Ground Beetle Tracker"/.test(ui)) fail('ui.R must set title = "NEON Ground Beetle Tracker"');
if (!/lang\s*=\s*"en"/.test(ui)) fail('ui.R must set lang = "en"');

// Item 17: banner text wraps as one prose child beside the icon.
const verdictCount = count(/class\s*=\s*"verdict-text"/g, server);
if (verdictCount !== 9) fail(`server.R must have 9 class = "verdict-text" banner spans; found ${verdictCount}`);
if (!/\.verdict-text\s*\{[^}]*min-width:\s*0/.test(css)) fail("www/styles.css must define a .verdict-text rule with min-width: 0");

// Item 23: Space on a role=button QC flag must not scroll the page.
const qcKeydown = (server.match(/onkeydown\s*=\s*sprintf\("([^"]*beetleQcInspect[^"]*)"/) || [])[1] || "";
if (!qcKeydown) fail("server.R QC flag onkeydown handler not found");
else if (!/event\.preventDefault\(\)/.test(qcKeydown)) fail("server.R QC flag onkeydown must call event.preventDefault()");

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

if (!process.exitCode) console.log("OK: Ground Beetle shell contracts passed");
