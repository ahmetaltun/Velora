import Cocoa
import CoreGraphics
import CoreText

// -----------------------------------------------------------------------------
// Velora Premium DMG Background Artwork Generator
// -----------------------------------------------------------------------------
// Generates:
// 1. background.png    (720x460 px, 1x standard resolution, 72 DPI)
// 2. background@2x.png (1440x920 px, 2x Retina resolution, 144 DPI)
//
// These two assets allow tools like `dmgbuild` and `tiffutil` to assemble
// a true HiDPI/Retina TIFF (.background.tiff) for macOS Finder, perfectly sized
// at 720x460 pt.
// -----------------------------------------------------------------------------

let pointWidth: CGFloat = 720
let pointHeight: CGFloat = 460

func renderImage(scale: CGFloat, outputURL: URL) {
    let pixelWidth = Int(pointWidth * scale)
    let pixelHeight = Int(pointHeight * scale)
    
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        fatalError("Failed to create CoreGraphics bitmap context for scale \(scale)")
    }
    
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.setAllowsFontSmoothing(true)
    context.setShouldSmoothFonts(true)
    context.interpolationQuality = .high
    
    // Scale points to pixels
    context.scaleBy(x: scale, y: scale)
    
    func topY(_ y: CGFloat) -> CGFloat {
        return pointHeight - y
    }
    
    // Colors
    let brandPrimary = NSColor(srgbRed: 0x35/255.0, green: 0x31/255.0, blue: 0x4A/255.0, alpha: 1.0)
    let textSecondary = NSColor(srgbRed: 0x7A/255.0, green: 0x75/255.0, blue: 0x8F/255.0, alpha: 1.0)
    let textTertiary = NSColor(srgbRed: 0x8E/255.0, green: 0x89/255.0, blue: 0xA1/255.0, alpha: 1.0)
    let cardBg = NSColor.white
    let cardBorder = NSColor(srgbRed: 0xE5/255.0, green: 0xE2/255.0, blue: 0xEE/255.0, alpha: 1.0)
    
    // 1. Subtle Canvas Gradient
    let gradientColors = [
        NSColor(srgbRed: 0xF8/255.0, green: 0xF7/255.0, blue: 0xFA/255.0, alpha: 1.0).cgColor,
        NSColor(srgbRed: 0xF3/255.0, green: 0xF2/255.0, blue: 0xF7/255.0, alpha: 1.0).cgColor
    ] as CFArray
    
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 1.0]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: pointHeight),
            end: CGPoint(x: 0, y: 0),
            options: []
        )
    }
    
    // 2. Main Installation Card Container
    let cardWidth: CGFloat = 616
    let cardHeight: CGFloat = 216
    let cardLeft: CGFloat = (pointWidth - cardWidth) / 2 // 52 pt
    let cardTop: CGFloat = 136
    let cardRect = CGRect(x: cardLeft, y: topY(cardTop + cardHeight), width: cardWidth, height: cardHeight)
    let cardRadius: CGFloat = 22
    let cardPath = CGPath(roundedRect: cardRect, cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)
    
    // Soft Ambient Shadow
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -3),
        blur: 14,
        color: NSColor(srgbRed: 0x2A/255.0, green: 0x22/255.0, blue: 0x3E/255.0, alpha: 0.05).cgColor
    )
    context.addPath(cardPath)
    context.setFillColor(cardBg.cgColor)
    context.fillPath()
    context.restoreGState()
    
    // Border
    context.saveGState()
    context.addPath(cardPath)
    context.setStrokeColor(cardBorder.cgColor)
    context.setLineWidth(1.2)
    context.strokePath()
    context.restoreGState()
    
    // 3. Center Installation Arrow
    let arrowCenterY = topY(cardTop + (cardHeight / 2)) // 244 pt from top -> topY(244)
    let arrowLength: CGFloat = 76
    let arrowStartX: CGFloat = (pointWidth / 2) - (arrowLength / 2) // 322 pt
    let arrowEndX: CGFloat = (pointWidth / 2) + (arrowLength / 2)   // 398 pt
    let arrowHeadSize: CGFloat = 9
    
    context.saveGState()
    context.setStrokeColor(brandPrimary.cgColor)
    context.setLineWidth(2.2)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    
    // Shaft
    context.move(to: CGPoint(x: arrowStartX, y: arrowCenterY))
    context.addLine(to: CGPoint(x: arrowEndX, y: arrowCenterY))
    context.strokePath()
    
    // Arrowhead
    context.move(to: CGPoint(x: arrowEndX - arrowHeadSize, y: arrowCenterY + arrowHeadSize * 0.75))
    context.addLine(to: CGPoint(x: arrowEndX, y: arrowCenterY))
    context.addLine(to: CGPoint(x: arrowEndX - arrowHeadSize, y: arrowCenterY - arrowHeadSize * 0.75))
    context.strokePath()
    context.restoreGState()
    
    // 4. Text Rendering Helper
    func drawText(
        _ string: String,
        font: NSFont,
        color: NSColor,
        kern: CGFloat = 0,
        at point: CGPoint
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: kern
        ]
        let attrString = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        
        let baselineY = topY(point.y) - ascent
        
        context.saveGState()
        context.textPosition = CGPoint(x: point.x, y: baselineY)
        CTLineDraw(line, context)
        context.restoreGState()
    }
    
    // 5. Header: "VELORA"
    drawText(
        "VELORA",
        font: NSFont.systemFont(ofSize: 11, weight: .bold),
        color: brandPrimary,
        kern: 3.2,
        at: CGPoint(x: cardLeft, y: 44)
    )
    
    // 6. Main Title: "Welcome to Velora"
    drawText(
        "Welcome to Velora",
        font: NSFont.systemFont(ofSize: 28, weight: .bold),
        color: brandPrimary,
        kern: -0.2,
        at: CGPoint(x: cardLeft, y: 64)
    )
    
    // 7. Subtitle: "Drag Velora into Applications to install."
    drawText(
        "Drag Velora into Applications to install.",
        font: NSFont.systemFont(ofSize: 14, weight: .regular),
        color: textSecondary,
        kern: 0.1,
        at: CGPoint(x: cardLeft, y: 102)
    )
    
    // 8. Footer Section
    drawText(
        "Then open Velora from Applications.",
        font: NSFont.systemFont(ofSize: 13, weight: .medium),
        color: brandPrimary,
        kern: 0.1,
        at: CGPoint(x: cardLeft, y: 382)
    )
    
    drawText(
        "macOS 15+ · Apple Silicon",
        font: NSFont.systemFont(ofSize: 11, weight: .regular),
        color: textTertiary,
        kern: 0.2,
        at: CGPoint(x: cardLeft, y: 405)
    )
    
    // Export PNG with accurate DPI metadata
    guard let cgImage = context.makeImage() else {
        fatalError("Failed to create CGImage from context")
    }
    
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: pointWidth, height: pointHeight)
    
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to convert image to PNG representation")
    }
    
    try? pngData.write(to: outputURL)
    print("   Created: \(outputURL.lastPathComponent) (\(pixelWidth)x\(pixelHeight) px @ \(scale)x)")
}

let fileManager = FileManager.default
let currentDir = fileManager.currentDirectoryPath
let outputDir = URL(fileURLWithPath: currentDir).appendingPathComponent("assets/dmg")
try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)

let bg1xURL = outputDir.appendingPathComponent("background.png")
let bg2xURL = outputDir.appendingPathComponent("background@2x.png")

print("🎨 Rendering Velora DMG background assets...")
renderImage(scale: 1.0, outputURL: bg1xURL)
renderImage(scale: 2.0, outputURL: bg2xURL)
print("✅ Background generation complete.")
