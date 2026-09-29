const DEFAULT_SETTINGS = { enabled: true, keepControlStrip: false, alwaysShow: false };

const status = document.getElementById('status');
const label = document.getElementById('label');
const help = document.getElementById('help');

function render({ connected, error }) {
  status.className = `status ${connected ? 'ok' : 'off'}`;
  if (connected) {
    label.textContent = 'Showing tabs on the Touch Bar';
  } else if (/not found/i.test(error ?? '')) {
    label.textContent = 'TouchTabs helper not installed';
  } else {
    label.textContent = 'Connecting to the Touch Bar…';
  }
  help.hidden = connected;
}

async function check() {
  try {
    render(await chrome.runtime.sendMessage({ type: 'status' }));
  } catch {
    render({ connected: false });
  }
}

async function setUpSettings() {
  const settings = await chrome.storage.local.get(DEFAULT_SETTINGS);
  for (const key of Object.keys(DEFAULT_SETTINGS)) {
    const box = document.getElementById(key);
    box.checked = settings[key];
    box.addEventListener('change', () => chrome.storage.local.set({ [key]: box.checked }));
  }
}

setUpSettings();
check();
setInterval(check, 1000);
