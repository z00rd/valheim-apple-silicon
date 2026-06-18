#!/usr/bin/env bash
# Podgląd logów serwera na żywo (Ctrl-C aby wyjść).
source "$(dirname "$0")/lib.sh"
need_colima
compose logs -f --tail=120 valheim
