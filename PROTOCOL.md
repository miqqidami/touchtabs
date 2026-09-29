# Extension ↔ app protocol

The macOS app listens on `ws://127.0.0.1:47823` (loopback only). The browser
extension connects to it from its service worker. The app accepts the WebSocket
handshake only when the `Origin` header is `chrome-extension://<id>` for an
allowed extension ID (see [README](README.md#configuration)).

Every message is one JSON text frame with a `type` field. Unknown types are
ignored, so either side can be extended without breaking the other.

## Extension → app

| type | fields | when |
| --- | --- | --- |
| `hello` | `protocol` (1), `browser` (brand from `navigator.userAgentData`, e.g. `"Google Chrome"`, `"Brave"`), `version` | right after connecting |
| `state` | `focused` (bool), `window` (object or `null`) | whenever the last-focused normal window's tab strip changes (debounced ~25 ms) |
| `favicon` | `key`, `data` (`data:` URL) | once per favicon per connection |
| `ping` | – | every 20 s, keeps the MV3 service worker alive |

`window`:

```json
{
  "id": 1,
  "incognito": false,
  "tabs": [
    {
      "id": 42, "title": "Hacker News", "url": "https://news.ycombinator.com/",
      "active": true, "pinned": false, "audible": false, "muted": false,
      "loading": false, "groupId": -1, "favicon": "https://news.ycombinator.com/y18.svg"
    }
  ],
  "groups": [{ "id": 7, "title": "Docs", "color": "blue", "collapsed": false }]
}
```

`focused` is true when the window has OS focus. With several browsers or
profiles connected, the app shows the one focused most recently. `favicon` is a
key into the favicons sent with `favicon` messages, or `null` for no icon.

## App → extension

| type | fields | effect |
| --- | --- | --- |
| `activate` | `tabId` | `chrome.tabs.update(tabId, {active: true})` |
| `close` | `tabId` | `chrome.tabs.remove(tabId)` |
| `newTab` | – | new tab in the last-focused window |
| `toggleGroup` | `groupId` | collapse / expand the group |
| `sync` | – | resend `state` |
