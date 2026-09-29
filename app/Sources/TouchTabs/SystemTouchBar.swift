import AppKit

/// Wrapper around the private DFRFoundation / NSTouchBar APIs that let a
/// background app put its own bar on the Touch Bar, on top of whatever the
/// frontmost app shows (the same APIs Pock and MTMR use). Everything is looked
/// up at runtime, so a missing symbol degrades to a no-op instead of a crash.
enum SystemTouchBar {
    private static let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)

    static var isAvailable: Bool {
        class_getClassMethod(NSTouchBar.self, NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")) != nil
    }

    /// Shows or hides an item added with `addSystemTrayItem` in the Control Strip.
    static func setControlStripPresence(_ identifier: NSTouchBarItem.Identifier, visible: Bool) {
        typealias Fn = @convention(c) (NSString, ObjCBool) -> Void
        dfrFunction("DFRElementSetControlStripPresenceForIdentifier", as: Fn.self)?(identifier.rawValue as NSString, ObjCBool(visible))
    }

    /// Whether the system draws an (x) on the left of a system-modal bar.
    static func setShowsCloseBoxWhenFrontmost(_ shows: Bool) {
        typealias Fn = @convention(c) (ObjCBool) -> Void
        dfrFunction("DFRSystemModalShowsCloseBoxWhenFrontMost", as: Fn.self)?(ObjCBool(shows))
    }

    static func addSystemTrayItem(_ item: NSTouchBarItem) {
        send(NSTouchBarItem.self, "addSystemTrayItem:", item)
    }

    static func removeSystemTrayItem(_ item: NSTouchBarItem) {
        send(NSTouchBarItem.self, "removeSystemTrayItem:", item)
    }

    /// Presents `touchBar` over the frontmost app's bar. Covering the Control
    /// Strip gives the bar the full width and, as a side effect, is the only
    /// way to get rid of the system close box on the left.
    static func present(_ touchBar: NSTouchBar, trayIdentifier: NSTouchBarItem.Identifier, coverControlStrip: Bool) {
        if coverControlStrip {
            let selector = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
            if let method = class_getClassMethod(NSTouchBar.self, selector) {
                typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, Int64, AnyObject) -> Void
                unsafeBitCast(method_getImplementation(method), to: Fn.self)(
                    NSTouchBar.self, selector, touchBar, 1, trayIdentifier.rawValue as NSString)
                return
            }
        }
        send(NSTouchBar.self, "presentSystemModalTouchBar:systemTrayItemIdentifier:", touchBar, trayIdentifier.rawValue as NSString)
    }

    /// Collapses the bar back into its Control Strip item.
    static func minimize(_ touchBar: NSTouchBar) {
        send(NSTouchBar.self, "minimizeSystemModalTouchBar:", touchBar)
    }

    static func dismiss(_ touchBar: NSTouchBar) {
        send(NSTouchBar.self, "dismissSystemModalTouchBar:", touchBar)
    }

    // MARK: - Runtime lookup

    private static func dfrFunction<T>(_ name: String, as type: T.Type) -> T? {
        guard let dfr, let symbol = dlsym(dfr, name) else {
            NSLog("TouchTabs: missing DFRFoundation symbol \(name)")
            return nil
        }
        return unsafeBitCast(symbol, to: type)
    }

    private static func send(_ cls: AnyClass, _ selectorName: String, _ arg: AnyObject) {
        let selector = NSSelectorFromString(selectorName)
        guard let method = class_getClassMethod(cls, selector) else {
            NSLog("TouchTabs: missing +[\(cls) \(selectorName)]")
            return
        }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        unsafeBitCast(method_getImplementation(method), to: Fn.self)(cls, selector, arg)
    }

    private static func send(_ cls: AnyClass, _ selectorName: String, _ arg1: AnyObject, _ arg2: AnyObject) {
        let selector = NSSelectorFromString(selectorName)
        guard let method = class_getClassMethod(cls, selector) else {
            NSLog("TouchTabs: missing +[\(cls) \(selectorName)]")
            return
        }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject) -> Void
        unsafeBitCast(method_getImplementation(method), to: Fn.self)(cls, selector, arg1, arg2)
    }
}
