# TouchTabs

**Your Chrome tab strip, on the MacBook Pro Touch Bar.**

![TouchTabs on the Touch Bar](docs/preview.png)

TouchTabs mirrors the tabs of your focused Chrome window onto the Touch Bar,
drawn like Chrome's own dark tab strip: favicons, fading titles, the active tab's
shape and close button, pinned tabs, tab groups with colored chips and
underlines, audio indicators and loading spinners.

- **Tap** a tab to switch to it
- **Tap ✕** on the active tab to close it
- **Tap +** for a new tab
- **Tap a group chip** to collapse or expand the group
- **Swipe** to scroll when there are more tabs than fit

It shows up whenever a Chromium browser is frontmost, using the whole Touch
Bar, and gets out of the way when you switch apps. It starts at login, so the
tabs are there whenever Chrome is.

Here it is on real hardware:

![Real Touch Bar screenshot](docs/touchbar.png)

## How it works

```
┌──────────────────────┐   WebSocket, 127.0.0.1:47823   ┌──────────────────────┐
│  Chrome extension    │ ─── tabs, groups, favicons ──▶ │  TouchTabs.app       │
│  (MV3 service worker)│ ◀── activate / close / new ─── │  (menu bar, Swift)   │
└──────────────────────┘                                └──────────┬───────────┘
                                                                   │ system-modal
                                                                   ▼ NSTouchBar
                                                             ┌────────────┐
                                                             │ Touch Bar  │
                                                             └────────────┘
```

- **`extension/`**: a Manifest V3 extension. It listens to `chrome.tabs`,
  `chrome.tabGroups` and `chrome.windows` events and streams the focused window's
  tab strip to the app. It fetches favicons through Chrome's own favicon cache
  (the `favicon` permission), so it never contacts any website.
- **`app/`**: a small Swift menu bar app with no dependencies. It runs a
  loopback-only WebSocket server (Network.framework) and custom-draws the tab
  strip. Because only the frontmost app can normally set the Touch Bar, it uses
  the private system-modal Touch Bar API (the one
  [Pock](https://github.com/pock/pock) and [MTMR](https://github.com/Toxblh/MTMR)
  use) to show the strip on top of Chrome's own bar.

The wire format is documented in [PROTOCOL.md](PROTOCOL.md).

## Install

Requirements: a Mac with a Touch Bar, macOS 11 or later, and Chrome 116+ (or
another Chromium browser: Edge, Brave, Opera, Vivaldi, Arc).

### 1. Build and run the app

```sh
git clone https://github.com/miqqidami/touchtabs.git
cd touchtabs
make install        # builds TouchTabs.app (universal), copies it to /Applications, starts it
```

This needs the Xcode command line tools (Swift 5.9+). On first launch the app
adds itself as a login item (macOS 13+), so it's always running. Turn that off
with **Launch at Login** in its menu bar menu.

> The app is ad-hoc signed. If you downloaded a build instead of compiling it,
> right-click it → **Open** the first time.

### 2. Load the extension

1. Open `chrome://extensions` and turn on **Developer mode**.
2. Click **Load unpacked** and select the `extension/` folder. (The app also
   ships a copy: menu bar icon → **Show Browser Extension in Finder**.)
3. Switch to Chrome. Your tabs appear on the Touch Bar.

The extension's popup shows whether it's connected to the app.

## Using it

- While a browser is frontmost, TouchTabs takes over the whole Touch Bar,
  including the Control Strip. To keep brightness and volume next to your tabs,
  turn on **Keep Control Strip Visible** in the menu bar menu. macOS then adds a
  ✕ on the left, and the TouchTabs button in the Control Strip toggles back to
  Chrome's own Touch Bar.
- **Show Tabs Over All Apps** (menu bar) keeps the strip on the Touch Bar
  everywhere, showing your most recently used browser window.
- With several browsers or profiles running, TouchTabs follows whichever
  window you focused last.

## Configuration

Settings live in the `io.github.miqqidami.touchtabs` defaults domain:

| Key | Type | Purpose |
| --- | --- | --- |
| `AlwaysShow` | bool | Same as **Show Tabs Over All Apps** |
| `KeepControlStrip` | bool | Same as **Keep Control Strip Visible** |
| `AllowedExtensionIDs` | array | Extra extension IDs allowed to connect (for example, a Web Store build of the extension) |
| `ExtraBrowserBundleIDs` | array | More app bundle IDs to treat as browsers |
| `AllowAnyExtension` | bool | Accept any `chrome-extension://` origin (development only) |

```sh
defaults write io.github.miqqidami.touchtabs AllowedExtensionIDs -array <extension-id>
```

## Privacy and security

- Tab titles and URLs go only from your browser to the app on the same Mac,
  over a socket bound to `127.0.0.1`. Nothing leaves your machine, and neither
  part makes any network request of its own.
- The app accepts connections only from the TouchTabs extension. Its ID is
  pinned by the `key` in `extension/manifest.json`, and the app checks the
  WebSocket handshake's `Origin` header against it, so web pages can't connect.
- The extension asks for `tabs` (titles/URLs), `tabGroups`, `favicon` and
  `alarms` (to reconnect when the app starts after the browser). It needs no
  host permissions.

## Development

```sh
make demo       # show sample tabs on the Touch Bar, no browser needed
make preview    # re-render docs/preview.png offscreen
make icons      # re-render the extension icons from the vector artwork
make extension-zip
```

Code map:

| File | What it does |
| --- | --- |
| `app/Sources/TouchTabs/TabStripView.swift` | Chrome-style layout, drawing, taps, scrolling with momentum |
| `app/Sources/TouchTabs/SystemTouchBar.swift` | Private DFRFoundation / NSTouchBar calls, looked up at runtime |
| `app/Sources/TouchTabs/BridgeServer.swift` | Loopback WebSocket server with origin check |
| `app/Sources/TouchTabs/AppDelegate.swift` | Sessions, which window to show, when to show it, menu bar |
| `extension/background.js` | Tab/group/window events, favicons, commands |

## Limitations

- Relies on private macOS APIs, so a future macOS update could break it. This
  version was tested on macOS 26 (Tahoe) on a 16" MacBook Pro.
- Only the focused window's tabs are shown, just like Chrome's tab strip.
- Incognito windows are shown only if you allow the extension in incognito.

## License

[MIT](LICENSE)
