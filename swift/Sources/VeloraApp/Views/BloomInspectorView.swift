import SwiftUI
import VeloraCore

/// Optional inspector: keeps the existing collector's five-second trash countdown
/// intact and surfaces staged files without duplicating destructive actions.
public struct BloomInspectorView: View {
    @Bindable public var viewModel: VeloraViewModel

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var stagedBytes: String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: viewModel.collectorTotalSize), countStyle: .file)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(VeloraTheme.accentViolet)
                    .frame(width: 34, height: 34)
                    .background(VeloraTheme.accentViolet.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cleanup basket")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(VeloraTheme.textPrimary)
                    Text("Review before removing")
                        .font(.system(size: 11))
                        .foregroundStyle(VeloraTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("READY TO RECLAIM")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(VeloraTheme.textMuted)
                Text(stagedBytes)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(VeloraTheme.textPrimary)
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(VeloraTheme.accentEmerald)
                    Text("\(viewModel.collectorItems.count) items staged")
                        .foregroundStyle(VeloraTheme.textSecondary)
                }
                .font(.system(size: 11, weight: .medium))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(VeloraTheme.cardBorder, lineWidth: 1))

            HStack {
                Text("IN YOUR BASKET")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.15)
                    .foregroundStyle(VeloraTheme.textMuted)
                Spacer()
                if !viewModel.collectorItems.isEmpty {
                    Button("Clear") { viewModel.clearCollector() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(VeloraTheme.accentViolet)
                }
            }
            .padding(.top, 23)
            .padding(.bottom, 11)

            if viewModel.collectorItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(VeloraTheme.accentViolet)
                        .frame(width: 56, height: 56)
                        .background(VeloraTheme.accentViolet.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    Text("A little breathing room")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(VeloraTheme.textPrimary)
                    Text("Collect files from any tool. Your picks will appear here before cleanup.")
                        .font(.system(size: 11))
                        .foregroundStyle(VeloraTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 24)
                .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(VeloraTheme.cardBorder, lineWidth: 1))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.collectorItems, id: \.path) { item in
                            HStack(spacing: 10) {
                                Image(systemName: item.isDir ? "folder.fill" : "doc.fill")
                                    .foregroundStyle(VeloraTheme.accentCyan)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text((item.path as NSString).lastPathComponent)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(VeloraTheme.textPrimary)
                                        .lineLimit(1)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: item.sizeBytes), countStyle: .file))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(VeloraTheme.textMuted)
                                }
                                Spacer(minLength: 0)
                                Button {
                                    viewModel.removeCollected(path: item.path)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(VeloraTheme.textMuted)
                                }
                                .buttonStyle(.plain)
                                .help("Remove from basket without deleting the file")
                            }
                            .padding(11)
                            .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }
                Text("Use the collector bar below the workspace to review and move staged items to Trash. Its safety countdown is unchanged.")
                    .font(.system(size: 10))
                    .foregroundStyle(VeloraTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            Spacer(minLength: 12)
            HStack(spacing: 7) {
                Circle()
                    .fill(viewModel.isScanning ? VeloraTheme.accentAmber : VeloraTheme.accentEmerald)
                    .frame(width: 7, height: 7)
                Text(viewModel.isScanning ? "Scanning your Mac" : "Storage catalog ready")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VeloraTheme.textSecondary)
                Spacer()
            }
            .padding(12)
            .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 11))
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VeloraTheme.obsidianSidebar)
    }
}
