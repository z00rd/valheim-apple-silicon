#!/usr/bin/env bash
# Update the container image (new wrapper features). The Valheim server itself
# auto-updates every 15 min when nobody is playing — this is for the image.
source "$(dirname "$0")/lib.sh"
need_colima; need_env
vm_running || die "VM is not running — run ./scripts/play.sh or ./scripts/setup.sh"
info "Pulling the latest image and recreating the containers..."
compose pull
compose up -d
c_grn "✔ Updated."
