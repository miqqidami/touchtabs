# TouchTabs privacy policy

_Last updated: September 29, 2026_

TouchTabs is a Chrome extension and a companion macOS helper that shows your
browser's tab strip on the MacBook Pro Touch Bar.

## What TouchTabs reads

To draw your tabs, the extension reads these details for the tabs in your
focused browser window:

- title and URL
- favicon, from the browser's own favicon cache
- whether the tab is active, pinned, playing audio, muted or loading
- tab group names and colors

It also stores three settings in the browser's local extension storage: whether
the tabs are shown, whether the Control Strip stays visible, and whether the
tabs show over all apps.

## Where it goes

The extension sends this information only to the TouchTabs helper on the same
Mac. It uses Chrome's native messaging, a direct pipe between the browser and
the helper. The helper keeps it in memory to draw the Touch Bar and discards it
when it exits, which happens when the browser quits.

TouchTabs does not:

- send any data off your Mac, or make network requests of its own
- store your browsing data on disk
- use analytics, tracking or advertising
- sell or share data with anyone

## Contact

Questions or concerns: open an issue at
https://github.com/miqqidami/touchtabs/issues.
