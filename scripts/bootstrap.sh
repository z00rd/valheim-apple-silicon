#!/usr/bin/env bash
# Instaluje wszystkie zależności potrzebne do postawienia serwera (przez Homebrew).
# Uruchom raz na świeżym Macu:  ./scripts/bootstrap.sh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
say(){ printf '\033[36m▶ %s\033[0m\n' "$*"; }
die(){ printf '\033[31m✗ %s\033[0m\n' "$*"; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Ten skrypt jest pod macOS."
[ "$(uname -m)" = "arm64" ] || printf '\033[33m▲ Nie arm64 — projekt celuje w Apple Silicon. Kontynuuję.\033[0m\n'

command -v brew >/dev/null 2>&1 || die "Brak Homebrew. Zainstaluj: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"  i uruchom ponownie."

say "Instaluję narzędzia maszyny wirtualnej + emulacji x86_64"
# colima  = VM + runtime dockera; qemu = emulacja x86_64;
# lima-additional-guestagents = agent gościa dla x86_64 (bez tego VM x86_64 NIE wstaje)
brew install colima qemu lima-additional-guestagents

if command -v docker >/dev/null 2>&1; then
  say "docker CLI już jest ($(docker --version)) — pomijam"
else
  say "Instaluję docker CLI + plugin compose"
  brew install docker docker-compose
fi

if [ ! -f "$PROJECT_DIR/.env" ]; then
  say "Tworzę .env z szablonu"
  cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
  printf '\033[33m▲ Uzupełnij teraz %s: SERVER_PASS, TS_AUTHKEY, SERVER_NAME, WORLD_NAME\033[0m\n' "$PROJECT_DIR/.env"
fi

chmod +x "$PROJECT_DIR"/scripts/*.sh 2>/dev/null || true

printf '\n\033[32m✔ Zależności zainstalowane.\033[0m\n'
cat <<'EOF'
Dalej:
  1. Uzupełnij .env  (SERVER_PASS min. 5 znaków, TS_AUTHKEY z panelu Tailscale)
  2. ./scripts/doctor.sh     # sprawdzenie gotowości
  3. ./scripts/setup.sh      # postawienie serwera (pierwszy raz ~15+ min)
EOF
