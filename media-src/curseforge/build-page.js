// media-src/curseforge/build-page.js - the CurseForge page images (page/*.png): real renders
// of the addon (scene.lua -> render-scene.js) composed on the brand background.
//   NODE_PATH=$(npm root -g) node media-src/curseforge/build-page.js [hero|themes|detail|stats|compact ...]
// Needs lua (5.1+) on the PATH, Node.js and Playwright's Chromium. Intermediate files go to a
// temporary directory (removed at the end; --keep keeps it and prints its path).
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFile } = require('child_process');
const R = require('./render-scene');

const DIR = __dirname;
const REPO = path.resolve(DIR, '..', '..');
const OUT = path.join(DIR, 'page');
const WIDTH = 1600;
const SS = 2;                       // supersampling: UI rendered at 2x its displayed size

const THEMES = [
  ['futuriste', 'Futuristic'], ['actuel', 'Classic'], ['heroic', 'Heroic fantasy'],
  ['pixel', 'Pixel'], ['warrior', 'Warrior'], ['paladin', 'Paladin'], ['hunter', 'Hunter'],
  ['rogue', 'Rogue'], ['priest', 'Priest'], ['shaman', 'Shaman'], ['mage', 'Mage'],
  ['warlock', 'Warlock'], ['druid', 'Druid'],
];

const args = process.argv.slice(2);
const keep = args.includes('--keep');
const wanted = args.filter((a) => !a.startsWith('--'));
const want = (n) => wanted.length === 0 || wanted.includes(n);
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'tp-page-'));

// ---------------------------------------------------------------------------
// Scenes
// ---------------------------------------------------------------------------
function scene(scenario, theme) {
  const out = path.join(TMP, `${scenario}-${theme}.json`);
  return new Promise((resolve, reject) => {
    execFile('lua', [path.join('media-src', 'curseforge', 'scene.lua'), scenario, theme, out],
      { cwd: REPO, env: Object.assign({}, process.env, { TZ: 'UTC' }) }, (err, _o, stderr) => {
        if (err) return reject(new Error(`scene ${scenario} ${theme}: ${stderr || err.message}`));
        if (/addon error/.test(stderr)) process.stderr.write(stderr);
        resolve(JSON.parse(fs.readFileSync(out, 'utf8')));
      });
  });
}

// Renders a scene at `zoom` CSS px per UI unit (x SS device px): { src, w, h, map(x, y) }.
async function shot(browser, sc, zoom, name, opts = {}) {
  const pad = opts.pad === undefined ? 4 : opts.pad;
  const file = path.join(TMP, name + '.png');
  const r = await R.renderScene(browser, sc, file, { scale: zoom * SS, pad, bg: 'transparent', region: opts.region });
  const reg = r.region;
  return {
    src: 'file://' + file, w: r.width / SS, h: r.height / SS,
    // UI point (top-left coordinates) -> CSS px inside the image
    map: (x, y) => [(x - reg[0] + pad) * zoom, (y - reg[1] + pad) * zoom],
  };
}

// ---------------------------------------------------------------------------
// Page template: background, headline, layout helpers
// ---------------------------------------------------------------------------
const FONT = (f) => 'file://' + path.join(REPO, 'Media', 'Fonts', f);
// The clock of the logo (logo.html, variant B), drawn inline as the brand mark.
const CLOCK = `<svg width="46" height="46" viewBox="-104 -104 208 208" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="arc" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#22d3ee"/>
<stop offset="1" stop-color="#ff2bd6"/></linearGradient></defs>
<circle r="92" fill="none" stroke="#a5f3fc" stroke-opacity="0.15" stroke-width="16"/>
<circle r="92" fill="none" stroke="url(#arc)" stroke-width="16" stroke-linecap="round"
 stroke-dasharray="433.5 578" transform="rotate(-90)"/>
<circle r="68" fill="#060c1a" stroke="#22d3ee" stroke-opacity="0.6" stroke-width="3"/>
<g stroke="#67e8f9" stroke-linecap="round" stroke-width="7">
<line x1="0" y1="-56" x2="0" y2="-44"/><line x1="56" y1="0" x2="44" y2="0"/>
<line x1="0" y1="56" x2="0" y2="44"/><line x1="-56" y1="0" x2="-44" y2="0"/></g>
<g stroke="#e6f7ff" stroke-linecap="round"><line x1="0" y1="0" x2="-29" y2="-16" stroke-width="9"/>
<line x1="0" y1="0" x2="32" y2="-34" stroke-width="7"/></g><circle r="9" fill="#ff2bd6"/></svg>`;

