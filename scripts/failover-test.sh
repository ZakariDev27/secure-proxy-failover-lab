#!/usr/bin/env bash
# End-to-end failover test. Breaks things on purpose and checks the proxy copes.
# Exits non-zero if any check fails, so it doubles as the CI test.
set -uo pipefail
cd "$(dirname "$0")/.."

BASE_URL="${BASE_URL:-https://localhost:8443}"
HTTP_URL="${HTTP_URL:-http://localhost:8080}"
COMPOSE="${COMPOSE:-docker compose}"
ALL_BACKENDS="web1 web2 web-dr api-primary api-standby"

pass=0; fail=0
ok()    { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()   { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
title() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
check() { if [[ "$2" == "true" ]]; then ok "$1"; else bad "$1"; fi; }

# Print the name of the node that answered, or ERR if the request failed.
node_of() {
  local body
  body="$(curl -sk --max-time 5 "$BASE_URL$1" 2>/dev/null)" || { echo ERR; return; }
  body="$(printf '%s' "$body" | sed -n 's/.*"node":"\([^"]*\)".*/\1/p')"
  echo "${body:-ERR}"
}

# sample <count> <path> <delay> -> one node name per line
sample() {
  local i
  for ((i = 0; i < $1; i++)); do node_of "$2"; sleep "$3"; done
}

summary() { sort | uniq -c | awk '{printf "%s x%s  ", $2, $1}'; }
count()   { grep -c -x "$1" || true; }

# wait_for <path> <seconds> <node>... -> succeeds once 6 requests in a row all hit one of <node>...
wait_for() {
  local path="$1" deadline=$((SECONDS + $2)) streak=0 n
  shift 2
  while ((SECONDS < deadline)); do
    n="$(node_of "$path")"
    if [[ " $* " == *" $n "* ]]; then streak=$((streak + 1)); else streak=0; fi
    ((streak >= 6)) && return 0
    sleep 0.3
  done
  return 1
}

restore() { $COMPOSE start $ALL_BACKENDS >/dev/null 2>&1 || true; }
trap restore EXIT

# ------------------------------------------------------------------------------
title "0. Waiting for the lab to be ready"
if wait_for / 60 web1 web2 && wait_for /api/ 30 api-primary; then
  ok "proxy is answering on $BASE_URL"
else
  bad "lab did not become ready - is it running? (make up)"
  exit 1
fi

# ------------------------------------------------------------------------------
title "1. Baseline: load balancing and routing"
web="$(sample 20 / 0.05)"
echo "  web pool: $(echo "$web" | summary)"
check "web1 and web2 both serve traffic" \
  "$([[ $(echo "$web" | count web1) -gt 0 && $(echo "$web" | count web2) -gt 0 ]] && echo true)"
check "backup node web-dr is idle while the active nodes are healthy" \
  "$([[ $(echo "$web" | count web-dr) -eq 0 ]] && echo true)"

api="$(sample 10 /api/ 0.05)"
echo "  api pool: $(echo "$api" | summary)"
check "/api is routed to api-primary only" \
  "$([[ $(echo "$api" | count api-primary) -eq 10 ]] && echo true)"

# ------------------------------------------------------------------------------
title "2. Security controls at the edge"
redirect="$(curl -s -o /dev/null --max-time 5 -w '%{http_code} %{redirect_url}' "$HTTP_URL/some/page")"
echo "  HTTP request -> $redirect"
check "plain HTTP is redirected to HTTPS (301)" \
  "$([[ "$redirect" == 301\ https://* ]] && echo true)"

headers="$(curl -sk --max-time 5 -o /dev/null -D - "$BASE_URL/" | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
check "HSTS header is set" \
  "$(echo "$headers" | grep -q '^strict-transport-security:' && echo true)"
check "backend Server header is hidden" \
  "$(echo "$headers" | grep -q '^server:' || echo true)"

old_tls="$(curl -sk --max-time 5 --tls-max 1.1 -o /dev/null -w '%{http_code}' "$BASE_URL/" 2>/dev/null)"
check "TLS 1.1 and older are refused" \
  "$([[ "$old_tls" == "000" ]] && echo true)"

# ------------------------------------------------------------------------------
title "3. Partial failure: one active web node dies"
$COMPOSE stop -t 0 web1 >/dev/null 2>&1
res="$(sample 30 / 0.2)"
echo "  during failure: $(echo "$res" | summary)"
check "no client-facing errors while web1 is down (retried on web2)" \
  "$([[ $(echo "$res" | count ERR) -eq 0 ]] && echo true)"
check "traffic converged on web2" \
  "$([[ "$(echo "$res" | tail -n 10 | sort -u)" == "web2" ]] && echo true)"

# ------------------------------------------------------------------------------
title "4. Total pool failure: last active web node dies"
$COMPOSE stop -t 0 web2 >/dev/null 2>&1
start=$SECONDS
res="$(sample 40 / 0.2)"
echo "  during failure: $(echo "$res" | summary)"
echo "  requests lost while HAProxy detected the outage: $(echo "$res" | count ERR) of 40"
check "backup node web-dr took over" \
  "$([[ "$(echo "$res" | tail -n 10 | sort -u)" == "web-dr" ]] && echo true)"

# ------------------------------------------------------------------------------
title "5. Failback: active web nodes return"
$COMPOSE start web1 web2 >/dev/null 2>&1
start=$SECONDS
if wait_for / 45 web1 web2; then
  ok "traffic moved back to the active nodes in ~$((SECONDS - start))s"
else
  bad "traffic did not return to web1/web2 within 45s"
fi
res="$(sample 20 / 0.05)"
echo "  after recovery: $(echo "$res" | summary)"
check "web-dr is idle again" \
  "$([[ $(echo "$res" | count web-dr) -eq 0 ]] && echo true)"

# ------------------------------------------------------------------------------
title "6. Active/standby: API primary dies"
$COMPOSE stop -t 0 api-primary >/dev/null 2>&1
start=$SECONDS
if wait_for /api/ 20 api-standby; then
  ok "api-standby took over in ~$((SECONDS - start))s"
else
  bad "api-standby did not take over within 20s"
fi
$COMPOSE start api-primary >/dev/null 2>&1
start=$SECONDS
if wait_for /api/ 45 api-primary; then
  ok "api-primary resumed in ~$((SECONDS - start))s"
else
  bad "api-primary did not resume within 45s"
fi

# ------------------------------------------------------------------------------
title "Result"
echo "  $pass passed, $fail failed"
[[ $fail -eq 0 ]]
