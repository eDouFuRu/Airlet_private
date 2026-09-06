#!/bin/bash
# The caller holds the shared build/sign lock and has sourced local-signing.sh.
island_codesign_app() {
  local island_sign_app="$1" island_resigned_child=false
  # Validate both bundles before any identity lookup, certificate extraction or signing.
  island_require_app_layout "$island_sign_app"
  island_require_bundle_id "$island_sign_app" "$ISLAND_APP_ID"
  island_require_bundle_id "$island_sign_app/$ISLAND_XPC_RELATIVE_PATH" "$ISLAND_XPC_ID"
  island_require_clean_signing_input "$island_sign_app"
  island_require_signing_identity
  # xcodebuild must have used the exact dedicated certificate, never ad-hoc signing.
  island_require_certificate "$island_sign_app"
  island_require_certificate "$island_sign_app/$ISLAND_XPC_RELATIVE_PATH"
  if ! island_requirement_is_stable "$island_sign_app/$ISLAND_XPC_RELATIVE_PATH" "$ISLAND_XPC_ID"; then
    /usr/bin/codesign --force --sign "$ISLAND_CERT_SHA1" --timestamp=none \
      --preserve-metadata=identifier,entitlements,flags,runtime,launch-constraints,library-constraints \
      --requirements "=designated => $(island_requirement "$ISLAND_XPC_ID")" \
      "$island_sign_app/$ISLAND_XPC_RELATIVE_PATH"
    island_resigned_child=true
  fi
  if [[ "$island_resigned_child" == true ]] || ! island_requirement_is_stable "$island_sign_app" "$ISLAND_APP_ID"; then
    /usr/bin/codesign --force --sign "$ISLAND_CERT_SHA1" --timestamp=none \
      --preserve-metadata=identifier,entitlements,flags,runtime,launch-constraints,library-constraints \
      --requirements "=designated => $(island_requirement "$ISLAND_APP_ID")" "$island_sign_app"
  fi
  island_verify_app "$island_sign_app"
  printf 'Verified stable signing: %s\nCertificate SHA-1: %s\n' "$island_sign_app" "$ISLAND_CERT_SHA1"
}
