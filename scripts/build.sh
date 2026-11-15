#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
derived="$root/build/DerivedData"

xcodegen generate

built=()
for destination in 'generic/platform=iOS Simulator' 'generic/platform=iOS'; do
  echo "== xcodebuild $destination"
  if xcodebuild -project FordWidget.xcodeproj -scheme FordWidget -destination "$destination" \
      -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO build > "$root/build/xcodebuild.log" 2>&1; then
    echo "BUILD SUCCEEDED ($destination)"
    built+=("$destination")
  else
    grep -E 'error:|BUILD FAILED' "$root/build/xcodebuild.log" | sort -u | head -n 30
    echo "BUILD FAILED ($destination)"
  fi
done

[ ${#built[@]} -gt 0 ] || { echo "no destination built"; exit 1; }

case "${built[0]}" in
  *Simulator) products="$derived/Build/Products/Debug-iphonesimulator" ;;
  *) products="$derived/Build/Products/Debug-iphoneos" ;;
esac
app="$products/FordWidget.app"
appex=("$app"/PlugIns/*.appex)
[ -d "${appex[0]}" ] || { echo "FAIL: no appex embedded at $app/PlugIns"; exit 1; }
appex="${appex[0]}"

plist() { plutil -extract "$2" raw -o - "$1/Info.plist"; }
check() {
  if [ "$2" != "$3" ]; then echo "FAIL: $1: expected '$3', got '$2'"; exit 1; fi
  echo "ok: $1 = $2"
}

app_id="$(plist "$app" CFBundleIdentifier)"
ext_id="$(plist "$appex" CFBundleIdentifier)"
prefix="${app_id}"

check "extension point" "$(plutil -extract NSExtension.NSExtensionPointIdentifier raw -o - "$appex/Info.plist")" "com.apple.widgetkit-extension"
[[ "$ext_id" == "$app_id"* ]] || { echo "FAIL: appex id $ext_id does not start with $app_id"; exit 1; }
echo "ok: appex id $ext_id starts with $app_id"
check "CFBundleShortVersionString matches" "$(plist "$appex" CFBundleShortVersionString)" "$(plist "$app" CFBundleShortVersionString)"
check "CFBundleVersion matches" "$(plist "$appex" CFBundleVersion)" "$(plist "$app" CFBundleVersion)"
check "app CFBundleDisplayName" "$(plist "$app" CFBundleDisplayName)" "My Ford"
check "app AppGroupID" "$(plist "$app" AppGroupID)" "group.$prefix"
check "appex AppGroupID" "$(plist "$appex" AppGroupID)" "group.$prefix"

grep -rq 'containerBackground(for: .widget' Widget/ || { echo "FAIL: containerBackground(for: .widget) missing in Widget/"; exit 1; }
echo "ok: containerBackground(for: .widget) present in Widget/"

echo "build.sh passed for: ${built[*]}"
