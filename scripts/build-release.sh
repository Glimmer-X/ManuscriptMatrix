#!/bin/bash
# Build only task-owned release outputs; never launch the personal board.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/release"
APP="$BUILD/DerivedData/Build/Products/Release/Manuscript Matrix.app"
mkdir -p "$BUILD"
cd "$ROOT"
xcodegen generate
xcodebuild -quiet -project ManuscriptMatrix.xcodeproj -scheme ManuscriptMatrix \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD/DerivedData" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO \
  GCC_GENERATE_DEBUGGING_SYMBOLS=NO SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
  'OTHER_SWIFT_FLAGS=$(inherited) -file-prefix-map $(SRCROOT)=/src/ManuscriptMatrix -debug-prefix-map $(SRCROOT)=/src/ManuscriptMatrix' \
  build > "$BUILD/build.log" 2>&1 || { tail -80 "$BUILD/build.log" >&2; exit 1; }
# Use the same deployment target and Release configuration for the MCP bridge.
xcodebuild -quiet -project ManuscriptMatrix.xcodeproj -scheme ManuscriptMatrixAgent \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD/DerivedData" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  GCC_GENERATE_DEBUGGING_SYMBOLS=NO SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
  'OTHER_SWIFT_FLAGS=$(inherited) -file-prefix-map $(SRCROOT)=/src/ManuscriptMatrix -debug-prefix-map $(SRCROOT)=/src/ManuscriptMatrix' \
  build > "$BUILD/agent.log" 2>&1 || { tail -80 "$BUILD/agent.log" >&2; exit 1; }
mkdir -p "$APP/Contents/Helpers"
cp "$BUILD/DerivedData/Build/Products/Release/manuscript-matrix-agent" \
  "$APP/Contents/Helpers/manuscript-matrix-agent"
strip -S "$APP/Contents/Helpers/manuscript-matrix-agent"
cp LICENSE "$APP/Contents/Resources/LICENSE"
python3 scripts/audit-release.py "$APP"
printf 'Built universal app and MCP helper: %s\n' "$APP"
