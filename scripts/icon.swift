// Draws the app icon: a page of prose with one line branching into a take.
// Run from the repository root:  swift scripts/icon.swift
// Writes every size Xcode wants into Take/Assets.xcassets/AppIcon.appiconset.
import AppKit

let out = "Take/Assets.xcassets/AppIcon.appiconset"
let side = 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: side, height: side)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// The tile: the macOS grid puts it at 824 points inside 1024.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)
let shadow = NSShadow()
shadow.shadowColor = color(0x000000, 0.35)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 24
shadow.set()
color(0x2B2622).setFill()
tilePath.fill()
NSShadow().set()
NSGradient(starting: color(0x3B332C), ending: color(0x221D19))!.draw(in: tilePath, angle: -90)

// The page, a little narrower than tall, sitting in the tile.
let page = NSRect(x: 292, y: 208, width: 440, height: 608)
let pagePath = NSBezierPath(roundedRect: page, xRadius: 22, yRadius: 22)
let pageShadow = NSShadow()
pageShadow.shadowColor = color(0x000000, 0.45)
pageShadow.shadowOffset = NSSize(width: 0, height: -10)
pageShadow.shadowBlurRadius = 30
pageShadow.set()
color(0xF4EDE0).setFill()
pagePath.fill()
NSShadow().set()

// Lines of prose, then one line branching into a second: a take.
let ink = color(0xB9AE9C)
let accent = color(0xE0662A)
let left = page.minX + 60
let stroke: CGFloat = 26
let gap: CGFloat = 72
var y = page.maxY - 96
func line(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y - stroke / 2, width: width, height: stroke),
                 xRadius: stroke / 2, yRadius: stroke / 2).fill()
}
line(left, y, 320, ink); y -= gap
line(left, y, 250, ink); y -= gap
line(left, y, 300, ink); y -= gap
let forkY = y
line(left + 56, y, 264, ink); y -= gap
line(left + 56, y, 220, accent); y -= gap
line(left, y, 280, ink); y -= gap
line(left, y, 180, ink)

// The fork: a dot at the margin, a stem to the first line, a curve to the take.
let dot = NSPoint(x: left + 13, y: forkY)
let stem = NSBezierPath()
stem.lineWidth = stroke * 0.55
stem.lineCapStyle = .round
stem.move(to: dot)
stem.line(to: NSPoint(x: left + 56, y: forkY))
ink.setStroke()
stem.stroke()
let curve = NSBezierPath()
curve.lineWidth = stroke * 0.55
curve.lineCapStyle = .round
curve.move(to: dot)
curve.curve(to: NSPoint(x: left + 56, y: forkY - gap),
            controlPoint1: NSPoint(x: dot.x, y: forkY - gap * 0.7),
            controlPoint2: NSPoint(x: left + 20, y: forkY - gap))
accent.setStroke()
curve.stroke()
accent.setFill()
NSBezierPath(ovalIn: NSRect(x: dot.x - 22, y: dot.y - 22, width: 44, height: 44)).fill()

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "\(out)/icon_512x512@2x.png"))

// Every other size, and the catalog's manifest.
let sizes: [(name: String, points: Int, scale: Int)] = [
    ("icon_16x16", 16, 1), ("icon_16x16@2x", 16, 2), ("icon_32x32", 32, 1), ("icon_32x32@2x", 32, 2),
    ("icon_128x128", 128, 1), ("icon_128x128@2x", 128, 2), ("icon_256x256", 256, 1), ("icon_256x256@2x", 256, 2),
    ("icon_512x512", 512, 1), ("icon_512x512@2x", 512, 2),
]
for entry in sizes where entry.name != "icon_512x512@2x" {
    let pixels = entry.points * entry.scale
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = ["-z", "\(pixels)", "\(pixels)", "\(out)/icon_512x512@2x.png", "--out", "\(out)/\(entry.name).png"]
    task.standardOutput = FileHandle.nullDevice
    try! task.run()
    task.waitUntilExit()
}
let images = sizes.map { entry in
    "    { \"filename\": \"\(entry.name).png\", \"idiom\": \"mac\", \"scale\": \"\(entry.scale)x\", \"size\": \"\(entry.points)x\(entry.points)\" }"
}
let contents = "{\n  \"images\": [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\": { \"author\": \"xcode\", \"version\": 1 }\n}\n"
try! contents.write(toFile: "\(out)/Contents.json", atomically: true, encoding: .utf8)
print("wrote \(sizes.count) icons to \(out)")
