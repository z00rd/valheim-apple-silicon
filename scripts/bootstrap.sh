#!/usr/bin/env bash
# Installs every dependency needed to stand the server up (via Homebrew).
# Run once on a fresh Mac:  ./scripts/bootstrap.sh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
say(){ printf '\033[36m▶ %s\033[0m\n' "$*"; }
die(){ printf '\033[31m✗ %s\033[0m\n' "$*"; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "This script is for macOS."
[ "$(uname -m)" = "arm64" ] || printf '\033[33m▲ Not arm64 — this project targets Apple Silicon. Continuing.\033[0m\n'

command -v brew >/dev/null 2>&1 || die "Homebrew not found. Install: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"  then re-run."

say "Installing VM + x86_64 emulation tooling"
# colima = VM + docker runtime; qemu = x86_64 emulation;
# lima-additional-guestagents = guest agent for x86_64 (without it an x86_64 VM will NOT start)
brew install colima qemu lima-additional-guestagents

if command -v docker >/dev/null 2>&1; then
  say "docker CLI already present ($(docker --version)) — skipping"
else
  say "Installing docker CLI + compose plugin"
  brew install docker docker-compose
fi

say "Installing Tailscale (runs on the host — gives remote players a direct P2P link)"
brew list tailscale >/dev/null 2>&1 || brew install tailscale

if [ ! -f "$PROJECT_DIR/.env" ]; then
  say "Creating .env from the template"
  cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
  printf '\033[33m▲ Now fill in %s: SERVER_PASS, SERVER_NAME, WORLD_NAME\033[0m\n' "$PROJECT_DIR/.env"
fi

chmod +x "$PROJECT_DIR"/scripts/*.sh 2>/dev/null || true

printf '\n\033[32m✔ Dependencies installed.\033[0m\n'
cat <<'EOF'
Next:
  1. Fill in .env                              (SERVER_PASS min. 5 chars, SERVER_NAME, WORLD_NAME)
  2. Set up Tailscale on the host (one-time):  sudo brew services start tailscale && tailscale up
  3. ./scripts/doctor.sh                       # preflight check
  4. ./scripts/setup.sh                        # provision the server (first run ~15+ min)
EOF
