// The page's demos: Vignette's stack, flights, annotator and marks, rebuilt with the app's own
// numbers (UITweaks, MarkStyle, NoteTag, NoteBadge). Every stage is a Mac screen 1440 by 900
// points, scaled to fit, so a size here is a size in the app.

const SCREEN = { w: 1440, h: 900, menu: 25 };
const UI = {
  cardMaxWidth: 188, cardMaxHeight: 153, cardMinSide: 120, cardSpacing: 10, screenMargin: 17,
  cardCorner: 16, hoverScale: 1.06, stackMinScale: 0.5, stackGap: 24,
  slideIn: 0.3, slideOut: 0.15, stagger: 0.07, staggerMax: 0.3, relayout: 0.25, shiftUp: 0.3,
  expand: 0.35, flightBounce: 0.15, flightArc: 0.15, flightArcMax: 64, flightDepth: 0.07,
  backdropWidth: 180, backdropFade: 0.25, dimFade: 0.4,
  annotationMinWidth: 770, annotationMinHeight: 320, annotationCorner: 16, toolbarGap: 9,
  screenInset: 60, toolbarHeight: 40, noticeSeconds: 1.7, thumbnailSeconds: 5,
};
const MARK = {
  person: "#e03131", agent: "#364fc7", edge: "#ffffff",
  stroke: 3.5, edgeWidth: 1.5, arrowLength: 4.5, arrowWidth: 4,
  textSize: 17, agentTextSize: 0.0133, lineHeight: 1.32,
  padTop: 0.42, padBottom: 0.47, padSide: 0.8, maxWidth: 18, noteGap: 8,
  badgeHeight: 1.36, badgeLabel: 0.75, badgeLogo: 0.79, badgeGap: 0.32,
  badgeLead: 0.5, badgeTrail: 0.57, badgeInset: 0.35, badgeOverlap: 0.2,
};
const FONT = {
  person: 'ui-rounded, "SF Pro Rounded", system-ui, -apple-system, sans-serif',
  agent: 'ui-monospace, "SF Mono", Menlo, monospace',
  ui: 'system-ui, -apple-system, "Helvetica Neue", sans-serif',
};
// Resolved from this file, so a page in another folder (the share image's) finds it.
const CLAUDE_SVG = new URL("claude.svg", import.meta.url).href;
const POINT_SCALE = 2; // the screenshots are 2x captures: image px per point

const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
const narrowScreen = matchMedia("(max-width: 600px)");
const motion = () => (reducedMotion.matches ? 0 : 1);
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const wait = (s) => new Promise((r) => setTimeout(r, s * 1000 * motion()));
// Calls `f` once a frame with the fraction of `seconds` gone, 0 to 1. It goes by the clock, so a
// display at 120 Hz takes as long as one at 60.
function tween(seconds, f) {
  const d = seconds * 1000 * motion();
  if (!d) { f(1); return Promise.resolve(); }
  return new Promise((resolve) => {
    let start = 0;
    const step = (now) => {
      start ||= now;
      const t = clamp((now - start) / d, 0, 1);
      f(t);
      t < 1 ? requestAnimationFrame(step) : resolve();
    };
    requestAnimationFrame(step);
  });
}
// A press that closes something: for a mouse the press itself, as in the app, and for a finger or a
// pen its click, since a touch that starts a scroll is a press too and must not close anything.
let pointerType = "mouse";
addEventListener("pointerdown", (e) => { pointerType = e.pointerType; }, true);
function onPress(target, f) {
  target.addEventListener("pointerdown", (e) => { if (e.pointerType === "mouse") f(e); });
  target.addEventListener("click", (e) => { if (pointerType !== "mouse") f(e); });
}
const escapeXML = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

// ---------------------------------------------------------------------------------------------
// Springs. SwiftUI's spring(duration:bounce:): stiffness (2π/d)², damping 4π(1-bounce)/d, mass 1.
// A spring sent to a new target keeps its velocity, so an interrupted motion blends instead of
// jumping, as the app's Tween does.

const active = new Set();
let frame = 0, last = 0;
function tick(now) {
  const dt = Math.min(0.05, last ? (now - last) / 1000 : 1 / 60);
  last = now;
  for (const m of [...active]) m.step(dt);
  frame = active.size ? requestAnimationFrame(tick) : ((last = 0), 0);
}
function wake(m) {
  active.add(m);
  if (!frame) frame = requestAnimationFrame(tick);
}

class Spring {
  constructor(value, eps = 0.01) {
    this.x = value; this.v = 0; this.target = value; this.eps = eps;
    this.k = 0; this.c = 0; this.moving = false; this.waiters = [];
  }
  to(target, duration, bounce = 0) {
    this.target = target;
    const d = duration * motion();
    if (d <= 0) return this.jump(target);
    const w = (2 * Math.PI) / d;
    this.k = w * w; this.c = (4 * Math.PI * (1 - bounce)) / d; this.moving = true;
    return this;
  }
  jump(value) {
    this.x = value; this.target = value; this.v = 0; this.moving = false; this.settle();
    return this;
  }
  step(dt) {
    if (!this.moving) return;
    const n = Math.ceil(dt / 0.002), h = dt / n;
    for (let i = 0; i < n; i++) {
      const a = -this.k * (this.x - this.target) - this.c * this.v;
      this.v += a * h; this.x += this.v * h;
    }
    if (Math.abs(this.x - this.target) < this.eps && Math.abs(this.v) < this.eps * 20) {
      this.x = this.target; this.v = 0; this.moving = false; this.settle();
    }
  }
  settle() { const w = this.waiters; this.waiters = []; w.forEach((f) => f()); }
  arrived() { return this.moving ? new Promise((r) => this.waiters.push(r)) : Promise.resolve(); }
}

// A set of springs and the one function that draws them, called once a frame while any moves.
class Motion {
  constructor(render) { this.render = render; this.springs = {}; }
  add(name, value, eps) { this.springs[name] = new Spring(value, eps); return this; }
  get(name) { return this.springs[name].x; }
  to(name, target, duration, bounce = 0) {
    const s = this.springs[name];
    if (!s.moving && s.x === target) return Promise.resolve();
    s.to(target, duration, bounce);
    this.springs[name].moving ? wake(this) : this.render(this);
    return this.springs[name].arrived();
  }
  jump(name, value) { this.springs[name].jump(value); this.render(this); }
  step(dt) {
    let moving = false;
    for (const s of Object.values(this.springs)) { s.step(dt); moving ||= s.moving; }
    this.render(this);
    if (!moving) active.delete(this);
  }
}

