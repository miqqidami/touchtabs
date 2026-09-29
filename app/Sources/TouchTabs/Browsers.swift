import Foundation

/// Chromium-based browsers the extension can run in.
enum Browsers {
    /// Bundle identifier → brand the extension reports via `navigator.userAgentData`.
    /// A nil brand means the browser doesn't report a distinctive one.
    private static let brands: [String: String?] = [
        "com.google.Chrome": "Google Chrome",
        "com.google.Chrome.beta": "Google Chrome",
        "com.google.Chrome.dev": "Google Chrome",
        "com.google.Chrome.canary": "Google Chrome",
        "com.google.chrome.for.testing": "Google Chrome for Testing",
        "org.chromium.Chromium": nil,
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.microsoft.edgemac.Beta": "Microsoft Edge",
        "com.microsoft.edgemac.Dev": "Microsoft Edge",
        "com.microsoft.edgemac.Canary": "Microsoft Edge",
        "com.brave.Browser": "Brave",
        "com.brave.Browser.beta": "Brave",
        "com.brave.Browser.nightly": "Brave",
        "com.operasoftware.Opera": "Opera",
        "com.vivaldi.Vivaldi": nil,
        "company.thebrowser.Browser": nil,
    ]

    static let knownBrands = Set(brands.values.compactMap { $0 })

    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return brands.keys.contains(bundleID)
            || (UserDefaults.standard.stringArray(forKey: "ExtraBrowserBundleIDs") ?? []).contains(bundleID)
    }

    static func brand(for bundleID: String?) -> String? {
        guard let bundleID, let brand = brands[bundleID] else { return nil }
        return brand
    }
}

/// User preferences (`defaults write io.github.miqqidami.touchtabs <key> …`).
final class Settings {
    /// ID of the extension in `extension/`, pinned by the `key` in its manifest.
    static let bundledExtensionID = "dogooidoflnmlpknaaiaeblffcechdji"

    private let defaults = UserDefaults.standard

    /// Show the tab strip over every app, not only while a browser is frontmost.
    var alwaysShow: Bool {
        get { defaults.bool(forKey: "AlwaysShow") }
        set { defaults.set(newValue, forKey: "AlwaysShow") }
    }

    /// Keep brightness/volume visible next to the tabs (adds a system close box).
    var keepControlStrip: Bool {
        get { defaults.bool(forKey: "KeepControlStrip") }
        set { defaults.set(newValue, forKey: "KeepControlStrip") }
    }

    /// Set once the app has registered itself as a login item, so turning
    /// Launch at Login off later sticks.
    var didSetUpLoginItem: Bool {
        get { defaults.bool(forKey: "DidSetUpLoginItem") }
        set { defaults.set(newValue, forKey: "DidSetUpLoginItem") }
    }

    func isAllowed(origin: String?) -> Bool {
        let prefix = "chrome-extension://"
        guard let origin, origin.hasPrefix(prefix) else { return false }
        if defaults.bool(forKey: "AllowAnyExtension") { return true }
        let id = String(origin.dropFirst(prefix.count))
        let extra = defaults.stringArray(forKey: "AllowedExtensionIDs") ?? []
        return id == Self.bundledExtensionID || extra.contains(id)
    }
}
