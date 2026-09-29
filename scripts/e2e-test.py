#!/usr/bin/env python3
"""End-to-end check: loads the extension into a throwaway headless Chrome
profile, opens a few sites, drives the extension's command handler and
screenshots the Touch Bar. Start TouchTabs.app first, with
`defaults write io.github.miqqidami.touchtabs AlwaysShow -bool true` so the
strip shows while Chrome runs headless.
"""
import fcntl, json, os, subprocess, sys, time, socket, tempfile
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

def origin_test(origin):
    s = socket.create_connection(('127.0.0.1', 47823))
    s.send((f'GET / HTTP/1.1\r\nHost: 127.0.0.1:47823\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
            f'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nOrigin: {origin}\r\n\r\n').encode())
    s.settimeout(2)
    try: resp = s.recv(200).decode(errors='replace').split('\r\n')[0]
    except Exception as e: resp = f'<{e}>'
    s.close(); return resp

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
    print('connected:', ev('isOpen()'))
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
    print('origin evil:', origin_test('https://evil.example'))
    print('origin other ext:', origin_test('chrome-extension://aaaabbbbccccddddeeeeffffgggghhhh'))
finally:
    proc.terminate(); proc.wait(10)
    print('Touch Bar screenshots:', TMP + '/e2e1.png', TMP + '/e2e2.png')
