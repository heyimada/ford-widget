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
# SCREENS_TABS="location health" limits the run to those tabs.
read -r -a tabs <<< "${SCREENS_TABS:-overview location health vehicle}"
mkdir -p "$out"
if [ "${SCREENS_ONLY:-both}" = both ] && [ -z "${SCREENS_TABS:-}" ]; then rm -f "$out"/*.png; fi
rm -f "$out"/.duo*.png

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
  rm -rf "$data/Documents/demo"
  mkdir -p "$data/Documents/demo"
  cp "$root/Fixtures/telemetry-full.json" "$root/Fixtures/garage.json" "$data/Documents/demo/"
  if [ -f "$root/build/parity/car.png" ]; then cp "$root/build/parity/car.png" "$data/Documents/demo/car.png"; fi
  # The first launch after an install is slow and screenshots as a blank launch screen: pay for it here.
  xcrun simctl launch "$udid" "$bundle" -demo > /dev/null
  sleep 6
  xcrun simctl terminate "$udid" "$bundle" > /dev/null
}

# launch <udid> <tab> [extra app arguments, e.g. -scroll-bottom]
launch() {
  local marker
  marker="$(xcrun simctl get_app_container "$1" "$bundle" data)/Documents/demo/ready"
  rm -f "$marker"
  xcrun simctl launch --terminate-running-process "$1" "$bundle" -demo -tab "$2" "${@:3}" > /dev/null
  for _ in $(seq 1 60); do [ -f "$marker" ] && break; sleep 0.5; done
  [ -f "$marker" ] || { echo "FAIL: the app did not render the $2 tab within 30 s" >&2; return 1; }
  # The map needs a moment to fetch tiles and the address.
  if [ "$2" = location ]; then sleep 5; else sleep 1; fi
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

rotated=0
rotate() {
  local try
  for try in 1 2 3 4; do
    if "$duo" rotate "$1" > /dev/null; then
      rotated=$(( (rotated + $1) % 4 ))
      return 0
    fi
    sleep 3
  done
  echo "FAIL: could not rotate the Duo" >&2
  return 1
}

# SCREENS_ONLY=phone|duo limits the run to one device.
only="${SCREENS_ONLY:-both}"

# Whatever happens, leave both simulators light and the Duo closed in its start orientation.
cleanup() {
  xcrun simctl ui "$phone" appearance light > /dev/null 2>&1 || true
  xcrun simctl ui "$duo_udid" appearance light > /dev/null 2>&1 || true
  if [ "$only" != phone ] && [ -x "$duo" ]; then
    if [ "$rotated" -ne 0 ]; then "$duo" rotate $(( 4 - rotated )) > /dev/null 2>&1 || true; fi
    "$duo" pose closed > /dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "== iPhone 18 Pro"
if [ "$only" = duo ]; then echo "skipped (SCREENS_ONLY=duo)"; else
install "$phone"
for tab in "${tabs[@]}"; do
  launch "$phone" "$tab"
  xcrun simctl io "$phone" screenshot "$out/iphone18pro-$tab.png" > /dev/null 2>&1
  echo "  iphone18pro-$tab.png"
  # The warning tile and the warning sections sit at the end of these tabs.
  case "$tab" in overview|health)
    launch "$phone" "$tab" -scroll-bottom
    xcrun simctl io "$phone" screenshot "$out/iphone18pro-$tab-bottom.png" > /dev/null 2>&1
    echo "  iphone18pro-$tab-bottom.png" ;;
  esac
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
    rotate 1
    duo_shot "duo-$tab-open-rotate"
    rotate 3
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
