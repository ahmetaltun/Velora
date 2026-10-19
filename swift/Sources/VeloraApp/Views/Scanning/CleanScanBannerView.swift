import SwiftUI

public struct CleanScanBannerView: View {
    @Bindable public var viewModel: VeloraViewModel

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Heartbeat Radar Orb
            PulsingOrbView(isScanning: viewModel.isScanning, size: 16)

            // Middle Section: Path Ticker & Shimmer Laser
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Scanning")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundColor(VeloraTheme.mint)

                    Text(viewModel.currentScanPath.isEmpty ? viewModel.currentPath : viewModel.currentScanPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                LaserTrackView(isScanning: viewModel.isScanning, height: 3)
            }

            Spacer(minLength: 16)

            // Trailing Section: Metric Badges & Abort Action
            HStack(spacing: 8) {
                MetricPillView(
                    icon: "doc.on.doc.fill",
                    value: formatItemCount(viewModel.scannedCount),
                    unit: "items",
                    tintColor: VeloraTheme.mint
                )

                if viewModel.scanThroughput > 0 {
                    MetricPillView(
                        icon: "bolt.fill",
                        value: formatThroughput(viewModel.scanThroughput),
                        unit: "/s",
                        tintColor: VeloraTheme.amber
                    )
                }

                Button(action: {
                    viewModel.cancelScan()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Stop scanning")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(VeloraTheme.specularRim, lineWidth: 1)
        )
        .shadow(color: VeloraTheme.glow, radius: 8, x: 0, y: 3)
        .shadow(color: Color.black.opacity(0.12), radius: 5, x: 0, y: 2)
    }

    private func formatItemCount(_ count: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private func formatThroughput(_ rate: Double) -> String {
        if rate >= 1000 {
            return String(format: "%.1fk", rate / 1000.0)
        } else {
            return String(format: "%.0f", rate)
        }
    }
}
