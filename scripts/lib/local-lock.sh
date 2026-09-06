#!/bin/bash
# One process owns the directory. Existing/stale locks are never stolen automatically.
ISLAND_LOCK_DIRECTORY=''
ISLAND_LOCK_OWNER=''
ISLAND_BUILD_INTERRUPTION=''

island_acquire_lock() {
  [[ -z "$ISLAND_LOCK_DIRECTORY" ]] || island_die 'This process already holds an operation lock.'
  local island_lock_path="$1" island_lock_label="$2" island_existing_owner='unknown'
  [[ ! -L "$island_lock_path" ]] || island_die "Refusing a symlink operation lock: $island_lock_path"
  local island_owner="$$:$(/usr/bin/uuidgen)"
  if ! /bin/mkdir -m 700 "$island_lock_path" 2>/dev/null; then
    if [[ -f "$island_lock_path/owner" && ! -L "$island_lock_path/owner" ]]; then
      IFS= read -r island_existing_owner < "$island_lock_path/owner" || true
    fi
    island_die "$island_lock_label is locked: $island_lock_path (owner $island_existing_owner). Wait for that process. If it was interrupted, first confirm no build/sign/install process remains, then remove only this stale lock directory; no automatic takeover was attempted."
  fi
  ISLAND_LOCK_DIRECTORY="$island_lock_path"
  ISLAND_LOCK_OWNER="$island_owner"
  printf '%s\n' "$ISLAND_LOCK_OWNER" > "$ISLAND_LOCK_DIRECTORY/owner"
}

island_release_lock() {
  [[ -n "$ISLAND_LOCK_DIRECTORY" ]] || return 0
  local island_actual_owner=''
  if [[ -d "$ISLAND_LOCK_DIRECTORY" && ! -L "$ISLAND_LOCK_DIRECTORY" &&
        -f "$ISLAND_LOCK_DIRECTORY/owner" && ! -L "$ISLAND_LOCK_DIRECTORY/owner" ]]; then
    IFS= read -r island_actual_owner < "$ISLAND_LOCK_DIRECTORY/owner" || true
    if [[ "$island_actual_owner" == "$ISLAND_LOCK_OWNER" ]]; then
      if /bin/rm "$ISLAND_LOCK_DIRECTORY/owner"; then
        /bin/rmdir "$ISLAND_LOCK_DIRECTORY" ||
          printf 'Operation ended; inspect the unexpected contents in lock directory: %s\n' "$ISLAND_LOCK_DIRECTORY" >&2
      else
        printf 'Operation ended; could not release owned lock: %s\n' "$ISLAND_LOCK_DIRECTORY" >&2
      fi
    fi
  fi
  ISLAND_LOCK_DIRECTORY=''
  ISLAND_LOCK_OWNER=''
}

island_lock_cleanup() {
  local island_exit_status=$?
  island_release_lock
  return "$island_exit_status"
}

island_trap_lock_cleanup() {
  trap island_lock_cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

island_build_interrupted() {
  ISLAND_BUILD_INTERRUPTION="signal=$1"
  exit "$2"
}

island_preserve_interrupted_lock() {
  [[ -n "$ISLAND_LOCK_DIRECTORY" ]] || return 0
  local island_actual_owner=''
  if [[ -d "$ISLAND_LOCK_DIRECTORY" && ! -L "$ISLAND_LOCK_DIRECTORY" &&
        -f "$ISLAND_LOCK_DIRECTORY/owner" && ! -L "$ISLAND_LOCK_DIRECTORY/owner" ]]; then
    IFS= read -r island_actual_owner < "$ISLAND_LOCK_DIRECTORY/owner" || true
    if [[ "$island_actual_owner" == "$ISLAND_LOCK_OWNER" ]]; then
      # Never follow or overwrite an unexpected marker. The lock itself stays held.
      (set -o noclobber
       printf 'owner=%s\ninterrupted: %s\ntime=%s\n' "$ISLAND_LOCK_OWNER" "$1" "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" \
         > "$ISLAND_LOCK_DIRECTORY/interrupted") ||
        printf 'Could not create interruption marker; the operation lock remains in place.\n' >&2
      printf 'Build/sign did not complete (%s). Lock retained: %s. Confirm the interrupted build and its signing operations have ended before manually clearing this lock; no process was signalled or lock taken over.\n' \
        "$1" "$ISLAND_LOCK_DIRECTORY" >&2
    fi
  fi
}

island_build_lock_cleanup() {
  local island_exit_status=$?
  if [[ "$island_exit_status" -eq 0 && -z "$ISLAND_BUILD_INTERRUPTION" ]]; then
    island_release_lock
  else
    island_preserve_interrupted_lock "${ISLAND_BUILD_INTERRUPTION:-nonzero exit}; exit-status=$island_exit_status"
  fi
  return "$island_exit_status"
}

island_trap_build_lock_cleanup() {
  ISLAND_BUILD_INTERRUPTION=''
  trap island_build_lock_cleanup EXIT
  trap 'island_build_interrupted HUP 129' HUP
  trap 'island_build_interrupted INT 130' INT
  trap 'island_build_interrupted TERM 143' TERM
}

island_acquire_build_lock() {
  local island_build_directory="$1/build"
  [[ ! -L "$island_build_directory" ]] || island_die "Refusing a symlink build directory: $island_build_directory"
  /bin/mkdir -p "$island_build_directory"
  island_acquire_lock "$island_build_directory/.NotchIsland-build.lock" 'Build/sign operation'
}
