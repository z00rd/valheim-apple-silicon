#!/usr/bin/env bash
# Preflight: checks whether the environment and config are ready to stand the server up.
# Changes nothing — just reports. Run:  ./scripts/doctor.sh
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"
ok=0; warn=0; err=0
pass() { printf '  \033[32m✔\033[0m %s\n' "$*"; ok=$((ok+1)); }
warnf(){ printf '  \033[33m▲\033[0m %s\n' "$*"; warn=$((warn+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; err=$((err+1)); }

echo "── System ──"
[ "$(uname -s)" = "Darwin" ] && pass "macOS" || fail "Not macOS — this setup is for a Mac."
if [ "$(uname -m)" = "arm64" ]; then pass "Apple Silicon (arm64)"; else warnf "Not arm64 ($(uname -m)) — project targets Apple Silicon (works on Intel too, but the instructions assume M-series)."; fi
RAM=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
[ "$RAM" -ge 8 ] && pass "RAM ${RAM} GB" || warnf "RAM ${RAM} GB — 8 GB recommended (the VM gets 6 GB)."
DISK=$(df -g / 2>/dev/null | awk 'NR==2{print $4}')
[ "${DISK:-0}" -ge 15 ] && pass "Free disk ${DISK} GB" || warnf "Low on space (${DISK:-?} GB) — VM + server is ~5-8 GB."

echo "── Tools ──"
command -v brew >/dev/null 2>&1 && pass "Homebrew" || fail "Homebrew missing — install from https://brew.sh, then ./scripts/bootstrap.sh"
command -v colima >/dev/null 2>&1 && pass "colima ($(colima version 2>/dev/null | head -1))" || fail "colima missing — run ./scripts/bootstrap.sh"
command -v qemu-system-x86_64 >/dev/null 2>&1 && pass "qemu (x86_64)" || fail "qemu missing — ./scripts/bootstrap.sh  (needed for x86_64 emulation)"
if brew list lima-additional-guestagents >/dev/null 2>&1; then pass "lima-additional-guestagents (x86_64 agent)"; else fail "lima-additional-guestagents missing — ./scripts/bootstrap.sh  (without it the x86_64 VM won't start)"; fi
command -v docker >/dev/null 2>&1 && pass "docker CLI" || fail "docker CLI missing — ./scripts/bootstrap.sh"
docker compose version >/dev/null 2>&1 && pass "docker compose (v2)" || warnf "'docker compose' plugin missing — ./scripts/bootstrap.sh (installs docker-compose)"

echo "── Tailscale (on the host — for direct P2P) ──"
if command -v tailscale >/dev/null 2>&1; then
  if tailscale status >/dev/null 2>&1; then pass "tailscale running on the host"; else warnf "tailscale installed but not up — run: sudo brew services start tailscale && tailscale up"; fi
else
  warnf "tailscale missing — run: brew install tailscale && sudo brew services start tailscale && tailscale up (gives remote players direct P2P)"
fi

echo "── Config (.env) ──"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE" 2>/dev/null; set +a
  [ -n "${SERVER_PASS:-}" ] && [ "${SERVER_PASS:-}" != "CHANGE_ME_min5chars" ] && [ "${#SERVER_PASS}" -ge 5 ] \
    && pass "SERVER_PASS set (≥5 chars)" || fail "Set SERVER_PASS in .env (min. 5 chars)."
  [ -n "${SERVER_NAME:-}" ] && pass "SERVER_NAME: ${SERVER_NAME}" || warnf "SERVER_NAME missing."
  [ -n "${WORLD_NAME:-}" ] && pass "WORLD_NAME: ${WORLD_NAME}" || warnf "WORLD_NAME missing."
else
  fail "No .env — copy:  cp .env.example .env  and fill it in."
fi

echo
printf '\033[1mResult:\033[0m %d ok, %d warnings, %d errors\n' "$ok" "$warn" "$err"
[ "$err" -eq 0 ] && echo "Ready for:  ./scripts/setup.sh" || { echo "Fix the errors above before ./scripts/setup.sh"; exit 1; }