function page(height, headline, body, opts = {}) {
  const [plain, accent] = headline;
  const sub = opts.sub ? `<p class="sub">${opts.sub}</p>` : '';
  return `<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{font-family:Orbitron;src:url(${FONT('Orbitron-Bold.ttf')});}
@font-face{font-family:Barlow;src:url(${FONT('Barlow-Medium.ttf')});}
html,body{margin:0;padding:0;}
body{width:${WIDTH}px;height:${height}px;position:relative;overflow:hidden;color:#f0fbff;
  background:radial-gradient(ellipse 120% 90% at 50% 0%,#1b1747 0%,#0b1026 55%,#03050d 100%);}
.grid{position:absolute;inset:0;background-image:
  linear-gradient(rgba(34,211,238,.045) 1px,transparent 1px),
  linear-gradient(90deg,rgba(34,211,238,.045) 1px,transparent 1px);
  background-size:40px 40px;background-position:-1px -1px;
  -webkit-mask-image:radial-gradient(ellipse 90% 80% at 50% 30%,#000 30%,transparent 100%);}
.blob{position:absolute;border-radius:50%;filter:blur(110px);}
.head{position:absolute;left:0;right:0;top:${opts.headTop || 84}px;text-align:${opts.align || 'center'};
  ${opts.align === 'left' ? 'padding-left:96px;' : ''}}
h1{margin:0;font-family:Orbitron;font-weight:700;font-size:${opts.size || 58}px;letter-spacing:.5px;line-height:1.15;}
h1 .acc{background:linear-gradient(90deg,#ff3cc7,#38bdf8);-webkit-background-clip:text;background-clip:text;color:transparent;}
.sub{margin:22px 0 0;font-family:Barlow;font-size:27px;color:#a3bfcf;letter-spacing:.2px;}
.ui{position:absolute;display:block;}
.float{filter:drop-shadow(0 28px 50px rgba(0,0,0,.55));}
.label{position:absolute;font-family:Barlow;font-size:17px;letter-spacing:2.5px;text-transform:uppercase;color:#7f96a9;}
.brand{position:absolute;display:flex;align-items:center;gap:14px;font-family:Orbitron;font-size:22px;color:#e6f7ff;}
.brand svg{filter:drop-shadow(0 0 6px rgba(34,211,238,.35));}
</style></head><body>
<div class="grid"></div>
<div class="blob" style="width:620px;height:420px;left:-180px;top:${height - 380}px;background:rgba(255,43,214,.16);"></div>
<div class="blob" style="width:680px;height:460px;right:-200px;top:-160px;background:rgba(34,211,238,.13);"></div>
${opts.brand ? `<div class="brand" style="left:96px;top:58px;">${CLOCK}TruePlayed</div>` : ''}
<div class="head"><h1>${plain}${accent ? ` <span class="acc">${accent}</span>` : ''}</h1>${sub}</div>
${body}
</body></html>`;
}

const img = (s, x, y, cls = '') =>
  `<img class="ui ${cls}" src="${s.src}" style="left:${x}px;top:${y}px;width:${s.w}px;height:${s.h}px;">`;

async function capture(browser, html, height, name) {
  height = Math.round(height);
  const file = path.join(TMP, name + '.html');
  fs.writeFileSync(file, html);
  const p = await browser.newPage({ viewport: { width: WIDTH, height }, deviceScaleFactor: 1 });
  await p.goto('file://' + file);
  await p.evaluate(() => document.fonts.ready);
  await p.evaluate(() => Promise.all([...document.images].map((i) => i.decode())));
  fs.mkdirSync(OUT, { recursive: true });
  const out = path.join(OUT, name + '.png');
  await p.screenshot({ path: out, clip: { x: 0, y: 0, width: WIDTH, height } });
  await p.close();
  console.log(`${path.relative(REPO, out)}: ${WIDTH} x ${height}`);
}

// ---------------------------------------------------------------------------
// Images
// ---------------------------------------------------------------------------

// hero.png: headline left, the bar (600 wide, bottom of the screen) with its tooltip on the right.
async function hero(browser) {
  const H = 800, zoom = 1.32;
  const sc = await scene('hero', 'futuriste');
  const s = await shot(browser, sc, zoom, 'hero-ui');
  const x = WIDTH - 64 - s.w, y = H - 30 - s.h;
  const body = img(s, x, y, 'float');
  const html = page(H, ['Your real', '/played.'], body, {
    align: 'left', headTop: 300, size: 64, brand: true,
    sub: 'Time to level. XP per hour. Mobs to kill.',
  });
  await capture(browser, html, H, 'hero');
}

// themes.png: the bar in each of the 13 themes, two columns.
async function themes(browser) {
  const zoom = 1.45;
  const scenes = await Promise.all(THEMES.map(([k]) => scene('bar', k)));
  const shots = [];
  for (let i = 0; i < THEMES.length; i++) shots.push(await shot(browser, scenes[i], zoom, 'bar-' + THEMES[i][0]));
  const top = 230, colW = 700, gapX = 40, rowH = 150;
  const left0 = (WIDTH - 2 * colW - gapX) / 2;
  let body = '';
  shots.forEach((s, i) => {
    const row = Math.floor(i / 2), col = i % 2;
    const last = i === shots.length - 1 && shots.length % 2 === 1;
    const cx = last ? WIDTH / 2 : left0 + col * (colW + gapX) + colW / 2;
    const y = top + row * rowH;
    body += img(s, Math.round(cx - s.w / 2), y + 26 + Math.round((100 - s.h) / 2));
    body += `<div class="label" style="left:${cx - 200}px;width:400px;text-align:center;top:${y}px;">${THEMES[i][1]}</div>`;
  });
  const H = top + Math.ceil(shots.length / 2) * rowH + 50;
  await capture(browser, page(H, ['13 themes.', 'One click.'], body), H, 'themes');
}

