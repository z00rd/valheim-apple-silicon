#!/usr/bin/env bash
# Shared functions and variables for all valheim-server project scripts.
# Sourced by the others: source "$(dirname "$0")/lib.sh"
set -euo pipefail

# --- Project configuration ---------------------------------------------------
PROFILE="valheim"                       # Colima profile name (a dedicated VM)
export DOCKER_CONTEXT="colima-${PROFILE}"   # docker context Colima creates for this profile

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
BACKUP_DIR="$PROJECT_DIR/backups"
CAFFEINATE_PID_FILE="$PROJECT_DIR/.caffeinate.pid"

# VM parameters (x86_64 full QEMU — proven, accurate emulation)
VM_CPU=4
VM_MEM=6        # GiB
VM_DISK=60      # GiB

# docker compose with our file and .env
compose() { docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"; }

# --- Helpers -----------------------------------------------------------------
c_red()   { printf '\033[31m%s\033[0m\n' "$*"; }
c_grn()   { printf '\033[32m%s\033[0m\n' "$*"; }
c_ylw()   { printf '\033[33m%s\033[0m\n' "$*"; }
info()    { printf '\033[36m▶ %s\033[0m\n' "$*"; }
die()     { c_red "✖ $*"; exit 1; }

need_colima() {
  command -v colima >/dev/null 2>&1 || die "'colima' not found. Install:  brew install colima docker docker-compose"
  command -v docker  >/dev/null 2>&1 || die "'docker' CLI not found. Install:  brew install docker docker-compose"
}

need_env() {
  [ -f "$ENV_FILE" ] || die "Missing .env ($ENV_FILE). Copy .env.example -> .env and fill it in."
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
  [ "${SERVER_PASS:-}" != "" ] && [ "${SERVER_PASS:-}" != "CHANGE_ME_min5chars" ] \
    || die "Set a real SERVER_PASS in .env (min. 5 chars)."
  # TS_AUTHKEY is no longer required: Tailscale runs on the HOST (one-time `tailscale up`),
  # not in a container inside the VM. See ARCHITECTURE.md.
}

vm_running() { colima status "$PROFILE" >/dev/null 2>&1; }   # Colima's exit code is authoritative (grep 'running' also matched 'is not running')

# Tailscale address of the server node = the Mac HOST (node on the host). Tailscale runs on the
# host, not in the VM (only the host has easy NAT → direct P2P). See ARCHITECTURE.md.
ts_ip() { tailscale ip -4 2>/dev/null | head -1 || true; }
