#!/bin/bash
# Builds FreeAppStore.app from the Swift sources in Sources/.
set -euo pipefail
cd "$(dirname "$0")"

APP="FreeAppStore.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/module-cache .build/tmp

# Keep compiler intermediates local so builds also work in restricted sandboxes.
export TMPDIR="$PWD/.build/tmp"

SOURCES=(
  Sources/Models.swift
  Sources/IAPCache.swift
  Sources/StoreAPI.swift
  Sources/StoreViewModel.swift
  Sources/Views.swift
  Sources/AppMain.swift
)

# Compiles the app for a single architecture.
compile_arch() {
  local target="$1" output="$2"
  swiftc \
    -O \
    -swift-version 5 \
    -module-cache-path "$PWD/.build/module-cache" \
    -target "$target" \
    -framework SwiftUI \
    -framework AppKit \
    "${SOURCES[@]}" \
    -o "$output"
}

if [ "${UNIVERSAL:-0}" = "1" ]; then
  echo "==> Compiling FreeAppStore (universal: arm64 + x86_64)"
  compile_arch arm64-apple-macos14.0   "$APP/Contents/MacOS/FreeAppStore-arm64"
  compile_arch x86_64-apple-macos14.0  "$APP/Contents/MacOS/FreeAppStore-x86_64"
  lipo -create \
    "$APP/Contents/MacOS/FreeAppStore-arm64" \
    "$APP/Contents/MacOS/FreeAppStore-x86_64" \
    -output "$APP/Contents/MacOS/FreeAppStore"
  rm -f "$APP/Contents/MacOS/FreeAppStore-arm64" "$APP/Contents/MacOS/FreeAppStore-x86_64"
else
  echo "==> Compiling FreeAppStore (arm64)"
  compile_arch arm64-apple-macos14.0 "$APP/Contents/MacOS/FreeAppStore"
fi

cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ -f Resources/free-mac-index.json ]; then
  cp Resources/free-mac-index.json "$APP/Contents/Resources/free-mac-index.json"
  echo "==> Bundled catalog index ($(du -h Resources/free-mac-index.json | cut -f1))"
else
  echo "==> NOTE: Resources/free-mac-index.json missing — 'All Free Apps' will ask you to run:"
  echo "        python3 Tools/build_index.py"
fi

echo "==> Generating icon"
ICON_PNG="Resources/icon_1024.png"
ICONSET="/tmp/freeappstore.iconset"
if swiftc -O -module-cache-path "$PWD/.build/module-cache" Tools/make_icon.swift -o .build/make_icon \
   && ./.build/make_icon "$ICON_PNG"; then
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  sips -z 16 16     "$ICON_PNG" --out "$ICONSET/icon_16x16.png"      >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_32x32.png"      >/dev/null
  sips -z 64 64     "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
  sips -z 128 128   "$ICON_PNG" --out "$ICONSET/icon_128x128.png"    >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_256x256.png"    >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_512x512.png"    >/dev/null
  sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  if iconutil -c icns "$ICONSET" -o /tmp/freeappstore.icns; then
    cp /tmp/freeappstore.icns "$APP/Contents/Resources/App.icns"
    echo "    icon ok"
  else
    echo "    icon failed (continuing without one)" >&2
  fi
else
  echo "    icon generation failed (continuing without one)" >&2
fi

echo "==> Ad-hoc signing"
codesign --force --sign - "$APP"

echo "==> Done: $APP"
echo "    Run with:  open \"$APP\""