// detail.png: the detailed (Shift) tooltip, Futuristic and Heroic fantasy side by side.
async function detail(browser) {
  const zoom = 1.08;
  const [a, b] = await Promise.all([scene('tooltipshift', 'futuriste'), scene('tooltipshift', 'heroic')]);
  const sa = await shot(browser, a, zoom, 'detail-fut'), sb = await shot(browser, b, zoom, 'detail-her');
  const gap = 70, top = 220;
  const total = sa.w + gap + sb.w;
  const x0 = (WIDTH - total) / 2;
  const H = Math.round(top + Math.max(sa.h, sb.h) + 70);
  const body = img(sa, x0, top, 'float') + img(sb, x0 + sa.w + gap, top, 'float');
  await capture(browser, page(H, ['Hold Shift.', 'See everything.'], body), H, 'detail');
}

// stats.png: the statistics window, the Levels tab (top left) and the Zones tab (bottom right,
// in front: an opaque plate of the window colour under it, as over a dark game scene).
async function stats(browser) {
  const zoom = 1.4;
  const [lv, zn] = await Promise.all([scene('levels', 'futuriste'), scene('zones', 'futuriste')]);
  const sl = await shot(browser, lv, zoom, 'stats-levels'), sz = await shot(browser, zn, zoom, 'stats-zones');
  const top = 240, dx = 470, dy = 330;
  const x0 = Math.round((WIDTH - sl.w - dx) / 2);
  const H = Math.round(top + dy + sz.h + 60);
  // the window's own backdrop (largest backdrop item) -> plate under the front window
  const bd = zn.items.filter((i) => i.kind === 'backdrop').sort((a, b) => b.rect[2] * b.rect[3] - a.rect[2] * a.rect[3])[0];
  const [px, py] = sz.map(bd.rect[0] + bd.insets[0], bd.rect[1] + bd.insets[2]);
  const pw = (bd.rect[2] - bd.insets[0] - bd.insets[1]) * zoom, ph = (bd.rect[3] - bd.insets[2] - bd.insets[3]) * zoom;
  const c = bd.bg.slice(0, 3).map((v) => Math.round(v * 255)).join(',');
  const fx = x0 + dx, fy = top + dy;
  const body = `<div style="opacity:.92">${img(sl, x0, top, 'float')}</div>` +
    `<div style="position:absolute;left:${fx + px}px;top:${fy + py}px;width:${pw}px;height:${ph}px;` +
    `background:rgb(${c});box-shadow:0 28px 60px rgba(0,0,0,.6);"></div>` + img(sz, fx, fy);
  await capture(browser, page(H, ['Every level.', 'Every zone.'], body), H, 'stats');
}

// compact.png: the mini display (the XP bar hidden): one line in three themes on the left,
// stacked in Heroic fantasy, and one line hovered with its tooltip on the right.
async function compact(browser) {
  const zoom = 2.1;
  const [h1, h2, h3, v, tip] = await Promise.all([scene('minih', 'futuriste'), scene('minih', 'mage'),
    scene('minih', 'warlock'), scene('miniv', 'heroic'), scene('minitip', 'futuriste')]);
  const s1 = await shot(browser, h1, zoom, 'mini-fut'), s2 = await shot(browser, h2, zoom, 'mini-mag');
  const s3 = await shot(browser, h3, zoom, 'mini-wlk'), sv = await shot(browser, v, zoom, 'mini-her');
  const st = await shot(browser, tip, 1.08, 'mini-tip');
  const top = 270, left = 120, gap = 40;
  let body = '', y = top;
  for (const [s, name] of [[s1, 'Futuristic'], [s2, 'Mage'], [s3, 'Warlock']]) {
    body += `<div class="label" style="left:${left}px;top:${y}px;">${name}</div>` + img(s, left, y + 30, 'float');
    y += 30 + s.h + gap;
  }
  body += `<div class="label" style="left:${left}px;top:${y}px;">Heroic fantasy, stacked</div>` + img(sv, left, y + 30, 'float');
  y += 30 + sv.h;
  const tx = WIDTH - 90 - st.w;
  body += img(st, tx, top, 'float');
  const H = Math.round(Math.max(y, top + st.h) + 70);
  await capture(browser, page(H, ['Your bar.', 'Or no bar.'], body, {
    sub: 'A tiny display in any corner. Hover it for everything.' }), H, 'compact');
}

(async () => {
  const browser = await R.launch();
  try {
    if (want('hero')) await hero(browser);
    if (want('themes')) await themes(browser);
    if (want('detail')) await detail(browser);
    if (want('stats')) await stats(browser);
    if (want('compact')) await compact(browser);
  } finally {
    await browser.close();
    if (keep) console.log('intermediate files: ' + TMP);
    else fs.rmSync(TMP, { recursive: true, force: true });
  }
})().catch((e) => { console.error(e); process.exit(1); });
