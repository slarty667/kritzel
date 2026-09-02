#!/bin/bash
# Builds Kritzel.app from source. No Xcode needed, Command Line Tools are enough.
set -euo pipefail
cd "$(dirname "$0")"

APP="Kritzel.app"
NAME="Kritzel"

echo "==> Icon"
swiftc -swift-version 5 -O -o /tmp/kritzel-makeicon tools/makeicon.swift -framework Cocoa
/tmp/kritzel-makeicon /tmp/kritzel-icon.png >/dev/null
rm -rf /tmp/Kritzel.iconset && mkdir -p /tmp/Kritzel.iconset
for size in 16 32 128 256 512; do
  sips -z $size $size /tmp/kritzel-icon.png --out "/tmp/Kritzel.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double /tmp/kritzel-icon.png --out "/tmp/Kritzel.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns /tmp/Kritzel.iconset -o AppIcon.icns

echo "==> Compile"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -target arm64-apple-macos13.0 \
  -o "$APP/Contents/MacOS/$NAME" Sources/*.swift -framework Cocoa

echo "==> Bundle"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "==> Fertig: $(pwd)/$APP"
