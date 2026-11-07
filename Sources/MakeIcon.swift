import AppKit

// Renders the app icon: the Apple logo glowing on a space-black squircle.
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.5).cgColor)
NSColor.black.setFill(); shape.fill()
ctx.restoreGState()

shape.addClip()
NSGradient(starting: NSColor(white: 0.17, alpha: 1), ending: NSColor(white: 0.05, alpha: 1))!
    .draw(in: shape, angle: -60)
NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.clear])!
    .draw(in: rect, relativeCenterPosition: .zero)

let config = NSImage.SymbolConfiguration(pointSize: 440, weight: .regular)
    .applying(.init(paletteColors: [.white]))
let logo = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)!
    .withSymbolConfiguration(config)!
let ls = logo.size
let lr = NSRect(x: (size - ls.width) / 2, y: (size - ls.height) / 2 + 10, width: ls.width, height: ls.height)
for (blur, alpha) in [(90.0, 0.55), (40.0, 0.7), (12.0, 0.9)] {
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: blur, color: NSColor.white.withAlphaComponent(alpha).cgColor)
    logo.draw(in: lr)
    ctx.restoreGState()
}
logo.draw(in: lr)
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
