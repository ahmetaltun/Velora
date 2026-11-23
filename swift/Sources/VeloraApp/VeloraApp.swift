#if !arch(arm64)
#error("Velora is designed exclusively for Apple Silicon (ARM64) macOS devices running macOS 15 (Sequoia) or later.")
#endif

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Runtime check: Verify native Apple Silicon (ARM64) execution without Rosetta 2 translation
        var isTranslated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("sysctl.proc_translated", &isTranslated, &size, nil, 0) == 0 && isTranslated != 0 {
            let alert = NSAlert()
            alert.messageText = "Rosetta Translation Not Supported"
            alert.informativeText = "Velora must run natively on Apple Silicon (ARM64). Rosetta 2 execution is not supported. The application will now terminate."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

}

extension Notification.Name {
    public static let veloraTriggerRescan = Notification.Name("velora_trigger_rescan")
}

@main
struct VeloraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel = VeloraViewModel()

    var body: some Scene {
        WindowGroup("Velora") {
            MainWindowView(viewModel: viewModel)
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
        .windowResizability(.contentMinSize)
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
                    NotificationCenter.default.post(name: .veloraTriggerRescan, object: nil)
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
