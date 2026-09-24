#!/bin/zsh
# Builds build/Minesweeper.app (release, universal arm64 + x86_64).
#
# Signing: uses the first "Developer ID Application" identity in the keychain
# with the hardened runtime (required for notarization). Falls back to an
# ad-hoc signature when no such identity exists. Override with SIGN_IDENTITY.
set -euo pipefail

ROOT="${0:A:h:h}"
SRC="$ROOT/Sources/MacosMinesweeper"
BUILD="$ROOT/build"
APP="$BUILD/Minesweeper.app"

VERSION="${VERSION:-1.0.1}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
BUNDLE_ID="${BUNDLE_ID:-com.codemaki.Minesweeper}"

cd "$ROOT"
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/MacosMinesweeper"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/tmp"
cp "$BIN" "$APP/Contents/MacOS/Minesweeper"

# App icon
swiftc -O -o "$BUILD/tmp/IconRenderer" \
    "$ROOT/Scripts/IconRenderer/main.swift" "$SRC/Sprites.swift" "$SRC/Game.swift" "$SRC/Config.swift"
"$BUILD/tmp/IconRenderer" "$BUILD/tmp/AppIcon.iconset"
iconutil -c icns "$BUILD/tmp/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Minesweeper</string>
    <key>CFBundleDisplayName</key><string>Minesweeper</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>Minesweeper</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.puzzle-games</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"

if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
    echo "Signed with: $SIGN_IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "No Developer ID identity found; signed ad-hoc (not notarizable)"
fi

rm -rf "$BUILD/tmp"
echo "Built $APP ($VERSION)"