// A CSS linear() easing sampled from the same spring, for small state changes such as a hover.
function springEasing(duration, bounce = 0) {
  const s = new Spring(0, 0.0005).to(1, duration, bounce);
  const pts = [];
  for (let i = 0; i <= 40; i++) { pts.push(+s.x.toFixed(4)); s.step(duration / 40); }
  pts[40] = 1;
  return `linear(${pts.join(", ")})`;
}
document.documentElement.style.setProperty("--spring-fast", springEasing(0.15, 0.15));
document.documentElement.style.setProperty("--spring", springEasing(0.3, 0.15));
document.documentElement.style.setProperty("--spring-bouncy", springEasing(0.4, 0.45));

// ---------------------------------------------------------------------------------------------
// Marks, drawn as the app's renderer draws them (MarkRendering.swift), in image px.

// Text is measured the way it is drawn, as SVG text in this document, so a tag fits its words in
// whatever font the browser resolves the family to.
const SVG_NS = "http://www.w3.org/2000/svg";
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
  return { ...st, lines, lh, w, h, badge, x: mark.x, y: mark.y };
}

function markBounds(mark, image) {
  if (mark.type === "rect") return { x: mark.x, y: mark.y, w: mark.w, h: mark.h };
  if (mark.type === "arrow") {
    const x = Math.min(mark.x1, mark.x2), y = Math.min(mark.y1, mark.y2);
    return { x, y, w: Math.abs(mark.x2 - mark.x1), h: Math.abs(mark.y2 - mark.y1) };
  }
  const l = noteLayout(mark, image);
  return { x: l.x, y: l.y, w: l.w, h: l.h };
}

const SHADOW_SHAPE = (px) => `drop-shadow(0 ${0.5 * px}px ${1 * px}px rgba(0,0,0,.28))`;

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

function marksSVG(marks, image, typing = null) {
  return marks.map((m) => markSVG(m, image, { caret: m === typing })).join("");
}

// ---------------------------------------------------------------------------------------------
// Geometry.

function coverRect(box, image) {
  const s = Math.max(box.w / image.w, box.h / image.h);
  const w = image.w * s, h = image.h * s;
  return { x: (box.w - w) / 2, y: (box.h - h) / 2, w, h };
}
function containRect(box, image) {
  const s = Math.min(box.w / image.w, box.h / image.h);
  const w = image.w * s, h = image.h * s;
  return { x: (box.w - w) / 2, y: (box.h - h) / 2, w, h };
}
const lerpRect = (a, b, t) => ({ x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t), w: lerp(a.w, b.w, t), h: lerp(a.h, b.h, t) });
const place = (el, r) => { el.style.left = `${r.x}px`; el.style.top = `${r.y}px`; el.style.width = `${r.w}px`; el.style.height = `${r.h}px`; };

function cardSize(image) {
  const aspect = image.w / image.h;
  if (aspect >= UI.cardMaxWidth / UI.cardMaxHeight) {
    return { w: UI.cardMaxWidth, h: clamp(UI.cardMaxWidth / aspect, UI.cardMinSide, UI.cardMaxHeight) };
  }
  return { w: clamp(UI.cardMaxHeight * aspect, UI.cardMinSide, UI.cardMaxWidth), h: UI.cardMaxHeight };
}

function el(tag, cls, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html != null) e.innerHTML = html;
  return e;
}

// A picture: the image and its marks, placed at `rect` inside a clipping box.
function picture(image, marks) {
  const root = el("div", "pic");
  const img = el("img");
  img.src = image.src; img.alt = ""; img.draggable = false;
  const svg = document.createElementNS(SVG_NS, "svg");
  svg.setAttribute("viewBox", `0 0 ${image.w} ${image.h}`);
  svg.setAttribute("class", "marks");
  root.append(img, svg);
  // Decoded now, so the first frame that shows the picture does not wait for its decode. A card
  // offscreen is not drawn until it slides in, and its decode then held frames of the slide-in.
  root.ready = img.decode().catch(() => {});
  root.update =(ms = marks, typing = null) => { svg.innerHTML = marksSVG(ms, image, typing); };
  root.place = (r) => place(root, r);
  root.update(marks);
  return root;
}

// ---------------------------------------------------------------------------------------------
// A stage: one Mac screen with its windows, the recent stack, the annotator and the flights.

const stages = [];
let keyStage = null; // the stage that holds the keys, as the stack panel does in the app

export class Stage {
  constructor(root, opts) {
    this.root = root;
    this.opts = opts;
    this.cards = [];
    this.stackOpen = false;
    this.open = null; // the card in the annotator
    this.marks = [];
    this.tool = "rectangle";
    this.typing = null;
    this.noteFor = null;
    this.history = [];
    this.stackTimers = [];
    this.focused = -1;
    this.listeners = new Set();
    this.build();
    stages.push(this);
  }

  emit(event, detail) { this.listeners.forEach((f) => f(event, detail)); }
  on(f) { this.listeners.add(f); }

