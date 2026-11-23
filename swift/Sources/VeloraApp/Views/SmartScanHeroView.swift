import SwiftUI

public struct SmartScanHeroView: View {
    @Bindable public var viewModel: VeloraViewModel

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var detail: String {
        if viewModel.isLoadingSnapshot || viewModel.isScanning {
            return "Browse and search indexed files."
        }
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
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [VeloraTheme.accentViolet.opacity(0.07), VeloraTheme.obsidianElevated],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(VeloraTheme.cardBorder)
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

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(VeloraTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if viewModel.isLoadingSnapshot {
            ToolActionProgress(title: "Loading Catalog…")
        } else if viewModel.isScanning {
            ToolActionProgress(title: "Indexing Files…")
        } else if viewModel.hasIndexedData {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    catalogActions
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 8) {
                    catalogActions
                }
            }
            .disabled(viewModel.isInteractionDisabled)
        } else {
            Button("Scan Home Folder", systemImage: "magnifyingglass", action: viewModel.scanCatalog)
                .buttonStyle(ToolActionButtonStyle(prominent: true))
                .disabled(viewModel.isInteractionDisabled)
        }
    }

    @ViewBuilder
    private var catalogActions: some View {
        Button("Browse Files", systemImage: "folder", action: viewModel.navigateToRoot)
            .buttonStyle(ToolActionButtonStyle(prominent: true))

        Button("Rescan Catalog", systemImage: "arrow.clockwise", action: viewModel.scanCatalog)
            .buttonStyle(ToolActionButtonStyle())
    }
}
