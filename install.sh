#!/bin/bash
# Süpürgeç'i derler ve doğrudan /Applications (Uygulamalar) klasörüne kurar.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

echo "Uygulamalar klasörüne kopyalanıyor..."
killall Supurgec 2>/dev/null || true
rm -rf "/Applications/Süpürgeç.app"
ditto "build/Süpürgeç.app" "/Applications/Süpürgeç.app"
xattr -cr "/Applications/Süpürgeç.app" 2>/dev/null || true

echo "Kurulum tamamlandı: /Applications/Süpürgeç.app"
open "/Applications/Süpürgeç.app"
