#!/usr/bin/env bash
# Pulls world backups from the container onto the Mac's disk (and optionally to Google Drive).
# Called manually, by stop.sh, or periodically from a LaunchAgent (example in README → Backups).
source "$(dirname "$0")/lib.sh"
need_colima
[ -f "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }

vm_running || die "VM is not running — nothing to back up from."
mkdir -p "$BACKUP_DIR"

info "Copying ready-made zip backups from the container -> $BACKUP_DIR"
docker cp valheim:/config/backups/. "$BACKUP_DIR/" 2>/dev/null \
  || c_ylw "No backups made in the container yet — dumping the live world."

# Safety net: also dump the LIVE world files (.db + .fwl)
TS="$(date +%Y%m%d-%H%M%S)"
TMP="$BACKUP_DIR/.live-$TS"
if docker cp "valheim:/config/worlds_local/." "$TMP/" 2>/dev/null; then
  if ls "$TMP"/*.db >/dev/null 2>&1; then
    ( cd "$TMP" && zip -j -q "$BACKUP_DIR/world-live-$TS.zip" ./*.db ./*.fwl 2>/dev/null ) || true
  fi
  rm -rf "$TMP"
fi

# Cleanup of copies ON THE MAC: keep the 30 newest zips (the image keeps BACKUPS_MAX_COUNT=12 in the container)
ls -1t "$BACKUP_DIR"/*.zip 2>/dev/null | tail -n +31 | xargs -I{} rm -f {} 2>/dev/null || true

# Optional copy to Google Drive
if [ "${GDRIVE_DIR:-}" != "" ] && [ -d "${GDRIVE_DIR}" ]; then
  info "Copying to Google Drive: $GDRIVE_DIR"
  cp -f "$BACKUP_DIR"/*.zip "$GDRIVE_DIR"/ 2>/dev/null || true
fi
c_grn "✔ Backup done: $BACKUP_DIR"
