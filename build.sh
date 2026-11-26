#!/bin/bash
# Süpürgeç.app paketini oluşturur: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

EXEC=Supurgec
OUT="build/Süpürgeç.app"

swift build --disable-sandbox -c release

if [ ! -f Resources/AppIcon.icns ]; then
  swift scripts/make_icon.swift Resources/AppIcon.icns
fi

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp ".build/release/$EXEC" "$OUT/Contents/MacOS/$EXEC"
cp Resources/Info.plist "$OUT/Contents/Info.plist"
cp Resources/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$OUT"

echo "Hazır: $(pwd)/$OUT"
