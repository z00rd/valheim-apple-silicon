#!/usr/bin/env bash
# Follow the server logs live (Ctrl-C to exit).
source "$(dirname "$0")/lib.sh"
need_colima
compose logs -f --tail=120 valheim
