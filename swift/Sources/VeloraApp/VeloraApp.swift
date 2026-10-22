import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        configureAndCenterWindows()

        // Ensure asynchronously restored or created windows are also sized and centered
        DispatchQueue.main.async { [weak self] in
            self?.configureAndCenterWindows()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private func configureAndCenterWindows() {
        for window in NSApp.windows {
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(red: 22/255.0, green: 25/255.0, blue: 46/255.0, alpha: 1.0)
            window.toolbar?.showsBaselineSeparator = false

            // Set minimum window bounds
            window.minSize = NSSize(width: VeloraTheme.minWindowWidth, height: VeloraTheme.minWindowHeight)

            // Ensure window is at least the minimum size
            var frame = window.frame
            if frame.width < VeloraTheme.minWindowWidth || frame.height < VeloraTheme.minWindowHeight {
                frame.size.width = max(frame.width, VeloraTheme.minWindowWidth)
                frame.size.height = max(frame.height, VeloraTheme.minWindowHeight)
                window.setFrame(frame, display: true)
            }

            // Center window on screen at startup
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct VeloraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Velora") {
            MainWindowView()
                .frame(
                    minWidth: VeloraTheme.minWindowWidth,
                    idealWidth: VeloraTheme.minWindowWidth,
                    minHeight: VeloraTheme.minWindowHeight,
                    idealHeight: VeloraTheme.minWindowHeight
                )
                .background(VeloraTheme.obsidianBase)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .defaultSize(width: VeloraTheme.minWindowWidth, height: VeloraTheme.minWindowHeight)
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
