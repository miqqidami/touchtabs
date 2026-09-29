import AppKit

// Chrome may close our stdout at any time; don't die writing to it.
signal(SIGPIPE, SIG_IGN)

let arguments = CommandLine.arguments

if let flag = arguments.firstIndex(of: "--render-preview"), flag + 1 < arguments.count {
    PreviewRenderer.renderPreview(to: arguments[flag + 1])
    exit(0)
}
if let flag = arguments.firstIndex(of: "--render-icons"), flag + 1 < arguments.count {
    PreviewRenderer.renderIcons(to: arguments[flag + 1])
    exit(0)
}
if arguments.contains("--install") || arguments.contains("--uninstall") {
    exit(HostInstaller.runFromCommandLine(arguments))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Chrome launches native messaging hosts with the caller's origin as an argument.
let launchedByBrowser = arguments.dropFirst().contains { $0.hasPrefix("chrome-extension://") }
if launchedByBrowser || arguments.contains("--demo") {
    let delegate = AppDelegate(channel: launchedByBrowser ? NativeMessagingChannel() : nil)
    app.delegate = delegate
    app.run()
} else {
    // Opened from Finder: register with the browsers and explain the next step.
    HostInstaller.runInteractive()
}
