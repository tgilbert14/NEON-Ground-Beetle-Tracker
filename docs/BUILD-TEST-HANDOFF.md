# Ground Beetle Tracker build/test handoff

This is the durable cross-session record for the application's scientific contract,
generated data, release state, and publication evidence. Read it before work and
re-read the latest entry immediately before revising it.

## Product and release identity

- Repository: `tgilbert14/NEON-Ground-Beetle-Tracker`
- Watched branch: `main`
- Data product: NEON `DP1.10022.001`, Ground beetles sampled from pitfall traps
- Baseline source: `ff82104db2fb944af897df9c12dc2cff108ce52e`
- Pages: <https://tgilbert14.github.io/NEON-Ground-Beetle-Tracker/>
- Connect: <https://019ec8ff-2a4b-e0e9-871d-07a047a571d3.share.connect.posit.cloud/>
- Connect content ID: `019ec8ff-2a4b-e0e9-871d-07a047a571d3`

## Current release state

**`IMPLEMENTED LOCALLY / PINNED VALIDATION PENDING / METRICS HELD`** as of
2026-07-22. The public Connect app still represents the baseline release; the
candidate worktree now contains the release/science foundation, but no R runtime is
available locally and no generated bundle has been promoted yet.

- Both zero-argument handlers are repaired and statically asserted.
- The app-specific semantic marker and content-aware production smoke exist.
- A pinned, read-only validator and deterministic manifest generator exist.
- Refresh now stages an exact site roster, validates immutable candidate bytes,
  and publishes only a review PR from a restricted writer job.
- The resolver now emits explicit field-effort anchors, including valid
  zero-carabid opportunities, and reconciles taxonomy through individualID.
- Committed site bundles, derived indexes, and manifest remain legacy bytes until
  the remote pinned builder produces and validates their replacements.

The candidate now includes matching Pages and in-app Living Posters with a
moss-and-copper editorial beetle/pitfall visual, one hook, one promise, one CTA,
and one Driver route. The first-run app no longer fetches Google Fonts or the
SweetAlert/html-to-image runtime from CDNs; exact vendored assets are pinned by
the cover contract. Publication and in-app runtime evidence remain pending.

## Baseline release audit

The tracked manifest declares R 4.5.2, 91 packages, 104 files, `terra 1.8-50`, and
a moving `jammy/latest` repository. Eight tracked-file checksums disagree:

- `data-sample/env_demo.csv`
- `global.R`
- `R/helpers.R`
- `R/report_pdf.R`
- `R/site_metadata.R`
- `server.R`
- `ui.R`
- `www/styles.css`

`.github/workflows/refresh-data.yml` uses moving action tags and runner/package
inputs, combines refresh/build/write/deploy authority, directly pushes to `main`,
and lets a watched-branch push trigger Connect publication. It has no separate
immutable read-only validator, exact artifact-promotion boundary, or semantic
post-deploy gate.

## Baseline scientific audit

The current source preserves several valuable protections: expert-ID override,
species-rank richness filtering, introduced-carabid context, activity-density
language, support floors, a circular-shift/permutation null for best-of-scan
environmental relationships, and trend small-sample gates.

The primary blocker is upstream of those estimators. `assemble_beetles()` starts
from positive Carabidae sorting records, drops non-positive counts, groups catch,
then left-joins `bet_fielddata` effort onto that outcome table. Valid field bouts
with zero Carabidae are not emitted into the bundle. Downstream effort and
occupancy-like denominators are therefore catch-conditioned unless proven otherwise
from an independent opportunity table. The contract and fixtures in
`docs/SCIENCE-CONTRACT.md` must be implemented before metric claims or Driver
adoption.

## Required release gates

1. Static R/JavaScript/workflow parsing and assertion-based scientific fixtures.
2. Opportunity-complete field-effort resolution, including valid zero-catch bouts,
   duplicate effort, missing effort, expert-ID, rank, and protocol-era cases.
3. Full site-bundle/index schema, row, key, support, and deterministic-byte checks.
4. Pinned R 4.5.2 / Ubuntu 22.04 / one-thread build with exact package provenance.
5. Validator-generated manifest with exact runtime file/checksum equality.
6. Bundle-only offline boot and exactly one argument for every Shiny message
   handler.
7. Green exact review head and merge; Connect deploys that merge identity.
8. App-specific semantic-ready marker plus representative interaction without an
   unexpected first-party console/server error.
9. Pages and in-app Living Poster verified at desktop, 390 px, and 320 px for
   accessibility, responsive art, metadata, local dependencies, and no overflow.
10. Final knowledge-package and Driver register/backlog disposition.

## 2026-07-22 MST - pass 5 baseline / Codex

