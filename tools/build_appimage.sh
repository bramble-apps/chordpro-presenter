#!/bin/sh
# Builds the Linux desktop app and packages it as an AppImage:
#   ~/Downloads/Claude Exports/ChordPro_Presenter-x86_64.AppImage
# Runs offline once built (no server, no Wi-Fi). Needs Flutter in
# ~/development/flutter and appimagetool in ~/development/tools.
set -e
cd "$(dirname "$0")/.."
FLUTTER="${FLUTTER:-$HOME/development/flutter/bin/flutter}"
APPIMAGETOOL="${APPIMAGETOOL:-$HOME/development/tools/appimagetool}"
OUT="${OUT:-$HOME/Downloads/Claude Exports}"

[ "$1" = "--no-build" ] || "$FLUTTER" build linux --release

BUNDLE=build/linux/x64/release/bundle
APPDIR=build/appimage/ChordPro_Presenter.AppDir
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
cp -a "$BUNDLE"/. "$APPDIR/usr/bin/"

cp web/icons/Icon-512.png "$APPDIR/chordpro-presenter.png"
cat > "$APPDIR/chordpro-presenter.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=ChordPro Presenter
Comment=Chord charts and bilingual song projection
Exec=bilingual_projector
Icon=chordpro-presenter
Categories=AudioVideo;Office;
StartupWMClass=com.bilingualprojector.bilingual_projector
EOF
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/bilingual_projector" "$@"
EOF
chmod +x "$APPDIR/AppRun"

mkdir -p "$OUT"
# Built beside it, then swapped in (works even while the app is open).
TMP="$OUT/.ChordPro_Presenter-x86_64.AppImage.new"
rm -f "$TMP"
ARCH=x86_64 "$APPIMAGETOOL" --no-appstream "$APPDIR" "$TMP"
mv -f "$TMP" "$OUT/ChordPro_Presenter-x86_64.AppImage"
echo "Built: $OUT/ChordPro_Presenter-x86_64.AppImage"
