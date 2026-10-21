import SwiftUI
import VeloraCore

public struct StorageDonutChartView: View {
    @Bindable public var viewModel: VeloraViewModel

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private struct SliceItem: Identifiable {
        let id: String
        let title: String
        let bytes: UInt64
        let color: Color
    }

    private var rec: StorageReconciliationItem? {
        viewModel.storageReconciliation
    }

    private var isBusy: Bool {
        viewModel.isScanning || viewModel.isLoadingSnapshot
    }

    private var hasCatalog: Bool {
        viewModel.hasBinaryIndex || viewModel.hasIndexedData
    }

    private var totalBytes: UInt64 {
        rec?.containerTotalBytes ?? 0
    }

    private var freeBytes: UInt64 {
        rec?.containerFreeBytes ?? 0
    }

    private var usedBytes: UInt64 {
        totalBytes > freeBytes ? totalBytes - freeBytes : 0
    }

    private var slices: [SliceItem] {
        guard hasCatalog else { return [] }

        let system = rec?.systemVolumeBytes ?? 0
        let apps = viewModel.installedApps.reduce(UInt64(0)) { $0 + $1.totalSizeBytes }
        let dev = viewModel.devArtifacts.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        let caches = (viewModel.packageCacheSummary?.totalBytes ?? 0) + (viewModel.xcodeSummary?.totalBytes ?? 0)
        let other = rec?.otherVolumesBytes ?? 0

        var list: [SliceItem] = []
        if system > 0 {
            list.append(SliceItem(id: "system", title: "System", bytes: system, color: VeloraTheme.accentBlue))
        }
        if apps > 0 {
            list.append(SliceItem(id: "apps", title: "Applications", bytes: apps, color: VeloraTheme.accentPink))
        }
        if dev > 0 {
            list.append(SliceItem(id: "dev", title: "Developer", bytes: dev, color: VeloraTheme.accentEmerald))
        }
        if caches > 0 {
            list.append(SliceItem(id: "caches", title: "Caches", bytes: caches, color: VeloraTheme.accentAmber))
        }
        if other > 0 {
            list.append(SliceItem(id: "other", title: "Other", bytes: other, color: VeloraTheme.accentPurple))
        }
        return list
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func percentage(for bytes: UInt64) -> Int {
        let total = slices.reduce(0) { $0 + $1.bytes }
        guard total > 0 else { return 0 }
        return Int(round((Double(bytes) / Double(total)) * 100))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title
            Text("Storage Usage")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(VeloraTheme.textPrimary)

            HStack(spacing: 20) {
                // Donut Chart Canvas
                ZStack {
                    GeometryReader { geo in
                        let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                        let radius = min(geo.size.width, geo.size.height) / 2 - 10
                        let total = Double(slices.reduce(0) { $0 + $1.bytes })

                        // Background track circle
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 16)
                            .padding(10)

                        if total > 0 {
                            Canvas { ctx, size in
                                var startAngle = Angle(degrees: -90)
                                for slice in slices {
                                    let sweep = Angle(degrees: (Double(slice.bytes) / total) * 360)
                                    let endAngle = startAngle + sweep

                                    var path = Path()
                                    path.addArc(
                                        center: center,
                                        radius: radius,
                                        startAngle: startAngle + Angle(degrees: 1),
                                        endAngle: endAngle - Angle(degrees: 1),
                                        clockwise: false
                                    )

                                    ctx.stroke(
                                        path,
                                        with: .color(slice.color),
                                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                                    )

                                    startAngle = endAngle
                                }
                            }
                        }
                    }
                    .frame(width: 130, height: 130)

                    // Center Metric
                    VStack(spacing: 2) {
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                            Text("Calculating")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(VeloraTheme.textSecondary)
                        } else if !hasCatalog {
                            Text("—")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(VeloraTheme.textPrimary)
                            Text("Not Scanned")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(VeloraTheme.textSecondary)
                        } else {
                            Text(formatBytes(usedBytes))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(VeloraTheme.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text("Used")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(VeloraTheme.textSecondary)
                        }
                    }
                }
                .frame(width: 130, height: 130)

                // Category Legend
                VStack(spacing: 8) {
                    if isBusy {
                        Text("Auditing storage categories...")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !hasCatalog {
                        Text("Scan disk to analyze storage breakdown by categories.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(VeloraTheme.textMuted)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if slices.isEmpty {
                        Text("Calculating category distribution...")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(slices) { slice in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(slice.color)
                                    .frame(width: 7, height: 7)

                                Text(slice.title)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(VeloraTheme.textSecondary)

                                Spacer()

                                Text(formatBytes(slice.bytes))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(VeloraTheme.textPrimary)

                                Text("\(percentage(for: slice.bytes))%")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(VeloraTheme.textMuted)
                                    .frame(width: 28, alignment: .trailing)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(VeloraTheme.cardBorder, lineWidth: 1)
        )
    }
}