  build() {
    const screen = el("div", "screen");
    this.screen = screen;
    screen.append(el("div", "wallpaper"));
    screen.append(el("div", "menubar", `<span class="apple">\uF8FF</span><b>${this.opts.app || "Chrome"}</b><span>File</span><span>Edit</span><span>View</span><span>Window</span><span>Help</span><i>Fri Oct 2&nbsp;&nbsp;9:41 AM</i>`));
    this.windows = el("div", "windows");
    screen.append(this.windows);
    this.dim = el("div", "dim");
    this.backdrop = el("div", "backdrop", "<i></i><i></i><i></i><i></i><i></i><b></b>");
    this.column = el("div", "column");
    this.frame = el("div", "frame");
    this.flights = el("div", "flights");
    this.toolbar = el("div", "toolbar");
    this.selection = el("div", "selection", "<b></b><i></i>");
    screen.append(this.selection, this.dim, this.backdrop, this.column, this.frame, this.flights, this.toolbar);
    this.root.append(screen);

    // On a narrow screen the stage is square and frames the part of the Mac screen that matters
    // now, as a camera would: the stack while it is open, the frame while a card is in the
    // annotator, or what the page points it at. The camera's rect springs between them.
    // The stage's size is kept from the observer, because reading it inside an animation frame,
    // after the frame's other writes, forced a layout on every frame.
    this.camera = new Motion(() => this.fit()).add("x", 0, 0.05).add("y", 0, 0.05).add("w", SCREEN.w, 0.05).add("h", SCREEN.h, 0.05);
    this.size = { w: this.root.clientWidth, h: this.root.clientHeight };
    new ResizeObserver(([entry]) => {
      this.size = { w: entry.contentRect.width, h: entry.contentRect.height };
      this.fit();
    }).observe(this.root);
    narrowScreen.addEventListener("change", () => this.reframe(true));
    this.reframe(true);
    // A stage scrolled out of view gives the keys back to the page, as the stack closes when its
    // panel loses the keys, so the arrows and Space scroll the page again.
    this.inView = false;
    new IntersectionObserver(([entry]) => {
      this.inView = entry.intersectionRatio >= 0.25;
      this.root.classList.toggle("asleep", !entry.isIntersecting);
      if (this.inView || keyStage !== this) return;
      keyStage = null;
      if (this.opts.alwaysOpen) return;
      if (this.open) this.cancel(); else this.dismiss();
    }, { threshold: [0, 0.25, 0.5] }).observe(this.root);

    this.stackMotion = new Motion((m) => {
      this.backdrop.style.opacity = m.get("backdrop");
      this.backdrop.style.transform = `translateX(${(1 - m.get("backdrop")) * 60}px)`;
      const s = m.get("scale");
      this.column.style.transform = `scale(${s})`;
    }).add("backdrop", 0, 0.002).add("scale", 1, 0.0005);
    this.dimMotion = new Motion((m) => { this.dim.style.opacity = m.get("o"); this.dim.style.visibility = m.get("o") > 0.001 ? "visible" : "hidden"; }).add("o", 0, 0.002);
    this.column.style.transformOrigin = `${SCREEN.w - UI.screenMargin}px ${SCREEN.h - UI.screenMargin}px`;

    // The toolbar is laid out, hidden, from the start: the first time the browser lays out ⌘ and ↩
    // it looks for a font that has them, which took 13 ms in the frame the editor opened.
    this.renderToolbar();
    this.frame.addEventListener("pointerdown", (e) => this.pointerDown(e));
    onPress(this.dim, () => this.open && this.cancel());
    onPress(this.screen, (e) => {
      if (e.target === this.screen || e.target.closest(".windows,.wallpaper,.menubar")) {
        if (this.open) this.cancel(); else if (this.stackOpen) this.dismiss();
      }
    });
  }

  fit() {
    const rw = this.size.w, rh = this.size.h;
    let s = rw / SCREEN.w, tx = 0, ty = 0;
    if (narrowScreen.matches && rw > 0) {
      const c = { x: this.camera.get("x"), y: this.camera.get("y"), w: this.camera.get("w"), h: this.camera.get("h") };
      s = Math.min(rw / c.w, rh / c.h);
      tx = rw / 2 - (c.x + c.w / 2) * s;
      ty = rh / 2 - (c.y + c.h / 2) * s;
      // The screen keeps covering the stage where it is big enough to, and is centred where not.
      const sw = SCREEN.w * s, sh = SCREEN.h * s;
      tx = sw >= rw ? clamp(tx, rw - sw, 0) : (rw - sw) / 2;
      ty = sh >= rh ? clamp(ty, rh - sh, 0) : (rh - sh) / 2;
    }
    this.scale = s;
    this.screen.style.transform = `translate(${tx}px, ${ty}px) scale(${s})`;
  }

  cameraRect() {
    const pad = (r, p) => ({ x: r.x - p, y: r.y - p, w: r.w + 2 * p, h: r.h + 2 * p });
    if (this.framed && this.frameRect) {
      const f = this.frameRect;
      return pad({ x: f.x, y: f.y, w: f.w, h: f.h + UI.toolbarGap + UI.toolbarHeight }, 20);
    }
    if (this.lookAt) return this.lookAt;
    if (this.stackOpen || this.lone) return { x: SCREEN.w - 560, y: SCREEN.menu, w: 560, h: SCREEN.h - SCREEN.menu };
    return this.opts.home || { x: 0, y: 0, w: SCREEN.w, h: SCREEN.h };
  }

  // Aim the camera at what matters now; `look` points it somewhere else until it is cleared.
  reframe(jump = false) {
    const c = this.cameraRect();
    // Only a narrow stage frames part of the screen, so a wide one has nothing to animate.
    if (!narrowScreen.matches) jump = true;
    for (const k of ["x", "y", "w", "h"]) jump ? this.camera.jump(k, c[k]) : this.camera.to(k, c[k], 0.6, 0);
  }

  look(rect) { this.lookAt = rect; this.reframe(); }

  toStage(e) {
    const r = this.screen.getBoundingClientRect();
    return { x: (e.clientX - r.left) / this.scale, y: (e.clientY - r.top) / this.scale };
  }

  addWindow(html, rect, cls = "") {
    const w = el("div", `window ${cls}`, html);
    place(w, rect);
    this.windows.append(w);
    return w;
  }

  // ---- the stack ------------------------------------------------------------------------------

  setCards(list) {
    this.clearStackTimers();
    this.cards.forEach((c) => c.el.remove());
    this.cards = list.map((c) => this.makeCard(c));
    this.layout();
    this.cards.forEach((c) => c.motion.jump("x", this.offX(c)));
  }

