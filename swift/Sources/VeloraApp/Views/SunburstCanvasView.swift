import SwiftUI
import VeloraCore

public struct SunburstCanvasView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var hoveredSector: SunburstSectorItem?

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let maxRadius = min(geometry.size.width, geometry.size.height) * 0.42

            ZStack {
                // Background radial glow
                RadialGradient(
                    gradient: Gradient(colors: [Color.accentColor.opacity(0.08), Color.clear]),
                    center: .center,
                    startRadius: 40,
                    endRadius: maxRadius * 1.2
                )

                if let root = viewModel.currentSunburst {
                    Canvas { context, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        drawSunburst(context: context, center: center, maxRadius: maxRadius, root: root)
                    }
                    .gesture(
                        SpatialTapGesture().onEnded { tap in
                            let location = tap.location
                            if let clicked = findSectorAt(point: location, center: center, maxRadius: maxRadius, root: root) {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                    viewModel.drillDown(sector: clicked)
                                }
                            } else {
                                // Tapped center circle
                                let dist = hypot(location.x - center.x, location.y - center.y)
                                if dist < 65 {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                        viewModel.navigateUp()
                                    }
                                }
                            }
                        }
                    )

                    // Center Circle Info
                    CenterCircleView(root: root, viewModel: viewModel)
                        .frame(width: 130, height: 130)
                } else if viewModel.isScanning {
                    ProgressView(viewModel.scanStatusMessage)
                        .controlSize(.large)
                } else {
                    ContentUnavailableView(
                        "No Disk Data",
                        systemImage: "circle.dashed",
                        description: Text("Select a folder or volume to scan.")
                    )
                }

                // Hovered Tooltip Overlay
                if let hovered = hoveredSector {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: hovered.colorHex))
                                .frame(width: 10, height: 10)
                            Text(hovered.name)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(formatBytes(hovered.sizeBytes))
                                .font(.system(.subheadline, design: .monospaced, weight: .medium))
                            Spacer()
                            Button("Collect") {
                                viewModel.collect(path: hovered.path, size: hovered.sizeBytes, isDir: hovered.isDir)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private func drawSunburst(context: GraphicsContext, center: CGPoint, maxRadius: CGFloat, root: SunburstSectorItem) {
        let baseRadius: CGFloat = 70
        let ringWidth = (maxRadius - baseRadius) / 3.0

        for child in root.children {
            drawSectorRecursive(context: context, center: center, baseRadius: baseRadius, ringWidth: ringWidth, sector: child)
        }
    }

    private func drawSectorRecursive(
        context: GraphicsContext,
        center: CGPoint,
        baseRadius: CGFloat,
        ringWidth: CGFloat,
        sector: SunburstSectorItem
    ) {
        let innerRadius = baseRadius + CGFloat(sector.depth - 1) * (ringWidth + 4)
        let outerRadius = innerRadius + ringWidth

        let startRad = Double(sector.startAngle - 90) * .pi / 180.0
        let endRad = Double(sector.startAngle + sector.sweepAngle - 90) * .pi / 180.0

        var path = Path()
        path.addArc(center: center, radius: innerRadius, startAngle: Angle(radians: startRad), endAngle: Angle(radians: endRad), clockwise: false)
        path.addArc(center: center, radius: outerRadius, startAngle: Angle(radians: endRad), endAngle: Angle(radians: startRad), clockwise: true)
        path.closeSubpath()

        let baseColor = Color(hex: sector.colorHex)
        context.fill(path, with: .color(baseColor.opacity(0.85)))
        context.stroke(path, with: .color(Color.black.opacity(0.4)), lineWidth: 1.5)

        for grandChild in sector.children {
            drawSectorRecursive(context: context, center: center, baseRadius: baseRadius, ringWidth: ringWidth, sector: grandChild)
        }
    }

    private func findSectorAt(point: CGPoint, center: CGPoint, maxRadius: CGFloat, root: SunburstSectorItem) -> SunburstSectorItem? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = hypot(dx, dy)
        let baseRadius: CGFloat = 70
        let ringWidth = (maxRadius - baseRadius) / 3.0

        if dist < baseRadius || dist > maxRadius {
            return nil
        }

        var angleDeg = atan2(dy, dx) * 180.0 / .pi + 90.0
        if angleDeg < 0 {
            angleDeg += 360.0
        }

        let targetDepth = UInt32((dist - baseRadius) / (ringWidth + 4)) + 1
        return searchSector(sector: root, angle: Float(angleDeg), depth: targetDepth)
    }

    private func searchSector(sector: SunburstSectorItem, angle: Float, depth: UInt32) -> SunburstSectorItem? {
        for child in sector.children {
            let start = child.startAngle
            let end = child.startAngle + child.sweepAngle
            if angle >= start && angle <= end {
                if child.depth == depth {
                    return child
                } else if child.depth < depth {
                    if let found = searchSector(sector: child, angle: angle, depth: depth) {
                        return found
                    }
                }
            }
        }
        return nil
    }
}

struct CenterCircleView: View {
    let root: SunburstSectorItem
    let viewModel: VeloraViewModel

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                viewModel.navigateUp()
            }
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)

                VStack(spacing: 4) {
                    Text(root.name)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)

                    Text(formatBytes(root.sizeBytes))
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundColor(.secondary)

                    if viewModel.pathStack.count > 1 {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

public func formatBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useAll]
    return formatter.string(fromByteCount: Int64(bytes))
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 128, 128, 128)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
