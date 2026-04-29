#!/bin/bash
set -e
cd "$(dirname "$0")"

APP_NAME="DoctorBattery"
BUILD_DIR="./build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS" "$RESOURCES"

SOURCES=(
    BatteryMonitor/BatteryMonitorApp.swift
    BatteryMonitor/ContentView.swift
    BatteryMonitor/BatteryReader.swift
    BatteryMonitor/IOSDeviceReader.swift
    BatteryMonitor/HistoryStore.swift
    BatteryMonitor/Notifier.swift
    BatteryMonitor/SettingsView.swift
    BatteryMonitor/HealthAnalytics.swift
    BatteryMonitor/AdapterDatabase.swift
    BatteryMonitor/Theme.swift
    BatteryMonitor/SystemTemperatures.swift
)

FRAMEWORKS="-framework SwiftUI -framework IOKit -framework UserNotifications -framework Charts -framework AppKit -framework ServiceManagement -lsqlite3"

UNIVERSAL=${UNIVERSAL:-1}

if [ "$UNIVERSAL" = "1" ]; then
    echo "Building arm64..."
    swiftc -O -target arm64-apple-macos13 $FRAMEWORKS \
        -o "$BUILD_DIR/$APP_NAME-arm64" "${SOURCES[@]}"
    echo "Building x86_64..."
    swiftc -O -target x86_64-apple-macos13 $FRAMEWORKS \
        -o "$BUILD_DIR/$APP_NAME-x86_64" "${SOURCES[@]}"
    echo "Lipo universal..."
    lipo -create "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64" \
        -output "$MACOS/$APP_NAME"
    rm "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64"
else
    echo "Building host arch only..."
    swiftc -O -target arm64-apple-macos13 $FRAMEWORKS \
        -o "$MACOS/$APP_NAME" "${SOURCES[@]}"
fi

cp -R BatteryMonitor/Resources/it.lproj "$RESOURCES/"
cp -R BatteryMonitor/Resources/en.lproj "$RESOURCES/"
if [ -f BatteryMonitor/Resources/AppIcon.icns ]; then
    cp BatteryMonitor/Resources/AppIcon.icns "$RESOURCES/AppIcon.icns"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>           <string>DoctorBattery</string>
    <key>CFBundleDisplayName</key>    <string>Doctor Battery</string>
    <key>CFBundleIdentifier</key>     <string>com.doctorbattery.app</string>
    <key>CFBundleVersion</key>        <string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>    <string>APPL</string>
    <key>CFBundleExecutable</key>     <string>DoctorBattery</string>
    <key>CFBundleIconFile</key>       <string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key><string>it</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>it</string>
        <string>en</string>
    </array>
    <key>LSMinimumSystemVersion</key> <string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>Open source — MIT licensed.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "Done: $APP_BUNDLE"
echo "Architectures:"
lipo -archs "$MACOS/$APP_NAME" 2>/dev/null || file "$MACOS/$APP_NAME"
