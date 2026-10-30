import SwiftUI
import AppKit

@main
struct DailyLogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var trackingVM = TrackingViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(trackingVM: trackingVM)
        } label: {
            MenuBarLabel(trackingVM: trackingVM, monitor: trackingVM.systemMonitor)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // If fans were forced to a manual speed, give them back to macOS before we go away.
        FanController.shared.shutdown()
    }
}
