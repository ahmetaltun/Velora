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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 16))
                            .foregroundColor(VeloraTheme.teal)
                        Text("App Uninstaller")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                    }
                    Text("Deep footprint analysis: Bundle, Application Support, Containers, Caches & Preferences")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(filteredApps.count) apps (\(formatBytes(totalAppsFootprint)))")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())

                Button(action: {
                    viewModel.loadInstalledApps()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Rescan installed applications")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            if viewModel.isLoadingApps {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Analyzing application footprints and Library containers...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.installedApps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No applications discovered")
                        .font(.headline)
                    Button("Scan Applications") {
                        viewModel.loadInstalledApps()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    // Left Column: App List & Filter
                    VStack(spacing: 0) {
                        // Filters & Search
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("Filter apps...", text: $searchFilter)
                                    .textFieldStyle(.plain)
                                if !searchFilter.isEmpty {
                                    Button(action: { searchFilter = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                            Picker("", selection: $filterMode) {
                                Text("User Apps").tag("User")
                                Text("All").tag("All")
                                Text("Large (>1GB)").tag("Large")
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(12)

                        Divider()

                        List(filteredApps, selection: $selectedAppId) { app in
                            AppRow(
                                app: app,
                                isRunning: isAppRunning(bundleId: app.bundleId),
                                icon: appIcon(for: app.appPath),
                                isSelected: (selectedAppId ?? filteredApps.first?.id) == app.id
                            )
                            .tag(app.id)
                        }
                        .listStyle(.inset)
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
                                .foregroundColor(.secondary)
                            Text("Select an application to inspect its full footprint")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
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
                .frame(width: 32, height: 32)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(.subheadline, weight: .semibold))
                        .lineLimit(1)

                    if isRunning {
                        Circle()
                            .fill(VeloraTheme.mint)
                            .frame(width: 6, height: 6)
                            .help("Application is currently running")
                    }
                }

                HStack(spacing: 6) {
                    Text(app.version.isEmpty ? "v1.0" : "v\(app.version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if app.isSystemApp {
                        Text("System")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                    }
                }
            }

            Spacer()

            Text(formatBytes(app.totalSizeBytes))
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
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
                    .frame(width: 52, height: 52)
                    .cornerRadius(10)
                    .shadow(radius: 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(app.name)
                            .font(.system(.title3, design: .rounded, weight: .bold))

                        if isRunning {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(VeloraTheme.mint)
                                    .frame(width: 6, height: 6)
                                Text("Running")
                                    .font(.caption2)
                                    .foregroundColor(VeloraTheme.mint)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VeloraTheme.mint.opacity(0.12), in: Capsule())
                        }

                        if app.isSystemApp {
                            Text("System Protected")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }

                    HStack(spacing: 10) {
                        Text(app.bundleId)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)

                        if !app.version.isEmpty {
                            Text("•  Version \(app.version)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Actions: Stage Complete App
                VStack(alignment: .trailing, spacing: 6) {
                    Text(formatBytes(app.totalSizeBytes))
                        .font(.system(.title2, design: .rounded, weight: .bold))

                    Button(action: {
                        for part in app.parts {
                            viewModel.collect(path: part.path, size: part.sizeBytes, isDir: true)
                        }
                    }) {
                        Label("Stage App (\(formatBytes(app.totalSizeBytes)))", systemImage: "trash.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.regular)
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)

            Divider()

            // Parts List: Categorized Breakdown
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Categorized Storage Breakdown")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                        Spacer()
                        Text("\(app.parts.count) components found")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                .frame(width: 4, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(part.kindName)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundColor(color)

                    Text("— \(part.name)")
                        .font(.caption)
                        .foregroundColor(.primary)
                }

                Text(part.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(formatBytes(part.sizeBytes))
                .font(.system(.caption, design: .monospaced, weight: .semibold))

            // Reveal in Finder
            Button(action: {
                let url = URL(fileURLWithPath: part.path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }) {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Reveal in Finder")

            // QuickLook preview
            Button(action: {
                let url = URL(fileURLWithPath: part.path)
                QuickLookCoordinator.shared.togglePreview(for: url)
            }) {
                Image(systemName: "eye")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("QuickLook preview")

            // Stage to Collector
            Button(action: onCollect) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .help("Stage into Collector Tray")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
