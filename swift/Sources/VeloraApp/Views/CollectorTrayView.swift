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
                Divider()

                if let errorMsg = viewModel.cleaningErrorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                        Button(action: { viewModel.cleaningErrorMessage = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(Color.yellow.opacity(0.12))
                    Divider()
                }

                if viewModel.isCleaning {
                    // Active Batch Trashing Progress & Loader UI
                    HStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.regular)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("Trashing \(viewModel.cleaningDisplayIndex) of \(viewModel.cleaningTotalCount) items...")
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))

                                if !viewModel.cleaningCurrentFileName.isEmpty {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text(viewModel.cleaningCurrentFileName)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }

                            ProgressView(value: viewModel.cleaningProgress)
                                .tint(.orange)
                        }

                        // Remaining time and freed capacity badge
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "hourglass")
                                    .font(.system(size: 10))
                                Text(formatETA(viewModel.cleaningEstimatedSecondsRemaining))
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12), in: Capsule())

                            Text("\(formatBytes(viewModel.cleaningFreedBytes)) / \(formatBytes(viewModel.cleaningTotalBytes))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Button("Stop") {
                            viewModel.cancelCleaning()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                } else {
                    // Standard Staging & Actions Bar
                    HStack(spacing: 16) {
                        // Collector Icon & Badge
                        HStack(spacing: 8) {
                            Image(systemName: "trash.circle.fill")
                                .font(.title2)
                                .foregroundColor(.orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Collector Tray")
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                Text("\(viewModel.collectorItems.count) items staged (Ready to free \(formatBytes(viewModel.collectorTotalSize)))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        // Staged files preview capsule
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.collectorItems, id: \.path) { item in
                                    HStack(spacing: 6) {
                                        Image(systemName: item.isDir ? "folder.fill" : "doc.fill")
                                            .font(.caption)
                                        Text((item.path as NSString).lastPathComponent)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Text(formatBytes(item.sizeBytes))
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Button(action: {
                                            viewModel.removeCollected(path: item.path)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.quaternary, in: Capsule())
                                }
                            }
                        }
                        .frame(maxWidth: 400)

                        // Actions
                        HStack(spacing: 10) {
                            Button("Clear") {
                                cancelCountdown()
                                viewModel.clearCollector()
                            }
                            .controlSize(.small)

                            if isCountdownActive {
                                Button(action: cancelCountdown) {
                                    HStack(spacing: 6) {
                                        Text("Cancel (\(countdownRemaining)s)")
                                        ProgressView()
                                            .controlSize(.mini)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.small)
                            } else {
                                Button(action: startCountdown) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash.fill")
                                        Text("Free Space")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
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
