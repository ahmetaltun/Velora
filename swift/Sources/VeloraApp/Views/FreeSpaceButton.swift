import SwiftUI
import VeloraCore

/// Reusable "Free Space" action button with confirmation dialog safeguard.
/// Provides consistent styling and confirmation safeguards for both tray and inspector surfaces.
public struct FreeSpaceButton: View {
    public let itemCount: Int
    public let totalBytes: UInt64
    public let isFullWidth: Bool
    public let isDisabled: Bool
    public let isCleaning: Bool
    public let onConfirm: () -> Void

    @State private var showingConfirmation: Bool = false

    public init(
        itemCount: Int,
        totalBytes: UInt64,
        isFullWidth: Bool = false,
        isDisabled: Bool = false,
        isCleaning: Bool = false,
        onConfirm: @escaping () -> Void
    ) {
        self.itemCount = itemCount
        self.totalBytes = totalBytes
        self.isFullWidth = isFullWidth
        self.isDisabled = isDisabled
        self.isCleaning = isCleaning
        self.onConfirm = onConfirm
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: totalBytes), countStyle: .file)
    }

    public var body: some View {
        Button(action: {
            showingConfirmation = true
        }) {
            HStack(spacing: 7) {
                if isCleaning {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Trashing items...")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                } else {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Free Space")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, isFullWidth ? 9 : 6)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(
                LinearGradient(
                    colors: [VeloraTheme.accentViolet, VeloraTheme.accentPurple],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: isFullWidth ? 11 : 16, style: .continuous)
            )
            .shadow(
                color: VeloraTheme.accentViolet.opacity((isDisabled || isCleaning) ? 0.0 : 0.35),
                radius: 6,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isCleaning)
        .opacity((isDisabled && !isCleaning) ? 0.45 : 1.0)
        .alert("Move Staged Items to Trash?", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                onConfirm()
            }
        } message: {
            let countText = itemCount == 1 ? "1 item" : "\(itemCount) items"
            Text("Are you sure you want to move \(countText) (\(formattedSize)) to the Trash? You can restore them from the macOS Trash if needed.")
        }
    }
}
