import AppKit
import SwiftUI
import VeloraCore

extension AiModelRecord: Identifiable {
    public var id: String { path }
}

public struct ModelWeightHunterView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var selectedFilter: String = "All"
    @State private var searchFilter: String = ""

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var summary: AiModelSummaryRecord? {
        viewModel.aiModelSummary
    }

    private var allItems: [AiModelRecord] {
        summary?.items ?? []
    }

    private var filteredItems: [AiModelRecord] {
        allItems.filter { item in
            // Search text filter
            if !searchFilter.isEmpty {
                let q = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let matches = item.name.lowercased().contains(q) ||
                    item.path.lowercased().contains(q) ||
                    item.ecosystemName.lowercased().contains(q) ||
                    item.formatName.lowercased().contains(q) ||
                    (item.organization?.lowercased().contains(q) ?? false) ||
                    (item.architecture?.lowercased().contains(q) ?? false) ||
                    (item.quantization?.lowercased().contains(q) ?? false) ||
                    (item.parameterSize?.lowercased().contains(q) ?? false)
                if !matches { return false }
            }

            // Category filter
            if selectedFilter == "All" {
                return true
            } else if selectedFilter == "Stale" {
                return item.inactivityTier.contains("Stale")
            } else {
                return item.ecosystemName.localizedCaseInsensitiveContains(selectedFilter)
            }
        }
    }

    private var stagedPaths: Set<String> {
        Set(viewModel.collectorItems.map { $0.path })
    }

    private var staleItems: [AiModelRecord] {
        allItems.filter { $0.inactivityTier.contains("Stale") && $0.canCollect }
    }

    private var staleTotalBytes: UInt64 {
        summary?.staleBytes ?? 0
    }

    private var allStaleStaged: Bool {
        !staleItems.isEmpty && staleItems.allSatisfy { stagedPaths.contains($0.path) }
    }

    private var totalBytes: UInt64 {
        summary?.totalBytes ?? 0
    }

    private var activeTotalBytes: UInt64 {
        allItems.filter { $0.inactivityTier.contains("Active") }.reduce(0) { $0 + $1.sizeBytes }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func toggleStaging(for item: AiModelRecord) {
        if stagedPaths.contains(item.path) {
            viewModel.removeCollected(path: item.path)
            for assoc in item.associatedPaths {
                viewModel.removeCollected(path: assoc)
            }
        } else {
            let isDir = item.associatedPaths.count <= 1 && (item.path.hasSuffix("/") || !item.path.contains("."))
            if item.associatedPaths.count > 1 {
                for assoc in item.associatedPaths {
                    viewModel.collect(path: assoc, size: item.sizeBytes / UInt64(item.associatedPaths.count), isDir: false)
                }
            } else {
                viewModel.collect(path: item.path, size: item.sizeBytes, isDir: isDir)
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            BloomToolHeaderView(
                title: "Local AI & LLM Model Weights",
                subtitle: "Ollama, Hugging Face Hub, LM Studio, PyTorch, Apple MLX & ComfyUI caches",
                systemImage: "sparkles.rectangle.stack.fill",
                accentColor: VeloraTheme.accentViolet
            ) {
                HStack(spacing: 10) {
                    // Models Count & Footprint Pill
                    if let s = summary {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(VeloraTheme.accentViolet)
                                .frame(width: 7, height: 7)
                            Text("\(s.totalModelCount) Models: \(formatBytes(s.totalBytes))")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(VeloraTheme.textPrimary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(VeloraTheme.obsidianElevated, in: Capsule())
                        .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }

                    // Prune Orphaned Blobs Button
                    Button(action: {
                        viewModel.pruneOllamaBlobs()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "shippingbox.and.arrow.backward")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Prune Blobs")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(VeloraTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(VeloraTheme.obsidianElevated, in: Capsule())
                        .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Scans ~/.ollama/models/blobs for unreferenced layer digests and reclaims space")

                    // Stage All Stale Models
                    if staleTotalBytes > 0 {
                        Button(action: {
                            if allStaleStaged {
                                for item in staleItems {
                                    viewModel.removeCollected(path: item.path)
                                    for a in item.associatedPaths {
                                        viewModel.removeCollected(path: a)
                                    }
                                }
                            } else {
                                for item in staleItems {
                                    if !stagedPaths.contains(item.path) {
                                        toggleStaging(for: item)
                                    }
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: allStaleStaged ? "checkmark.circle.fill" : "sparkles")
                                    .font(.system(size: 11, weight: .bold))
                                Text(allStaleStaged ? "Unstage Stale" : "Stage Stale (\(formatBytes(staleTotalBytes)))")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                LinearGradient(
                                    colors: allStaleStaged
                                        ? [VeloraTheme.accentEmerald, VeloraTheme.accentCyan]
                                        : [VeloraTheme.accentViolet, VeloraTheme.accentPurple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule()
                            )
                            .shadow(color: (allStaleStaged ? VeloraTheme.accentEmerald : VeloraTheme.accentViolet).opacity(0.35), radius: 6, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }

                    // Rescan Button
                    Button(action: {
                        viewModel.loadAiModels()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .padding(8)
                            .background(VeloraTheme.obsidianElevated, in: Circle())
                            .overlay(Circle().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Rescan all local AI model caches")
                }
            }

            // 4-Column Metric Cards Row with Elevated Background & Bottom Separation Line
            if let s = summary {
                HStack(spacing: 12) {
                    ToolMetricCardView(
                        title: "Total AI Model Footprint",
                        value: formatBytes(s.totalBytes),
                        accentColor: VeloraTheme.accentViolet
                    )
                    ToolMetricCardView(
                        title: "Active & In-Use",
                        value: formatBytes(activeTotalBytes),
                        accentColor: VeloraTheme.accentEmerald
                    )
                    ToolMetricCardView(
                        title: "Stale Storage (> 60 Days)",
                        value: s.staleBytes > 0 ? formatBytes(s.staleBytes) : "Zero KB",
                        accentColor: s.staleBytes > 0 ? VeloraTheme.accentPink : VeloraTheme.accentAmber
                    )
                    ToolMetricCardView(
                        title: "Total Models Discovered",
                        value: "\(s.totalModelCount) models",
                        accentColor: VeloraTheme.accentCyan
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(VeloraTheme.obsidianElevated.opacity(0.4))
                .overlay(alignment: .bottom) {
                    Divider().overlay(VeloraTheme.cardBorder)
                }
            }

            // Action Status Notification Banner (if any)
            if let status = viewModel.pruneOllamaBlobsStatus {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(VeloraTheme.accentEmerald)
                    Text(status)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.pruneOllamaBlobsStatus = nil
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

            // Category Filter Bar & Action Strip with ToolFilterChip & Separation Line
            HStack(spacing: 8) {
                ToolFilterChip(title: "All", isSelected: selectedFilter == "All", accentColor: VeloraTheme.accentViolet) { selectedFilter = "All" }
                ToolFilterChip(title: "LM Studio", isSelected: selectedFilter == "LM Studio", accentColor: VeloraTheme.accentCyan) { selectedFilter = "LM Studio" }
                ToolFilterChip(title: "Ollama", isSelected: selectedFilter == "Ollama", accentColor: VeloraTheme.accentAmber) { selectedFilter = "Ollama" }
                ToolFilterChip(title: "Hugging Face", isSelected: selectedFilter == "Hugging Face", accentColor: Color(hex: "#FBBF24")) { selectedFilter = "Hugging Face" }
                ToolFilterChip(title: "Apple MLX", isSelected: selectedFilter == "Apple MLX", accentColor: VeloraTheme.accentPurple) { selectedFilter = "Apple MLX" }
                ToolFilterChip(title: "PyTorch", isSelected: selectedFilter == "PyTorch", accentColor: VeloraTheme.accentPink) { selectedFilter = "PyTorch" }
                ToolFilterChip(title: "ComfyUI", isSelected: selectedFilter == "ComfyUI", accentColor: VeloraTheme.accentEmerald) { selectedFilter = "ComfyUI" }
                ToolFilterChip(title: "Loose", isSelected: selectedFilter == "Loose", accentColor: VeloraTheme.textSecondary) { selectedFilter = "Loose" }
                ToolFilterChip(title: "Stale (> 60d)", isSelected: selectedFilter == "Stale", accentColor: VeloraTheme.accentPink) { selectedFilter = "Stale" }

                Spacer()

                // Search Filter Input
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(VeloraTheme.textSecondary)
                    TextField("Filter items...", text: $searchFilter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(VeloraTheme.textPrimary)
                    if !searchFilter.isEmpty {
                        Button(action: { searchFilter = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(VeloraTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
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
            if viewModel.isLoadingAiModels {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Hunting local AI model weights in ~/.cache, ~/.ollama, and workspace caches...")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                }
                Spacer()
            } else if allItems.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 40))
                        .foregroundColor(VeloraTheme.textSecondary)
                    Text("No local AI models detected in standard caches.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                    Button("Scan AI Models Now") {
                        viewModel.loadAiModels()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredItems) { item in
                            AiModelCardRow(
                                item: item,
                                isStaged: stagedPaths.contains(item.path),
                                onToggleStage: { toggleStaging(for: item) }
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(VeloraTheme.obsidianBase)
        .onAppear {
            if viewModel.aiModelSummary == nil {
                viewModel.loadAiModels()
            }
        }
    }
}

// MARK: - Individual Model Card Row Component

private struct AiModelCardRow: View {
    let item: AiModelRecord
    let isStaged: Bool
    let onToggleStage: () -> Void

    @State private var isHovering: Bool = false

    private var formatColor: Color {
        Color(hex: item.colorHex)
    }

    private var inactivityColor: Color {
        if item.inactivityTier.contains("Active") {
            return VeloraTheme.accentEmerald
        } else if item.inactivityTier.contains("Idle") {
            return VeloraTheme.accentAmber
        } else {
            return VeloraTheme.accentPink
        }
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

    private func formatContextLength(_ ctx: UInt32) -> String {
        if ctx >= 1024 {
            return "\(ctx / 1024)k ctx"
        }
        return "\(ctx) ctx"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Format / Ecosystem Icon (32x32 matching DockerDiskRow)
            Image(systemName: iconForFormat(item.formatName))
                .font(.system(size: 16))
                .foregroundColor(formatColor)
                .frame(width: 32, height: 32)
                .background(formatColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            // Details Stack
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    // Ecosystem Capsule Badge
                    Text(item.ecosystemName)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(formatColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(formatColor.opacity(0.15), in: Capsule())

                    if let org = item.organization {
                        Text(org)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VeloraTheme.obsidianSubsurface, in: Capsule())
                    }

                    if isStaged {
                        Text("STAGED")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(VeloraTheme.accentEmerald)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VeloraTheme.accentEmerald.opacity(0.18), in: Capsule())
                    }
                }

                // Subtitle: Metadata Chips & Monospaced Path
                HStack(spacing: 6) {
                    if let arch = item.architecture {
                        HStack(spacing: 3) {
                            Image(systemName: "cpu")
                                .font(.system(size: 8))
                            Text(arch)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(VeloraTheme.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(VeloraTheme.obsidianSubsurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                    }

                    if let quant = item.quantization {
                        HStack(spacing: 3) {
                            Image(systemName: "square.stack.3d.down.right.fill")
                                .font(.system(size: 8))
                            Text(quant)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(VeloraTheme.accentCyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(VeloraTheme.accentCyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }

                    if let param = item.parameterSize {
                        HStack(spacing: 3) {
                            Image(systemName: "number")
                                .font(.system(size: 8))
                            Text(param)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(VeloraTheme.accentAmber)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(VeloraTheme.accentAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }

                    if let ctx = item.contextLength {
                        HStack(spacing: 3) {
                            Image(systemName: "waveform.path")
                                .font(.system(size: 8))
                            Text(formatContextLength(ctx))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(VeloraTheme.accentEmerald)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(VeloraTheme.accentEmerald.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }

                    Text(item.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(VeloraTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            // Trailing Size & Inactivity Age
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatBytes(item.sizeBytes))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)

                let lastDate = max(item.modifiedSecs, item.accessedSecs)
                HStack(spacing: 4) {
                    Circle()
                        .fill(inactivityColor)
                        .frame(width: 5, height: 5)
                    Text(item.inactivityTier.contains("Active") ? "Active (\(formatRelativeDate(secs: lastDate)))" : (item.inactivityTier.contains("Idle") ? "Idle (\(formatRelativeDate(secs: lastDate)))" : "Stale (\(formatRelativeDate(secs: lastDate)))"))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(inactivityColor)
                }
            }

            // Stage Action Button
            Button(action: onToggleStage) {
                Image(systemName: isStaged ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isStaged ? VeloraTheme.accentEmerald : (isHovering ? VeloraTheme.textPrimary : VeloraTheme.textSecondary))
                    .padding(6)
                    .background(isStaged ? VeloraTheme.accentEmerald.opacity(0.15) : VeloraTheme.obsidianElevated, in: Circle())
                    .overlay(Circle().stroke(isStaged ? VeloraTheme.accentEmerald.opacity(0.3) : VeloraTheme.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(isStaged ? "Remove from staged cleanup tray" : "Stage for safe deletion into macOS Trash")
        }
        .padding(12)
        .background(
            isStaged
                ? VeloraTheme.accentEmerald.opacity(0.06)
                : (isHovering ? VeloraTheme.obsidianElevated.opacity(0.9) : VeloraTheme.obsidianElevated),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isStaged
                        ? VeloraTheme.accentEmerald.opacity(0.4)
                        : (isHovering ? VeloraTheme.cardBorderHover : VeloraTheme.cardBorder),
                    lineWidth: 1
                )
        )
        .onHover { h in
            isHovering = h
        }
        .contextMenu {
            Button("Reveal in Finder") {
                let url = URL(fileURLWithPath: item.path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

            Button("Quick Look Preview") {
                QuickLookCoordinator.shared.togglePreview(for: item.path)
            }

            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.path, forType: .string)
            }

            Divider()

            Button(isStaged ? "Remove from Staged Tray" : "Stage for Deletion") {
                onToggleStage()
            }
        }
    }

    private func iconForFormat(_ fmt: String) -> String {
        switch fmt {
        case "GGUF": return "brain.head.profile"
        case "Safetensors": return "cube.transparent.fill"
        case "PyTorch (.pth/.pt)": return "flame.fill"
        case "ONNX": return "network"
        case "Ollama Blob": return "shippingbox.fill"
        default: return "doc.fill"
        }
    }
}
