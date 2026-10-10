#!/bin/zsh
# Builds a universal (Apple silicon + Intel) Release of NeoNotch and packages
# it as a disk image for a GitHub release: build/NeoNotch-<version>.dmg
#
# Signing: if the local signing identity from install.sh exists, the app is
# signed with it, so a new version keeps the permissions people granted to the
# last one. Otherwise it is signed ad-hoc. Either way it is not notarized.
set -euo pipefail
cd "$(dirname "$0")/.."

KEYCHAIN="$PWD/Signing/NeoNotch.keychain-db"
KEYCHAIN_PASSWORD="neonotch"   # a local, single-purpose keychain
OUT="$PWD/build"
DERIVED="$OUT/DerivedData"

echo "Building universal Release…"
rm -rf "$DERIVED"
xcodebuild -project NeoNotch.xcodeproj -scheme NeoNotch -configuration Release \
    -derivedDataPath "$DERIVED" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build 2>&1 \
    | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
APP="$DERIVED/Build/Products/Release/NeoNotch.app"
[[ -d "$APP" ]] || { echo "No build at $APP"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "Version $VERSION, architectures: $(lipo -archs "$APP/Contents/MacOS/NeoNotch")"

if [[ -f "$KEYCHAIN" ]]; then
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    IDENTITY=$(security find-identity -p codesigning "$KEYCHAIN" | awk '/NeoNotch Local Signing/ {print $2; exit}')
    codesign --force --deep --sign "$IDENTITY" --keychain "$KEYCHAIN" "$APP"
    echo "Signed with NeoNotch Local Signing"
else
    codesign --force --deep --sign - "$APP"
    echo "Signed ad-hoc"
fi
codesign --verify --strict "$APP"

echo "Packaging…"
STAGE="$OUT/dmg"
DMG="$OUT/NeoNotch-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/NeoNotch.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "NeoNotch $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
shasum -a 256 "$DMG"
echo "Wrote $DMG"
