#!/usr/bin/env bash
# Content-aware production smoke. A host error page can return HTTP 200, so the
# Connect endpoint must also expose this app's ready marker, which carries the
# runtime build digest: a stale bundle that still answers is a failure, not health.
#
# Usage: post_deploy_smoke.sh '<label>=<url>' ...
# Labels containing "app" get the app checks: SMOKE_APP_MARKER (normally
# "ground-beetle-tracker-v1 build=<digest from scripts/build_digest.sh>"), the
# exact <title>, and lang="en". Other labels get the host-error-page check only.

set -uo pipefail

MAX_ATTEMPTS="${SMOKE_MAX_ATTEMPTS:-10}"
SLEEP_BASE="${SMOKE_SLEEP_BASE:-5}"
SLEEP_CAP="${SMOKE_SLEEP_CAP:-40}"
CONNECT_TIMEOUT="${SMOKE_CONNECT_TIMEOUT:-15}"
MAX_TIME="${SMOKE_MAX_TIME:-45}"
APP_MARKER="${SMOKE_APP_MARKER:-ground-beetle-tracker-v1}"
APP_TITLE='<title>NEON Ground Beetle Tracker</title>'
fail=0

# The build=<x> value inside the live ddl-app-ready meta tag, or "none".
live_build() {
  local content
  content=$(grep -Eo '<meta[^>]*name="ddl-app-ready"[^>]*>' "$1" 2>/dev/null \
    | grep -Eo 'content="[^"]*"' | head -n 1)
  if [[ "$content" =~ build=([^\"[:space:]]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ -n "$content" ]]; then
    echo "none (${content})"
  else
    echo "none (no ddl-app-ready meta)"
  fi
}

check_one() {
  local label="$1" url="$2" attempt code body nap reason="" saw_app_html=0
  body=$(mktemp)
  for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
    code=$(curl -sS -o "$body" -w '%{http_code}' -L \
      --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
      -A 'ddl-uptime-smoke/1.0' "$url" 2>/dev/null || echo "000")
    reason=""
    if [[ "$code" =~ ^(2|3)[0-9][0-9]$ ]]; then
      if grep -Eqi 'startup error|application failed to start|application error|service unavailable' "$body"; then
        reason="body is a host error page"
      elif [[ "$label" == *"app"* ]]; then
        saw_app_html=0
        if grep -q 'name="ddl-app-ready"' "$body"; then saw_app_html=1; fi
        if ! grep -Fq "$APP_MARKER" "$body"; then
          reason="app-ready marker \"$APP_MARKER\" absent (live build=$(live_build "$body"))"
        elif ! grep -Fq "$APP_TITLE" "$body"; then
          reason="title $APP_TITLE absent"
        elif ! grep -Eq '<html[^>]*lang="en"' "$body"; then
          reason='lang="en" absent on <html>'
        fi
      fi
      if [[ -z "$reason" ]]; then
        echo "ok [$label] $url -> $code + semantic body check (attempt $attempt)"
        rm -f "$body"
        return 0
      fi
      echo "wait [$label] $url -> $code but $reason ($attempt/$MAX_ATTEMPTS)"
    else
      echo "wait [$label] $url -> $code ($attempt/$MAX_ATTEMPTS)"
    fi
    if ((attempt < MAX_ATTEMPTS)); then
      nap=$((SLEEP_BASE * attempt)); ((nap > SLEEP_CAP)) && nap=$SLEEP_CAP
      sleep "$nap"
    fi
  done
  if [[ "$label" == *"app"* && "$saw_app_html" -eq 1 && "$APP_MARKER" == *"build="* ]] \
     && ! grep -Fq "$APP_MARKER" "$body"; then
    echo "DOWN [$label] $url -> stale bundle: live build=$(live_build "$body"), expected ${APP_MARKER##*build=}"
  else
    echo "DOWN [$label] $url -> last=$code; ${reason:-semantic health not reached}"
  fi
  rm -f "$body"
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
