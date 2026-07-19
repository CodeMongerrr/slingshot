#!/bin/bash
# Assemble Slingshot.app from the release build and zip it for distribution.
# CODESIGN_IDENTITY: signing identity (default ad-hoc).
# NOTARY_PROFILE: if set with a Developer ID identity, notarizes and staples.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${CODESIGN_IDENTITY:--}"

swift build -c release
rm -rf Slingshot.app Slingshot.zip
mkdir -p Slingshot.app/Contents/MacOS Slingshot.app/Contents/Frameworks
cp Info.plist Slingshot.app/Contents/Info.plist
cp .build/release/Slingshot Slingshot.app/Contents/MacOS/Slingshot

SPARKLE=$(find .build/artifacts -path "*macos-arm64_x86_64/Sparkle.framework" -maxdepth 6 | head -1)
cp -R "$SPARKLE" Slingshot.app/Contents/Frameworks/
install_name_tool -add_rpath "@executable_path/../Frameworks" Slingshot.app/Contents/MacOS/Slingshot 2>/dev/null || true

codesign --force --deep -s "$IDENTITY" Slingshot.app/Contents/Frameworks/Sparkle.framework
codesign --force -s "$IDENTITY" Slingshot.app

if [ -n "${NOTARY_PROFILE:-}" ]; then
    ditto -c -k --keepParent Slingshot.app notary-submit.zip
    xcrun notarytool submit notary-submit.zip --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple Slingshot.app
    rm notary-submit.zip
fi

ditto -c -k --keepParent Slingshot.app Slingshot.zip
echo "Packaged Slingshot.zip (signed: $IDENTITY, notarized: ${NOTARY_PROFILE:+yes}${NOTARY_PROFILE:-no})"
