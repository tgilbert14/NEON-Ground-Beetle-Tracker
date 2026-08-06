#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const html = readFileSync(resolve(root, "docs/index.html"), "utf8");
const ui = readFileSync(resolve(root, "ui.R"), "utf8");
const css = readFileSync(resolve(root, "www/styles.css"), "utf8");

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exitCode = 1;
}

function count(pattern, source = html) {
  return (source.match(pattern) || []).length;
}

function requireText(pattern, message, source = html) {
  if (!pattern.test(source)) fail(message);
}

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

function pngDimensions(buffer) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (!buffer.subarray(0, 8).equals(signature)) throw new Error("not a PNG");
  return [buffer.readUInt32BE(16), buffer.readUInt32BE(20)];
}

if (count(/<h1\b/gi) !== 1) fail("Pages cover must contain exactly one h1");
if (count(/<main\b/gi) !== 1) fail("Pages cover must contain exactly one main landmark");
if (count(/class="button"/g) !== 1) fail("Pages poster face must contain exactly one primary CTA");
requireText(/<html\s+lang="en">/i, "document language must be English");
requireText(/class="skip"[^>]+href="#main"/, "missing skip link to the poster");
requireText(/<nav\b[^>]+aria-label="NEON Explorer Suite"/, "suite route needs an accessible label");
requireText(/<link rel="canonical" href="https:\/\/tgilbert14\.github\.io\/NEON-Ground-Beetle-Tracker\/">/, "canonical URL is missing or incorrect");
requireText(/og-image-v2\.png/, "social card must use the cache-busted v2 PNG");
requireText(/property="og:image:width" content="1200"/, "Open Graph width must be 1200");
requireText(/property="og:image:height" content="630"/, "Open Graph height must be 630");
requireText(/property="og:image:alt" content="[^"]+"/, "Open Graph image needs alternative text");
requireText(/name="twitter:image:alt" content="[^"]+"/, "Twitter image needs alternative text");
requireText(/What moves at ground level\?/i, "poster hook is missing");
requireText(/Explore the ground beetles NEON pitfall traps encountered, site by site and season by season\./i, "poster promise is missing");
requireText(/Pick a place/i, "poster CTA must be contextual");
if (/Editorial illustration—not a field photograph or data record\./i.test(html) ||
    /<figcaption\b[^>]*class="art-note"/i.test(html) || /\.art-note\b/.test(html)) {
  fail("Pages poster must omit redundant illustration-badge markup and CSS");
}
requireText(/activity as well as local abundance/i, "cover must state the activity-density boundary");
requireText(/does not estimate population density or site health/i, "cover must reject unsupported population and health claims");
requireText(/detection frequency is not detection-corrected occupancy/i, "cover must distinguish detection frequency from occupancy");
requireText(/DP1\.10022\.001/g, "cover must identify the source data product");
if (count(/https:\/\/tgilbert14\.github\.io\/NEON-Driver-Cascade\//g) !== 1) {
  fail("Pages poster face must contain exactly one Driver route");
}

requireText(/ground_beetle_poster\s*<-\s*function/, "in-app Living Poster component is missing", ui);
requireText(/What moves at ground level\?/i, "in-app poster hook diverges from Pages", ui);
requireText(/Explore the ground beetles NEON pitfall traps encountered, site by site and season by season\./i, "in-app poster promise diverges from Pages", ui);
requireText(/href = "#site-picker-start"/, "in-app poster CTA must route to the picker", ui);
requireText(/id = "site-picker-start"[^\n]+tabindex = "-1"/, "in-app picker target must be focusable", ui);
if (/Editorial illustration—not a field photograph or data record\./i.test(ui) ||
    /tags\$figcaption\s*\(/.test(ui) || /\.gbt-poster-art\s+figcaption\b/.test(css)) {
  fail("in-app poster must omit the redundant illustration badge and its dead CSS");
}
requireText(/activity index—not population density or site health/i, "in-app poster must state the claim boundary", ui);
if (count(/NEON-Driver-Cascade\//g, ui) !== 1) fail("in-app poster must contain exactly one Driver route");
if (count(/\bh1\(/g, ui) !== 1) fail("in-app first-run surface must contain exactly one h1 constructor");
requireText(/@media \(prefers-reduced-motion: reduce\)/, "poster CSS needs reduced-motion handling", css);
requireText(/@media \(forced-colors: active\)/, "poster CSS needs forced-colors handling", css);

for (const forbidden of [
  /fonts\.googleapis\.com/i, /fonts\.gstatic\.com/i, /cdnjs\.cloudflare\.com/i,
  /unpkg\.com/i, /cdn\.jsdelivr\.net/i, /mode\s*:\s*["']no-cors["']/i,
  /(?:href|src)\s*=\s*["']http:\/\//i
]) {
  if (forbidden.test(html) || forbidden.test(ui)) {
    fail(`cover/app contains a forbidden external runtime or insecure pattern: ${forbidden}`);
  }
}

const pinnedAssets = [
  ["docs/assets/ground-beetle-living-poster.png", "9d5fbbe03079f09c838b3d6c6221518d82c47c3c1dd2818e3c7f2a55afeee27a"],
  ["docs/assets/ground-beetle-living-poster.webp", "287ee35f15454493b0858df70f47aa236c9a1671621d2f147899401a02800d82"],
  ["docs/assets/ground-beetle-living-poster-840.webp", "f23c8781035b95b59c9eb019b644986e96674a7899f38ab300db3f223464a367"],
  ["www/assets/ground-beetle-living-poster.png", "9d5fbbe03079f09c838b3d6c6221518d82c47c3c1dd2818e3c7f2a55afeee27a"],
  ["www/assets/ground-beetle-living-poster.webp", "287ee35f15454493b0858df70f47aa236c9a1671621d2f147899401a02800d82"],
  ["www/assets/ground-beetle-living-poster-840.webp", "f23c8781035b95b59c9eb019b644986e96674a7899f38ab300db3f223464a367"],
  ["docs/assets/ground-beetle-social-v1.svg", "0e72d8140ff48f94afafdf17bb0d12e7f93449936c7603fd67052bb56d5d6633"],
  ["docs/og-image-v2.png", "20d91cce9532ac8b7d597edb3f536054688ac33619bd2564f307118bcd4c8345"],
  ["www/vendor/sweetalert2-11.10.0.min.css", "6422b5d2cc17bfd08dd39f409997fd5335a9252df85ef8a50cc27bf4af963a07"],
  ["www/vendor/sweetalert2-11.10.0.all.min.js", "216f514edcba7636e2dfe772ca9c5a8c2d78a44e99acfe770cb7d8f70e345e7e"],
  ["www/vendor/html-to-image-1.11.11.js", "0181b9a4ea3351540751b2e72b6baecb5c2297093fcb0bd2af94fc531cb0fbda"]
];

for (const [file, expectedHash] of pinnedAssets) {
  try {
    const actualHash = sha256(readFileSync(resolve(root, file)));
    if (actualHash !== expectedHash) fail(`${file} hash changed: ${actualHash}`);
  } catch (error) {
    fail(`${file}: ${error.message}`);
  }
}

try {
  const buffer = readFileSync(resolve(root, "docs/assets/ground-beetle-living-poster.png"));
  const [width, height] = pngDimensions(buffer);
  if (width !== 1672 || height !== 941) fail(`poster art is ${width}x${height}; expected 1672x941`);
} catch (error) {
  fail(`docs/assets/ground-beetle-living-poster.png: ${error.message}`);
}

try {
  const buffer = readFileSync(resolve(root, "docs/og-image-v2.png"));
  const [width, height] = pngDimensions(buffer);
  if (width !== 1200 || height !== 630) fail(`social card is ${width}x${height}; expected 1200x630`);
} catch (error) {
  fail(`docs/og-image-v2.png: ${error.message}`);
}

if (!process.exitCode) console.log("OK: Pages and in-app Ground Beetle Living Poster contracts passed");
