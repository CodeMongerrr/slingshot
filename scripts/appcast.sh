#!/bin/bash
# Regenerate appcast.xml for the given version, signing Slingshot.zip.
# usage: scripts/appcast.sh 2.0.0 25
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$1"
BUILD="$2"
SIG=$(swift scripts/sparkle-sign.swift sign Slingshot.zip)
URL="https://github.com/Giri-Aayush/slingshot/releases/download/v${VERSION}/Slingshot.zip"
cat > appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Slingshot</title>
    <item>
      <title>Version ${VERSION}</title>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <link>https://github.com/Giri-Aayush/slingshot/releases/tag/v${VERSION}</link>
      <enclosure url="${URL}" ${SIG} type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
echo "appcast.xml written for v${VERSION}"
