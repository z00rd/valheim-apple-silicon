#!/usr/bin/env bash
# Wspólne funkcje i zmienne dla wszystkich skryptów projektu valheim-server.
# Źródłowane przez pozostałe skrypty: source "$(dirname "$0")/lib.sh"
set -euo pipefail

# --- Konfiguracja projektu ---------------------------------------------------
PROFILE="valheim"                       # nazwa profilu Colima (osobna VM)
export DOCKER_CONTEXT="colima-${PROFILE}"   # docker context tworzony przez Colima dla tego profilu

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
BACKUP_DIR="$PROJECT_DIR/backups"
CAFFEINATE_PID_FILE="$PROJECT_DIR/.caffeinate.pid"

# Parametry maszyny wirtualnej (x86_64 pełny QEMU — sprawdzona, dokładna emulacja)
VM_CPU=4
VM_MEM=6        # GiB
VM_DISK=60      # GiB

# docker compose z naszym plikiem i .env
compose() { docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"; }

# --- Pomocnicze --------------------------------------------------------------
c_red()   { printf '\033[31m%s\033[0m\n' "$*"; }
c_grn()   { printf '\033[32m%s\033[0m\n' "$*"; }
c_ylw()   { printf '\033[33m%s\033[0m\n' "$*"; }
info()    { printf '\033[36m▶ %s\033[0m\n' "$*"; }
die()     { c_red "✖ $*"; exit 1; }

need_colima() {
  command -v colima >/dev/null 2>&1 || die "Brak 'colima'. Zainstaluj:  brew install colima docker docker-compose"
  command -v docker  >/dev/null 2>&1 || die "Brak 'docker' CLI. Zainstaluj:  brew install docker docker-compose"
}

need_env() {
  [ -f "$ENV_FILE" ] || die "Brak pliku .env ($ENV_FILE). Skopiuj .env.example -> .env i uzupełnij."
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
  [ "${SERVER_PASS:-}" != "" ] && [ "${SERVER_PASS:-}" != "ZMIEN_MNIE_min5znakow" ] \
    || die "Ustaw prawdziwe SERVER_PASS w .env (min. 5 znaków)."
  # TS_AUTHKEY już NIEwymagany: od Opcji 1 Tailscale biegnie na HOŚCIE (jednorazowe `tailscale up`),
  # nie w kontenerze w VM. Patrz ROADMAP.md "Opcja 1".
}

vm_running() { colima status "$PROFILE" >/dev/null 2>&1; }   # exit code Colimy jest miarodajny (grep 'running' łapał też 'is not running')

# Adres Tailscale węzła z serwerem = HOST Maca (węzeł macbook-priv). Od Opcji 1 Tailscale
# biegnie na hoście, nie w VM (tylko host ma easy NAT → direct P2P). Patrz ROADMAP.md.
ts_ip() { tailscale ip -4 2>/dev/null | head -1 || true; }
