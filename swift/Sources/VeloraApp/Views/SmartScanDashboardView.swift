import SwiftUI

public struct SmartScanDashboardView: View {
    @Bindable public var viewModel: VeloraViewModel

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GeometryReader { geometry in
            let pageWidth = min(geometry.size.width, 1120)
            let inset: CGFloat = pageWidth >= 700 ? 28 : 18
            let contentWidth = pageWidth - 2 * inset

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Overview")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(VeloraTheme.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    SmartScanHeroView(viewModel: viewModel)

                    storagePanel(sideBySide: contentWidth >= 620)

                    tools(columnCount: contentWidth >= 790 ? 3 : contentWidth >= 490 ? 2 : 1)
                }
                .padding(.horizontal, inset)
                .padding(.top, inset)
                .padding(.bottom, 28)
                .frame(width: pageWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(VeloraTheme.obsidianBase)
    }

    private func storagePanel(sideBySide: Bool) -> some View {
        let storage = viewModel.storageReconciliation
        let totalBytes = storage?.containerTotalBytes ?? 0
        let freeBytes = min(storage?.containerFreeBytes ?? 0, totalBytes)
        let usedBytes = totalBytes - freeBytes

        return Group {
            if let storage, totalBytes > 0 {
                let layout = sideBySide
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 32))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))

                layout {
                    LinearStorageGaugeCardView(totalBytes: totalBytes, freeBytes: freeBytes)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !sideBySide {
                        Divider().overlay(VeloraTheme.cardBorder)
                    }

                    StorageBreakdownView(storage: storage, usedBytes: usedBytes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Startup Disk", systemImage: "internaldrive")
                        .font(.headline)
                        .foregroundStyle(VeloraTheme.textPrimary)

                    if viewModel.isReconcilingStorage {
                        ProgressView("Reading disk usage…")
                            .controlSize(.small)
                    } else {
                        Text("Disk usage is unavailable.")
                    }
                }
                .foregroundStyle(VeloraTheme.textSecondary)
            }
        }
        .padding(sideBySide ? 24 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [VeloraTheme.obsidianSurface, VeloraTheme.obsidianElevated],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(VeloraTheme.cardBorder)
        }
    }

    private func tools(columnCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage Tools")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(VeloraTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount),
                spacing: 12
            ) {
                tool("Build Junk", detail: "Build outputs and dependencies",
                     icon: "gearshape.2", color: VeloraTheme.accentViolet, destination: "tool_dev_artifacts")
                tool("App Leftovers", detail: "Files left by removed apps",
                     icon: "trash", color: VeloraTheme.accentPink, destination: "tool_orphans")
                tool("Xcode Storage", detail: "Simulators, archives and build data",
                     icon: "hammer", color: VeloraTheme.accentEmerald, destination: "tool_xcode")
                tool("Package Caches", detail: "Downloaded packages",
                     icon: "shippingbox", color: VeloraTheme.accentAmber, destination: "tool_package_caches")
                tool("AI Models", detail: "Local models and weights",
                     icon: "sparkles.rectangle.stack", color: VeloraTheme.accentPurple, destination: "tool_ai_models")
                tool("Duplicate Finder", detail: "Files with identical contents",
                     icon: "doc.on.doc", color: VeloraTheme.accentCyan, destination: "tool_duplicates")
            }
            .disabled(viewModel.isInteractionDisabled)
        }
    }

    private func tool(_ title: String, detail: String, icon: String, color: Color, destination: String) -> some View {
        QuickToolLauncherTile(title: title, detail: detail, icon: icon, accentColor: color) {
            viewModel.activeSidebarId = destination
        }
    }
}

// MARK: - Tool Launcher

private struct QuickToolLauncherTile: View {
    let title: String
    let detail: String
    let icon: String
    let accentColor: Color
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        let highlighted = isEnabled && isHovering

        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(accentColor)
                    .frame(width: 36, height: 36)
                    .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(VeloraTheme.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(VeloraTheme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(highlighted ? accentColor : VeloraTheme.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 72)
            .background(
                highlighted ? VeloraTheme.obsidianSurface : VeloraTheme.obsidianElevated,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(highlighted ? accentColor.opacity(0.45) : VeloraTheme.cardBorder)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .onHover { isHovering = $0 }
    }
}
