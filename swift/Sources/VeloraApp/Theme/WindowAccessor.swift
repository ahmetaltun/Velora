import AppKit
import SwiftUI

public struct WindowAccessor: NSViewRepresentable {
    public let configure: (NSWindow) -> Void

    public init(configure: @escaping (NSWindow) -> Void) {
        self.configure = configure
    }

    public final class Coordinator {
        var hasConfigured = false
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window, !context.coordinator.hasConfigured {
                context.coordinator.hasConfigured = true
                self.configure(window)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if !context.coordinator.hasConfigured, let window = nsView.window {
            context.coordinator.hasConfigured = true
            DispatchQueue.main.async {
                self.configure(window)
            }
        }
    }
}
