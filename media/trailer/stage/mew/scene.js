// Mew's world, drawn as layers of cut paper in front of a glowing sky.
// Everything is SVG in a 1600 x 1000 box. A seeded random source keeps every render identical,
// which the recordings depend on.

import { cat } from './cat.js';

export const W = 1600, H = 1000;
export const INK = '#0b0509';
const MID = '#34102c';
const FAR = '#7a2a4e';
const HAZE = '#a8405e';
const CREAM = '#fff1d6';
const LIT = '#f7a652';

export function rng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ---- Sky ------------------------------------------------------------------------------------

export function sky() {
  return `
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1e071b"/>
      <stop offset=".16" stop-color="#3a1136"/>
      <stop offset=".36" stop-color="#7c2550"/>
      <stop offset=".5" stop-color="#c0435d"/>
      <stop offset=".6" stop-color="#ec7b4c"/>
      <stop offset=".7" stop-color="#ffb35f"/>
      <stop offset="1" stop-color="#ffd58a"/>
    </linearGradient>
    <radialGradient id="edges" cx=".5" cy=".42" r=".75">
      <stop offset=".55" stop-color="#1a0616" stop-opacity="0"/>
      <stop offset="1" stop-color="#1a0616" stop-opacity=".42"/>
    </radialGradient>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#sky)"/>`;
}

export function stars(seed = 7, count = 90, maxY = 430) {
  const r = rng(seed);
  let out = '';
  // The HUD's corners stay clear, so no star sits on its words.
  const clear = (x, y) => (x < 420 && y < 130) || (x > W - 200 && y < 110);
  for (let i = 0; i < count; i++) {
    const x = r() * W, y = Math.pow(r(), 1.5) * maxY;
    if (clear(x, y)) { r(); r(); continue; }
    const size = 0.6 + Math.pow(r(), 3) * 1.8;
    const o = (0.3 + r() * 0.6) * (1 - y / (maxY * 1.25));
    out += `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${size.toFixed(2)}" fill="${CREAM}" opacity="${o.toFixed(2)}"/>`;
  }
  // A few brighter stars get a four-point glint.
  for (let i = 0; i < 6; i++) {
    const x = 80 + r() * (W - 160), y = 30 + r() * (maxY * 0.6), l = 5 + r() * 5;
    if (clear(x, y)) continue;
    out += `<path d="M${x} ${y - l}Q${x} ${y} ${x + l} ${y}Q${x} ${y} ${x} ${y + l}Q${x} ${y} ${x - l} ${y}Q${x} ${y} ${x} ${y - l}Z" fill="${CREAM}" opacity=".8"/>`;
  }
  return `<g class="stars">${out}</g>`;
}

export function moon(cx, cy, r = 62) {
  return `
  <defs>
    <radialGradient id="moonGlow"><stop offset="0" stop-color="#ffe9c4" stop-opacity=".55"/><stop offset=".35" stop-color="#ffd9a8" stop-opacity=".22"/><stop offset="1" stop-color="#ffd9a8" stop-opacity="0"/></radialGradient>
    <radialGradient id="moonFace" cx=".42" cy=".38" r=".7"><stop offset="0" stop-color="#fffaf0"/><stop offset=".7" stop-color="#fff0d2"/><stop offset="1" stop-color="#ffe2b0"/></radialGradient>
  </defs>
  <g class="moon">
    <circle cx="${cx}" cy="${cy}" r="${r * 4.4}" fill="url(#moonGlow)"/>
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="url(#moonFace)"/>
    <circle cx="${cx - r * 0.28}" cy="${cy + r * 0.12}" r="${r * 0.16}" fill="#f6ddb4" opacity=".55"/>
    <circle cx="${cx + r * 0.22}" cy="${cy - r * 0.3}" r="${r * 0.1}" fill="#f6ddb4" opacity=".5"/>
    <circle cx="${cx + r * 0.3}" cy="${cy + r * 0.34}" r="${r * 0.07}" fill="#f6ddb4" opacity=".45"/>
  </g>`;
}