- Began on `main` at `ff82104`, matching fetched `origin/main`, then created
  `agent/ground-beetle-pass5-baseline`.
- Preserved a pre-existing unstaged modification to
  `data-sample/beetle_demo.csv`. Inspection showed a line-ending-only
  normalization affecting the whole file; it is outside this pass and must not be
  staged or discarded.
- Public Connect verification found a rendered 46-site picker and live Shiny
  connection, correcting the stale outage record. No semantic-ready marker was
  present. The console reported the one-argument handler error. Source inspection
  found zero-argument handlers for `kickMaps` in `ui.R` and `smtRevealQc` in
  `www/pincards.js`; both require repair and tests.
- Static manifest inspection found the eight checksum mismatches, moving repository
  alias, and workflow authority risks summarized above. No R runtime is available
  locally, so no R parse, bundle, manifest regeneration, or boot result is claimed.
- Scientific source inspection found the opportunity/outcome conflation summarized
  above. Existing expert-ID, rank, introduced-species, permutation-null, caveat,
  and support logic is retained as valuable source behavior, not yet deployed
  evidence.
- Claude's shared `ddl-fleet` NEONize context and lessons were read from the
  canonical `TG-Data-Apps` source. Applied lessons include exact manifest/file
  equality, semantic rather than HTTP-only health, one-argument message handlers,
  and the structural Living Poster contract. Current Driver records remain the
  suite authority where older fleet guidance conflicts with the newer restricted
  review/promotion design.
- Changed only governance, contract, handoff, and knowledge-package documents in
  this baseline tranche. No app code, bundle, manifest, workflow, public release,
  or Driver artifact byte changed.
- Classification: `scientific-contract`, `suite-platform`, `release-foundation`,
  and `Driver-impacting`. Driver disposition is `CONTEXT / HOLD METRIC ADOPTION`.
- Next concrete action: commit this evidence-only baseline without the dirty CSV;
  update the Driver suite register with restored-startup/release-unsafe evidence;
  then implement one-argument message handlers, semantic health, pinned validation,
  and the opportunity-complete effort resolver with adversarial fixtures before the
  Living Poster/product pass.

## 2026-07-22 MST - release/science implementation candidate / Codex

- Preserved the pre-existing line-ending-only modification to
  `data-sample/beetle_demo.csv`; it remains unstaged and outside this pass.
- Added `ground-beetle-tracker-v1`, content-aware Connect/Pages smoke, issue-based
  production incident handling, and a static contract requiring one payload
  argument on all four Shiny custom-message handlers.
- Replaced catch-conditioned effort with explicit opportunity anchors built from
  distinct `bet_fielddata` trap identities where `sampleCollected == "Y"` and
  trapping days are valid. All rate, trend, seasonal, environmental, and
  detection-frequency denominators now use that opportunity table; raw unmatched
  catches remain visible but cannot receive a fabricated rate.
- Corrected an inherited taxonomy bug found against NEON's current table
  relationships: expert determinations are joined by `individualID`, not taxonID.
  Pinned individuals move through sorting -> parataxonomist -> expert one specimen
  at a time; the unpinned residual retains sorting taxonomy and total sorting count
  is conserved.
- Renamed the occupancy-like panel to detection frequency, removed site-health and
  generic bioindicator claims, and aligned UI, export, codebook, README, and PDF
  language with the science contract.
- Added adversarial helper fixtures covering valid zero-catch opportunities,
  physical-effort deduplication, missing effort, all-zero sites, conflicting
  effort, individual expert override, count conservation, coarse-ID exclusion, and
  legacy catch-only fallback.
- Added exact roster/schema/key/index/manifest verification and a pinned R 4.5.2 /
  Ubuntu 22.04 / one-thread validator. The refresh workflow now builds in an empty
  staging directory, promotes only the exact canonical roster, validates all
  derived bytes, and opens/updates a review PR rather than pushing `main`.
- Local evidence: every workflow parses as YAML; JavaScript syntax and the
  four-handler assertion pass; shell smoke syntax and `git diff --check` pass for
  all in-scope files. No local R parse/test/boot result is claimed.
- Classification remains `scientific-contract`, `suite-platform`,
  `release-foundation`, and `Driver-impacting`. Driver disposition remains
  `CONTEXT / HOLD METRIC ADOPTION` until pinned candidate generation, green review
  head, merge, Connect semantic health, representative interaction, and final
  bundle evidence pass.
- Next concrete action: commit/push the candidate without the dirty demo CSV, run
  pinned CI, generate and promote the opportunity-complete bundles via the
  restricted refresh workflow, resolve exact failures, then complete the Ground
  Beetle Living Poster and post-merge evidence loop.

