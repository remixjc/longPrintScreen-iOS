import AppKit
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let bitmap = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
let bounds = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(starting: NSColor(red: 0.19, green: 0.14, blue: 0.33, alpha: 1),
           ending: NSColor(red: 0.035, green: 0.04, blue: 0.07, alpha: 1))!.draw(in: bounds, angle: 270)
for (x, y, color) in [(280.0, 200.0, NSColor(red: 0.61, green: 0.48, blue: 0.97, alpha: 1)),
                      (390.0, 300.0, NSColor(red: 0.65, green: 0.94, blue: 0.44, alpha: 1))] {
    let path = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 350, height: 520), xRadius: 55, yRadius: 55)
    color.setFill()
    path.fill()
    NSColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 0.65).setFill()
    for index in 0..<4 {
        NSBezierPath(roundedRect: NSRect(x: x + 50, y: y + 90 + Double(index) * 76,
                                       width: index == 3 ? 160 : 250, height: 24), xRadius: 12, yRadius: 12).fill()
    }
}
NSGraphicsContext.restoreGraphicsState()
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL,
                                                  UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, bitmap.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
