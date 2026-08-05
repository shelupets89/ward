import AppKit

// Draws Ward's app icon into an .iconset directory. Run via scripts/make-icon.sh,
// which turns the result into Support/Ward.icns.
//
// The icon is drawn rather than stored as artwork so it stays editable in a
// diff: the shape, the gradient and the glyph are all right here. It reuses the
// same SF Symbol vocabulary as the menu bar — a bolt for "this Mac is currently
// altered" — inside a shield for the app's name.

/// Top-level `try` in a script exits with a raw LLVM stack dump, which is a
/// poor thing to hand someone whose disk filled up mid-render. Everything that
/// can fail reports through here instead.
func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write("make-icon: \(message)\n".data(using: .utf8) ?? Data())
    exit(code)
}

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    fail("usage: make-icon.swift <output.iconset>", code: 2)
}
let outputDirectory = arguments[1]

/// The sizes `iconutil` expects, with the filenames it matches them by.
let iconSizes: [(pixels: Int, name: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

let symbolName = "bolt.shield.fill"
let gradientTop = NSColor(srgbRed: 0.36, green: 0.42, blue: 0.95, alpha: 1)
let gradientBottom = NSColor(srgbRed: 0.16, green: 0.19, blue: 0.55, alpha: 1)
let boltColor = NSColor(srgbRed: 0.24, green: 0.29, blue: 0.78, alpha: 1)

func drawIcon(pixelSize: Int) -> NSBitmapImageRep? {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }
    representation.size = NSSize(width: pixelSize, height: pixelSize)

    guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
        return nil
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context

    let side = CGFloat(pixelSize)
    // macOS insets the artwork inside the canvas rather than filling it; the
    // corner radius is the squircle proportion Apple's own icons use.
    let inset = side * 0.085
    let badge = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let badgePath = NSBezierPath(roundedRect: badge, xRadius: badge.width * 0.2237, yRadius: badge.width * 0.2237)
    NSGradient(colors: [gradientTop, gradientBottom])?.draw(in: badgePath, angle: -90)

    // Two palette colours, in layer order: the bolt, then the shield behind it.
    // One colour would flatten both layers and the bolt would vanish.
    let configuration = NSImage.SymbolConfiguration(pointSize: badge.height * 0.56, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [boltColor, .white]))
    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else {
        fail("the symbol \(symbolName) is unavailable on this macOS version")
    }
    let glyphHeight = badge.height * 0.60
    let glyphWidth = glyphHeight * (symbol.size.width / symbol.size.height)
    symbol.draw(
        in: NSRect(
            x: badge.midX - glyphWidth / 2,
            y: badge.midY - glyphHeight / 2,
            width: glyphWidth,
            height: glyphHeight
        ),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    return representation
}

do {
    try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
} catch {
    fail("could not create \(outputDirectory): \(error.localizedDescription)")
}

for iconSize in iconSizes {
    guard let representation = drawIcon(pixelSize: iconSize.pixels),
          let pngData = representation.representation(using: .png, properties: [:]) else {
        fail("could not render \(iconSize.name)")
    }
    do {
        try pngData.write(to: URL(fileURLWithPath: "\(outputDirectory)/\(iconSize.name)"))
    } catch {
        fail("could not write \(iconSize.name): \(error.localizedDescription)")
    }
}

print("Rendered \(iconSizes.count) sizes into \(outputDirectory)")
