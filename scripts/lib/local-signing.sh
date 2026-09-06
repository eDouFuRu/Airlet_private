#!/bin/bash
# Shared policy. Sourcing this file does not build, sign, install, or change trust.
readonly ISLAND_CERT_NAME='NotchIsland Local Development'
readonly ISLAND_CERT_SHA1='0A93291611F302DBECD76D2ACEC9DEF86D1F3DB2'
readonly ISLAND_APP_ID='com.dongfengrui.NotchIsland'
readonly ISLAND_XPC_ID='com.dongfengrui.NotchIsland.XPCHelper'
readonly ISLAND_XPC_RELATIVE_PATH='Contents/XPCServices/NotchIslandXPCHelper.xpc'

island_die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

island_require_app_layout() {
  local island_component
  for island_component in "$1" "$1/Contents" "$1/Contents/MacOS" "$1/Contents/XPCServices" \
    "$1/$ISLAND_XPC_RELATIVE_PATH" "$1/$ISLAND_XPC_RELATIVE_PATH/Contents" \
    "$1/$ISLAND_XPC_RELATIVE_PATH/Contents/MacOS"; do
    [[ -d "$island_component" && ! -L "$island_component" ]] ||
      island_die "Expected a real bundle directory, not a symlink: $island_component"
  done
}

island_signature_is_intact() {
  /usr/bin/codesign --verify --deep --strict "$1"
}

island_require_clean_signing_input() {
  local island_stale_file
  island_stale_file="$(/usr/bin/find "$1" -name '*.cstemp' -print -quit)" ||
    island_die 'Could not inspect signing input; no signing was attempted.'
  [[ -z "$island_stale_file" ]] || island_die \
    "Stale signing temporary file: $island_stale_file. Stop all build/sign processes, then clean/rebuild the standalone XPC and app products. No deletion or signature repair was attempted."
  island_signature_is_intact "$1" || island_die \
    "Invalid existing signature: $1. Stop all build/sign processes, then clean/rebuild the standalone XPC and app products (including any .cstemp residue). No signature repair was attempted."
}

island_require_bundle_id() {
  local island_actual_id
  island_actual_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$1/Contents/Info.plist")" || return 1
  [[ "$island_actual_id" == "$2" ]] || island_die "Unexpected bundle ID at $1: $island_actual_id (expected $2)."
}

island_requirement() {
  printf 'identifier "%s" and certificate leaf = H"%s"' "$1" "$ISLAND_CERT_SHA1"
}

island_read_requirement() {
  /usr/bin/codesign --display --requirements - "$1" 2>/dev/null |
    /usr/bin/sed -n 's/^designated => //p'
}

island_requirement_is_stable() {
  local island_actual island_leaf_requirement island_anchor_requirement
  # codesign prints certificate hashes in lowercase. Normalize the comparison,
  # including our known identifiers, without accepting any additional clauses.
  island_actual="$(island_read_requirement "$1" | /usr/bin/tr '[:upper:]' '[:lower:]')" || return 1
  island_leaf_requirement="$(island_requirement "$2" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  island_anchor_requirement="$(printf 'identifier "%s" and anchor H"%s"' "$2" "$ISLAND_CERT_SHA1" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  [[ "$island_actual" == "$island_leaf_requirement" || "$island_actual" == "$island_anchor_requirement" ]]
}

island_require_certificate() (
  set -euo pipefail
  local island_certificate_dir island_actual_sha
  island_certificate_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/notchisland-certificate.XXXXXX")"
  trap '/bin/rm -rf "$island_certificate_dir"' EXIT
  # Only public DER certificates are extracted. No keychain private key export.
  /usr/bin/codesign --display "--extract-certificates=$island_certificate_dir/cert-" "$1" >/dev/null 2>&1 ||
    island_die "Cannot read the signing certificate: $1"
  [[ -f "$island_certificate_dir/cert-0" ]] || island_die "Ad-hoc or unsigned application: $1"
  island_actual_sha="$(/usr/bin/shasum -a 1 "$island_certificate_dir/cert-0" | /usr/bin/awk '{print toupper($1)}')"
  [[ "$island_actual_sha" == "$ISLAND_CERT_SHA1" ]] || island_die "Wrong signing certificate for $1: $island_actual_sha"
)

island_verify_component() {
  [[ -d "$1" && ! -L "$1" ]] || island_die "Expected a real signed bundle: $1"
  island_require_bundle_id "$1" "$2"
  island_require_certificate "$1"
  island_requirement_is_stable "$1" "$2" || island_die "Unstable designated requirement: $1"
  /usr/bin/codesign --verify --strict --test-requirement "=$(island_requirement "$2")" "$1"
}

island_verify_app() {
  island_require_app_layout "$1"
  island_verify_component "$1/$ISLAND_XPC_RELATIVE_PATH" "$ISLAND_XPC_ID"
  island_verify_component "$1" "$ISLAND_APP_ID"
  /usr/bin/codesign --verify --deep --strict "$1"
}

island_require_signing_identity() {
  local island_identities
  island_identities="$(/usr/bin/security find-identity -v -p codesigning)" ||
    island_die 'Cannot query signing identities in the current keychain search list.'
  [[ "$island_identities" == *"$ISLAND_CERT_SHA1"* ]] || island_die \
    "The dedicated certificate is not a valid code-signing identity. Resolve its current-user codeSign trust/key access first: $ISLAND_CERT_NAME ($ISLAND_CERT_SHA1). No fallback or trust change was attempted."
}
