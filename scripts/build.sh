#!/bin/bash
set -euo pipefail
umask 077

# Build the customized app locally. This does not install or launch either app.
ISLAND_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ISLAND_PROJECT_ROOT/scripts/lib/local-signing.sh"
source "$ISLAND_PROJECT_ROOT/scripts/lib/local-lock.sh"
source "$ISLAND_PROJECT_ROOT/scripts/lib/codesign-app.sh"
ISLAND_CONFIGURATION="${1:-Debug}"
case "$ISLAND_CONFIGURATION" in
  Debug|Release) ;;
  *) echo "Usage: $0 [Debug|Release]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || island_die "Usage: $0 [Debug|Release]"
ISLAND_REQUESTED_IDENTITY="${ISLAND_SIGN_IDENTITY:-$ISLAND_CERT_SHA1}"
case "$ISLAND_REQUESTED_IDENTITY" in
  "$ISLAND_CERT_SHA1"|"$ISLAND_CERT_NAME") ISLAND_REQUESTED_IDENTITY="$ISLAND_CERT_SHA1"; island_require_signing_identity ;;
  -) [[ "$ISLAND_CONFIGURATION" == Debug ]] || island_die 'Ad-hoc signing is an explicit Debug-only fallback.' ;;
  *) island_die 'Only the dedicated local certificate or explicit ISLAND_SIGN_IDENTITY=- is supported.' ;;
esac
ISLAND_REQUESTED_BUILD_NUMBER="${ISLAND_BUILD_NUMBER:-308}"
[[ "$ISLAND_REQUESTED_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || island_die 'ISLAND_BUILD_NUMBER must be a positive decimal integer.'
ISLAND_BUILD_JOBS="${ISLAND_BUILD_JOBS:-1}"
[[ "$ISLAND_BUILD_JOBS" =~ ^[1-9][0-9]*$ ]] || island_die 'ISLAND_BUILD_JOBS must be a positive decimal integer.'
printf 'Signing identity: %s\n' "$ISLAND_REQUESTED_IDENTITY"
island_trap_build_lock_cleanup
island_acquire_build_lock "$ISLAND_PROJECT_ROOT"

xcodebuild \
  -jobs "$ISLAND_BUILD_JOBS" \
  -project "$ISLAND_PROJECT_ROOT/boringNotch.xcodeproj" \
  -scheme NotchIslandNext \
  -configuration "$ISLAND_CONFIGURATION" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$ISLAND_PROJECT_ROOT/build" \
  -clonedSourcePackagesDirPath "$ISLAND_PROJECT_ROOT/build/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  "CODE_SIGN_IDENTITY=$ISLAND_REQUESTED_IDENTITY" \
  OTHER_CODE_SIGN_FLAGS=--timestamp=none \
  "CURRENT_PROJECT_VERSION=$ISLAND_REQUESTED_BUILD_NUMBER" \
  build

ISLAND_BUILT_APP="$ISLAND_PROJECT_ROOT/build/Build/Products/$ISLAND_CONFIGURATION/Airlet.app"
if [[ "$ISLAND_REQUESTED_IDENTITY" == - ]]; then
  /usr/bin/codesign --verify --deep --strict "$ISLAND_BUILT_APP"
  printf 'Built with explicit ad-hoc signing; fixed-path installer will reject this debug artifact.\n'
else
  # Keep the lock across xcodebuild and post-signing; no nested lock/process.
  island_codesign_app "$ISLAND_BUILT_APP"
fi
# Xcode registers build products with Launch Services. Keep only the fixed-path
# installation visible as Airlet in Launchpad and application pickers.
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u "$ISLAND_BUILT_APP" >/dev/null 2>&1 || true
printf 'Built: %s\n' "$ISLAND_BUILT_APP"
