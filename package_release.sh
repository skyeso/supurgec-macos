#!/bin/bash
# Başka Mac'lere kolayca indirip kurmak için DMG ve ZIP dağıtım paketlerini üretir.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d "build/Süpürgeç.app" ]; then
  ./build.sh
fi

VERSION="v0.2-alpha"
ZIP_OUT="build/Supurgec-${VERSION}-macOS.zip"
DMG_OUT="build/Supurgec-${VERSION}-macOS.dmg"
STAGE="build/dmg_stage"

rm -f "$ZIP_OUT" "$DMG_OUT"
ditto -c -k --keepParent "build/Süpürgeç.app" "$ZIP_OUT"

rm -rf "$STAGE"
mkdir -p "$STAGE"
touch "$STAGE/.metadata_never_index"
ditto "build/Süpürgeç.app" "$STAGE/Süpürgeç.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Süpürgeç" -srcfolder "$STAGE" -ov -format UDZO "$DMG_OUT" >/dev/null
rm -rf "$STAGE"

# hdiutil geçici bağlama sırasında /Volumes/Süpürgeç/Süpürgeç.app kaydını LaunchServices'e ekler;
# Spotlight'ta çift Süpürgeç görünmemesi için /Applications dışındaki tüm kopyaları kayıttan düşür!
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREG" ]; then
  python3 - "$LSREG" <<'PY' || true
import re, subprocess, sys, unicodedata
lsreg = sys.argv[1]
out = subprocess.run([lsreg, "-dump"], capture_output=True, text=True).stdout
for line in out.splitlines():
    m = re.match(r"^\s*path:\s+(.+?\.app)\s+\(0x[0-9a-fA-F]+\)\s*$", line)
    if not m:
        continue
    raw_path = m.group(1)
    norm = unicodedata.normalize("NFC", raw_path)
    if ("Süpürgeç.app" in norm or "Supurgec.app" in norm) and norm != "/Applications/Süpürgeç.app":
        subprocess.run([lsreg, "-u", raw_path], capture_output=True)
PY
fi

echo "Hazır:"
echo "  ZIP: $(pwd)/$ZIP_OUT"
echo "  DMG: $(pwd)/$DMG_OUT"
