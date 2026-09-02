#!/bin/bash
# Pixel level render tests plus interaction tests that drive the real canvas
# with synthesized mouse events in an off-screen window.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf /tmp/kritzel-tests && mkdir -p /tmp/kritzel-tests
for f in Sources/*.swift; do
  [ "$(basename "$f")" = "main.swift" ] && continue
  cp "$f" /tmp/kritzel-tests/
done
cp tests/Tests.swift /tmp/kritzel-tests/main.swift
swiftc -swift-version 5 -target arm64-apple-macos13.0 \
  -o /tmp/kritzel-tests/run /tmp/kritzel-tests/*.swift -framework Cocoa
/tmp/kritzel-tests/run
