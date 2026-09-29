import AppKit

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Chrome's dark-mode tab strip palette.
enum Theme {
    static let frame = NSColor(hex: 0x202124)
    static let activeTab = NSColor(hex: 0x35363A)
    static let pressedTab = NSColor(hex: 0x2B2C30)
    static let activeTitle = NSColor(hex: 0xE8EAED)
    static let inactiveTitle = NSColor(hex: 0xBDC1C6)
    static let separator = NSColor(hex: 0x5F6368)
    static let throbber = NSColor(hex: 0x8AB4F8)
    static let groupChipText = NSColor(hex: 0x202124)

    /// `chrome.tabGroups.Color` values, dark-mode variants.
    static func groupColor(_ name: String) -> NSColor {
        switch name {
        case "blue": return NSColor(hex: 0x8AB4F8)
        case "red": return NSColor(hex: 0xF28B82)
        case "yellow": return NSColor(hex: 0xFDD663)
        case "green": return NSColor(hex: 0x81C995)
        case "pink": return NSColor(hex: 0xFF8BCB)
        case "purple": return NSColor(hex: 0xD7AEFB)
        case "cyan": return NSColor(hex: 0x78D9EC)
        case "orange": return NSColor(hex: 0xFCAD70)
        default: return NSColor(hex: 0xDADCE0) // grey
        }
    }
}
