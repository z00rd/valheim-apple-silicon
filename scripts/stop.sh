#!/usr/bin/env bash
# End of session: backup -> stop the server -> stop the VM -> the Mac can sleep.
source "$(dirname "$0")/lib.sh"
need_colima

info "Stopping the UDP bridge (host->VM proxy)..."
"$(dirname "$0")/host-ts-bridge.sh" stop || true

if vm_running; then
  info "Backing up the world before shutdown..."
  "$(dirname "$0")/backup.sh" || c_ylw "Backup failed — skipping."

  info "Stopping the server (world is saved, 2 min grace)..."
  compose stop || true

  info "Stopping the VM (frees RAM/CPU)..."
  colima stop "$PROFILE" || true
fi

if [ -f "$CAFFEINATE_PID_FILE" ]; then
  kill "$(cat "$CAFFEINATE_PID_FILE" 2>/dev/null)" 2>/dev/null || true
  rm -f "$CAFFEINATE_PID_FILE"
fi
c_grn "Stopped. The Mac can sleep."
