// media-src/curseforge/render-logo.js - renders the two CurseForge logo variants of
// logo.html (A: brand violet, B: neon night) to logo-A.png and logo-B.png, 400 x 400 px,
// with the bundled OFL fonts (Orbitron). Needs Node.js and Playwright with Chromium:
//   NODE_PATH=$(npm root -g) node media-src/curseforge/render-logo.js
const path = require('path');
const { chromium } = require('playwright');

(async () => {
  const dir = __dirname;
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 400, height: 800 }, deviceScaleFactor: 1 });
  await page.goto('file://' + path.join(dir, 'logo.html'));
  await page.evaluate(() => document.fonts.ready);
  for (const id of ['A', 'B']) {
    await page.locator('#' + id).screenshot({ path: path.join(dir, 'logo-' + id + '.png') });
  }
  await browser.close();
})();
