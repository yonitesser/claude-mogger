// a11y-browser.mjs <url> — optional axe-core pass at 375px width (phone).
// Prints check lines (LEVEL|check-id|message), same shape as scripts/checks/*.sh.
// Runs ONLY when playwright and axe-core are already resolvable from the
// project or this plugin; it never installs anything. Exit 0 always
// (a SKIP line explains why nothing ran). Report-only: navigates, reads.
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const url = process.argv[2];
const skip = (why) => { console.log('SKIP|a11y-axe|' + why); process.exit(0); };
if (!url) skip('no URL given (usage: node a11y-browser.mjs http://localhost:3000)');

function resolveFrom(name) {
  const bases = [process.cwd() + '/', import.meta.url];
  for (const b of bases) {
    try { return createRequire(b).resolve(name); } catch { /* try next base */ }
  }
  return null;
}
const pwPath = resolveFrom('playwright');
const axePath = resolveFrom('axe-core');
if (!pwPath) skip('playwright is not installed (not installing it); run axe/Lighthouse manually');
if (!axePath) skip('axe-core is not installed (not installing it); run axe/Lighthouse manually');

let browser;
try {
  const pw = await import(pathToFileURL(pwPath).href);
  const chromium = pw.chromium || (pw.default && pw.default.chromium);
  const axe = createRequire(import.meta.url)(axePath);
  browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 375, height: 812 } });
  await page.goto(url, { waitUntil: 'load', timeout: 15000 });
  await page.addScriptTag({ content: axe.source });
  const result = await page.evaluate(async () => await window.axe.run());
  const v = result.violations || [];
  if (v.length === 0) {
    console.log('PASS|a11y-axe|axe found no violations at 375px width on ' + url + ' (axe covers about a third of WCAG issues; not proof of accessibility)');
  }
  for (const item of v) {
        const first = item.nodes && item.nodes[0] ? String(item.nodes[0].target).slice(0, 80) : '';
    const msg = (item.impact || 'unknown') + ': ' + item.help + ' (' + item.nodes.length + ' node(s), first: ' + first + ') ' + item.helpUrl;
    console.log('WARN|a11y-axe-' + item.id + '|' + msg.replace(/[\r\n|]+/g, ' '));
  }
  await browser.close();
} catch (e) {
  try { if (browser) await browser.close(); } catch { /* ignore */ }
  skip('axe run could not complete: ' + String(e && e.message ? e.message : e).split('\n')[0].replace(/\|/g, '/'));
}
process.exit(0);
