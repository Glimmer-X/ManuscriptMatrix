#!/bin/bash
# Requires existing Keychain credentials. No credentials are written to this tree.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${MM_SIGN_IDENTITY:?Set MM_SIGN_IDENTITY to an existing Developer ID Application identity}"
: "${MM_NOTARY_PROFILE:?Set MM_NOTARY_PROFILE to an existing notarytool Keychain profile}"
cd "$ROOT"
if [[ "${1:-}" != "--skip-build" ]]; then bash scripts/build-release.sh; fi
BUILD="$ROOT/build/release"
APP="$BUILD/DerivedData/Build/Products/Release/Manuscript Matrix.app"
[[ -d "$APP" ]] || { echo 'Release app not found.' >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p dist
WORK=$(mktemp -d "$BUILD/notarize.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
codesign --force --sign "$MM_SIGN_IDENTITY" --options runtime --timestamp \
  "$APP/Contents/Helpers/manuscript-matrix-agent"
codesign --force --sign "$MM_SIGN_IDENTITY" --options runtime --timestamp "$APP"
codesign --verify --strict --deep "$APP"
ditto -c -k --keepParent "$APP" "$WORK/submission.zip"
xcrun notarytool submit "$WORK/submission.zip" --keychain-profile "$MM_NOTARY_PROFILE" \
  --wait --timeout 20m --output-format json > "$WORK/notary.json"
python3 - "$WORK/notary.json" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization did not succeed: '+str(result.get('id')))
print('Notarization accepted.')
PY
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
ARCHIVE="dist/Manuscript-Matrix-$VERSION-universal.zip"
ditto -c -k --keepParent "$APP" "$ARCHIVE"
mkdir "$WORK/unpacked"
ditto -x -k "$ARCHIVE" "$WORK/unpacked"
codesign --verify --strict --deep "$WORK/unpacked/Manuscript Matrix.app"
xcrun stapler validate "$WORK/unpacked/Manuscript Matrix.app"
python3 scripts/audit-release.py "$WORK/unpacked/Manuscript Matrix.app"
(cd dist && shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256")
printf 'Verified release: %s\n' "$ARCHIVE"
