import AppKit
import SwiftUI
import VeloraCore

extension DockerImageRecord: Identifiable {}
extension DockerVolumeRecord: Identifiable {
    public var id: String { name }
}
extension DockerBuildCacheRecord: Identifiable {}
extension DockerContainerRecord: Identifiable {}
extension DockerVmDiskRecord: Identifiable {
    public var id: String { path }
}

public struct DockerStorageView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var selectedFilter: String = "All"
    @State private var searchFilter: String = ""
    @State private var showSystemPruneConfirmation: Bool = false
    @State private var showVolumePruneConfirmation: Bool = false

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var summary: DockerStorageSummaryRecord? {
        viewModel.dockerSummary
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func formatRelativeDate(secs: UInt64) -> String {
        guard secs > 0 else { return "Unknown" }
        let date = Date(timeIntervalSince1970: TimeInterval(secs))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var totalReclaimableBytes: UInt64 {
        guard let s = summary else { return 0 }
        return s.danglingImagesBytes + s.unusedImagesBytes + s.danglingAnonymousVolumesBytes + s.buildCacheReclaimableBytes + s.stoppedContainersBytes
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            BloomToolHeaderView(
                title: "Docker Deep Inspection",
                subtitle: "Dangling layers, unused volumes, BuildKit cache, and APFS VM sparse disk reclamation",
                systemImage: "cylinder.split.1x2",
                accentColor: VeloraTheme.accentBlue
            ) {
                HStack(spacing: 10) {
                    // Engine Daemon Status Indicator Pill
                    if let s = summary {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(s.daemonStatus == "Running" ? VeloraTheme.accentEmerald : VeloraTheme.accentAmber)
                                .frame(width: 7, height: 7)
                            Text("\(s.engineName): \(s.daemonStatus)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(VeloraTheme.textPrimary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(VeloraTheme.obsidianElevated, in: Capsule())
                        .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }

                    // Open Docker Desktop / Compaction Button
                    Button(action: {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Open Docker")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(VeloraTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(VeloraTheme.obsidianElevated, in: Capsule())
                        .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Opens Docker Desktop to trigger Virtual Disk Compaction (Settings > Resources > Virtual disk limit > Reclaim disk space)")

                    // Rescan Docker Button
                    Button(action: {
                        viewModel.loadDockerSummary()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .padding(8)
                            .background(VeloraTheme.obsidianElevated, in: Circle())
                            .overlay(Circle().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Rescan Docker host VM disks and query daemon /system/df")
                }
            }

            // Metric Cards Row
            if let s = summary {
                HStack(spacing: 12) {
                    ToolMetricCardView(
                        title: "Host VM Disk",
                        value: formatBytes(s.totalHostAllocatedBytes),
                        accentColor: VeloraTheme.accentBlue
                    )
                    ToolMetricCardView(
                        title: "Live Guest Data",
                        value: formatBytes(s.totalGuestActiveBytes),
                        accentColor: VeloraTheme.accentEmerald
                    )
                    ToolMetricCardView(
                        title: "Dangling & Unused",
                        value: formatBytes(totalReclaimableBytes),
                        accentColor: VeloraTheme.accentAmber
                    )
                    ToolMetricCardView(
                        title: "Phantom Bloat",
                        value: formatBytes(s.phantomBloatBytes),
                        accentColor: s.phantomBloatBytes > 1_000_000_000 ? VeloraTheme.accentPink : VeloraTheme.textSecondary
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(VeloraTheme.obsidianElevated.opacity(0.4))
                .overlay(alignment: .bottom) {
                    Divider().overlay(VeloraTheme.cardBorder)
                }
            }

            // Action Status Notification Banner
            if let statusMsg = viewModel.dockerActionStatusMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(VeloraTheme.accentEmerald)
                    Text(statusMsg)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.dockerActionStatusMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(VeloraTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(VeloraTheme.accentEmerald.opacity(0.15))
                .overlay(alignment: .bottom) {
                    Divider().overlay(VeloraTheme.cardBorder)
                }
            }

            // Phantom Bloat Advisory Banner
            if let s = summary, s.phantomBloatBytes > 1_000_000_000 {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(VeloraTheme.accentAmber)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("APFS Sparse Disk Space Disconnect (\(formatBytes(s.phantomBloatBytes)) Unreclaimed)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(VeloraTheme.textPrimary)

                        Text("Deleting containers or images only marks blocks free inside Docker's Linux ext4 filesystem. macOS APFS retains allocated physical storage blocks until an APFS punch-hole TRIM compaction is executed. Use Docker Desktop Settings → Resources → Virtual disk limit → Reclaim disk space to shrink Docker.raw.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button("Compact Disk...") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(VeloraTheme.accentAmber, in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(VeloraTheme.accentAmber.opacity(0.1))
                .overlay(alignment: .bottom) {
                    Divider().overlay(VeloraTheme.cardBorder)
                }
            }

            // Category Filter Bar & Action Strip
            HStack(spacing: 8) {
                ToolFilterChip(title: "All", isSelected: selectedFilter == "All", accentColor: VeloraTheme.accentBlue) { selectedFilter = "All" }
                ToolFilterChip(title: "Dangling Layers", isSelected: selectedFilter == "Dangling Layers", accentColor: VeloraTheme.accentAmber) { selectedFilter = "Dangling Layers" }
                ToolFilterChip(title: "Unused Images", isSelected: selectedFilter == "Unused Images", accentColor: VeloraTheme.accentViolet) { selectedFilter = "Unused Images" }
                ToolFilterChip(title: "Anonymous Volumes", isSelected: selectedFilter == "Anonymous Volumes", accentColor: VeloraTheme.accentPink) { selectedFilter = "Anonymous Volumes" }
                ToolFilterChip(title: "Named Volumes", isSelected: selectedFilter == "Named Volumes", accentColor: VeloraTheme.accentCyan) { selectedFilter = "Named Volumes" }
                ToolFilterChip(title: "BuildKit Cache", isSelected: selectedFilter == "BuildKit Cache", accentColor: VeloraTheme.accentEmerald) { selectedFilter = "BuildKit Cache" }
                ToolFilterChip(title: "Containers", isSelected: selectedFilter == "Containers", accentColor: VeloraTheme.accentBlue) { selectedFilter = "Containers" }

                Spacer()

                // Search Filter
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(VeloraTheme.textSecondary)
                    TextField("Filter items...", text: $searchFilter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(VeloraTheme.cardBorder, lineWidth: 1))
                .frame(width: 180)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider().overlay(VeloraTheme.cardBorder)

            // Content List
            if viewModel.isLoadingDocker {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Inspecting Docker host VM disks and daemon storage...")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                }
                Spacer()
            } else if let s = summary {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // 1. Host VM Disks Section
                        if selectedFilter == "All" {
                            ForEach(s.vmDisks) { disk in
                                DockerDiskRow(disk: disk, formatBytes: formatBytes, formatRelativeDate: formatRelativeDate)
                            }
                        }

                        // 2. Images & Dangling Layers
                        if selectedFilter == "All" || selectedFilter == "Dangling Layers" || selectedFilter == "Unused Images" {
                            ForEach(filteredImages(s.images)) { img in
                                DockerImageRow(image: img, formatBytes: formatBytes, formatRelativeDate: formatRelativeDate)
                            }
                        }

                        // 3. Volumes
                        if selectedFilter == "All" || selectedFilter == "Anonymous Volumes" || selectedFilter == "Named Volumes" {
                            ForEach(filteredVolumes(s.volumes)) { vol in
                                DockerVolumeRow(volume: vol, formatBytes: formatBytes)
                            }
                        }

                        // 4. BuildKit Cache
                        if selectedFilter == "All" || selectedFilter == "BuildKit Cache" {
                            ForEach(filteredBuildCache(s.buildCache)) { bc in
                                DockerBuildCacheRow(cache: bc, formatBytes: formatBytes)
                            }
                        }

                        // 5. Containers
                        if selectedFilter == "All" || selectedFilter == "Containers" {
                            ForEach(filteredContainers(s.containers)) { cnt in
                                DockerContainerRow(container: cnt, formatBytes: formatBytes)
                            }
                        }
                    }
                    .padding(20)
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "shippingbox.circle")
                        .font(.system(size: 40))
                        .foregroundColor(VeloraTheme.textSecondary)
                    Text("No Docker storage information loaded yet.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                    Button("Scan Docker Now") {
                        viewModel.loadDockerSummary()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }

            Divider().overlay(VeloraTheme.cardBorder)

            // Bottom Prune Actions Toolbar
            HStack(spacing: 12) {
                // Prune Dangling Layers Button (Safe)
                Button(action: {
                    viewModel.pruneDockerDanglingImages()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.down.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Prune Dangling Layers")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(VeloraTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(VeloraTheme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isPruningDockerAction)
                .help("Safely prunes untagged intermediate image layers (<none>:<none>)")

                // Prune Anonymous Volumes Button
                Button(action: {
                    viewModel.pruneDockerAnonymousVolumes()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "externaldrive.badge.xmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Prune Anonymous Volumes")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(VeloraTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(VeloraTheme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isPruningDockerAction)
                .help("Prunes unattached 64-character hash anonymous volumes created implicitly by VOLUME directives")

                // Prune BuildKit Cache
                Button(action: {
                    viewModel.pruneDockerBuildCache()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Prune BuildKit Cache")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(VeloraTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(VeloraTheme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isPruningDockerAction)
                .help("Prunes intermediate build cache stages created during docker build")

                Spacer()

                // System Prune All
                Button(action: {
                    showSystemPruneConfirmation = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("System Prune All...")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
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
                .disabled(viewModel.isPruningDockerAction)
                .confirmationDialog(
                    "Comprehensive Docker Prune",
                    isPresented: $showSystemPruneConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Prune All Unused Containers, Images & Volumes", role: .destructive) {
                        viewModel.pruneDockerSystemAll()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove all stopped containers, all unused networks, all dangling and unreferenced images, and unattached volumes via docker system prune -a --volumes.")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(VeloraTheme.obsidianBase)
        }
        .background(VeloraTheme.obsidianBase)
        .onAppear {
            if viewModel.dockerSummary == nil {
                viewModel.loadDockerSummary()
            }
        }
    }

    private func matchesSearch(_ text: String) -> Bool {
        let q = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return text.lowercased().contains(q)
    }

    private func filteredImages(_ images: [DockerImageRecord]) -> [DockerImageRecord] {
        images.filter { img in
            let tagStr = img.repoTags.joined(separator: ", ")
            if !matchesSearch("\(img.id) \(tagStr)") { return false }
            if selectedFilter == "Dangling Layers" { return img.isDangling }
            if selectedFilter == "Unused Images" { return !img.isDangling && !img.inUse }
            return true
        }
    }

    private func filteredVolumes(_ volumes: [DockerVolumeRecord]) -> [DockerVolumeRecord] {
        volumes.filter { vol in
            if !matchesSearch("\(vol.name) \(vol.driver)") { return false }
            if selectedFilter == "Anonymous Volumes" { return vol.isAnonymous }
            if selectedFilter == "Named Volumes" { return !vol.isAnonymous }
            return true
        }
    }

    private func filteredBuildCache(_ cache: [DockerBuildCacheRecord]) -> [DockerBuildCacheRecord] {
        cache.filter { bc in
            matchesSearch("\(bc.id) \(bc.cacheType) \(bc.description)")
        }
    }

    private func filteredContainers(_ containers: [DockerContainerRecord]) -> [DockerContainerRecord] {
        containers.filter { cnt in
            let namesStr = cnt.names.joined(separator: ", ")
            return matchesSearch("\(cnt.id) \(namesStr) \(cnt.image) \(cnt.state)")
        }
    }
}

// -----------------------------------------------------------------------------
// Row Subviews
// -----------------------------------------------------------------------------

struct DockerDiskRow: View {
    let disk: DockerVmDiskRecord
    let formatBytes: (UInt64) -> String
    let formatRelativeDate: (UInt64) -> String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 18))
                .foregroundColor(VeloraTheme.accentBlue)
                .frame(width: 32, height: 32)
                .background(VeloraTheme.accentBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(disk.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text(disk.engineName)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.accentBlue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(VeloraTheme.accentBlue.opacity(0.15), in: Capsule())
                }

                Text(disk.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(VeloraTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatBytes(disk.allocatedBytes))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)

                Text("Max Limit: \(formatBytes(disk.virtualCapacityBytes))")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(VeloraTheme.textSecondary)
            }
        }
        .padding(12)
        .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VeloraTheme.cardBorder, lineWidth: 1))
    }
}

struct DockerImageRow: View {
    let image: DockerImageRecord
    let formatBytes: (UInt64) -> String
    let formatRelativeDate: (UInt64) -> String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: image.isDangling ? "square.stack.3d.down.dottedline" : "square.stack.3d.down.right.fill")
                .font(.system(size: 16))
                .foregroundColor(image.isDangling ? VeloraTheme.accentAmber : VeloraTheme.accentViolet)
                .frame(width: 32, height: 32)
                .background((image.isDangling ? VeloraTheme.accentAmber : VeloraTheme.accentViolet).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(image.repoTags.isEmpty ? "<none>:<none>" : image.repoTags.joined(separator: ", "))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    if image.isDangling {
                        Text("Dangling Layer")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(VeloraTheme.accentAmber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VeloraTheme.accentAmber.opacity(0.15), in: Capsule())
                    } else if !image.inUse {
                        Text("Unused")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(VeloraTheme.accentViolet)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VeloraTheme.accentViolet.opacity(0.15), in: Capsule())
                    } else {
                        Text("In Use")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(VeloraTheme.accentEmerald)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VeloraTheme.accentEmerald.opacity(0.15), in: Capsule())
                    }
                }

                Text("ID: \(image.id) • Created: \(formatRelativeDate(image.createdSecs))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(VeloraTheme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatBytes(image.sizeBytes))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)

                if image.sharedSizeBytes > 0 {
                    Text("Shared: \(formatBytes(image.sharedSizeBytes))")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                }
            }
        }
        .padding(12)
        .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VeloraTheme.cardBorder, lineWidth: 1))
    }
}

struct DockerVolumeRow: View {
    let volume: DockerVolumeRecord
    let formatBytes: (UInt64) -> String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.icloud")
                .font(.system(size: 16))
                .foregroundColor(volume.isAnonymous ? VeloraTheme.accentPink : VeloraTheme.accentCyan)
                .frame(width: 32, height: 32)
                .background((volume.isAnonymous ? VeloraTheme.accentPink : VeloraTheme.accentCyan).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(volume.name)
                        .font(.system(size: 13, weight: .semibold, design: volume.isAnonymous ? .monospaced : .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if volume.isAnonymous {
                        Text("Anonymous")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(VeloraTheme.accentPink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VeloraTheme.accentPink.opacity(0.15), in: Capsule())
                    }

                    if !volume.inUse {
                        Text("Unattached")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(VeloraTheme.accentAmber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VeloraTheme.accentAmber.opacity(0.15), in: Capsule())
                    } else {
                        Text("\(volume.refCount) container\(volume.refCount == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(VeloraTheme.accentEmerald)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VeloraTheme.accentEmerald.opacity(0.15), in: Capsule())
                    }
                }

                Text("Driver: \(volume.driver)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(VeloraTheme.textSecondary)
            }

            Spacer()

            Text(formatBytes(volume.sizeBytes))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(VeloraTheme.textPrimary)
        }
        .padding(12)
        .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VeloraTheme.cardBorder, lineWidth: 1))
    }
}

struct DockerBuildCacheRow: View {
    let cache: DockerBuildCacheRecord
    let formatBytes: (UInt64) -> String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 16))
                .foregroundColor(VeloraTheme.accentEmerald)
                .frame(width: 32, height: 32)
                .background(VeloraTheme.accentEmerald.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(cache.description.isEmpty ? "Build Cache (\(cache.cacheType))" : cache.description)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    if !cache.inUse {
                        Text("Reclaimable")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(VeloraTheme.accentEmerald)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VeloraTheme.accentEmerald.opacity(0.15), in: Capsule())
                    }
                }

                Text("ID: \(cache.id) • Type: \(cache.cacheType)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(VeloraTheme.textSecondary)
            }

            Spacer()

            Text(formatBytes(cache.sizeBytes))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(VeloraTheme.textPrimary)
        }
        .padding(12)
        .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VeloraTheme.cardBorder, lineWidth: 1))
    }
}

struct DockerContainerRow: View {
    let container: DockerContainerRecord
    let formatBytes: (UInt64) -> String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: container.state == "running" ? "play.circle.fill" : "stop.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(container.state == "running" ? VeloraTheme.accentEmerald : VeloraTheme.accentPink)
                .frame(width: 32, height: 32)
                .background((container.state == "running" ? VeloraTheme.accentEmerald : VeloraTheme.accentPink).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(container.names.isEmpty ? container.id : container.names.joined(separator: ", "))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text(container.state.capitalized)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(container.state == "running" ? VeloraTheme.accentEmerald : VeloraTheme.accentPink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((container.state == "running" ? VeloraTheme.accentEmerald : VeloraTheme.accentPink).opacity(0.15), in: Capsule())
                }

                Text("Image: \(container.image) • ID: \(container.id)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(VeloraTheme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatBytes(container.sizeRwBytes))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)

                Text("Writable Layer")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(VeloraTheme.textSecondary)
            }
        }
        .padding(12)
        .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VeloraTheme.cardBorder, lineWidth: 1))
    }
}
