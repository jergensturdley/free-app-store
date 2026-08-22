// Generates a large marketing banner for the app, matching the icon's
// visual identity (blue → purple gradient, white bag, green check seal).
// Usage: make_banner <output-png-path>
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: make_banner <out.png>\n".data(using: .utf8)!)
    exit(1)
}
let outPath = args[1]

let width: CGFloat = 1600
let height: CGFloat = 900

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

// MARK: Background — diagonal blue→purple gradient
// Solid base fill first: a diagonal gradient can leave the far corner
// unpainted (transparent), so paint the end color underneath.
NSColor(srgbRed: 0.42, green: 0.22, blue: 0.94, alpha: 1.0).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

let bgGradient = NSGradient(
    starting: NSColor(srgbRed: 0.13, green: 0.56, blue: 0.98, alpha: 1.0),
    ending: NSColor(srgbRed: 0.42, green: 0.22, blue: 0.94, alpha: 1.0)
)
bgGradient?.draw(in: CGRect(x: 0, y: 0, width: width, height: height), angle: -55)

// Soft radial glow, top-left
let glow = NSGradient(
    starting: NSColor.white.withAlphaComponent(0.16),
    ending: NSColor.white.withAlphaComponent(0.0)
)
let glowRect = CGRect(x: -240, y: 250, width: 1100, height: 1100)
glow?.draw(in: glowRect, relativeCenterPosition: .zero)

// MARK: Decorative oversized bag, right side (behind the text)
if let deco = NSImage(systemSymbolName: "bag.fill", accessibilityDescription: nil),
   let decoConfig = deco.withSymbolConfiguration(
       NSImage.SymbolConfiguration(pointSize: 720, weight: .semibold))
   ?? Optional.some(deco) {
    let tinted = NSImage(size: decoConfig.size)
    tinted.lockFocus()
    decoConfig.draw(at: .zero, from: .zero, operation: .copy, fraction: 1)
    // Tint the silhouette opaque white, then draw it near-transparent so it
    // reads as a soft highlight rather than a black shape.
    NSColor.white.setFill()
    NSRect(origin: .zero, size: decoConfig.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.draw(
        in: CGRect(x: 930, y: -80, width: 820, height: 820),
        from: .zero, operation: .sourceOver, fraction: 0.10
    )
}

// MARK: Icon tile
let tileRect = CGRect(x: 120, y: 470, width: 200, height: 200)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 46, yRadius: 46)
let tileGradient = NSGradient(
    starting: NSColor(srgbRed: 0.16, green: 0.62, blue: 0.99, alpha: 1.0),
    ending: NSColor(srgbRed: 0.44, green: 0.28, blue: 0.96, alpha: 1.0)
)
tileGradient?.draw(in: tile, angle: -90)

func drawSymbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor,
                center: NSPoint) {
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let configured = symbol.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)) ?? Optional.some(symbol)
    else { return }
    let s = configured.size
    let tinted = NSImage(size: s)
    tinted.lockFocus()
    configured.draw(at: .zero, from: .zero, operation: .copy, fraction: 1)
    color.setFill()
    NSRect(origin: .zero, size: s).fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.draw(
        in: CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height),
        from: .zero, operation: .sourceOver, fraction: 1
    )
}

drawSymbol("bag.fill", pointSize: 108, weight: .semibold, color: .white,
           center: NSPoint(x: tileRect.midX, y: tileRect.midY + 6))
drawSymbol("checkmark.seal.fill", pointSize: 74, weight: .bold,
           color: NSColor(srgbRed: 0.20, green: 0.85, blue: 0.45, alpha: 1.0),
           center: NSPoint(x: tileRect.maxX - 2, y: tileRect.minY + 4))

// MARK: Text
func draw(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at p: NSPoint) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
    ]
    (string as NSString).draw(at: p, withAttributes: attrs)
}

// Title
draw("Free App Store", size: 106, weight: .heavy, color: .white, at: NSPoint(x: 360, y: 570))

// Tagline
draw("Every Mac app that's actually free.",
     size: 44, weight: .semibold,
     color: NSColor.white.withAlphaComponent(0.94),
     at: NSPoint(x: 364, y: 478))

// Sub-line
draw("Zero in-app purchases. One click opens it in the App Store.",
     size: 27, weight: .regular,
     color: NSColor.white.withAlphaComponent(0.74),
     at: NSPoint(x: 364, y: 424))

// Bottom metadata strip
drawSymbol("checkmark.seal.fill", pointSize: 30, weight: .bold,
           color: NSColor(srgbRed: 0.20, green: 0.85, blue: 0.45, alpha: 1.0),
           center: NSPoint(x: 132, y: 62))
draw("$0 only  ·  No in-app purchases  ·  Native Mac apps",
     size: 24, weight: .medium,
     color: NSColor.white.withAlphaComponent(0.82),
     at: NSPoint(x: 158, y: 49))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else { exit(2) }

try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(Int(width))x\(Int(height)))")