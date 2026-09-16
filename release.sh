#!/bin/bash
# Schnuert ein Weitergabe-Paket: fertige App, Quellcode und LIESMICH in einem ZIP.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
STAGE="/tmp/kritzel-release"
OUT="$HOME/Documents/Claude/Projects/Alltag/Kritzel-$VERSION.zip"

./build.sh >/dev/null

rm -rf "$STAGE" && mkdir -p "$STAGE/Kritzel/Quellcode"
cp -R Kritzel.app "$STAGE/Kritzel/"
cp LIESMICH.txt "$STAGE/Kritzel/"
cp -R Sources tests tools build.sh run-tests.sh Info.plist README.md "$STAGE/Kritzel/Quellcode/"

rm -f "$OUT"
# ditto statt zip: erhaelt die Code-Signatur und die Bundle-Struktur.
ditto -c -k --sequesterRsrc --keepParent "$STAGE/Kritzel" "$OUT"

echo "Paket: $OUT"
echo "Groesse: $(du -h "$OUT" | cut -f1)"
