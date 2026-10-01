#!/usr/bin/env python3
"""SVG -> uncompressed 32-bit TGA (type 2, bottom-left origin, 8 alpha bits) for WoW.
macOS sips rasterises the SVG (it writes RLE TGA, which WoW does not read reliably);
this script decodes that RLE output and rewrites it uncompressed.

The colour of the visible texels is then bled into the fully transparent ones (alpha
stays 0): WoW filters straight alpha, so at a UI scale other than 1, or on minified art,
an edge texel is blended with its transparent neighbours, and a black colour there
draws a dark fringe along bright lines.

Usage:
  python3 tools/svg2tga.py src.svg dst.tga          convert (and bleed)
  python3 tools/svg2tga.py --bleed file.tga ...     bleed existing TGAs in place"""
import struct, subprocess, sys, tempfile, os

def read_tga(path):
    b = open(path, 'rb').read()
    idl, itype = b[0], b[2]
    w, h, bpp, desc = struct.unpack('<HHBB', b[12:18])
    if bpp != 32: raise SystemExit(f'{path}: expected 32 bpp, got {bpp}')
    o, n, px = 18 + idl, w * h, bytearray()
    if itype == 2:
        px = bytearray(b[o:o + n * 4])
    elif itype == 10:
        while len(px) < n * 4:
            c = b[o]; o += 1
            cnt = (c & 0x7f) + 1
            if c & 0x80:
                px += b[o:o + 4] * cnt; o += 4
            else:
                px += b[o:o + 4 * cnt]; o += 4 * cnt
    else:
        raise SystemExit(f'{path}: unsupported TGA type {itype}')
    rows = [px[r * w * 4:(r + 1) * w * 4] for r in range(h)]
    if not desc & 0x20: rows.reverse()          # -> top-left order
    return w, h, rows

def write_tga(path, w, h, rows_topleft):
    hdr = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08)
    with open(path, 'wb') as f:
        f.write(hdr)
        for r in reversed(rows_topleft): f.write(r)   # bottom-left origin

def pot(n): return n > 0 and n & (n - 1) == 0

NEIGHBOURS = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]

def bleed(w, h, rows):
    """Fills the colour (B, G, R) of every alpha-0 texel, ring by ring from the visible
    art: the average of its already coloured 8-neighbours, weighted by their alpha (1 for
    texels coloured by an earlier ring). Alpha and visible texels are left as they are.
    Grey art stays grey (the three channels get the same arithmetic)."""
    col = [[None] * w for _ in range(h)]
    pending = []
    for y in range(h):
        r = rows[y]
        for x in range(w):
            a = r[x * 4 + 3]
            if a > 0:
                col[y][x] = (r[x * 4], r[x * 4 + 1], r[x * 4 + 2], a)
            else:
                pending.append((x, y))
    if len(pending) == w * h:
        return rows                                  # nothing visible: nothing to bleed
    while pending:
        ring, rest = [], []
        for x, y in pending:
            sb = sg = sr = sw = 0
            for dx, dy in NEIGHBOURS:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    c = col[ny][nx]
                    if c is not None:
                        sb += c[0] * c[3]; sg += c[1] * c[3]; sr += c[2] * c[3]; sw += c[3]
            if sw > 0:
                ring.append((x, y, (sb + sw // 2) // sw, (sg + sw // 2) // sw, (sr + sw // 2) // sw))
            else:
                rest.append((x, y))
        if not ring:
            break
        for x, y, b, g, r in ring:
            col[y][x] = (b, g, r, 1)
            rows[y][x * 4:x * 4 + 3] = bytes((b, g, r))
        pending = rest
    return rows

if __name__ == '__main__':
    if len(sys.argv) >= 2 and sys.argv[1] == '--bleed':
        for path in sys.argv[2:]:
            w, h, rows = read_tga(path)
            write_tga(path, w, h, bleed(w, h, rows))
            print(f'{path}: {w}x{h} bled')
        raise SystemExit(0)
    src, dst = sys.argv[1], sys.argv[2]
    with tempfile.TemporaryDirectory() as d:
        tmp = os.path.join(d, 'x.tga')
        subprocess.run(['sips', '-s', 'format', 'tga', src, '--out', tmp], check=True, capture_output=True)
        w, h, rows = read_tga(tmp)
    if not (pot(w) and pot(h)): raise SystemExit(f'{src}: {w}x{h} is not power-of-two')
    write_tga(dst, w, h, bleed(w, h, rows))
    print(f'{dst}: {w}x{h}')
