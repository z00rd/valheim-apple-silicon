#!/usr/bin/env bash
# "Let's play tonight" — one command: VM + server + keep the Mac awake.
source "$(dirname "$0")/lib.sh"
need_colima
need_env

if ! vm_running; then
  info "Starting the VM..."
  # --network-address: the VM gets a vmnet address reachable from the Mac (e.g. 192.168.106.2) —
  # required for the host->VM UDP bridge. First run will ask for sudo (vmnet). See ARCHITECTURE.md.
  colima start "$PROFILE" --arch x86_64 --vm-type qemu --cpu "$VM_CPU" --memory "$VM_MEM" --disk "$VM_DISK" --network-address
fi

info "Bringing the server up..."
compose up -d

# Host->VM UDP bridge: Tailscale runs on the HOST (easy NAT → direct P2P), and the proxy relays the
# game ports into the container in the VM. See ARCHITECTURE.md + scripts/host-ts-bridge.sh.
if tailscale status >/dev/null 2>&1; then
  info "Starting the UDP bridge (host->VM proxy)..."
  "$(dirname "$0")/host-ts-bridge.sh" start || c_ylw "Bridge didn't start — diagnose: ./scripts/host-ts-bridge.sh status"
else
  c_ylw "Tailscale is not running on the HOST — run once:  sudo brew services start tailscale && tailscale up"
fi

# Keep-awake: the Mac won't sleep during the session (works with the lid OPEN / on power).
if [ -f "$CAFFEINATE_PID_FILE" ] && kill -0 "$(cat "$CAFFEINATE_PID_FILE" 2>/dev/null)" 2>/dev/null; then
  :
else
  nohup caffeinate -dimsu >/dev/null 2>&1 &
  echo $! > "$CAFFEINATE_PID_FILE"
fi

IP="$(ts_ip)"
echo
c_grn "Server is starting. Friends in game -> Join IP -> ${IP:-<./scripts/status.sh>}:2456"
c_ylw "The Mac won't sleep during the session. When done, run:  ./scripts/stop.sh"
c_ylw "caffeinate keeps the Mac awake with the lid OPEN / on power. Lid closed -> see README."
