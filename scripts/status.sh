#!/usr/bin/env bash
# Szybki przegląd: czy VM działa, czy kontenery żyją, adres Tailscale, czy serwer nasłuchuje.
source "$(dirname "$0")/lib.sh"
need_colima

echo "── VM (Colima '$PROFILE') ──"
colima status "$PROFILE" 2>&1 | sed 's/^/  /' || echo "  (nie działa)"

if vm_running; then
  echo; echo "── Kontenery ──"
  compose ps 2>/dev/null | sed 's/^/  /' || true

  echo; echo "── Tailscale ──"
  IP="$(ts_ip)"
  echo "  Adres serwera (Join IP):  ${IP:-?}:2456"
  docker exec valheim-ts tailscale status 2>/dev/null | head -10 | sed 's/^/  /' || echo "  (kontener tailscale nie działa)"

  echo; echo "── Serwer Valheim ──"
  if compose logs --tail=400 valheim 2>/dev/null | grep -qE "Opened Steam server|Connections [0-9]"; then
    c_grn "  ✔ Serwer gotowy (Opened Steam server / heartbeat)"
  else
    c_ylw "  ⚠ Serwer jeszcze wstaje (pierwszy świat się generuje?) — zobacz ./scripts/logs.sh"
  fi
fi
