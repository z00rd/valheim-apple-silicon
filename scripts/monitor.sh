#!/usr/bin/env bash
# Sample resource usage during a session and — crucially — log the top host CPU hogs each tick.
# If players report lag, the synchronized hitch is almost always the server tick stalling because
# the x86 emulator (QEMU) lost CPU to some background host process. This catches that culprit.
#
# Usage:  ./scripts/monitor.sh [minutes]   (default 10; samples every 30s)
# Output: prints live and appends to /tmp/valheim-usage.log
source "$(dirname "$0")/lib.sh"

MINS="${1:-10}"
INTERVAL=30
SAMPLES=$(( MINS * 60 / INTERVAL ))
OUT=/tmp/valheim-usage.log
: > "$OUT"

QPID="$(pgrep -f qemu-system-x86_64 | head -1)"
info "Monitoring ${MINS} min (every ${INTERVAL}s). QEMU pid: ${QPID:-?}. Log: $OUT"

for i in $(seq 1 "$SAMPLES"); do
  TS=$(date +%H:%M:%S)
  CSTAT=$(docker stats valheim --no-stream --format '{{.CPUPerc}} mem={{.MemUsage}} net={{.NetIO}}' 2>/dev/null)
  QCPU=$(ps -o %cpu= -p "$QPID" 2>/dev/null | tr -d ' ')
  CONN=$(docker logs valheim --since 40s 2>&1 | grep -oE 'Connections [0-9]+' | tail -1)
  LOAD=$(uptime | sed 's/.*load averages*: //')
  # Top 3 host CPU consumers — the lag suspects. Exclude QEMU itself so we see the competition.
  TOP=$(ps -axo %cpu,comm | sort -rn | grep -iv qemu | head -3 | awk '{printf "%s(%s%%) ", $2, $1}')
  LINE="$TS | ${CSTAT:-n/a} | ${CONN:-?} | qemu=${QCPU:-?}% | load: $LOAD | top-host: $TOP"
  echo "$LINE"
  echo "$LINE" >> "$OUT"
  sleep "$INTERVAL"
done
info "Done. Full log: $OUT"
