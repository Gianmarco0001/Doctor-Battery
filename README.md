# Doctor Battery

Open-source battery diagnostics for **macOS**, **iOS** and **iPadOS** — free alternative to commercial battery monitoring tools.

All data stays on your Mac. No telemetry. No account.

## Features

- **macOS battery**: cycle count, design / max / current capacity, raw FCC health %, voltage, current, instant + rolling watt averages, temperature, manufacture date, optimized charging state, low power mode.
- **iOS / iPadOS** (via [libimobiledevice](https://libimobiledevice.org)): same battery details over USB or Wi-Fi for paired iPhone / iPad. Reads `AppleSmartBattery` IORegistry directly.
- **Power adapter info**: wattage, manufacturer, family code with Apple-original / MFi / generic classification.
- **History**: SQLite snapshots every N minutes, charts for charge % and health % across 1h / 24h / 7d / 30d / all-time.
- **Health forecast**: linear regression on health trend, predicts the date you reach 80% and remaining cycles.
- **Anomaly detection**: alerts when health drops faster than a configurable threshold (e.g. > 2 % in 7 days).
- **Multi-device comparison**: overlapped trend charts across Mac + all connected iOS devices.
- **Menu bar**: always-on % indicator with quick stats per device.
- **Notifications**: low battery, hot battery, full charge while plugged, cycle count milestones.
- **Calibration suggestion** when no full discharge is detected for > 30 days.
- **CSV export** of history.
- **Localized** in Italian and English.

## Build

Requirements: macOS 13+, command-line tools (Swift toolchain).

```bash
git clone https://github.com/Gianmarco0001/Doctor-Battery.git
cd Doctor-Battery
./build.sh
open build/DoctorBattery.app
```

Build options:

- `UNIVERSAL=0 ./build.sh` builds for the host architecture only (faster).
- Default builds a universal arm64 + x86_64 binary.

> **Note on Intel Macs**: the universal binary is produced via `lipo` and includes both arm64 and x86_64 slices, but it has only been tested on Apple Silicon. It should work on Intel since none of the APIs used are Apple Silicon-only, but reports from Intel users are welcome — please open an issue if you try it.

## iOS / iPadOS support

Install libimobiledevice (Homebrew):

```bash
brew install libimobiledevice usbmuxd
```

- **USB**: connect the device, unlock it, accept "Trust this Mac".
- **Wi-Fi**: pair via USB once, then enable "Show this iPhone when on Wi-Fi" in Finder. Same network required.

### Limitations

- Apple Watch is **not supported** (libimobiledevice doesn't reach watchOS).
- On iOS the cycle count / capacity values come from the gas-gauge IC — same data Apple's own diagnostics use, but the value reported in Settings → Battery includes additional impedance / throttling factors. Both are valid measurements of different things.

## Distribution

The repository ships pre-built `.app` bundles in releases. They are signed ad-hoc — Gatekeeper will warn on first launch:

> "App can't be opened because Apple cannot check it for malicious software."

Right-click the `.app` → **Open** → confirm. macOS remembers the choice.

For users who want a notarized binary, see the project notes on packaging with a paid Apple Developer account.

## Architecture

- `BatteryReader.swift` — IOKit `AppleSmartBattery` query.
- `IOSDeviceReader.swift` — shells out to `idevice_id`, `ideviceinfo`, `idevicediagnostics`. Parses XML plist via `PropertyListSerialization`.
- `HistoryStore.swift` — SQLite via direct C API.
- `HealthAnalytics.swift` — least-squares regression and anomaly detection.
- `AdapterDatabase.swift` — Apple FamilyCode database.
- `Notifier.swift` — UNUserNotificationCenter wrapper with cooldown.
- `SettingsView.swift` — preferences pane with `SMAppService` autostart.

Pure Swift + SwiftUI + Swift Charts. No third-party dependencies. ~1300 lines of code.

## Privacy

- All data is stored at `~/Library/Application Support/DoctorBattery/history.sqlite`.
- No network requests. No analytics. No crash reporting.

## License

MIT — see `LICENSE`.

## Acknowledgements

This project would not exist without [libimobiledevice](https://libimobiledevice.org) (LGPL). Battery Monitor calls its CLI tools as separate processes; no library code is statically linked.
