#!/usr/bin/env bash
# Import istniejącego świata (np. od kumpla) do serwera.
# Użycie:  ./scripts/import-world.sh /ścieżka/do/Świat.db /ścieżka/do/Świat.fwl
# Kopiuje oba pliki do serwera, ustawia WORLD_NAME w .env i przypomina o restarcie.
source "$(dirname "$0")/lib.sh"
need_colima

DB="${1:-}"; FWL="${2:-}"
if [ ! -f "$DB" ] || [ ! -f "$FWL" ]; then
  die "Podaj ścieżki do OBU plików świata.
Przykład:  ./scripts/import-world.sh ~/Downloads/Midgard.db ~/Downloads/Midgard.fwl
(Poproś kumpla o oba pliki z jego folderu worlds_local — patrz README.)"
fi

base_db="$(basename "$DB" .db)"
base_fwl="$(basename "$FWL" .fwl)"
[ "$base_db" = "$base_fwl" ] \
  || die "Pliki muszą mieć tę samą nazwę bazową (np. Midgard.db + Midgard.fwl). Mam: '$base_db' vs '$base_fwl'."

vm_running || die "Najpierw odpal serwer raz: ./scripts/setup.sh (utworzy wolumen na świat)."
docker ps --format '{{.Names}}' | grep -q '^valheim$' || die "Kontener 'valheim' nie działa. Odpal ./scripts/play.sh i spróbuj ponownie."

info "Kopiuję świat '$base_db' do serwera..."
docker exec valheim mkdir -p /config/worlds_local
docker cp "$DB"  "valheim:/config/worlds_local/$base_db.db"
docker cp "$FWL" "valheim:/config/worlds_local/$base_db.fwl"

# Ustaw WORLD_NAME w .env (macOS sed)
if [ -f "$ENV_FILE" ]; then
  # usuń istniejącą linię WORLD_NAME i dopisz nową DOSŁOWNIE (bezpieczne dla każdej nazwy: &, /, ...)
  grep -v '^WORLD_NAME=' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
  printf 'WORLD_NAME="%s"\n' "$base_db" >> "$ENV_FILE"
  c_grn "✔ Ustawiłem WORLD_NAME=\"$base_db\" w .env"
fi

info "Restartuję serwer na zaimportowanym świecie..."
compose up -d --force-recreate valheim
c_grn "✔ Gotowe. Serwer wczytuje świat '$base_db'. Sprawdź ./scripts/logs.sh"
