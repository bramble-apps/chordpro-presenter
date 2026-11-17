#!/bin/sh
# Builds the Linux desktop app (Electron + the web app + its local server)
# as an AppImage: ~/Downloads/Claude Exports/ChordPro_Presenter-x86_64.AppImage
set -e
cd "$(dirname "$0")/.."
export PATH="$HOME/development/node/bin:$PATH"
FLUTTER="${FLUTTER:-$HOME/development/flutter/bin/flutter}"
OUT="${OUT:-$HOME/Downloads/Claude Exports}"

[ "$1" = "--no-build" ] || "$FLUTTER" build web
# The server's Python packages (casting etc.), bundled with the app.
rm -rf desktop/electron/pylib
mkdir -p desktop/electron/pylib
cp -a tools/.venv/lib/python3*/site-packages/. desktop/electron/pylib/
rm -rf desktop/electron/pylib/pip desktop/electron/pylib/pip-*
find desktop/electron/pylib -name __pycache__ -type d -exec rm -rf {} +

cd desktop/electron
npm run dist
mkdir -p "$OUT"
# Swapped in (works even while the app is open).
cp dist/ChordPro_Presenter-x86_64.AppImage "$OUT/.ChordPro_Presenter-x86_64.AppImage.new"
mv -f "$OUT/.ChordPro_Presenter-x86_64.AppImage.new" "$OUT/ChordPro_Presenter-x86_64.AppImage"
echo "Built: $OUT/ChordPro_Presenter-x86_64.AppImage"
../../tools/install_linux_launcher.sh "$OUT/ChordPro_Presenter-x86_64.AppImage"
