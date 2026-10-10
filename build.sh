#!/bin/bash
# Compila WorkHub.app.
#   ./build.sh            compila (WorkHub.app in questa cartella)
#   ./build.sh install    compila, sostituisce /Applications/WorkHub.app e la avvia
#   ./build.sh dmg        crea WorkHub-<versione>.dmg da dare ad altri: app universale (Apple Silicon + Intel)
#                         compatibile da macOS 12, con le istruzioni per aprirla
# Requisito: Xcode Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

APP="WorkHub.app"
IDENTITY="WorkHub Dev"
MODE="${1:-}"
MIN_MACOS="12.0"
FRAMEWORKS=(-framework Cocoa -framework WebKit -framework UserNotifications -framework ServiceManagement -framework AVFoundation)

# $1 = target (es. arm64-apple-macos12.0) oppure vuoto per questo Mac; $2 = file di uscita
compile() {
  if [[ -n "$1" ]]; then
    swiftc -O -swift-version 5 -target "$1" Sources/*.swift -o "$2" "${FRAMEWORKS[@]}"
  else
    swiftc -O -swift-version 5 Sources/*.swift -o "$2" "${FRAMEWORKS[@]}"
  fi
}

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "$MODE" == "dmg" ]]; then
  # Per altri Mac: un binario per Apple Silicon e uno per Intel, uniti, compatibili da macOS 12.
  PARTS="$(mktemp -d)"
  if compile "arm64-apple-macos$MIN_MACOS" "$PARTS/arm64" && compile "x86_64-apple-macos$MIN_MACOS" "$PARTS/x86_64"; then
    lipo -create -output "$APP/Contents/MacOS/WorkHub" "$PARTS/arm64" "$PARTS/x86_64"
    echo "App universale (Apple Silicon + Intel), macOS $MIN_MACOS o successivo."
  else
    echo "ATTENZIONE: build universale non riuscita. Uso solo questo Mac: funzionerà su Mac"
    echo "con lo stesso processore e la stessa versione di macOS (o più recente)."
    compile "" "$APP/Contents/MacOS/WorkHub"
  fi
  rm -rf "$PARTS"
else
  compile "" "$APP/Contents/MacOS/WorkHub"
fi

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/todos.html Resources/focus.html Resources/settings.html "$APP/Contents/Resources/"

# Suoni del Focus: vanno nella tua Libreria, non dentro l'app (quindi non finiscono nel DMG).
# Quelli già presenti non vengono sovrascritti.
SOUNDS_DIR="$HOME/Library/Application Support/WorkHub/Sounds"
if compgen -G "Sounds/*" > /dev/null; then
  mkdir -p "$SOUNDS_DIR"
  cp -n Sounds/* "$SOUNDS_DIR/" 2>/dev/null || true
  echo "Suoni disponibili in: $SOUNDS_DIR"
fi

# Numero di build = data e ora (visibile in "Informazioni su WorkHub")
BUILD="$(date +%Y%m%d.%H%M)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

# Firma stabile se esiste il certificato (vedi ./setup-signing.sh), altrimenti ad-hoc.
SIGNED_WITH_CERT=0
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
  SIGNED_WITH_CERT=1
  echo "Firmata con \"$IDENTITY\"."
else
  codesign --force --sign - "$APP"
  echo "Firma ad-hoc: macOS richiederà i permessi a ogni build (lancia ./setup-signing.sh per evitarlo)."
fi
echo "WorkHub $VERSION (build $BUILD)"

case "$MODE" in
  install)
    pkill -x WorkHub 2>/dev/null && sleep 1 || true
    rm -rf "/Applications/$APP"
    mv "$APP" /Applications/
    open "/Applications/$APP"
    echo "Installata in /Applications e avviata."
    ;;
  dmg)
    DMG="WorkHub-$VERSION.dmg"
    STAGE="$(mktemp -d)"
    trap 'rm -rf "$STAGE"' EXIT
    ditto "$APP" "$STAGE/$APP"
    ln -s /Applications "$STAGE/Applications"
    cp "Distribuzione/Come aprire WorkHub.txt" "$STAGE/"
    rm -f "$DMG"
    hdiutil create -volname "WorkHub $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    if [[ $SIGNED_WITH_CERT == 1 ]]; then codesign --force --sign "$IDENTITY" "$DMG"; fi
    echo "Installer pronto: $DMG"
    echo "I suoni del Focus non sono inclusi: chi la installa può aggiungere i propri da \"Add sounds…\"."
    ;;
  *)
    echo "Fatto: $APP  (./build.sh install per installarla, ./build.sh dmg per l'installer)"
    ;;
esac
