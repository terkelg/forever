import AppKit
import ImageIO
import UniformTypeIdentifiers

struct Animation: Decodable {
    let frames: Int
    let fps: Int
    let size: Int
    let columns: Int
    let rows: Int
}

func load(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return image
}

func canvas(_ width: Int, _ height: Int) throws -> CGContext {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return context
}

func save(_ image: CGImage, to url: URL) throws {
    guard let target = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(target, image, nil)
    guard CGImageDestinationFinalize(target) else { throw CocoaError(.fileWriteUnknown) }
}

guard CommandLine.arguments.count == 4 else {
    print("Usage: swift Pack.swift <frames directory> <resources directory> <asset catalog>")
    exit(1)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let assets = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
let data = try Data(contentsOf: input.appendingPathComponent("animation.json"))
let animation = try JSONDecoder().decode(Animation.self, from: data)
let width = animation.columns * animation.size
let height = animation.rows * animation.size
let sheet = try canvas(width, height)
var frames: [CGImage] = []

for index in 0..<animation.frames {
    let image = try load(input.appendingPathComponent(String(format: "%04d.png", index)))
    guard image.width == animation.size, image.height == animation.size else {
        throw CocoaError(.fileReadCorruptFile)
    }
    frames.append(image)
    let x = (index % animation.columns) * animation.size
    // Pack rows from the top; the app crops CGImages using the same convention.
    let y = height - (index / animation.columns + 1) * animation.size
    sheet.draw(image, in: CGRect(x: x, y: y, width: animation.size, height: animation.size))
}
guard let atlas = sheet.makeImage() else { throw CocoaError(.fileWriteUnknown) }
try save(atlas, to: output.appendingPathComponent("beachball.png"))
try data.write(to: output.appendingPathComponent("animation.json"), options: .atomic)

let art = assets.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("art")
try FileManager.default.createDirectory(at: art, withIntermediateDirectories: true)
let icon = try load(input.appendingPathComponent("icon.png"))
try save(icon, to: art.appendingPathComponent("preview.png"))
let iconset = assets.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let info: [String: Any] = ["author": "xcode", "version": 1]
var entries: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let context = try canvas(pixels, pixels)
        context.interpolationQuality = .high
        context.draw(icon, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let name = "icon-\(size)@\(scale)x.png"
        guard let resized = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        try save(resized, to: iconset.appendingPathComponent(name))
        entries.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
try JSONSerialization.data(withJSONObject: ["images": entries, "info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: iconset.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: assets.appendingPathComponent("Contents.json"))

// A browser-viewable animation gives the render loop a quick visual check.
let preview = art.appendingPathComponent("spin.gif")
guard let gif = CGImageDestinationCreateWithURL(preview as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
    throw CocoaError(.fileWriteUnknown)
}
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for frame in frames {
    CGImageDestinationAddImage(gif, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(animation.fps)]] as CFDictionary)
}
guard CGImageDestinationFinalize(gif) else { throw CocoaError(.fileWriteUnknown) }
print("Packed \(width)×\(height) sprite sheet, app icon, and spin preview.")
