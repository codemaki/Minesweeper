#!/bin/zsh
# Builds, signs and notarizes build/Minesweeper-<version>.dmg.
#
# Requires a "Developer ID Application" certificate in the keychain and
# notarytool credentials stored under NOTARY_PROFILE, e.g.:
#   xcrun notarytool store-credentials minesweeper-notary --key AuthKey_XXX.p8 --key-id XXX --issuer XXX
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/build"
APP="$BUILD/Minesweeper.app"
NOTARY_PROFILE="${NOTARY_PROFILE:-minesweeper-notary}"

export VERSION="${VERSION:-1.0.1}"
DMG="$BUILD/Minesweeper-$VERSION.dmg"

"$ROOT/Scripts/build-app.sh"

SIGN_IDENTITY="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)/\1/p')"
if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "error: $APP is not signed with a Developer ID Application certificate" >&2
    exit 1
fi

# Disk image: the app plus a shortcut to /Applications for drag-and-drop install
STAGING="$BUILD/dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Minesweeper.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Minesweeper" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"

codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

echo "Submitting to Apple notary service..."
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# Gatekeeper check, as a downloaded file would be assessed
spctl --assess --type open --context context:primary-signature -v "$DMG"
echo "Done: $DMG"
