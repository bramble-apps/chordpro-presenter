#!/bin/sh
# Installs ChordPro Presenter into the GNOME app grid: icons into the user's
# hicolor theme and a .desktop launcher for the AppImage. The launcher's name
# matches the Electron app's desktopName (package.json), which is the window's
# Wayland app ID, so GNOME shows this icon in the grid, dash and switcher.
#   tools/install_linux_launcher.sh [path/to/ChordPro_Presenter-x86_64.AppImage]
set -e
cd "$(dirname "$0")/.."
APPIMAGE="$(readlink -f "${1:-$HOME/Downloads/Claude Exports/ChordPro_Presenter-x86_64.AppImage}")"
[ -f "$APPIMAGE" ] || { echo "AppImage not found: $APPIMAGE" >&2; exit 1; }
chmod +x "$APPIMAGE"
ID=chordpro-presenter
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

[ -f assets/app_icon/icon.png ] || python3 tools/app_icon.py
for s in 16 24 32 48 64 128 256 512; do
  mkdir -p "$DATA/icons/hicolor/${s}x${s}/apps"
  python3 -c "import sys;from PIL import Image;Image.open(sys.argv[1]).resize((int(sys.argv[2]),)*2,Image.LANCZOS).save(sys.argv[3])" \
    assets/app_icon/icon.png "$s" "$DATA/icons/hicolor/${s}x${s}/apps/$ID.png"
done

# AppImages mount themselves with FUSE 2 (libfuse.so.2), which newer
# Ubuntu releases don't install (26.04's upgrade removed it): without it the
# AppImage unpacks itself and runs from there instead (a little slower to
# start; `sudo apt install libfuse2t64` brings the fast way back).
RUN=""
ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2' || RUN="APPIMAGE_EXTRACT_AND_RUN=1 "

mkdir -p "$DATA/applications"
cat > "$DATA/applications/$ID.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=ChordPro Presenter
Comment=Chord charts and bilingual song projection
Exec=env ${RUN}CHROME_DESKTOP=$ID.desktop "$APPIMAGE" %U
TryExec=$APPIMAGE
Icon=$ID
Terminal=false
Categories=AudioVideo;Music;
Keywords=chordpro;chords;lyrics;songs;projector;worship;
StartupWMClass=$ID
StartupNotify=true
MimeType=x-scheme-handler/chordpropresenter;application/x-chordpro;application/pdf;image/png;image/jpeg;image/gif;image/webp;application/json;application/zip;text/plain;
DESKTOP

# ChordPro files (.cho, .chopro, .chordpro, .crd) as a type of their own,
# so "Open with" offers the app for them.
mkdir -p "$DATA/mime/packages"
cat > "$DATA/mime/packages/$ID.xml" <<'MIME'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-chordpro">
    <comment>ChordPro song</comment>
    <sub-class-of type="text/plain"/>
    <glob pattern="*.cho"/>
    <glob pattern="*.chopro"/>
    <glob pattern="*.chordpro"/>
    <glob pattern="*.crd"/>
  </mime-type>
</mime-info>
MIME
command -v update-mime-database >/dev/null && update-mime-database "$DATA/mime" 2>/dev/null || true

touch "$DATA/icons/hicolor"
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t -f "$DATA/icons/hicolor" 2>/dev/null || true
command -v update-desktop-database >/dev/null && update-desktop-database -q "$DATA/applications" 2>/dev/null || true
echo "Installed $DATA/applications/$ID.desktop -> $APPIMAGE"
