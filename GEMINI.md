# DailyLog - Project Overview

DailyLog is a macOS Menu Bar application designed to help users track their productivity through automated app usage monitoring and a built-in focus timer, all while incorporating gamification elements to keep users engaged.

## Core Features
- **App Usage Tracking:** Automatically monitors the active (frontmost) application and records time spent. Data is reset daily.
- **System Monitoring:** Real-time monitoring of CPU, RAM, GPU, Disk, Temperature, and Network directly in the menu bar.
- **Gamification:**
    - **Levels & EXP:** Earn 1 EXP for every minute spent on any application. Track your progress through levels based on total lifetime usage.
- **Menu Bar Integration:** Runs entirely from the macOS menu bar for a non-intrusive experience.

## Technology Stack
- **Language:** Swift 5.10
- **Frameworks:**
    - **SwiftUI:** Used for the entire user interface.
    - **AppKit:** Used for menu bar integration (`NSMenuBarExtra`), app tracking (`NSWorkspace`), and lifecycle management (`NSApplicationDelegate`).
    - **Combine:** Used for reactive state management within ViewModels.
- **Persistence:** `UserDefaults` with `JSONEncoder`/`JSONDecoder` for storing game state and daily usage data.

## Project Structure
- `Sources/DailyLog/`
    - `DailyLogApp.swift`: App entry point and Menu Bar configuration.
    - `Models/`: Data structures (`AppUsage`, `GameState`, `HonorPet`).
    - `ViewModels/`: Business logic and state management (`TrackingViewModel`, `FocusTimerViewModel`).
    - `Views/`: SwiftUI views for the menu bar interface (`MenuBarView`).
- `Package.swift`: Swift Package Manager configuration.
- `Info.plist`: Application metadata.
- `build.sh`: Shell script for building and packaging the app bundle.

## Building and Running

### Build from Terminal
To build the project using Swift Package Manager:
```bash
swift build -c release
```

### Package as .app Bundle
Run the provided build script to create a standalone macOS application:
```bash
./build.sh
```
This will generate `DailyLog.app` in the root directory.

### Running Tests
To run the automated test suite:
```bash
swift test
```
This will execute logic tests for system monitoring and data management.

## Development Conventions
- **MVVM Architecture:** Logic should be kept in ViewModels (`TrackingViewModel`, `FocusTimerViewModel`), while Views remain declarative.
- **State Management:** Use `@StateObject` and `@Published` for reactive UI updates.
- **Tracking Logic:** The `TrackingViewModel` uses a 1-second timer to poll for the frontmost application.
- **Persistence:** Ensure any new game state or tracking data is added to the `saveState()` and `loadState()` methods in `TrackingViewModel`.
- **Navigation & Confirmation Convention (CRITICAL):**
    - **NO NATIVE POPUPS:** Never use `.sheet()`, `.fullScreenCover()`, or system `.alert()`.
    - **WHY:** In `MenuBarExtra` (.window style), dismissing any native popup (even a simple alert) kills the main window process, causing the app to disappear.
    - **THE SOLUTION (View Switching):** Use `@State` flags and `if/else` blocks to swap views inside the main `VStack`.
    - **THE SOLUTION (Custom Overlays):** For confirmations (like Reset Data), use a `ZStack` with a custom-designed overlay card and a dimmed background instead of a system alert.
