#!/usr/bin/env bash
# Quick overview: is the VM up, are the containers alive, the Tailscale address, is the server ready.
source "$(dirname "$0")/lib.sh"
need_colima

echo "── VM (Colima '$PROFILE') ──"
colima status "$PROFILE" 2>&1 | sed 's/^/  /' || echo "  (not running)"

if vm_running; then
  echo; echo "── Containers ──"
  compose ps 2>/dev/null | sed 's/^/  /' || true

  echo; echo "── Tailscale (host) ──"
  IP="$(ts_ip)"
  echo "  Server address (Join IP):  ${IP:-?}:2456"
  tailscale status 2>/dev/null | head -10 | sed 's/^/  /' || echo "  (tailscale not running on the host)"

  echo; echo "── Valheim server ──"
  if compose logs --tail=400 valheim 2>/dev/null | grep -qE "Opened Steam server|Connections [0-9]"; then
    c_grn "  ✔ Server ready (Opened Steam server / heartbeat)"
  else
    c_ylw "  ⚠ Server still starting (first world generating?) — see ./scripts/logs.sh"
  fi
fi
