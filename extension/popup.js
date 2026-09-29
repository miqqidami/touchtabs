const status = document.getElementById('status');
const label = document.getElementById('label');
const help = document.getElementById('help');

function render(connected) {
  status.className = `status ${connected ? 'ok' : 'off'}`;
  label.textContent = connected ? 'Connected to the Touch Bar' : 'TouchTabs app not running';
  help.hidden = connected;
}

async function check() {
  try {
    const { connected } = await chrome.runtime.sendMessage({ type: 'status' });
    render(connected);
  } catch {
    render(false);
  }
}

check();
setInterval(check, 1000);
