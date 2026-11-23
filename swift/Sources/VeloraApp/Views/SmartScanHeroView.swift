import SwiftUI

public struct SmartScanHeroView: View {
    @Bindable public var viewModel: VeloraViewModel

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var status: String {
        if viewModel.isLoadingSnapshot { return "Loading your saved catalog…" }
        if viewModel.isScanning { return "Indexing files…" }
        if viewModel.hasIndexedData {
            let count = viewModel.scannedCount
            return count == 1 ? "1 item indexed" : "\(count.formatted()) items indexed"
        }
        return "Scan your home folder to browse and search files."
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                summary
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                actions
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 12) {
                summary
                actions
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(VeloraTheme.cardBorder)
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(VeloraTheme.accentViolet)
                .frame(width: 38, height: 38)
                .background(VeloraTheme.accentViolet.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("File Catalog")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(VeloraTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(status)
                    .font(.callout)
                    .foregroundStyle(VeloraTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if viewModel.isLoadingSnapshot {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Loading file catalog")
        } else if !viewModel.isScanning {
            HStack(spacing: 8) {
                if viewModel.hasIndexedData {
                    Button("Browse Files", systemImage: "folder") {
                        viewModel.navigateToRoot()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VeloraTheme.accentViolet)

                    Button("Rescan Catalog", systemImage: "arrow.clockwise") {
                        viewModel.scanCatalog()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Scan Home Folder", systemImage: "magnifyingglass") {
                        viewModel.scanCatalog()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VeloraTheme.accentViolet)
                }
            }
            .controlSize(.large)
            .disabled(viewModel.isInteractionDisabled)
        }
    }
}
