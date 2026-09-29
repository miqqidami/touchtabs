import AppKit

/// Vector drawing shared by the tab strip, the menu bar / Control Strip glyph
/// and the app + extension icons.
enum Artwork {
    /// Chrome's tab silhouette: rounded top corners and concave "feet" that
    /// flare out into the toolbar at the bottom. `body` is the tab without the
    /// feet; the feet extend `footRadius` beyond it on each side.
    static func tabPath(body: CGRect, cornerRadius r: CGFloat, footRadius f: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: body.minX - f, y: body.minY))
        path.appendArc(withCenter: CGPoint(x: body.minX - f, y: body.minY + f), radius: f,
                       startAngle: 270, endAngle: 360, clockwise: false)
        path.line(to: CGPoint(x: body.minX, y: body.maxY - r))
        path.appendArc(withCenter: CGPoint(x: body.minX + r, y: body.maxY - r), radius: r,
                       startAngle: 180, endAngle: 90, clockwise: true)
        path.line(to: CGPoint(x: body.maxX - r, y: body.maxY))
        path.appendArc(withCenter: CGPoint(x: body.maxX - r, y: body.maxY - r), radius: r,
                       startAngle: 90, endAngle: 0, clockwise: true)
        path.line(to: CGPoint(x: body.maxX, y: body.minY + f))
        path.appendArc(withCenter: CGPoint(x: body.maxX + f, y: body.minY + f), radius: f,
                       startAngle: 180, endAngle: 270, clockwise: false)
        path.close()
        return path
    }

    /// A small tab-on-a-toolbar glyph for the menu bar and the Control Strip.
    static func tabGlyph(size: NSSize, color: NSColor = .black, template: Bool = true) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            let base = rect.height * 0.16
            NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: rect.width, height: base),
                         xRadius: base / 2, yRadius: base / 2).fill()
            let body = CGRect(x: rect.width * 0.2, y: base * 0.5,
                              width: rect.width * 0.6, height: rect.height * 0.84 - base * 0.5)
            tabPath(body: body, cornerRadius: rect.height * 0.22, footRadius: rect.width * 0.08).fill()
            return true
        }
        image.isTemplate = template
        return image
    }

    /// The app / extension icon: a Chrome tab strip in a dark squircle.
    static func drawAppIcon(in rect: CGRect) {
        let s = rect.width
        let inset = s * 0.098
        let tile = rect.insetBy(dx: inset, dy: inset)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
        shadow.shadowBlurRadius = s * 0.02
        shadow.set()
        Theme.frame.setFill()
        tilePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        tilePath.addClip()
        NSGradient(starting: NSColor(hex: 0x2D2E32), ending: NSColor(hex: 0x1A1B1E))?.draw(in: tile, angle: -90)

        // Toolbar with an omnibox.
        let toolbarTop = tile.minY + tile.height * 0.40
        Theme.activeTab.setFill()
        CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: toolbarTop - tile.minY).fill()
        let omnibox = CGRect(x: tile.minX + tile.width * 0.1, y: tile.minY + tile.height * 0.13,
                             width: tile.width * 0.8, height: tile.height * 0.14)
        NSColor(hex: 0x202124).setFill()
        NSBezierPath(roundedRect: omnibox, xRadius: omnibox.height / 2, yRadius: omnibox.height / 2).fill()

        // Active tab.
        let body = CGRect(x: tile.minX + tile.width * 0.13, y: toolbarTop - 1,
                          width: tile.width * 0.56, height: tile.height * 0.30)
        Theme.activeTab.setFill()
        tabPath(body: body, cornerRadius: s * 0.06, footRadius: s * 0.045).fill()

        let favicon = CGRect(x: body.minX + body.width * 0.12, y: body.midY - s * 0.045,
                             width: s * 0.09, height: s * 0.09)
        Theme.throbber.setFill()
        NSBezierPath(ovalIn: favicon).fill()
        let title = CGRect(x: favicon.maxX + s * 0.04, y: body.midY - s * 0.018,
                           width: body.maxX - favicon.maxX - s * 0.1, height: s * 0.036)
        Theme.activeTitle.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: title, xRadius: title.height / 2, yRadius: title.height / 2).fill()

        // New tab button.
        let plus = NSBezierPath()
        let c = CGPoint(x: tile.minX + tile.width * 0.83, y: body.midY)
        let arm = s * 0.045
        plus.move(to: CGPoint(x: c.x - arm, y: c.y)); plus.line(to: CGPoint(x: c.x + arm, y: c.y))
        plus.move(to: CGPoint(x: c.x, y: c.y - arm)); plus.line(to: CGPoint(x: c.x, y: c.y + arm))
        plus.lineWidth = s * 0.02
        plus.lineCapStyle = .round
        Theme.inactiveTitle.setStroke()
        plus.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// SF Symbols tinted to a solid color (works back to macOS 11).
enum Glyph {
    private static var cache: [String: NSImage] = [:]

    static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSImage? {
        let key = "\(name)|\(pointSize)|\(weight.rawValue)|\(color)"
        if let cached = cache[key] { return cached }
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
        else { return nil }
        let tinted = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        cache[key] = tinted
        return tinted
    }
}
