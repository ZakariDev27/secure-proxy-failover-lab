#!/usr/bin/env bash
# Walkthrough: shows where traffic goes while proxies are taken out, the reserve
# pool takes over, and the kill switch blocks everything. It doesn't check
# anything, it just shows you. The checks are in failover-test.sh.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

say() { printf '\n>>> %s\n' "$1"; }
cleanup() { revive $PRIMARY $RESERVE; runtime "enable frontend fe_egress" >/dev/null 2>&1; }
trap cleanup EXIT

say "Normal: traffic rotates through the 16 primary exit proxies"
watch_for 4

say "Crash one proxy (egress-03)"
crash egress-03
watch_for 4

say "Crash the whole primary pool: the 4 reserve proxies should take over"
crash $PRIMARY
watch_for 8

say "Crash the reserve pool too: nothing left, so traffic is blocked"
crash $RESERVE
watch_for 5

say "Bring all 20 proxies back"
revive $PRIMARY $RESERVE
watch_for 8

say "Manual kill switch ON: block everything even though the proxies are fine"
runtime "disable frontend fe_egress" >/dev/null
watch_for 3

say "Kill switch OFF"
runtime "enable frontend fe_egress" >/dev/null
watch_for 3

say "Done"
