#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/build"

swiftc -parse-as-library -swift-version 6 -o "$root/build/check-parser" \
  "$root/Shared/Models.swift" \
  "$root/Shared/Parser.swift" \
  "$root/Shared/WireFormat.swift" \
  "$root/Shared/FordRegion.swift" \
  "$root/scripts/check-parser.swift"

"$root/build/check-parser" "$root/Fixtures"
