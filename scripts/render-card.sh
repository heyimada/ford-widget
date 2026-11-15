#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/build"

# 2025-07-07T05:34:24.902Z: exactly 7 days after the sample's newest updateTime (2025-06-30T05:34:24.902Z).
now=1751866464.902

swiftc -parse-as-library -swift-version 6 -o "$root/build/render-card" \
  "$root/Shared/Models.swift" \
  "$root/Shared/Parser.swift" \
  "$root/Shared/VehicleCardView.swift" \
  "$root/scripts/render-card.swift"

# args: [locale] [car image or -] [WxH in pt] [output png]
"$root/build/render-card" "$root/Fixtures/telemetry-sample.json" "${4:-$root/build/card.png}" "$now" "${1:-en_DE}" "$root/Shared/Assets.xcassets/FordLogo.imageset/FordLogo.svg" "${2:--}" "${3:-364x170}"
