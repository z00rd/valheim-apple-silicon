#!/usr/bin/env bash
# Host->VM UDP bridge for the "Tailscale on the Mac HOST" architecture (see ARCHITECTURE.md).
#
# WHY: the Tailscale node MUST live on the Mac host (only the host has easy NAT; any node
# INSIDE the VM — slirp or vmnet — has symmetric NAT, verified with netcheck). The server
# container publishes 2456-2457/udp inside the VM, reachable from the Mac at the VM's vmnet
# address (`colima --network-address`, e.g. 192.168.106.2). udp-proxy.py relays those ports
# from the Mac, and Tailscale on the host exposes them at the node's 100.x address.
#
#   Remote player (easy) --direct--> Mac:2456 (host TS, easy NAT) --udp-proxy--> <VM_IP>:2456 --> container
#
# Requires: VM started with `--network-address`; `tailscale up` done on the host; python3.
# Launched automatically by play.sh (start) and stop.sh (stop).
set -euo pipefail

PROFILE="valheim"
PORTS=(2456 2457)
PID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$PID_DIR/.udp-bridge.pids"

vm_ip() { colima list 2>/dev/null | awk -v p="$PROFILE" '$1==p {print $NF}'; }

PROXY="$PID_DIR/scripts/udp-proxy.py"

start() {
  command -v python3 >/dev/null || { echo "python3 not found."; exit 1; }
  local ip; ip="$(vm_ip)"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "The VM has no vmnet address (ADDRESS column in 'colima list' is empty)."
    echo "Start the VM with: colima start $PROFILE --network-address  (other flags from lib.sh)"; exit 1; }
  stop
  : > "$PID_FILE"
  for port in "${PORTS[@]}"; do
    # Multi-client UDP proxy (udp-proxy.py) — socat 'UDP-LISTEN,fork' mangled demux with >1 player.
    # The listener stays up indefinitely (no idle timeout).
    nohup python3 "$PROXY" "$port" "$ip" "$port" >/dev/null 2>&1 &
    echo $! >> "$PID_FILE"
    echo "proxy ${port} -> ${ip}:${port}  (pid $!)"
  done
  echo "Bridge ready. Join IP = $(tailscale ip -4 2>/dev/null | head -1):2456"
}

stop() {
  if [ -f "$PID_FILE" ]; then
    while read -r pid; do [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; done < "$PID_FILE"
    rm -f "$PID_FILE"
  fi
  pkill -f "udp-proxy.py" 2>/dev/null || true
  pkill -f "socat .*UDP4-LISTEN:(2456|2457)" 2>/dev/null || true   # clean up old socat if any remains
}

status() {
  pgrep -fl "udp-proxy.py" || echo "no proxy running"
  echo "VM IP: $(vm_ip)   host TS IP: $(tailscale ip -4 2>/dev/null | head -1)"
}

case "${1:-start}" in
  start)  start ;;
  stop)   stop; echo "Bridge stopped." ;;
  status) status ;;
  *) echo "usage: $0 [start|stop|status]"; exit 1 ;;
esac
