import AppKit
import SwiftUI

public struct FullDiskAccessBannerView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(VeloraTheme.accentAmber.opacity(0.18))
                    .frame(width: 30, height: 30)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(VeloraTheme.accentAmber)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access Recommended")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)

                Text("Velora requires Full Disk Access to scan protected system caches, snapshots, and orphaned residues.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(VeloraTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button(action: {
                permissionManager.openFullDiskAccessSettings()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Grant Access")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(VeloraTheme.ctaGradient, in: Capsule())
                .shadow(color: VeloraTheme.accentViolet.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    permissionManager.dismissBanner()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(VeloraTheme.textMuted)
                    .padding(5)
                    .background(VeloraTheme.obsidianElevated, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss notification")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(VeloraTheme.obsidianElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(VeloraTheme.accentAmber.opacity(0.35), lineWidth: 1)
                )
        )
    }
}
