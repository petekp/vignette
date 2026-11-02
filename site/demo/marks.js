// Marks, drawn as the app's renderer draws them (MarkRendering.swift), in image px, and the
// numbers they are drawn with (MarkStyle, NoteTag, NoteBadge).

export const MARK = {
  person: "#e03131", agent: "#364fc7", edge: "#ffffff",
  stroke: 3.5, edgeWidth: 1.5, arrowLength: 4.5, arrowWidth: 4,
  textSize: 17, agentTextSize: 0.0133, lineHeight: 1.32,
  padTop: 0.42, padBottom: 0.47, padSide: 0.8, maxWidth: 18, noteGap: 8,
  badgeHeight: 1.36, badgeLabel: 0.75, badgeLogo: 0.79, badgeGap: 0.32,
  badgeLead: 0.5, badgeTrail: 0.57, badgeInset: 0.35, badgeOverlap: 0.2,
};
export const FONT = {
  person: 'ui-rounded, "SF Pro Rounded", system-ui, -apple-system, sans-serif',
  agent: 'ui-monospace, "SF Mono", Menlo, monospace',
  ui: 'system-ui, -apple-system, "Helvetica Neue", sans-serif',
};
// Resolved from this file, so a page in another folder (the share image's) finds it.
export const CLAUDE_SVG = new URL("claude.svg", import.meta.url).href;
export const POINT_SCALE = 2; // the screenshots are 2x captures: image px per point
export const escapeXML = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

// Text is measured the way it is drawn, as SVG text in this document, so a tag fits its words in
// whatever font the browser resolves the family to.
export const SVG_NS = "http://www.w3.org/2000/svg";
const ruler = document.createElementNS(SVG_NS, "svg");
ruler.setAttribute("aria-hidden", "true");
ruler.style.cssText = "position:absolute;width:0;height:0;overflow:hidden;visibility:hidden";
const rulerText = document.createElementNS(SVG_NS, "text");
rulerText.setAttribute("font-weight", "600");
rulerText.setAttribute("text-rendering", "geometricPrecision");
ruler.append(rulerText);
document.body.append(ruler);
const widths = new Map();
function textWidth(text, size, family) {
  const key = `${size}|${family}|${text}`;
  if (!widths.has(key)) {
    rulerText.setAttribute("font-size", size);
    rulerText.setAttribute("font-family", family);
    rulerText.textContent = text;
    widths.set(key, rulerText.getComputedTextLength());
  }
  return widths.get(key);
}

function noteStyle(mark, image) {
  const agent = mark.who === "agent";
  const size = agent ? Math.round(image.w * MARK.agentTextSize) : MARK.textSize * POINT_SCALE;
  return { agent, size, family: agent ? FONT.agent : FONT.person, color: agent ? MARK.agent : MARK.person };
}

function wrap(text, size, family, max) {
  const lines = [];
  for (const para of text.split("\n")) {
    let line = "";
    for (const word of para.split(" ")) {
      const next = line ? `${line} ${word}` : word;
      if (line && textWidth(next, size, family) > max) { lines.push(line); line = word; } else line = next;
    }
    lines.push(line);
  }
  return lines;
}

// The tag's box and its lines, from TextLayout: padding in multiples of the size, 18 em at most.
function noteLayout(mark, image) {
  const st = noteStyle(mark, image);
  const { size, family } = st;
  const max = Math.min(MARK.maxWidth * size, image.w - mark.x - MARK.padSide * size * 2);
  const lines = wrap(mark.text || "", size, family, Math.max(size * 3, max));
  const inner = Math.max(size * 0.5, ...lines.map((l) => textWidth(l, size, family)));
  let badge = null;
  if (st.agent) {
    const label = mark.agentName || "Claude";
    const labelWidth = textWidth(label, size * MARK.badgeLabel, FONT.ui);
    const width = size * (MARK.badgeLead + MARK.badgeLogo + MARK.badgeGap + MARK.badgeTrail) + labelWidth;
    badge = { label, width, height: size * MARK.badgeHeight, inset: size * MARK.badgeInset, overlap: size * MARK.badgeOverlap };
  }
  let w = inner + 2 * MARK.padSide * size;
  if (badge) w = Math.max(w, badge.inset + MARK.padSide * size + badge.width);
  const lh = MARK.lineHeight * size;
  const h = lines.length * lh + (MARK.padTop + MARK.padBottom) * size;
  // The tag is kept inside the image, as TextLayout keeps it.
  const x = Math.max(0, Math.min(mark.x, image.w - w)), y = Math.max(0, Math.min(mark.y, image.h - h));
  return { ...st, lines, lh, w, h, badge, x, y };
}

