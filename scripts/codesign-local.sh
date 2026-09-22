#!/bin/bash
set -euo pipefail
umask 077
ISLAND_SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ISLAND_SCRIPT_ROOT/lib/local-signing.sh"
source "$ISLAND_SCRIPT_ROOT/lib/local-lock.sh"
source "$ISLAND_SCRIPT_ROOT/lib/codesign-app.sh"
[[ $# -eq 1 ]] || island_die "Usage: $0 /path/to/Airlet.app"
island_require_app_layout "$1"
island_trap_build_lock_cleanup
island_acquire_build_lock "$(cd "$ISLAND_SCRIPT_ROOT/.." && pwd)"
island_codesign_app "$1"
