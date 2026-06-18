#!/usr/bin/env bash
# Zrzuca backupy świata z kontenera na dysk Maca (i opcjonalnie na Google Drive).
# Wywoływane ręcznie, przez stop.sh, albo cyklicznie z LaunchAgenta (przykład w README → Backupy).
source "$(dirname "$0")/lib.sh"
need_colima
[ -f "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }

vm_running || die "VM nie działa — nie ma skąd backupować."
mkdir -p "$BACKUP_DIR"

info "Kopiuję gotowe zip-backupy z kontenera -> $BACKUP_DIR"
docker cp valheim:/config/backups/. "$BACKUP_DIR/" 2>/dev/null \
  || c_ylw "Brak jeszcze zrobionych backupów w kontenerze — zrzucam żywy świat."

# Sieć bezpieczeństwa: zrzuć też ŻYWE pliki świata (.db + .fwl)
TS="$(date +%Y%m%d-%H%M%S)"
TMP="$BACKUP_DIR/.live-$TS"
if docker cp "valheim:/config/worlds_local/." "$TMP/" 2>/dev/null; then
  if ls "$TMP"/*.db >/dev/null 2>&1; then
    ( cd "$TMP" && zip -j -q "$BACKUP_DIR/world-live-$TS.zip" ./*.db ./*.fwl 2>/dev/null ) || true
  fi
  rm -rf "$TMP"
fi

# Sprzątanie kopii NA MACU: zostaw 30 najnowszych zipów (w kontenerze obraz trzyma BACKUPS_MAX_COUNT=12)
ls -1t "$BACKUP_DIR"/*.zip 2>/dev/null | tail -n +31 | xargs -I{} rm -f {} 2>/dev/null || true

# Opcjonalna kopia na Google Drive
if [ "${GDRIVE_DIR:-}" != "" ] && [ -d "${GDRIVE_DIR}" ]; then
  info "Kopiuję na Google Drive: $GDRIVE_DIR"
  cp -f "$BACKUP_DIR"/*.zip "$GDRIVE_DIR"/ 2>/dev/null || true
fi
c_grn "✔ Backup gotowy: $BACKUP_DIR"
