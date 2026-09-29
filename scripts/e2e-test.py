#!/usr/bin/env python3
"""End-to-end check: loads the extension into a throwaway headless Chrome
profile, registers build/TouchTabs.app as that profile's native messaging
host, opens a few sites, drives the extension's command handler and
screenshots the Touch Bar. Run `make app` first.
"""
import fcntl, json, os, subprocess, sys, time, tempfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TMP = tempfile.mkdtemp(prefix='touchtabs-e2e-')
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

def high(fd):
    n = os.dup(fd) if fd >= 10 else fcntl.fcntl(fd, fcntl.F_DUPFD, 10)
    os.close(fd); return n
r1, w1 = map(high, os.pipe())  # we write -> chrome reads fd3
r2, w2 = map(high, os.pipe())  # chrome writes fd4 -> we read
for fd in (r1, w1, r2, w2): os.set_inheritable(fd, True)
profile = tempfile.mkdtemp(dir=TMP)
subprocess.run([ROOT + '/build/TouchTabs.app/Contents/MacOS/TouchTabs', '--install', '--user-data-dir', profile], check=True)
def child():
    os.dup2(r1, 3); os.dup2(w2, 4); os.close(w1); os.close(r2)
proc = subprocess.Popen([CHROME, '--headless=new', f'--user-data-dir={profile}', '--remote-debugging-pipe',
    '--enable-unsafe-extension-debugging', '--no-first-run', '--no-default-browser-check', 'about:blank'],
    preexec_fn=child, close_fds=False, stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
os.close(r1); os.close(w2)
out = os.fdopen(w1, 'wb'); inp = os.fdopen(r2, 'rb')
buf = b''; msg_id = 0
def cdp(method, params=None, session=None):
    global buf, msg_id
    msg_id += 1
    m = {'id': msg_id, 'method': method, 'params': params or {}}
    if session: m['sessionId'] = session
    out.write(json.dumps(m).encode() + b'\0'); out.flush()
    while True:
        while b'\0' not in buf:
            chunk = os.read(inp.fileno(), 65536)
            if not chunk: raise SystemExit(f'chrome closed rc={proc.poll()}')
            buf += chunk
        raw, buf = buf.split(b'\0', 1)
        r = json.loads(raw)
        if r.get('id') == msg_id:
            if 'error' in r: raise RuntimeError(f'{method}: {r["error"]}')
            return r['result']

try:
    ext = cdp('Extensions.loadUnpacked', {'path': ROOT + '/extension'})['id']
    print('extension id', ext)
    for url in ['https://github.com', 'https://en.wikipedia.org/wiki/Touch_Bar', 'https://www.apple.com', 'https://news.ycombinator.com']:
        cdp('Target.createTarget', {'url': url})
    time.sleep(6)
    sw = next(t for t in cdp('Target.getTargets')['targetInfos'] if t['type'] == 'service_worker' and ext in t['url'])
    sess = cdp('Target.attachToTarget', {'targetId': sw['targetId'], 'flatten': True})['sessionId']
    def ev(expr):
        r = cdp('Runtime.evaluate', {'expression': expr, 'awaitPromise': True, 'returnByValue': True}, sess)
        return r['result'].get('value', r)
    ev('chrome.storage.local.set({alwaysShow: true})')  # headless Chrome is never frontmost
    time.sleep(1)
    print('helper ready:', ev('hostReady'))
    tabs = ev('chrome.tabs.query({}).then(ts => ts.map(t => ({id: t.id, title: t.title, active: t.active, fav: !!t.favIconUrl})))')
    print('tabs:', json.dumps(tabs))
    ids = [t['id'] for t in tabs]
    ev(f'chrome.tabs.group({{tabIds: {ids[1:3]}}}).then(g => chrome.tabGroups.update(g, {{title: "Docs", color: "blue"}}))')
    ev(f'chrome.tabs.update({ids[0]}, {{pinned: true}})')
    ev(f'handleCommand({{type: "activate", tabId: {ids[3]}}})')
    time.sleep(2)
    print('active after activate cmd:', ev('chrome.tabs.query({active: true}).then(t => t[0].title)'))
    print('sent favicons:', ev('[...sentFavicons]'))
    subprocess.run(['screencapture', '-b', TMP + '/e2e1.png'])
    ev(f'handleCommand({{type: "close", tabId: {ids[3]}}})')
    ev('handleCommand({type: "newTab"})')
    time.sleep(1.5)
    print('tabs after close+new:', ev('chrome.tabs.query({}).then(ts => ts.map(t => t.title))'))
    subprocess.run(['screencapture', '-b', TMP + '/e2e2.png'])
finally:
    proc.terminate(); proc.wait(10)
    print('Touch Bar screenshots:', TMP + '/e2e1.png', TMP + '/e2e2.png')
