// smoke-browser.mjs <url> <png-path> — optional Playwright pass for smoke-check.sh.
// Prints one line per console error / page error, then "SHOT <path>".
// Exit 3 = playwright not installed (caller treats as "skipped", not failure).
// Report-only: navigates and screenshots, nothing else.
const [url, out] = process.argv.slice(2);
let pw;
try { pw = await import('playwright'); } catch { process.exit(3); }
try {
  const browser = await pw.chromium.launch();
  const page = await browser.newPage();
  page.on('console', (m) => { if (m.type() === 'error') console.log('console: ' + m.text()); });
  page.on('pageerror', (e) => console.log('pageerror: ' + e.message));
  await page.goto(url, { waitUntil: 'load', timeout: 15000 });
  await page.screenshot({ path: out });
  await browser.close();
  console.log('SHOT ' + out);
} catch (e) { console.error(String(e)); process.exit(4); }
