#!/usr/bin/env bash
# Breaks the lab on purpose and checks it behaves. Exits non-zero if any check
# fails, so CI runs it on every push.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

pass=0; fail=0
ok()    { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()   { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
title() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
check() { if [[ "$2" == "true" ]]; then ok "$1"; else bad "$1"; fi; }

count()    { grep -c -E "$1" || true; }
distinct() { sort -u | grep -c . || true; }
# all_match <regex>: true if every line on stdin matches
all_match() { if grep -q -v -E "$1"; then echo false; else echo true; fi; }
summary() {
  awk '
    /^egress-(0[1-9]|1[0-6])$/ { p++; next }
    /^egress-/                 { r++; next }
    /^BLOCKED$/                { b++; next }
                               { o++ }
    END { printf "primary x%d, reserve x%d, blocked x%d, other x%d", p, r, b, o }'
}

# wait_for <seconds> <regex>: succeeds once 5 requests in a row match
wait_for() {
  local deadline=$((SECONDS + $1)) streak=0
  while ((SECONDS < deadline)); do
    if burst 1 0 | grep -q -E "$2"; then streak=$((streak + 1)); else streak=0; fi
    ((streak >= 5)) && return 0
  done
  return 1
}

# Try to reach the target from the client WITHOUT the gateway. Prints what came back.
direct_attempt() {
  local ip
  ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$($COMPOSE ps -q target)")"
  $COMPOSE exec -T client sh -c '
    curl -s --max-time 3 --noproxy "*" http://target/ 2>/dev/null
    curl -s --max-time 3 --noproxy "*" "http://$0/" 2>/dev/null' "$ip"
}

cleanup() { revive $PRIMARY $RESERVE; runtime "enable frontend fe_egress" >/dev/null 2>&1; }
trap cleanup EXIT

# ------------------------------------------------------------------------------
title "0. Waiting for the lab"
if wait_for 90 "$PRIMARY_RE"; then
  ok "client can get out through the gateway"
else
  bad "lab did not become ready - is it running? (make up)"
  exit 1
fi
sleep 3   # let every proxy finish its first health checks

# ------------------------------------------------------------------------------
title "1. Normal operation"
res="$(burst 48 0.02)"
echo "  $(echo "$res" | summary), $(echo "$res" | distinct) different exits used"
check "traffic rotates across all 16 primary proxies" \
  "$([[ $(echo "$res" | grep -E "$PRIMARY_RE" | distinct) -eq 16 ]] && echo true)"
check "reserve proxies stay idle" \
  "$([[ $(echo "$res" | count "$RESERVE_RE") -eq 0 ]] && echo true)"

# ------------------------------------------------------------------------------
title "2. Isolation"
leak="$(direct_attempt)"
check "client cannot reach the outside without the gateway" \
  "$([[ -z "$leak" ]] && echo true)"
open="$($COMPOSE exec -T -e http_proxy=http://egress-01:8888 target wget -q -T 3 -O- http://target/ 2>/dev/null)"
check "exit proxies refuse anyone who is not the gateway" \
  "$([[ -z "$open" ]] && echo true)"

# ------------------------------------------------------------------------------
title "3. One proxy crashes"
crash egress-03
res="$(burst 40 0.15)"
echo "  $(echo "$res" | summary)"
check "no requests blocked while egress-03 is down" \
  "$([[ $(echo "$res" | count '^BLOCKED$') -eq 0 ]] && echo true)"
check "egress-03 is out of rotation" \
  "$([[ $(echo "$res" | tail -n 20 | count '^egress-03$') -eq 0 ]] && echo true)"

# ------------------------------------------------------------------------------
title "4. Per-proxy kill switch"
./scripts/killswitch.sh proxy 05 off >/dev/null
res="$(burst 32 0.02)"
echo "  $(echo "$res" | summary)"
check "egress-05 gets no traffic as soon as it is switched off" \
  "$([[ $(echo "$res" | count '^egress-05$') -eq 0 ]] && echo true)"
check "no requests blocked" \
  "$([[ $(echo "$res" | count '^BLOCKED$') -eq 0 ]] && echo true)"
./scripts/killswitch.sh proxy 05 on >/dev/null

# ------------------------------------------------------------------------------
title "5. Whole primary pool crashes"
crash $PRIMARY
start=$SECONDS
if wait_for 30 "$RESERVE_RE"; then
  ok "reserve pool took over in ~$((SECONDS - start))s"
else
  bad "reserve pool did not take over within 30s"
fi
res="$(burst 24 0.02)"
echo "  $(echo "$res" | summary), $(echo "$res" | distinct) different exits used"
check "all traffic now leaves through the 4 reserve proxies" \
  "$([[ $(echo "$res" | grep -E "$RESERVE_RE" | distinct) -eq 4 && $(echo "$res" | all_match "$RESERVE_RE") == true ]] && echo true)"

# ------------------------------------------------------------------------------
title "6. Every proxy is gone: automatic kill switch"
crash $RESERVE
start=$SECONDS
if wait_for 30 '^BLOCKED$'; then
  ok "traffic was cut off in ~$((SECONDS - start))s"
else
  bad "traffic was still getting out 30s after the last proxy died"
fi
res="$(burst 10 0.1)"
echo "  $(echo "$res" | summary)"
check "everything is blocked (fail closed)" \
  "$(echo "$res" | all_match '^BLOCKED$')"
leak="$(direct_attempt)"
check "and nothing leaks out directly" \
  "$([[ -z "$leak" ]] && echo true)"

# ------------------------------------------------------------------------------
title "7. Recovery"
revive $PRIMARY $RESERVE
start=$SECONDS
if wait_for 60 "$PRIMARY_RE"; then
  ok "traffic resumed on the primary pool in ~$((SECONDS - start))s"
else
  bad "traffic did not resume within 60s"
fi
sleep 4
res="$(burst 48 0.02)"
echo "  $(echo "$res" | summary), $(echo "$res" | distinct) different exits used"
check "all 16 primary proxies are back in rotation" \
  "$([[ $(echo "$res" | grep -E "$PRIMARY_RE" | distinct) -eq 16 ]] && echo true)"
check "reserve proxies are idle again" \
  "$([[ $(echo "$res" | count "$RESERVE_RE") -eq 0 ]] && echo true)"

# ------------------------------------------------------------------------------
title "8. Manual kill switch"
./scripts/killswitch.sh on >/dev/null
res="$(burst 10 0.05)"
echo "  switch on:  $(echo "$res" | summary)"
check "switch on: everything is blocked even though all proxies are healthy" \
  "$(echo "$res" | all_match '^BLOCKED$')"
./scripts/killswitch.sh off >/dev/null
res="$(burst 10 0.05)"
echo "  switch off: $(echo "$res" | summary)"
check "switch off: traffic flows again" \
  "$(echo "$res" | all_match "$PRIMARY_RE")"

# ------------------------------------------------------------------------------
title "Result"
echo "  $pass passed, $fail failed"
[[ $fail -eq 0 ]]
