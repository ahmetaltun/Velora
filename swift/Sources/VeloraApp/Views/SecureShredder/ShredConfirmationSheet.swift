import SwiftUI
import VeloraCore

public struct ShredConfirmationSheet: View {
    @Bindable public var viewModel: VeloraViewModel
    @Binding public var isPresented: Bool
    @State private var hasAcknowledgedWarning: Bool = false

    public init(viewModel: VeloraViewModel, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self._isPresented = isPresented
    }

    private var itemCount: Int {
        viewModel.shredQueue.count
    }

    private var totalBytesFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(viewModel.shredQueueTotalSize), countStyle: .file)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Danger Banner
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#DC2626").opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color(hex: "#EF4444"))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Permanent File Destruction")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text("This operation completely bypasses Trash and is mathematically irreversible.")
                        .font(.system(size: 12))
                        .foregroundColor(VeloraTheme.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider().overlay(VeloraTheme.cardBorder)

            // Content Summary Card
            VStack(alignment: .leading, spacing: 14) {
                // Overview metrics pill row
                HStack(spacing: 12) {
                    MetricMiniPill(
                        label: "Targets",
                        value: "\(itemCount) item\(itemCount == 1 ? "" : "s")",
                        systemImage: "doc.fill"
                    )
                    MetricMiniPill(
                        label: "Total Size",
                        value: totalBytesFormatted,
                        systemImage: "internaldrive.fill"
                    )
                    MetricMiniPill(
                        label: "Sanitization",
                        value: "\(viewModel.selectedShredAlgorithm.totalPassesCount) Passes",
                        systemImage: "shield.checkered"
                    )
                }

                // Algorithm detail note
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundColor(VeloraTheme.accentCyan)
                        Text(viewModel.selectedShredAlgorithm.title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(VeloraTheme.textPrimary)
                    }
                    Text(viewModel.selectedShredAlgorithm.description)
                        .font(.system(size: 11))
                        .foregroundColor(VeloraTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(VeloraTheme.cardBorder, lineWidth: 1))

                // Scrollable targets list preview
                Text("Target items queued for sanitization:")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(VeloraTheme.textMuted)

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(viewModel.shredQueue) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.isDir ? "folder.fill" : "doc.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(item.isDir ? VeloraTheme.accentAmber : VeloraTheme.accentCyan)

                                Text(item.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(VeloraTheme.textPrimary)
                                    .lineLimit(1)

                                Spacer()

                                Text(ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(VeloraTheme.textMuted)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(VeloraTheme.obsidianSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(maxHeight: 140)

                // Mandatory acknowledgment toggle
                HStack(alignment: .top, spacing: 9) {
                    Toggle("", isOn: $hasAcknowledgedWarning)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .padding(.top, 1)

                    Text("I acknowledge that these items will be permanently sanitized and can never be recovered.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(VeloraTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    hasAcknowledgedWarning.toggle()
                }
                .padding(.top, 4)
            }
            .padding(24)

            Divider().overlay(VeloraTheme.cardBorder)

            // Actions Footer
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(VeloraTheme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(VeloraTheme.obsidianSurface, in: Capsule())
                .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))

                Spacer()

                Button(action: {
                    isPresented = false
                    viewModel.startShredding()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Permanently Destroy (\(itemCount))")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        hasAcknowledgedWarning
                            ? LinearGradient(
                                colors: [Color(hex: "#EF4444"), Color(hex: "#B91C1C")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        in: Capsule()
                    )
                    .shadow(
                        color: hasAcknowledgedWarning ? Color(hex: "#EF4444").opacity(0.4) : Color.clear,
                        radius: 8,
                        x: 0,
                        y: 3
                    )
                }
                .buttonStyle(.plain)
                .disabled(!hasAcknowledgedWarning)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(VeloraTheme.obsidianElevated)
        }
        .frame(width: 540)
        .background(VeloraTheme.obsidianBase)
    }
}

private struct MetricMiniPill: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
                .foregroundColor(VeloraTheme.accentPink)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(VeloraTheme.textMuted)
                Text(value)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(VeloraTheme.cardBorder, lineWidth: 1))
    }
}