// A cloud as cut paper: a few long wisps, each a lens that tapers to a point at both ends.
export function wisps(x, y, w, fill, opacity = 1, seed = 3) {
  const r = rng(seed);
  let d = '';
  const n = 2 + Math.floor(r() * 2);
  for (let i = 0; i < n; i++) {
    const len = w * (0.45 + r() * 0.55);
    const x1 = x + (w - len) * r();
    const y1 = y + i * (11 + r() * 6);
    const t = 7 + r() * 7;
    const bow = (r() - 0.5) * 6;
    d += `<path d="M${x1} ${y1}C${x1 + len * 0.3} ${y1 - t + bow} ${x1 + len * 0.7} ${y1 - t - bow} ${x1 + len} ${y1}C${x1 + len * 0.7} ${y1 + t * 0.5} ${x1 + len * 0.3} ${y1 + t * 0.5} ${x1} ${y1}Z"/>`;
  }
  return `<g fill="${fill}" opacity="${opacity}">${d}</g>`;
}

// ---- Distant layers -------------------------------------------------------------------------

// A row of buildings for a back layer. Heights, domes and spires come from the seed, so each
// layer is a different, fixed skyline.
export function skyline({ seed, base, minTop, maxTop, fill, from = -40, to = W + 40, windows = 0, lit = LIT, detail = 1 }) {
  const r = rng(seed);
  let x = from, shapes = '', cuts = '';
  while (x < to) {
    const w = 38 + r() * 90 * detail;
    const top = minTop + r() * (maxTop - minTop);
    shapes += `<rect x="${x.toFixed(1)}" y="${top.toFixed(1)}" width="${(w + 1).toFixed(1)}" height="${(base - top).toFixed(1)}"/>`;
    const kind = r();
    const cx = x + w / 2;
    if (kind < 0.12) {
      // A dome with a finial.
      const dw = w * 0.7;
      shapes += `<path d="M${cx - dw / 2} ${top}A${dw / 2} ${dw * 0.55} 0 0 1 ${cx + dw / 2} ${top}Z"/>`;
      shapes += `<rect x="${cx - 1.2}" y="${top - dw * 0.55 - 16}" width="2.4" height="18"/><circle cx="${cx}" cy="${top - dw * 0.55 - 16}" r="2.6"/>`;
    } else if (kind < 0.2) {
      // A spire.
      shapes += `<path d="M${x + w * 0.25} ${top}L${cx} ${top - w * 1.3}L${x + w * 0.75} ${top}Z"/><rect x="${cx - 0.8}" y="${top - w * 1.3 - 20}" width="1.6" height="22"/>`;
    } else if (kind < 0.36) {
      // A pitched roof.
      shapes += `<path d="M${x - 3} ${top}L${cx} ${top - w * 0.38}L${x + w + 3} ${top}Z"/>`;
    } else if (kind < 0.5) {
      // A stepped top.
      shapes += `<rect x="${x + w * 0.2}" y="${top - 14}" width="${w * 0.6}" height="15"/><rect x="${x + w * 0.38}" y="${top - 26}" width="${w * 0.24}" height="13"/>`;
    } else if (kind < 0.62) {
      // A small water tank on legs.
      const tx = x + w * 0.3, tw = Math.min(26, w * 0.4);
      shapes += `<rect x="${tx}" y="${top - 30}" width="${tw}" height="18" rx="2"/><path d="M${tx - 2} ${top - 30}L${tx + tw / 2} ${top - 42}L${tx + tw + 2} ${top - 30}Z"/>`;
      shapes += `<path d="M${tx + 3} ${top - 12}L${tx + 1} ${top}M${tx + tw - 3} ${top - 12}L${tx + tw - 1} ${top}" stroke="${fill}" stroke-width="2.4"/>`;
    } else if (kind < 0.8) {
      // Chimneys.
      const c = 1 + Math.floor(r() * 3);
      for (let i = 0; i < c; i++) {
        const chx = x + 6 + r() * (w - 18);
        shapes += `<rect x="${chx}" y="${top - 16}" width="9" height="17"/><rect x="${chx - 1.5}" y="${top - 18}" width="12" height="3"/>`;
      }
    }
    if (windows) {
      for (let wy = top + 14; wy < base - 16; wy += 22) {
        for (let wx = x + 8; wx < x + w - 12; wx += 16) {
          if (r() < windows) cuts += `<rect x="${wx.toFixed(1)}" y="${wy.toFixed(1)}" width="6" height="9"/>`;
        }
      }
    }
    x += w - 1;
  }
  return `<g fill="${fill}">${shapes}</g>${cuts ? `<g fill="${lit}" opacity=".85">${cuts}</g>` : ''}`;
}

