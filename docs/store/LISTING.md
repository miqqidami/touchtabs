# Chrome Web Store listing

Everything to paste into the
[Developer Dashboard](https://chrome.google.com/webstore/devconsole), in the
order you'll need it.

## Before you submit

1. Build the upload: `make store-zip` → `build/touchtabs-store.zip` (the
   extension without its manifest `key`, which the store rejects).
2. Upload it as a **new item** and save it as a draft. The dashboard shows the
   item's ID right away.
3. Add that ID to `storeExtensionIDs` in
   `app/Sources/TouchTabs/HostInstaller.swift`. Otherwise the helper won't let
   the store build connect. Publish a new helper release.
4. Fill in the tabs below, then **Submit for review**.

## Store listing tab

**Name:** TouchTabs

**Summary** (132 characters max):

> Your Chrome tab strip on the MacBook Pro Touch Bar. Tap to switch, close and open tabs. Needs the free TouchTabs Mac helper.

**Description:**

> See and switch your tabs right on your MacBook Pro's Touch Bar.
>
> TouchTabs draws your tab strip on the Touch Bar the way Chrome draws it: favicons, titles, pinned tabs, tab groups with their colors, and audio and loading indicators.
>
> • Tap a tab to switch to it
> • Tap ✕ on the current tab to close it
> • Tap + to open a new tab
> • Tap a group's name to collapse or expand it
> • Swipe to scroll through lots of tabs
>
> Click the TouchTabs toolbar button (or press Option-Shift-T) to show or hide your tabs on the Touch Bar. Options let you keep brightness and volume visible next to your tabs, or show your tabs over every app.
>
> REQUIRES the free, open-source TouchTabs helper for macOS, because extensions can't draw on the Touch Bar themselves. Download it from https://github.com/miqqidami/touchtabs/releases/latest and open it once. After that, the browser starts it automatically.
>
> Needs a MacBook Pro with a Touch Bar and macOS 11 or later.
>
> Private by design: your tabs go only from Chrome to the helper on your Mac. Nothing is sent anywhere else.
>
> Open source (MIT): https://github.com/miqqidami/touchtabs

**Category:** Productivity → Tools

**Language:** English

**Graphics** (in `docs/store/`):

| Asset | File |
| --- | --- |
| Store icon, 128×128 | `icon-128.png` |
| Screenshot, 1280×800 | `screenshot-1280x800.png` |
| Small promo tile, 440×280 | `promo-tile-440x280.png` |

**Homepage URL:** https://github.com/miqqidami/touchtabs

**Support URL:** https://github.com/miqqidami/touchtabs/issues

## Privacy practices tab

**Single purpose:**

> Shows the browser's tab strip on the MacBook Pro Touch Bar and lets the user switch, close and open tabs from it.

**Permission justifications:**

| Permission | Justification |
| --- | --- |
| `tabs` | Reads the titles and URLs of the tabs in the focused window to draw them on the Touch Bar, and switches to, closes or opens tabs when the user taps the Touch Bar. |
| `tabGroups` | Shows tab groups with their names and colors, and collapses or expands a group when the user taps it. |
| `favicon` | Shows each tab's icon from the browser's own favicon cache, without any network requests. |
| `nativeMessaging` | Sends the tab strip to the TouchTabs macOS helper, which draws it on the Touch Bar. Extensions have no access to the Touch Bar themselves. |
| `storage` | Remembers the user's three display settings. |
| `alarms` | Periodically reconnects to the helper if it was installed after the browser started. |

**Remote code:** No, I am not using remote code.

**Data usage.** Check:

- **Web history** (tab URLs)
- **Website content** (tab titles and favicons)

Certify all three statements: data isn't sold to third parties, isn't used for
purposes unrelated to the single purpose, and isn't used to determine
creditworthiness.

**Privacy policy URL:** https://github.com/miqqidami/touchtabs/blob/main/PRIVACY.md

## Distribution tab

- **Visibility:** Public
- **Regions:** All regions

## Test instructions (for the reviewer)

> This extension needs a MacBook Pro with a Touch Bar and the companion macOS helper, because Chrome extensions can't access the Touch Bar.
>
> 1. Download TouchTabs.zip from https://github.com/miqqidami/touchtabs/releases/latest, unzip it and move TouchTabs.app to Applications.
> 2. Open TouchTabs.app once. If macOS blocks it, go to System Settings → Privacy & Security and click "Open Anyway". A dialog confirms it's registered with Chrome.
> 3. Install this extension. Within a few seconds, the tabs of the focused Chrome window appear on the Touch Bar whenever Chrome is in front.
> 4. Tap a tab to switch to it, tap ✕ on the current tab to close it, and tap + for a new tab. Click the toolbar button to hide or show the tabs on the Touch Bar.
>
> The helper's source is at https://github.com/miqqidami/touchtabs (the app/ folder).
