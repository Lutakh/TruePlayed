// media-src/curseforge/render-scene.js - turns a scene JSON written by scene.lua into a PNG:
// what the addon draws, rendered with its own art and fonts. Node.js + Playwright (Chromium):
//   NODE_PATH=$(npm root -g) node media-src/curseforge/render-scene.js <scene.json> <out.png>
//       [--scale 3] [--pad 6] [--bg transparent|#rrggbb]
// Also a module: require('./render-scene').renderScene(browser, scene, outPng, opts).
//
// Textures: the .tga files of Media/Themes (decoded here: uncompressed or RLE, 8/24/32 bit)
// are resampled per device pixel in the page like the game does it: texture coordinates
// (4 or 8 values, CLAMP or REPEAT wrap), bilinear filtering, vertex colour or gradient
// multiplied, effective alpha, a circle mask (the game's TempPortraitAlphaMask), partial
// pixel coverage at the edges. ADD blending uses mix-blend-mode: plus-lighter (exact over an
// opaque background; over a transparent one it degrades to normal alpha blending).
// Game files that are not in the repository are stand-ins: WHITE8X8 and the tooltip
// background = white, the tooltip border = a thin rounded line, game fonts (FRIZQT__,
// ARIALN...) = the bundled Signika Medium (the width stand-in of tests/fontmetrics.lua) or
// Barlow Condensed (Arial Narrow). Text: HTML with the bundled fonts; OUTLINE /
// THICKOUTLINE = a 1 / 2 px black stroke outside the glyphs, the shadow offset as recorded.
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const REPO = path.resolve(__dirname, '..', '..');

// ---------------------------------------------------------------------------
// TGA decoder -> { w, h, data: Uint8Array RGBA, top-down rows }
// ---------------------------------------------------------------------------
function decodeTGA(buf) {
  const idLen = buf[0], cmapType = buf[1], type = buf[2];
  const cmapLen = buf.readUInt16LE(5), cmapDepth = buf[7];
  const w = buf.readUInt16LE(12), h = buf.readUInt16LE(14);
  const bpp = buf[16], desc = buf[17];
  if (cmapType !== 0) throw new Error('TGA: colour-mapped images are not supported');
  const rle = type === 10 || type === 11;
  const grey = type === 3 || type === 11;
  if (![2, 3, 10, 11].includes(type)) throw new Error('TGA: unsupported type ' + type);
  const bytes = bpp / 8;
  let off = 18 + idLen + cmapLen * Math.ceil(cmapDepth / 8);
  const n = w * h;
  const px = new Uint8Array(n * bytes);
  if (!rle) {
    buf.copy(Buffer.from(px.buffer), 0, off, off + n * bytes);
  } else {
    let i = 0;
    while (i < n) {
      const c = buf[off++];
      const count = (c & 0x7f) + 1;
      if (c & 0x80) {
        for (let k = 0; k < count; k++) for (let b = 0; b < bytes; b++) px[(i + k) * bytes + b] = buf[off + b];
        off += bytes;
      } else {
        for (let k = 0; k < count * bytes; k++) px[i * bytes + k] = buf[off + k];
        off += count * bytes;
      }
      i += count;
    }
  }
  const topDown = (desc & 0x20) !== 0;
  const rightLeft = (desc & 0x10) !== 0;
  const out = new Uint8Array(n * 4);
  for (let y = 0; y < h; y++) {
    const sy = topDown ? y : h - 1 - y;
    for (let x = 0; x < w; x++) {
      const sx = rightLeft ? w - 1 - x : x;
      const s = (sy * w + sx) * bytes, d = (y * w + x) * 4;
      if (grey) {
        out[d] = out[d + 1] = out[d + 2] = px[s];
        out[d + 3] = bytes === 2 ? px[s + 1] : 255;
      } else {
        out[d] = px[s + 2]; out[d + 1] = px[s + 1]; out[d + 2] = px[s];
        out[d + 3] = bytes === 4 ? px[s + 3] : 255;
      }
    }
  }
  return { w, h, data: out };
}

