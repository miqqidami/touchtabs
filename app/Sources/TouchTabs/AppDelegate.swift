import AppKit
import ServiceManagement

/// State reported by one connected extension instance.
final class BrowserSession {
    let client: BridgeClient
    var brand = "Chromium"
    var window: WindowState?
    var favicons: [String: NSImage] = [:]
    var lastFocused = Date.distantPast

    init(client: BridgeClient) {
        self.client = client
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let repositoryURL = URL(string: "https://github.com/miqqidami/touchtabs")!

    private let settings = Settings()
    private let touchBar = TouchBarController()
    private lazy var server = BridgeServer { [settings] origin in settings.isAllowed(origin: origin) }
    private let decoder = JSONDecoder()
    private let demoMode: Bool

    private var sessions: [ObjectIdentifier: BrowserSession] = [:]
    private var shownSession: BrowserSession?
    private var hiddenByUser = false
    private var serverError: String?
    private var statusItem: NSStatusItem?

    init(demoMode: Bool) {
        self.demoMode = demoMode
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSLog("TouchTabs: already running")
            NSApp.terminate(nil)
            return
        }

        setUpStatusItem()
        guard SystemTouchBar.isAvailable else {
            serverError = "This Mac's Touch Bar APIs are unavailable."
            return
        }

        registerLoginItemOnFirstLaunch()
        touchBar.keepsControlStrip = settings.keepControlStrip
        touchBar.install()
        touchBar.onTrayTap = { [weak self] in self?.toggleFromTray() }
        touchBar.onUserDismiss = { [weak self] in self?.hiddenByUser = true }
        let strip = touchBar.stripView
        strip.onActivate = { [weak self] id in self?.shownSession?.client.send(["type": "activate", "tabId": id]) }
        strip.onClose = { [weak self] id in self?.shownSession?.client.send(["type": "close", "tabId": id]) }
        strip.onNewTab = { [weak self] in self?.shownSession?.client.send(["type": "newTab"]) }
        strip.onToggleGroup = { [weak self] id in self?.shownSession?.client.send(["type": "toggleGroup", "groupId": id]) }

        server.onConnect = { [weak self] client in
            self?.sessions[ObjectIdentifier(client)] = BrowserSession(client: client)
        }
        server.onDisconnect = { [weak self] client in
            self?.sessions[ObjectIdentifier(client)] = nil
            self?.refresh()
        }
        server.onMessage = { [weak self] client, data in self?.handle(data, from: client) }
        server.onListenerError = { [weak self] error in self?.serverError = error }
        if !demoMode { server.start() }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(frontmostAppChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchBar.uninstall()
    }

    // MARK: - Messages

    private func handle(_ data: Data, from client: BridgeClient) {
        guard let session = sessions[ObjectIdentifier(client)],
              let envelope = try? decoder.decode(Incoming.Envelope.self, from: data)
        else { return }

        switch envelope.type {
        case "hello":
            session.brand = (try? decoder.decode(Incoming.Hello.self, from: data))?.browser ?? "Chromium"
        case "state":
            do {
                let message = try decoder.decode(Incoming.State.self, from: data)
                session.window = message.window
                if message.focused { session.lastFocused = Date() }
                refresh()
            } catch {
                NSLog("TouchTabs: bad state message: \(error)")
            }
        case "favicon":
            guard let message = try? decoder.decode(Incoming.Favicon.self, from: data),
                  let image = NSImage(dataURL: message.data)
            else { return }
            session.favicons[message.key] = image
            if session === shownSession { refresh() }
        default:
            break
        }
    }

    // MARK: - Showing the strip

    @objc private func frontmostAppChanged() {
        hiddenByUser = false
        refresh()
    }

    private func toggleFromTray() {
        hiddenByUser = touchBar.isPresented
        if !hiddenByUser { shownSession?.client.send(["type": "sync"]) }
        refresh()
    }

    /// The session to show while `bundleID` is frontmost: the most recently
    /// focused window among extensions whose browser brand fits the app.
    private func session(forFrontmost bundleID: String?) -> BrowserSession? {
        let expected = Browsers.brand(for: bundleID)
        return sessions.values
            .filter { $0.window != nil }
            .filter { expected == nil || $0.brand == expected || !Browsers.knownBrands.contains($0.brand) }
            .max { $0.lastFocused < $1.lastFocused }
    }

    private func refresh() {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let browserIsFrontmost = Browsers.isBrowser(frontmost)
        let wanted = demoMode || settings.alwaysShow || browserIsFrontmost
        touchBar.setTrayVisible(wanted)

        let strip = touchBar.stripView
        if demoMode {
            strip.update(state: DemoData.window, favicons: DemoData.favicons)
        } else {
            shownSession = session(forFrontmost: frontmost)
            strip.placeholder = sessions.isEmpty
                ? "Install the TouchTabs extension in your browser to see your tabs here"
                : "No browser window open"
            strip.update(state: shownSession?.window, favicons: shownSession?.favicons ?? [:])
        }

        // With no extension connected, still show the setup hint; with an
        // extension but no window, get out of the way.
        let hasContent = demoMode || shownSession != nil || sessions.isEmpty
        if wanted, hasContent, !hiddenByUser {
            touchBar.present()
        } else {
            touchBar.hide()
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Artwork.tabGlyph(size: NSSize(width: 18, height: 13))
        item.button?.toolTip = "TouchTabs"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status: String
        if let serverError {
            status = serverError
        } else if demoMode {
            status = "Demo mode"
        } else if sessions.isEmpty {
            status = "Waiting for the browser extension…"
        } else {
            let brands = Set(sessions.values.map(\.brand)).sorted().joined(separator: ", ")
            status = "Connected: \(brands)"
        }
        let statusItem = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())

        let always = NSMenuItem(title: "Show Tabs Over All Apps", action: #selector(toggleAlwaysShow), keyEquivalent: "")
        always.target = self
        always.state = settings.alwaysShow ? .on : .off
        menu.addItem(always)

        let controlStrip = NSMenuItem(title: "Keep Control Strip Visible", action: #selector(toggleKeepControlStrip), keyEquivalent: "")
        controlStrip.target = self
        controlStrip.state = settings.keepControlStrip ? .on : .off
        menu.addItem(controlStrip)

        if #available(macOS 13.0, *) {
            let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
        }
        menu.addItem(.separator())

        if Bundle.main.url(forResource: "Extension", withExtension: nil) != nil {
            let reveal = NSMenuItem(title: "Show Browser Extension in Finder", action: #selector(revealExtension), keyEquivalent: "")
            reveal.target = self
            menu.addItem(reveal)
        }
        let site = NSMenuItem(title: "TouchTabs on GitHub", action: #selector(openRepository), keyEquivalent: "")
        site.target = self
        menu.addItem(site)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit TouchTabs", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func toggleAlwaysShow() {
        settings.alwaysShow.toggle()
        refresh()
    }

    @objc private func toggleKeepControlStrip() {
        settings.keepControlStrip.toggle()
        touchBar.keepsControlStrip = settings.keepControlStrip
        refresh()
    }

    /// Start with the Mac so the tabs are there whenever Chrome is. Only done
    /// once, and only from an installed .app, so the menu toggle stays in charge.
    private func registerLoginItemOnFirstLaunch() {
        guard #available(macOS 13.0, *), !demoMode, !settings.didSetUpLoginItem,
              Bundle.main.bundleURL.pathExtension == "app"
        else { return }
        do {
            try SMAppService.mainApp.register()
            settings.didSetUpLoginItem = true
        } catch {
            NSLog("TouchTabs: could not add login item: \(error)")
        }
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func revealExtension() {
        guard let url = Bundle.main.url(forResource: "Extension", withExtension: nil) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func openRepository() {
        NSWorkspace.shared.open(Self.repositoryURL)
    }
}
