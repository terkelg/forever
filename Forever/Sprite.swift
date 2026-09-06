import AppKit
import ImageIO

@MainActor
final class Sprite: NSView {
    private struct Animation: Decodable {
        let frames: Int
        let fps: Double
        let size: Int
        let columns: Int
        let rows: Int
    }

    let frames: [NSImage]
    let fps: Double
    var index = 0

    init(bundle: Bundle) throws {
        guard let manifest = bundle.url(forResource: "animation", withExtension: "json"),
              let image = bundle.url(forResource: "beachball", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(image as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let animation = try JSONDecoder().decode(Animation.self, from: Data(contentsOf: manifest))
        guard animation.frames > 0, animation.fps > 0, animation.size > 0,
              animation.columns > 0, animation.rows > 0,
              animation.frames <= animation.columns * animation.rows,
              sheet.width == animation.columns * animation.size,
              sheet.height == animation.rows * animation.size else {
            throw CocoaError(.fileReadCorruptFile)
        }
        frames = try (0..<animation.frames).map { index in
            let rectangle = CGRect(x: (index % animation.columns) * animation.size,
                                   y: (index / animation.columns) * animation.size,
                                   width: animation.size, height: animation.size)
            guard let frame = sheet.cropping(to: rectangle) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return NSImage(cgImage: frame, size: NSSize(width: animation.size, height: animation.size))
        }
        fps = animation.fps
        super.init(frame: NSRect(x: 0, y: 0, width: animation.size, height: animation.size))
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        frames[index].draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
    }
}
