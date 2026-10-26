#!/usr/bin/env bash
# Print the 12-hex runtime build digest of the app, run from the repo root.
#
# Mirrors DDL_BUILD in global.R: the md5 of the concatenated md5 hex of each file
# below, in this order, with no separators and no newline; a missing file
# contributes the literal "missing". Keep FILES identical to DDL_DIGEST_FILES,
# including the data/env/*.rds bundles appended after the fixed list.
# Works with md5sum (Linux) or md5 -q (macOS).
set -euo pipefail

FILES=(
  "global.R"
  "ui.R"
  "server.R"
  "R/helpers.R"
  "R/map_picker.R"
  "R/report_pdf.R"
  "R/seasonal_env.R"
  "R/site_metadata.R"
  "www/styles.css"
  "www/pincards.js"
  "data/precomputed.rds"
  "data/search_index.rds"
  "data/release.rds"
)
# Then every data/env/*.rds bundle, sorted by name in C order (matches
# DDL_DIGEST_FILES in global.R).
while IFS= read -r f; do
  [[ -n "$f" ]] && FILES+=("$f")
done < <(shopt -s nullglob; for f in data/env/*.rds; do printf '%s\n' "$f"; done | LC_ALL=C sort)

md5_file() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$1" | awk '{print $1}'
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$1"
  else
    echo "build_digest.sh: neither md5sum nor md5 is available" >&2
    exit 1
  fi
}

concat=""
for f in "${FILES[@]}"; do
  if [[ -f "$f" ]]; then
    concat+="$(md5_file "$f" | tr 'A-F' 'a-f')"
  else
    concat+="missing"
  fi
done

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf '%s' "$concat" > "$tmp"
digest="$(md5_file "$tmp" | tr 'A-F' 'a-f')"
printf '%s\n' "${digest:0:12}"
