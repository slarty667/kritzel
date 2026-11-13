#!/bin/bash
# Bundles a hand-out package: the built app, the source code and the plain
# text instructions (English and German) in one ZIP.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
STAGE="/tmp/kritzel-release"
OUT="$HOME/Documents/Claude/Projects/Alltag/Kritzel-$VERSION.zip"

./build.sh >/dev/null

rm -rf "$STAGE" && mkdir -p "$STAGE/Kritzel/Source"
cp -R Kritzel.app "$STAGE/Kritzel/"
cp README.txt LIESMICH.txt "$STAGE/Kritzel/"
cp -R Sources Localization tests tools build.sh run-tests.sh Info.plist README.md README.de.md LICENSE \
  "$STAGE/Kritzel/Source/"

rm -f "$OUT"
# ditto rather than zip: it keeps the code signature and the bundle structure.
ditto -c -k --sequesterRsrc --keepParent "$STAGE/Kritzel" "$OUT"

echo "Package: $OUT"
echo "Size: $(du -h "$OUT" | cut -f1)"
