#!/bin/zsh
# Builds build/Minesweeper.app (release, universal when possible).
set -euo pipefail

ROOT="${0:A:h:h}"
SRC="$ROOT/Sources/MacosMinesweeper"
BUILD="$ROOT/build"
APP="$BUILD/Minesweeper.app"

cd "$ROOT"
swift build -c release --arch arm64 --arch x86_64 2>/dev/null \
    || swift build -c release
BIN="$(swift build -c release --show-bin-path 2>/dev/null)/MacosMinesweeper"
[[ -f "$BIN" ]] || BIN="$ROOT/.build/apple/Products/Release/MacosMinesweeper"

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
    <key>CFBundleIdentifier</key><string>com.example.MacosMinesweeper</string>
    <key>CFBundleExecutable</key><string>Minesweeper</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.puzzle-games</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
rm -rf "$BUILD/tmp"
echo "Built $APP"
