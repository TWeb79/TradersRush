import AppKit

// Draws the app icon programmatically (no external asset) using the same Theme palette as
// the app itself: a squircle background with a simple three-candle glyph.
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let bg = NSColor(srgbRed: 0x09/255, green: 0x0C/255, blue: 0x10/255, alpha: 1)
let bull = NSColor(srgbRed: 0x2D/255, green: 0xD4/255, blue: 0xA0/255, alpha: 1)
let bear = NSColor(srgbRed: 0xF0/255, green: 0x5D/255, blue: 0x83/255, alpha: 1)

let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: size * 0.224, yRadius: size * 0.224)
bg.setFill()
bgPath.fill()

func drawCandle(cx: CGFloat, bodyTop: CGFloat, bodyBottom: CGFloat, wickTop: CGFloat, wickBottom: CGFloat, width: CGFloat, color: NSColor) {
    color.setStroke()
    color.setFill()
    let wick = NSBezierPath()
    wick.lineWidth = width * 0.22
    wick.move(to: NSPoint(x: cx, y: wickBottom))
    wick.line(to: NSPoint(x: cx, y: wickTop))
    wick.stroke()
    let body = NSBezierPath(roundedRect: NSRect(x: cx - width / 2, y: bodyBottom, width: width, height: bodyTop - bodyBottom), xRadius: width * 0.18, yRadius: width * 0.18)
    body.fill()
}

let candleWidth: CGFloat = size * 0.16
drawCandle(cx: size * 0.30, bodyTop: size * 0.46, bodyBottom: size * 0.34, wickTop: size * 0.52, wickBottom: size * 0.28, width: candleWidth, color: bear)
drawCandle(cx: size * 0.50, bodyTop: size * 0.72, bodyBottom: size * 0.40, wickTop: size * 0.80, wickBottom: size * 0.34, width: candleWidth, color: bull)
drawCandle(cx: size * 0.70, bodyTop: size * 0.58, bodyBottom: size * 0.46, wickTop: size * 0.64, wickBottom: size * 0.40, width: candleWidth, color: bear)

image.unlockFocus()

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to render icon")
}
let outPath = CommandLine.arguments[1]
try! png.write(to: URL(fileURLWithPath: outPath))
