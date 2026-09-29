import AppKit

/// Chrome Web Store listing images, drawn with the real tab strip renderer
/// (`--render-store <dir>`).
enum StoreArtwork {
    static func render(to directory: String) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = { (name: String) in (directory as NSString).appendingPathComponent(name) }
        PreviewRenderer.writePNG(size: NSSize(width: 1280, height: 800), scale: 1, to: path("screenshot-1280x800.png")) {
            drawScreenshot(height: 800)
        }
        PreviewRenderer.writePNG(size: NSSize(width: 440, height: 280), scale: 1, to: path("promo-tile-440x280.png")) {
            drawPromoTile(height: 280)
        }
        PreviewRenderer.writePNG(size: NSSize(width: 128, height: 128), scale: 1, to: path("icon-128.png")) {
            Artwork.drawAppIcon(in: CGRect(x: 0, y: 0, width: 128, height: 128))
        }
    }

    // MARK: - Screenshot

    private static func drawScreenshot(height h: CGFloat) {
        let w: CGFloat = 1280
        drawBackground(CGRect(x: 0, y: 0, width: w, height: h))

        drawText("Your Chrome tabs, on the Touch Bar", font: .systemFont(ofSize: 54, weight: .semibold),
                 color: .white, centerX: w / 2, top: 64, canvasHeight: h)
        drawText("Tap to switch  ·  ✕ to close  ·  + for a new tab  ·  swipe to scroll",
                 font: .systemFont(ofSize: 23), color: Theme.inactiveTitle, centerX: w / 2, top: 144, canvasHeight: h)

        // A MacBook Pro keyboard deck: Esc, Touch Bar, Touch ID, then keys,
        // drawn in a layer so its lower part can fade out over the background.
        let context = NSGraphicsContext.current!.cgContext
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        let deck = CGRect(x: 40, y: h - 250 - 330, width: w - 80, height: 330)
        NSGradient(starting: NSColor(hex: 0x3A3A3D), ending: NSColor(hex: 0x2A2A2C))?
            .draw(in: NSBezierPath(roundedRect: deck, xRadius: 30, yRadius: 30), angle: -90)

        let barTop = h - 282
        let barHeight: CGFloat = 46
        let esc = CGRect(x: 70, y: barTop - barHeight, width: 62, height: barHeight)
        drawKey(esc, label: "esc")
        let touchID = CGRect(x: w - 70 - barHeight, y: barTop - barHeight, width: barHeight, height: barHeight)
        NSColor.black.setFill()
        NSBezierPath(roundedRect: touchID, xRadius: 8, yRadius: 8).fill()
        NSColor(hex: 0x48484A).setStroke()
        let ring = NSBezierPath(roundedRect: touchID.insetBy(dx: 3, dy: 3), xRadius: 6, yRadius: 6)
        ring.lineWidth = 1.5
        ring.stroke()

        let bar = CGRect(x: esc.maxX + 10, y: barTop - barHeight, width: touchID.minX - 10 - esc.maxX - 10, height: barHeight)
        NSColor.black.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 8, yRadius: 8).fill()
        let strip = demoStrip()
        let scale = (bar.width - 12) / strip.bounds.width
        drawStrip(strip, at: CGPoint(x: bar.minX + 6, y: bar.midY - 15 * scale), scale: scale)

        // Two rows of keys, fading out.
        let keyWidth: CGFloat = 68, gap: CGFloat = 9
        for (row, inset) in [(0, 70.0), (1, 104.0)] {
            let top = barTop - barHeight - 16 - CGFloat(row) * (keyWidth + gap - 4)
            var x = CGFloat(inset)
            while x + keyWidth <= deck.maxX - 30 {
                drawKey(CGRect(x: x, y: top - keyWidth + 4, width: keyWidth, height: keyWidth - 4), label: nil)
                x += keyWidth + gap
            }
        }
        context.saveGState()
        context.setBlendMode(.destinationOut)
        NSColor.black.setFill()
        CGRect(x: 0, y: 0, width: w, height: deck.minY).fill()
        NSGradient(starting: .black, ending: NSColor.black.withAlphaComponent(0))?
            .draw(in: CGRect(x: 0, y: deck.minY, width: w, height: 200), angle: 90)
        context.restoreGState()
        context.endTransparencyLayer()

        // Close-up of the strip.
        drawText("Pinned tabs, tab groups, audio and loading indicators, just like Chrome",
                 font: .systemFont(ofSize: 20), color: NSColor(hex: 0x9AA0A6), centerX: w / 2, top: 588, canvasHeight: h)
        let zoom = CGRect(x: 64, y: h - 630 - 88, width: w - 128, height: 88)
        drawZoomedStrip(strip, in: zoom, scale: 2.5)
    }

    // MARK: - Promo tile

    private static func drawPromoTile(height h: CGFloat) {
        let w: CGFloat = 440
        drawBackground(CGRect(x: 0, y: 0, width: w, height: h))
        Artwork.drawAppIcon(in: CGRect(x: 18, y: h - 30 - 120, width: 120, height: 120))
        drawText("TouchTabs", font: .systemFont(ofSize: 38, weight: .bold), color: .white, left: 150, top: 48, canvasHeight: h)
        drawText("Your Chrome tabs,", font: .systemFont(ofSize: 18), color: Theme.inactiveTitle, left: 152, top: 100, canvasHeight: h)
        drawText("on the Touch Bar", font: .systemFont(ofSize: 18), color: Theme.inactiveTitle, left: 152, top: 124, canvasHeight: h)
        drawZoomedStrip(demoStrip(), in: CGRect(x: 18, y: 26, width: w - 36, height: 54), scale: 1.45)
    }

    // MARK: - Pieces

    private static func demoStrip() -> TabStripView {
        let strip = TabStripView(frame: NSRect(x: 0, y: 0, width: 1004, height: 30))
        strip.update(state: DemoData.window, favicons: DemoData.favicons)
        return strip
    }

    private static func drawStrip(_ strip: TabStripView, at origin: CGPoint, scale: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: origin.x, yBy: origin.y)
        transform.scale(by: scale)
        transform.concat()
        strip.draw(strip.bounds)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The start of the strip, magnified inside a black Touch Bar frame that
    /// fades out on the right.
    private static func drawZoomedStrip(_ strip: TabStripView, in frame: CGRect, scale: CGFloat) {
        let shape = NSBezierPath(roundedRect: frame, xRadius: 14, yRadius: 14)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        NSColor.black.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        let inset: CGFloat = 7
        drawStrip(strip, at: CGPoint(x: frame.minX + inset, y: frame.midY - 15 * scale), scale: scale)
        let fade = CGRect(x: frame.maxX - 90, y: frame.minY, width: 90, height: frame.height)
        NSGradient(starting: NSColor.black.withAlphaComponent(0), ending: .black)?.draw(in: fade, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawKey(_ rect: CGRect, label: String?) {
        NSColor(hex: 0x1C1C1E).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        if let label {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(hex: 0xD1D1D6)]
            let size = (label as NSString).size(withAttributes: attrs)
            (label as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
        }
    }

    private static func drawBackground(_ rect: CGRect) {
        NSGradient(starting: NSColor(hex: 0x2A2B2F), ending: NSColor(hex: 0x17181A))?.draw(in: rect, angle: -90)
    }

    /// Draws one line of text with its top edge `top` points below the top of the canvas.
    private static func drawText(_ text: String, font: NSFont, color: NSColor, centerX: CGFloat? = nil, left: CGFloat? = nil,
                                 top: CGFloat, canvasHeight: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let x = centerX.map { $0 - size.width / 2 } ?? left ?? 0
        (text as NSString).draw(at: CGPoint(x: x, y: canvasHeight - top - size.height), withAttributes: attrs)
    }
}
