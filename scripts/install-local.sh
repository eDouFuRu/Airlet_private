#!/bin/bash
set -euo pipefail
umask 077
ISLAND_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ISLAND_PROJECT_ROOT/scripts/lib/local-signing.sh"
source "$ISLAND_PROJECT_ROOT/scripts/lib/local-lock.sh"
[[ "$(/usr/bin/id -u)" -ne 0 ]] || island_die 'Run this installer as the current user, without sudo.'
ISLAND_INSTALL_SOURCE="$ISLAND_PROJECT_ROOT/build/Build/Products/Debug/Airlet.app"
ISLAND_VERIFY_ONLY=false
ISLAND_SOURCE_SET=false
for ISLAND_ARGUMENT in "$@"; do
  case "$ISLAND_ARGUMENT" in
    --verify-only) ISLAND_VERIFY_ONLY=true ;;
    -h|--help)
      printf 'Usage: %s [Debug|Release|/path/to/app.app] [--verify-only]\n' "$0"
      exit 0 ;;
    *)
      [[ "$ISLAND_SOURCE_SET" == false ]] || island_die 'Specify only one source application.'
      ISLAND_SOURCE_SET=true
      case "$ISLAND_ARGUMENT" in
        Debug|Release) ISLAND_INSTALL_SOURCE="$ISLAND_PROJECT_ROOT/build/Build/Products/$ISLAND_ARGUMENT/Airlet.app" ;;
        /*) ISLAND_INSTALL_SOURCE="$ISLAND_ARGUMENT" ;;
        *) island_die 'Source must be Debug, Release, or an absolute app path.' ;;
      esac ;;
  esac
done
island_verify_app "$ISLAND_INSTALL_SOURCE"
printf 'Verified source: %s\n' "$ISLAND_INSTALL_SOURCE"
printf 'Main requirement: %s\n' "$(island_read_requirement "$ISLAND_INSTALL_SOURCE")"
printf 'XPC requirement: %s\n' "$(island_read_requirement "$ISLAND_INSTALL_SOURCE/$ISLAND_XPC_RELATIVE_PATH")"
[[ "$ISLAND_VERIFY_ONLY" == false ]] || exit 0

ISLAND_APPLICATIONS="$HOME/Applications"
ISLAND_INSTALL_DESTINATION="$ISLAND_APPLICATIONS/Airlet.app"
ISLAND_BACKUP_DIRECTORY="$ISLAND_APPLICATIONS/.NotchIsland-backups"
ISLAND_BACKUP_PATH=''
ISLAND_STAGE_DIRECTORY=''
ISLAND_OLD_MOVED=false
ISLAND_COMMITTED=false

island_assert_stopped() {
  local island_running
  # AppKit inventory only. This sends no Apple Events, quits nothing, and does
  # not rely on ambiguous process names such as "boringNotch".
  island_running="$(/usr/bin/osascript -l JavaScript <<'JXA'
ObjC.import('AppKit');
var matches = [];
var apps = $.NSWorkspace.sharedWorkspace.runningApplications;
for (var i = 0; i < apps.count; i++) {
    var app = apps.objectAtIndex(i);
    if (ObjC.unwrap(app.bundleIdentifier) === 'com.dongfengrui.Airlet') {
        matches.push('PID ' + app.processIdentifier + ': ' + ObjC.unwrap(app.bundleURL.path));
    }
}
matches.join('\n');
JXA
)" || island_die 'Could not check running applications; installation stopped.'
  if [[ -n "$island_running" ]]; then
    printf 'Running copies:\n%s\n' "$island_running" >&2
    island_die 'Quit Airlet before installing, then rerun this script.'
  fi
}

island_check_destination() {
  [[ ! -L "$ISLAND_APPLICATIONS" && ! -L "$ISLAND_INSTALL_DESTINATION" && ! -L "$ISLAND_BACKUP_DIRECTORY" ]] ||
    island_die 'The Applications directory, destination, or backup directory is a symlink; refusing replacement.'
  if [[ -e "$ISLAND_INSTALL_DESTINATION" ]]; then
    [[ -d "$ISLAND_INSTALL_DESTINATION" ]] || island_die 'The fixed destination is not an application directory.'
    island_require_bundle_id "$ISLAND_INSTALL_DESTINATION" "$ISLAND_APP_ID"
  fi
}

island_install_cleanup() {
  local island_exit_status=$?
  # If the final rename failed, restore the existing app without touching its
  # settings. A successfully installed replacement keeps the named backup.
  if [[ "$ISLAND_OLD_MOVED" == true && "$ISLAND_COMMITTED" == false && ! -e "$ISLAND_INSTALL_DESTINATION" ]]; then
    /bin/mv "$ISLAND_BACKUP_PATH" "$ISLAND_INSTALL_DESTINATION" ||
      printf 'Restore the previous app manually from: %s\n' "$ISLAND_BACKUP_PATH" >&2
  fi
  if [[ -n "$ISLAND_STAGE_DIRECTORY" && -d "$ISLAND_STAGE_DIRECTORY" ]]; then
    /bin/rm -rf "$ISLAND_STAGE_DIRECTORY" ||
      printf 'Inspect the remaining staging directory: %s\n' "$ISLAND_STAGE_DIRECTORY" >&2
  fi
  island_release_lock
  return "$island_exit_status"
}
trap island_install_cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

island_check_destination
island_assert_stopped
/bin/mkdir -p "$ISLAND_APPLICATIONS"
island_acquire_lock "$ISLAND_APPLICATIONS/.NotchIsland-install.lock" 'Fixed-path installation'
# A previous installer may have finished between the first check and acquiring the lock.
island_check_destination
island_assert_stopped
ISLAND_STAGE_DIRECTORY="$(/usr/bin/mktemp -d "$ISLAND_APPLICATIONS/.NotchIsland-install.XXXXXX")"
/usr/bin/ditto "$ISLAND_INSTALL_SOURCE" "$ISLAND_STAGE_DIRECTORY/Airlet.app"
island_verify_app "$ISLAND_STAGE_DIRECTORY/Airlet.app"
# Recheck after copying; a launched app or changed destination must not be
# silently replaced. Installation still requires the user to keep it stopped.
island_check_destination
island_assert_stopped
if [[ -e "$ISLAND_INSTALL_DESTINATION" ]]; then
  /bin/mkdir -p "$ISLAND_BACKUP_DIRECTORY"
  ISLAND_BACKUP_PATH="$ISLAND_BACKUP_DIRECTORY/Airlet-$(/bin/date '+%Y%m%d-%H%M%S')-$(/usr/bin/uuidgen).app"
  /bin/mv "$ISLAND_INSTALL_DESTINATION" "$ISLAND_BACKUP_PATH"
  ISLAND_OLD_MOVED=true
fi
/bin/mv "$ISLAND_STAGE_DIRECTORY/Airlet.app" "$ISLAND_INSTALL_DESTINATION"
ISLAND_COMMITTED=true
printf 'Installed: %s\n' "$ISLAND_INSTALL_DESTINATION"
if [[ -n "$ISLAND_BACKUP_PATH" ]]; then printf 'Previous version: %s\n' "$ISLAND_BACKUP_PATH"; fi
printf 'The application was not launched. Open the fixed installed copy for permissions and daily use.\n'
