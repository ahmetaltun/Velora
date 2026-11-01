import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeloraCore

public struct SecureShredderView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var isDropTargeted: Bool = false

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var activeSnapshotsCount: Int {
        viewModel.storageReconciliation?.snapshots.count ?? 0
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func formatThroughput(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_000_000_000 {
            return String(format: "%.2f GB/s", bytesPerSec / 1_000_000_000.0)
        } else if bytesPerSec >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_000_000.0)
        } else if bytesPerSec >= 1_000 {
            return String(format: "%.0f KB/s", bytesPerSec / 1_000.0)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }

    private func formatETA(_ seconds: Double?) -> String {
        guard let seconds = seconds else { return "Calculating..." }
        let s = max(1, Int(ceil(seconds)))
        if s < 60 {
            return "~\(s)s remaining"
        } else {
            let m = s / 60
            let remS = s % 60
            return "~\(m)m \(remS)s remaining"
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Select Files to Shred Permanently"
        panel.prompt = "Queue for Shredding"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            let paths = panel.urls.map(\.path)
            viewModel.queueForShredding(paths: paths)
        }
    }

    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = "Select Folders to Shred Permanently"
        panel.prompt = "Queue Folder"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK {
            let paths = panel.urls.map(\.path)
            viewModel.queueForShredding(paths: paths)
        }
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        var collectedPaths: [String] = []
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        collectedPaths.append(url.path)
                    } else if let url = item as? URL {
                        collectedPaths.append(url.path)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            if !collectedPaths.isEmpty {
                viewModel.queueForShredding(paths: collectedPaths)
            }
        }
        return true
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            BloomToolHeaderView(
                title: "Cryptographic Secure Shredder",
                subtitle: "Multi-pass physical block sanitization, POSIX F_FULLFSYNC hardware flush & directory inode scrubbing",
                systemImage: "lock.shield.fill",
                accentColor: VeloraTheme.accentPink
            ) {
                HStack(spacing: 10) {
                    Button(action: openFilePicker) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Add Files...")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(VeloraTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(VeloraTheme.obsidianSurface, in: Capsule())
                        .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isShredding)

                    Button(action: openFolderPicker) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Add Folder...")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(VeloraTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(VeloraTheme.obsidianSurface, in: Capsule())
                        .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isShredding)
                }
            }

            // Error banner if any
            if let errorMsg = viewModel.shredErrorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(VeloraTheme.accentAmber)
                    Text(errorMsg)
                        .font(.system(size: 12))
                        .foregroundColor(VeloraTheme.textPrimary)
                        .lineLimit(2)
                    Spacer()
                    Button(action: { viewModel.shredErrorMessage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(VeloraTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(VeloraTheme.accentAmber.opacity(0.16))
                Divider().overlay(VeloraTheme.cardBorder)
            }

            // Main Content Area
            if viewModel.isShredding {
                shreddingActiveView
            } else {
                standardQueueView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VeloraTheme.obsidianBase)
        .sheet(isPresented: $viewModel.isShredConfirmationPresented) {
            ShredConfirmationSheet(viewModel: viewModel, isPresented: $viewModel.isShredConfirmationPresented)
        }
    }

    // MARK: - Standard View (Drop Zone + Queue + Algorithm)

    private var standardQueueView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Side-by-side Drop Zone and Staged Targets cards
                HStack(alignment: .top, spacing: 16) {
                    dropZoneCard
                        .frame(maxWidth: .infinity)

                    if !viewModel.shredQueue.isEmpty {
                        queuedItemsCard
                            .frame(maxWidth: .infinity)
                    } else {
                        emptyQueuedCard
                            .frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                // APFS Snapshot Advisory if detected
                if activeSnapshotsCount > 0 {
                    apfsAdvisoryCard
                }

                // Algorithm Selection Cards
                algorithmSelectorCard
            }
            .padding(24)
        }
    }

    private var dropZoneCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDropTargeted ? VeloraTheme.accentPink : VeloraTheme.cardBorder,
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2.5 : 1.5, dash: [8, 6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isDropTargeted ? VeloraTheme.accentPink.opacity(0.08) : VeloraTheme.obsidianElevated.opacity(0.7))
                )

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [VeloraTheme.accentPink.opacity(0.35), Color.clear],
                                center: .center,
                                startRadius: 4,
                                endRadius: 32
                            )
                        )
                        .frame(width: 64, height: 64)

                    Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "lock.shield.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(isDropTargeted ? VeloraTheme.accentCyan : VeloraTheme.accentPink)
                        .scaleEffect(isDropTargeted ? 1.15 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDropTargeted)
                }

                VStack(spacing: 3) {
                    Text(isDropTargeted ? "Release to stage for sanitization" : "Drop sensitive files or folders here")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text("Bypasses Trash • Physical block rewrite\nPOSIX F_FULLFSYNC • Inode metadata scrambling")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(VeloraTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                HStack(spacing: 10) {
                    Button(action: openFilePicker) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 11))
                            Text("Select Files")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(VeloraTheme.textPrimary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(VeloraTheme.obsidianSurface, in: Capsule())
                        .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button(action: openFolderPicker) {
                        HStack(spacing: 5) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 11))
                            Text("Select Folder")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(VeloraTheme.textPrimary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(VeloraTheme.obsidianSurface, in: Capsule())
                        .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
        }
        .frame(height: 220)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDroppedProviders(providers)
        }
    }

    private var emptyQueuedCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(VeloraTheme.obsidianElevated.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(VeloraTheme.cardBorder, lineWidth: 1))

            VStack(spacing: 0) {
                // Header bar
                HStack(spacing: 10) {
                    Text("Staged Targets (0)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider().overlay(VeloraTheme.cardBorder)

                // Empty state body
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 26))
                        .foregroundColor(VeloraTheme.textMuted.opacity(0.5))

                    Text("No Targets Staged")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)

                    Text("Drop files or folders into the dropzone to review before permanent destruction.")
                        .font(.system(size: 11))
                        .foregroundColor(VeloraTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 12)

                Divider().overlay(VeloraTheme.cardBorder)

                // Footer placeholder
                HStack(spacing: 12) {
                    Text("Awaiting targets...")
                        .font(.system(size: 11))
                        .foregroundColor(VeloraTheme.textMuted)

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "flame")
                            .font(.system(size: 11))
                        Text("Secure Shred")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(VeloraTheme.textMuted.opacity(0.4))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(VeloraTheme.obsidianSurface.opacity(0.6), in: Capsule())
                    .overlay(Capsule().stroke(VeloraTheme.cardBorder.opacity(0.5), lineWidth: 1))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(VeloraTheme.obsidianElevated)
            }
        }
        .frame(height: 220)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDroppedProviders(providers)
        }
    }

    private var apfsAdvisoryCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(VeloraTheme.accentAmber)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("APFS Local Snapshot Advisory")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.accentAmber)

                Text("\(activeSnapshotsCount) active APFS local snapshot(s) exist on this container. Velora guarantees low-level hardware overwrite via F_FULLFSYNC on active file blocks; however, historic data versions preserved in existing APFS snapshots will persist until those snapshots are pruned or expire.")
                    .font(.system(size: 11))
                    .foregroundColor(VeloraTheme.textSecondary)
                    .lineSpacing(2)
            }
            Spacer()
        }
        .padding(14)
        .background(VeloraTheme.accentAmber.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VeloraTheme.accentAmber.opacity(0.3), lineWidth: 1))
    }

    private var algorithmSelectorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sanitization Specification")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)
                Spacer()
                Text("Enforces hardware write sync")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(VeloraTheme.textMuted)
            }

            let algorithms: [ShredAlgorithm] = [.zero, .randomNist80088, .dod522022M, .dod522022MEce]

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(algorithms) { algo in
                    let isSelected = viewModel.selectedShredAlgorithm == algo
                    Button(action: {
                        viewModel.selectedShredAlgorithm = algo
                    }) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(algo.title)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(isSelected ? VeloraTheme.textPrimary : VeloraTheme.textSecondary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(VeloraTheme.accentPink)
                                        .font(.system(size: 12))
                                }
                            }

                            Text(algo.description)
                                .font(.system(size: 11))
                                .foregroundColor(VeloraTheme.textMuted)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            isSelected ? VeloraTheme.accentPink.opacity(0.12) : VeloraTheme.obsidianElevated,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? VeloraTheme.accentPink : VeloraTheme.cardBorder, lineWidth: isSelected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(VeloraTheme.cardBorder, lineWidth: 1))
    }

    private var queuedItemsCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(VeloraTheme.obsidianElevated)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(VeloraTheme.cardBorder, lineWidth: 1))

            VStack(spacing: 0) {
                // Queue header bar
                HStack(spacing: 10) {
                    Text("Staged Targets (\(viewModel.shredQueue.count))")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text("•")
                        .foregroundColor(VeloraTheme.textMuted)

                    Text("Total \(formatBytes(viewModel.shredQueueTotalSize))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(VeloraTheme.accentCyan)

                    Spacer()

                    Button("Clear All") {
                        viewModel.clearShredQueue()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(VeloraTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(VeloraTheme.obsidianSurface, in: Capsule())
                    .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider().overlay(VeloraTheme.cardBorder)

                // Scrollable Items List
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 1) {
                        ForEach(viewModel.shredQueue) { item in
                            HStack(spacing: 10) {
                                Image(systemName: item.isDir ? "folder.fill" : "doc.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(item.isDir ? VeloraTheme.accentAmber : VeloraTheme.accentCyan)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(VeloraTheme.textPrimary)
                                        .lineLimit(1)

                                    Text(item.path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(VeloraTheme.textMuted)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer()

                                Text(formatBytes(item.sizeBytes))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(VeloraTheme.textSecondary)

                                Button(action: {
                                    viewModel.removeFromShredQueue(id: item.id)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(VeloraTheme.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove from shred queue")
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(VeloraTheme.obsidianSurface.opacity(0.45))
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                Divider().overlay(VeloraTheme.cardBorder)

                // Primary Shred Action Bar
                HStack(spacing: 10) {
                    Text("Permanent overwriting will commence upon confirmation")
                        .font(.system(size: 10.5))
                        .foregroundColor(VeloraTheme.textMuted)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: {
                        viewModel.isShredConfirmationPresented = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Secure Shred (\(viewModel.shredQueue.count) Items)...")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [VeloraTheme.accentPink, Color(hex: "#DC2626")],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                        .shadow(color: VeloraTheme.accentPink.opacity(0.4), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(VeloraTheme.obsidianElevated)
            }
        }
        .frame(height: 220)
    }

    // MARK: - Active Shredding View (HUD)

    private var shreddingActiveView: some View {
        VStack(spacing: 28) {
            Spacer()

            // Large Animated Pulse Center
            ZStack {
                Circle()
                    .stroke(VeloraTheme.accentPink.opacity(0.2), lineWidth: 8)
                    .frame(width: 140, height: 140)

                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.shredProgress))
                    .stroke(
                        AngularGradient(
                            colors: [VeloraTheme.accentPink, Color(hex: "#EF4444"), VeloraTheme.accentCyan],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 140, height: 140)
                    .animation(.linear(duration: 0.1), value: viewModel.shredProgress)

                VStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(VeloraTheme.accentPink)

                    Text("\(Int(viewModel.shredProgress * 100))%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                }
            }

            // Status & Pass Information
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("Sanitizing Item \(min(viewModel.shredCurrentIndex, viewModel.shredTotalCount)) of \(viewModel.shredTotalCount)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text("•")
                        .foregroundColor(VeloraTheme.textMuted)

                    Text("Pass \(viewModel.shredCurrentPass)/\(viewModel.shredTotalPasses)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.accentCyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(VeloraTheme.accentCyan.opacity(0.15), in: Capsule())
                }

                Text(viewModel.shredPassDescription)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(VeloraTheme.accentAmber)

                if !viewModel.shredCurrentFileName.isEmpty {
                    Text(viewModel.shredCurrentFileName)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(VeloraTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 500)
                }
            }

            // Progress Metrics Row
            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    Text("THROUGHPUT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(VeloraTheme.textMuted)
                    Text(formatThroughput(viewModel.shredThroughputBytesPerSec))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(VeloraTheme.textPrimary)
                }

                Divider()
                    .frame(height: 24)
                    .overlay(VeloraTheme.cardBorder)

                VStack(spacing: 2) {
                    Text("WRITTEN")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(VeloraTheme.textMuted)
                    Text("\(formatBytes(viewModel.shredBytesProcessed)) / \(formatBytes(viewModel.shredTotalBytes))")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(VeloraTheme.textPrimary)
                }

                Divider()
                    .frame(height: 24)
                    .overlay(VeloraTheme.cardBorder)

                VStack(spacing: 2) {
                    Text("TIME REMAINING")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(VeloraTheme.textMuted)
                    Text(formatETA(viewModel.shredEstimatedSecondsRemaining))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(VeloraTheme.accentCyan)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(VeloraTheme.cardBorder, lineWidth: 1))

            // Abort Button
            Button(action: {
                viewModel.cancelShredding()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 12))
                    Text("Abort Shredding")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(Color(hex: "#EF4444"))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Color(hex: "#EF4444").opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(Color(hex: "#EF4444").opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