  makeCard(c) {
    const card = { ...c, marks: c.marks ? c.marks.map((m) => ({ ...m })) : [] };
    card.size = cardSize(c.image);
    const e = el("div", "card");
    e.style.width = `${card.size.w}px`; e.style.height = `${card.size.h}px`;
    card.pic = picture(c.image, card.marks);
    card.pic.place(coverRect(card.size, c.image));
    // The picture is clipped by a layer inside the card, so a ring can sit outside the card.
    const clip = el("div", "clip");
    clip.append(card.pic);
    e.append(clip);
    if (c.from) e.append(el("div", "from", `<img src="${CLAUDE_SVG}" alt="">From ${c.from}`));
    e.append(el("div", "ring"));
    e.addEventListener("pointerenter", () => { if ((this.stackOpen || this.lone === card) && !this.open) this.focus(this.cards.indexOf(card)); });
    e.addEventListener("pointerleave", () => { if (this.lone === card && !this.stackOpen && !this.open) this.focus(-1); });
    e.addEventListener("click", () => this.cardClicked(card));
    card.el = e;
    card.motion = new Motion((m) => {
      e.style.transform = `translate(${m.get("x")}px, ${m.get("lift")}px) scale(${m.get("hover")})`;
    }).add("x", 400, 0.1).add("lift", 0, 0.1).add("hover", 1, 0.0005);
    this.column.append(e);
    return card;
  }

  offX(c) { return c.size.w + UI.screenMargin + 30; }

  // Newest at the bottom, each card's right edge on the screen margin.
  layout() {
    let bottom = SCREEN.h - UI.screenMargin;
    for (let i = this.cards.length - 1; i >= 0; i--) {
      const c = this.cards[i];
      c.slot = { x: SCREEN.w - UI.screenMargin - c.size.w, y: bottom - c.size.h, w: c.size.w, h: c.size.h };
      c.el.style.left = `${c.slot.x}px`; c.el.style.top = `${c.slot.y}px`;
      bottom -= c.size.h + UI.cardSpacing;
    }
  }

  async showStack() {
    if (this.stackOpen) return;
    this.clearStackTimers();
    this.stackOpen = true;
    this.reframe();
    this.takeKeys();
    this.root.classList.add("stack-open");
    this.stackMotion.to("backdrop", 1, UI.backdropFade);
    const n = this.cards.length;
    const step = Math.min(UI.stagger, UI.staggerMax / Math.max(1, n - 1));
    this.focus(n - 1);
    this.emit("stack");
    for (let i = n - 1; i >= 0; i--) {
      const c = this.cards[i];
      this.stackTimers.push(setTimeout(() => {
        if (this.stackOpen) c.motion.to("x", 0, UI.slideIn, UI.flightBounce);
      }, (n - 1 - i) * step * 1000 * motion()));
    }
  }

  clearStackTimers() {
    this.stackTimers.forEach(clearTimeout);
    this.stackTimers = [];
  }

  dismiss() {
    if (!this.stackOpen || this.open || this.opts.alwaysOpen) return;
    this.clearStackTimers();
    this.stackOpen = false;
    this.lone = null;
    this.reframe();
    this.root.classList.remove("stack-open");
    this.focus(-1);
    this.stackMotion.to("backdrop", 0, UI.backdropFade);
    this.cards.forEach((c) => c.motion.to("x", this.offX(c), UI.slideOut));
    if (keyStage === this) keyStage = null;
    this.emit("dismiss");
  }

  focus(i) {
    this.focused = i;
    this.cards.forEach((c, j) => c.el.classList.toggle("focused", j === i));
    this.cards.forEach((c, j) => c.motion.to("hover", j === i && !this.open ? UI.hoverScale : 1, 0.15, 0.15));
  }

  cardClicked(card) {
    if (!this.stackOpen && !this.opts.alwaysOpen && this.lone !== card) return;
    if (this.open === card) return;
    if (this.open) return;
    this.annotate(card);
  }

  // A card joining the open stack: the others lift back to where they were and spring up.
  async insert(c) {
    const card = this.makeCard(c);
    const before = this.cards.map((k) => k.slot.y);
    this.cards.push(card);
    this.layout();
    this.cards.slice(0, -1).forEach((k, i) => {
      k.motion.jump("lift", before[i] - k.slot.y);
      k.motion.to("lift", 0, UI.shiftUp, UI.flightBounce);
    });
    card.motion.jump("x", this.offX(card));
    await wait(0.08);
    await card.motion.to("x", 0, UI.slideIn, UI.flightBounce);
    return card;
  }

  // A capture, as Cmd+Shift+4 takes one: a selection dragged over the screen, then the screenshot
  // comes in as a card with its copy result. With the stack closed it is the lone thumbnail in the
  // corner, which leaves after thumbnailSeconds unless the pointer is on it or it is opened.
  // `card` may be a promise, which the drag gives time to settle.
  async capture(rect, card, copyResult = Promise.resolve(true)) {
    const sel = this.selection, size = sel.querySelector("i");
    this.look({ x: rect.x - 40, y: rect.y - 40, w: rect.w + 80, h: rect.h + 80 });
    sel.classList.add("on");
    await tween(0.56, (t) => {
      const e = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
      const w = rect.w * e, h = rect.h * e;
      place(sel, { x: rect.x, y: rect.y, w, h });
      size.textContent = `${Math.round(w * POINT_SCALE)}  ${Math.round(h * POINT_SCALE)}`;
    });
    const copyAttempt = {};
    card = { ...await card, copyAttempt };
    await wait(0.18);
    sel.classList.remove("on");
    sel.classList.add("taken");
    setTimeout(() => sel.classList.remove("taken"), 400);
    await wait(0.12);
    let made;
    if (this.stackOpen) this.look(null);
    if (this.stackOpen) made = this.insert(card).then((c) => { if (!this.open) this.focus(this.cards.indexOf(c)); return c; });
    else {
      made = this.makeCard(card);
      this.cards.push(made);
      this.layout();
      made.motion.jump("x", this.offX(made));
      this.lone = made;
      this.look(null);
      made.motion.to("x", 0, UI.slideIn, UI.flightBounce);
    }
    made = await made;
    made.copied = await copyResult;
    if (made.copyAttempt === copyAttempt) {
      this.notice(made, made.copied ? { kind: "copied" } : { kind: "failed", reason: "This browser didn't allow the copy." });
    }
    while (this.cards.length > (this.opts.keep || 99)) this.cards.shift().el.remove();
    this.layout();
    if (this.lone === made) this.leaveSoon(made);
    this.emit("captured", made);
    return made;
  }

