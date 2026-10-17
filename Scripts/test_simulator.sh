#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/app_group_override.sh
mkdir -p output
xcrun simctl list devices available --json > output/simulator-devices.json
device=$(python3 - <<'PY'
import json
d=json.load(open('output/simulator-devices.json'))
all_devices=[v for name,values in d['devices'].items() if 'iOS' in name for v in values if v.get('isAvailable') and 'iPhone' in v['name']]
if not all_devices:raise SystemExit('No available iPhone simulator; cannot claim simulator tests passed.')
preferred=sorted(all_devices,key=lambda x:('SE' not in x['name'],x['name']))[0]
print(preferred['udid'])
PY
)
xcodebuild -project ColorLight.xcodeproj -scheme ColorLight -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" -derivedDataPath build/SimulatorData \
  -resultBundlePath output/PixelTests.xcresult CODE_SIGNING_ALLOWED=NO \
  "${app_group_build_args[@]}" \
  test > output/xcode-simulator-tests.log 2>&1 || { tail -120 output/xcode-simulator-tests.log; exit 1; }
echo 'Simulator CoreVideo pixel/channel/orientation/protocol tests passed; this is NOT ReplayKit real-device verification.'
app=build/SimulatorData/Build/Products/Debug-iphonesimulator/ColorLight.app
bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
xcrun simctl bootstatus "$device" -b
xcrun simctl install "$device" "$app"
xcrun simctl launch "$device" "$bundle"
sleep 2
xcrun simctl io "$device" screenshot output/dashboard-simulator.png
echo 'Captured simulator dashboard for visual review; permissions and capture are not auto-approved.'
