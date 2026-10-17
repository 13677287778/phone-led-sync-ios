#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/app_group_override.sh
mkdir -p output build
python3 Scripts/generate_project.py
xcodebuild -version | tee output/xcode-version.txt
swiftc Shared/ColorCore.swift Tests/main.swift -o build/core-tests
build/core-tests | tee output/core-tests.txt
xcodebuild -project ColorLight.xcodeproj -scheme ColorLight -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  "${app_group_build_args[@]}" \
  build > output/xcode-device-build.log 2>&1 || { tail -120 output/xcode-device-build.log; exit 1; }
app=build/DerivedData/Build/Products/Release-iphoneos/ColorLight.app
test -d "$app/PlugIns/ColorLightBroadcast.appex"
/usr/bin/lipo -info "$app/ColorLight" | tee output/architecture.txt
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")
python3 Scripts/package_ipa.py "$app" "output/ColorLight-$version-unsigned.ipa"
echo 'Unsigned ARM64 device IPA produced. User must sign BOTH app and extension with the App Group entitlement.'
