#!/bin/bash
set -euo pipefail
umask 022

# Build the source snapshot that goes into the public repository. GPL-3.0 requires
# publishing the source of whatever binary we hand out; it does not require our
# git history, so the snapshot is a single commit of the current tree with the
# internal validation notes, artwork sources and local signing scripts left out.
#
# Nothing is pushed here: this only writes a local directory.
#
# Usage: bash scripts/make-public-snapshot.sh [output-directory]

ISLAND_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ISLAND_PROJECT_ROOT/scripts/lib/local-signing.sh"

ISLAND_OUTPUT="${1:-$ISLAND_PROJECT_ROOT/dist/public-snapshot}"
[[ $# -le 1 ]] || island_die "Usage: $0 [output-directory]"

# The snapshot comes from HEAD, so an uncommitted wordmark fix (or any other
# uncommitted change) would silently not be in it. Refuse instead.
[[ -z "$(/usr/bin/git -C "$ISLAND_PROJECT_ROOT" status --porcelain)" ]] ||
  island_die 'Commit everything first: the snapshot is taken from HEAD, not from the working tree.'

ISLAND_SHORT_VERSION="$(/usr/bin/git -C "$ISLAND_PROJECT_ROOT" show HEAD:boringNotch.xcodeproj/project.pbxproj |
  /usr/bin/sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' | /usr/bin/sort -u)"
[[ "$(printf '%s\n' "$ISLAND_SHORT_VERSION" | /usr/bin/wc -l | /usr/bin/tr -d ' ')" == 1 ]] ||
  island_die "Inconsistent MARKETING_VERSION in HEAD: $ISLAND_SHORT_VERSION"

/bin/rm -rf "$ISLAND_OUTPUT"
/bin/mkdir -p "$ISLAND_OUTPUT"
/usr/bin/git -C "$ISLAND_PROJECT_ROOT" archive HEAD | /usr/bin/tar -x -C "$ISLAND_OUTPUT"

# Internal-only material: local iteration notes, artwork sources with their
# generation logs, the local signing/release plumbing, upstream CI and configs.
ISLAND_REMOVE=(
  '.devcontainer' '.github' 'artwork' 'crowdin.yml' 'packaging'
  'BRIEF-NOTIFICATIONS-VALIDATION.md' 'COMPACT-HUD-275-VALIDATION.md'
  'HOME-DEFAULT-274-VALIDATION.md' 'HUD25D-VALIDATION.md' 'LOCAL-SIGNING.md'
  'LYRICS-271-VALIDATION.md' 'LYRICS-COLOR-272-VALIDATION.md'
  'MENU-BAR-273-VALIDATION.md' 'NOTIFICATIONS-293-VALIDATION.md'
  'NOTIFICATIONS-294-VALIDATION.md' 'README-Island.md' 'SECURITY.md'
  'SETTINGS-VERIFICATION.md' 'SHU-MOTION-VALIDATION.md'
  'SYSTEM-TOOLS-CAPABILITIES.md' 'TOOLS-NOTIFICATIONS-276-VALIDATION.md'
  'TOOLS-NOTIFICATIONS-277-VALIDATION.md' 'TOOLS-NOTIFICATIONS-278-VALIDATION.md'
  'TOOLS-NOTIFICATIONS-279-VALIDATION.md' 'TOOLS-NOTIFICATIONS-280-VALIDATION.md'
  'VALIDATION-MIGRATION.md' 'VALIDATION.md'
)
for ISLAND_PATH in "${ISLAND_REMOVE[@]}"; do
  /bin/rm -rf "$ISLAND_OUTPUT/$ISLAND_PATH"
done

# scripts/ is an allow list, not a deny list: everything that touches the local
# certificate, the fixed install path or the artwork sources stays private.
ISLAND_PUBLIC_SCRIPTS=(
  'audit-localization.py' 'system-tools-translations.json' 'test-services.sh'
)
/bin/mv "$ISLAND_OUTPUT/scripts" "$ISLAND_OUTPUT/.scripts-full"
/bin/mkdir -p "$ISLAND_OUTPUT/scripts"
for ISLAND_SCRIPT in "${ISLAND_PUBLIC_SCRIPTS[@]}"; do
  [[ -e "$ISLAND_OUTPUT/.scripts-full/$ISLAND_SCRIPT" ]] ||
    island_die "Missing script expected in the public snapshot: $ISLAND_SCRIPT"
  /bin/cp -R "$ISLAND_OUTPUT/.scripts-full/$ISLAND_SCRIPT" "$ISLAND_OUTPUT/scripts/"
done
/bin/rm -rf "$ISLAND_OUTPUT/.scripts-full"

/bin/cp "$ISLAND_PROJECT_ROOT/packaging/public-README.md" "$ISLAND_OUTPUT/README.md"
# The Chinese README links to the English one, so it has to travel with it.
/bin/cp "$ISLAND_PROJECT_ROOT/packaging/public-README.en.md" "$ISLAND_OUTPUT/README.en.md"
/bin/cp "$ISLAND_PROJECT_ROOT/packaging/public-CHANGELOG.md" "$ISLAND_OUTPUT/CHANGELOG.md"

# Nobody outside this machine has the local certificate, so the published project
# signs to run locally instead. scripts/build.sh overrides the identity on the
# command line anyway, which is why this only matters for the public copy.
/usr/bin/sed -i '' 's/CODE_SIGN_IDENTITY = "NotchIsland Local Development";/CODE_SIGN_IDENTITY = "-";/g' \
  "$ISLAND_OUTPUT/boringNotch.xcodeproj/project.pbxproj"

# The public README points at an icon that must survive the artwork removal.
[[ -f "$ISLAND_OUTPUT/boringNotch/Assets.xcassets/AppIcon.appiconset/tomato-1024.png" ]] ||
  island_die 'The app icon referenced by the public README is missing from the snapshot.'

# Guard against publishing local machine details. The product bundle id
# (com.dongfengrui.Airlet) is deliberately not in this list.
ISLAND_FORBIDDEN=(
  '/Users/dongfengrui' "$ISLAND_CERT_SHA1" '小红书' 'xiaohongshu' '.codex/'
  'NotchIsland Local Development'
)
ISLAND_LEAKS=0
for ISLAND_PATTERN in "${ISLAND_FORBIDDEN[@]}"; do
  if /usr/bin/grep -rIl -- "$ISLAND_PATTERN" "$ISLAND_OUTPUT" >/tmp/island-snapshot-hits 2>/dev/null; then
    printf 'Forbidden string %s appears in:\n' "$ISLAND_PATTERN"
    /usr/bin/sed "s|^$ISLAND_OUTPUT/||" /tmp/island-snapshot-hits
    ISLAND_LEAKS=$((ISLAND_LEAKS + 1))
  fi
done
/bin/rm -f /tmp/island-snapshot-hits
[[ "$ISLAND_LEAKS" -eq 0 ]] || island_die "$ISLAND_LEAKS forbidden pattern(s) found; the snapshot was left in place for inspection."

/usr/bin/git -C "$ISLAND_OUTPUT" init -q -b main
/usr/bin/git -C "$ISLAND_OUTPUT" add -A
/usr/bin/git -C "$ISLAND_OUTPUT" -c commit.gpgsign=false commit -q -m "Airlet v$ISLAND_SHORT_VERSION

基于 boring.notch v2.7.3（GPL-3.0，上游提交 16b0f11f51c79d42e27c10d77fd9e53c11410fdb）的定制版本。
本提交是对外发布版本对应的完整源码快照，用于满足 GPL-3.0 的源码提供义务。"
/usr/bin/git -C "$ISLAND_OUTPUT" tag "v$ISLAND_SHORT_VERSION"

printf 'Snapshot: %s\n' "$ISLAND_OUTPUT"
printf 'Version:  v%s\n' "$ISLAND_SHORT_VERSION"
printf 'Files:    %s\n' "$(/usr/bin/git -C "$ISLAND_OUTPUT" ls-files | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
printf 'Nothing was pushed. Review it, then run scripts/publish-release.sh.\n'
