import SwiftUI
import VeloraCore

public struct CollectorTrayView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var isCountdownActive: Bool = false
    @State private var countdownRemaining: Int = 5
    @State private var timer: Timer?

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if !viewModel.collectorItems.isEmpty || viewModel.isCleaning {
            VStack(spacing: 0) {
                Divider().overlay(VeloraTheme.cardBorder)

                if let errorMsg = viewModel.cleaningErrorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(VeloraTheme.accentAmber)
                        Text(errorMsg)
                            .font(.system(size: 12))
                            .foregroundColor(VeloraTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Button(action: { viewModel.cleaningErrorMessage = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(VeloraTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(VeloraTheme.accentAmber.opacity(0.18))
                    Divider().overlay(VeloraTheme.cardBorder)
                }

                if viewModel.isCleaning {
                    // Active Batch Trashing Progress & Loader UI
                    HStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.regular)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("Trashing \(viewModel.cleaningDisplayIndex) of \(viewModel.cleaningTotalCount) items...")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(VeloraTheme.textPrimary)

                                if !viewModel.cleaningCurrentFileName.isEmpty {
                                    Text("•")
                                        .foregroundColor(VeloraTheme.textMuted)
                                    Text(viewModel.cleaningCurrentFileName)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(VeloraTheme.textSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }

                            ProgressView(value: viewModel.cleaningProgress)
                                .tint(VeloraTheme.accentViolet)
                        }

                        // Remaining time and freed capacity badge
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "hourglass")
                                    .font(.system(size: 10))
                                Text(formatETA(viewModel.cleaningEstimatedSecondsRemaining))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(VeloraTheme.accentAmber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(VeloraTheme.accentAmber.opacity(0.15), in: Capsule())

                            Text("\(formatBytes(viewModel.cleaningFreedBytes)) / \(formatBytes(viewModel.cleaningTotalBytes))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(VeloraTheme.textSecondary)
                        }

                        Button("Stop") {
                            viewModel.cancelCleaning()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(VeloraTheme.obsidianSurface, in: Capsule())
                        .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(VeloraTheme.obsidianElevated)
                } else {
                    // Standard Staging & Actions Bar
                    HStack(spacing: 16) {
                        // Collector Icon & Badge
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(VeloraTheme.accentViolet.opacity(0.18))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(VeloraTheme.accentViolet)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cleanup basket")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(VeloraTheme.textPrimary)
                                Text("\(viewModel.collectorItems.count) items staged (Free \(formatBytes(viewModel.collectorTotalSize)))")
                                    .font(.system(size: 11))
                                    .foregroundColor(VeloraTheme.textSecondary)
                            }
                        }

                        Spacer()

                        // Staged files preview capsule
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.collectorItems, id: \.path) { item in
                                    HStack(spacing: 6) {
                                        Image(systemName: item.isDir ? "folder.fill" : "doc.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(VeloraTheme.accentCyan)
                                        Text((item.path as NSString).lastPathComponent)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(VeloraTheme.textPrimary)
                                            .lineLimit(1)
                                        Text(formatBytes(item.sizeBytes))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(VeloraTheme.textMuted)
                                        Button(action: {
                                            viewModel.removeCollected(path: item.path)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(VeloraTheme.textSecondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(VeloraTheme.obsidianSurface, in: Capsule())
                                    .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                                }
                            }
                        }
                        .frame(maxWidth: 420)

                        // Actions
                        HStack(spacing: 10) {
                            Button("Clear") {
                                cancelCountdown()
                                viewModel.clearCollector()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(VeloraTheme.obsidianSurface, in: Capsule())
                            .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))

                            if isCountdownActive {
                                Button(action: cancelCountdown) {
                                    HStack(spacing: 6) {
                                        Text("Cancel (\(countdownRemaining)s)")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                        ProgressView()
                                            .controlSize(.mini)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(VeloraTheme.obsidianSurface, in: Capsule())
                                    .overlay(Capsule().stroke(VeloraTheme.accentPink, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button(action: startCountdown) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Free Space")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(
                                        LinearGradient(
                                            colors: [VeloraTheme.accentViolet, VeloraTheme.accentPurple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        in: Capsule()
                                    )
                                    .shadow(color: VeloraTheme.accentViolet.opacity(0.35), radius: 6, x: 0, y: 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(VeloraTheme.obsidianElevated)
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func formatETA(_ seconds: Double?) -> String {
        guard let seconds = seconds else { return "Estimating..." }
        let rounded = max(1, Int(ceil(seconds)))
        if rounded < 60 {
            return "~\(rounded)s remaining"
        } else {
            let mins = rounded / 60
            let secs = rounded % 60
            return "~\(mins)m \(secs)s remaining"
        }
    }

    private func startCountdown() {
        isCountdownActive = true
        countdownRemaining = 5

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            if countdownRemaining > 1 {
                countdownRemaining -= 1
            } else {
                t.invalidate()
                isCountdownActive = false
                viewModel.cleanStagedItems()
            }
        }
    }

    private func cancelCountdown() {
        timer?.invalidate()
        timer = nil
        isCountdownActive = false
        countdownRemaining = 5
    }
}
