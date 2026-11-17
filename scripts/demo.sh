#!/usr/bin/env bash
# Guided demo: prints who answers each request while servers are taken down and
# brought back. Unlike failover-test.sh it checks nothing - it just shows you.
set -uo pipefail
cd "$(dirname "$0")/.."

BASE_URL="${BASE_URL:-https://localhost:8443}"
COMPOSE="${COMPOSE:-docker compose}"

probe() {
  local out node code ms
  out="$(curl -sk --max-time 3 -o /dev/null -D - -w 'code=%{http_code} time=%{time_total}\n' "$BASE_URL/" 2>/dev/null)"
  node="$(printf '%s\n' "$out" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-served-by"{print $2}')"
  code="$(printf '%s\n' "$out" | sed -n 's/.*code=\([0-9]*\).*/\1/p')"
  ms="$(printf '%s\n' "$out" | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | awk '{printf "%d", $1 * 1000}')"
  printf '%s  %-8s %s  %sms\n' "$(date +%H:%M:%S)" "${node:-FAILED}" "${code:-000}" "${ms:-0}"
}

# watch_for <seconds>: one request every 0.4s
watch_for() {
  local end=$((SECONDS + $1))
  while ((SECONDS < end)); do probe; sleep 0.4; done
}

say() { printf '\n>>> %s\n' "$1"; }

trap '$COMPOSE start web1 web2 >/dev/null 2>&1 || true' EXIT

say "All servers healthy: web1 and web2 share the traffic"
watch_for 4

say "Stopping web1"
$COMPOSE stop -t 0 web1 >/dev/null 2>&1
watch_for 5

say "Stopping web2: no active servers left, backup web-dr should take over"
$COMPOSE stop -t 0 web2 >/dev/null 2>&1
watch_for 6

say "Starting web1 and web2 again"
$COMPOSE start web1 web2 >/dev/null 2>&1
watch_for 9

say "Done: traffic is back on the active servers"
