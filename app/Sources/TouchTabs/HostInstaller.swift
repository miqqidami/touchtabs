import AppKit
import ServiceManagement

/// Registers TouchTabs as a native messaging host with the installed
/// Chromium browsers, so the extension can start it on demand.
enum HostInstaller {
    static let hostName = "io.github.miqqidami.touchtabs"
    /// ID of the extension in `extension/`, pinned by the `key` in its manifest.
    static let extensionID = "dogooidoflnmlpknaaiaeblffcechdji"

    /// Browser name → user data directory under ~/Library/Application Support.
    private static let browsers: [(name: String, directory: String)] = [
        ("Google Chrome", "Google/Chrome"),
        ("Chrome Beta", "Google/Chrome Beta"),
        ("Chrome Dev", "Google/Chrome Dev"),
        ("Chrome Canary", "Google/Chrome Canary"),
        ("Chromium", "Chromium"),
        ("Microsoft Edge", "Microsoft Edge"),
        ("Brave", "BraveSoftware/Brave-Browser"),
        ("Vivaldi", "Vivaldi"),
        ("Arc", "Arc/User Data"),
    ]

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Writes the host manifest for every installed browser (always Chrome)
    /// and returns their names.
    static func install() throws -> [String] {
        var installed: [String] = []
        for browser in browsers {
            let userData = applicationSupport.appendingPathComponent(browser.directory)
            guard browser.name == "Google Chrome" || FileManager.default.fileExists(atPath: userData.path) else { continue }
            try install(inUserDataDirectory: userData)
            installed.append(browser.name)
        }
        removeLegacyLoginItem()
        return installed
    }

    static func install(inUserDataDirectory userData: URL) throws {
        let directory = userData.appendingPathComponent("NativeMessagingHosts")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try manifest().write(to: directory.appendingPathComponent("\(hostName).json"))
    }

    static func uninstall() {
        for browser in browsers {
            let file = applicationSupport.appendingPathComponent(browser.directory)
                .appendingPathComponent("NativeMessagingHosts/\(hostName).json")
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func manifest() throws -> Data {
        let executable = Bundle.main.executableURL!.resolvingSymlinksInPath().path
        let extra = UserDefaults.standard.stringArray(forKey: "AllowedExtensionIDs") ?? []
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Shows your browser tabs on the Touch Bar",
            "path": executable,
            "type": "stdio",
            "allowed_origins": ([extensionID] + extra).map { "chrome-extension://\($0)/" },
        ]
        return try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    }

    /// Earlier versions ran as a login item; now the browser starts us.
    private static func removeLegacyLoginItem() {
        guard #available(macOS 13.0, *), SMAppService.mainApp.status == .enabled else { return }
        try? SMAppService.mainApp.unregister()
    }

    // MARK: - Entry points

    /// `--install [--user-data-dir <dir>]` and `--uninstall`, for scripts.
    static func runFromCommandLine(_ arguments: [String]) -> Int32 {
        do {
            if arguments.contains("--uninstall") {
                uninstall()
                print("Removed the TouchTabs native messaging host.")
            } else if let flag = arguments.firstIndex(of: "--user-data-dir"), flag + 1 < arguments.count {
                try install(inUserDataDirectory: URL(fileURLWithPath: arguments[flag + 1]))
                print("Installed the TouchTabs native messaging host in \(arguments[flag + 1]).")
            } else {
                let browsers = try install()
                print("Installed the TouchTabs native messaging host for \(browsers.joined(separator: ", ")).")
            }
            return 0
        } catch {
            FileHandle.standardError.write("TouchTabs: \(error.localizedDescription)\n".data(using: .utf8)!)
            return 1
        }
    }

    /// Opening the app from Finder sets it up and explains the extension step.
    static func runInteractive() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        do {
            let browsers = try install()
            alert.messageText = "TouchTabs is set up"
            alert.informativeText = """
                Registered with \(browsers.joined(separator: ", ")).

                If you haven't yet, add the TouchTabs extension: open chrome://extensions, turn on \
                Developer mode, click “Load unpacked” and choose the Extension folder.

                From then on, your tabs appear on the Touch Bar whenever the browser is open. \
                Keep this app where it is; the browser starts it from here.
                """
            alert.addButton(withTitle: "Done")
            if Bundle.main.url(forResource: "Extension", withExtension: nil) != nil {
                alert.addButton(withTitle: "Show Extension Folder")
            }
        } catch {
            alert.messageText = "TouchTabs couldn't be set up"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
        }
        if alert.runModal() == .alertSecondButtonReturn,
           let folder = Bundle.main.url(forResource: "Extension", withExtension: nil) {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }
}