  leaveSoon(card) {
    clearTimeout(this.loneTimer);
    this.loneTimer = setTimeout(() => {
      if (this.lone !== card || this.stackOpen || this.open) return;
      if (card.el.matches(":hover")) return this.leaveSoon(card);
      this.lone = null;
      this.reframe();
      this.focus(-1);
      card.motion.to("x", this.offX(card), UI.slideOut);
      this.emit("lone-gone", card);
    }, UI.thumbnailSeconds * 1000);
  }

  // ---- keys -----------------------------------------------------------------------------------

  takeKeys() { keyStage = this; }

  key(e) {
    if (this.open) return this.editorKey(e);
    if (!this.stackOpen) return false;
    if (e.key === "ArrowUp") { this.focus(clamp(this.focused - 1, 0, this.cards.length - 1)); return true; }
    if (e.key === "ArrowDown") { this.focus(clamp(this.focused + 1, 0, this.cards.length - 1)); return true; }
    if (e.key === "Enter") { const c = this.cards[this.focused]; if (c) this.annotate(c); return true; }
    if (e.key === "Escape") { this.dismiss(); return true; }
    return false;
  }

  // ---- the annotator --------------------------------------------------------------------------

  room() {
    const narrowest = SCREEN.w - UI.screenMargin - UI.cardMaxWidth * UI.stackMinScale;
    return {
      x: UI.screenInset, y: SCREEN.menu + UI.screenInset * 0.6,
      w: narrowest - UI.stackGap - UI.screenInset,
      h: SCREEN.h - SCREEN.menu - UI.screenInset * 1.2 - UI.toolbarHeight - UI.toolbarGap,
    };
  }

  frameFor(image) {
    const room = this.room();
    const s = Math.min(1, room.w / (image.w / POINT_SCALE), room.h / (image.h / POINT_SCALE));
    let w = (image.w / POINT_SCALE) * s, h = (image.h / POINT_SCALE) * s;
    w = Math.min(room.w, Math.max(w, UI.annotationMinWidth));
    h = Math.min(room.h, Math.max(h, UI.annotationMinHeight));
    return { x: room.x + (room.w - w) / 2, y: room.y + (room.h - h) / 2, w, h };
  }

  // The widest the stack can be drawn while it clears the frame by the gap.
  widthScale(frame) {
    const right = SCREEN.w - UI.screenMargin;
    const widest = Math.max(...this.cards.map((c) => c.size.w));
    return clamp((right - (frame.x + frame.w + UI.stackGap)) / widest, UI.stackMinScale, 1);
  }

  cardRect(card) {
    const s = this.stackMotion.get("scale");
    const ox = SCREEN.w - UI.screenMargin, oy = SCREEN.h - UI.screenMargin;
    const x = card.slot.x + card.motion.get("x"), y = card.slot.y + card.motion.get("lift");
    return { x: ox + (x - ox) * s, y: oy + (y - oy) * s, w: card.size.w * s, h: card.size.h * s };
  }

  async annotate(card, { marks } = {}) {
    if (this.open) return;
    this.takeKeys();
    this.open = card;
    this.marks = (marks || card.marks).map((m) => ({ ...m }));
    this.history = [];
    this.typing = null; this.noteFor = null;
    const frame = this.frameFor(card.image);
    this.frameRect = frame;
    this.framed = true;
    this.reframe();
    this.focus(this.cards.indexOf(card));
    card.motion.jump("hover", 1);
    this.dimMotion.to("o", 1, UI.dimFade);
    if (this.stackOpen || this.opts.alwaysOpen) this.stackMotion.to("scale", this.widthScale(frame), UI.relayout, UI.flightBounce);
    this.emit("opening", card);
    const from = this.cardRect(card);
    const flight = await this.fly(card, this.marks, from, frame, "out", () => card.el.classList.add("away"));
    if (!flight) return;
    this.showFrame(card);
    // The flight covers the frame until the frame's own picture is decoded and drawn.
    this.framePic.ready.then(() => requestAnimationFrame(() => requestAnimationFrame(() => flight.remove())));
    this.emit("open", card);
  }

  showFrame(card) {
    const f = this.frameRect;
    place(this.frame, f);
    this.frame.innerHTML = "";
    const pic = picture(card.image, this.marks);
    this.picRect = containRect(f, card.image);
    pic.place(this.picRect);
    this.frame.append(pic);
    this.framePic = pic;
    this.frame.classList.add("up");
    this.renderToolbar();
    place(this.toolbar, { x: f.x, y: f.y + f.h + UI.toolbarGap, w: f.w, h: UI.toolbarHeight });
    requestAnimationFrame(() => this.toolbar.classList.add("up"));
  }

  hideFrame() {
    this.frame.classList.remove("up");
    this.toolbar.classList.remove("up");
    this.framePic = null;
  }

