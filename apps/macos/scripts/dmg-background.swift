import AppKit

let canvas = NSSize(width: 640, height: 400)
let output = URL(fileURLWithPath: CommandLine.arguments[1])

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

func centeredText(_ text: String, top: CGFloat, size: CGFloat,
                  weight: NSFont.Weight = .regular, foreground: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    (text as NSString).draw(in: NSRect(x: 24, y: canvas.height - top - size - 10,
                                      width: canvas.width - 48, height: size + 10),
                           withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                            .foregroundColor: foreground, .paragraphStyle: paragraph])
}

func drawBackground() {
    color(247, 245, 241).setFill()
    NSRect(origin: .zero, size: canvas).fill()

    centeredText("Install Grove", top: 38, size: 28, weight: .semibold, foreground: color(43, 45, 41))
    centeredText("Drag Grove into Applications to get started.", top: 80, size: 14,
                 foreground: color(112, 113, 106))

    for x: CGFloat in [76, 388] {
        let card = NSBezierPath(roundedRect: NSRect(x: x, y: 108, width: 176, height: 154),
                                xRadius: 20, yRadius: 20)
        color(255, 254, 252).setFill()
        card.fill()
        color(230, 228, 222).setStroke()
        card.lineWidth = 1
        card.stroke()
    }

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 294, y: 198))
    arrow.line(to: NSPoint(x: 346, y: 198))
    arrow.move(to: NSPoint(x: 336, y: 208))
    arrow.line(to: NSPoint(x: 346, y: 198))
    arrow.line(to: NSPoint(x: 336, y: 188))
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(98, 125, 108).setStroke()
    arrow.stroke()

    centeredText("Then open Grove from Applications.", top: 330, size: 12,
                 foreground: color(128, 128, 120))
}

let image = NSImage(size: canvas)
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                  pixelsWide: Int(canvas.width) * scale,
                                  pixelsHigh: Int(canvas.height) * scale,
                                  bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = canvas
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    drawBackground()
    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(bitmap)
}
try image.tiffRepresentation!.write(to: output)
