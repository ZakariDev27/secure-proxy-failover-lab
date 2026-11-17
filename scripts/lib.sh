#!/usr/bin/env bash
# Shared helpers for the lab scripts.
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

COMPOSE="${COMPOSE:-docker compose}"
PRIMARY="$(printf 'egress-%02d ' $(seq 1 16))"
RESERVE="$(printf 'egress-%02d ' $(seq 17 20))"
PRIMARY_RE='^egress-(0[1-9]|1[0-6])$'
RESERVE_RE='^egress-(1[7-9]|20)$'

# burst <count> <delay>: send requests from the client through the gateway.
# Prints one line per request: the exit proxy that carried it, or BLOCKED.
burst() {
  $COMPOSE exec -T client sh -c '
    i=0
    while [ "$i" -lt "$0" ]; do
      r="$(curl -sf --max-time 4 -x http://gateway:3128 http://target/ 2>/dev/null)" || r=""
      echo "${r:-BLOCKED}"
      i=$((i + 1))
      sleep "$1"
    done' "$1" "$2"
}

# watch_for <seconds>: like burst, but timestamped and with response times.
watch_for() {
  $COMPOSE exec -T client sh -c '
    end=$(( $(date +%s) + $0 ))
    while [ "$(date +%s)" -lt "$end" ]; do
      out="$(curl -sf --max-time 3 -x http://gateway:3128 -w " %{time_total}" http://target/ 2>/dev/null | tr "\n" " ")"
      set -- $out
      if [ "$#" -eq 2 ]; then node="$1"; t="$2"; else node="BLOCKED"; t="${1:-0}"; fi
      ms="$(awk "BEGIN { printf \"%d\", $t * 1000 }")"
      printf "%s  %-10s %sms\n" "$(date +%H:%M:%S)" "$node" "$ms"
      sleep 0.3
    done' "$1"
}

# runtime "<command>": send a command to the gateway's HAProxy runtime API.
runtime() {
  $COMPOSE exec -T gateway sh -c 'echo "$0" | nc -w 2 127.0.0.1 9999' "$1"
}

crash()  { $COMPOSE stop -t 0 "$@" >/dev/null 2>&1; }
revive() { $COMPOSE start "$@" >/dev/null 2>&1; }
