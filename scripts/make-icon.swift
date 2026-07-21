// Generates the app icon: the Claude Code block mascot on a black rounded
// square. Run from the repo root:  swift scripts/make-icon.swift
import AppKit

let frames = [" ▐▛███▜▌ ",
              "▝▜█████▛▘",
              "  ▘▘ ▝▝  "]
let quadrants: [Character: (Bool, Bool, Bool, Bool)] = [
    "█": (true, true, true, true),
    "▐": (false, true, false, true),
    "▌": (true, false, true, false),
    "▛": (true, true, true, false),
    "▜": (true, true, false, true),
    "▘": (true, false, false, false),
    "▝": (false, true, false, false),
    "▖": (false, false, true, false),
    "▗": (false, false, false, true),
    " ": (false, false, false, false),
]

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let inset: CGFloat = 100
let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset),
                      xRadius: 180, yRadius: 180)
NSColor.black.setFill()
bg.fill()
NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1).setFill()  // Anthropic coral
let cols = frames[0].count * 2, rows = frames.count * 2
let subW: CGFloat = 30, subH: CGFloat = 60
let x0 = (size - CGFloat(cols) * subW) / 2
let y0 = (size + CGFloat(rows) * subH) / 2
for (j, line) in frames.enumerated() {
    for (i, ch) in line.enumerated() {
        guard let q = quadrants[ch] else { continue }
        for (on, qx, qy) in [(q.0, 0, 0), (q.1, 1, 0), (q.2, 0, 1), (q.3, 1, 1)] where on {
            NSRect(x: x0 + CGFloat(i * 2 + qx) * subW,
                   y: y0 - CGFloat(j * 2 + qy + 1) * subH,
                   width: subW - 3, height: subH - 5).fill()
        }
    }
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "scripts/appicon-1024.png"))
print("wrote scripts/appicon-1024.png")
