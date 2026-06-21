#!/usr/bin/env bash
# ONE-TIME setup: creates the x86_64 VM (full QEMU) and brings the server up.
# The first run TAKES A WHILE (~10-15 min): downloads and emulates x86 Ubuntu, then the Valheim server.
source "$(dirname "$0")/lib.sh"

need_colima
need_env

info "1/4  x86_64 virtual machine (full QEMU) — profile '$PROFILE'"
if vm_running; then
  c_grn "VM is already running."
else
  c_ylw "Starting the VM. This takes a long time on the first run — don't interrupt."
  # --network-address: gives the VM a vmnet address reachable from the Mac (needed by the host->VM
  # UDP bridge). First run will ask for a sudo password (vmnet). See ARCHITECTURE.md.
  colima start "$PROFILE" --arch x86_64 --vm-type qemu --cpu "$VM_CPU" --memory "$VM_MEM" --disk "$VM_DISK" --network-address
fi

info "2/4  Making sure the 'tun' module is available in the VM"
colima ssh --profile "$PROFILE" -- sudo modprobe tun 2>/dev/null || true

info "3/4  Pulling images and bringing up the containers"
compose pull
compose up -d

info "4/4  Waiting for the server to report readiness ('Opened Steam server') — it downloads the Valheim server, be patient..."
ok=0
for _ in $(seq 1 90); do
  if compose logs valheim 2>/dev/null | grep -qE "Opened Steam server|Connections [0-9]"; then ok=1; break; fi
  sleep 10; printf '.'
done
echo

IP="$(ts_ip)"
echo
if [ "$ok" = "1" ]; then c_grn "================== DONE =================="; else c_ylw "===== Server still starting (check the logs) ====="; fi
echo "  Address for friends (Join IP in game):  ${IP:-<run ./scripts/status.sh>}:2456"
echo "  Password:                                from .env (SERVER_PASS)"
echo "  Status:                                  ./scripts/status.sh"
echo "  Logs:                                    ./scripts/logs.sh"
echo "  Import a world:                          ./scripts/import-world.sh <world>.db <world>.fwl"
c_grn "=========================================="
[ "$ok" = "1" ] || c_ylw "If it's still not ready after a few minutes — check ./scripts/logs.sh"