// ---- Near details, all in ink ---------------------------------------------------------------

// A cornice: the moulded band at a flat roof's edge, with dentils under it.
export function cornice(x1, x2, y) {
  let d = `<rect x="${x1 - 6}" y="${y}" width="${x2 - x1 + 12}" height="9"/><rect x="${x1 - 3}" y="${y + 9}" width="${x2 - x1 + 6}" height="4"/>`;
  for (let x = x1 + 4; x < x2 - 6; x += 13) d += `<rect x="${x}" y="${y + 13}" width="6" height="5"/>`;
  return d;
}

export function chimney(x, y, w = 50, h = 92, pots = 3) {
  let d = `<rect x="${x}" y="${y - h}" width="${w}" height="${h + 2}"/><rect x="${x - 4}" y="${y - h - 6}" width="${w + 8}" height="8"/>`;
  const step = w / pots;
  for (let i = 0; i < pots; i++) {
    const px = x + step * i + step / 2;
    d += `<path d="M${px - 5} ${y - h - 6}L${px - 4} ${y - h - 22}L${px - 7} ${y - h - 26}L${px + 7} ${y - h - 26}L${px + 4} ${y - h - 22}L${px + 5} ${y - h - 6}Z"/>`;
  }
  return d;
}

// Smoke from a chimney pot: a soft, rose-tinted wisp drawn behind the ink.
export function smoke(x, y) {
  return `<path d="M${x} ${y}C${x - 14} ${y - 40} ${x + 24} ${y - 70} ${x + 6} ${y - 110}C${x - 8} ${y - 140} ${x + 30} ${y - 170} ${x + 40} ${y - 200}C${x + 44} ${y - 170} ${x + 12} ${y - 140} ${x + 22} ${y - 112}C${x + 36} ${y - 72} ${x + 4} ${y - 40} ${x + 10} ${y}Z" fill="#e79a8f" opacity=".22"/>`;
}

// A fishbone TV aerial.
export function aerial(x, y, h = 150) {
  let d = `<rect x="${x - 1.6}" y="${y - h}" width="3.2" height="${h}"/>`;
  for (let i = 0; i < 5; i++) {
    const ay = y - h + 10 + i * 13, half = 34 - i * 5;
    d += `<rect x="${x - half}" y="${ay}" width="${half * 2}" height="2.2"/>`;
  }
  d += `<path d="M${x} ${y - h * 0.45}L${x + 46} ${y}" stroke="${INK}" stroke-width="1.6" fill="none"/><path d="M${x} ${y - h * 0.45}L${x - 40} ${y}" stroke="${INK}" stroke-width="1.6" fill="none"/>`;
  return d;
}