// Minimal PNG encoder (RGBA 8 bit), for tools that want the decoded textures.
function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function encodePNG(img) {
  const { w, h, data } = img;
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    Buffer.from(data.buffer, data.byteOffset + y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
  }
  const chunk = (type, body) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(body.length);
    const tb = Buffer.concat([Buffer.from(type), body]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(tb));
    return Buffer.concat([len, tb, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

// ---------------------------------------------------------------------------
// Textures: repository .tga, or a stand-in for a game file
// ---------------------------------------------------------------------------
function solid(w, h, fn) {
  const data = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const v = fn(x, y), d = (y * w + x) * 4;
    data[d] = v[0]; data[d + 1] = v[1]; data[d + 2] = v[2]; data[d + 3] = v[3];
  }
  return { w, h, data };
}
const warned = new Set();
function loadTexture(file) {
  if (!file) return solid(1, 1, () => [255, 255, 255, 255]);
  if (file.startsWith('game:')) {
    const g = file.slice(5).toLowerCase();
    if (g.includes('tempportraitalphamask')) {
      const S = 128;
      return solid(S, S, (x, y) => {
        const dx = x + 0.5 - S / 2, dy = y + 0.5 - S / 2;
        const a = Math.max(0, Math.min(1, S / 2 - Math.sqrt(dx * dx + dy * dy)));
        return [255, 255, 255, Math.round(a * 255)];
      });
    }
    if (!g.includes('white8x8') && !g.includes('ui-tooltip-background') && !warned.has(g)) {
      warned.add(g);
      process.stderr.write('render-scene: game texture ' + file + ' drawn as white\n');
    }
    return solid(1, 1, () => [255, 255, 255, 255]);
  }
  return decodeTGA(fs.readFileSync(path.join(REPO, file)));
}

// ---------------------------------------------------------------------------
// Fonts
// ---------------------------------------------------------------------------
function fontFile(font) {
  if (!font.startsWith('game:')) return font;
  const f = font.toLowerCase();
  if (f.includes('arialn')) return 'Media/Fonts/BarlowCondensed-Medium.ttf';
  return 'Media/Fonts/Signika-Medium.ttf';   // FRIZQT__ and any other game font
}
const STANDIN = 'f_Signika_Medium_ttf';   // glyphs a bundled font lacks (tests/fontmetrics.lua)
function fontFamily(file) {
  return 'f_' + path.basename(file).replace(/\W/g, '_');
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------
function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
function rgba(c, mul) {
  const a = (c[3] === undefined ? 1 : c[3]) * (mul === undefined ? 1 : mul);
  return `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a.toFixed(4)})`;
}
// WoW escape sequences: |cAARRGGBB ... |r colour runs, || a pipe; other codes dropped.
function textHTML(text, base) {
  let out = '', i = 0, open = false;
  const s = String(text);
  while (i < s.length) {
    if (s[i] === '|' && i + 1 < s.length) {
      const n = s[i + 1];
      if ((n === 'c' || n === 'C') && /^[0-9a-fA-F]{8}$/.test(s.substr(i + 2, 8))) {
        const h = s.substr(i + 2, 8);
        if (open) out += '</span>';
        out += `<span style="color:#${h.substr(2, 6)}">`;
        open = true; i += 10; continue;
      }
      if (n === 'r' || n === 'R') { if (open) out += '</span>'; open = false; i += 2; continue; }
      if (n === '|') { out += '|'; i += 2; continue; }
    }
    out += s[i] === '\n' ? '<br>' : esc(s[i]);
    i++;
  }
  if (open) out += '</span>';
  return out;
}

function buildPage(scene, opts) {
  const S = opts.scale, pad = opts.pad;
  const b = opts.region || scene.bounds;
  const ox = -b[0] + pad, oy = -b[1] + pad;
  const W = Math.ceil(b[2] + 2 * pad), H = Math.ceil(b[3] + 2 * pad);

  const texIndex = new Map(), textures = [];
  const fonts = new Set(['Media/Fonts/Signika-Medium.ttf']);
  const items = [];
  for (const it of scene.items) {
    const r = [it.rect[0] + ox, it.rect[1] + oy, it.rect[2], it.rect[3]];
    const clip = it.clip ? [it.clip[0] + ox, it.clip[1] + oy, it.clip[2], it.clip[3]] : null;
    if (it.kind === 'tex') {
      for (const f of [it.file, it.mask && it.mask.file]) {
        const key = f || '';
        if (f !== undefined && !texIndex.has(key)) {
          texIndex.set(key, textures.length);
          const t = loadTexture(f);
          textures.push({ w: t.w, h: t.h, b64: Buffer.from(t.data).toString('base64') });
        }
      }
      items.push({ k: 't', r, clip, tex: texIndex.get(it.file || ''), tc: it.tc, wrapH: it.wrapH,
        wrapV: it.wrapV, blend: it.blend, alpha: it.alpha, vertex: it.vertex, grad: it.grad,
        solid: it.solid,
        mask: it.mask ? { tex: texIndex.get(it.mask.file || ''),
          r: [it.mask.rect[0] + ox, it.mask.rect[1] + oy, it.mask.rect[2], it.mask.rect[3]] } : null });
    } else if (it.kind === 'text') {
      const file = fontFile(it.font);
      fonts.add(file);
      items.push({ k: 'x', r, clip, html: textHTML(it.text), fam: fontFamily(file), size: it.size,
        flags: it.flags || '', color: it.color, shadow: it.shadow, jh: it.justifyH, jv: it.justifyV,
        wrap: it.wrap, bounded: it.bounded, alpha: it.alpha, game: it.font.startsWith('game:'), natW: it.natW });
    } else if (it.kind === 'backdrop') {
      items.push({ k: 'b', r, clip, it });
    }
  }

  // HTML for text and backdrops; textures are canvases filled by the page script
  let body = '';
  items.forEach((x, i) => {
    let inner = '';
    if (x.k === 't') {
      inner = `<canvas id="c${i}"></canvas>`;
    } else if (x.k === 'x') {
      const out = /THICKOUTLINE/.test(x.flags) ? 2 : /OUTLINE/.test(x.flags) ? 1 : 0;
      const sh = x.shadow ? `${x.shadow.x}px ${-x.shadow.y}px 0 ${rgba(x.shadow.color)}` : 'none';
      const jh = { LEFT: 'flex-start', CENTER: 'center', RIGHT: 'flex-end' }[x.jh] || 'center';
      const jv = { TOP: 'flex-start', MIDDLE: 'center', BOTTOM: 'flex-end' }[x.jv] || 'center';
      const ta = { LEFT: 'left', CENTER: 'center', RIGHT: 'right' }[x.jh] || 'center';
      const bounded = x.bounded && x.r[2] > 0 && x.natW > x.r[2] + 0.5;
      const ws = bounded && x.wrap ? 'normal' : 'pre';
      const ell = bounded && !x.wrap ? 'overflow:hidden;text-overflow:ellipsis;max-width:100%;' : '';
      const stroke = out ? `-webkit-text-stroke:${2 * out}px rgba(0,0,0,${x.color[3] === undefined ? 1 : x.color[3]});paint-order:stroke fill;` : '';
      inner = `<div class="tx" style="left:${x.r[0]}px;top:${x.r[1]}px;width:${x.r[2]}px;height:${x.r[3]}px;` +
        `justify-content:${jh};align-items:${jv};opacity:${x.alpha};">` +
        `<span style="font-family:${x.fam},${STANDIN};font-size:${x.size}px;line-height:${x.size}px;color:${rgba(x.color)};` +
        `text-shadow:${sh};${stroke}white-space:${ws};text-align:${ta};${ell}">${x.html}</span></div>`;
    } else if (x.k === 'b') {
      const it = x.it, [l, t, w, h] = x.r;
      const ins = it.insets || [0, 0, 0, 0];
      const e = it.edgeSize || 0;
      const tooltipEdge = it.edgeFile && /ui-tooltip-border/i.test(it.edgeFile);
      if (it.bgFile) {
        const rad = tooltipEdge ? 'border-radius:3px;' : '';
        inner += `<div style="position:absolute;left:${l + ins[0]}px;top:${t + ins[2]}px;` +
          `width:${w - ins[0] - ins[1]}px;height:${h - ins[2] - ins[3]}px;background:${rgba(it.bg, it.alpha)};${rad}"></div>`;
      }
      if (it.edgeFile && e > 0) {
        if (tooltipEdge) {
          inner += `<div style="position:absolute;left:${l + 1}px;top:${t + 1}px;width:${w - 2}px;height:${h - 2}px;` +
            `box-sizing:border-box;border:2px solid ${rgba(it.border, it.alpha)};border-radius:4px;"></div>`;
        } else {
          inner += `<div style="position:absolute;left:${l}px;top:${t}px;width:${w}px;height:${h}px;` +
            `box-sizing:border-box;border:${e}px solid ${rgba(it.border, it.alpha)};"></div>`;
        }
      }
    }
    if (x.clip) {
      const c = x.clip;
      inner = `<div style="position:absolute;left:0;top:0;width:${W}px;height:${H}px;` +
        `clip-path:inset(${c[1]}px ${W - c[0] - c[2]}px ${H - c[1] - c[3]}px ${c[0]}px);">${inner}</div>`;
    }
    body += inner + '\n';
  });

  const faces = [...fonts].map((f) => {
    const b64 = fs.readFileSync(path.join(REPO, f)).toString('base64');
    return `@font-face{font-family:${fontFamily(f)};src:url(data:font/ttf;base64,${b64});}`;
  }).join('\n');

  const texItems = items.map((x, i) => (x.k === 't' ? Object.assign({ i }, x) : null)).filter(Boolean);
  const html = `<!doctype html><html><head><meta charset="utf-8"><style>
${faces}
html,body{margin:0;padding:0;background:${opts.bg};}
#root{position:relative;width:${W}px;height:${H}px;overflow:hidden;}
canvas{position:absolute;display:block;}
.tx{position:absolute;display:flex;box-sizing:border-box;}
.tx>span{display:block;font-kerning:normal;-webkit-font-smoothing:antialiased;}
</style></head><body><div id="root">
${body}</div>
<script>
const S = ${S};
const TEX = ${JSON.stringify(textures)};
const ITEMS = ${JSON.stringify(texItems)};
${pageScript.toString()}
pageScript();
</script></body></html>`;
  return { html, W, H };
}

// Runs in the page: samples every texture item into its canvas.
function pageScript() {
  const decoded = TEX.map((t) => {
    const bin = atob(t.b64);
    const d = new Float32Array(bin.length);
    for (let i = 0; i < bin.length; i += 4) {      // premultiplied, 0..1
      const a = bin.charCodeAt(i + 3) / 255;
      d[i] = bin.charCodeAt(i) / 255 * a; d[i + 1] = bin.charCodeAt(i + 1) / 255 * a;
      d[i + 2] = bin.charCodeAt(i + 2) / 255 * a; d[i + 3] = a;
    }
    return { w: t.w, h: t.h, d };
  });
  const wrapIdx = (i, n, repeat) => {
    if (repeat) return ((i % n) + n) % n;
    return i < 0 ? 0 : i >= n ? n - 1 : i;
  };
  const out4 = [0, 0, 0, 0];
  function sample(t, u, v, rh, rv) {
    const x = u * t.w - 0.5, y = v * t.h - 0.5;
    const x0 = Math.floor(x), y0 = Math.floor(y);
    const fx = x - x0, fy = y - y0;
    const xa = wrapIdx(x0, t.w, rh), xb = wrapIdx(x0 + 1, t.w, rh);
    const ya = wrapIdx(y0, t.h, rv), yb = wrapIdx(y0 + 1, t.h, rv);
    const d = t.d, w = t.w;
    const i00 = (ya * w + xa) * 4, i10 = (ya * w + xb) * 4, i01 = (yb * w + xa) * 4, i11 = (yb * w + xb) * 4;
    const w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy), w01 = (1 - fx) * fy, w11 = fx * fy;
    for (let k = 0; k < 4; k++) out4[k] = d[i00 + k] * w00 + d[i10 + k] * w10 + d[i01 + k] * w01 + d[i11 + k] * w11;
    return out4;
  }
  for (const it of ITEMS) {
    const [x, y, w, h] = it.r;
    const X0 = Math.floor(x * S + 1e-6), Y0 = Math.floor(y * S + 1e-6);
    const X1 = Math.ceil((x + w) * S - 1e-6), Y1 = Math.ceil((y + h) * S - 1e-6);
    const cw = X1 - X0, ch = Y1 - Y0;
    const cv = document.getElementById('c' + it.i);
    if (cw <= 0 || ch <= 0) { cv.remove(); continue; }
    cv.width = cw; cv.height = ch;
    cv.style.left = (X0 / S) + 'px'; cv.style.top = (Y0 / S) + 'px';
    cv.style.width = (cw / S) + 'px'; cv.style.height = (ch / S) + 'px';
    if (it.blend === 'ADD') cv.style.mixBlendMode = 'plus-lighter';
    else if (it.blend === 'MOD') cv.style.mixBlendMode = 'multiply';
    const ctx = cv.getContext('2d');
    const img = ctx.createImageData(cw, ch);
    const o = img.data;
    const t = it.solid ? null : TEX[it.tex] && decoded[it.tex];
    const tc = it.tc;
    const rh = it.wrapH === 'REPEAT' || it.wrapH === 'MIRROR', rv = it.wrapV === 'REPEAT' || it.wrapV === 'MIRROR';
    const m = it.mask ? { t: decoded[it.mask.tex], r: it.mask.r } : null;
    for (let py = 0; py < ch; py++) {
      const dy0 = (Y0 + py) / S, dy1 = (Y0 + py + 1) / S;
      const covY = Math.max(0, Math.min(dy1, y + h) - Math.max(dy0, y)) * S;
      const fyc = (((Y0 + py + 0.5) / S) - y) / h;
      for (let px = 0; px < cw; px++) {
        const dx0 = (X0 + px) / S, dx1 = (X0 + px + 1) / S;
        const covX = Math.max(0, Math.min(dx1, x + w) - Math.max(dx0, x)) * S;
        const cov = covX * covY;
        const di = (py * cw + px) * 4;
        if (cov <= 0) { o[di + 3] = 0; continue; }
        const fx = (((X0 + px + 0.5) / S) - x) / w;
        const fy = fyc;
        // texture coordinates: bilinear over the four corners (UL, LL, UR, LR)
        const u = tc[0] * (1 - fx) * (1 - fy) + tc[2] * (1 - fx) * fy + tc[4] * fx * (1 - fy) + tc[6] * fx * fy;
        const v = tc[1] * (1 - fx) * (1 - fy) + tc[3] * (1 - fx) * fy + tc[5] * fx * (1 - fy) + tc[7] * fx * fy;
        let r, g, b, a;
        if (it.solid) {
          [r, g, b, a] = it.solid; r *= a; g *= a; b *= a;
        } else if (t) {
          const s = sample(t, u, v, rh, rv);
          r = s[0]; g = s[1]; b = s[2]; a = s[3];
        } else { r = g = b = a = 1; }
        let c;
        if (it.grad) {
          const gr = it.grad, k = gr.dir === 'VERTICAL' ? 1 - fy : fx;
          c = [0, 1, 2, 3].map((j) => gr.from[j] + (gr.to[j] - gr.from[j]) * k);
        } else c = it.vertex || [1, 1, 1, 1];
        let mk = 1;
        if (m) {
          const mu = (((X0 + px + 0.5) / S) - m.r[0]) / m.r[2];
          const mv = (((Y0 + py + 0.5) / S) - m.r[1]) / m.r[3];
          mk = (mu < 0 || mu > 1 || mv < 0 || mv > 1) ? 0 : sample(m.t, mu, mv, false, false)[3];
        }
        const A = a * c[3] * it.alpha * cov * mk;
        const k2 = A > 0 ? (c[3] * it.alpha * cov * mk) / A : 0;    // un-premultiply
        o[di] = Math.min(255, Math.round(r * c[0] * k2 * 255));
        o[di + 1] = Math.min(255, Math.round(g * c[1] * k2 * 255));
        o[di + 2] = Math.min(255, Math.round(b * c[2] * k2 * 255));
        o[di + 3] = Math.min(255, Math.round(A * 255));
      }
    }
    ctx.putImageData(img, 0, 0);
  }
  window.__done = true;
}

async function renderScene(browser, scene, outPng, opts = {}) {
  const o = Object.assign({ scale: 3, pad: 6, bg: 'transparent' }, opts);
  const { html, W, H } = buildPage(scene, o);
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: o.scale });
  const tmp = path.join(require('os').tmpdir(), 'tp-scene-' + process.pid + '-' + Math.random().toString(36).slice(2) + '.html');
  fs.writeFileSync(tmp, html);
  await page.goto('file://' + tmp);
  await page.waitForFunction(() => window.__done === true);
  await page.evaluate(() => document.fonts.ready);
  await page.locator('#root').screenshot({ path: outPng, omitBackground: o.bg === 'transparent' });
  await page.close();
  fs.unlinkSync(tmp);
  return { width: W * o.scale, height: H * o.scale, region: o.region || scene.bounds, pad: o.pad };
}

