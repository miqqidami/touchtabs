import AppKit

/// Runs while the browser extension holds its native messaging port open:
/// Chrome starts this process when the extension connects and it exits when
/// the browser closes the port.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Every profile (and every browser) starts its own host. The one whose
    /// window was focused last announces it; the others step aside.
    private static let focusNotification = Notification.Name("io.github.miqqidami.touchtabs.focused")
    private static let releaseNotification = Notification.Name("io.github.miqqidami.touchtabs.released")

    private let touchBar = TouchBarController()
    private let channel: NativeMessagingChannel?
    private let decoder = JSONDecoder()
    private let processID = String(ProcessInfo.processInfo.processIdentifier)
    private var terminationSource: DispatchSourceSignal?

    private var brand = "Chromium"
    private var window: WindowState?
    private var favicons: [String: NSImage] = [:]
    private var alwaysShow = false
    private var hiddenByUser = false
    private var ownsFocus = false
    /// Another host whose window was focused more recently.
    private var yieldedTo: String?

    /// `channel` is nil in demo mode.
    init(channel: NativeMessagingChannel?) {
        self.channel = channel
    }

    private var isDemo: Bool { channel == nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard SystemTouchBar.isAvailable else {
            // Stay alive anyway: exiting would make the extension relaunch us.
            NSLog("TouchTabs: this Mac's Touch Bar APIs are unavailable")
            return
        }

        touchBar.install()
        touchBar.onTrayTap = { [weak self] in self?.toggleFromTray() }
        touchBar.onUserDismiss = { [weak self] in self?.hiddenByUser = true }
        let strip = touchBar.stripView
        strip.onActivate = { [weak self] id in self?.channel?.send(["type": "activate", "tabId": id]) }
        strip.onClose = { [weak self] id in self?.channel?.send(["type": "close", "tabId": id]) }
        strip.onNewTab = { [weak self] in self?.channel?.send(["type": "newTab"]) }
        strip.onToggleGroup = { [weak self] id in self?.channel?.send(["type": "toggleGroup", "groupId": id]) }

        if let channel {
            channel.onMessage = { [weak self] data in self?.handle(data) }
            channel.onClose = { NSApp.terminate(nil) }
            channel.start()
            channel.send(["type": "ready", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "dev"])
        }

        // Chrome stops the host with SIGTERM; exit through AppKit so the bar is cleaned up.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSource = source

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(frontmostAppChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(otherHostFocused(_:)), name: Self.focusNotification,
                                object: nil, suspensionBehavior: .deliverImmediately)
        distributed.addObserver(self, selector: #selector(otherHostReleased(_:)), name: Self.releaseNotification,
                                object: nil, suspensionBehavior: .deliverImmediately)
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchBar.uninstall()
        post(Self.releaseNotification)
    }

    // MARK: - Messages

    private func handle(_ data: Data) {
        guard let envelope = try? decoder.decode(Incoming.Envelope.self, from: data) else { return }
        switch envelope.type {
        case "hello":
            brand = (try? decoder.decode(Incoming.Hello.self, from: data))?.browser ?? "Chromium"
            refresh()
        case "settings":
            guard let settings = try? decoder.decode(Incoming.Settings.self, from: data) else { return }
            alwaysShow = settings.alwaysShow
            touchBar.keepsControlStrip = settings.keepControlStrip
            refresh()
        case "state":
            do {
                let message = try decoder.decode(Incoming.State.self, from: data)
                window = message.window
                if message.focused { takeFocus() }
                refresh()
            } catch {
                NSLog("TouchTabs: bad state message: \(error)")
            }
        case "favicon":
            guard let message = try? decoder.decode(Incoming.Favicon.self, from: data),
                  let image = NSImage(dataURL: message.data)
            else { return }
            favicons[message.key] = image
            refresh()
        default:
            break
        }
    }

    // MARK: - Coordinating with other hosts

    private func takeFocus() {
        yieldedTo = nil
        guard !ownsFocus else { return }
        ownsFocus = true
        post(Self.focusNotification)
    }

    private func post(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(name, object: processID, userInfo: nil, deliverImmediately: true)
    }

    @objc private func otherHostFocused(_ notification: Notification) {
        guard let sender = notification.object as? String, sender != processID else { return }
        ownsFocus = false
        yieldedTo = sender
        refresh()
    }

    @objc private func otherHostReleased(_ notification: Notification) {
        guard let sender = notification.object as? String, sender == yieldedTo else { return }
        yieldedTo = nil
        refresh()
    }

    // MARK: - Showing the strip

    @objc private func frontmostAppChanged() {
        hiddenByUser = false
        refresh()
    }

    private func toggleFromTray() {
        hiddenByUser = touchBar.isPresented
        if !hiddenByUser { channel?.send(["type": "sync"]) }
        refresh()
    }

    private func refresh() {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let expected = Browsers.brand(for: frontmost)
        let isOurBrowser = Browsers.isBrowser(frontmost)
            && (expected == nil || expected == brand || !Browsers.knownBrands.contains(brand))
        let wanted = isDemo || ((alwaysShow || isOurBrowser) && yieldedTo == nil)
        touchBar.setTrayVisible(wanted)

        let state = isDemo ? DemoData.window : window
        touchBar.stripView.update(state: state, favicons: isDemo ? DemoData.favicons : favicons)
        if wanted, state != nil, !hiddenByUser {
            touchBar.present()
        } else {
            touchBar.hide()
        }
    }
}
