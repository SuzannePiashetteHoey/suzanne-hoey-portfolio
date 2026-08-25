'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const [siteTarget, debugTarget, screenshotDir] = process.argv.slice(2);
const debugPort = Number(debugTarget);
assert.ok(siteTarget && debugPort, 'Usage: node tests/browser-acceptance.js SITE_PORT_OR_URL DEBUG_PORT [SCREENSHOT_DIR]');
const base = /^https?:\/\//.test(siteTarget) ? siteTarget.replace(/\/$/, '') : 'http://127.0.0.1:' + Number(siteTarget);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function findTarget() {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    try {
      const targets = await fetch('http://127.0.0.1:' + debugPort + '/json').then(r => r.json());
      const target = targets.find(item => item.type === 'page');
      if (target) return target;
    } catch {}
    await sleep(100);
  }
  throw new Error('Browser debugging target was unavailable');
}

class Cdp {
  constructor(url) { this.id = 0; this.pending = new Map(); this.events = []; this.ws = new WebSocket(url); }
  async open() {
    await new Promise((resolve, reject) => { this.ws.onopen = resolve; this.ws.onerror = reject; });
    this.ws.onmessage = event => {
      const message = JSON.parse(event.data);
      if (message.id) {
        const waiter = this.pending.get(message.id);
        if (!waiter) return;
        this.pending.delete(message.id);
        return message.error ? waiter.reject(new Error(message.error.message)) : waiter.resolve(message.result);
      }
      this.events.push(message);
    };
  }
  send(method, params = {}) {
    const id = ++this.id;
    return new Promise((resolve, reject) => { this.pending.set(id, { resolve, reject }); this.ws.send(JSON.stringify({ id, method, params })); });
  }
  close() { this.ws.close(); }
}

async function evaluate(cdp, expression) {
  const result = await cdp.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.text);
  return result.result.value;
}

function pageChecks() {
  const hrefs = Array.from(document.querySelectorAll('a')).map(a => a.getAttribute('href'));
  const links = Array.from(document.querySelectorAll('nav a'));
  links[0].focus();
  const focus = getComputedStyle(links[0]);
  return {
    title: document.title,
    language: document.documentElement.lang,
    hasMain: !!document.querySelector('main#content'),
    hasNav: !!document.querySelector('nav[aria-label="Primary navigation"]'),
    hasSkip: !!document.querySelector('.skip-link[href="#content"]'),
    sections: ['work', 'capabilities', 'approach', 'contact'].every(id => !!document.getElementById(id)),
    headings: document.querySelectorAll('h1').length,
    approvedMailto: hrefs.filter(h => h && h.startsWith('mailto:')).every(h => h === 'mailto:business@suzannehoey.com') && hrefs.filter(h => h === 'mailto:business@suzannehoey.com').length === 1,
    pdfLinked: hrefs.some(h => h && h.endsWith('.pdf')),
    noHorizontalOverflow: document.documentElement.scrollWidth <= window.innerWidth + 1,
    focusVisible: focus.outlineStyle !== 'none' && focus.outlineWidth !== '0px',
    structuredData: !!document.querySelector('script[type="application/ld+json"]'),
    description: !!document.querySelector('meta[name="description"]'),
    productionMetadata: document.querySelector('link[rel="canonical"]')?.href === 'https://suzannehoey.com/' && document.querySelector('meta[property="og:url"]')?.content === 'https://suzannehoey.com/' && document.querySelector('meta[property="og:image"]')?.content === 'https://suzannehoey.com/assets/portfolio-desktop.png' && document.querySelector('meta[name="twitter:image"]')?.content === 'https://suzannehoey.com/assets/portfolio-desktop.png',
    safeContact: document.getElementById('contact').textContent.includes('business@suzannehoey.com')
  };
}

async function testViewport(cdp, viewport) {
  await cdp.send('Emulation.setDeviceMetricsOverride', { width: viewport.width, height: viewport.height, deviceScaleFactor: 1, mobile: viewport.mobile });
  await cdp.send('Page.navigate', { url: base + '/' });
  await sleep(500);
  const result = await evaluate(cdp, '(' + pageChecks.toString() + ')()');
  assert.match(result.title, /Suzanne Hoey/);
  assert.equal(result.language, 'en');
  assert.ok(result.hasMain && result.hasNav && result.hasSkip && result.sections);
  assert.equal(result.headings, 1);
  assert.ok(result.approvedMailto);
  assert.equal(result.pdfLinked, false);
  assert.ok(result.noHorizontalOverflow);
  assert.ok(result.focusVisible);
  assert.ok(result.structuredData && result.description && result.productionMetadata && result.safeContact);
  if (screenshotDir) {
    fs.mkdirSync(screenshotDir, { recursive: true });
    const dimensions = await evaluate(cdp, '({width:document.documentElement.scrollWidth,height:document.documentElement.scrollHeight})');
    const capture = await cdp.send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, clip: { x: 0, y: 0, width: dimensions.width, height: dimensions.height, scale: 1 } });
    fs.writeFileSync(path.join(screenshotDir, 'portfolio-' + viewport.name + '.png'), Buffer.from(capture.data, 'base64'));
  }
  console.log(viewport.name + ' viewport: PASS');
}

async function run() {
  const target = await findTarget();
  const cdp = new Cdp(target.webSocketDebuggerUrl);
  await cdp.open();
  try {
    await Promise.all([cdp.send('Page.enable'), cdp.send('Runtime.enable'), cdp.send('Network.enable'), cdp.send('Log.enable')]);
    for (const viewport of [
      { name: 'desktop', width: 1440, height: 1000, mobile: false },
      { name: 'tablet', width: 768, height: 1024, mobile: true },
      { name: 'mobile', width: 390, height: 844, mobile: true }
    ]) await testViewport(cdp, viewport);
    const assetExpression = '(async()=>Promise.all(' + JSON.stringify(['styles.css', 'favicon.svg', 'robots.txt', 'sitemap.xml', 'assets/portfolio-desktop.png', 'assets/portfolio-mobile.png']) + '.map(name=>fetch(' + JSON.stringify(base + '/') + '+name).then(r=>({ok:r.ok,status:r.status})))))()';
    const assets = await evaluate(cdp, assetExpression);
    assert.ok(assets.every(asset => asset.ok && asset.status === 200));
    const origins = await evaluate(cdp, "performance.getEntriesByType('resource').map(entry=>new URL(entry.name).origin)");
    assert.ok(origins.every(origin => origin === base));
    await sleep(150);
    const errors = cdp.events.filter(event => event.method === 'Runtime.exceptionThrown' || event.method === 'Network.loadingFailed' || (event.method === 'Log.entryAdded' && event.params.entry.level === 'error'));
    assert.deepEqual(errors, []);
    console.log('assets, console, network, and external-request checks: PASS');
  } finally { cdp.close(); }
}

run().catch(error => { console.error(error); process.exitCode = 1; });
