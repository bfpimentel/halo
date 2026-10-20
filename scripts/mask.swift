// Turns a window capture into a video mask: alpha only, scaled so the window's body (its most common non-zero alpha,
// e.g. a 94% opaque card) is fully opaque. The recording then shows in full, while anti-aliased edges and see-through
// corners stay as they are.
// Usage: swift scripts/mask.swift <capture.png> <mask.png>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let source = NSImage(contentsOfFile: arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { fatalError("usage: mask.swift <capture.png> <mask.png>") }
let width = source.width, height = source.height
guard let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
), let data = context.data else { fatalError("no context") }
context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
let alpha = data.bindMemory(to: UInt8.self, capacity: width * height)
var counts = [Int](repeating: 0, count: 256)
for index in 0..<width * height { counts[Int(alpha[index])] += 1 }
guard let body = (1...255).max(by: { counts[$0] < counts[$1] }), counts[body] > 0 else {
    fatalError("\(arguments[1]) is fully transparent")
}
for index in 0..<width * height { alpha[index] = UInt8(min(255, Int(alpha[index]) * 255 / body)) }
guard let mask = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: mask).representation(using: .png, properties: [:])
else { fatalError("couldn't encode \(arguments[2])") }
try png.write(to: URL(fileURLWithPath: arguments[2]))
