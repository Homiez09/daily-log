# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DailyLog is a macOS menu bar productivity tracker built with Swift Package Manager (no Xcode project). It runs entirely from `NSMenuBarExtra`, tracks time spent in user-designated "productive" apps, and gamifies that time into levels/EXP. It also renders a live system monitor (CPU/GPU/RAM/disk/temp/fans/network) in the menu bar and in an expanded dashboard, and can override fan speed through a root helper.

## Commands

```bash
swift build -c release   # build
swift test                # run the test suite (Tests/DailyLogTests)
./build.sh                 # release build + package into DailyLog.app (via scripts/bundle.sh), then opens it
swift scripts/make_icon.swift  # regenerate Resources/AppIcon.icns from Resources/AppIcon.icon (needs Xcode's ictool)
./make_dmg.sh               # runs build.sh, then packages DailyLog.app into DailyLog.dmg
./release.sh <version>       # e.g. ./release.sh 1.1.0 — bumps Info.plist version, builds,
                              # ad-hoc codesigns, zips DailyLog.app, commits+tags+pushes,
                              # and publishes a GitHub Release with the zip attached
```

To run a single test, use XCTest filtering:
```bash
swift test --filter DailyLogTests.SystemMonitorTests/testRAMCalculations
```

There is no lint/format tooling configured in this repo.

## Architecture

**Swift Package Manager layout**, not an Xcode project. `Package.swift` targets: `CSMC` (C struct layout for the AppleSMC user client), `HardwareKit` (Swift: SMC read/write, IOHID temperature sensors, fan curve/protocol/safety, Unix-socket helpers — shared by the app and the helper), `DailyLog` (the app), `DailyLogFanHelper` (root helper executable) and the `DailyLogTests` test target. `Info.plist` (repo root) and `Resources/AppIcon.icns` are copied into the bundle by `scripts/bundle.sh` (called by `build.sh` and `release.sh`), not managed by Xcode build settings. The helper is bundled next to the main binary in `Contents/MacOS`.

**MVVM with two independent `ObservableObject` managers, composed at the app root:**
- `DailyLogApp.swift` — `@main` entry point. Declares the `MenuBarExtra` scene (`.menuBarExtraStyle(.window)`), owns the single `TrackingViewModel` instance, and `AppDelegate` (restores automatic fan control in `applicationWillTerminate`).
- `Views/MenuBarLabel.swift` — the status-item label. `MenuBarExtra` only draws plain `Text`/`Image` in its label (shapes/gauges are silently dropped), so `MenuBarLabel` rasterises `MenuBarLabelContent` with `ImageRenderer` into an `NSImage`. Monochrome mode sets `isTemplate = true` (drawn in black; the system tints it), coloured mode is a normal image. Shows `menuBarLeading` and, if `showTrailingMetric`, `menuBarTrailing`.
- `ViewModels/TrackingViewModel.swift` — the central state/business-logic object. Owns `GameState` (persisted), a 1-second polling `Timer` (`tick()`) that reads `NSWorkspace.shared.frontmostApplication` to attribute time to the active app, accumulates EXP every 60 pending seconds, and handles the app-icon cache (`iconCache`) to avoid triggering SwiftUI redraws on every tick. Also owns a `SystemMonitorManager` instance (`trackingVM.systemMonitor`) and `fanController`. `@Published` fires on every assignment even for equal values — guard assignments in `tick()` so the popover and menu bar image are not re-rendered every second for nothing.
- `Managers/SystemMonitorManager.swift` — a separate `ObservableObject` polling on its own 2-second `Timer`, independent of `TrackingViewModel`'s tracking loop. Values follow the system tools: CPU = `host_processor_info` tick diffs (per-core array always has one entry per core so it stays aligned with `coreTypes`, which is derived from `hw.perflevelN.*` sysctls); RAM = Activity Monitor's definition (App = internal − purgeable, + wired + compressed; *not* `active`), with the breakdown and `kern.memorystatus_vm_pressure_level`; GPU = max `Device Utilization %` of `IOAccelerator`; disk = `URLResourceValues` (matches Finder, counts purgeable as available); network = 64-bit counters from `sysctl NET_RT_IFLIST2` for `en*` interfaces (the `getifaddrs` counters are 32-bit and wrap), stored as bytes/second; temperature = average of the `PMU tdie*` IOHID sensors via `HardwareKit.ThermalSensors` — **`nil` when unavailable, never a made-up number**; fans = `SMCConnection.readFans()`; per-app CPU/RAM (`updateProcesses`, `proc_pid_rusage(RUSAGE_INFO_V4)`) sorted into `SystemStats.topProcesses`. Both timers are added to `RunLoop.current` with `.common` mode so they keep firing while the popover menu is open.
- `Managers/FanController.swift` — app-side client of the fan helper. Reading fan RPM needs no privileges; *changing* it requires writing SMC keys as root. First manual request runs `osascript ... with administrator privileges` to start `DailyLogFanHelper --uid <uid>`, which listens on `/var/run/com.user.DailyLog.fan.<uid>.sock` (0600, owned by the user) and speaks `AUTO` / `MANUAL <0-1>` / `PING`. The app pings every 3 s; the helper restores automatic mode when the app disconnects, goes silent for 10 s, gets a signal, or the die reaches 95 °C. `fanControlMode` is reset to `.auto` on every load (manual needs a fresh admin approval per launch). The manual write path (root, SMC `F<n>Md`/`F<n>Tg`, optional `Ftst` unlock) is **not exercised by the automated tests** — they cover the curve, codecs, protocol and safety rules, and read-only hardware access.
- `Models/GameModels.swift` — pure data/`Codable` types persisted as JSON in `UserDefaults` (keys `"GameState"`, `"CurrentDay"`), no I/O. `GameState.level`/`exp`/`requiredExpForNextLevel` are all derived from `totalLifetimeExp` via a level curve (`calculateLevelAndProgress`, `C = 60`), not stored directly — don't add stored `level`/`exp` fields. Custom `Codable init(from:)` decodes older/partial JSON gracefully with `decodeIfPresent` fallbacks for everything except `totalLifetimeExp`.
- `Views/` — `MenuBarView` (main popover, switches between dashboard/`HistoryView`/`SettingsView` via `@State` bools, not `NavigationStack`; the dashboard `ScrollView` is sized to its measured content, capped by screen height), `SystemDashboardView`, `HistoryView`, `SettingsView` (incl. `FanControlSection`), `Theme.swift` (`Palette`, `Format`, `glassCard`/`glassCapsule`/`GlassGroup`/`popoverBackground`), `Charts.swift`, `AppLogoView.swift`.

