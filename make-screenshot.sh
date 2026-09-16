#!/bin/bash
# Rendert docs/screenshot.png offscreen aus der App selbst, damit der Screenshot
# im README nach UI-Aenderungen reproduzierbar bleibt. Braucht keine
# Bildschirmaufnahme-Rechte.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf /tmp/kritzel-shot && mkdir -p /tmp/kritzel-shot
for f in Sources/*.swift; do
  [ "$(basename "$f")" = "main.swift" ] && continue
  cp "$f" /tmp/kritzel-shot/
done
cp tools/screenshot.swift /tmp/kritzel-shot/main.swift
swiftc -swift-version 5 -target arm64-apple-macos13.0 \
  -o /tmp/kritzel-shot/run /tmp/kritzel-shot/*.swift -framework Cocoa
/tmp/kritzel-shot/run "$(pwd)/docs/screenshot.png"
