#if !arch(arm64)
#error("Velora is designed exclusively for Apple Silicon (ARM64) macOS devices running macOS 15 (Sequoia) or later.")
#endif

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard #available(macOS 15.0, *) else {
            let alert = NSAlert()
            alert.messageText = "Unsupported macOS Version"
            alert.informativeText = "Velora requires macOS 15 (Sequoia) or later on Apple Silicon (ARM64). The application will now terminate."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let icon = AppAssetLoader.appIcon {
            NSApp.applicationIconImage = icon
        }
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
            window.backgroundColor = NSColor(red: 32/255.0, green: 32/255.0, blue: 49/255.0, alpha: 1.0)

            // Set minimum window bounds
            window.minSize = NSSize(width: VeloraTheme.minWindowWidth, height: VeloraTheme.minWindowHeight)

            // Ensure window is at least minimum size and fits within visible screen
            if let screen = window.screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                var frame = window.frame
                frame.size.width = min(visible.width, max(frame.size.width, VeloraTheme.minWindowWidth))
                frame.size.height = min(visible.height, max(frame.size.height, VeloraTheme.minWindowHeight))
                if frame.maxY > visible.maxY {
                    frame.origin.y = visible.maxY - frame.size.height
                }
                if frame.origin.x < visible.origin.x {
                    frame.origin.x = visible.origin.x
                }
                window.setFrame(frame, display: true)
            }
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
                    minHeight: VeloraTheme.minWindowHeight
                )
                .background(VeloraTheme.obsidianBase)
                .preferredColorScheme(.dark)
                .tint(VeloraTheme.accentViolet)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1350, height: 780)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .appInfo) {
                Button("About Velora") {
                    AppAssetLoader.openAboutPanel()
                }
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesMenuItem()
            }
            CommandGroup(replacing: .newItem) {
                Button("Rescan Folder") {
                    // Rescan trigger
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            VStack(alignment: .leading, spacing: 20) {
                UpdatePreferencesCardView()
            }
            .padding(24)
            .frame(width: 540)
            .background(VeloraTheme.obsidianBase)
            .preferredColorScheme(.dark)
        }
    }
}
