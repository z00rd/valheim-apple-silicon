#!/usr/bin/env bash
# "Let's play tonight" — one command: VM + server + keep the Mac awake.
source "$(dirname "$0")/lib.sh"
need_colima
need_env

# Bring the VM up with a vmnet address (self-heals a VM started without --network-address).
ensure_vm

info "Bringing the server up..."
compose up -d

# Host->VM UDP bridge: Tailscale runs on the HOST (easy NAT → direct P2P), and the proxy relays the
# game ports into the container in the VM. See ARCHITECTURE.md + scripts/host-ts-bridge.sh.
info "Starting the UDP bridge (host->VM proxy)..."
ensure_bridge

# Keep-awake: keep the SYSTEM awake during the session but let the DISPLAY sleep (a headless server
# doesn't need the screen — saves ~5-8 W). Flags: -i idle, -m disk, -s system-on-AC; we deliberately
# drop -d (display) and -u (user-active), both of which would keep the panel lit.
if [ -f "$CAFFEINATE_PID_FILE" ] && kill -0 "$(cat "$CAFFEINATE_PID_FILE" 2>/dev/null)" 2>/dev/null; then
  :
else
  nohup caffeinate -ims >/dev/null 2>&1 &
  echo $! > "$CAFFEINATE_PID_FILE"
fi

IP="$(ts_ip)"
echo
c_grn "Server is starting. Friends in game -> Join IP -> ${IP:-<./scripts/status.sh>}:2456"
c_ylw "The Mac won't sleep during the session. When done, run:  ./scripts/stop.sh"
c_ylw "Mac stays awake (display may sleep — that's fine); lid OPEN / on power. Lid closed -> see README."