export function markBounds(mark, image) {
  if (mark.type === "rect") return { x: mark.x, y: mark.y, w: mark.w, h: mark.h };
  if (mark.type === "arrow") {
    const pts = [[mark.x1, mark.y1], ...(mark.via || []), [mark.x2, mark.y2]];
    const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
    const x = Math.min(...xs), y = Math.min(...ys);
    return { x, y, w: Math.max(...xs) - x, h: Math.max(...ys) - y };
  }
  const l = noteLayout(mark, image);
  return { x: l.x, y: l.y, w: l.w, h: l.h };
}

// A freehand arrow's body, as ArrowBody.Curve makes it (MarkGeometry.swift): a centripetal
// Catmull-Rom curve through its ends and its `via` points, sampled about every 2 px.
function curveSamples(knots) {
  const n = knots.length;
  const knot = (i) => i < 0 ? [2 * knots[0][0] - knots[1][0], 2 * knots[0][1] - knots[1][1]]
    : i >= n ? [2 * knots[n - 1][0] - knots[n - 2][0], 2 * knots[n - 1][1] - knots[n - 2][1]] : knots[i];
  const root = (a, b) => Math.sqrt(Math.hypot(b[0] - a[0], b[1] - a[1]));
  // Yuksel, Schaefer and Keyser's conversion, with `near` and `far` the square roots of the chords.
  const control = (p0, p1, p2, near, far) => {
    if (near <= 1e-9) return p1;
    const a = near * near, b = far * far, d = 3 * near * (near + far), c = 2 * a + 3 * near * far + b;
    return [(a * p2[0] - b * p0[0] + c * p1[0]) / d, (a * p2[1] - b * p0[1] + c * p1[1]) / d];
  };
  const samples = [knots[0]], lengths = [0];
  for (let i = 0; i < n - 1; i++) {
    const p0 = knot(i - 1), p1 = knot(i), p2 = knot(i + 1), p3 = knot(i + 2);
    const d1 = root(p0, p1), d2 = root(p1, p2), d3 = root(p2, p3);
    const seg = [p1, control(p0, p1, p2, d1, d2), control(p3, p2, p1, d3, d2), p2];
    const poly = seg.slice(1).reduce((t, q, j) => t + Math.hypot(q[0] - seg[j][0], q[1] - seg[j][1]), 0);
    const steps = Math.max(8, Math.ceil(poly / 2));
    for (let k = 1; k <= steps; k++) {
      const t = k / steps, u = 1 - t;
      const q = [0, 1].map((c) => u * u * u * seg[0][c] + 3 * u * u * t * seg[1][c] + 3 * u * t * t * seg[2][c] + t * t * t * seg[3][c]);
      const last = samples[samples.length - 1];
      lengths.push(lengths[lengths.length - 1] + Math.hypot(q[0] - last[0], q[1] - last[1]));
      samples.push(q);
    }
  }
  return { samples, lengths };
}

const SHADOW_SHAPE = (px) => `drop-shadow(0 ${0.5 * px}px ${1 * px}px rgba(0,0,0,.28))`;

