#!/usr/bin/env bash
# "Gramy dziś wieczorem" — jedna komenda: VM + serwer + Mac nie zaśnie.
source "$(dirname "$0")/lib.sh"
need_colima
need_env

if ! vm_running; then
  info "Startuję VM..."
  # --network-address: VM dostaje adres vmnet osiągalny z Maca (np. 192.168.106.2) — niezbędny dla
  # mostka UDP host->VM (Opcja 1). Pierwszy raz poprosi o sudo (vmnet). Patrz ROADMAP.md.
  colima start "$PROFILE" --arch x86_64 --vm-type qemu --cpu "$VM_CPU" --memory "$VM_MEM" --disk "$VM_DISK" --network-address
fi

info "Podnoszę serwer..."
compose up -d

# Most UDP host->VM: Tailscale biegnie na HOŚCIE (easy NAT → direct P2P), a proxy przerzuca
# porty gry do kontenera w VM. Patrz ROADMAP.md "Opcja 1" + scripts/host-ts-bridge.sh.
if tailscale status >/dev/null 2>&1; then
  info "Uruchamiam most UDP (proxy host->VM)..."
  "$(dirname "$0")/host-ts-bridge.sh" start || c_ylw "Most nie wstał — diagnoza: ./scripts/host-ts-bridge.sh status"
else
  c_ylw "Tailscale na HOŚCIE nie działa — uruchom raz:  sudo brew services start tailscale && tailscale up"
fi

# Keep-awake: Mac nie zaśnie dopóki trwa sesja (działa przy OTWARTEJ klapie / na zasilaniu).
if [ -f "$CAFFEINATE_PID_FILE" ] && kill -0 "$(cat "$CAFFEINATE_PID_FILE" 2>/dev/null)" 2>/dev/null; then
  :
else
  nohup caffeinate -dimsu >/dev/null 2>&1 &
  echo $! > "$CAFFEINATE_PID_FILE"
fi

IP="$(ts_ip)"
echo
c_grn "Serwer wstaje. Znajomi w grze -> Join IP -> ${IP:-<./scripts/status.sh>}:2456"
c_ylw "Mac nie zaśnie podczas sesji. Po graniu odpal:  ./scripts/stop.sh"
c_ylw "caffeinate trzyma Maca przy OTWARTEJ klapie / na zasilaniu. Zamknięta klapa -> patrz README."