## 2026-07-22 MST - Living Poster implementation candidate / Codex

- Replaced the dense Pages report cover with the final suite frame: “What moves
  at ground level?”, the promise “Explore the ground beetles NEON pitfall traps
  encountered, site by site and season by season.”, one “Pick a place” CTA, and
  one Driver Cascade route.
- Built a code-native moss-and-copper beetle/pitfall illustration rather than a
  field photograph or data-like mark. The art boundary is disclosed on both
  surfaces; the footer retains the activity-density, population/site-health,
  detection-frequency/occupancy, and association/causality boundaries.
- Ported the same hook, promise, CTA, claim boundary, and visual world into the
  Shiny first-run screen. The former dashboard hero is now a loaded-site `h2` and
  is shown only after a site loads, leaving exactly one first-run `h1`.
- Removed the Google Fonts request and replaced the two export CDNs with the exact
  SweetAlert 11.10.0 and html-to-image 1.11.11 bytes already used by the validated
  Small Mammal suite pattern.
- Added a cache-busted 1200x630 social card, its code-native SVG source, and a
  hash/dimension/static contract wired into both CI and refresh validation.
- Local Pages evidence: one `h1`, one CTA, one Driver route, no external runtime,
  no horizontal overflow, and visually reviewed layouts at 1440x900, 390x844,
  and 320x720. The 390 and 320 covers retain the full promise and 52 px CTA.
- Local static evidence: cover contract, handler contract, JavaScript syntax,
  shell syntax, and `git diff --check` pass. No local R parse/app-render result is
  claimed; the pinned remote validator remains authoritative.
- Next concrete action: push the poster candidate, resolve pinned CI and generated
  bundle/manifest evidence, then verify the exact deployed Pages and Connect
  identities before promotion.

## 2026-07-23 MST - Static artistic Living Poster refresh / Codex

- Replaced the sparse code-native beetle diagram on both entry surfaces with one
  static, production-grade editorial screenprint. The illustration shows a
  recognizable carabid crossing moss and leaf litter beside a flush-buried
  pitfall cup in a forest-floor cutaway.
- Kept the approved hook, promise, one CTA, one Driver route, source attribution,
  and activity-density/population/occupancy/causality boundaries unchanged.
- Removed the hero halo, beetle drift, and trail animations. The main art is now
  still at every motion preference; only ordinary CTA hover feedback remains.
- Added identical PNG/WebP assets for Pages and Connect, a responsive 840 px
  derivative, high-priority preload metadata, exact asset hashes, a dimension
  assertion, and `docs/IMAGE-PROVENANCE.md`.
- Local Pages evidence: the cover was visually reviewed at 1280 x 720, 390 x 844,
  and 320 x 720. The beetle and trap remain legible, the full CTA remains at
  least 52 px high, and no horizontal overflow appears at any reviewed width.
- Local static evidence: the cover contract, custom-message-handler contract, and
  `git diff --check` pass. No local R parse/app-render result is claimed because
  this host does not expose an R runtime; pinned CI remains authoritative.

## 2026-08-03 EDT - restricted publisher repair candidate / Codex

- Audited scheduled refresh run `30736780782`. Producer and validator jobs
  passed and published exact candidate `3010bef7f02199fe093635c72baeea2bfdbc76fc`
  to `automation/ground-beetle-data-refresh`; only workflow-authored PR creation
  failed because the repository correctly forbids Actions from creating or
  approving pull requests.
- Replaced that prohibited final action with a reviewer-authenticated handoff.
  The publisher now rejects a stale `main`, requires the promotion commit to be a
  direct child of the validated producer revision, force-pushes only with a lease,
  polls the remote branch to its exact SHA, and refuses ambiguous or mismatched
  PR identity.
- When no PR exists, the successful run summary exposes the exact branch, head,
  validator run, and GitHub compare link for a repository write user. When one
  exact PR exists, the workflow comments the exact-head approval requirement; it
  never creates or merges a PR and never writes `main`.
- Local evidence: the workflow parses as YAML, all 10 embedded shell blocks pass
  `bash -n`, and `git diff --check` passes. This is a workflow-only repair; no
  scientific helper, bundle, data, manifest, app, or Pages byte changed.
- Next concrete action: publish this repair through exact-head review CI, merge it,
  then open and validate the already-produced refresh candidate with a
  reviewer-authenticated PR before any production promotion.

## 2026-08-03 EDT - deterministic scheduled-refresh repair production closeout / Codex

- Scope was limited to closing the derived-refresh determinism defect and binding
  the repaired candidate to review, merge, and production evidence. The source
  family remains NEON `DP1.10022.001`; the scientific opportunity, taxonomy, zero,
  support, and claim contracts did not change.
