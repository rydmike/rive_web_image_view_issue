// Opens one build in headless Chrome, waits for the Rive file to load and the image to decode, then records the
// console, the requests and a screenshot, and counts the checker's orange and teal pixels in each half of the
// page. The artboard is centred, so its left square lands in the left half and its right square in the right.
//
//   node tool/capture.mjs <url> <output.json>
import puppeteer from 'puppeteer-core';
import fs from 'node:fs/promises';

const url = process.argv[2] ?? 'http://127.0.0.1:8123';
const output = process.argv[3] ?? 'capture.json';
// Long enough for the browser image decode and Rive's watermark splash on a free plan file.
const SETTLE_MS = 6000;
if (!process.env.CHROME_PATH) throw new Error('Set CHROME_PATH to the Chrome executable');
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH,
  headless: true,
  args: ['--enable-unsafe-swiftshader', '--no-first-run', '--no-default-browser-check'],
});
const record = {capturedAt: new Date().toISOString(), url, browser: await browser.version(), console: [],
                pageErrors: [], requests: []};
try {
  const page = await browser.newPage();
  await page.setViewport({width: 1000, height: 700, deviceScaleFactor: 1});
  let loaded;
  const ready = new Promise(resolve => { loaded = resolve; });
  page.on('console', message => {
    const entry = {type: message.type(), text: message.text()};
    record.console.push(entry);
    console.log(`[${entry.type}] ${entry.text}`);
    if (entry.text.includes('[repro] loaded') || entry.text.includes('[repro] failed')) loaded();
  });
  page.on('pageerror', error => {
    record.pageErrors.push(String(error));
    console.log(`[pageerror] ${error}`);
  });
  page.on('request', request => record.requests.push(request.url()));
  await page.goto(url, {waitUntil: 'domcontentloaded', timeout: 60000});
  let timeout;
  await Promise.race([ready, new Promise((_, reject) => {
    timeout = setTimeout(() => reject(new Error('The file did not load within 60 s')), 60000);
  })]);
  clearTimeout(timeout);
  await new Promise(resolve => setTimeout(resolve, SETTLE_MS));
  const png = await page.screenshot({encoding: 'base64'});
  await fs.writeFile(output.replace(/\.json$/, '.png'), Buffer.from(png, 'base64'));
  record.checker = await page.evaluate(async data => {
    const image = new Image();
    image.src = 'data:image/png;base64,' + data;
    await image.decode();
    const canvas = document.createElement('canvas');
    canvas.width = image.width;
    canvas.height = image.height;
    const context = canvas.getContext('2d');
    context.drawImage(image, 0, 0);
    const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
    const near = (i, r, g, b) => Math.abs(pixels[i] - r) < 24 && Math.abs(pixels[i + 1] - g) < 24 &&
        Math.abs(pixels[i + 2] - b) < 24;
    const counts = {left: 0, right: 0};
    for (let y = 0; y < canvas.height; y++) {
      for (let x = 0; x < canvas.width; x++) {
        const i = (y * canvas.width + x) * 4;
        if (near(i, 255, 122, 26) || near(i, 26, 176, 200)) counts[x < canvas.width / 2 ? 'left' : 'right']++;
      }
    }
    return counts;
  }, png);
  record.rightSquareDrawn = record.checker.right > record.checker.left * 0.5;
  record.oreSkips = record.console.filter(e => e.text.includes('rive ore replay')).length;
  record.complete = true;
  console.log(`[capture] checker pixels left=${record.checker.left} right=${record.checker.right} ` +
              `rightSquareDrawn=${record.rightSquareDrawn} oreReplayMessages=${record.oreSkips}`);
} catch (error) {
  record.error = String(error);
  process.exitCode = 1;
} finally {
  await fs.writeFile(output, JSON.stringify(record, null, 2) + '\n');
  await browser.close();
}
