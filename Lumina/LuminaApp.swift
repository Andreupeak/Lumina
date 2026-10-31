import SwiftUI

@main
struct LuminaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var controller = AutoBacklightController.shared

    var body: some Scene {
        #if DEBUG && LUMINA_UI_TESTING
        WindowGroup("Lumina UI Test") {
            ContentView()
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--light") ? .light : .dark)
        }
        .windowResizability(.contentSize)
        #else
        MenuBarExtra("Lumina", systemImage: controller.isNightMode
                     ? "moon.stars.fill" : "sun.max.fill") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(AppRuntime.isUITesting ? .regular : .accessory)
        AutoBacklightController.shared.startMonitoring()
        if !AppRuntime.isUITesting {
            SunScheduleManager.shared.refreshLocationOnceAtStartup()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AutoBacklightController.shared.stopMonitoring()
        if AppRuntime.isUITesting {
            UserDefaults.standard.removePersistentDomain(forName: "Lumina.UITesting")
        }
    }
}
