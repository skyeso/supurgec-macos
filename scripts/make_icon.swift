import AppKit

let outPath = CommandLine.arguments[1]
let outURL = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let chunks: [(String, Int, Int)] = [
    ("icp4", 16, 1), ("ic11", 16, 2),
    ("icp5", 32, 1), ("ic12", 32, 2),
    ("ic07", 128, 1), ("ic13", 128, 2),
    ("ic08", 256, 1), ("ic14", 256, 2),
    ("ic09", 512, 1), ("ic10", 512, 2),
]

func renderPNG(pt: Int, scale: Int) -> Data {
    let px = pt * scale
    let s = CGFloat(pt)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pt, height: pt)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    let grad = NSGradient(colors: [
        NSColor(calibratedRed: 0.98, green: 0.36, blue: 0.62, alpha: 1),
        NSColor(calibratedRed: 0.55, green: 0.27, blue: 0.93, alpha: 1),
        NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.97, alpha: 1),
    ])!
    grad.draw(in: path, angle: -60)
    if let base = NSImage(systemSymbolName: "paintbrush.pointed.fill", accessibilityDescription: nil),
       let sym = base.withSymbolConfiguration(.init(pointSize: s * 0.40, weight: .semibold)) {
        let tinted = NSImage(size: sym.size, flipped: false) { r in
            sym.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let w = tinted.size.width, h = tinted.size.height
        tinted.draw(in: NSRect(x: (s - w) / 2, y: (s - h) / 2, width: w, height: h))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func appendUInt32BE(_ v: UInt32, to data: inout Data) {
    var be = v.bigEndian
    withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
}

var body = Data()
for (tag, pt, scale) in chunks {
    let png = renderPNG(pt: pt, scale: scale)
    body.append(contentsOf: tag.utf8)
    appendUInt32BE(UInt32(8 + png.count), to: &body)
    body.append(png)
}

var icns = Data("icns".utf8)
appendUInt32BE(UInt32(8 + body.count), to: &icns)
icns.append(body)
try! icns.write(to: outURL)
print("icns ok (\(icns.count) bayt)")
