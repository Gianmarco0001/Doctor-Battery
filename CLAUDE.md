# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & run

There is **no Xcode project and no SwiftPM manifest**. The build is a hand-rolled `swiftc` invocation in `build.sh`.

```bash
./build.sh                # universal arm64 + x86_64, lipo'd into build/DoctorBattery.app
UNIVERSAL=0 ./build.sh    # host arch only (faster iteration)
open build/DoctorBattery.app
./make-dmg.sh             # packages build/DoctorBattery.app into build/DoctorBattery.dmg
```

Min target is `macOS 13`. The script links `-framework SwiftUI -framework IOKit -framework UserNotifications -framework Charts -framework AppKit -framework ServiceManagement -lsqlite3` and ad-hoc-codesigns the bundle at the end (`codesign --force --deep --sign -`).

**Adding a new `.swift` file requires editing the `SOURCES` array in `build.sh`** — there is no glob.

The product name (`DoctorBattery`) and bundle id (`com.doctorbattery.app`) are baked into the `Info.plist` heredoc at the bottom of `build.sh`. The `@main` entry point is `DoctorBatteryApp` in [BatteryMonitor/BatteryMonitorApp.swift](BatteryMonitor/BatteryMonitorApp.swift). Note the on-disk folder is still `BatteryMonitor/` (the project was renamed but directories were not).

There are no automated tests in the repo.

## Architecture

Pure Swift + SwiftUI + Swift Charts, no third-party Swift dependencies. ~1300 LOC. Dark-only UI defined in [BatteryMonitor/Theme.swift](BatteryMonitor/Theme.swift).

### Runtime loop

`AppViewModel` in [BatteryMonitor/ContentView.swift](BatteryMonitor/ContentView.swift) is the single source of truth and drives four timers added to `RunLoop.main`:

- **3 s** — `refreshAll()`: re-read Mac battery + system temps; kick off iOS battery refresh on `iosQueue` (a serial background queue) guarded by `iosRefreshInFlight`.
- **10 s** — `rescanDevices()`: re-list iOS devices via libimobiledevice, guarded by `deviceScanInFlight`.
- **30 s** — `maybeLog()`: gate that writes to SQLite only if `logIntervalMin` (default 5 min) has elapsed per device.
- **600 s** — `checkAnomalies()`: regression-based health-drop alerts and calibration reminders.

Temperature samples are smoothed via a 5-sample rolling average (`tempSamples` window). Wattage history is kept in-memory for 30 minutes only — anything older lives in SQLite.

### Data sources

- **Mac battery** ([BatteryMonitor/BatteryReader.swift](BatteryMonitor/BatteryReader.swift)): matches the `AppleSmartBattery` IOService and reads its CFProperties dictionary directly (not IOPowerSources). Prefers `AppleRawMaxCapacity` / `AppleRawCurrentCapacity` over the user-facing `MaxCapacity` / `CurrentCapacity` so health is reported from gas-gauge data, not the throttled values shown in System Settings. Caps health at 100 % (raw FCC can exceed design briefly on new packs).
- **iOS / iPadOS** ([BatteryMonitor/IOSDeviceReader.swift](BatteryMonitor/IOSDeviceReader.swift)): shells out to `idevice_id`, `ideviceinfo`, `idevicediagnostics` from libimobiledevice. Searches `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin` — if none are present, `libimobileMissing` is set and the UI shows install instructions. Cycle/health are obtained by parsing the XML plist returned from `idevicediagnostics ioregentry AppleSmartBattery|IOPMPowerSource|AppleARMPMUCharger`. The basic charge-percent path uses `ideviceinfo -q com.apple.mobile.battery` colon-KV output.
- **System temps** ([BatteryMonitor/SystemTemperatures.swift](BatteryMonitor/SystemTemperatures.swift)): uses **private SPI** (`IOHIDEventSystemClientCreate`, `IOHIDServiceClientCopyEvent`, etc.) imported via `@_silgen_name`. These are not in any public framework header; the symbols are resolved at link time against IOKit. Treat this file as fragile — Apple can break it across macOS versions.
- **Health forecast / anomaly** ([BatteryMonitor/HealthAnalytics.swift](BatteryMonitor/HealthAnalytics.swift)): least-squares linear regression over health samples to project the date health crosses 80 %, plus a simpler windowed delta check for sudden drops.
- **Adapter classification** ([BatteryMonitor/AdapterDatabase.swift](BatteryMonitor/AdapterDatabase.swift)): hardcoded sets of Apple / MFi `FamilyCode` values. Update these sets when new adapters need to be classified.

### Persistence

- **History DB**: raw SQLite C API in [BatteryMonitor/HistoryStore.swift](BatteryMonitor/HistoryStore.swift) (singleton `HistoryStore.shared`, all writes serialized through its private `DispatchQueue`). Single `snapshots` table keyed by `device_id` (`"mac"` for the host, UDID for iOS devices). Lives at `~/Library/Application Support/DoctorBattery/history.sqlite`. Note the `SQLITE_TRANSIENT` shim at the top — required because Swift can't import the `-1` C macro directly.
- **Preferences**: `SettingsModel.shared` (in [BatteryMonitor/SettingsView.swift](BatteryMonitor/SettingsView.swift)) wraps `UserDefaults`; keys are listed in `SettingsKeys`. Launch-at-login uses `SMAppService` (modern API, requires the `ServiceManagement` framework that's already in the link line).
- **Notifications**: [BatteryMonitor/Notifier.swift](BatteryMonitor/Notifier.swift) wraps `UNUserNotificationCenter` with a 30-minute per-key cooldown to prevent spam; cycle-count milestones bypass cooldown via `noCooldown: true`.

### UI

[BatteryMonitor/ContentView.swift](BatteryMonitor/ContentView.swift) is a single ~1700-line file holding `AppViewModel`, sidebar, all per-device detail views, and chart components. The `Selection` enum (`.mac`, `.ios(udid)`, `.compare`) drives the right pane. The app also ships a `MenuBarExtra` (window-style) defined in [BatteryMonitor/BatteryMonitorApp.swift](BatteryMonitor/BatteryMonitorApp.swift).

Localization lives in `BatteryMonitor/Resources/{it,en}.lproj/`. Italian is the `CFBundleDevelopmentRegion`, so untranslated `LocalizedStringKey`s fall back to Italian. `build.sh` copies both lproj directories into the bundle's `Resources/`.

## Privacy invariant

The README promises no network calls, no telemetry, no analytics. **Do not add any** — it is a load-bearing product claim. All data stays in `~/Library/Application Support/DoctorBattery/`.
