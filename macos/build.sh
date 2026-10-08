#!/bin/bash
# Compila No Distraction e crea build/No Distraction.app.
#   ./build.sh            compila
#   ./build.sh --install  compila e copia in /Applications
set -euo pipefail

cd "$(dirname "$0")"
APP="build/No Distraction.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/NoDistraction"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NoDistraction"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Lo stesso suono dell'estensione Chrome.
cp ../chrome-extension/sounds/error.mp3 "$APP/Contents/Resources/error.mp3"

# Icona: dalla PNG 1024 di branding/ a AppIcon.icns.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size ../branding/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) ../branding/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Firma ad hoc: basta per l'uso locale. macOS chiede di nuovo i permessi
# (webcam, Accessibilità) dopo ogni ricompilazione.
codesign --force --deep --sign - "$APP"
echo "Creata: $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x NoDistraction 2>/dev/null || true
  rm -rf "/Applications/No Distraction.app"
  cp -R "$APP" /Applications/
  echo "Installata in /Applications"
fi