  // A flight: the picture travels between the card's slot and the frame on a bowed path, swelling
  // in the middle (FlightCurve). The picture inside goes from the card's crop to the frame's fit.
  // The flight, its shadow and its picture are laid out once at the frame's size and moved only by
  // transforms, so the picture and its marks are drawn once and the GPU scales them. The corners
  // are set against the scale so they stay round. The shadow is cast at the frame's size: scaled
  // to the card, its blur and offset shrink as the card's own do, and its opacity does the rest.
  // `start` runs on the first frame the flight shows, which is when the card hides.
  async fly(card, marks, from, to, way, start) {
    const W = to.w, H = to.h, R = UI.annotationCorner;
    const shadow = el("div", "flight-shadow");
    const f = el("div", `flight ${way}`);
    const pic = picture(card.image, marks);
    const toPic = containRect(to, card.image), fromPic = coverRect(from, card.image);
    for (const e of [shadow, f]) place(e, { x: 0, y: 0, w: W, h: H });
    place(pic, { x: 0, y: 0, w: toPic.w, h: toPic.h });
    f.append(pic);
    this.flights.append(shadow, f);
    const dx = to.x + to.w / 2 - (from.x + from.w / 2), dy = to.y + to.h / 2 - (from.y + from.h / 2);
    const len = Math.hypot(dx, dy) || 1;
    const bow = Math.min(UI.flightArc * len, UI.flightArcMax) * motion();
    const nx = -dy / len, ny = dx / len, side = nx < 0 ? -1 : 1; // the side belongs to the line
    const startAtCard = way === "out";
    const m = new Motion((mm) => {
      const p = mm.get("p");
      const t = startAtCard ? p : 1 - p;
      const swell = 1 + UI.flightDepth * motion() * Math.sin(Math.PI * clamp(p, 0, 1));
      const r = lerpRect(from, to, t);
      const off = bow * Math.sin(Math.PI * clamp(t, 0, 1)) * side;
      const w = r.w * swell, h = r.h * swell;
      const x = r.x + r.w / 2 + nx * off - w / 2, y = r.y + r.h / 2 + ny * off - h / 2;
      const sx = w / W, sy = h / H;
      const move = `translate3d(${x}px, ${y}px, 0) scale(${sx}, ${sy})`;
      f.style.transform = move;
      shadow.style.transform = move;
      f.style.borderRadius = `${R / sx}px / ${R / sy}px`;
      const pr = lerpRect(fromPic, toPic, t);
      pic.style.transform = `translate3d(${(pr.x * swell) / sx}px, ${(pr.y * swell) / sy}px, 0) scale(${(pr.w * swell) / sx / toPic.w}, ${(pr.h * swell) / sy / toPic.h})`;
      shadow.style.opacity = lerp(1, 0.6, t);
    }).add("p", 0, 0.0008);
    // The flight in progress, which close() turns around (`turned`) while it is on its way out.
    const flight = { m, way, turned: false };
    this.flight = flight;
    // A layer keeps the scale it was first rasterized at, so a flight that starts at the card is
    // drawn once at full size first, almost transparent, while the card still shows.
    if (startAtCard && motion()) {
      f.style.transform = `translate3d(${to.x}px, ${to.y}px, 0)`;
      f.style.opacity = "0.01";
      shadow.style.opacity = "0";
      await Promise.all([pic.ready, new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))]);
      f.style.opacity = "";
    }
    if (!flight.turned) {
      m.render(m);
      start?.();
      await m.to("p", 1, UI.expand, UI.flightBounce);
    }
    if (this.flight === flight) this.flight = null;
    shadow.remove();
    // A flight turned around ends back where it started, and answers null.
    if (flight.turned) { f.remove(); return null; }
    return f;
  }

  async close({ notice } = {}) {
    const card = this.open;
    if (!card || this.closing) return;
    this.closing = true;
    this.endTyping();
    card.marks = this.marks.map((m) => ({ ...m }));
    card.pic.update(card.marks);
    const from = this.frameRect;
    // A card still on its way into the editor turns around in mid-air, keeping its speed, and lands
    // back in its slot, as the app's flights do. Nobody has seen the editor yet, so nothing else
    // flies.
    const turning = this.flight?.way === "out" ? this.flight : null;
    this.framed = false;
    this.reframe();
    this.hideFrame();
    if (!turning) this.flights.querySelectorAll(".flight.out").forEach((e) => e.remove());
    this.dimMotion.to("o", 0, UI.dimFade);
    if (this.stackOpen || this.opts.alwaysOpen) this.stackMotion.to("scale", 1, UI.relayout, UI.flightBounce);
    this.emit("closing", card);
    if (turning) {
      turning.turned = true;
      await turning.m.to("p", 0, UI.expand, UI.flightBounce);
      card.el.classList.remove("away");
    } else {
      // The flight home aims at the slot as the stack will draw it at rest.
      const s0 = this.stackMotion.get("scale");
      this.stackMotion.springs.scale.x = 1;
      const to = this.cardRect(card);
      this.stackMotion.springs.scale.x = s0;
      const flight = await this.fly(card, card.marks, to, from, "home");
      card.el.classList.remove("away");
      flight.remove();
    }
    this.open = null;
    this.closing = false;
    if (notice) this.notice(card, notice);
    this.focus(this.cards.indexOf(card));
    if (this.lone === card && !this.stackOpen) this.leaveSoon(card);
    this.emit("closed", card);
  }

  cancel() { this.close(); }

  // ---- notices --------------------------------------------------------------------------------

  notice(card, n) {
    card.el.querySelector(".notice")?.remove();
    const e = el("div", "notice");
    const set = (state) => {
      if (state.kind === "copied") e.innerHTML = `<span class="check"></span><b>${state.label || "Copied"}</b>`;
      else if (state.kind === "failed") e.innerHTML = `<span class="cross"></span><b>Not copied</b><small>${state.reason}</small>`;
      else e.innerHTML = `<span class="disc"><img src="${CLAUDE_SVG}" alt=""><i class="${state.kind}"></i></span><b>${state.kind === "sending" ? "Sending to" : "Sent to"} ${state.project}</b>`;
    };
    set(n);
    card.el.append(e);
    requestAnimationFrame(() => e.classList.add("in"));
    e.setState = (state) => { e.classList.add("swap"); setTimeout(() => { set(state); e.classList.remove("swap"); }, 120 * motion()); };
    e.leave = (after) => setTimeout(() => { e.classList.remove("in"); setTimeout(() => e.remove(), 400); }, after * 1000);
    if (n.kind !== "sending") e.leave(UI.noticeSeconds);
    return e;
  }

  // ---- the editor -----------------------------------------------------------------------------

  toImage(p) {
    const r = this.picRect, f = this.frameRect, img = this.open.image;
    return { x: ((p.x - f.x - r.x) / r.w) * img.w, y: ((p.y - f.y - r.y) / r.h) * img.h };
  }

  redraw() { this.framePic?.update(this.marks, this.typing); }

  snapshot() { this.history.push(this.marks.map((m) => ({ ...m }))); }

  pointerDown(e) {
    if (!this.open || !this.framePic) return;
    this.emit("editing", this.open);
    e.preventDefault();
    const img = this.open.image;
    const start = this.toImage(this.toStage(e));
    this.endTyping();
    const target = e.target.closest(".toolbar");
    if (target) return;
    if (this.tool === "select") {
      const hit = [...this.marks].reverse().find((m) => { const b = markBounds(m, img); return start.x >= b.x - 12 && start.x <= b.x + b.w + 12 && start.y >= b.y - 12 && start.y <= b.y + b.h + 12; });
      if (!hit) return;
      this.snapshot();
      const orig = { ...hit };
      this.drag(e, (p) => {
        const dx = p.x - start.x, dy = p.y - start.y;
        if (hit.type === "arrow") Object.assign(hit, { x1: orig.x1 + dx, y1: orig.y1 + dy, x2: orig.x2 + dx, y2: orig.y2 + dy });
        else Object.assign(hit, { x: orig.x + dx, y: orig.y + dy });
        this.redraw();
      });
      return;
    }
    if (this.tool === "text") {
      this.snapshot();
      const note = { type: "note", who: "person", x: start.x, y: start.y - 30, text: "" };
      this.marks.push(note);
      this.typing = note;
      this.redraw();
      this.emit("mark");
      return;
    }
    this.snapshot();
    const mark = this.tool === "arrow"
      ? { type: "arrow", who: "person", x1: start.x, y1: start.y, x2: start.x, y2: start.y }
      : { type: "rect", who: "person", x: start.x, y: start.y, w: 0, h: 0 };
    this.marks.push(mark);
    this.drag(e, (p) => {
      if (mark.type === "arrow") Object.assign(mark, { x2: p.x, y2: p.y });
      else Object.assign(mark, { x: Math.min(start.x, p.x), y: Math.min(start.y, p.y), w: Math.abs(p.x - start.x), h: Math.abs(p.y - start.y) });
      this.redraw();
    }, () => {
      const small = mark.type === "arrow" ? Math.hypot(mark.x2 - mark.x1, mark.y2 - mark.y1) < 16 : mark.w < 8 || mark.h < 8;
      if (small) { this.marks.pop(); this.history.pop(); this.redraw(); return; }
      this.noteFor = mark;
      this.emit("mark");
    });
  }

  drag(e, move, up) {
    const target = e.target;
    target.setPointerCapture?.(e.pointerId);
    const onMove = (ev) => move(this.toImage(this.toStage(ev)));
    const onUp = () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      up?.();
    };
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
  }

  // A note for the box just drawn: beside it when there is room, else under it (notePlace).
  startNote(mark, ch) {
    const img = this.open.image;
    const gap = MARK.noteGap * POINT_SCALE, ink = (MARK.stroke * POINT_SCALE) / 2;
    const size = MARK.textSize * POINT_SCALE;
    let x, y;
    if (mark.type === "rect") {
      const right = mark.x + mark.w + ink + gap;
      if (img.w - right > Math.max(img.w * 0.15, 6 * size)) { x = right; y = mark.y - ink; }
      else if (img.h - (mark.y + mark.h + ink + gap) > size * 2.4) { x = Math.max(0, mark.x - ink); y = mark.y + mark.h + ink + gap; }
      else { x = Math.max(0, mark.x - ink); y = Math.max(0, mark.y - ink - gap - size * 2.2); }
    } else {
      x = Math.max(0, mark.x1 - size * 2); y = mark.y1 - size * 1.1;
    }
    const note = { type: "note", who: "person", x, y, text: ch };
    this.marks.push(note);
    this.typing = note;
    this.noteFor = null;
    this.redraw();
  }

  endTyping() {
    if (!this.typing) return;
    if (!this.typing.text.trim()) this.marks.splice(this.marks.indexOf(this.typing), 1);
    this.typing = null;
    this.redraw();
  }

  setTool(t) {
    this.endTyping();
    this.tool = t;
    this.toolbar.querySelectorAll("[data-tool]").forEach((b) => {
      const selected = b.dataset.tool === t;
      b.classList.toggle("on", selected);
      b.setAttribute("aria-pressed", selected);
    });
    this.emit("tool", t);
  }

  editorKey(e) {
    if (e.key === "Tab") { this.endTyping(); return false; }
    // On the way in, Esc turns the card around, and the editor takes no other key until it lands.
    if (!this.framePic) {
      if (e.key === "Escape") this.cancel();
      return e.key !== "Tab";
    }
    const cmd = e.metaKey || e.ctrlKey;
    if (cmd && e.key.toLowerCase() === "z") {
      this.endTyping();
      const prev = this.history.pop();
      if (prev) { this.marks = prev; this.redraw(); }
      return true;
    }
    if (this.typing) {
      if (e.key === "Escape") { this.endTyping(); return true; }
      if (e.key === "Enter" && cmd) { this.endTyping(); this.finish(e); return true; }
      if (e.key === "Enter") { this.endTyping(); return true; }
      if (e.key === "Backspace") { this.typing.text = this.typing.text.slice(0, -1); this.redraw(); return true; }
      if (e.key.length === 1 && !cmd) { this.typing.text += e.key; this.redraw(); return true; }
      return true;
    }
    if (e.key.length === 1 && !cmd && this.noteFor && e.key !== " ") {
      this.snapshot();
      this.startNote(this.noteFor, e.key);
      this.emit("typing");
      return true;
    }
    if (e.key === "Escape") { this.cancel(); return true; }
    if (e.key === "Enter") { this.finish(e); return true; }
    if (!cmd) {
      const tool = { v: "select", r: "rectangle", a: "arrow", t: "text" }[e.key.toLowerCase()];
      if (tool) { this.setTool(tool); return true; }
    }
    if (e.key === "Backspace" && this.marks.length) { this.snapshot(); this.marks.pop(); this.redraw(); return true; }
    return e.key !== "Tab";
  }

  finish(e) { this.opts.onFinish ? this.opts.onFinish(this, e) : this.copy(); }

  // Copy: the rendering on the clipboard, as Done does, then the card home with its notice.
  async copy() {
    const card = this.open;
    if (!card || this.closing) return;
    const result = { card };
    card.copyAttempt = result;
    this.emit("copying", result);
    this.endTyping();
    const marks = this.marks.map((m) => ({ ...m }));
    const copied = copyPNG(renderPNG(card.image, marks));
    const [ok] = await Promise.all([copied, this.close()]);
    result.ok = ok;
    if (card.copyAttempt === result) {
      this.notice(card, ok ? { kind: "copied" } : { kind: "failed", reason: "This browser didn't allow the copy." });
    }
    this.emit("copied", result);
  }

  // ---- the toolbar ----------------------------------------------------------------------------

  renderToolbar() {
    const tools = [
      ["select", "Select (V)", '<path d="M5 3l12 8-5.5 1.2L9 18z" fill="currentColor"/>'],
      ["rectangle", "Rectangle (R)", '<rect x="3.5" y="5.5" width="15" height="11" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.8"/>'],
      ["arrow", "Arrow (A)", '<path d="M5 17L17 5M9 5h8v8" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>'],
      ["text", "Text (T)", '<text x="11" y="16" text-anchor="middle" font-size="13" font-weight="600" text-rendering="geometricPrecision" fill="currentColor" font-family="system-ui">Aa</text>'],
    ];
    const buttons = tools.map(([t, label, icon]) =>
      `<button type="button" class="tool${this.tool === t ? " on" : ""}" data-tool="${t}" aria-label="${label}" aria-pressed="${this.tool === t}"><svg viewBox="0 0 22 22" width="22" height="22">${icon}</svg></button>`).join("");
    const offer = this.opts.offer ? this.opts.offer(this) : `<button type="button" class="pill" data-act="copy">Copy <kbd>↩</kbd></button>`;
    this.toolbar.innerHTML = `<div class="bar">${buttons}<span class="divider"></span>${offer}</div>`;
    this.toolbar.querySelectorAll("[data-tool]").forEach((b) => b.addEventListener("click", () => this.setTool(b.dataset.tool)));
    this.toolbar.querySelector('[data-act="copy"]')?.addEventListener("click", () => this.copy());
    this.opts.wireOffer?.(this);
  }

  reset() {
    this.clearStackTimers();
    this.flights.innerHTML = "";
    this.hideFrame();
    this.open = null;
    this.flight = null;
    this.closing = false;
    this.framed = false;
    this.lookAt = null;
    this.dimMotion.jump("o", 0);
    this.stackMotion.jump("scale", 1);
  }
}