- Controlled derived-only run `30863099574` checked out exact `main`
  `43b6b5175f77a0da802c05ebbb4ba5c2a7a13cce` with the network fetch skipped.
  Expected: unchanged committed bundles would rebuild to identical derived bytes
  and produce no review branch. Actual: all science/release gates passed, but
  `scripts/build_search_index.R` embedded `Sys.time()`, so the run published
  superseded direct-child candidate
  `92bbb2effb397cdc280b161f0cbc0431fa88f9bd`. It changed only
  `data/search_index.rds` and that file's manifest checksum despite unchanged
  source data. Artifact `8875112150` was 722,514 bytes with digest
  `sha256:9d98ec6cbef5dc3b43e139d5f2befc2f29d37f37390194da00ef5380de79413a`;
  it was not reviewed or merged and was replaced with a lease by the repaired
  candidate.
- Fix source `1a65342e83e7a5c763dff88ef00511c4d2459af0` removes the wall clock by
  recording `built = NA_character_`, makes the verifier reject any other value,
  and runs `Rscript --vanilla scripts/build_search_index.R` twice in separate R
  processes with an intervening copy and byte-for-byte `cmp --silent`. This turns
  determinism into an executable producer gate rather than a semantic assumption.
- Repaired derived-only producer/validator/publisher run `30863698398` passed on
  exact source `1a65342`. Its artifact `8875330379` was 722,500 bytes with digest
  `sha256:03d2c1abdb1e8c4f4dcfd409cd7f1de2b742faecdf7a8b2dae5fb1824686cd02`.
  The restricted publisher produced exact direct child
  `226a45934ecfc6e1a51207344787b6837a5cfaab`, changing only
  `data/search_index.rds` and `manifest.json` after the three-file fix source.
- Reviewer-authenticated PR #17, `main <- automation/ground-beetle-data-refresh`,
  reviewed literal head `226a459`; exact-head run `30864009177` passed before the
  PR merged as `a615d6cdf550ea19ea13448bd234004f94de312e`. Merged-main validation
  `30864227238` passed the pinned OpenBLAS, source/static, scientific-helper,
  manifest, complete-bundle/index, offline-source, and exact-generated-byte gates.
- The released family remains exactly 46 site bundles, 100,163 rows, 33,012
  independent opportunity anchors, and 67,151 catch rows. The deterministic search
  index contains 2,630 taxon-by-site rows, 816 distinct taxa, 46 sites, and 41
  introduced taxon-by-site rows representing 10 introduced species. Its `built`
  field is exactly `NA_character_`; the 32,032-byte file has SHA-256
  `1360ecc3559a978268647ef969af21ac8459da933edbb0a1694e48ef5a0a4a17`.
  No site-bundle byte changed.
- The R 4.5.2 manifest still records 112 runtime files and 91 packages. Its
  `data/search_index.rds` checksum is now
  `27c2c412ad0546971103b1de603b60c4`; the complete committed manifest SHA-256 is
  `9dc3b0ff85b42ffada7ee0b7388027f796d08931a6fe398134433ccbff2aa2d2`.
  Merged-main run `30864227238` uploaded exact manifest artifact `8875517238`
  (61,350 bytes; digest
  `sha256:a6dadd095f04f752673a200d57e50d11f0a4f718ee67fad00df9036b889af9c0`).
  Downloaded artifact content was byte-identical to the committed manifest.
- Pages run `30864226376` published exact merge `a615d6c` as deployment
  `5735600639`. Content-aware production run `30864227265` then returned HTTP 200
  plus the required semantic bodies for both Pages and Connect on its first
  attempt, with no Startup Error text.
- Fresh live Connect QA at
  <https://019ec8ff-2a4b-e0e9-871d-07a047a571d3.share.connect.posit.cloud/>
  selected and loaded the default `DCFS` bundle. The rendered release showed 2,717
  individuals, 90 species-level taxa, 543 trap bouts, and 22,644 trap-nights;
  charts, QC, and downloads were present; the app-specific semantic marker was
  true; there were zero `.shiny-output-error` nodes, zero root horizontal overflow,
  and no Startup Error.
- Classification: `suite-platform` and app-local release integrity. Driver
  disposition remains `CONTEXT / HOLD DRIVER INGESTION / NO DRIVER BYTE CHANGE`;
  no ecological Driver decision, adapter, or data byte changed.
- Residual risk: these runs deliberately skipped the live NEON download, so they
  prove deterministic derivation and the restricted review/publish path, not a new
  upstream fetch. Next concrete action: let the next controlled full refresh run
  with download enabled, independently review its source/data delta, and promote it
  only through the same exact-head reviewer PR and production gates.
