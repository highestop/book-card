#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain.sh
requested_device="${1:-iphone}"
device_id=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
requested = sys.argv[1]
devices = [device for runtime, group in json.load(sys.stdin)["devices"].items()
           if ".iOS-" in runtime for device in group if device.get("isAvailable")]
if requested.lower() in ("iphone", "ipad"):
    devices = [device for device in devices if device["name"].lower().startswith(requested.lower())]
    devices.sort(key=lambda device: device["state"] != "Booted")
else:
    devices = [device for device in devices if device["udid"] == requested or device["name"] == requested]
if not devices:
    sys.exit("No matching iOS simulator. Install a runtime in Xcode or pass an available device UDID.")
print(devices[0]["udid"])
' "$requested_device")
./scripts/build-ios.sh simulator
device_state=$(xcrun simctl list devices -j | python3 -c '
import json, sys
print(next(device["state"] for group in json.load(sys.stdin)["devices"].values()
           for device in group if device["udid"] == sys.argv[1]))
' "$device_id")
if [[ "$device_state" != "Booted" ]]; then xcrun simctl boot "$device_id"; fi
xcrun simctl bootstatus "$device_id" -b
xcrun simctl install "$device_id" build/ios-simulator/Build/Products/Debug-iphonesimulator/BookCard.app
xcrun simctl launch --terminate-running-process "$device_id" local.BookCard.iOS
developer_dir="$(xcode-select -p)"
if [[ -d "${developer_dir:h}/Applications/DeviceHub.app" ]]; then
  open -a "${developer_dir:h}/Applications/DeviceHub.app"
else
  open -a "$developer_dir/Applications/Simulator.app" --args -CurrentDeviceUDID "$device_id"
fi
