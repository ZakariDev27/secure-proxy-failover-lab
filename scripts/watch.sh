#!/usr/bin/env bash
# Live view of which exit proxy carries each request. Run it in one terminal
# and use the kill switches in another. Ctrl+C to stop.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
watch_for "${1:-3600}"
