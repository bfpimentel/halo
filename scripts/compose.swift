// Draws window captures at their screen positions on a dark, screen-sized canvas (the main display's size): a picture
// of how widgets sit on screen, without the wallpaper or any other app.
// Usage: swift scripts/compose.swift <out.png> <png>:<x>:<y> ...   (x/y: top-left points; later parts draw on top)
import AppKit

let arguments = CommandLine.arguments.dropFirst()
guard let out = arguments.first, let screen = NSScreen.screens.first else { fatalError("usage: compose.swift <out.png> <png>:<x>:<y> ...") }
let size = screen.frame.size
let scale = screen.backingScaleFactor
let width = Int(size.width * scale), height = Int(size.height * scale)
guard let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("no context") }
context.setFillColor(CGColor(srgbRed: 0.07, green: 0.07, blue: 0.09, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
for spec in arguments.dropFirst() {
    let parts = spec.split(separator: ":")
    guard parts.count == 3, let x = Double(parts[1]), let y = Double(parts[2]),
          let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: String(parts[0])) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { continue }
    // Core Graphics draws bottom-up; the captures' x/y are top-left points.
    let frame = CGRect(x: x * scale, y: Double(height) - y * scale - Double(image.height), width: Double(image.width), height: Double(image.height))
    context.draw(image, in: frame)
}
guard let image = context.makeImage(),
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else { fatalError("encoding failed") }
try data.write(to: URL(fileURLWithPath: out))
