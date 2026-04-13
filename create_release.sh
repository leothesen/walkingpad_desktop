#!/bin/bash
set -e

# Usage: ./create_release.sh v0.2.0
# Builds, signs, creates GitHub Release, and updates appcast.

if [ -z "$1" ]; then
  echo "Usage: ./create_release.sh <tag>"
  echo "  e.g. ./create_release.sh v0.2.0"
  exit 1
fi

TAG="$1"
VERSION="${TAG#v}"

# Check prerequisites
command -v gh >/dev/null 2>&1 || { echo "Error: gh CLI not installed (brew install gh)"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "Error: xcodebuild not found"; exit 1; }

# Check for Sparkle signing tool
SIGN_UPDATE=""
if [ -f "/tmp/bin/sign_update" ]; then
  SIGN_UPDATE="/tmp/bin/sign_update"
elif [ -f "$HOME/bin/sign_update" ]; then
  SIGN_UPDATE="$HOME/bin/sign_update"
else
  echo "Warning: sign_update not found. Download Sparkle tools first:"
  echo '  curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz" | tar xJ -C /tmp'
  echo ""
  read -p "Continue without signing? (y/N) " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

echo "==> Stamping version ${VERSION}..."
sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = ${VERSION};/g" \
  walkingpad-client.xcodeproj/project.pbxproj

echo "==> Building (Release)..."
xcodebuild -scheme walkingpad-client \
  -configuration Release \
  -derivedDataPath build \
  -destination "platform=macOS,arch=arm64" \
  CODE_SIGN_IDENTITY="-" \
  -quiet

echo "==> Packaging..."
cd build/Build/Products/Release
zip -r ../../../../WalkingPad-Client.zip "Walkingpad Client.app" -q
cd ../../../..

SIZE=$(ls -lh WalkingPad-Client.zip | awk '{print $5}')
echo "    WalkingPad-Client.zip ($SIZE)"

# Generate appcast with EdDSA signature
if [ -n "$SIGN_UPDATE" ]; then
  echo "==> Signing update..."
  FILE_SIZE=$(stat -f%z WalkingPad-Client.zip)
  PUB_DATE=$(date -R)
  SIGNATURE=$("$SIGN_UPDATE" WalkingPad-Client.zip 2>/dev/null)

  echo "==> Generating appcast.xml..."
  cat > appcast.xml << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>WalkingPad Client</title>
    <link>https://github.com/leothesen/walkingpad_desktop</link>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <enclosure
        url="https://github.com/leothesen/walkingpad_desktop/releases/download/${TAG}/WalkingPad-Client.zip"
        length="${FILE_SIZE}"
        type="application/octet-stream"
        sparkle:edSignature="${SIGNATURE}"
      />
    </item>
  </channel>
</rss>
EOF
  echo "    appcast.xml generated"
fi

echo "==> Creating tag ${TAG}..."
git tag "$TAG" 2>/dev/null || echo "    Tag already exists, skipping"

echo "==> Pushing tag..."
git push origin "$TAG" 2>/dev/null || echo "    Tag already pushed"

echo "==> Creating GitHub Release..."
gh release create "$TAG" \
  WalkingPad-Client.zip \
  --title "WalkingPad Client ${VERSION}" \
  --generate-notes

# Commit updated appcast if it was generated
if [ -f appcast.xml ] && [ -n "$SIGN_UPDATE" ]; then
  echo "==> Committing appcast.xml..."
  git add appcast.xml walkingpad-client.xcodeproj/project.pbxproj
  git commit -m "chore: update appcast and version for ${TAG}"
  git push origin HEAD
fi

echo ""
echo "Done! Release ${TAG} published."
echo "https://github.com/leothesen/walkingpad_desktop/releases/tag/${TAG}"
