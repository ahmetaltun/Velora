import SwiftUI
import VeloraCore

public struct LinearStorageGaugeCardView: View {
    @Bindable public var viewModel: VeloraViewModel

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var rec: StorageReconciliationItem? {
        viewModel.storageReconciliation
    }

    private var isBusy: Bool {
        viewModel.isReconcilingStorage || viewModel.isScanning
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

    private var usedRatio: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(usedBytes) / Double(totalBytes)))
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            Text("Disk Space")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(VeloraTheme.textPrimary)

            // Volume Row
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(VeloraTheme.accentViolet.opacity(0.18))
                        .frame(width: 34, height: 34)

                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 16))
                        .foregroundColor(VeloraTheme.accentViolet)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Macintosh HD")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text("APFS Container")
                        .font(.system(size: 10))
                        .foregroundColor(VeloraTheme.textMuted)
                }

                Spacer()

                if isBusy && totalBytes == 0 {
                    Text("Calculating...")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                } else if totalBytes == 0 {
                    Text("—")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                } else {
                    Text("\(formatBytes(usedBytes)) / \(formatBytes(totalBytes))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                }
            }

            // Smooth Gradient Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 8)

                    if usedRatio > 0 {
                        Capsule()
                            .fill(VeloraTheme.storageGauge)
                            .frame(width: max(8, geo.size.width * usedRatio), height: 8)
                            .shadow(color: Color(hex: "#9381F3").opacity(0.35), radius: 4, x: 0, y: 0)
                    }
                }
            }
            .frame(height: 8)

            // Free Space Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(totalBytes > 0 ? VeloraTheme.accentEmerald : VeloraTheme.textMuted)
                    .frame(width: 7, height: 7)

                Text("Free Space")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(VeloraTheme.textSecondary)

                Spacer()

                if isBusy && totalBytes == 0 {
                    Text("...")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                } else if totalBytes == 0 {
                    Text("—")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                } else {
                    Text(formatBytes(freeBytes))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                }
            }

            Spacer(minLength: 4)

            // Tip Banner (Rocket Box)
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(VeloraTheme.accentViolet.opacity(0.18))
                        .frame(width: 36, height: 36)

                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundColor(VeloraTheme.accentViolet)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("More free space, more possibilities.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text("Clean up build caches and residue to keep your Mac fast.")
                        .font(.system(size: 11))
                        .foregroundColor(VeloraTheme.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(VeloraTheme.cardBorder, lineWidth: 1)
            )
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
