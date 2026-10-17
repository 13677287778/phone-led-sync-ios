#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
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
  test > output/xcode-simulator-tests.log 2>&1 || { tail -120 output/xcode-simulator-tests.log; exit 1; }
echo 'Simulator CoreVideo pixel/channel/orientation/protocol tests passed; this is NOT ReplayKit real-device verification.'
