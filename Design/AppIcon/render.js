// Renders ./svg/dialed-icon-*.svg to 1024px PNGs (and a preview sheet).
//   NODE_PATH=$(npm root -g) node render.js <outDir>
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
(async () => {
  const out = process.argv[2] || path.join(__dirname, 'png');
  fs.mkdirSync(out, { recursive: true });
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1024, height: 1024 } });
  for (const name of ['light', 'dark', 'tinted']) {
    const svg = fs.readFileSync(path.join(__dirname, 'svg', `dialed-icon-${name}.svg`), 'utf8');
    await p.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
    await p.screenshot({ path: path.join(out, `AppIcon-${name}.png`), clip: { x: 0, y: 0, width: 1024, height: 1024 }, omitBackground: name === 'tinted' ? false : false });
  }
  await b.close();
})();
