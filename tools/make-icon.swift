// Zeichnet das App-Icon (1024×1024): eine zerlaufende schwarze Masse – „Slop“.
// Aufruf: swift tools/make-icon.swift <ziel.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Koordinaten von oben nach unten, wie beim Zeichnen auf Papier.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// Hintergrund: warmes Off-White, kein reines Weiß.
ctx.setFillColor(NSColor(srgbRed: 0.937, green: 0.922, blue: 0.890, alpha: 1).cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

let ink = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1).cgColor
ctx.setFillColor(ink)

// Die Masse läuft vom oberen Rand herunter: eine Fläche oben, unten fünf Tropfen
// unterschiedlicher Länge. Jeder Tropfen: (Mitte x, Breite, Länge bis zur Spitze).
let base: CGFloat = 300
let neck: CGFloat = 70  // ab hier laufen die Tropfen senkrecht
let drips: [(x: CGFloat, w: CGFloat, len: CGFloat)] = [
    (150, 92, 390), (330, 104, 230), (512, 116, 520), (700, 96, 310), (880, 84, 170),
]

// Von rechts nach links: zwischen zwei Tropfen ein Bogen, dessen Enden senkrecht
// in die Tropfenkanten übergehen – so entstehen keine Spitzen.
let path = CGMutablePath()
path.move(to: CGPoint(x: -10, y: -10))
path.addLine(to: CGPoint(x: size + 10, y: -10))
path.addLine(to: CGPoint(x: size + 10, y: base))
var fromX = size + 10
var fromNeck = false
for drip in drips.reversed() {
    let right = drip.x + drip.w / 2
    let left = drip.x - drip.w / 2
    let r = drip.w / 2
    let tip = base + drip.len
    // Bogen vom vorherigen Punkt (Rand oder linke Kante des vorigen Tropfens) zur rechten Kante.
    path.addCurve(to: CGPoint(x: right, y: base + neck),
                  control1: CGPoint(x: fromX, y: fromNeck ? base - 14 : base),
                  control2: CGPoint(x: right, y: base - 14))
    path.addLine(to: CGPoint(x: right, y: tip - r))
    path.addArc(center: CGPoint(x: drip.x, y: tip - r), radius: r, startAngle: 0, endAngle: .pi, clockwise: false)
    path.addLine(to: CGPoint(x: left, y: base + neck))
    fromX = left
    fromNeck = true
}
path.addCurve(to: CGPoint(x: -10, y: base),
              control1: CGPoint(x: fromX, y: base - 14), control2: CGPoint(x: 20, y: base))
path.closeSubpath()
ctx.addPath(path)
ctx.fillPath()

// Ein abgelöster Tropfen unter dem längsten.
let dropTop: CGFloat = base + 520 + 40
let drop = CGMutablePath()
drop.move(to: CGPoint(x: 512, y: dropTop))
drop.addCurve(to: CGPoint(x: 538, y: dropTop + 50), control1: CGPoint(x: 522, y: dropTop + 18), control2: CGPoint(x: 538, y: dropTop + 30))
drop.addCurve(to: CGPoint(x: 486, y: dropTop + 50), control1: CGPoint(x: 538, y: dropTop + 84), control2: CGPoint(x: 486, y: dropTop + 84))
drop.addCurve(to: CGPoint(x: 512, y: dropTop), control1: CGPoint(x: 486, y: dropTop + 30), control2: CGPoint(x: 502, y: dropTop + 18))
drop.closeSubpath()
ctx.addPath(drop)
ctx.fillPath()

NSGraphicsContext.current = nil
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: output))
print("Icon gespeichert: \(output)")
