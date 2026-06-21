#!/usr/bin/env bash
# Koniec sesji: backup -> zatrzymanie serwera -> zatrzymanie VM -> Mac może spać.
source "$(dirname "$0")/lib.sh"
need_colima

info "Zatrzymuję most UDP (proxy host->VM)..."
"$(dirname "$0")/host-ts-bridge.sh" stop || true

if vm_running; then
  info "Backup świata przed zamknięciem..."
  "$(dirname "$0")/backup.sh" || c_ylw "Backup nie wyszedł — pomijam."

  info "Zatrzymuję serwer (świat się zapisze, grace 2 min)..."
  compose stop || true

  info "Zatrzymuję VM (zwalnia RAM/CPU)..."
  colima stop "$PROFILE" || true
fi

if [ -f "$CAFFEINATE_PID_FILE" ]; then
  kill "$(cat "$CAFFEINATE_PID_FILE" 2>/dev/null)" 2>/dev/null || true
  rm -f "$CAFFEINATE_PID_FILE"
fi
c_grn "Zatrzymane. Mac może spać."
