import AppKit
let target = CommandLine.arguments[1]
let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temp) }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(calibratedRed: 0.06, green: 0.36, blue: 0.34, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.05, y: p * 0.05, width: p * 0.9, height: p * 0.9), xRadius: p * 0.21, yRadius: p * 0.21).fill()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: p * 0.45, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: paragraph]
        ("한" as NSString).draw(in: NSRect(x: 0, y: p * 0.26, width: p, height: p * 0.55), withAttributes: attributes)
        NSColor(calibratedRed: 0.62, green: 0.88, blue: 0.7, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.34, y: p * 0.18, width: p * 0.32, height: p * 0.035), xRadius: p * 0.017, yRadius: p * 0.017).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: temp.appendingPathComponent(name))
    }
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", temp.path, "-o", target]
try process.run(); process.waitUntilExit()
exit(process.terminationStatus)
