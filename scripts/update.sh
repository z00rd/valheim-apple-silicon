#!/usr/bin/env bash
# Aktualizacja obrazu kontenera (nowe funkcje wrappera). Sam serwer Valheim
# i tak auto-aktualizuje się co 15 min gdy nikt nie gra — to jest do obrazu.
source "$(dirname "$0")/lib.sh"
need_colima; need_env
vm_running || die "VM nie działa — odpal ./scripts/play.sh albo ./scripts/setup.sh"
info "Pobieram najnowszy obraz i odtwarzam kontenery..."
compose pull
compose up -d
c_grn "✔ Zaktualizowane."
