# Extension ↔ helper protocol

The extension talks to the helper over Chrome
[native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging).
It calls `chrome.runtime.connectNative("io.github.miqqidami.touchtabs")`. Chrome
starts the helper and exchanges messages with it over its stdin/stdout. Each
message is a 32-bit little-endian length followed by that many bytes of UTF-8
JSON. When the port closes, Chrome closes the pipes, and the helper exits on EOF
or SIGTERM.

The host manifest that `TouchTabs --install` writes to
`~/Library/Application Support/<browser>/NativeMessagingHosts/io.github.miqqidami.touchtabs.json`
lists the only extension origins allowed to start the helper.

Every message has a `type` field. Unknown types are ignored, so either side can
be extended without breaking the other.

## Extension → helper

| type | fields | when |
| --- | --- | --- |
| `hello` | `protocol` (2), `browser` (brand from `navigator.userAgentData`, e.g. `"Google Chrome"`, `"Brave"`), `version` | right after connecting |
| `settings` | `enabled` (bool, the toolbar button), `keepControlStrip` (bool), `alwaysShow` (bool) | after connecting and whenever they change |
| `state` | `focused` (bool), `window` (object or `null`) | whenever the last-focused normal window's tab strip changes (debounced ~25 ms) |
| `favicon` | `key`, `data` (`data:` URL) | once per favicon per connection |

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

`focused` is true when the window has OS focus. `favicon` is a key into the
favicons sent with `favicon` messages, or `null` for no icon.

## Helper → extension

| type | fields | effect |
| --- | --- | --- |
| `ready` | `version` | the helper started; the popup shows "connected" |
| `activate` | `tabId` | `chrome.tabs.update(tabId, {active: true})` |
| `close` | `tabId` | `chrome.tabs.remove(tabId)` |
| `newTab` | – | new tab in the last-focused window |
| `toggleGroup` | `groupId` | collapse / expand the group |
| `sync` | – | resend `state` |

## Several helpers

Each browser profile (and each browser) starts its own helper. When a helper's
window gains focus, it posts the distributed notification
`io.github.miqqidami.touchtabs.focused` with its PID, and the other helpers hide.
When a helper exits, it posts `io.github.miqqidami.touchtabs.released`.
