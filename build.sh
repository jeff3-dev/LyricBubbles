#!/bin/zsh
# Builds LyricBubbles.app (release) next to this script.
#   ./build.sh            build only
#   ./build.sh --install  build, then copy to /Applications and open it
#   ./build.sh --dist     universal (Apple silicon + Intel) build, packed into
#                         dist/LyricBubbles-<version>.dmg and .zip
# Bump VERSION / BUILD for each release.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="0.1.0"
BUILD="1"
MODE="${1:-}"

if [[ "$MODE" == "--dist" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/LyricBubbles"
else
  swift build -c release
  BIN=.build/release/LyricBubbles
fi
APP=LyricBubbles.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LyricBubbles"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LyricBubbles</string>
  <key>CFBundleDisplayName</key><string>LyricBubbles</string>
  <key>CFBundleIdentifier</key><string>local.lyricbubbles</string>
  <key>CFBundleExecutable</key><string>LyricBubbles</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAudioCaptureUsageDescription</key>
  <string>LyricBubbles listens to what your Mac is playing so the glow border can move with the music. Audio is never recorded or saved.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>LyricBubbles can listen through the microphone so the glow border can move with the music. Audio is never recorded or saved.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>LyricBubbles reads the current Spotify track and playback position to sync lyrics, and sends play, pause and skip when you use its playback controls.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "$MODE" == "--install" ]]; then
  DEST=/Applications/LyricBubbles.app
  pkill -x LyricBubbles 2>/dev/null || true
  sleep 0.5
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  # Refresh Launchpad/Spotlight so the new icon shows up.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true
  echo "Installed $DEST"
  open "$DEST"
fi

if [[ "$MODE" == "--dist" ]]; then
  NAME="LyricBubbles-$VERSION"
  TMP=$(mktemp -d); STAGE="$TMP/LyricBubbles"; mkdir -p "$STAGE"
  mkdir -p dist
  ditto "$APP" "$STAGE/LyricBubbles.app"
  ln -s /Applications "$STAGE/Applications"
  cp "docs/INSTALL.txt" "$STAGE/Read Me First.txt"
  rm -f "dist/$NAME.dmg" "dist/$NAME.zip"
  hdiutil create -volname "LyricBubbles" -srcfolder "$STAGE" -ov -format UDZO \
    "dist/$NAME.dmg" >/dev/null
  # Zip too, for places that handle .dmg badly. ditto keeps the app's signature intact.
  rm -f "$STAGE/Applications"
  ditto -c -k --keepParent "$STAGE" "dist/$NAME.zip"
  rm -rf "$TMP"
  echo "Packed dist/$NAME.dmg and dist/$NAME.zip"
fi
