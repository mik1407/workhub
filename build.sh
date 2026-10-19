#!/bin/bash
# Builds WorkHub.app.
#   ./build.sh            builds (WorkHub.app in this folder)
#   ./build.sh install    builds, replaces /Applications/WorkHub.app and launches it
#   ./build.sh dmg        creates WorkHub-<version>.dmg to give to others: universal app (Apple Silicon + Intel)
#                         compatible with macOS 12 and later, with instructions for opening it
#   ./build.sh test       runs the logic tests (Tests/ folder) without building the app
# Requirement: Xcode Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

APP="WorkHub.app"
IDENTITY="WorkHub Dev"
MODE="${1:-}"
MIN_MACOS="12.0"
FRAMEWORKS=(-framework Cocoa -framework WebKit -framework UserNotifications -framework ServiceManagement -framework AVFoundation -framework Network)
# This Mac, with the minimum version from Info.plist: the local build behaves like the distributed one
HOST_TARGET="$(uname -m)-apple-macos$MIN_MACOS"

# $1 = target (e.g. arm64-apple-macos12.0) or empty for this Mac; $2 = output file
compile() {
  if [[ -n "$1" ]]; then
    swiftc -O -swift-version 5 -target "$1" Sources/*.swift -o "$2" "${FRAMEWORKS[@]}"
  else
    swiftc -O -swift-version 5 Sources/*.swift -o "$2" "${FRAMEWORKS[@]}"
  fi
}

if [[ "$MODE" == "test" ]]; then
  # All sources except main.swift (which launches the app) plus the tests, in a temporary folder.
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  SOURCES=()
  for f in Sources/*.swift; do [[ "$(basename "$f")" == "main.swift" ]] || SOURCES+=("$f"); done
  swiftc -swift-version 5 -target "$HOST_TARGET" "${SOURCES[@]}" Tests/*.swift -o "$TMP/tests" "${FRAMEWORKS[@]}"
  "$TMP/tests" "$TMP"
  exit 0
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "$MODE" == "dmg" ]]; then
  # For other Macs: one binary for Apple Silicon and one for Intel, merged, compatible with macOS 12 and later.
  PARTS="$(mktemp -d)"
  if compile "arm64-apple-macos$MIN_MACOS" "$PARTS/arm64" && compile "x86_64-apple-macos$MIN_MACOS" "$PARTS/x86_64"; then
    lipo -create -output "$APP/Contents/MacOS/WorkHub" "$PARTS/arm64" "$PARTS/x86_64"
    echo "Universal app (Apple Silicon + Intel), macOS $MIN_MACOS or later."
  else
    echo "WARNING: universal build failed. Building for this Mac only: it will work on Macs"
    echo "with the same processor and the same macOS version (or newer)."
    compile "" "$APP/Contents/MacOS/WorkHub"
  fi
  rm -rf "$PARTS"
else
  compile "$HOST_TARGET" "$APP/Contents/MacOS/WorkHub"
fi

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/todos.html Resources/focus.html Resources/snippets.html Resources/settings.html "$APP/Contents/Resources/"

# Focus sounds: they go into your Library, not inside the app (so they don't end up in the DMG).
# Sounds already there are not overwritten.
SOUNDS_DIR="$HOME/Library/Application Support/WorkHub/Sounds"
if compgen -G "Sounds/*" > /dev/null; then
  mkdir -p "$SOUNDS_DIR"
  cp -n Sounds/* "$SOUNDS_DIR/" 2>/dev/null || true
  echo "Sounds available in: $SOUNDS_DIR"
fi

# Build number = date and time (shown in "About WorkHub")
BUILD="$(date +%Y%m%d.%H%M)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

# Stable signature if the certificate exists (see ./setup-signing.sh), otherwise ad-hoc.
SIGNED_WITH_CERT=0
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
  SIGNED_WITH_CERT=1
  echo "Signed with \"$IDENTITY\"."
else
  codesign --force --sign - "$APP"
  echo "Ad-hoc signature: macOS will ask for permissions on every build (run ./setup-signing.sh to avoid this)."
fi
echo "WorkHub $VERSION (build $BUILD)"

case "$MODE" in
  install)
    pkill -x WorkHub 2>/dev/null && sleep 1 || true
    rm -rf "/Applications/$APP"
    mv "$APP" /Applications/
    open "/Applications/$APP"
    echo "Installed in /Applications and launched."
    ;;
  dmg)
    DMG="WorkHub-$VERSION.dmg"
    STAGE="$(mktemp -d)"
    trap 'rm -rf "$STAGE"' EXIT
    ditto "$APP" "$STAGE/$APP"
    ln -s /Applications "$STAGE/Applications"
    cp "Distribution/How to open WorkHub.txt" "$STAGE/"
    rm -f "$DMG"
    hdiutil create -volname "WorkHub $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    if [[ $SIGNED_WITH_CERT == 1 ]]; then codesign --force --sign "$IDENTITY" "$DMG"; fi
    echo "Installer ready: $DMG"
    echo "Focus sounds are not included: whoever installs it can add their own from \"Add sounds…\"."
    ;;
  *)
    echo "Done: $APP  (./build.sh install to install it, ./build.sh dmg for the installer)"
    ;;
esac