**Liquid Glass & GPU cost:** the popover window itself is system Liquid Glass on macOS 26+ (a solid fill before, via `popoverBackground`). Every extra `glassEffect` on top of it makes WindowServer re-sample and re-refract whatever is behind the window on every frame — with a live video wallpaper (Aerial) that is real GPU time, multiplied by the number of glass layers. So cards use a cheap translucent fill by default (`glassCard` in `Theme.swift`, via `CardSurface`), and real glass cards are opt-in: `UISettings.liquidGlassCards` (Settings ▸ Appearance, macOS 26+ only), injected into the view tree as `EnvironmentValues.glassCardsEnabled` by `MenuBarView`. `GlassGroup` only creates a `GlassEffectContainer` when that is on. Chips (`tintedCapsule`) are never glass (no glass-on-glass). The deployment target stays macOS 13. **Do not add continuous or data-driven animation** (`TimelineView(.animation)`, `repeatForever`, `.animation(_, value:)` on values that change every poll): it is rendered by the render server so the app's own CPU/run-loop counters barely show it, but it forces the whole glass group to re-render; a 30 fps spinning fan icon measured ~40 % of a core with the popover open (vs ~4 % without). The app process itself uses ~0 % GPU (check with the IORegistry `AppUsage`/`accumulatedGPUTime` of its client); the cost that matters is WindowServer's. Measuring it on a machine with other GPU activity is very noisy — compare several interleaved runs over a moving backdrop and calibrate (e.g. add 25 extra glass layers and confirm the setup sees them) before trusting a difference.

**Persistence convention:** all persisted state lives in `GameState`, saved/loaded only from `TrackingViewModel.saveState()`/`loadState()`. When adding new persisted fields, add them to `GameState`, and to its `CodingKeys` + `init(from:)` fallback if they must remain backward-compatible with previously saved JSON (see `exportAsJSON`/`importFromJSON` for the user-facing JSON import/export path).

**Menu bar popup navigation (important, macOS-specific constraint):** Never use `.sheet()`, `.fullScreenCover()`, or system `.alert()`. In a `MenuBarExtra` with `.menuBarExtraStyle(.window)`, dismissing any native popup tears down the window and the app appears to vanish. Instead:
- View switching: toggle `@State` booleans and swap views inside the root `VStack` (see how `MenuBarView` swaps between the dashboard, `HistoryView`, and `SettingsView`).
- Confirmations: use a `ZStack` with a custom overlay card + dimmed background instead of a system alert (e.g. the Reset Data confirmation).

## Tests

`HardwareKitTests.swift`, `SettingsModelTests.swift` — pure-logic tests (fan curve, SMC value codecs, protocol parsing, safety rules, settings backward compatibility, formatting) plus read-only checks against the real SMC/IOHID that `XCTSkip` on Macs without fans/sensors. Never write SMC keys from a test.

`Tests/DailyLogTests/SystemMonitorTests.swift` instantiates a real `SystemMonitorManager` and asserts against actual host stats (real RAM/disk values) with `XCTestExpectation` + `DispatchQueue.main.asyncAfter`, since `refreshStats()` dispatches its `@Published` update to the main queue asynchronously. Follow this pattern (real system calls, not mocks) for new manager tests.
