// The levels, each one composed from the pieces in scene.js.
import {
  W, H, INK, sky, stars, moon, wisps, skyline, cornice, chimney, smoke, aerial, waterTower, ledge,
  hud, cat, rng, LIT, MID, FAR,
} from './scene.js';

// Sky, stars, clouds, the moon and the two distant skylines, shared by every level. With no
// `moonAt` there is no moon, and `city: false` leaves out the skylines.
function backdrop({ moonAt = null, city = true, seed }) {
  const sky0 = `
  ${sky()}
  ${stars(seed, 110, 520)}
  ${wisps(90, 300, 460, '#f0a08a', 0.22, seed + 1)}
  ${wisps(880, 430, 380, '#ffc58a', 0.26, seed + 2)}
  ${moonAt ? moon(moonAt[0], moonAt[1], moonAt[2]) : ''}`;
  if (!city) return sky0;
  return `${sky0}
  ${skyline({ seed: seed + 3, base: H, minTop: 640, maxTop: 730, fill: FAR, windows: 0.05, detail: 0.9 })}
  <defs><linearGradient id="mist" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#f6955a" stop-opacity="0"/><stop offset="1" stop-color="#f6955a" stop-opacity=".38"/>
  </linearGradient></defs>
  <rect x="0" y="640" width="${W}" height="${H - 640}" fill="url(#mist)"/>
  ${skyline({ seed: seed + 4, base: H, minTop: 740, maxTop: 820, fill: MID, windows: 0.1, detail: 1.1 })}`;
}

// A near building: a flat roof with a cornice, and a facade of lit and dark windows below.
function building(x1, x2, roof, seed, { lit = 0.35, windowRows = 6 } = {}) {
  const r = rng(seed);
  let shape = `<rect x="${x1}" y="${roof}" width="${x2 - x1}" height="${H - roof + 2}"/>${cornice(x1, x2, roof)}`;
  let lights = '';
  const cols = Math.max(2, Math.floor((x2 - x1 - 40) / 58));
  const step = (x2 - x1 - 40) / cols;
  for (let row = 0; row < windowRows; row++) {
    const y = roof + 58 + row * 74;
    if (y > H - 30) break;
    for (let c = 0; c < cols; c++) {
      if (r() > lit) continue;
      const x = x1 + 20 + step * c + (step - 26) / 2;
      // A lit window: amber glass, split into four panes by an ink cross.
      lights += `<rect x="${x}" y="${y}" width="26" height="40" rx="2" fill="${LIT}"/>`;
      lights += `<rect x="${x + 12}" y="${y}" width="2.4" height="40" fill="${INK}"/><rect x="${x}" y="${y + 18}" width="26" height="2.4" fill="${INK}"/>`;
      if (r() < 0.4) lights += `<rect x="${x}" y="${y}" width="26" height="${8 + r() * 14}" fill="${INK}" opacity=".85"/>`;
    }
  }
  return { shape, lights };
}

// A railing along a roof edge.
function railing(x1, x2, roof) {
  let d = `<rect x="${x1}" y="${roof - 26}" width="${x2 - x1}" height="3"/>`;
  for (let x = x1; x <= x2; x += 14) d += `<rect x="${x - 1}" y="${roof - 26}" width="2" height="26"/>`;
  return d;
}

// A mansard roof with dormer windows, the tall building on the right.
function mansard(x1, x2, roof, height, seed) {
  const r = rng(seed);
  const inset = 40;
  let shape = `<path d="M${x1} ${roof}L${x1 + inset} ${roof - height}L${x2 - inset} ${roof - height}L${x2} ${roof}Z"/>`;
  shape += `<rect x="${x1 + inset - 8}" y="${roof - height - 8}" width="${x2 - x1 - 2 * inset + 16}" height="9"/>`;
  let lights = '';
  const n = Math.floor((x2 - x1 - 2 * inset) / 90);
  for (let i = 0; i < n; i++) {
    const cx = x1 + inset + 45 + i * ((x2 - x1 - 2 * inset - 90) / Math.max(1, n - 1));
    const dy = roof - height * 0.62;
    shape += `<path d="M${cx - 24} ${dy + 52}L${cx - 24} ${dy}L${cx} ${dy - 26}L${cx + 24} ${dy}L${cx + 24} ${dy + 52}Z"/>`;
    if (r() < 0.6) lights += `<path d="M${cx - 12} ${dy + 44}L${cx - 12} ${dy + 8}Q${cx} ${dy - 6} ${cx + 12} ${dy + 8}L${cx + 12} ${dy + 44}Z" fill="${LIT}"/><rect x="${cx - 1.2}" y="${dy + 2}" width="2.4" height="42" fill="${INK}"/>`;
  }
  return { shape, lights };
}

// Level 4: the cat's roof on the left, a gap, and two roofs beyond it. What else stands in the
// scene is `layout`, which level4.json holds: the moon, the city behind, a water tower and ledges.
export const roofs = [
  { from: -10, to: 520, top: 720 },
  { from: 706, to: 1080, top: 700 },
  // The mansard's flat top.
  { from: 1120, to: 1570, top: 550 },
];

export function roofUnder(x) {
  return roofs.find(r => x >= r.from && x <= r.to) || null;
}

