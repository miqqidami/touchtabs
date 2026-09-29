import AppKit

/// One tab as reported by the browser extension.
struct TabInfo: Codable, Equatable {
    var id: Int
    var title: String
    var url: String
    var active: Bool
    var pinned: Bool
    var audible: Bool
    var muted: Bool
    var loading: Bool
    /// -1 when the tab is not in a group (matches `chrome.tabGroups.TAB_GROUP_ID_NONE`).
    var groupId: Int
    /// Key into the session's favicon cache; nil when the browser has no favicon.
    var favicon: String?
}

/// A Chrome tab group (`chrome.tabGroups.TabGroup`).
struct GroupInfo: Codable, Equatable {
    var id: Int
    var title: String
    var color: String
    var collapsed: Bool
}

/// The tab strip of one browser window.
struct WindowState: Codable, Equatable {
    var id: Int
    var incognito: Bool
    var tabs: [TabInfo]
    var groups: [GroupInfo]
}

/// Messages sent by the extension. See PROTOCOL.md.
enum Incoming {
    struct Envelope: Decodable { let type: String }

    struct Hello: Decodable {
        let browser: String?
    }

    struct State: Decodable {
        let focused: Bool
        let window: WindowState?
    }

    struct Settings: Decodable {
        let keepControlStrip: Bool
        let alwaysShow: Bool
    }

    struct Favicon: Decodable {
        let key: String
        let data: String
    }
}

extension NSImage {
    /// Decodes a `data:<mime>;base64,<payload>` URL.
    convenience init?(dataURL: String) {
        guard let comma = dataURL.firstIndex(of: ","),
              dataURL[..<comma].hasSuffix(";base64"),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
        else { return nil }
        self.init(data: data)
    }
}
