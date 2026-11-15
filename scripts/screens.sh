#!/bin/bash
# Builds Debug, installs it on the iPhone 18 Pro and iPhone Duo simulators and screenshots every tab in demo mode.
# Output: build/screens/<device>-<tab>[-<pose>].png. Needs the Duo booted with DeviceHub open (see the iphone-duo-simulator skill).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
out="$root/build/screens"
derived="$root/build/DerivedData"
bundle=com.heyimada.myford
phone=54D9765F-8268-4B7F-8C9E-44C053E9D4E8
duo_udid=FD3A2110-D222-45D1-9AA6-35265D0E30E1
duo="${DUO:-$HOME/.claude/skills/iphone-duo-simulator/scripts/duo}"
tabs=(overview location health vehicle)
mkdir -p "$out"
if [ "${SCREENS_ONLY:-both}" = both ]; then rm -f "$out"/*.png; fi

xcodegen generate > /dev/null
xcodebuild -project FordWidget.xcodeproj -scheme FordWidget -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO build \
  > "$root/build/xcodebuild-screens.log" 2>&1 || { grep -E 'error:' "$root/build/xcodebuild-screens.log" | sort -u; exit 1; }
app="$derived/Build/Products/Debug-iphonesimulator/FordWidget.app"

install() {
  local udid="$1"
  xcrun simctl bootstatus "$udid" -b > /dev/null
  xcrun simctl terminate "$udid" "$bundle" 2> /dev/null || true
  xcrun simctl install "$udid" "$app"
  local data
  data="$(xcrun simctl get_app_container "$udid" "$bundle" data)"
  mkdir -p "$data/Documents/demo"
  cp "$root/Fixtures/telemetry-full.json" "$root/Fixtures/garage.json" "$data/Documents/demo/"
  if [ -f "$root/build/parity/car.png" ]; then cp "$root/build/parity/car.png" "$data/Documents/demo/car.png"; fi
  # The first launch after an install is slow and screenshots as a blank launch screen: pay for it here.
  xcrun simctl launch "$udid" "$bundle" -demo > /dev/null
  sleep 6
  xcrun simctl terminate "$udid" "$bundle" > /dev/null
}

launch() {
  xcrun simctl launch --terminate-running-process "$1" "$bundle" -demo -tab "$2" > /dev/null
  # The map needs a moment to fetch tiles and the address.
  if [ "$2" = location ]; then sleep 6; else sleep 3; fi
}

# The Duo writes <prefix>-outer.png / -inner.png for whichever display is lit; keep a single file per pose.
duo_shot() {
  local name="$1" tmp="$out/.duo"
  rm -f "$tmp"-*.png
  "$duo" shot "$tmp" > /dev/null
  for f in "$tmp"-*.png; do
    case "$f" in
      *-outer.png) mv "$f" "$out/$name-outer.png" ;;
      *-inner.png) mv "$f" "$out/$name-inner.png" ;;
    esac
  done
}

# DeviceHub's pose buttons occasionally vanish for a moment; retry before giving up.
pose() {
  local try
  for try in 1 2 3 4; do
    "$duo" pose "$1" > /dev/null && return 0
    sleep 3
  done
  echo "FAIL: could not pose the Duo $1" >&2
  return 1
}

# SCREENS_ONLY=phone|duo limits the run to one device.
only="${SCREENS_ONLY:-both}"

echo "== iPhone 18 Pro"
if [ "$only" = duo ]; then echo "skipped (SCREENS_ONLY=duo)"; else
install "$phone"
for tab in "${tabs[@]}"; do
  launch "$phone" "$tab"
  xcrun simctl io "$phone" screenshot "$out/iphone18pro-$tab.png" > /dev/null 2>&1
  echo "  iphone18pro-$tab.png"
done
xcrun simctl ui "$phone" appearance dark
launch "$phone" overview
xcrun simctl io "$phone" screenshot "$out/iphone18pro-overview-dark.png" > /dev/null 2>&1
xcrun simctl ui "$phone" appearance light
echo "  iphone18pro-overview-dark.png"
fi

echo "== iPhone Duo"
if [ "$only" = phone ]; then
  echo "skipped (SCREENS_ONLY=phone)"
elif [ ! -x "$duo" ]; then
  echo "skipped: $duo not found (set DUO to the iphone-duo-simulator scripts/duo helper)"
else
  export DUO_UDID="$duo_udid"
  "$duo" doctor
  install "$duo_udid"
  pose closed
  for tab in "${tabs[@]}"; do
    launch "$duo_udid" "$tab"
    for pose in closed half open; do
      pose "$pose"
      sleep 2
      duo_shot "duo-$tab-$pose"
    done
    "$duo" rotate 1
    duo_shot "duo-$tab-open-rotate"
    "$duo" rotate 3
    pose closed
    echo "  duo-$tab-*"
  done
  xcrun simctl ui "$duo_udid" appearance dark
  launch "$duo_udid" overview
  duo_shot "duo-overview-closed-dark"
  xcrun simctl ui "$duo_udid" appearance light
  pose closed
fi

ls "$out"
