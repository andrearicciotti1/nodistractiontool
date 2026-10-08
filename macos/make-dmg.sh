#!/bin/bash
# Crea il DMG di installazione: build/No-Distraction-<versione>.dmg
# (finestra impaginata con sfondo, icona del volume e collegamento ad Applicazioni).
set -euo pipefail

cd "$(dirname "$0")"
./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG="build/No-Distraction-$VERSION.dmg"

# dmgbuild scrive il layout della finestra senza pilotare Finder.
VENV=".build/dmg-venv"
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet dmgbuild
fi

# Sfondo Retina: le due risoluzioni in un unico TIFF.
tiffutil -cathidpicheck ../branding/dmg-background.png ../branding/dmg-background@2x.png \
  -out build/dmg-background.tiff >/dev/null

rm -f "$DMG"
"$VENV/bin/dmgbuild" -s dmg-settings.py -D app="build/No Distraction.app" \
  -D background=build/dmg-background.tiff -D icon="build/No Distraction.app/Contents/Resources/AppIcon.icns" \
  "No Distraction" "$DMG"
codesign --force --sign - "$DMG"
echo "Creato: $DMG"
