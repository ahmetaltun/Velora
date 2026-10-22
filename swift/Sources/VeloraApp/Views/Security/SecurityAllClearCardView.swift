import SwiftUI

public struct SecurityAllClearCardView: View {
    public let asepCount: UInt32
    public let candidatesCount: UInt32

    public init(asepCount: UInt32, candidatesCount: UInt32) {
        self.asepCount = asepCount
        self.candidatesCount = candidatesCount
    }

    public var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(VeloraTheme.accentEmerald.opacity(0.12))
                    .frame(width: 68, height: 68)

                Circle()
                    .stroke(VeloraTheme.accentEmerald.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 78, height: 78)

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 34))
                    .foregroundColor(VeloraTheme.accentEmerald)
            }
            .padding(.top, 10)

            VStack(spacing: 6) {
                Text("Zero Active Threats Detected")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)

                Text("Velora evaluated \(candidatesCount) system candidates and verified \(asepCount) boot persistence daemons. No malicious hashes, unsigned startup items, or compromised signatures were found.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(VeloraTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }

            // 4 Verified Checks
            HStack(spacing: 12) {
                verifiedCheck(text: "LaunchAgents Clean")
                verifiedCheck(text: "LaunchDaemons Clean")
                verifiedCheck(text: "Mach-O Verified")
                verifiedCheck(text: "Zero IOC Matches")
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    VeloraTheme.accentEmerald.opacity(0.08),
                    VeloraTheme.obsidianSurface
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(VeloraTheme.accentEmerald.opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func verifiedCheck(text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(VeloraTheme.accentEmerald)

            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(VeloraTheme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(VeloraTheme.obsidianElevated, in: Capsule())
        .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
    }
}
