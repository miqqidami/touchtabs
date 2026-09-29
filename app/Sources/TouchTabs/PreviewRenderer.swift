import AppKit

/// Sample tab strip used by `--demo` and `--render-preview`.
enum DemoData {
    static let window = WindowState(
        id: 1,
        incognito: false,
        tabs: [
            tab(1, "Inbox (3) — Mail", icon: "m", pinned: true),
            tab(2, "Calendar", icon: "c", pinned: true),
            tab(3, "touchtabs: Chrome tabs on your Touch Bar", icon: "t"),
            tab(4, "Swift Concurrency | Documentation", icon: "s", group: 10),
            tab(5, "NSTouchBar | Apple Developer Documentation", icon: "a", group: 10),
            tab(6, "Lo-fi radio — beats to code to", icon: "l", active: true, audible: true),
            tab(7, "How do I scroll an NSView on the Touch Bar?", icon: "q", loading: true),
            tab(8, "Flights to Lisbon", icon: "f", group: 11),
            tab(9, "New Tab", icon: nil),
        ],
        groups: [
            GroupInfo(id: 10, title: "Research", color: "blue", collapsed: false),
            GroupInfo(id: 11, title: "Trip", color: "green", collapsed: true),
        ])

    static let favicons: [String: NSImage] = [
        "m": letterIcon("M", NSColor(hex: 0xEA4335)),
        "c": letterIcon("31", NSColor(hex: 0x4285F4)),
        "t": letterIcon("T", NSColor(hex: 0x6E7681)),
        "s": letterIcon("S", NSColor(hex: 0xF05138)),
        "a": letterIcon("A", NSColor(hex: 0x8E8E93)),
        "l": letterIcon("▶", NSColor(hex: 0xFF0033)),
        "q": letterIcon("Q", NSColor(hex: 0xF48024)),
        "f": letterIcon("✈", NSColor(hex: 0x0F9D58)),
    ]

    private static func tab(_ id: Int, _ title: String, icon: String?, active: Bool = false, pinned: Bool = false,
                            audible: Bool = false, loading: Bool = false, group: Int = -1) -> TabInfo {
        TabInfo(id: id, title: title, url: "https://example.com/\(id)", active: active, pinned: pinned,
                audible: audible, muted: false, loading: loading, groupId: group, favicon: icon)
    }

    private static func letterIcon(_ text: String, _ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
            let font = NSFont.systemFont(ofSize: text.count > 1 ? 14 : 19, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
            return true
        }
    }
}

/// Offscreen rendering for the README screenshot and the icon assets.
enum PreviewRenderer {
    static func renderPreview(to path: String) {
        let strip = TabStripView(frame: NSRect(x: 0, y: 0, width: 900, height: 30))
        strip.update(state: DemoData.window, favicons: DemoData.favicons)
        let padding: CGFloat = 10
        let size = NSSize(width: strip.bounds.width + padding * 2, height: strip.bounds.height + padding * 2)
        write(png(size: size, scale: 2) {
            NSColor.black.setFill()
            NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: 12, yRadius: 12).fill()
            let transform = NSAffineTransform()
            transform.translateX(by: padding, yBy: padding)
            transform.concat()
            strip.draw(strip.bounds)
        }, to: path)
    }

    static func renderIcons(to directory: String) {
        let fm = FileManager.default
        let iconset = (directory as NSString).appendingPathComponent("AppIcon.iconset")
        try? fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                write(icon(pixels: points * scale), to: (iconset as NSString).appendingPathComponent(name))
            }
        }
        for pixels in [16, 32, 48, 128] {
            write(icon(pixels: pixels), to: (directory as NSString).appendingPathComponent("icon\(pixels).png"))
        }
    }

    private static func icon(pixels: Int) -> Data {
        let size = NSSize(width: pixels, height: pixels)
        return png(size: size, scale: 1) { Artwork.drawAppIcon(in: CGRect(origin: .zero, size: size)) }
    }

    private static func png(size: NSSize, scale: CGFloat, draw: () -> Void) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    private static func write(_ data: Data, to path: String) {
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write("Could not write \(path): \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }
}
