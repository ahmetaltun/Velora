import SwiftUI
import VeloraCore

struct StorageBreakdownView: View {
    let storage: StorageReconciliationItem
    let usedBytes: UInt64

    private struct VolumeUsage: Identifiable {
        let id: String
        let title: String
        let bytes: UInt64
        let color: Color
    }

    private var volumes: [VolumeUsage] {
        var remaining = usedBytes
        var usage: [VolumeUsage] = []

        for (id, title, measured, color) in [
            ("system", "System", storage.systemVolumeBytes, VeloraTheme.accentBlue),
            ("vm", "Virtual Memory", storage.vmSwapBytes, VeloraTheme.accentAmber),
            ("other", "Other Volumes", storage.otherVolumesBytes, VeloraTheme.accentEmerald)
        ] {
            let bytes = min(measured, remaining)
            guard bytes > 0 else { continue }
            usage.append(VolumeUsage(id: id, title: title, bytes: bytes, color: color))
            remaining -= bytes
        }

        if remaining > 0 {
            let title = usage.isEmpty ? "Used Space" : "Data & Other Usage"
            usage.insert(VolumeUsage(id: "data", title: title, bytes: remaining, color: VeloraTheme.accentViolet), at: 0)
        }
        return usage
    }

    var body: some View {
        let volumes = volumes

        VStack(alignment: .leading, spacing: 10) {
            Text("Used Space by Volume")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(VeloraTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if volumes.isEmpty {
                Text("No used space reported.")
                    .font(.callout)
                    .foregroundStyle(VeloraTheme.textSecondary)
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(volumes) { volume in
                            Rectangle()
                                .fill(volume.color)
                                .frame(width: geometry.size.width * CGFloat(Double(volume.bytes) / Double(usedBytes)))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)
                .accessibilityHidden(true)

                VStack(spacing: 7) {
                    ForEach(volumes) { volume in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(volume.color)
                                .frame(width: 7, height: 7)
                                .accessibilityHidden(true)

                            Text(volume.title)
                                .foregroundStyle(VeloraTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 6)

                            Text(formatBytes(volume.bytes))
                                .monospacedDigit()
                                .foregroundStyle(VeloraTheme.textPrimary)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .font(.callout)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
