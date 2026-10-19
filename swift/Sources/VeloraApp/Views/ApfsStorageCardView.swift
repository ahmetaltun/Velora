import AppKit
import SwiftUI
import VeloraCore

public struct ApfsStorageCardView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var isExpanded: Bool = false
    @State private var showSnapshotsPopover: Bool = false

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var rec: StorageReconciliationItem? {
        viewModel.storageReconciliation
    }

    private var totalBytes: UInt64 {
        rec?.containerTotalBytes ?? 1
    }

    private var freeBytes: UInt64 {
        rec?.containerFreeBytes ?? 0
    }

    private var usedBytes: UInt64 {
        totalBytes > freeBytes ? totalBytes - freeBytes : 0
    }

    private var usedPercent: Int {
        guard totalBytes > 0 else { return 0 }
        return Int(min(100, max(0, (Double(usedBytes) / Double(totalBytes)) * 100)))
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row
            HStack(spacing: 8) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 15))
                    .foregroundColor(viewModel.activeSidebarId == "volume_root" ? .accentColor : .blue)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Macintosh HD")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundColor(viewModel.activeSidebarId == "volume_root" ? .accentColor : .primary)
                    Text("APFS Container")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(usedPercent)%")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundColor(.secondary)
            }

            // Multi-segment Segmented Bar
            GeometryReader { geo in
                let width = geo.size.width
                let tot = Double(totalBytes)

                let scannedRatio = Double(rec?.userScannedBytes ?? 0) / tot
                let systemRatio = Double(rec?.systemVolumeBytes ?? 0) / tot
                let otherRatio = Double(rec?.otherVolumesBytes ?? 0) / tot
                let hiddenRatio = Double(rec?.hiddenSystemBytes ?? 0) / tot
                let purgeRatio = Double(rec?.purgeableBytes ?? 0) / tot

                ZStack(alignment: .leading) {
                    // Background / Free Space
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: width, height: 7)

                    HStack(spacing: 1.5) {
                        // User Scanned Files (Teal/Blue)
                        if scannedRatio > 0.005 {
                            Capsule()
                                .fill(VeloraTheme.teal)
                                .frame(width: max(2, width * scannedRatio), height: 7)
                        }

                        // macOS System OS (Indigo)
                        if systemRatio > 0.005 {
                            Capsule()
                                .fill(Color.indigo)
                                .frame(width: max(2, width * systemRatio), height: 7)
                        }

                        // Other Container Volumes - Preboot/VM/Recovery (Purple)
                        if otherRatio > 0.005 {
                            Capsule()
                                .fill(Color.purple)
                                .frame(width: max(2, width * otherRatio), height: 7)
                        }

                        // Hidden System Data & Caches (Slate)
                        if hiddenRatio > 0.005 {
                            Capsule()
                                .fill(Color.secondary.opacity(0.75))
                                .frame(width: max(2, width * hiddenRatio), height: 7)
                        }

                        // Purgeable (Amber)
                        if purgeRatio > 0.005 {
                            Capsule()
                                .fill(VeloraTheme.amber)
                                .frame(width: max(2, width * purgeRatio), height: 7)
                        }
                    }
                }
            }
            .frame(height: 7)

            // Free Space Caption
            HStack {
                Text("\(formatBytes(freeBytes)) free of \(formatBytes(totalBytes))")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle detailed APFS space breakdown")
            }

            // Expanded Detail View
            if isExpanded, let r = rec {
                VStack(alignment: .leading, spacing: 5) {
                    Divider()
                        .opacity(0.3)
                        .padding(.vertical, 2)

                    DetailRow(color: VeloraTheme.teal, label: "Scanned Files", value: formatBytes(r.userScannedBytes))
                    DetailRow(color: .indigo, label: "macOS System", value: formatBytes(r.systemVolumeBytes))
                    DetailRow(color: .purple, label: "Other APFS Volumes", value: formatBytes(r.otherVolumesBytes))
                    DetailRow(color: .secondary.opacity(0.75), label: "System Caches / Data", value: formatBytes(r.hiddenSystemBytes))
                    if r.purgeableBytes > 0 {
                        DetailRow(color: VeloraTheme.amber, label: "Purgeable Space", value: formatBytes(r.purgeableBytes))
                    }

                    // Snapshots Row & Action
                    if !r.snapshots.isEmpty {
                        Divider()
                            .opacity(0.3)
                            .padding(.vertical, 2)

                        HStack {
                            Label("\(r.snapshots.count) Local Snapshot\(r.snapshots.count > 1 ? "s" : "")", systemImage: "clock.arrow.circlepath")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)

                            Spacer()

                            Button("View") {
                                showSnapshotsPopover.toggle()
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .popover(isPresented: $showSnapshotsPopover) {
                                SnapshotsListPopover(snapshots: r.snapshots)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(viewModel.activeSidebarId == "volume_root" ? Color.accentColor.opacity(0.10) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.navigateToRoot()
        }
    }
}

private struct DetailRow: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}

private struct SnapshotsListPopover: View {
    let snapshots: [StorageSnapshotItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("APFS Local Snapshots")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Spacer()
                Text("\(snapshots.count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
            }

            Text("Time Machine local freeze points. macOS automatically thins these when space is required.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(snapshots, id: \.name) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.dateFormatted)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                        Text(s.name)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                }
            }

            Divider()

            Button(action: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack {
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                    Text("Manage in macOS Storage Settings")
                    Spacer()
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
    }
}
