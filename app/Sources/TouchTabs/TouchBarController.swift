import AppKit

/// Owns the system-wide Touch Bar that shows the tab strip, plus the Control
/// Strip button that toggles it.
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let stripIdentifier = NSTouchBarItem.Identifier("io.github.miqqidami.touchtabs.strip")
    static let trayIdentifier = NSTouchBarItem.Identifier("io.github.miqqidami.touchtabs.tray")

    let stripView = TabStripView(frame: NSRect(x: 0, y: 0, width: 1004, height: 30))
    var onTrayTap: (() -> Void)?
    /// The user closed the bar with the system close box.
    var onUserDismiss: (() -> Void)?
    /// Leave the Control Strip visible. The system then adds a close box.
    var keepsControlStrip = false {
        didSet {
            guard keepsControlStrip != oldValue, isPresented else { return }
            SystemTouchBar.dismiss(touchBar)
            isPresented = false
            present()
        }
    }
    private(set) var isPresented = false
    private var isTrayVisible = false

    private lazy var touchBar: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.stripIdentifier]
        return bar
    }()

    private lazy var trayItem: NSCustomTouchBarItem = {
        let item = NSCustomTouchBarItem(identifier: Self.trayIdentifier)
        let glyph = Artwork.tabGlyph(size: NSSize(width: 22, height: 15), color: .white, template: false)
        item.view = NSButton(image: glyph, target: self, action: #selector(trayTapped))
        return item
    }()

    func install() {
        stripView.onDetach = { [weak self] in
            // If we still think it's up, the system dismissed it, not us.
            guard let self, self.isPresented else { return }
            self.isPresented = false
            if self.keepsControlStrip { self.onUserDismiss?() }
        }
        SystemTouchBar.setShowsCloseBoxWhenFrontmost(false)
        SystemTouchBar.addSystemTrayItem(trayItem)
    }

    func uninstall() {
        if isPresented { SystemTouchBar.dismiss(touchBar) }
        isPresented = false
        SystemTouchBar.setControlStripPresence(Self.trayIdentifier, visible: false)
        SystemTouchBar.removeSystemTrayItem(trayItem)
    }

    func setTrayVisible(_ visible: Bool) {
        guard visible != isTrayVisible else { return }
        isTrayVisible = visible
        SystemTouchBar.setControlStripPresence(Self.trayIdentifier, visible: visible)
    }

    func present() {
        guard !isPresented else { return }
        isPresented = true
        SystemTouchBar.present(touchBar, trayIdentifier: Self.trayIdentifier, coverControlStrip: !keepsControlStrip)
    }

    func hide() {
        guard isPresented else { return }
        isPresented = false
        SystemTouchBar.minimize(touchBar)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.stripIdentifier else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        stripView.fitToTouchBar()
        item.view = stripView
        return item
    }

    @objc private func trayTapped() {
        onTrayTap?()
    }
}