// A freehand arrow, as Arrowhead places its head on a curve (MarkRendering.swift): the head is aimed
// from the point on the body one head-length back from the tip, and the stroke stops there.
function freehandArrowSVG(mark, color, stroke, edge, px) {
  const tip = [mark.x2, mark.y2];
  const { samples, lengths } = curveSamples([[mark.x1, mark.y1], ...mark.via, tip]);
  const total = lengths[lengths.length - 1];
  const reachable = samples.reduce((m, p) => Math.max(m, Math.hypot(p[0] - tip[0], p[1] - tip[1])), 0);
  const hl = Math.min(MARK.arrowLength * stroke, total * 0.5, reachable);
  const hw = (MARK.arrowWidth * stroke * hl) / (MARK.arrowLength * stroke) / 2;
  let i = samples.length - 1;
  while (i > 0 && Math.hypot(samples[i - 1][0] - tip[0], samples[i - 1][1] - tip[1]) < hl) i--;
  const a = samples[Math.max(0, i - 1)], b = samples[i];
  const d = [b[0] - a[0], b[1] - a[1]], w = [a[0] - tip[0], a[1] - tip[1]];
  const qa = d[0] * d[0] + d[1] * d[1], qb = 2 * (w[0] * d[0] + w[1] * d[1]), qc = w[0] * w[0] + w[1] * w[1] - hl * hl;
  const u = qa > 0 ? Math.min(Math.max((-qb - Math.sqrt(Math.max(0, qb * qb - 4 * qa * qc))) / (2 * qa), 0), 1) : 0;
  const from = [a[0] + d[0] * u, a[1] + d[1] * u];
  const reach = Math.hypot(tip[0] - from[0], tip[1] - from[1]) || 1;
  const ux = (tip[0] - from[0]) / reach, uy = (tip[1] - from[1]) / reach;
  const bx = tip[0] - ux * hl, by = tip[1] - uy * hl;
  const head = `${tip[0]},${tip[1]} ${bx - uy * hw},${by + ux * hw} ${bx + uy * hw},${by - ux * hw}`;
  const body = [...samples.slice(0, Math.max(1, i)), from].map((p) => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(" ");
  return `<g style="filter:${SHADOW_SHAPE(px)}" stroke-linecap="round" stroke-linejoin="round" fill="none">
      <polyline points="${body}" stroke="${MARK.edge}" stroke-width="${stroke + 2 * edge}"/>
      <polygon points="${head}" fill="${MARK.edge}" stroke="${MARK.edge}" stroke-width="${2 * edge}"/>
      <polyline points="${body}" stroke="${color}" stroke-width="${stroke}"/>
      <polygon points="${head}" fill="${color}"/></g>`;
}

function markSVG(mark, image, { caret = false } = {}) {
  const px = POINT_SCALE;
  const color = mark.who === "agent" ? MARK.agent : MARK.person;
  const stroke = MARK.stroke * px, edge = MARK.edgeWidth * px;
  if (mark.type === "rect") {
    const { x, y, w, h } = mark;
    return `<g style="filter:${SHADOW_SHAPE(px)}">
      <rect x="${x}" y="${y}" width="${w}" height="${h}" fill="none" stroke="${MARK.edge}" stroke-width="${stroke + 2 * edge}" stroke-linejoin="round"/>
      <rect x="${x}" y="${y}" width="${w}" height="${h}" fill="none" stroke="${color}" stroke-width="${stroke}" stroke-linejoin="round"/></g>`;
  }
  if (mark.type === "arrow" && mark.via?.length) return freehandArrowSVG(mark, color, stroke, edge, px);
  if (mark.type === "arrow") {
    const { x1, y1, x2, y2 } = mark;
    const len = Math.hypot(x2 - x1, y2 - y1) || 1;
    const ux = (x2 - x1) / len, uy = (y2 - y1) / len;
    const hl = Math.min(MARK.arrowLength * stroke, len * 0.6), hw = (MARK.arrowWidth * stroke * hl) / (MARK.arrowLength * stroke) / 2;
    const bx = x2 - ux * hl, by = y2 - uy * hl;
    const head = `${x2},${y2} ${bx - uy * hw},${by + ux * hw} ${bx + uy * hw},${by - ux * hw}`;
    const sx = x2 - ux * hl * 0.8, sy = y2 - uy * hl * 0.8;
    return `<g style="filter:${SHADOW_SHAPE(px)}" stroke-linecap="round" stroke-linejoin="round">
      <line x1="${x1}" y1="${y1}" x2="${sx}" y2="${sy}" stroke="${MARK.edge}" stroke-width="${stroke + 2 * edge}"/>
      <polygon points="${head}" fill="${MARK.edge}" stroke="${MARK.edge}" stroke-width="${2 * edge}"/>
      <line x1="${x1}" y1="${y1}" x2="${sx}" y2="${sy}" stroke="${color}" stroke-width="${stroke}"/>
      <polygon points="${head}" fill="${color}"/></g>`;
  }
  // A note: the tag, its white edge, NoteTag's two shadows, an agent's badge, and the words.
  const l = noteLayout(mark, image);
  const r = Math.min(l.h / 2, (l.lh + (MARK.padTop + MARK.padBottom) * l.size) / 2);
  const s = l.size;
  const shadows = `drop-shadow(0 ${0.18 * s}px ${0.59 * s}px rgba(0,0,0,.14)) drop-shadow(0 ${0.03 * s}px ${0.06 * s}px rgba(0,0,0,.22))`;
  let out = `<g style="filter:${shadows}">
    <rect x="${l.x - edge}" y="${l.y - edge}" width="${l.w + 2 * edge}" height="${l.h + 2 * edge}" rx="${r + edge}" fill="${MARK.edge}"/>
    <rect x="${l.x}" y="${l.y}" width="${l.w}" height="${l.h}" rx="${r}" fill="${l.color}"/></g>`;
  if (l.badge) {
    const b = l.badge, bx = l.x + b.inset, by = l.y - (b.height - b.overlap);
    const logo = s * MARK.badgeLogo;
    out += `<g style="filter:drop-shadow(0 ${0.05 * s}px ${0.2 * s}px rgba(0,0,0,.16))">
      <rect x="${bx}" y="${by}" width="${b.width}" height="${b.height}" rx="${b.height / 2}" fill="#fff" stroke="rgba(0,0,0,.22)" stroke-width="${0.054 * s}"/></g>
      <image href="${CLAUDE_SVG}" x="${bx + s * MARK.badgeLead}" y="${by + (b.height - logo) / 2}" width="${logo}" height="${logo}"/>
      <text x="${bx + s * (MARK.badgeLead + MARK.badgeLogo + MARK.badgeGap)}" y="${by + b.height / 2}" dominant-baseline="central"
        font-family='${FONT.ui}' font-weight="600" text-rendering="geometricPrecision" font-size="${s * MARK.badgeLabel}" fill="rgba(0,0,0,.85)">${escapeXML(b.label)}</text>`;
  }
  const tx = l.x + MARK.padSide * s;
  l.lines.forEach((line, i) => {
    const ty = l.y + MARK.padTop * s + (i + 0.5) * l.lh;
    out += `<text x="${tx}" y="${ty}" dominant-baseline="central" font-family='${l.family}' font-weight="600" text-rendering="geometricPrecision" font-size="${s}" fill="#fff" xml:space="preserve">${escapeXML(line)}</text>`;
  });
  if (caret) {
    const last = l.lines[l.lines.length - 1] || "";
    const cx = tx + textWidth(last, s, l.family) + s * 0.06;
    const cy = l.y + MARK.padTop * s + (l.lines.length - 1) * l.lh + l.lh * 0.14;
    out += `<rect class="caret" x="${cx}" y="${cy}" width="${Math.max(2, s * 0.08)}" height="${l.lh * 0.72}" rx="1" fill="#fff"/>`;
  }
  return out;
}

export function marksSVG(marks, image, typing = null) {
  return marks.map((m) => markSVG(m, image, { caret: m === typing })).join("");
}
