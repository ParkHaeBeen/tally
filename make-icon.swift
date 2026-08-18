// 앱 아이콘 생성기 — '바' 후보: 파이프라인 + 상태점(빨강·호박·초록).
// 실행: swift make-icon.swift   →   icon.icns
import AppKit

func rgb(_ hex: String) -> NSColor {
    var v = UInt64(0)
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

let teal = rgb("#6FC9BE")
let dim = rgb("#4C6166")
let red = rgb("#E4573D")
let amber = rgb("#E0A54B")
let green = rgb("#3FBF8F")

func draw(side: CGFloat) -> NSBitmapImageRep {
    let px = Int(side)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // 바탕: 그라파이트 라운드 사각형
    let pad = side * 0.085
    let box = CGRect(x: pad, y: pad, width: side - pad * 2, height: side - pad * 2)
    let radius = box.width * 0.225
    let path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        rgb("#2A3438").cgColor, rgb("#151D20").cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: box.minX, y: box.maxY),
                           end: CGPoint(x: box.maxX, y: box.minY), options: [])
    // 위쪽 광택 — 경계선이 보이지 않게 그라데이션으로
    let gloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor.white.withAlphaComponent(0.10).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: box.midX, y: box.maxY),
                           end: CGPoint(x: box.midX, y: box.midY - box.height * 0.1),
                           options: [])
    ctx.restoreGState()

    // 파이프라인 — 아래쪽. 앞 두 단계는 통과(청록), 마지막은 대기(빈 원)
    let nodeY = box.minY + box.height * 0.34
    let r = box.width * 0.082
    let xs = [0.27, 0.5, 0.73].map { box.minX + box.width * CGFloat($0) }
    let lw = box.width * 0.046

    ctx.setLineCap(.round)
    ctx.setLineWidth(lw)
    ctx.setStrokeColor(dim.cgColor)
    ctx.move(to: CGPoint(x: xs[0], y: nodeY)); ctx.addLine(to: CGPoint(x: xs[2], y: nodeY))
    ctx.strokePath()
    ctx.setStrokeColor(teal.cgColor)
    ctx.move(to: CGPoint(x: xs[0], y: nodeY)); ctx.addLine(to: CGPoint(x: xs[1], y: nodeY))
    ctx.strokePath()

    for (i, x) in xs.enumerated() {
        let box2 = CGRect(x: x - r, y: nodeY - r, width: r * 2, height: r * 2)
        if i < 2 {
            ctx.setFillColor(teal.cgColor)
            ctx.fillEllipse(in: box2)
        } else {
            ctx.setFillColor(rgb("#2A3438").cgColor)
            ctx.fillEllipse(in: box2)
            ctx.setStrokeColor(dim.cgColor)
            ctx.setLineWidth(box.width * 0.034)
            ctx.strokeEllipse(in: box2.insetBy(dx: box.width * 0.017, dy: box.width * 0.017))
        }
    }

    // 상태점 — 위쪽. 빨강 · 호박 · 초록
    let dotY = box.minY + box.height * 0.70
    let dr = box.width * 0.056
    let dxs = [0.35, 0.5, 0.65].map { box.minX + box.width * CGFloat($0) }
    for (i, c) in [red, amber, green].enumerated() {
        ctx.setFillColor(c.cgColor)
        ctx.fillEllipse(in: CGRect(x: dxs[i] - dr, y: dotY - dr, width: dr * 2, height: dr * 2))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let dir = fm.currentDirectoryPath
let setDir = dir + "/Tally.iconset"
try? fm.removeItem(atPath: setDir)
try! fm.createDirectory(atPath: setDir, withIntermediateDirectories: true)

let specs: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, side) in specs {
    let rep = draw(side: side)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try! data.write(to: URL(fileURLWithPath: "\(setDir)/\(name).png"))
}
// 미리보기용 한 장 남긴다
if let d = draw(side: 256).representation(using: .png, properties: [:]) {
    try! d.write(to: URL(fileURLWithPath: dir + "/icon-preview.png"))
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", setDir, "-o", dir + "/icon.icns"]
try! p.run(); p.waitUntilExit()
try? fm.removeItem(atPath: setDir)
print(p.terminationStatus == 0 ? "icon.icns 생성 완료" : "iconutil 실패")
