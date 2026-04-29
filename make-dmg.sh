#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="build/DoctorBattery.app"
DMG="build/DoctorBattery.dmg"
VOL="Doctor Battery"

if [ ! -d "$APP" ]; then
    echo "Build first: ./build.sh"; exit 1
fi

rm -f "$DMG"
rm -rf build/dmg-staging
mkdir -p build/dmg-staging
cp -R "$APP" build/dmg-staging/
ln -s /Applications build/dmg-staging/Applications

hdiutil create -volname "$VOL" -srcfolder build/dmg-staging -ov -format UDZO "$DMG"
rm -rf build/dmg-staging

echo "Created: $DMG"
ls -lh "$DMG"