// Chromium with font hinting off: subpixel glyph positioning, so text widths match the
// font metrics the addon was laid out with (tests/fontmetrics.lua) within 1 px.
function launch() {
  const { chromium } = require('playwright');
  return chromium.launch({ args: ['--font-render-hinting=none'] });
}

module.exports = { decodeTGA, encodePNG, buildPage, renderScene, launch };

if (require.main === module) {
  (async () => {
    const args = process.argv.slice(2);
    const pos = [], opts = {};
    for (let i = 0; i < args.length; i++) {
      if (args[i] === '--scale') opts.scale = Number(args[++i]);
      else if (args[i] === '--pad') opts.pad = Number(args[++i]);
      else if (args[i] === '--bg') opts.bg = args[++i];
      else if (args[i] === '--region') opts.region = args[++i].split(',').map(Number);
      else pos.push(args[i]);
    }
    if (pos.length < 2) {
      console.error('usage: node render-scene.js <scene.json> <out.png> [--scale 3] [--pad 6] [--bg transparent|#rrggbb] [--region x,y,w,h]');
      process.exit(2);
    }
    const browser = await launch();
    const scene = JSON.parse(fs.readFileSync(pos[0], 'utf8'));
    const r = await renderScene(browser, scene, pos[1], opts);
    await browser.close();
    console.log(`${pos[1]}: ${r.width} x ${r.height}`);
  })().catch((e) => { console.error(e); process.exit(1); });
}
