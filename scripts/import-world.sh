#!/usr/bin/env bash
# Import an existing world (e.g. from a friend) into the server.
# Usage:  ./scripts/import-world.sh /path/to/World.db /path/to/World.fwl
# Copies both files into the server, sets WORLD_NAME in .env and restarts.
source "$(dirname "$0")/lib.sh"
need_colima

DB="${1:-}"; FWL="${2:-}"
if [ ! -f "$DB" ] || [ ! -f "$FWL" ]; then
  die "Provide the paths to BOTH world files.
Example:  ./scripts/import-world.sh ~/Downloads/Midgard.db ~/Downloads/Midgard.fwl
(Ask your friend for both files from their worlds_local folder — see README.)"
fi

base_db="$(basename "$DB" .db)"
base_fwl="$(basename "$FWL" .fwl)"
[ "$base_db" = "$base_fwl" ] \
  || die "The files must share the same base name (e.g. Midgard.db + Midgard.fwl). Got: '$base_db' vs '$base_fwl'."

vm_running || die "Run the server once first: ./scripts/setup.sh (creates the world volume)."
docker ps --format '{{.Names}}' | grep -q '^valheim$' || die "The 'valheim' container is not running. Run ./scripts/play.sh and try again."

docker exec valheim mkdir -p /config/worlds_local 2>/dev/null || true

# Stop the server BEFORE copying. A running server holds the (old) world in memory and SAVES it on
# shutdown — which would overwrite the file we just copied (Valheim rotates it to .db.old). So:
# save+stop the old world first, THEN overwrite the files, THEN start so it loads the imported world.
info "Saving & stopping the current server (so it can't overwrite the import)..."
compose stop valheim

info "Copying world '$base_db' into the server..."
docker cp "$DB"  "valheim:/config/worlds_local/$base_db.db"
docker cp "$FWL" "valheim:/config/worlds_local/$base_db.fwl"

# Set WORLD_NAME in .env
if [ -f "$ENV_FILE" ]; then
  # remove any existing WORLD_NAME line and append a new one VERBATIM (safe for any name: &, /, ...)
  grep -v '^WORLD_NAME=' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
  printf 'WORLD_NAME="%s"\n' "$base_db" >> "$ENV_FILE"
  c_grn "✔ Set WORLD_NAME=\"$base_db\" in .env"
fi

info "Starting the server on the imported world..."
compose up -d valheim
c_grn "✔ Done. The server is loading world '$base_db'. Check ./scripts/logs.sh"
