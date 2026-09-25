// Lays a window capture on a 2560×1600 canvas for the Mac App Store.
//   swift scripts/screenshot.swift <window.png> <out.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let window = NSImage(contentsOfFile: args[1]) else {
    print("usage: screenshot.swift <window.png> <out.png>"); exit(1)
}
let width = 2560, height = 1600
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let canvas = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(starting: NSColor(srgbRed: 0.93, green: 0.90, blue: 0.85, alpha: 1),
           ending: NSColor(srgbRed: 0.80, green: 0.76, blue: 0.70, alpha: 1))!.draw(in: canvas, angle: -70)

// The capture is in pixels already; draw it 1:1, centred, with a shadow.
let pixels = window.representations.first.map { NSSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? window.size
let scale = min(1, min((Double(width) - 160) / pixels.width, (Double(height) - 160) / pixels.height))
let size = NSSize(width: pixels.width * scale, height: pixels.height * scale)
let frame = NSRect(x: (Double(width) - size.width) / 2, y: (Double(height) - size.height) / 2, width: size.width, height: size.height)
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
shadow.shadowOffset = NSSize(width: 0, height: -20)
shadow.shadowBlurRadius = 60
shadow.set()
NSColor.white.setFill()
NSBezierPath(roundedRect: frame, xRadius: 20, yRadius: 20).fill()
NSShadow().set()
NSBezierPath(roundedRect: frame, xRadius: 20, yRadius: 20).addClip()
window.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]) \(width)x\(height)")
