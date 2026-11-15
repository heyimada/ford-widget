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

"$root/build/render-card" "$root/Fixtures/telemetry-sample.json" "$root/build/card.png" "$now" "${1:-en_DE}"
