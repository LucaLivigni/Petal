import AppKit

// Renders the Petal app icon: an orange squircle with a ring of eight glass petals.
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let ctx = NSGraphicsContext.current!.cgContext
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: NSColor.black.withAlphaComponent(0.32).cgColor)
    NSColor.black.setFill(); squircle.fill()
    ctx.restoreGState()

    ctx.saveGState()
    squircle.addClip()
    let bg = NSGradient(colors: [NSColor(srgbRed: 1.0, green: 0.74, blue: 0.30, alpha: 1), NSColor(srgbRed: 1.0, green: 0.40, blue: 0.04, alpha: 1)])!
    bg.draw(in: tile, angle: -90)
    let glow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.38), NSColor.white.withAlphaComponent(0)])!
    glow.draw(fromCenter: NSPoint(x: 512, y: 880), radius: 0, toCenter: NSPoint(x: 512, y: 880), radius: 520, options: [])
    ctx.restoreGState()

    let center = NSPoint(x: 512, y: 512)
    let count = 8
    for i in 0..<count {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: CGFloat(i) * 2 * .pi / CGFloat(count))
        let petal = NSBezierPath(roundedRect: NSRect(x: -62, y: 118, width: 124, height: 214), xRadius: 62, yRadius: 62)
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: NSColor(srgbRed: 0.6, green: 0.2, blue: 0, alpha: 0.38).cgColor)
        let fill = NSGradient(colors: [NSColor.white.withAlphaComponent(0.98), NSColor.white.withAlphaComponent(0.72)])!
        fill.draw(in: petal, angle: 90)
        ctx.restoreGState()
    }
    // centre dot
    let dot = NSBezierPath(ovalIn: NSRect(x: 512 - 46, y: 512 - 46, width: 92, height: 92))
    NSColor.white.withAlphaComponent(0.95).setFill(); dot.fill()
    return true
}

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
