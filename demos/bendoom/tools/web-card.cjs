// Writes og.png into the site: the 1200 by 630 link preview, which is
// the page itself at the E1M1 spawn, rearranged into a card.
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_DRIVER || 'playwright-core');

const card = `
  body { display: grid; grid-template: 1fr auto auto 1fr / 1fr auto; gap: 0 40px; height: 630px; padding: 48px; }
  main { display: contents; }
  header { grid-area: 2 / 1; flex-direction: column; align-items: start; margin: 0 0 28px; }
  h1 { --scale: 7; }
  header p { font-size: 22px; text-align: left; }
  header a, #sound, #keys, .level > :last-child, footer { display: none; }
  .level { grid-area: 3 / 1; margin: 0; }
  #screen { grid-area: 1 / 2 / 5; width: 640px; align-self: center; }
`;

async function main() {
  const root = path.resolve(process.argv[2]);
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || '/usr/bin/chromium',
    headless: true, args: ['--no-sandbox', '--mute-audio', '--disable-dev-shm-usage'] });
  try {
    const page = await browser.newPage({ viewport: { width: 1200, height: 630 } });
    await page.route('http://localhost/**', route => route.fulfill({
      path: path.join(root, new URL(route.request().url()).pathname.replace(/\/$/, '/index.html')),
      headers: { 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' }
    }));
    await page.goto('http://localhost/');
    await page.waitForFunction(() => !document.getElementById('play').disabled, null, { timeout: 120000 });
    await page.keyboard.press('Enter');
    await page.waitForFunction(() => document.getElementById('wipe').hidden);
    await page.waitForTimeout(1000);
    await page.addStyleTag({ content: card });
    await page.screenshot({ path: path.join(root, 'og.png') });
  } finally {
    await browser.close();
  }
}

main().catch(error => { console.error(error); process.exit(1); });
