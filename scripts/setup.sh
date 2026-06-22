#!/usr/bin/env bash
# ONE-TIME setup: creates the x86_64 VM (full QEMU) and brings the server up.
# The first run TAKES A WHILE (~10-15 min): downloads and emulates x86 Ubuntu, then the Valheim server.
source "$(dirname "$0")/lib.sh"

need_colima
need_env

info "1/3  x86_64 virtual machine (full QEMU) with a vmnet address — profile '$PROFILE'"
ensure_vm

info "2/3  Pulling images and bringing up the containers"
compose pull
compose up -d

info "3/3  Waiting for the server to report readiness ('Opened Steam server') — it downloads the Valheim server, be patient..."
ok=0
for _ in $(seq 1 90); do
  if compose logs valheim 2>/dev/null | grep -qE "Opened Steam server|Connections [0-9]"; then ok=1; break; fi
  sleep 10; printf '.'
done
echo

# Start the host->VM UDP bridge so the server is reachable on the tailnet right away
# (same bridge that play.sh manages). Needs Tailscale running on the host.
ensure_bridge

IP="$(ts_ip)"
echo
if [ "$ok" = "1" ]; then c_grn "================== DONE =================="; else c_ylw "===== Server still starting (check the logs) ====="; fi
echo "  Address for friends (Join IP in game):  ${IP:-<run ./scripts/status.sh>}:2456"
echo "  Password:                                from .env (SERVER_PASS)"
echo "  Status:                                  ./scripts/status.sh"
echo "  Logs:                                    ./scripts/logs.sh"
echo "  Import a world:                          ./scripts/import-world.sh <world>.db <world>.fwl"
c_grn "=========================================="
echo "For day-to-day sessions use:  ./scripts/play.sh  (start)  ·  ./scripts/stop.sh  (end)"
[ "$ok" = "1" ] || c_ylw "If it's still not ready after a few minutes — check ./scripts/logs.sh"
