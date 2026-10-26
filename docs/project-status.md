# Project status: NEON Ground Beetle Tracker

As of: 2026-10-22 · Version: `main` @ `9680014` plus open PR #25 · Stage: live on
Posit Connect Cloud (git-backed from `main`) and GitHub Pages.

> Cold-boot agents: read this, `docs/BUILD-TEST-HANDOFF.md` and
> `docs/SCIENCE-CONTRACT.md` before flagging anything. The **Deliberately deferred**
> section is binding: those items were decided, with the reason recorded.

## Now (blocks a ship, a demo or a user)

- [ ] **Merge PR #25** (Tim). It finishes the 2026-10-18 audit for this app: the
  partial-season trend rule, the seasonal card gate, release pinning with DOI and a
  release watch, PUUM in the roster, accessibility and copy fixes, revision-proving
  smoke checks. Post-merge: confirm the post-deploy job goes green on the new
  `build=` marker and rerun the headless harness on the Connect app.
- [ ] **Set `CARTO_BASEMAP_KEY` on the Connect content and republish** (Tim, Connect
  dashboard). Every live tile currently comes from the keyless Esri fallback.

## Next (real, not urgent)

- [ ] **Plot-matched annual estimator** for the 2023 cut from 10 plots to 6
  (`glm(count ~ factor(plotID) + factor(year), offset = log(trapnights))`), with a
  synthetic test that 6-plot and 10-plot estimates agree. Needs HK sign-off because
  it changes the units the trend, the seasonal card and the PDF read. Until then the
  app marks 2023 as a design break and does not call a trend clear when it rests on
  2023. Owner: cara (method), HK (estimator), lead.
- [ ] **Confirm what "Amara cupreolata group" covers** (cara). It counts as one
  species where no member species is present; at BLAN and CLBJ it sits next to
  *A. impuncticollis*.
- [ ] **Species range map dot size**: with a species picked, the Biogeography map
  sizes dots by raw local counts, which depend on effort. The Search tables no
  longer open in catch-rate order (fixed 2026-10-26). Decide whether the range map
  should size by catch per 100 trap-nights or use one size. Owner: cara, lead.
- [ ] **Branch protection on `main`** (Tim): a ruleset requiring a PR and the
  `contracts` check, no force-push or deletion.
- [ ] **Actions policy** (Tim): allow only selected actions and require full-SHA pins
  (every workflow already pins SHAs).

## Later (polish)

- [ ] Run axe-core on the landing and a loaded site once it is available in the
  toolchain (every serious finding from the 2026-10-18 audit was fixed and checked
  by direct DOM measurement; no axe rerun has been done).
- [ ] The phone poster wraps the long Atlas name to four lines; the CTA still sits
  inside the first screen.

## Deliberately deferred (do not re-flag; decided, with the reason)

- **Provisional NEON records stay out.** The bundle is released data only, pinned
  to one release (`GBT_RELEASE`), because expert identifications arrive after the
  provisional window. Adopting a newer release is a reviewed bump of `GBT_RELEASE`;
  the `release_watch` job opens an issue when NEON publishes one.
- **No cross-site richness rank.** `docs/SCIENCE-CONTRACT.md` holds cross-site
  rankings until protocol-change fixtures exist; raw richness moves sites up to 18
  rank places once rarefied. The rank banner, richness-sized dots and the
  richest-first table order were removed on purpose.
- **`scripts/write_manifest.R` reserialises the manifest with jsonlite** instead of
  targeted text edits (connor doctrine). Accepted: the output is deterministic and
  CI fails on any byte difference between the committed and regenerated manifest.
- **No CSP, HSTS or framing headers on the app or cover.** Both hosts (Connect Cloud
  share URLs and GitHub Pages) control their headers; no repo change can set them.
  Revisit only if a client embed needs them (custom domain behind Cloudflare).
- **Playwright tile canary in CI** (audit GB-15): not added. The basemap fallback is
  an owner configuration issue (the Connect content variable), and the post-deploy
  job already proves the deployed revision; a browser in CI was judged not worth its
  weight for this one check.
- **The keepalive job is a trial.** Whether re-enabling an enabled workflow resets
  GitHub's 60-day inactivity clock is undocumented; a merged commit is the
  documented re-arm.
- **Doctrine drift in `neonize.md`** (single Atlas route on the cover vs a ten-app
  grid) is not an app defect: the cover follows the playbook's Living Poster V1
  frame. The doctrine session owns that text.
