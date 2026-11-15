#!/bin/bash
# Renders the card at the reference's size with the real car image and prints the mean per-pixel difference (0-255).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/build/parity"

"$root/scripts/render-card.sh" 'en_US@rg=dezzzz' "$out/car.png" 334x158 "$out/render.png" > /dev/null
swiftc -O -o "$out/parity-tool" "$root/scripts/parity.swift"
"$out/parity-tool" "$out/reference-full.png" "$out/render.png" "$out" 1002 474
