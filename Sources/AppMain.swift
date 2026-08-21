import SwiftUI

@main
struct FreeAppStoreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Free App Store") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1120, height: 740)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // We cache verification verdicts ourselves; keep HTTP caching off.
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
