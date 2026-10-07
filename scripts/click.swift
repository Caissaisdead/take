// Posts a real mouse click at a screen point, for scripts/tour.applescript.
//   click <x> <y> [count]

import CoreGraphics
import Foundation
let a = CommandLine.arguments
let p = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
let n = a.count > 3 ? Int(a[3])! : 1
let src = CGEventSource(stateID: .hidSystemState)
CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(120_000)
for i in 1...n {
    let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)!
    let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)!
    d.setIntegerValueField(.mouseEventClickState, value: Int64(i))
    u.setIntegerValueField(.mouseEventClickState, value: Int64(i))
    d.post(tap: .cghidEventTap); usleep(60_000); u.post(tap: .cghidEventTap); usleep(90_000)
}
