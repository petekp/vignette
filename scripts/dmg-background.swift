// Draws the disk image window's background: a looping arrow from the app's icon to Applications,
// drawn as Vignette draws a person's arrow (red stroke, white edge, filled head, soft shadow).
// Usage: swift scripts/dmg-background.swift <out.png> <scale>
// The layout numbers must match the Finder layout in scripts/release.sh.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let scale = Double(args[2]) else {
    FileHandle.standardError.write("usage: dmg-background.swift <out.png> <scale>\n".data(using: .utf8)!)
    exit(2)
}

// The window's size and the icons' centres, in points, matching release.sh. Finder's bounds include
// the title bar, so the image runs past the bottom of the content and is cut there. Finder draws a
// background picture over white, with dark labels, in dark mode too (macOS 15), so one image serves.
let size = CGSize(width: 600, height: 360)
let appCenter = CGPoint(x: 150, y: 160)
let applicationsCenter = CGPoint(x: 450, y: 160)
let iconSize: CGFloat = 128

let red = CGColor(srgbRed: 0xe0 / 255, green: 0x31 / 255, blue: 0x31 / 255, alpha: 1)
let stroke: CGFloat = 4
let edge: CGFloat = 1.5
let headLength = stroke * 4.5
let headWidth = stroke * 4

// The arrow runs between the icons, level with their centres. Two loops in the middle come from a
// prolate cycloid: the point circles backwards faster than the line moves forwards, so the path
// crosses itself. The envelope keeps both ends straight, and the whole path bows up a little.
let start = CGPoint(x: appCenter.x + iconSize / 2 + 14, y: appCenter.y)
let end = CGPoint(x: applicationsCenter.x - iconSize / 2 - 12, y: applicationsCenter.y)
let span = end.x - start.x
let loops = 2.0
// The loops take the middle of the path; the stretches either side stay straight.
let loopsFrom: CGFloat = 0.14, loopsTo: CGFloat = 0.86
// The loops' horizontal swing has to beat the line's speed for the path to cross itself.
let swing: CGFloat = 27
let rise: CGFloat = 26
let bow: CGFloat = 12

func point(_ t: CGFloat) -> CGPoint {
    let u = min(max((t - loopsFrom) / (loopsTo - loopsFrom), 0), 1)
    let envelope = sin(.pi * u)
    let theta = 2 * .pi * loops * u
    let x = start.x + span * t + swing * envelope * sin(theta)
    // y is down: the loops rise above the line, and the bow lifts the middle.
    let y = start.y - rise * envelope * (1 - cos(theta)) - bow * sin(.pi * t)
    return CGPoint(x: x, y: y)
}

let steps = 400
let points = (0...steps).map { point(CGFloat($0) / CGFloat(steps)) }

// The body stops where the head begins, so the round cap never shows past the head's sides.
var bodyEnd = points.count - 1
while bodyEnd > 0, hypot(points[bodyEnd].x - end.x, points[bodyEnd].y - end.y) < headLength * 0.6 { bodyEnd -= 1 }
let body = CGMutablePath()
body.addLines(between: Array(points[0...bodyEnd]))

// The head points along the path's last stretch.
let back = points[max(0, points.count - 1 - steps / 40)]
let angle = atan2(end.y - back.y, end.x - back.x)
let tip = CGPoint(x: end.x, y: end.y)
let baseCenter = CGPoint(x: tip.x - headLength * cos(angle), y: tip.y - headLength * sin(angle))
let normal = CGPoint(x: -sin(angle), y: cos(angle))
let head = CGMutablePath()
head.move(to: tip)
head.addLine(to: CGPoint(x: baseCenter.x + normal.x * headWidth / 2, y: baseCenter.y + normal.y * headWidth / 2))
head.addLine(to: CGPoint(x: baseCenter.x - normal.x * headWidth / 2, y: baseCenter.y - normal.y * headWidth / 2))
head.closeSubpath()

let width = Int(size.width * scale), height = Int(size.height * scale)
guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.scaleBy(x: scale, y: scale)
// Core Graphics puts y up; the layout above is y down, as Finder's is.
ctx.translateBy(x: 0, y: size.height)
ctx.scaleBy(x: 1, y: -1)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

func draw(_ color: CGColor, grow: CGFloat) {
    ctx.setStrokeColor(color)
    ctx.setFillColor(color)
    ctx.setLineWidth(stroke + 2 * grow)
    ctx.addPath(body)
    ctx.strokePath()
    ctx.setLineWidth(2 * grow)
    ctx.addPath(head)
    ctx.drawPath(using: grow > 0 ? .fillStroke : .fill)
}

// The shadow is cast by the white edge, the widest shape, as a mark's is.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 5, color: CGColor(gray: 0, alpha: 0.35))
draw(CGColor(gray: 1, alpha: 1), grow: edge)
ctx.restoreGState()
draw(red, grow: 0)

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
rep.size = size
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[1]))
