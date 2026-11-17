#!/usr/bin/env bash
# Kill switches for the gateway.
#
#   killswitch.sh on            block ALL outbound traffic right now
#   killswitch.sh off           let traffic flow again
#   killswitch.sh proxy 07 off  pull one exit proxy out of rotation
#   killswitch.sh proxy 07 on   put it back
#   killswitch.sh status        show the switch and every proxy
set -uo pipefail
source "$(dirname "$0")/lib.sh"

case "${1:-status}" in
  on)
    runtime "disable frontend fe_egress" >/dev/null
    echo "Kill switch ON: all outbound traffic is blocked"
    ;;
  off)
    runtime "enable frontend fe_egress" >/dev/null
    echo "Kill switch OFF: traffic is flowing"
    ;;
  proxy)
    node="egress-$(printf '%02d' "$((10#${2:?proxy number, e.g. 07}))")"
    case "${3:-}" in
      off) runtime "disable server be_egress/$node" >/dev/null; echo "$node pulled out of rotation" ;;
      on)  runtime "enable server be_egress/$node"  >/dev/null; echo "$node back in rotation" ;;
      *)   echo "usage: $0 proxy <number> on|off" >&2; exit 2 ;;
    esac
    ;;
  status)
    stat="$(runtime "show stat")"
    fe="$(echo "$stat" | awk -F, '$1=="fe_egress" && $2=="FRONTEND" {print $18}')"
    if [[ "$fe" == "OPEN" ]]; then echo "Kill switch: OFF (traffic allowed)"; else echo "Kill switch: ON (traffic blocked)"; fi
    echo "$stat" | awk -F, '
      $1=="be_egress" && $2 ~ /^egress-/ {
        total++; if ($18 ~ /^UP/) up++
        pool = (substr($2, 8) + 0 <= 16) ? "primary" : "reserve"
        rows = rows sprintf("  %-10s %-8s %s\n", $2, pool, $18)
      }
      END { printf "Exit proxies up: %d of %d\n%s", up, total, rows }'
    ;;
  *)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
