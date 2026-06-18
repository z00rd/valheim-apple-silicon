#!/usr/bin/env bash
# Preflight: sprawdza czy środowisko i konfiguracja są gotowe do postawienia serwera.
# Nie zmienia niczego — tylko raportuje. Uruchom:  ./scripts/doctor.sh
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"
ok=0; warn=0; err=0
pass() { printf '  \033[32m✔\033[0m %s\n' "$*"; ok=$((ok+1)); }
warnf(){ printf '  \033[33m▲\033[0m %s\n' "$*"; warn=$((warn+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; err=$((err+1)); }

echo "── System ──"
[ "$(uname -s)" = "Darwin" ] && pass "macOS" || fail "To nie macOS — ten setup jest pod Maca."
if [ "$(uname -m)" = "arm64" ]; then pass "Apple Silicon (arm64)"; else warnf "Nie arm64 ($(uname -m)) — projekt celuje w Apple Silicon (działa też na Intelu, ale instrukcje są pod M-serię)."; fi
RAM=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
[ "$RAM" -ge 8 ] && pass "RAM ${RAM} GB" || warnf "RAM ${RAM} GB — zalecane min. 8 GB (VM dostaje 6 GB)."
DISK=$(df -g / 2>/dev/null | awk 'NR==2{print $4}')
[ "${DISK:-0}" -ge 15 ] && pass "Wolne na dysku ${DISK} GB" || warnf "Mało miejsca (${DISK:-?} GB) — VM + serwer to ~5-8 GB."

echo "── Narzędzia ──"
command -v brew >/dev/null 2>&1 && pass "Homebrew" || fail "Brak Homebrew — zainstaluj z https://brew.sh, potem ./scripts/bootstrap.sh"
command -v colima >/dev/null 2>&1 && pass "colima ($(colima version 2>/dev/null | head -1))" || fail "Brak colima — uruchom ./scripts/bootstrap.sh"
command -v qemu-system-x86_64 >/dev/null 2>&1 && pass "qemu (x86_64)" || fail "Brak qemu — ./scripts/bootstrap.sh  (potrzebne do emulacji x86_64)"
if brew list lima-additional-guestagents >/dev/null 2>&1; then pass "lima-additional-guestagents (agent x86_64)"; else fail "Brak lima-additional-guestagents — ./scripts/bootstrap.sh  (bez tego VM x86_64 nie wstanie)"; fi
command -v docker >/dev/null 2>&1 && pass "docker CLI" || fail "Brak docker CLI — ./scripts/bootstrap.sh"
docker compose version >/dev/null 2>&1 && pass "docker compose (v2)" || warnf "Brak pluginu 'docker compose' — ./scripts/bootstrap.sh (instaluje docker-compose)"

echo "── Konfiguracja (.env) ──"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE" 2>/dev/null; set +a
  [ -n "${SERVER_PASS:-}" ] && [ "${SERVER_PASS:-}" != "ZMIEN_MNIE_min5znakow" ] && [ "${#SERVER_PASS}" -ge 5 ] \
    && pass "SERVER_PASS ustawione (≥5 znaków)" || fail "Ustaw SERVER_PASS w .env (min. 5 znaków)."
  [ -n "${TS_AUTHKEY:-}" ] && [ "${TS_AUTHKEY:-}" != "tskey-auth-WKLEJ-TUTAJ" ] \
    && pass "TS_AUTHKEY ustawione" || fail "Ustaw TS_AUTHKEY w .env (klucz z https://login.tailscale.com/admin/settings/keys)."
  [ -n "${SERVER_NAME:-}" ] && pass "SERVER_NAME: ${SERVER_NAME}" || warnf "Brak SERVER_NAME."
  [ -n "${WORLD_NAME:-}" ] && pass "WORLD_NAME: ${WORLD_NAME}" || warnf "Brak WORLD_NAME."
else
  fail "Brak .env — skopiuj:  cp .env.example .env  i uzupełnij."
fi

echo
printf '\033[1mWynik:\033[0m %d ok, %d ostrzeżeń, %d błędów\n' "$ok" "$warn" "$err"
[ "$err" -eq 0 ] && echo "Gotowe do:  ./scripts/setup.sh" || { echo "Napraw błędy powyżej przed ./scripts/setup.sh"; exit 1; }
