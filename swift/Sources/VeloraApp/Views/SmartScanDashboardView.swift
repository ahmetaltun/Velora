import SwiftUI
import VeloraCore

public struct SmartScanDashboardView: View {
    @Bindable public var viewModel: VeloraViewModel

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 19) {
                // Tier 1: Hero Banner (Catalog Status & Indexing Action)
                SmartScanHeroView(viewModel: viewModel)
                    .background(
                        VeloraTheme.obsidianElevated,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(VeloraTheme.cardBorder, lineWidth: 1)
                    )

                // Loading Snapshot Notice Banner
                if viewModel.isLoadingSnapshot {
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Loading Cached Catalog")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(VeloraTheme.textPrimary)

                                if let size = viewModel.catalogFileSizeString {
                                    Text("(\(size))")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(VeloraTheme.accentCyan)
                                }
                            }

                            Text("Reading catalog.bin from disk into RAM. Sub-millisecond search and memory traversal will be ready shortly.")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundColor(VeloraTheme.textSecondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [
                                VeloraTheme.accentBlue.opacity(0.18),
                                VeloraTheme.obsidianElevated
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(VeloraTheme.accentCyan.opacity(0.4), lineWidth: 1)
                    )
                    .shadow(color: VeloraTheme.accentBlue.opacity(0.15), radius: 8, x: 0, y: 2)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Tier 2: Storage Analytics Grid (APFS Container & Volume Usage)
                HStack(spacing: 16) {
                    LinearStorageGaugeCardView(viewModel: viewModel)
                        .frame(maxWidth: .infinity)

                    StorageDonutChartView(viewModel: viewModel)
                        .frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Tier 3: On-Demand Tools & Utilities Hub
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Maintenance & Storage Tools")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(VeloraTheme.textPrimary)

                            Text("Select any module to inspect and reclaim space on-demand.")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundColor(VeloraTheme.textSecondary)
                        }

                        Spacer()
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 11),
                            GridItem(.flexible(), spacing: 11),
                            GridItem(.flexible(), spacing: 11)
                        ],
                        spacing: 11
                    ) {
                        QuickToolLauncherTile(
                            title: "Build Junk",
                            subtitle: "Rust target, node_modules & build caches",
                            systemImage: "gearshape.2.fill",
                            accentColor: VeloraTheme.accentViolet,
                            isDisabled: viewModel.isInteractionDisabled
                        ) {
                            viewModel.activeSidebarId = "tool_dev_artifacts"
                        }

                        QuickToolLauncherTile(
                            title: "App Leftovers",
                            subtitle: "Orphaned ~/Library support files",
                            systemImage: "trash.circle.fill",
                            accentColor: VeloraTheme.accentPink,
                            isDisabled: viewModel.isInteractionDisabled
                        ) {
                            viewModel.activeSidebarId = "tool_orphans"
                        }

                        QuickToolLauncherTile(
                            title: "Xcode Storage",
                            subtitle: "DerivedData, device support & simulators",
                            systemImage: "hammer.circle.fill",
                            accentColor: VeloraTheme.accentEmerald,
                            isDisabled: viewModel.isInteractionDisabled
                        ) {
                            viewModel.activeSidebarId = "tool_xcode"
                        }

                        QuickToolLauncherTile(
                            title: "Package Caches",
                            subtitle: "Homebrew, Cargo, npm, pip & Docker",
                            systemImage: "shippingbox.circle.fill",
                            accentColor: VeloraTheme.accentAmber,
                            isDisabled: viewModel.isInteractionDisabled
                        ) {
                            viewModel.activeSidebarId = "tool_package_caches"
                        }

                        QuickToolLauncherTile(
                            title: "Duplicate Finder",
                            subtitle: "Byte-for-byte duplicate file detector",
                            systemImage: "doc.on.doc.fill",
                            accentColor: VeloraTheme.accentCyan,
                            isDisabled: viewModel.isInteractionDisabled
                        ) {
                            viewModel.activeSidebarId = "tool_duplicates"
                        }

                        QuickToolLauncherTile(
                            title: "Malware & Threats",
                            subtitle: "LaunchAgent audit & code signatures",
                            systemImage: "shield.lefthalf.filled",
                            accentColor: VeloraTheme.accentBlue,
                            isDisabled: viewModel.isInteractionDisabled
                        ) {
                            viewModel.activeSidebarId = "tool_security"
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(VeloraTheme.obsidianBase)
    }
}

// MARK: - Minimalist Tool Launcher Tile

private struct QuickToolLauncherTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isDisabled ? VeloraTheme.textMuted.opacity(0.1) : accentColor.opacity(isHovering ? 0.22 : 0.12))
                        .frame(width: 38, height: 38)

                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(isDisabled ? VeloraTheme.textMuted : accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(isDisabled ? VeloraTheme.textMuted : VeloraTheme.textPrimary)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(isDisabled ? VeloraTheme.textMuted.opacity(0.7) : VeloraTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isHovering && !isDisabled ? accentColor : VeloraTheme.textMuted.opacity(0.6))
                    .offset(x: isHovering && !isDisabled ? 2 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                isHovering && !isDisabled ? VeloraTheme.obsidianElevated.opacity(0.9) : VeloraTheme.obsidianElevated,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovering && !isDisabled ? accentColor.opacity(0.4) : VeloraTheme.cardBorder, lineWidth: 1)
            )
            .opacity(isDisabled ? 0.45 : 1.0)
            .shadow(color: isHovering && !isDisabled ? accentColor.opacity(0.12) : Color.clear, radius: 8, x: 0, y: 3)
            .scaleEffect(isHovering && !isDisabled ? 1.015 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            guard !isDisabled else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                isHovering = hovering
            }
        }
    }
}
