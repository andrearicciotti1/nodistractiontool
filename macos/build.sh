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
