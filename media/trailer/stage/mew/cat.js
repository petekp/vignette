// Mew, the cat: one cut-paper silhouette, sitting, facing right and looking up.
// Drawn in a 100 x 100 box with the paws on y = 100. The eye is cut out, so whatever is behind
// the cat shows through it, and the whiskers are fine strokes off the muzzle.

export const CAT_BODY = `
M 32 100
C 21 100 17 93 18 85
C 19 74 26 64 36 57
C 43 52 47 46 50 39
C 53 33 56 28.6 58.8 25.4
C 58.2 22.6 58.2 20.2 59 18
L 57.6 3.6
L 66 11.4
C 68.6 10.6 71.2 10.4 73.6 10.8
L 80.6 2.4
L 80.4 15.6
C 82.8 17.2 85 19.2 86.8 21.2
C 88 22.6 88.2 24 87.2 25
C 85.8 26.4 83.4 27 81.4 27.4
C 79.4 27.8 78.2 29.2 78 31.2
C 77.8 35 79.6 39 80.8 44
C 81.8 49 81.4 55 80.2 61
C 79 68 78.4 80 78.6 90
C 78.7 95 79.2 98 82.2 98.8
C 84.2 99.3 84 100 82.2 100
L 32 100 Z`;

// Fine cuts inside the silhouette: the line of the thigh, and the back of the front leg.
export const CAT_CUTS = [
  `M 64 99.6 C 63.4 88 57 77.6 45.6 73`,
  `M 73.6 66 C 73.1 77 73.1 89 73.8 99.6`,
];

// The tail is cut as its own shape so it can taper to a point, which a stroke can't.
export const CAT_TAIL = `
M 26 99.2
C 14 99.8 4 99 -1 94
C -6 89 -7 80 -3 73.6
C -1.6 71.4 0.6 71.4 0.4 73.2
C -1.8 79 -1 86 3.4 90.6
C 8 95 16 96.4 26 96.4 Z`;

// The eye, an almond turned up toward the moon, and three whiskers off the muzzle.
export const CAT_EYE = `M 72.6 18.6 C 75 16.2 78.4 16 80.4 18.2 C 78 20.4 74.8 20.8 72.6 18.6 Z`;
export const CAT_WHISKERS = [
  `M 84.6 23.4 C 90 21.2 95 20.2 100 20.4`,
  `M 85 24.6 C 90.4 24 95.4 24.4 100.2 25.8`,
  `M 84.4 25.8 C 88.8 27.2 92.8 29.2 96.4 31.8`,
];

let catCount = 0;
// Returns SVG for the cat at (x, y) = where its paws touch down, at the given height in px.
export function cat(x, y, height, { fill = '#0b0509', flip = false } = {}) {
  const id = `catcut${catCount++}`;
  const s = height / 100;
  const t = `translate(${x} ${y}) scale(${flip ? -s : s} ${s}) translate(-60 -100)`;
  return `
  <defs><mask id="${id}" maskUnits="userSpaceOnUse" x="-20" y="-10" width="140" height="120">
    <rect x="-20" y="-10" width="140" height="120" fill="#fff"/>
    <path d="${CAT_EYE}" fill="#000"/>
    ${CAT_CUTS.map(d => `<path d="${d}" fill="none" stroke="#000" stroke-width="0.9" stroke-linecap="round"/>`).join('')}
  </mask></defs>
  <g transform="${t}" fill="${fill}">
    <path d="${CAT_BODY}" mask="url(#${id})"/>
    ${CAT_WHISKERS.map(d => `<path d="${d}" fill="none" stroke="${fill}" stroke-width="0.8" stroke-linecap="round"/>`).join('')}
    <path d="${CAT_TAIL}"/>
  </g>`;
}
