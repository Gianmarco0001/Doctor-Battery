#!/bin/bash
set -e
cd "$(dirname "$0")"

SRC="${1:-icon-source.png}"
STYLED="icon-styled.png"
OUT="BatteryMonitor/Resources/AppIcon.icns"

if [ ! -f "$SRC" ]; then
    echo "Source PNG not found: $SRC"; exit 1
fi

if [ -f make-fancy-icon.swift ]; then
    echo "Generating styled icon..."
    swift make-fancy-icon.swift "$SRC" "$STYLED" >/dev/null
    SRC="$STYLED"
fi

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET" "BatteryMonitor/Resources"

for size in 16 32 64 128 256 512 1024; do
    sips -z $size $size "$SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    half=$((size / 2))
    if [ $half -ge 16 ]; then
        sips -z $half $half "$SRC" --out "$ICONSET/icon_${half}x${half}@2x.png" >/dev/null
    fi
done

mv "$ICONSET/icon_64x64.png" "$ICONSET/icon_32x32@2x.png"
mv "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png" 2>/dev/null || true

iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$ICONSET"

echo "Created: $OUT"
ls -lh "$OUT"
