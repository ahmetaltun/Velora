import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(red: 22/255.0, green: 25/255.0, blue: 46/255.0, alpha: 1.0)
            window.toolbar?.showsBaselineSeparator = false
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct VeloraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Velora") {
            MainWindowView()
                .frame(minWidth: 920, idealWidth: 1180, minHeight: 620, idealHeight: 760)
                .background(VeloraTheme.obsidianBase)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("Rescan Folder") {
                    // Rescan trigger
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
