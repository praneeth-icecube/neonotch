#!/bin/zsh
# Builds NeoNotch, signs it with the local signing identity, installs it in
# /Applications and relaunches it.
#
# Why the signing: macOS files every permission — Reminders, camera, Calendar,
# Automation — under the app's code signature. Signed ad-hoc, each build is a
# different app to macOS and every permission is asked for again. Signed with
# the same certificate every time, a new build is the same app and keeps them.
#
# The identity lives in its own keychain, Signing/NeoNotch.keychain-db — not in
# your login keychain, and not trusted system-wide. It signs nothing but this.
set -euo pipefail
cd "$(dirname "$0")/.."

KEYCHAIN="$PWD/Signing/NeoNotch.keychain-db"
KEYCHAIN_PASSWORD="neonotch"   # a local, single-purpose keychain

echo "Building…"
xcodebuild -project NeoNotch.xcodeproj -scheme NeoNotch -configuration Release build 2>&1 \
    | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
PRODUCTS=$(xcodebuild -project NeoNotch.xcodeproj -scheme NeoNotch -configuration Release \
    -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
APP="$PRODUCTS/NeoNotch.app"
[[ -d "$APP" ]] || { echo "No build at $APP"; exit 1; }

if [[ -f "$KEYCHAIN" ]]; then
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    IDENTITY=$(security find-identity -p codesigning "$KEYCHAIN" | awk '/NeoNotch Local Signing/ {print $2; exit}')
    codesign --force --deep --sign "$IDENTITY" --keychain "$KEYCHAIN" "$APP"
    echo "Signed with NeoNotch Local Signing"
else
    echo "Warning: $KEYCHAIN is missing — this build is signed ad-hoc and macOS will ask for permissions again."
fi
codesign --verify --strict "$APP"

echo "Installing…"
pkill -TERM -x NeoNotch 2>/dev/null || true
for _ in {1..20}; do pgrep -x NeoNotch >/dev/null || break; sleep 0.25; done
rm -rf /Applications/NeoNotch.app
ditto "$APP" /Applications/NeoNotch.app
open -a /Applications/NeoNotch.app
echo "NeoNotch is running from /Applications."
