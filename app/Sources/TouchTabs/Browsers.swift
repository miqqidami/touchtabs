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
