#!/usr/bin/env bash
# Live view of which backend answers each request. Run it in a second terminal,
# then stop/start containers and watch traffic move.
#   ./scripts/watch.sh          -> web pool
#   ./scripts/watch.sh /api/    -> API pool
set -uo pipefail
URL="${BASE_URL:-https://localhost:8443}${1:-/}"

echo "Watching $URL (Ctrl+C to stop)"
while true; do
  out="$(curl -sk --max-time 3 -o /dev/null -D - -w 'code=%{http_code} time=%{time_total}s' "$URL" 2>/dev/null)"
  node="$(printf '%s\n' "$out" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-served-by"{print $2}')"
  stats="$(printf '%s\n' "$out" | tail -n 1)"
  printf '%s  %-12s %s\n' "$(date +%H:%M:%S)" "${node:-NO-RESPONSE}" "$stats"
  sleep 0.5
done
