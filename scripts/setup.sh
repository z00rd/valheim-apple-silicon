#!/usr/bin/env bash
# JEDNORAZOWY setup: tworzy maszynę x86_64 (pełny QEMU) i podnosi serwer + Tailscale.
# Pierwsze uruchomienie POTRWA (~10-15 min): pobiera i emuluje x86 Ubuntu, potem serwer Valheim.
source "$(dirname "$0")/lib.sh"

need_colima
need_env

info "1/4  Maszyna wirtualna x86_64 (pełny QEMU) — profil '$PROFILE'"
if vm_running; then
  c_grn "VM już działa."
else
  c_ylw "Startuję VM. To długo trwa za pierwszym razem — nie przerywaj."
  colima start "$PROFILE" --arch x86_64 --vm-type qemu --cpu "$VM_CPU" --memory "$VM_MEM" --disk "$VM_DISK"
fi

info "2/4  Upewniam się, że moduł 'tun' jest w VM (potrzebny Tailscale)"
colima ssh --profile "$PROFILE" -- sudo modprobe tun 2>/dev/null || true

info "3/4  Pobieram obrazy i podnoszę kontenery (Tailscale + Valheim)"
compose pull
compose up -d

info "4/4  Czekam aż serwer zgłosi gotowość ('Opened Steam server') — pobiera serwer Valheim, cierpliwie..."
ok=0
for _ in $(seq 1 90); do
  if compose logs valheim 2>/dev/null | grep -qE "Opened Steam server|Connections [0-9]"; then ok=1; break; fi
  sleep 10; printf '.'
done
echo

IP="$(ts_ip)"
echo
if [ "$ok" = "1" ]; then c_grn "================== GOTOWE =================="; else c_ylw "===== Serwer jeszcze wstaje (sprawdź logi) ====="; fi
echo "  Adres dla znajomych (Join IP w grze):  ${IP:-<uruchom ./scripts/status.sh>}:2456"
echo "  Hasło:                                  z .env (SERVER_PASS)"
echo "  Status:                                 ./scripts/status.sh"
echo "  Logi:                                   ./scripts/logs.sh"
echo "  Import świata:                          ./scripts/import-world.sh <świat>.db <świat>.fwl"
c_grn "============================================"
[ "$ok" = "1" ] || c_ylw "Jeśli po kilku minutach dalej brak gotowości — sprawdź ./scripts/logs.sh"
