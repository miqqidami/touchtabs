// TouchTabs: streams the focused window's tab strip to the TouchTabs helper
// (a native messaging host that draws it on the Touch Bar) and carries out the
// taps it sends back. Chrome starts the helper when we connect and stops it
// when we disconnect. The message format is documented in PROTOCOL.md.

const HOST = 'io.github.miqqidami.touchtabs';
const PROTOCOL_VERSION = 2;
const FAVICON_SIZE = 32;
const DEFAULT_SETTINGS = { keepControlStrip: false, alwaysShow: false };

let port = null;
let hostReady = false;
let lastError = null;
let retryDelay = 1000;
let retryTimer = null;

// ---------------------------------------------------------------------------
// Connection

function isOpen() {
  return port !== null;
}

function connect() {
  if (port) return;
  clearTimeout(retryTimer);
  const p = chrome.runtime.connectNative(HOST);
  port = p;
  hostReady = false;
  sentFavicons.clear();

  p.onMessage.addListener((message) => {
    if (message?.type === 'ready') {
      hostReady = true;
      lastError = null;
      retryDelay = 1000;
      return;
    }
    handleCommand(message);
  });
  p.onDisconnect.addListener(() => {
    lastError = chrome.runtime.lastError?.message ?? 'Disconnected';
    if (port === p) port = null;
    hostReady = false;
    // Helper not installed, or it quit: retry with backoff while we're awake;
    // the alarm below covers us after the service worker sleeps.
    retryTimer = setTimeout(connect, retryDelay);
    retryDelay = Math.min(retryDelay * 2, 30_000);
  });

  send({ type: 'hello', protocol: PROTOCOL_VERSION, browser: browserBrand(), version: chrome.runtime.getManifest().version });
  sendSettings();
  scheduleSync(true);
}

function send(message) {
  if (!port) return false;
  try {
    port.postMessage(message);
    return true;
  } catch {
    return false;
  }
}

async function sendSettings() {
  const settings = await chrome.storage.local.get(DEFAULT_SETTINGS);
  send({ type: 'settings', ...settings });
}

function browserBrand() {
  const brands = (navigator.userAgentData?.brands ?? [])
    .map((b) => b.brand)
    .filter((b) => b !== 'Chromium' && !/not.a.brand/i.test(b));
  return brands[0] ?? 'Chromium';
}

// ---------------------------------------------------------------------------
// Tab strip state

let syncTimer = null;
let syncFocused = false;

function scheduleSync(focused = false) {
  syncFocused ||= focused;
  clearTimeout(syncTimer);
  syncTimer = setTimeout(() => {
    const hint = syncFocused;
    syncFocused = false;
    sync(hint).catch((error) => console.warn('TouchTabs: sync failed', error));
  }, 25);
}

async function sync(focusedHint) {
  if (!isOpen()) return;
  let win = null;
  try {
    win = await chrome.windows.getLastFocused({ populate: true, windowTypes: ['normal'] });
  } catch {
    // No normal windows open.
  }
  if (!win) {
    send({ type: 'state', focused: false, window: null });
    return;
  }

  const groups = await chrome.tabGroups.query({ windowId: win.id });
  send({
    type: 'state',
    focused: win.focused || focusedHint,
    window: {
      id: win.id,
      incognito: win.incognito,
      tabs: win.tabs.map((tab) => ({
        id: tab.id,
        title: tab.title || tab.pendingUrl || tab.url || 'New Tab',
        url: tab.url || tab.pendingUrl || '',
        active: tab.active,
        pinned: tab.pinned,
        audible: !!tab.audible,
        muted: !!tab.mutedInfo?.muted,
        loading: tab.status === 'loading',
        groupId: tab.groupId ?? -1,
        favicon: faviconKey(tab),
      })),
      groups: groups.map((g) => ({ id: g.id, title: g.title || '', color: g.color, collapsed: g.collapsed })),
    },
  });
  for (const tab of win.tabs) pushFavicon(tab);
}

// ---------------------------------------------------------------------------
// Favicons: sent once per connection, keyed so tabs can refer to them.

const sentFavicons = new Set();
const inflightFavicons = new Set();
const faviconAttempts = new Map();
let defaultFaviconBytes = null;

