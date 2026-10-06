// Drives the website's account pages in real (headless) Chrome over the
// DevTools protocol. Node 22's built-in WebSocket and fetch, no packages.
// Called by tool/email/email_flow.dart, which owns the server side.
//
//   node tool/email/page_flow.mjs reset <url with ?s=> <new password>
//   node tool/email/page_flow.mjs verify-open <url with ?s=>
//   node tool/email/page_flow.mjs verify-confirm <url with ?s=>
//   node tool/email/page_flow.mjs missing <page url without ?s=>
//
// Prints ok/FAIL lines like the other checks and exits non-zero on any
// FAIL. Every mode also fails on a Content-Security-Policy violation: the
// page is served with production's policy (site_server.py).
import { spawn } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [mode, url, newPassword] = process.argv.slice(2);
const chromePath = process.env.CHROME ??
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
let failures = 0;
const check = (what, ok, detail = '') => {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}${ok ? '' : `: ${detail}`}`);
  if (!ok) failures++;
};

const chrome = spawn(chromePath, [
  '--headless=new', '--remote-debugging-port=0', '--no-first-run',
  '--no-default-browser-check', `--user-data-dir=${mkdtempSync(join(tmpdir(), 'rubric-page-'))}`,
  'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });

const port = await new Promise((resolve, reject) => {
  let err = '';
  chrome.stderr.on('data', (d) => {
    err += d;
    const m = err.match(/DevTools listening on ws:\/\/[^:]+:(\d+)\//);
    if (m) resolve(m[1]);
  });
  chrome.on('exit', () => reject(new Error(`Chrome exited: ${err}`)));
});
const [page] = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json())
  .filter((t) => t.type === 'page');
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r, { once: true }));

let nextId = 0;
const pending = new Map();
const listeners = [];
ws.addEventListener('message', (e) => {
  const msg = JSON.parse(e.data);
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
  } else if (msg.method) {
    for (const l of listeners) l(msg);
  }
});
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const id = ++nextId;
  pending.set(id, { resolve, reject });
  ws.send(JSON.stringify({ id, method, params }));
});
const evaluate = async (expression) => {
  const { result, exceptionDetails } = await send('Runtime.evaluate', {
    expression, awaitPromise: true, returnByValue: true,
  });
  if (exceptionDetails) throw new Error(exceptionDetails.text);
  return result.value;
};
const waitFor = async (expression, ms = 8000) => {
  for (const end = Date.now() + ms; Date.now() < end;) {
    if (await evaluate(expression)) return true;
    await new Promise((r) => setTimeout(r, 100));
  }
  return false;
};
const visible = (state) =>
  `!document.querySelector('[data-state="${state}"]').hidden`;

// Collect CSP violations and page errors from the first byte on.
await send('Page.enable');
await send('Runtime.enable');
await send('Page.addScriptToEvaluateOnNewDocument', {
  source: `window.__violations = [];
    addEventListener('securitypolicyviolation', (e) =>
      __violations.push(e.violatedDirective + ' ' + e.blockedURI));`,
});
const errors = [];
listeners.push((m) => {
  if (m.method === 'Runtime.exceptionThrown') {
    errors.push(m.params.exceptionDetails.exception?.description ?? m.params.exceptionDetails.text);
  }
});

const open = async (target) => {
  const loaded = new Promise((r) => listeners.push((m) => m.method === 'Page.loadEventFired' && r()));
  await send('Page.navigate', { url: target });
  await loaded;
};
const fill = (name, value) => evaluate(`(() => {
  const input = document.querySelector('input[name="${name}"]');
  input.value = ${JSON.stringify(value)};
  input.dispatchEvent(new Event('input', { bubbles: true }));
})()`);

try {
  await open(url);
  if (mode === 'reset') {
    check('the reset page shows its form', await waitFor(visible('form')));
    check('the token leaves the address bar', await evaluate('location.search === ""'),
      await evaluate('location.href'));
    await fill('password', newPassword);
    await fill('confirm', `${newPassword}-typo`);
    await evaluate(`document.querySelector('[type="submit"]').click()`);
    check('mismatched passwords are caught on the page',
      await waitFor(`!document.querySelector('[data-error]').hidden`));
    await fill('confirm', newPassword);
    await evaluate(`document.querySelector('[type="submit"]').click()`);
    check('saving shows "Password changed"', await waitFor(visible('done')),
      await evaluate(`[...document.querySelectorAll('[data-state]')].filter(s => !s.hidden).map(s => s.dataset.state)`));
  } else if (mode === 'verify-open') {
    check('the verify page waits for a tap', await waitFor(visible('form')));
    await new Promise((r) => setTimeout(r, 1000)); // anything sent on load would land now
  } else if (mode === 'verify-confirm') {
    await waitFor(visible('form'));
    await evaluate(`document.querySelector('[data-confirm]').click()`);
    check('confirming shows "Email confirmed"', await waitFor(visible('done')));
  } else if (mode === 'missing') {
    check('a link without its token says so', await waitFor(visible('missing')));
  } else {
    throw new Error(`unknown mode ${mode}`);
  }
  const violations = await evaluate('window.__violations');
  check('no Content-Security-Policy violations', violations.length === 0, violations.join('; '));
  check('no script errors', errors.length === 0, errors.join('; '));
} catch (e) {
  check(`page flow (${mode})`, false, e.message);
} finally {
  ws.close();
  chrome.kill();
}
process.exit(failures === 0 ? 0 : 1);
