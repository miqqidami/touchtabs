import AppKit

let arguments = CommandLine.arguments

if let flag = arguments.firstIndex(of: "--render-preview"), flag + 1 < arguments.count {
    PreviewRenderer.renderPreview(to: arguments[flag + 1])
    exit(0)
}
if let flag = arguments.firstIndex(of: "--render-icons"), flag + 1 < arguments.count {
    PreviewRenderer.renderIcons(to: arguments[flag + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate(demoMode: arguments.contains("--demo"))
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
