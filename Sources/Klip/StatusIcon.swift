import Cocoa

/// The menu bar glyph: the app icon's clipboard character as an outline, without the
/// squircle. Drawn in code so it stays crisp at any scale and needs no bundled asset.
enum StatusIcon {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            // The same slight tilt as the app icon.
            let tilt = NSAffineTransform()
            tilt.translateX(by: 9, yBy: 9.5)
            tilt.rotate(byDegrees: -9)
            tilt.translateX(by: -9, yBy: -9.5)
            tilt.concat()
            NSColor.black.set()

            let board = NSBezierPath(
                roundedRect: NSRect(x: 3.4, y: 3.6, width: 11.2, height: 12.6), xRadius: 3, yRadius: 3)
            board.lineWidth = 1.3
            board.stroke()
            NSBezierPath(
                roundedRect: NSRect(x: 5.9, y: 1.5, width: 6.2, height: 3.8), xRadius: 1.9, yRadius: 1.9
            ).fill()
            for x in [5.7, 9.9] {
                NSBezierPath(
                    roundedRect: NSRect(x: x, y: 8.1, width: 2.4, height: 1.1), xRadius: 0.55, yRadius: 0.55
                ).fill()
            }
            let smile = NSBezierPath()
            smile.move(to: NSPoint(x: 6.2, y: 11.3))
            smile.curve(
                to: NSPoint(x: 11.8, y: 11.3),
                controlPoint1: NSPoint(x: 7.6, y: 13.6), controlPoint2: NSPoint(x: 10.4, y: 13.6))
            smile.lineWidth = 1.2
            smile.lineCapStyle = .round
            smile.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
