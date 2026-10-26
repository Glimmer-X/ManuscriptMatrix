#!/bin/bash
# Uses command-line preference overrides and an in-memory repository only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/release/DerivedData/Build/Products/Release/Manuscript Matrix.app"
[[ -d "$APP" ]] || { echo 'Run make release-build first.' >&2; exit 1; }
mkdir -p "$ROOT/Docs/images"
for language in en zh-Hans; do
  "$APP/Contents/MacOS/Manuscript Matrix" \
    --export-demo-screenshot "$ROOT/Docs/images/matrix-$language.png" \
    -app.interfaceLanguage "$language" -app.appearance light \
    -AppleLanguages "($language)" \
    -matrix.semanticDensity detailed -matrix.hideUnusedJournals NO \
    -matrix.hideIncompleteManuscripts NO -matrix.hideAcceptedManuscripts NO
done