function copyPNG(blobOrPromise) {
  const png = Promise.resolve(blobOrPromise);
  const ready = png.then(() => true, () => false);
  try {
    // Safari's clipboard write must start during the press, before waiting for the PNG to render.
    const written = navigator.clipboard.write([new ClipboardItem({ "image/png": png })]);
    return Promise.all([written, ready]).then(([, ok]) => ok, () => false);
  } catch {
    return Promise.resolve(false);
  }
}

// The rendering: the screenshot with its drawing drawn into it, as one PNG.
function renderPNG(image, marks) {
  return new Promise((resolve, reject) => {
    const canvas = document.createElement("canvas");
    canvas.width = image.w; canvas.height = image.h;
    const ctx = canvas.getContext("2d");
    const base = new Image();
    base.onload = () => {
      ctx.drawImage(base, 0, 0, image.w, image.h);
      const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${image.w}" height="${image.h}" viewBox="0 0 ${image.w} ${image.h}">${marksSVG(marks, image).replaceAll(`href="${CLAUDE_SVG}"`, `href="${CLAUDE_DATA}"`)}</svg>`;
      const over = new Image();
      over.onload = () => { ctx.drawImage(over, 0, 0); canvas.toBlob((b) => (b ? resolve(b) : reject()), "image/png"); };
      over.onerror = reject;
      over.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
    };
    base.onerror = reject;
    base.src = image.src;
  });
}
let CLAUDE_DATA = "";
fetch(CLAUDE_SVG).then((r) => r.text()).then((t) => { CLAUDE_DATA = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(t)}`; });

// ---------------------------------------------------------------------------------------------
// Keys. The stage holding the keys gets them; a click outside every stage takes them away.
// Right Shift, tapped twice, opens the stack of the stage in view, and held on the second tap,
// lifts the newest card into the annotator (ModifierTap: the hold is 0.4 s).

const TAP = { gap: 0.35, hold: 0.4 };
let tap = { lastUp: 0, downAt: 0, armed: false, holdTimer: 0, clean: true };

function stageInView() {
  let best = null, bestShare = 0.35;
  for (const s of stages) {
    if (!s.opts.shortcut) continue;
    const r = s.root.getBoundingClientRect();
    const seen = Math.max(0, Math.min(innerHeight, r.bottom) - Math.max(0, r.top)) / Math.max(1, r.height);
    if (seen > bestShare) { best = s; bestShare = seen; }
  }
  return best;
}

addEventListener("keydown", (e) => {
  if (e.defaultPrevented || e.target.closest?.("input, textarea, select, [contenteditable]")) return;
  if (e.code === "ShiftRight" && !e.repeat) {
    const now = performance.now() / 1000;
    if (tap.clean && now - tap.lastUp < TAP.gap) {
      const s = stageInView();
      if (s) {
        tap.armed = true;
        if (!s.open) {
          const wasOpen = s.stackOpen;
          const lift = wasOpen ? s.cards[s.focused] : null;
          if (wasOpen) s.dismiss(); else s.showStack();
          tap.holdTimer = setTimeout(() => {
            if (!tap.armed) return;
            s.showStack();
            const c = lift || s.cards[s.cards.length - 1];
            if (c) s.annotate(c);
          }, TAP.hold * 1000);
        }
      }
    }
    tap.downAt = now; tap.clean = true;
    return;
  }
  tap.clean = false;
  if (!keyStage || !keyStage.inView) return;
  if ((e.key === " " || (e.key === "Enter" && !e.metaKey && !e.ctrlKey)) && e.target.closest?.("button, a[href]")) return;
  if (keyStage.key(e)) e.preventDefault();
});
addEventListener("keyup", (e) => {
  if (e.code !== "ShiftRight") return;
  tap.lastUp = performance.now() / 1000;
  tap.armed = false;
  clearTimeout(tap.holdTimer);
});
onPress(window, (e) => {
  if (!keyStage) return;
  if (keyStage.root.contains(e.target) || e.target.closest?.("[data-stage-control]")) return;
  const s = keyStage;
  if (s.open) s.cancel(); else s.dismiss();
  keyStage = null;
});

export { picture, marksSVG, cardSize, coverRect, containRect, Motion, Spring, UI, wait, tween, motion, el, place, copyPNG };
