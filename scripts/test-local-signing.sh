#!/bin/bash
# Static policy and temporary-directory fault injection only; no signing or installation.
set -euo pipefail
ISLAND_TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ISLAND_TEST_ROOT"
bash -n scripts/build.sh scripts/install-local.sh scripts/codesign-local.sh scripts/lib/local-signing.sh scripts/lib/local-lock.sh scripts/lib/codesign-app.sh
printf 'PASS: bash syntax for six signing/install scripts\n'
/usr/bin/plutil -lint boringNotch.xcodeproj/project.pbxproj
source scripts/lib/local-signing.sh
[[ ${#ISLAND_CERT_SHA1} -eq 40 ]]
# Replace only the read-only DR provider; no codesign/security command runs.
island_read_requirement() { printf '%s\n' "$ISLAND_TEST_REQUIREMENT"; }
ISLAND_TEST_REQUIREMENT="$(island_requirement "$ISLAND_APP_ID")"
island_requirement_is_stable unused "$ISLAND_APP_ID"
ISLAND_TEST_REQUIREMENT="$(printf '%s' "$ISLAND_TEST_REQUIREMENT" | /usr/bin/tr '[:upper:]' '[:lower:]')"
island_requirement_is_stable unused "$ISLAND_APP_ID"
ISLAND_TEST_REQUIREMENT="identifier \"$ISLAND_APP_ID\" and anchor H\"$ISLAND_CERT_SHA1\""
island_requirement_is_stable unused "$ISLAND_APP_ID"
ISLAND_TEST_REQUIREMENT='cdhash H"0000000000000000000000000000000000000000"'
if island_requirement_is_stable unused "$ISLAND_APP_ID"; then exit 1; fi
ISLAND_TEST_REQUIREMENT="$(island_requirement "$ISLAND_APP_ID") or true"
if island_requirement_is_stable unused "$ISLAND_APP_ID"; then exit 1; fi
ISLAND_TEST_REQUIREMENT="$(island_requirement 'com.example.other')"
if island_requirement_is_stable unused "$ISLAND_APP_ID"; then exit 1; fi
ISLAND_TEST_REQUIREMENT="identifier \"$ISLAND_APP_ID\" and certificate leaf = H\"0000000000000000000000000000000000000000\""
if island_requirement_is_stable unused "$ISLAND_APP_ID"; then exit 1; fi
printf 'PASS: 7 pure DR policy cases (leaf, lowercase, equivalent anchor; reject CDHash, broad OR, wrong ID, wrong certificate)\n'
python3 - <<'PY'
from pathlib import Path
import plistlib
import re
p=Path('boringNotch.xcodeproj/project.pbxproj').read_text()
assert p.count('CODE_SIGN_IDENTITY = "NotchIsland Local Development";')==4
assert 'CODE_SIGN_IDENTITY[sdk=' not in p
versions=re.findall(r'CURRENT_PROJECT_VERSION = (\d+);', p)
assert len(versions)==4 and len(set(versions))==1 and int(versions[0])>0
assert p.count('PRODUCT_BUNDLE_IDENTIFIER = com.dongfengrui.Airlet;')==2
assert p.count('PRODUCT_BUNDLE_IDENTIFIER = com.dongfengrui.Airlet.XPCHelper;')==2
assert p.count('CODE_SIGN_ENTITLEMENTS = boringNotch/boringNotch.local.entitlements;')==2
assert p.count('ENABLE_HARDENED_RUNTIME = YES;')==2
base=plistlib.loads(Path('boringNotch/boringNotch.entitlements').read_bytes())
local=plistlib.loads(Path('boringNotch/boringNotch.local.entitlements').read_bytes())
assert 'com.apple.security.cs.disable-library-validation' not in base
assert local == dict(base, **{'com.apple.security.cs.disable-library-validation': True})
print('PASS: four dedicated signing configurations, consistent version, and unchanged main/XPC IDs')
print('PASS: local-only library-validation exception is the sole entitlement difference; hardened runtime stays enabled')
print('NOT RUN: signing, installation, trust changes, hardware, or permission checks')
PY
python3 "$ISLAND_TEST_ROOT/scripts/tests/local-signing-safety.py"
