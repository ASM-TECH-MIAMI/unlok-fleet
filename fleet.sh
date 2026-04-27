#!/bin/bash
# fleet.sh — dispatch commands across the unlok helper fleet (run on workstation)
#
# Usage:
#   fleet.sh all "<command>"        run on all online helpers, in parallel
#   fleet.sh <N> "<command>"        run on unlok-server-<N> only
#   fleet.sh status                 quick health check (uptime + disk + tmux)
#   fleet.sh logs <N>               tail recent agent logs from server <N>

set -uo pipefail

# Edit this list as helpers come online.
SERVERS=(unlok-server-1 unlok-server-2 unlok-server-3 unlok-server-4)

run_on() {
  local host=$1; shift
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" "$@" 2>&1 | sed "s|^|[$host] |"
}

run_all_parallel() {
  local pids=()
  for s in "${SERVERS[@]}"; do
    run_on "$s" "$@" &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p" || true; done
}

cmd=${1:-}
case "$cmd" in
  all)
    shift
    run_all_parallel "$@"
    ;;
  status)
    run_all_parallel 'echo "$(uptime) | disk: $(df -h ~ | tail -1 | awk "{print \$4\" free\"}") | tmux: $(tmux ls 2>/dev/null | wc -l | tr -d " ")"'
    ;;
  logs)
    n=${2:-}
    [ -z "$n" ] && { echo "usage: fleet.sh logs <N>"; exit 1; }
    run_on "unlok-server-$n" 'ls -lt ~/agents/logs/ 2>/dev/null | head -10'
    ;;
  ''|-h|--help)
    sed -n '2,10p' "$0"
    ;;
  *)
    if [[ "$cmd" =~ ^[0-9]+$ ]]; then
      shift
      run_on "unlok-server-$cmd" "$@"
    else
      echo "unknown command: $cmd"
      sed -n '2,10p' "$0"
      exit 1
    fi
    ;;
esac
