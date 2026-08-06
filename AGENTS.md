# Repository operating instructions

These instructions apply to the entire repository. User and platform instructions
take precedence.

## Mandatory entry point

Before inspecting, changing, testing, rebuilding, publishing, or reporting on this
repository, read `docs/BUILD-TEST-HANDOFF.md`, `docs/SCIENCE-CONTRACT.md`, and
`docs/DRIVER-KNOWLEDGE-PACKAGE.md` completely. For suite work, also read the Driver
repository's complete `docs/NEON-SUITE-LEARNING-LOOP.md`,
`docs/NEON-SUITE-REVAMP-PLAN.md`, and `docs/neonize-playbook.md`.

Start and end every session with `git status --short --branch`. Preserve changes
you did not create. In particular, the July 22 baseline found a pre-existing
line-ending-only modification to `data-sample/beetle_demo.csv`; do not stage,
rewrite, normalize, or discard it without explicit owner direction.

## Scientific contract

- The product is NEON Ground beetles sampled from pitfall traps `DP1.10022.001`.
  Pitfall catch is an activity-density index: it combines abundance, movement,
  encounter probability, and sampling effort. It is not population density or a
  general measure of ecosystem or site health.
- The sampling opportunity is a physical pitfall-trap deployment within a
  `siteID x plotID x collection bout` (and trap identity where available), including
  valid sampled opportunities with zero Carabidae. Catch is the outcome. Never
  reconstruct the effort denominator from positive catch rows alone.
- Effort-normalized metrics use attempted, valid trap-nights. Zero catch is a real
  zero only when the field-effort table establishes that sampling occurred;
  missing/invalid effort is unavailable, not zero.
- Species richness and occupancy-like summaries use the authoritative expert-ID
  result and species-level rank gate. Genus/family records remain in total activity
  where appropriate but cannot inflate species richness.
- Retain introduced-species context, small-sample gates, activity-density caveats,
  and the circular-shift/permutation null for environmental scans. Environmental
  relationships are exploratory and cannot support causal claims.
- Keep explicit `CAN`, `CANNOT`, and `HELD` claims. Prefer an unavailable state to
  a catch-conditioned or weakly supported estimate.

## Build, release, and data rules

1. Runtime must boot from committed bundles without startup network dependencies.
2. Never edit `manifest.json` by hand. Generate it in the pinned validator,
   validate exact tracked files and dependency provenance, and promote only the
   exact validated artifact.
3. Data refreshes must assemble a complete review candidate and retain a known-good
   bundle until the replacement passes. Automated refresh code must not push
   unchecked bytes directly to the watched branch.
4. Pin R, runner image, package sources/snapshots, workflow actions, and release
   identities. Do not weaken gates to make an environment pass.
5. Every Shiny custom-message handler must accept exactly one payload argument,
   including handlers that ignore it.
6. A release requires green tests on the exact review head and merge, exact
   manifest equality, a matching Connect deployment, an app-specific semantic-ready
   marker, and desktop/mobile Pages verification. HTTP 200 is not health.
7. The Pages and in-app cover must use the suite Living Poster frame: one hook, one
   promise, one contextual CTA, one Driver route, locally served responsive art,
   meaningful art-status alt text, no ornamental illustration badge, visible
   scientific claim limits, and documented image provenance.

## Durable closeout

Immediately before editing either durable record, re-read its latest entry. Update
`docs/BUILD-TEST-HANDOFF.md` with time zone, scope, source and release identities,
commands, expected/actual results, failures, residual risks, and the next concrete
action. Update `docs/DRIVER-KNOWLEDGE-PACKAGE.md` with the evidence, opportunity
contract, eligible joins, engineering learning, and an explicit `ADOPT`, `HOLD`,
`CONTEXT`, `COMPLEMENT`, `REJECT`, or `NONE` decision.

A companion pass is not complete until its verified package is represented in the
Driver suite register and implication backlog. Do not change Driver artifact bytes
from this app until the decision and evidence are complete.
