# Ground Beetle Tracker to Driver knowledge package

This package records what the companion app can safely contribute to Driver
Cascade. It does not authorize a Driver artifact change by itself.

## Current disposition

**`CONTEXT / HOLD METRIC ADOPTION / NO DRIVER ARTIFACT BYTE CHANGE`**

Driver may retain Ground Beetles as companion context and navigation. It must not
adopt or refresh beetle activity, occupancy, trend, or environmental-driver metric
bytes from the current committed bundle until the opportunity-complete effort
contract and pinned release gates pass.

## Source identity

- Repository: `tgilbert14/NEON-Ground-Beetle-Tracker`
- Source product: NEON `DP1.10022.001`
- Baseline source: `main` at
  `ff82104db2fb944af897df9c12dc2cff108ce52e` (short `ff82104`)
- Pages: <https://tgilbert14.github.io/NEON-Ground-Beetle-Tracker/>
- Connect: <https://019ec8ff-2a4b-e0e9-871d-07a047a571d3.share.connect.posit.cloud/>

## What is scientifically useful

- Expert-taxonomist reconciliation and a species-rank gate provide a defensible
  species-level composition/richness basis.
- Catch per 100 trap-nights is the right form for a within-site activity-density
  index when its denominator is built from every valid field sampling opportunity.
- Introduced European carabid context is already represented and should be retained.
- The deseasonalized environmental scan with a circular-shift/permutation null is a
  useful exploratory screen; the null and candidate-search disclosure must travel
  with any result.
- Small-series trend gates and the explicit activity-density caveat are reusable
  scientific protections.

## Candidate implementation (not yet promoted)

The candidate `assemble_beetles()` now starts from the independent field-effort
table and emits one explicit opportunity anchor per sampled plot-bout, including
valid zero-carabid bouts. Taxonomy is reconciled at the documented individualID
grain: expert overrides parataxonomist for one pinned specimen, while unpinned
residual counts retain sorting taxonomy. Rate numerators accept only catches with a
matching valid opportunity.

Adversarial fixtures cover zero catch, duplicate and conflicting effort, missing
effort, all-zero sites, expert override without count multiplication, and legacy
fallback. This is implementation evidence only: the committed bundles and public
app still represent the baseline until the pinned refresh/review/deploy loop passes.

## Eligible Driver join and grain

Candidate joins remain contextual until validation:

- spatial: `siteID`
- temporal: a reviewed month/year derived from the collection bout
- response: opportunity-complete activity-density, with valid attempted
  trap-nights and zero-catch bouts represented
- taxonomy: authoritative expert-reconciled Carabidae result, with species-level
  gate for richness/composition

The Driver must not interpret this response as population density, ecosystem
health, or causal response to a climate/plant driver.

## Engineering learning for the suite

- A non-missing denominator column on positive outcome rows is not proof of
  complete sampling opportunity. Validate the field-effort roster independently
  and reconcile it to outcomes.
- Shiny 1.13 rejects zero-argument custom-message handlers. Every handler must take
  one payload, even when ignored.
- Public app health requires an app-specific semantic-ready marker and a real Shiny
  session/interaction. HTTP 200 and visible first paint are insufficient.
- Connect manifests must match every runtime byte. A moving RSPM alias and eight
  file-checksum mismatches make the current manifest unreleasable.
- The shared Living Poster family is structural, not palette-based. The candidate
  Ground Beetle Pages and in-app covers now use the one-hook, one-promise,
  one-CTA, one-Driver-route frame while retaining their own moss-and-copper
  beetle/pitfall visual world. This is candidate evidence until the exact review
  head and both public surfaces pass.

## Promotion evidence required

1. Opportunity-complete field-effort resolver and adversarial fixtures.
2. All committed site bundles and derived indexes validate against the contract.
3. UI, exports, codebook, PDF, and claims are aligned; the unsupported site-health
   claim is removed.
4. Pinned exact-manifest and bundle-only offline boot gates pass.
5. Every custom-message handler accepts one argument; semantic-ready smoke and a
   representative public interaction pass on the exact deployed commit.
6. Pages and in-app Living Poster pass desktop and 390/320 px verification.
7. Driver register/backlog is updated with the final evidence and an explicit
   `ADOPT`, `COMPLEMENT`, `CONTEXT`, `HOLD`, or `REJECT` disposition.

## 2026-08-03 EDT - deterministic derived-release addendum

Reviewer-authenticated PR #17 promoted fix source
`1a65342e83e7a5c763dff88ef00511c4d2459af0` and its exact direct-child candidate
`226a45934ecfc6e1a51207344787b6837a5cfaab`; production authority is merge
`a615d6cdf550ea19ea13448bd234004f94de312e`. Exact-head run `30864009177`,
merged-main run `30864227238`, Pages run `30864226376`, and semantic-production
run `30864227265` passed. Merged-main manifest artifact `8875517238` has digest
`sha256:a6dadd095f04f752673a200d57e50d11f0a4f718ee67fad00df9036b889af9c0`.

The reusable engineering lesson is stricter than “rebuild the index.” A derived
artifact must be a pure function of immutable reviewed inputs. Do not embed
`Sys.time()`, a CI run time, or another wall clock in published bytes. A time may
travel only when it is itself part of a reviewed upstream receipt; when no such
authority exists, record an explicit unavailable value. Then invoke the producer
twice as two independent processes in the pinned runtime and require byte equality
with `cmp`, before manifest generation and candidate publication. Semantic equality
inside one process is not a substitute for this two-process byte proof.

The Ground Beetle repair applies that rule to `data/search_index.rds`: the index
now carries `built = NA_character_`, its verifier fails closed on any other value,
and the workflow compares two independent builds. Controlled no-download run
`30863099574` exposed the defect by producing superseded candidate `92bbb2e` from
unchanged bundles; repaired run `30863698398` produced the reviewed deterministic
candidate. The release still contains 46 bundles, 100,163 rows, 33,012 opportunity
anchors, and 67,151 catch rows; only the derived search-index byte and its manifest
checksum changed.

Driver decision for this addendum is **`NONE`** for ecological integration, layered
on the existing **`CONTEXT / HOLD DRIVER INGESTION`** disposition. The repair does
not alter the activity-density estimand, opportunity denominator, zero rule,
eligible Driver join, mechanism status, or scientific claim boundary. No Driver
artifact or ecological data byte changed. The next dependency remains a separately
reviewed, pinned Driver adapter with measured join/support at suite synthesis; the
next app-release check is a full-download refresh through the same exact-head
review path.
