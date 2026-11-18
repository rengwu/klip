import Cocoa

/// Never takes focus, so the search field keeps the keyboard while the preview is up.
private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A floating preview beside the panel for the highlighted image row.
final class ImagePreview {
    /// The largest the image is drawn, in points. Smaller images show at their natural size.
    private static let maxSize = NSSize(width: 360, height: 360)
    private static let minSide: CGFloat = 48
    private static let inset: CGFloat = 8
    private static let gap: CGFloat = 8

    private let window: PreviewPanel
    private let imageView = NSImageView()
    private let cache = NSCache<NSURL, NSImage>()
    /// The image the preview should show; a decode that finishes late is dropped.
    private var wanted: URL?

    init() {
        // Titled with a hidden title bar, like the panel, for matching corners and shadow.
        window = PreviewPanel(
            contentRect: .zero, styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: true)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.animationBehavior = .none

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        window.contentView = background
        imageView.imageScaling = .scaleProportionallyDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(imageView)
        let inset = Self.inset
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: background.topAnchor, constant: inset),
            imageView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: inset),
            imageView.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -inset),
            imageView.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -inset),
        ])
    }

    func show(_ url: URL, beside parent: NSWindow) {
        wanted = url
        if let cached = cache.object(forKey: url as NSURL) {
            present(cached, beside: parent)
            return
        }
        let scale = parent.backingScaleFactor
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak parent] in
            let image = Self.decode(url, scale: scale)
            DispatchQueue.main.async {
                guard let self, let parent, let image else { return }
                self.cache.setObject(image, forKey: url as NSURL)
                if self.wanted == url { self.present(image, beside: parent) }
            }
        }
    }

    func hide() {
        wanted = nil
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    /// Beside the panel's right edge, or its left when the screen has no room, top-aligned.
    private func present(_ image: NSImage, beside parent: NSWindow) {
        guard parent.isVisible else { return }
        let size = NSSize(
            width: max(image.size.width, Self.minSide) + 2 * Self.inset,
            height: max(image.size.height, Self.minSide) + 2 * Self.inset)
        let anchor = parent.frame
        let area = parent.screen?.visibleFrame ?? anchor
        var x = anchor.maxX + Self.gap
        if x + size.width > area.maxX { x = anchor.minX - Self.gap - size.width }
        let y = max(anchor.maxY - size.height, area.minY)
        imageView.image = image
        window.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        if window.parent == nil { parent.addChildWindow(window, ordered: .above) }
        window.orderFront(nil)
    }

    /// Decodes only as many pixels as the preview draws, sized in points for the screen's scale.
    private static func decode(_ url: URL, scale: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
            pixelWidth > 0, pixelHeight > 0
        else { return nil }
        let natural = NSSize(width: pixelWidth / scale, height: pixelHeight / scale)
        let fit = min(1, maxSize.width / natural.width, maxSize.height / natural.height)
        let size = NSSize(
            width: max(1, (natural.width * fit).rounded()),
            height: max(1, (natural.height * fit).rounded()))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int((max(size.width, size.height) * scale).rounded(.up)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: size)
    }
}
