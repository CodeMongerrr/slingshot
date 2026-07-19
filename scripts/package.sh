#!/bin/bash
# Assemble Slingshot.app from the release build and zip it for distribution.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${CODESIGN_IDENTITY:--}"

swift build -c release
rm -rf Slingshot.app Slingshot.zip
mkdir -p Slingshot.app/Contents/MacOS
cp Info.plist Slingshot.app/Contents/Info.plist
cp .build/release/Slingshot Slingshot.app/Contents/MacOS/Slingshot
codesign --force -s "$IDENTITY" Slingshot.app
ditto -c -k --keepParent Slingshot.app Slingshot.zip
echo "Packaged Slingshot.zip (signed: $IDENTITY)"
