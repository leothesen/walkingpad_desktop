#!/bin/bash
set -e

echo "Building WalkingPad Client (Release)..."
xcodebuild -scheme walkingpad-client \
  -configuration Release \
  -derivedDataPath build \
  -destination "platform=macOS,arch=arm64" \
  CODE_SIGN_IDENTITY="-" \
  -quiet

echo "Packaging..."
cd build/Build/Products/Release
zip -r ../../../../WalkingPad-Client.zip "Walkingpad Client.app" -q
cd ../../../..

SIZE=$(ls -lh WalkingPad-Client.zip | awk '{print $5}')
echo ""
echo "Done! WalkingPad-Client.zip ($SIZE)"
echo "Upload to: https://github.com/leothesen/walkingpad_desktop/releases/new"
