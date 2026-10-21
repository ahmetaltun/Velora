import AppKit
import SwiftUI
import VeloraCore

extension InstalledAppRecord: Identifiable {
    public var id: String {
        bundleId.isEmpty ? appPath : bundleId
    }
}

extension AppPartRecord: Identifiable {
    public var id: String { path }
}

public struct AppUninstallerDashboardView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var selectedAppId: String?
    @State private var searchFilter: String = ""
    @State private var filterMode: String = "User" // "All", "User", "Large"
    @State private var selectedPartPaths = Set<String>()

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var filteredApps: [InstalledAppRecord] {
        var result = viewModel.installedApps

        if filterMode == "User" {
            result = result.filter { !$0.isSystemApp }
        } else if filterMode == "Large" {
            result = result.filter { $0.totalSizeBytes >= 1_000_000_000 }
        }

        let query = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.bundleId.lowercased().contains(query)
            }
        }

        return result
    }

    private var selectedApp: InstalledAppRecord? {
        guard let id = selectedAppId else {
            return filteredApps.first
        }
        return viewModel.installedApps.first { $0.id == id }
    }

    private var totalAppsFootprint: UInt64 {
        filteredApps.reduce(0) { $0 + $1.totalSizeBytes }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func appIcon(for path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }

    private func isAppRunning(bundleId: String) -> Bool {
        guard !bundleId.isEmpty else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    private func parseColor(hex: String) -> Color {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r, g, b: UInt64
        switch clean.count {
        case 6:
            (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (100, 149, 237)
        }
        return Color(
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            ToolHeaderView(
                title: "App Uninstaller",
                subtitle: "Deep footprint analysis: Bundle, Application Support, Containers, Caches & Preferences",
                systemImage: "app.badge.checkmark",
                accentColor: VeloraTheme.accentBlue
            ) {
                HStack(spacing: 12) {
                    Text("\(filteredApps.count) apps (\(formatBytes(totalAppsFootprint)))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(VeloraTheme.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(VeloraTheme.obsidianElevated, in: Capsule())
                        .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))

                    Button(action: {
                        viewModel.loadInstalledApps()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .padding(8)
                            .background(VeloraTheme.obsidianElevated, in: Circle())
                            .overlay(Circle().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Rescan installed applications")
                }
            }

            if viewModel.isLoadingApps {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Text("Analyzing application footprints and Library containers...")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VeloraTheme.obsidianBase)
            } else if viewModel.installedApps.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(VeloraTheme.accentBlue.opacity(0.15))
                            .frame(width: 64, height: 64)
                        Image(systemName: "app.dashed")
                            .font(.system(size: 32))
                            .foregroundColor(VeloraTheme.accentBlue)
                    }
                    Text("No applications discovered")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                    Button("Scan Applications") {
                        viewModel.loadInstalledApps()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(VeloraTheme.ctaGradient, in: Capsule())
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VeloraTheme.obsidianBase)
            } else {
                HSplitView {
                    // Left Column: App List & Filter
                    VStack(spacing: 0) {
                        // Filters & Search
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(VeloraTheme.textSecondary)
                                TextField("Filter apps...", text: $searchFilter)
                                    .textFieldStyle(.plain)
                                    .foregroundColor(VeloraTheme.textPrimary)
                                if !searchFilter.isEmpty {
                                    Button(action: { searchFilter = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(VeloraTheme.textSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(VeloraTheme.cardBorder, lineWidth: 1))

                            Picker("", selection: $filterMode) {
                                Text("User Apps").tag("User")
                                Text("All").tag("All")
                                Text("Large (>1GB)").tag("Large")
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(12)
                        .background(VeloraTheme.obsidianSidebar)

                        Divider().overlay(VeloraTheme.cardBorder)

                        List(filteredApps, selection: $selectedAppId) { app in
                            AppRow(
                                app: app,
                                isRunning: isAppRunning(bundleId: app.bundleId),
                                icon: appIcon(for: app.appPath),
                                isSelected: (selectedAppId ?? filteredApps.first?.id) == app.id
                            )
                            .tag(app.id)
                        }
                        .scrollContentBackground(.hidden)
                        .background(VeloraTheme.obsidianSidebar)
                    }
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

                    // Right Column: Categorized Breakdown Inspector
                    if let app = selectedApp {
                        AppDetailView(
                            app: app,
                            isRunning: isAppRunning(bundleId: app.bundleId),
                            icon: appIcon(for: app.appPath),
                            viewModel: viewModel,
                            selectedPartPaths: $selectedPartPaths,
                            parseColor: parseColor,
                            formatBytes: formatBytes
                        )
                        .frame(minWidth: 420)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "sidebar.right")
                                .font(.system(size: 36))
                                .foregroundColor(VeloraTheme.textMuted)
                            Text("Select an application to inspect its full footprint")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(VeloraTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(VeloraTheme.obsidianBase)
                    }
                }
            }
        }
        .background(VeloraTheme.obsidianBase)
        .onAppear {
            if viewModel.installedApps.isEmpty {
                viewModel.loadInstalledApps()
            }
        }
    }
}

// MARK: - App Row Component

private struct AppRow: View {
    let app: InstalledAppRecord
    let isRunning: Bool
    let icon: NSImage
    let isSelected: Bool

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 30, height: 30)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundColor(isSelected ? .white : VeloraTheme.textPrimary)
                        .lineLimit(1)

                    if isRunning {
                        Circle()
                            .fill(VeloraTheme.accentEmerald)
                            .frame(width: 6, height: 6)
                    }
                }

                HStack(spacing: 6) {
                    Text(app.version.isEmpty ? "v1.0" : "v\(app.version)")
                        .font(.system(size: 10))
                        .foregroundColor(VeloraTheme.textMuted)

                    if app.isSystemApp {
                        Text("System")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                }
            }

            Spacer()

            Text(formatBytes(app.totalSizeBytes))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(isSelected ? .white.opacity(0.85) : VeloraTheme.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isSelected ? VeloraTheme.obsidianElevated : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - App Detail Inspector Component

private struct AppDetailView: View {
    let app: InstalledAppRecord
    let isRunning: Bool
    let icon: NSImage
    @Bindable var viewModel: VeloraViewModel
    @Binding var selectedPartPaths: Set<String>
    let parseColor: (String) -> Color
    let formatBytes: (UInt64) -> String

    var body: some View {
        VStack(spacing: 0) {
            // App Header Banner
            HStack(spacing: 16) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .cornerRadius(10)
                    .shadow(radius: 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(app.name)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(VeloraTheme.textPrimary)

                        if isRunning {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(VeloraTheme.accentEmerald)
                                    .frame(width: 6, height: 6)
                                Text("Running")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(VeloraTheme.accentEmerald)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VeloraTheme.accentEmerald.opacity(0.15), in: Capsule())
                        }

                        if app.isSystemApp {
                            Text("System Protected")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(VeloraTheme.textMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.06), in: Capsule())
                        }
                    }

                    HStack(spacing: 10) {
                        Text(app.bundleId)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(VeloraTheme.textMuted)

                        if !app.version.isEmpty {
                            Text("• Version \(app.version)")
                                .font(.system(size: 11))
                                .foregroundColor(VeloraTheme.textSecondary)
                        }
                    }
                }

                Spacer()

                // Actions: Stage Complete App
                VStack(alignment: .trailing, spacing: 6) {
                    Text(formatBytes(app.totalSizeBytes))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Button(action: {
                        for part in app.parts {
                            viewModel.collect(path: part.path, size: part.sizeBytes, isDir: true)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Stage App")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                colors: [VeloraTheme.accentPink, VeloraTheme.accentViolet],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                        .shadow(color: VeloraTheme.accentPink.opacity(0.35), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .background(VeloraTheme.obsidianElevated)
            .overlay(alignment: .bottom) {
                Divider().overlay(VeloraTheme.cardBorder)
            }

            // Parts List: Categorized Breakdown
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Categorized Storage Breakdown")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(VeloraTheme.textPrimary)
                        Spacer()
                        Text("\(app.parts.count) components found")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(VeloraTheme.textMuted)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    VStack(spacing: 8) {
                        ForEach(app.parts) { part in
                            AppPartCard(
                                part: part,
                                color: parseColor(part.colorHex),
                                formatBytes: formatBytes,
                                onCollect: {
                                    viewModel.collect(path: part.path, size: part.sizeBytes, isDir: true)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .background(VeloraTheme.obsidianBase)
        }
    }
}

// MARK: - App Part Card Component

private struct AppPartCard: View {
    let part: AppPartRecord
    let color: Color
    let formatBytes: (UInt64) -> String
    let onCollect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(part.kindName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(color)

                    Text("— \(part.name)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(VeloraTheme.textPrimary)
                }

                Text(part.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(VeloraTheme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(formatBytes(part.sizeBytes))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(VeloraTheme.textPrimary)

            // Reveal in Finder
            Button(action: {
                let url = URL(fileURLWithPath: part.path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }) {
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(VeloraTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")

            // QuickLook preview
            Button(action: {
                let url = URL(fileURLWithPath: part.path)
                QuickLookCoordinator.shared.togglePreview(for: url)
            }) {
                Image(systemName: "eye")
                    .foregroundColor(VeloraTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("QuickLook preview")

            // Stage to Collector
            Button(action: onCollect) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(VeloraTheme.accentCyan)
            }
            .buttonStyle(.plain)
            .help("Stage into Collector Tray")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(VeloraTheme.cardBorder, lineWidth: 1)
        )
    }
}
