import SwiftUI

@main
struct LuminaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var controller = AutoBacklightController.shared

    var body: some Scene {
        MenuBarExtra("Lumina", systemImage: controller.isNightMode
                     ? "moon.stars.fill" : "sun.max.fill") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AutoBacklightController.shared.startMonitoring()
        SunScheduleManager.shared.refreshLocationOnceAtStartup()
    }
}
