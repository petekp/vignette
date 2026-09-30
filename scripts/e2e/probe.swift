// The end-to-end runner's helper for what Python cannot reach on its own.
//   probe pasteboard save <folder>     writes each item's types to <folder>, skipping a concealed item
//   probe pasteboard restore <folder>  puts the saved items back, or clears the pasteboard when a
//                                      concealed item was skipped
//   probe pasteboard types             prints the item count and each item's types, one line each
//   probe pasteboard data <type> <out> writes the first item's bytes for <type> to <out>
//   probe pixels <png> x,y …           prints each point's colour as #rrggbb in sRGB, one per line
//   probe image <file> <w> <h>         writes a test image: bands of grey with a grid, in sRGB, as a
//                                      JPEG when the name ends in .jpg or .jpeg and a PNG otherwise
import AppKit

let args = CommandLine.arguments
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// Password managers mark what they copy with these; nothing of them is written to disk.
let concealed: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                              "com.agilebits.onepassword"]

func savePasteboard(to folder: URL) throws {
    let fm = FileManager.default
    try? fm.removeItem(at: folder)
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let items = NSPasteboard.general.pasteboardItems ?? []
    if items.contains(where: { !concealed.isDisjoint(with: $0.types.map(\.rawValue)) }) {
        try Data("concealed\n".utf8).write(to: folder.appendingPathComponent("skipped"))
        print("skipped: a concealed item")
        return
    }
    for (i, item) in items.enumerated() {
        let dir = folder.appendingPathComponent(String(i))
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var order: [String] = []
        for type in item.types {
            guard let data = item.data(forType: type) else { continue }
            let file = "\(order.count).data"
            try data.write(to: dir.appendingPathComponent(file))
            order.append(type.rawValue)
        }
        try Data(order.joined(separator: "\n").utf8).write(to: dir.appendingPathComponent("types"))
    }
    print("saved \(items.count) items")
}

func restorePasteboard(from folder: URL) throws {
    let fm = FileManager.default
    let board = NSPasteboard.general
    board.clearContents()
    if fm.fileExists(atPath: folder.appendingPathComponent("skipped").path) {
        print("cleared: the saved item was concealed")
        return
    }
    let dirs = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).compactMap(Int.init).sorted()
    var items: [NSPasteboardItem] = []
    for i in dirs {
        let dir = folder.appendingPathComponent(String(i))
        let types = (try String(contentsOf: dir.appendingPathComponent("types"), encoding: .utf8)).split(separator: "\n").map(String.init)
        let item = NSPasteboardItem()
        for (n, type) in types.enumerated() {
            let data = try Data(contentsOf: dir.appendingPathComponent("\(n).data"))
            item.setData(data, forType: NSPasteboard.PasteboardType(type))
        }
        items.append(item)
    }
    if !items.isEmpty { board.writeObjects(items) }
    print("restored \(items.count) items")
}

func pixels(_ path: String, _ points: [String]) {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(path)") }
    let w = image.width, h = image.height
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("no context") }
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { fail("no pixels") }
    print("size \(w) \(h)")
    for point in points {
        let parts = point.split(separator: ",").compactMap { Int($0) }
        guard parts.count == 2, (0..<w).contains(parts[0]), (0..<h).contains(parts[1]) else { print("\(point) outside"); continue }
        // Top-left origin, as the image's pixels are named everywhere else.
        let p = data + (parts[1] * w + parts[0]) * 4
        print(String(format: "%@ #%02x%02x%02x", point, p[0], p[1], p[2]))
    }
}

func image(_ path: String, _ w: Int, _ h: Int) {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("no context") }
    for band in 0..<8 {
        let v = 0.25 + 0.06 * Double(band)
        context.setFillColor(CGColor(srgbRed: v, green: v, blue: v + 0.03, alpha: 1))
        context.fill(CGRect(x: 0, y: h * band / 8, width: w, height: h / 8 + 1))
    }
    context.setStrokeColor(CGColor(srgbRed: 0.7, green: 0.7, blue: 0.7, alpha: 1))
    context.setLineWidth(1)
    for x in stride(from: 0, to: w, by: 100) { context.stroke(CGRect(x: x, y: 0, width: 0, height: h)) }
    guard let cg = context.makeImage(),
          let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                    (["jpg", "jpeg"].contains((path as NSString).pathExtension.lowercased()) ? "public.jpeg" : "public.png") as CFString,
                                                    1, nil) else { fail("cannot write \(path)") }
    CGImageDestinationAddImage(out, cg, nil)
    guard CGImageDestinationFinalize(out) else { fail("cannot write \(path)") }
}

guard args.count >= 2 else { fail("usage: probe pasteboard save|restore|types … | pixels <png> x,y … | image <png> w h") }
switch (args[1], args.count) {
case ("pasteboard", 4) where args[2] == "save": do { try savePasteboard(to: URL(fileURLWithPath: args[3])) } catch { fail("\(error)") }
case ("pasteboard", 4) where args[2] == "restore": do { try restorePasteboard(from: URL(fileURLWithPath: args[3])) } catch { fail("\(error)") }
case ("pasteboard", 3) where args[2] == "types":
    let items = NSPasteboard.general.pasteboardItems ?? []
    print("items \(items.count)")
    for item in items { print(item.types.map(\.rawValue).joined(separator: " ")) }
case ("pasteboard", 5) where args[2] == "data":
    guard let data = NSPasteboard.general.pasteboardItems?.first?.data(forType: NSPasteboard.PasteboardType(args[3])) else { fail("no \(args[3]) on the pasteboard") }
    do { try data.write(to: URL(fileURLWithPath: args[4])) } catch { fail("\(error)") }
case ("pixels", _) where args.count >= 4: pixels(args[2], Array(args[3...]))
case ("image", 5): image(args[2], Int(args[3]) ?? 0, Int(args[4]) ?? 0)
default: fail("usage: probe pasteboard save|restore|types … | pixels <png> x,y … | image <png> w h")
}
