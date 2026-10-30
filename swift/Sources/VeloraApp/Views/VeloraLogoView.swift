import SwiftUI
import AppKit

public enum AppAssetLoader {
    private static var cachedIcon: NSImage?

    public static var appIcon: NSImage? {
        if let cached = cachedIcon {
            return cached
        }

        // 1. Try bundle resources (e.g. inside Velora.app/Contents/Resources)
        let candidateNames = ["VeloraIcon-128", "AppIcon", "VeloraIcon-256", "VeloraIcon-512", "VeloraIcon-1024"]
        for name in candidateNames {
            if let path = Bundle.main.path(forResource: name, ofType: "png"),
               let image = NSImage(contentsOfFile: path),
               image.isValid {
                cachedIcon = image
                return image
            }
        }

        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let image = NSImage(contentsOfFile: path),
           image.isValid {
            cachedIcon = image
            return image
        }

        // 2. Query NSApplication applicationIconImage if running in bundled application
        if Bundle.main.bundlePath.hasSuffix(".app"),
           let appIcon = NSApplication.shared.applicationIconImage,
           appIcon.isValid && appIcon.size.width > 0 {
            cachedIcon = appIcon
            return appIcon
        }

        // 3. Fallback for unbundled development mode (swift run from repo root)
        let devPaths = [
            "assets/icons/VeloraIcon-128.png",
            "assets/icons/AppIcon.png",
            "assets/icons/VeloraIcon-256.png",
            "assets/icons/AppIcon.icns",
            "../assets/icons/VeloraIcon-128.png",
            "../assets/icons/AppIcon.png"
        ]
        for path in devPaths {
            if FileManager.default.fileExists(atPath: path),
               let image = NSImage(contentsOfFile: path),
               image.isValid {
                cachedIcon = image
                return image
            }
        }

        // 4. Default fallback to NSApplication icon
        if let fallback = NSApplication.shared.applicationIconImage, fallback.isValid {
            return fallback
        }

        return nil
    }

    public static func openAboutPanel() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Velora",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        ]
        if let icon = appIcon {
            options[.applicationIcon] = icon
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
}

public struct VeloraLogoView: View {
    public let size: CGFloat

    public init(size: CGFloat = 34) {
        self.size = size
    }

    public var body: some View {
        if let icon = AppAssetLoader.appIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
        } else {
            // Elegant fallback if no icon asset found
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [VeloraTheme.accentBlue, VeloraTheme.accentCyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)

                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}
