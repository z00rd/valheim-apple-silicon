#!/usr/bin/env bash
# Mostek UDP host->VM dla architektury "Tailscale na HOŚCIE Maca" (Opcja 1 z ROADMAP.md).
#
# DLACZEGO: węzeł Tailscale MUSI być na hoście Maca (tylko host ma easy NAT; każdy węzeł
# WEWNĄTRZ VM — slirp czy vmnet — ma symetryczny NAT, sprawdzone netcheckiem). Kontener
# serwera publikuje 2456-2457/udp w VM, osiągalne z Maca pod adresem vmnet VM
# (`colima --network-address`, np. 192.168.106.2). socat przerzuca te porty z Maca, a
# Tailscale hosta wystawia je pod adresem 100.x węzła `macbook-priv`.
#
#   Jasiek (easy) --direct--> Mac:2456 (host TS, easy NAT) --socat--> <VM_IP>:2456 --> kontener
#
# Wymaga: VM wstała z `--network-address`; `tailscale up` zrobiony na hoście; socat (brew).
# UWAGA: to rozwiązanie jest PROWIZORYCZNE do czasu potwierdzenia wejściem zdalnego gracza,
# i NIE jest jeszcze wpięte w play.sh/stop.sh (świadomie — patrz ROADMAP.md).
set -euo pipefail

PROFILE="valheim"
PORTS=(2456 2457)
PID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$PID_DIR/.socat-bridge.pids"

vm_ip() { colima list 2>/dev/null | awk -v p="$PROFILE" '$1==p {print $NF}'; }

start() {
  command -v socat >/dev/null || { echo "Brak socat. brew install socat"; exit 1; }
  local ip; ip="$(vm_ip)"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "VM nie ma adresu vmnet (kolumna ADDRESS w 'colima list' pusta)."
    echo "Wstań VM z: colima start $PROFILE --network-address  (reszta flag z lib.sh)"; exit 1; }
  stop
  : > "$PID_FILE"
  for port in "${PORTS[@]}"; do
    nohup socat -T600 "UDP4-LISTEN:${port},fork,reuseaddr" "UDP4:${ip}:${port}" >/dev/null 2>&1 &
    echo $! >> "$PID_FILE"
    echo "socat ${port} -> ${ip}:${port}  (pid $!)"
  done
  echo "Most gotowy. Join IP (NOWY) = $(tailscale ip -4 2>/dev/null | head -1):2456"
}

stop() {
  if [ -f "$PID_FILE" ]; then
    while read -r pid; do [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; done < "$PID_FILE"
    rm -f "$PID_FILE"
  fi
  pkill -f "socat .*UDP4-LISTEN:(2456|2457)" 2>/dev/null || true
}

status() {
  pgrep -fl "socat .*UDP4-LISTEN" || echo "brak socat"
  echo "VM IP: $(vm_ip)   host TS IP: $(tailscale ip -4 2>/dev/null | head -1)"
}

case "${1:-start}" in
  start)  start ;;
  stop)   stop; echo "Most zatrzymany." ;;
  status) status ;;
  *) echo "uzycie: $0 [start|stop|status]"; exit 1 ;;
esac
