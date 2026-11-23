import SwiftUI
import VeloraCore

/// Optional inspector: surfaces staged files and provides direct cleanup confirmation.
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
            HStack(spacing: 8) {
                Label("Cleanup Basket", systemImage: "tray")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(VeloraTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                if !viewModel.collectorItems.isEmpty {
                    Button("Clear") { viewModel.clearCollector() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(viewModel.isInteractionDisabled)
                        .help("Remove all items from the basket")
                }
            }
            .padding(16)

            Divider().overlay(VeloraTheme.cardBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    if let error = viewModel.cleaningErrorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button("Dismiss", systemImage: "xmark") {
                                viewModel.cleaningErrorMessage = nil
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                        }
                        .font(.caption)
                        .foregroundStyle(VeloraTheme.accentAmber)
                        .padding(10)
                        .background(VeloraTheme.accentAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if viewModel.collectorItems.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("No staged items")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(VeloraTheme.textPrimary)
                            Text("Stage files from any tool to review them here.")
                                .font(.caption)
                                .foregroundStyle(VeloraTheme.textSecondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("\(viewModel.collectorItems.count.formatted()) staged · \(stagedBytes)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(VeloraTheme.textSecondary)

                        ForEach(viewModel.collectorItems, id: \.path) { item in
                            itemRow(item)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().overlay(VeloraTheme.cardBorder)

            FreeSpaceButton(
                itemCount: viewModel.collectorItems.count,
                totalBytes: viewModel.collectorTotalSize,
                isFullWidth: true,
                isDisabled: viewModel.isInteractionDisabled || viewModel.isCleaning || viewModel.collectorItems.isEmpty,
                isCleaning: viewModel.isCleaning
            ) {
                viewModel.cleanStagedItems()
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VeloraTheme.obsidianSidebar)
    }

    private func itemRow(_ item: CollectedFile) -> some View {
        HStack(spacing: 9) {
            Image(systemName: item.isDir ? "folder.fill" : "doc.fill")
                .foregroundStyle(VeloraTheme.accentCyan)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text((item.path as NSString).lastPathComponent)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(VeloraTheme.textPrimary)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: item.sizeBytes), countStyle: .file))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(VeloraTheme.textSecondary)
            }
            .help(item.path)

            Spacer(minLength: 0)

            Button("Remove from Basket", systemImage: "xmark.circle.fill") {
                viewModel.removeCollected(path: item.path)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(VeloraTheme.textSecondary)
            .disabled(viewModel.isInteractionDisabled)
            .help("Remove from basket without deleting the file")
        }
        .padding(9)
        .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 8))
    }
}
