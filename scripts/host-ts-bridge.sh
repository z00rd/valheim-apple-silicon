#!/usr/bin/env bash
# Host->VM UDP bridge for the "Tailscale on the Mac HOST" architecture (see ARCHITECTURE.md).
#
# WHY: the Tailscale node MUST live on the Mac host (only the host has easy NAT; any node
# INSIDE the VM — slirp or vmnet — has symmetric NAT, verified with netcheck). The server
# container publishes 2456-2457/udp inside the VM, reachable from the Mac at the VM's vmnet
# address (`colima --network-address`). udp-proxy.py relays those ports from the Mac, and
# Tailscale on the host exposes them at the node's 100.x address.
#
#   Remote player (easy) --direct--> Mac:2456 (host TS, easy NAT) --udp-proxy--> <VM_IP>:2456 --> container
#
# Requires: VM started with --network-address; `tailscale up` done on the host; python3.
# Launched automatically by play.sh (start) and stop.sh (stop). It is session-scoped: there is no
# launchd unit, so after a Mac reboot you re-run play.sh (this is a not-24/7 server by design).
source "$(dirname "$0")/lib.sh"

PORTS=(2456 2457)                       # game / Steam-query (PROFILE + helpers come from lib.sh)
PROXY="$PROJECT_DIR/scripts/udp-proxy.py"

start() {
  command -v python3 >/dev/null || die "python3 not found."
  local ip; ip="$(vm_addr)"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die \
    "VM has no vmnet address — start it with --network-address (use ./scripts/play.sh, which self-heals this)."
  stop
  local port pid log
  for port in "${PORTS[@]}"; do
    log="$PROJECT_DIR/.udp-proxy-${port}.log"
    nohup python3 "$PROXY" "$port" "$ip" "$port" >>"$log" 2>&1 &
    pid=$!
    sleep 0.3
    if kill -0 "$pid" 2>/dev/null; then
      echo "proxy ${port} -> ${ip}:${port}  (pid $pid)"
    else
      die "proxy for port ${port} failed to start — see ${log}"
    fi
  done
  echo "Bridge ready. Join IP = $(ts_ip):2456"
}

stop() {
  pkill -f "$PROXY" 2>/dev/null || true
}

status() {
  pgrep -fl "$PROXY" || echo "no proxy running"
  echo "VM addr: $(vm_addr)   host TS IP: $(ts_ip)"
}

case "${1:-start}" in
  start)  start ;;
  stop)   stop; echo "Bridge stopped." ;;
  status) status ;;
  *) echo "usage: $0 [start|stop|status]"; exit 1 ;;
esac
