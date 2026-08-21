// Generates the app icon: a gradient tile with a white shopping-bag badge.
// Usage: make_icon <output-1024-png-path>
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: make_icon <out.png>\n".data(using: .utf8)!)
    exit(1)
}
let outPath = args[1]
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Rounded tile
let inset: CGFloat = 26
let tileRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 224, yRadius: 224)

let gradient = NSGradient(
    starting: NSColor(srgbRed: 0.13, green: 0.56, blue: 0.98, alpha: 1.0),
    ending: NSColor(srgbRed: 0.42, green: 0.22, blue: 0.94, alpha: 1.0)
)
gradient?.draw(in: tile, angle: -90)

// Subtle inner highlight
let highlight = NSBezierPath(roundedRect: tileRect.insetBy(dx: 6, dy: 6), xRadius: 218, yRadius: 218)
NSColor.white.withAlphaComponent(0.08).setFill()
highlight.fill()

// White bag symbol
if let symbol = NSImage(systemSymbolName: "bag.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .semibold)
    let configured = symbol.withSymbolConfiguration(config) ?? symbol
    let symbolSize = configured.size
    let symbolRect = CGRect(
        x: (size - symbolSize.width) / 2,
        y: (size - symbolSize.height) / 2 - 20,
        width: symbolSize.width,
        height: symbolSize.height
    )
    // Tint white
    let white = NSImage(size: symbolSize)
    white.lockFocus()
    configured.draw(at: .zero, from: .zero, operation: .copy, fraction: 1)
    NSColor.white.setFill()
    NSRect(origin: .zero, size: symbolSize).fill(using: .sourceAtop)
    white.unlockFocus()
    white.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
}

// Small checkmark seal badge
if let badge = NSImage(systemSymbolName: "checkmark.seal.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 250, weight: .bold)
    let configured = badge.withSymbolConfiguration(config) ?? badge
    let symbolSize = configured.size
    let badgeRect = CGRect(
        x: size - inset - symbolSize.width - 40,
        y: inset + 30,
        width: symbolSize.width,
        height: symbolSize.height
    )
    let tinted = NSImage(size: symbolSize)
    tinted.lockFocus()
    configured.draw(at: .zero, from: .zero, operation: .copy, fraction: 1)
    NSColor(srgbRed: 0.20, green: 0.85, blue: 0.45, alpha: 1.0).setFill()
    NSRect(origin: .zero, size: symbolSize).fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else { exit(2) }

try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