// A washing line with clothes pegged on it, sagging between two points.
export function washing(x1, y1, x2, y2, items = ['shirt', 'sock', 'dress', 'sock', 'shirt']) {
  const mx = (x1 + x2) / 2, my = Math.max(y1, y2) + 26;
  let d = `<path d="M${x1} ${y1}Q${mx} ${my} ${x2} ${y2}" stroke="${INK}" stroke-width="1.6" fill="none"/>`;
  const n = items.length;
  items.forEach((it, i) => {
    const t = (i + 1) / (n + 1);
    const px = (1 - t) * (1 - t) * x1 + 2 * (1 - t) * t * mx + t * t * x2;
    const py = (1 - t) * (1 - t) * y1 + 2 * (1 - t) * t * my + t * t * y2;
    if (it === 'shirt') d += `<path d="M${px - 12} ${py}L${px - 20} ${py + 8}L${px - 15} ${py + 13}L${px - 10} ${py + 9}L${px - 10} ${py + 30}L${px + 10} ${py + 30}L${px + 10} ${py + 9}L${px + 15} ${py + 13}L${px + 20} ${py + 8}L${px + 12} ${py}C${px + 6} ${py + 5} ${px - 6} ${py + 5} ${px - 12} ${py}Z"/>`;
    if (it === 'sock') d += `<path d="M${px - 4} ${py}L${px + 3} ${py}L${px + 3} ${py + 15}C${px + 3} ${py + 19} ${px + 8} ${py + 19} ${px + 10} ${py + 21}C${px + 10} ${py + 25} ${px - 4} ${py + 25} ${px - 4} ${py + 18}Z"/>`;
    if (it === 'dress') d += `<path d="M${px - 7} ${py}L${px + 7} ${py}L${px + 8} ${py + 12}L${px + 16} ${py + 38}L${px - 16} ${py + 38}L${px - 8} ${py + 12}Z"/>`;
  });
  return d;
}

// A water tower: a barrel tank on braced legs, with a conical cap. The hoops are cut out,
// so the sky shows through them.
export function waterTower(cx, roof, { w = 118, legs = 132, tank = 96 } = {}) {
  const tb = roof - legs, tt = tb - tank, x1 = cx - w / 2, x2 = cx + w / 2;
  let d = '';
  // Legs and bracing.
  const lx = [x1 + 8, cx - 12, cx + 12, x2 - 8];
  const fx = [x1 - 6, cx - 16, cx + 16, x2 + 6];
  lx.forEach((x, i) => { d += `<path d="M${x - 3} ${tb}L${fx[i] - 3} ${roof}L${fx[i] + 3} ${roof}L${x + 3} ${tb}Z"/>`; });
  for (let k = 0; k < 2; k++) {
    const ya = tb + legs * (k * 0.5), yb = tb + legs * (k * 0.5 + 0.5);
    const xa1 = x1 + 8 - 14 * (k * 0.5), xa2 = x2 - 8 + 14 * (k * 0.5);
    const xb1 = x1 + 8 - 14 * (k * 0.5 + 0.5), xb2 = x2 - 8 + 14 * (k * 0.5 + 0.5);
    d += `<path d="M${xa1} ${ya}L${xb2} ${yb}M${xa2} ${ya}L${xb1} ${yb}M${xb1} ${yb}L${xb2} ${yb}" stroke="${INK}" stroke-width="3.2" fill="none"/>`;
  }
  // Tank, slightly barrelled.
  d += `<path d="M${x1} ${tb}C${x1 - 5} ${tb - tank * 0.35} ${x1 - 5} ${tt + tank * 0.35} ${x1} ${tt}L${x2} ${tt}C${x2 + 5} ${tt + tank * 0.35} ${x2 + 5} ${tb - tank * 0.35} ${x2} ${tb}Z"/>`;
  d += `<rect x="${x1 - 6}" y="${tb - 2}" width="${w + 12}" height="8"/>`;
  // Cap and finial.
  d += `<path d="M${x1 - 10} ${tt + 4}L${cx} ${tt - w * 0.42}L${x2 + 10} ${tt + 4}Z"/>`;
  d += `<rect x="${cx - 1.5}" y="${tt - w * 0.42 - 26}" width="3" height="28"/><circle cx="${cx}" cy="${tt - w * 0.42 - 27}" r="4"/>`;
  // The hoops are cut out of the tank, so the sky shows through them.
  const id = `hoops${Math.round(cx)}`;
  const hoops = [0.24, 0.5, 0.76].map(f => `<path d="M${x1 - 6} ${tt + tank * f}Q${cx} ${tt + tank * f + 6} ${x2 + 6} ${tt + tank * f}" stroke="#000" stroke-width="2.4" fill="none"/>`).join('');
  const shape = `<defs><mask id="${id}" maskUnits="userSpaceOnUse" x="0" y="0" width="${W}" height="${H}"><rect width="${W}" height="${H}" fill="#fff"/>${hoops}</mask></defs><g mask="url(#${id})">${d}</g>`;
  return { shape, top: tt - w * 0.42 - 31, tankTop: tt, tankBottom: tb };
}

