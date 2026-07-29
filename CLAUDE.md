# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DailyLog is a macOS menu bar productivity tracker built with Swift Package Manager (no Xcode project). It runs entirely from `NSMenuBarExtra`, tracks time spent in user-designated "productive" apps, and gamifies that time into levels/EXP. It also renders a live system monitor (CPU/GPU/RAM/disk/temp/network) in the menu bar and in an expanded dashboard.

## Commands

```bash
swift build -c release   # build
swift test                # run the test suite (Tests/DailyLogTests)
./build.sh                 # release build + package into DailyLog.app, then opens it
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

**Swift Package Manager layout**, not an Xcode project: `Package.swift` defines an executable target `DailyLog` at `Sources/DailyLog` and a test target at `Tests/DailyLogTests`. `Info.plist` (repo root) is copied into the bundle by `build.sh`, not managed by Xcode build settings.

**MVVM with two independent `ObservableObject` managers, composed at the app root:**
- `DailyLogApp.swift` — `@main` entry point. Declares the `MenuBarExtra` scene (`.menuBarExtraStyle(.window)`), owns the single `TrackingViewModel` instance, and renders the compact menu bar label (`MenuBarAdvancedLabel`/`MetricRow`) showing two configurable metrics (`uiSettings.menuBarLeading`/`menuBarTrailing`) side by side in the menu bar itself.
- `ViewModels/TrackingViewModel.swift` — the central state/business-logic object. Owns `GameState` (persisted), a 1-second polling `Timer` (`tick()`) that reads `NSWorkspace.shared.frontmostApplication` to attribute time to the active app, accumulates EXP every 60 pending seconds, and handles the app-icon cache (`iconCache`) to avoid triggering SwiftUI redraws on every tick. Also owns a `SystemMonitorManager` instance (`trackingVM.systemMonitor`).
- `Managers/SystemMonitorManager.swift` — a separate `ObservableObject` polling on its own 2-second `Timer`, independent of `TrackingViewModel`'s tracking loop. Reads CPU (via `host_processor_info`/Mach APIs, diffed against the previous sample), RAM (`host_statistics64`), GPU (`IOAccelerator` IOKit registry), disk (`URLResourceValues`), network throughput (diffed `getifaddrs` byte counters), and thermal state (`ProcessInfo.thermalState`, since macOS has no public per-degree sensor API — see `updateTemperature`). Both timers are added to `RunLoop.current` with `.common` mode so they keep firing while the popover menu is open.
- `Models/GameModels.swift` — pure data/`Codable` types persisted as JSON in `UserDefaults` (keys `"GameState"`, `"CurrentDay"`), no I/O. `GameState.level`/`exp`/`requiredExpForNextLevel` are all derived from `totalLifetimeExp` via a level curve (`calculateLevelAndProgress`, `C = 60`), not stored directly — don't add stored `level`/`exp` fields. Custom `Codable init(from:)` decodes older/partial JSON gracefully with `decodeIfPresent` fallbacks for everything except `totalLifetimeExp`.
- `Views/` — `MenuBarView` (main popover, switches between dashboard/`HistoryView`/`SettingsView` via `@State` bools, not `NavigationStack`), `HistoryView`, `SettingsView`.

**Persistence convention:** all persisted state lives in `GameState`, saved/loaded only from `TrackingViewModel.saveState()`/`loadState()`. When adding new persisted fields, add them to `GameState`, and to its `CodingKeys` + `init(from:)` fallback if they must remain backward-compatible with previously saved JSON (see `exportAsJSON`/`importFromJSON` for the user-facing JSON import/export path).

**Menu bar popup navigation (important, macOS-specific constraint):** Never use `.sheet()`, `.fullScreenCover()`, or system `.alert()`. In a `MenuBarExtra` with `.menuBarExtraStyle(.window)`, dismissing any native popup tears down the window and the app appears to vanish. Instead:
- View switching: toggle `@State` booleans and swap views inside the root `VStack` (see how `MenuBarView` swaps between the dashboard, `HistoryView`, and `SettingsView`).
- Confirmations: use a `ZStack` with a custom overlay card + dimmed background instead of a system alert (e.g. the Reset Data confirmation).

## Tests

`Tests/DailyLogTests/SystemMonitorTests.swift` instantiates a real `SystemMonitorManager` and asserts against actual host stats (real RAM/disk values) with `XCTestExpectation` + `DispatchQueue.main.asyncAfter`, since `refreshStats()` dispatches its `@Published` update to the main queue asynchronously. Follow this pattern (real system calls, not mocks) for new manager tests.
