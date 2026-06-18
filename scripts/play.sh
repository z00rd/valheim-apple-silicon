#!/usr/bin/env bash
# "Gramy dziś wieczorem" — jedna komenda: VM + serwer + Mac nie zaśnie.
source "$(dirname "$0")/lib.sh"
need_colima
need_env

if ! vm_running; then
  info "Startuję VM..."
  colima start "$PROFILE" --arch x86_64 --vm-type qemu --cpu "$VM_CPU" --memory "$VM_MEM" --disk "$VM_DISK"
fi

info "Podnoszę serwer..."
compose up -d

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
