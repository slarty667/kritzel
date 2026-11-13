#!/bin/bash
# Renders docs/screenshot.png off-screen from the app itself, so the README
# screenshot stays reproducible after UI changes. Needs no screen recording
# permission.
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
