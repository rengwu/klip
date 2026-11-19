import Cocoa

/// The menu bar glyph: the app icon's clipboard as an outline, without the squircle.
/// Drawn in code so it stays crisp at any scale and needs no bundled asset.
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
            clip().fill()

            // Three lines of text, getting shorter down the board.
            let text = NSBezierPath()
            for (y, end) in [(8.3, 11.9), (10.85, 11.1), (13.4, 9.4)] {
                text.move(to: NSPoint(x: 6.1, y: y))
                text.line(to: NSPoint(x: end, y: y))
            }
            text.lineWidth = 1.1
            text.lineCapStyle = .round
            text.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The icon's clip: a plate gripping the board's top edge, rising through concave fillets into
    /// an arched tab with a hanging hole. Coordinates are flipped (y grows downward).
    private static func clip() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 7.25, y: 2.45))
        // Over the top of the tab: in flipped coordinates, increasing angles run through 270° (up).
        p.appendArc(withCenter: NSPoint(x: 9, y: 2.45), radius: 1.75, startAngle: 180, endAngle: 360, clockwise: false)
        p.curve(
            to: NSPoint(x: 11.4, y: 3.05),
            controlPoint1: NSPoint(x: 10.75, y: 2.85), controlPoint2: NSPoint(x: 10.95, y: 3.05))
        p.appendArc(from: NSPoint(x: 12.55, y: 3.05), to: NSPoint(x: 12.55, y: 5.25), radius: 0.6)
        p.appendArc(from: NSPoint(x: 12.55, y: 5.25), to: NSPoint(x: 5.45, y: 5.25), radius: 0.7)
        p.appendArc(from: NSPoint(x: 5.45, y: 5.25), to: NSPoint(x: 5.45, y: 3.05), radius: 0.7)
        p.appendArc(from: NSPoint(x: 5.45, y: 3.05), to: NSPoint(x: 6.6, y: 3.05), radius: 0.6)
        p.line(to: NSPoint(x: 6.6, y: 3.05))
        p.curve(
            to: NSPoint(x: 7.25, y: 2.45),
            controlPoint1: NSPoint(x: 7.05, y: 3.05), controlPoint2: NSPoint(x: 7.25, y: 2.85))
        p.close()
        p.appendOval(in: NSRect(x: 8.28, y: 1.6, width: 1.44, height: 1.44))
        p.windingRule = .evenOdd
        return p
    }
}
