#!/usr/bin/env bash
# Request the public pages continuously and count errors, to check that an
# update causes no downtime.
#
# Usage: scripts/probe.sh <log-file> [interval-seconds]
# Runs until interrupted (Ctrl+C), then prints a summary.
set -uo pipefail

LOG="${1:?usage: scripts/probe.sh <log-file> [interval-seconds]}"
INTERVAL="${2:-0.2}"
NAMESPACE=bernstein

urls=()
for svc in poll result; do
  ip="$(kubectl get svc "$svc" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
  [[ -n "$ip" ]] || { echo "error: $svc has no external IP" >&2; exit 1; }
  urls+=("$svc=http://$ip/")
done

summary() {
  echo
  echo "== $(wc -l < "$LOG") requests"
  awk '{print $2, ($3 == 200 ? "ok" : "ERROR " $3)}' "$LOG" | sort | uniq -c
  grep -v ' 200$' "$LOG" || true
  exit 0
}
trap summary INT TERM

: > "$LOG"
echo "Probing ${urls[*]} every ${INTERVAL}s (Ctrl+C to stop)"
while true; do
  for entry in "${urls[@]}"; do
    code="$(curl -s -o /dev/null -m 2 -w '%{http_code}' "${entry#*=}")"
    echo "$(date +%T.%N | cut -c1-12) ${entry%%=*} $code" >> "$LOG"
  done
  sleep "$INTERVAL"
done