export function level4(layout = {}, { showHud = false } = {}) {
  const { moon: moonAt = null, city = false, waterTower: towerAt = null, ledges = [] } = layout;
  const a = building(-10, 520, 720, 41, { lit: 0.3 });
  const b = building(706, 1080, 700, 42, { lit: 0.32 });
  const c = building(1080, 1610, 660, 43, { lit: 0.28 });
  const m = mansard(1080, 1610, 660, 110, 44);
  const roof = towerAt ? roofUnder(towerAt.x) : null;
  const tower = roof ? waterTower(towerAt.x, roof.top, { w: 124, legs: 128, tank: 100 }) : null;
  const near = `
  <g fill="${INK}">
    ${a.shape}
    ${chimney(96, 720, 56, 96, 3)}
    ${aerial(300, 720, 168)}
    ${b.shape}
    ${railing(716, 1072, 700)}
    ${tower ? tower.shape : ''}
    ${c.shape}
    ${m.shape}
    ${chimney(1470, 550, 44, 70, 2)}
  </g>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid slice">
  ${backdrop({ moonAt, city, seed: 4 })}
  ${smoke(122, 598)}
  ${near}
  <g>${a.lights}${b.lights}${c.lights}${m.lights}</g>
  ${ledges.map(([x, y, w]) => ledge(x, y, w)).join('')}
  ${cat(448, 720, 164)}
  <rect width="${W}" height="${H}" fill="url(#edges)"/>
  ${showHud ? hud({ level: 4, name: 'Across the Gap', lives: 7 }) : ''}
  </svg>`;
}

// A clock tower: a tall shaft, a clock face cut out, and a pointed roof with a finial.
function clockTower(cx, base, { w = 150, h = 430 } = {}) {
  const x1 = cx - w / 2, top = base - h;
  const id = `clock${Math.round(cx)}`;
  let d = `<rect x="${x1}" y="${top}" width="${w}" height="${h + 2}"/>`;
  d += `<rect x="${x1 - 10}" y="${top - 10}" width="${w + 20}" height="14"/>`;
  d += `<path d="M${x1 - 4} ${top - 10}L${cx} ${top - w * 1.15}L${x1 + w + 4} ${top - 10}Z"/>`;
  d += `<rect x="${cx - 2}" y="${top - w * 1.15 - 40}" width="4" height="42"/><circle cx="${cx}" cy="${top - w * 1.15 - 42}" r="6"/>`;
  // Corner pinnacles.
  for (const px of [x1 - 6, x1 + w + 6]) d += `<path d="M${px - 8} ${top - 8}L${px} ${top - 58}L${px + 8} ${top - 8}Z"/>`;
  // Tall louvred windows below the clock.
  let cuts = '';
  for (const wx of [cx - 34, cx + 14]) cuts += `<path d="M${wx} ${top + 250}L${wx} ${top + 176}Q${wx + 10} ${top + 162} ${wx + 20} ${top + 176}L${wx + 20} ${top + 250}Z" fill="#000"/>`;
  const face = `<circle cx="${cx}" cy="${top + 88}" r="${w * 0.33}" fill="#000"/>`;
  const hands = `<path d="M${cx} ${top + 88}L${cx} ${top + 88 - w * 0.24}M${cx} ${top + 88}L${cx + w * 0.16} ${top + 88 + w * 0.06}" stroke="#fff" stroke-width="5" stroke-linecap="round"/><circle cx="${cx}" cy="${top + 88}" r="5" fill="#fff"/>`;
  return `<defs><mask id="${id}" maskUnits="userSpaceOnUse" x="0" y="0" width="${W}" height="${H}"><rect width="${W}" height="${H}" fill="#fff"/>${face}${hands}${cuts}</mask></defs><g mask="url(#${id})">${d}</g>`;
}

// Level 3, the bug: the moon is drawn in front of the clock tower, half over the sky and half
// over the stone. The fixed version draws the moon before the tower.
export function level3({ fixed = false } = {}) {
  const a = building(-10, 640, 760, 31, { lit: 0.3 });
  const b = building(640, 1610, 800, 32, { lit: 0.26 });
  const tower = clockTower(1010, 800, { w: 156, h: 440 });
  const moonAt = [1100, 300, 70];
  const near = `
  <g fill="${INK}">
    ${a.shape}
    ${chimney(170, 760, 50, 84, 3)}
    ${chimney(520, 760, 40, 64, 2)}
    ${b.shape}
    ${tower}
    ${aerial(1380, 800, 150)}
  </g>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid slice">
  ${backdrop({ moonAt: fixed ? moonAt : [-400, -400, 1], seed: 11 })}
  ${smoke(194, 668)}
  ${near}
  ${fixed ? '' : moon(...moonAt)}
  <g>${a.lights}${b.lights}</g>
  ${cat(560, 760, 170)}
  <rect width="${W}" height="${H}" fill="url(#edges)"/>
  ${hud({ level: 3, name: 'The Clock Tower', lives: 8 })}
  </svg>`;
}

// Level 2: a water tower to climb on the next roof.
export function level2() {
  const a = building(-10, 560, 790, 21, { lit: 0.32 });
  const b = building(620, 1610, 720, 22, { lit: 0.28 });
  const tower = waterTower(1180, 720, { w: 130, legs: 150, tank: 104 });
  const near = `
  <g fill="${INK}">
    ${a.shape}
    ${chimney(380, 790, 60, 90, 3)}
    ${b.shape}
    ${railing(630, 1600, 720)}
    ${tower.shape}
    ${aerial(820, 720, 140)}
  </g>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid slice">
  ${backdrop({ moonAt: [470, 250, 58], seed: 23 })}
  ${smoke(410, 694)}
  ${near}
  <g>${a.lights}${b.lights}</g>
  ${cat(250, 790, 160)}
  <rect width="${W}" height="${H}" fill="url(#edges)"/>
  ${hud({ level: 2, name: 'The Water Tower', lives: 9 })}
  </svg>`;
}