// A ledge the cat can stand on: an ink slab whose top edge catches the sky's glow, with a soft
// shadow under it. `y` is its top.
export function ledge(x, y, w) {
  const h = 18;
  return `<g class="ledge">
    <rect x="${x + 6}" y="${y + h}" width="${w - 12}" height="10" rx="5" fill="${INK}" opacity=".28"/>
    <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="4" fill="${INK}"/>
    <rect x="${x + 4}" y="${y}" width="${w - 8}" height="3" rx="1.5" fill="${LIT}" opacity=".7"/>
  </g>`;
}

export function birds(x1, y1, x2, y2, at = [0.3, 0.42, 0.7]) {
  const mx = (x1 + x2) / 2, my = Math.max(y1, y2) + 18;
  let d = `<path d="M${x1} ${y1}Q${mx} ${my} ${x2} ${y2}" stroke="${INK}" stroke-width="1.4" fill="none"/>`;
  at.forEach((t, i) => {
    const px = (1 - t) * (1 - t) * x1 + 2 * (1 - t) * t * mx + t * t * x2;
    const py = (1 - t) * (1 - t) * y1 + 2 * (1 - t) * t * my + t * t * y2;
    const f = i % 2 ? -1 : 1;
    d += `<g transform="translate(${px} ${py}) scale(${f} 1)"><path d="M-7 -1C-7 -9 1 -12 5 -8L10 -9L6 -6C7 -2 4 1 -1 1L-9 4Z"/><path d="M0 0L0 2.4" stroke="${INK}" stroke-width="1"/></g>`;
  });
  return d;
}

// Lit windows on a facade, in rows, some dark.
export function facadeWindows(x1, x2, top, seed, { cols = 0, lit = 0.55, w = 14, h = 22, gapX = 30, gapY = 44 } = {}) {
  const r = rng(seed);
  let d = '';
  for (let y = top; y < H; y += gapY) {
    for (let x = x1 + 18; x < x2 - 20; x += gapX) {
      if (r() < lit) {
        d += `<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${w}" height="${h}" rx="1.5"/>`;
      }
    }
  }
  return `<g fill="${LIT}">${d}</g>`;
}

export function hud({ level, name, lives = 9 }) {
  // A small cat's head for the lives counter.
  const head = (x, y) => `<path d="M${x - 11} ${y + 9}C${x - 13} ${y + 1} ${x - 12} ${y - 5} ${x - 10} ${y - 8}L${x - 11} ${y - 17}L${x - 4} ${y - 11}C${x - 1.4} ${y - 12} ${x + 1.4} ${y - 12} ${x + 4} ${y - 11}L${x + 11} ${y - 17}L${x + 10} ${y - 8}C${x + 12} ${y - 5} ${x + 13} ${y + 1} ${x + 11} ${y + 9}C${x + 6} ${y + 13} ${x - 6} ${y + 13} ${x - 11} ${y + 9}Z"/>`;
  return `
  <g class="hud" fill="${CREAM}">
    <text x="58" y="62" font-family="Futura, 'Avenir Next', sans-serif" font-size="15" font-weight="500" letter-spacing="5" opacity=".7">LEVEL ${level}</text>
    <text x="56" y="100" font-family="'Iowan Old Style', Baskerville, serif" font-style="italic" font-size="32" opacity=".95">${name}</text>
    <g opacity=".92">${head(W - 118, 70)}</g>
    <text x="${W - 96}" y="80" font-family="'Iowan Old Style', Baskerville, serif" font-size="28" opacity=".95">× ${lives}</text>
  </g>`;
}

export { cat, CREAM, LIT, MID, FAR, HAZE };
