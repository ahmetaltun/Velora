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
        if !viewModel.collectorItems.isEmpty {
            VStack(spacing: 0) {
                Divider()

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
            .transition(.move(edge: .bottom).combined(with: .opacity))
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
