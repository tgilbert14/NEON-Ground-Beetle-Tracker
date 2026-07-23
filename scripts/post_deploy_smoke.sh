#!/usr/bin/env bash
# Content-aware production smoke. A host error page can return HTTP 200, so the
# Connect endpoint must also expose this app's marker.

set -uo pipefail

MAX_ATTEMPTS="${SMOKE_MAX_ATTEMPTS:-10}"
SLEEP_BASE="${SMOKE_SLEEP_BASE:-5}"
CONNECT_TIMEOUT="${SMOKE_CONNECT_TIMEOUT:-15}"
MAX_TIME="${SMOKE_MAX_TIME:-45}"
APP_MARKER="${SMOKE_APP_MARKER:-ground-beetle-tracker-v1}"
fail=0

check_one() {
  local label="$1" url="$2" attempt code body nap
  body=$(mktemp)
  for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
    code=$(curl -sS -o "$body" -w '%{http_code}' -L \
      --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
      -A 'ddl-uptime-smoke/1.0' "$url" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^(2|3)[0-9][0-9]$ ]]; then
      if grep -Eqi 'startup error|application failed to start|application error|service unavailable' "$body"; then
        echo "wait [$label] $url -> $code but body is a host error page ($attempt/$MAX_ATTEMPTS)"
      elif [[ "$label" == *"app"* ]] && ! grep -Fq "$APP_MARKER" "$body"; then
        echo "wait [$label] $url -> $code but app-ready marker is absent ($attempt/$MAX_ATTEMPTS)"
      else
        echo "ok [$label] $url -> $code + semantic body check (attempt $attempt)"
        rm -f "$body"
        return 0
      fi
    else
      echo "wait [$label] $url -> $code ($attempt/$MAX_ATTEMPTS)"
    fi
    nap=$((SLEEP_BASE * attempt)); ((nap > 40)) && nap=40
    sleep "$nap"
  done
  rm -f "$body"
  echo "DOWN [$label] $url -> last=$code; semantic health not reached"
  return 1
}

if [[ $# -eq 0 ]]; then
  echo "usage: $0 '<label>=<url>' ..." >&2
  exit 2
fi

for spec in "$@"; do
  label="${spec%%=*}"
  url="${spec#*=}"
  check_one "$label" "$url" || fail=1
done

[[ "$fail" -eq 0 ]] || exit 1
echo "post-deploy smoke PASSED"
