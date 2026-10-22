<!-- neonize-playbook-stub: v1 -->
# NEONize playbook: pointer for Ground Beetle Tracker

The NEON suite playbook has one home, read by Claude Code and Codex alike:
https://github.com/tgilbert14/NEON-Driver-Cascade/blob/master/docs/neonize-playbook.md
(side-by-side clone: `../NEON-Driver-Cascade/docs/neonize-playbook.md`). Read it before
suite work. Fold every suite rule, pattern or gotcha into that file, never into this one.
Anything here beyond this pointer and the app facts below is a stale fork: report it.

## This app

- Repo `NEON-Ground-Beetle-Tracker` · watched branch `main` · product `DP1.10022.001`
- Rung specialist: `cara`
- Refresh: `refresh-data.yml` (first-week cadence) publishes validated bytes only to the fixed review branch `automation/ground-beetle-data-refresh`, never `main`; a person's merge to `main` is the deploy.
- Local authority files: `docs/SCIENCE-CONTRACT.md` (opportunity, activity-density, claim limits), `docs/BUILD-TEST-HANDOFF.md` (commands, evidence, session log), `docs/EXPERT-REVIEW.md` (product-expert review), `docs/DRIVER-KNOWLEDGE-PACKAGE.md` (Driver disposition).
- Site picker: `R/map_picker.R` is the suite's reference port of the site-picker map contract (Explore/About popup, sidebar sync, one shared loader); its "See docs/neonize-playbook.md" resolves to canonical §2g.

## App-specific rules

- None beyond the local authority files above.

## Owner-settled house rules (both tools)

- Default demo, startup and picker pre-selection site: **SRER** (then JORN, SJER, MOAB, ONAQ) unless this app documents a reason.
- Copy voice on covers, share cards and in-app copy: plain words a non-expert follows; say what NEON is; no em dashes; no sales pitch (price, access, ease); no hype adjectives; no sincerity labels ("honest", "real data"); never state what the reader can already see.
- No visible "illustration" badge on poster art; the art's status lives in alt text and the image provenance record.

Cold boot: also grep the fleet's `.claude/agents/LESSONS.md` in TG-Data-Apps (Codex: the
`dev-teams` mirror) for your role name: `grep -E '^- \[[0-9-]*\] [a-z0-9+-]*<role>[ +]'`.