function faviconKey(tab) {
  const url = tab.url || tab.pendingUrl || '';
  if (tab.favIconUrl) {
    return tab.favIconUrl.startsWith('data:') ? `data:${hash(tab.favIconUrl)}` : tab.favIconUrl;
  }
  // Browser pages (settings, history, …) have icons but no favIconUrl.
  if (/^(chrome|edge|brave|opera|vivaldi):\/\//.test(url)) return `page:${new URL(url).host}`;
  return null;
}

function faviconEndpoint(pageUrl) {
  const url = new URL(chrome.runtime.getURL('/_favicon/'));
  url.searchParams.set('pageUrl', pageUrl);
  url.searchParams.set('size', String(FAVICON_SIZE));
  return url.toString();
}

async function pushFavicon(tab) {
  const key = faviconKey(tab);
  if (!key || sentFavicons.has(key) || inflightFavicons.has(key)) return;
  inflightFavicons.add(key);
  try {
    let dataUrl;
    if (tab.favIconUrl?.startsWith('data:')) {
      dataUrl = tab.favIconUrl;
    } else {
      const response = await fetch(faviconEndpoint(tab.url || tab.pendingUrl));
      const bytes = new Uint8Array(await response.arrayBuffer());
      // Right after a page loads, Chrome's favicon cache may not have the icon
      // yet and hands back its generic globe. Don't cache that; try again.
      if (await isDefaultFavicon(bytes)) {
        const attempts = (faviconAttempts.get(key) ?? 0) + 1;
        faviconAttempts.set(key, attempts);
        if (attempts < 5) setTimeout(() => pushFavicon(tab), 1000 * 2 ** attempts);
        return;
      }
      dataUrl = `data:${response.headers.get('content-type') || 'image/png'};base64,${base64(bytes)}`;
    }
    if (send({ type: 'favicon', key, data: dataUrl })) sentFavicons.add(key);
  } catch (error) {
    console.warn('TouchTabs: favicon failed', key, error);
  } finally {
    inflightFavicons.delete(key);
  }
}

async function isDefaultFavicon(bytes) {
  if (!defaultFaviconBytes) {
    const response = await fetch(faviconEndpoint('https://touchtabs.invalid/'));
    defaultFaviconBytes = new Uint8Array(await response.arrayBuffer());
  }
  return bytes.length === defaultFaviconBytes.length && bytes.every((b, i) => b === defaultFaviconBytes[i]);
}

function base64(bytes) {
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

function hash(text) {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(36);
}

// ---------------------------------------------------------------------------
// Commands from the Touch Bar

async function handleCommand(message) {
  try {
    switch (message.type) {
      case 'activate':
        await chrome.tabs.update(message.tabId, { active: true });
        break;
      case 'close':
        await chrome.tabs.remove(message.tabId);
        break;
      case 'newTab': {
        const win = await chrome.windows.getLastFocused({ windowTypes: ['normal'] });
        await chrome.tabs.create({ windowId: win.id });
        break;
      }
      case 'toggleGroup': {
        const group = await chrome.tabGroups.get(message.groupId);
        await chrome.tabGroups.update(group.id, { collapsed: !group.collapsed });
        break;
      }
      case 'sync':
        scheduleSync();
        break;
    }
  } catch (error) {
    console.warn('TouchTabs: command failed', message, error);
    scheduleSync(); // resync so the Touch Bar drops any optimistic change
  }
}

// ---------------------------------------------------------------------------
// Browser events

const syncOnly = () => scheduleSync();
chrome.tabs.onCreated.addListener(syncOnly);
chrome.tabs.onRemoved.addListener(syncOnly);
chrome.tabs.onMoved.addListener(syncOnly);
chrome.tabs.onActivated.addListener(syncOnly);
chrome.tabs.onAttached.addListener(syncOnly);
chrome.tabs.onDetached.addListener(syncOnly);
chrome.tabs.onReplaced.addListener(syncOnly);
chrome.tabs.onUpdated.addListener((_id, change) => {
  if (['title', 'favIconUrl', 'status', 'audible', 'mutedInfo', 'pinned', 'groupId', 'url'].some((k) => k in change)) {
    scheduleSync();
  }
});
chrome.tabGroups.onCreated.addListener(syncOnly);
chrome.tabGroups.onUpdated.addListener(syncOnly);
chrome.tabGroups.onRemoved.addListener(syncOnly);
chrome.tabGroups.onMoved.addListener(syncOnly);
chrome.windows.onRemoved.addListener(syncOnly);
chrome.windows.onFocusChanged.addListener((windowId) => {
  if (windowId !== chrome.windows.WINDOW_ID_NONE) scheduleSync(true);
});

chrome.storage.onChanged.addListener((_changes, area) => {
  if (area === 'local') sendSettings();
});

// Popup status.
chrome.runtime.onMessage.addListener((message, _sender, reply) => {
  if (message?.type === 'status') {
    if (!isOpen()) connect();
    reply({ connected: hostReady, error: hostReady ? null : lastError });
  }
});

// Wake up periodically to reconnect if the helper was installed after the browser started.
chrome.alarms.create('reconnect', { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'reconnect') connect();
});
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
connect();
