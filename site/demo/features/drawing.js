import { el, place, Motion, wait, motion } from "../vignette.js";
import { IMAGES, PERSON_MARKS } from "../cards.js";
import { lerp, GUTTER, shot, overlay, POINTER, smallFit } from "./parts.js";

// A hand's stroke with the Arrow tool: points every few px along a smooth path, as the editor keeps
// them while the button is down.
function stroke(knots, step = 9) {
  const out = [];
  for (let i = 0; i < knots.length - 1; i++) {
    const a = knots[i], b = knots[i + 1], n = Math.max(1, Math.round(Math.hypot(b[0] - a[0], b[1] - a[1]) / step));
    for (let j = 0; j < n; j++) out.push([lerp(a[0], b[0], j / n), lerp(a[1], b[1], j / n)]);
  }
  out.push(knots[knots.length - 1]);
  return out.map((p, i) => i === 0 || i === out.length - 1 ? p
    : [(out[i - 1][0] + p[0] * 2 + out[i + 1][0]) / 4, (out[i - 1][1] + p[1] * 2 + out[i + 1][1]) / 4]);
}
// The arrow a stroke makes: its ends, and the points between them as its `via`.
const arrowOf = (pts) => ({ type: "arrow", who: "person", x1: pts[0][0], y1: pts[0][1], x2: pts.at(-1)[0], y2: pts.at(-1)[1], via: pts.slice(1, -1) });
const CROSSHAIR = '<svg width="21" height="21" viewBox="0 0 21 21"><path d="M10.5 1v19M1 10.5h19" stroke="#fff" stroke-width="3.5"/><path d="M10.5 1.5v18M1.5 10.5h18" stroke="#000" stroke-width="1.3"/></svg>';

export class Arrows {
  // The trip's map in the editor. One stroke with the Arrow tool circles the stop at Greve and
  // carries on to Pienza; the head rides the pointer and stays where the button comes up.
  static fit = smallFit(196);
  static STROKE = (() => {
    const c = [1327, 292], r = 42, loop = [];
    for (let a = 150; a <= 450; a += 15) loop.push([c[0] + r * Math.cos((a * Math.PI) / 180), c[1] + r * Math.sin((a * Math.PI) / 180)]);
    return stroke([...loop, [1372, 340], [1450, 360], [1530, 378], [1588, 380]]);
  })();
  // Where the pointer rests once the arrow is drawn: clear of the head, on open map.
  static after() { const [x, y] = Arrows.STROKE.at(-1); return [x + 20, y - 58]; }
  build({ W, H }) {
    const s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    this.fw = W - GUTTER + 40;
    this.k = 0.55;
    // The frame ends at the map's foot, so a taller tile never shows the day cards under it.
    const fh = Math.round((440 - 112) * this.k);
    this.view = { x: 1010, y: 112, w: this.fw / this.k, h: fh / this.k };
    const f = el("div", "frame-x");
    place(f, { x: GUTTER, y: 0, w: this.fw, h: fh });
    const sh = shot(IMAGES.itin, this.view, [], this.fw, fh);
    this.pic = sh.pic;
    this.cursor = el("div", "crosshair", CROSSHAIR);
    f.append(sh, this.cursor);
    s.append(f);
    const [x, y] = Arrows.STROKE[0];
    this.rest = [x + 70, y + 110];
    return s;
  }
  aim([x, y]) { this.cursor.style.transform = `translate(${(x - this.view.x) * this.k - 10.5}px, ${(y - this.view.y) * this.k - 10.5}px)`; }
  move(from, to, seconds) {
    return new Motion((m) => { const t = m.get("t"); this.aim([lerp(from[0], to[0], t), lerp(from[1], to[1], t)]); }).add("t", 0, 0.001).to("t", 1, seconds);
  }
  reset() { this.pic.update([]); this.pic.querySelector("svg.marks").style.opacity = 1; this.cursor.style.opacity = 1; this.aim(this.rest); }
  final() { this.reset(); this.pic.update([arrowOf(Arrows.STROKE)]); this.aim(Arrows.after()); }
  async play() {
    this.reset();
    const pts = Arrows.STROKE, end = pts.at(-1);
    await this.move(this.rest, pts[0], 0.4);
    await wait(0.08);
    // Drawn at a hand's pace: slower into the loop and out of it, quicker along the straight.
    const seconds = 1.2 * motion(), t0 = performance.now();
    await new Promise((done) => {
      const tick = () => {
        const t = Math.min(1, (performance.now() - t0) / 1000 / seconds);
        const e = t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2;
        const live = pts.slice(0, Math.max(2, Math.round(e * (pts.length - 1)) + 1));
        this.pic.update([arrowOf(live)]);
        this.aim(live.at(-1));
        t < 1 ? requestAnimationFrame(tick) : done();
      };
      requestAnimationFrame(tick);
    });
    this.pic.update([arrowOf(pts)]);
    await wait(0.25);
    await this.move(end, Arrows.after(), 0.4);
  }
  async rewind() { this.pic.querySelector("svg.marks").style.opacity = 0; this.cursor.style.opacity = 0; await wait(0.25); }
}

export class Later {
  // A drawing opened again: the pointer takes a note and drags it to where it belongs, beside the
  // arrow it goes with.
  static fit = smallFit(196);
  build({ W, H }) {
    const s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    this.fw = W - GUTTER + 40;
    this.k = 0.42;
    this.view = { x: 780, y: 120, w: this.fw / this.k, h: 240 / this.k };
    this.from = { x: 1010, y: 470 }; this.to = { x: 1222, y: 252 };
    this.note = { ...PERSON_MARKS[3] };
    this.arrow = PERSON_MARKS[2];
    const f = el("div", "frame-x");
    place(f, { x: GUTTER, y: 0, w: this.fw, h: 240 });
    const sh = shot(IMAGES.itin, this.view, [], this.fw, 240);
    this.pic = sh.pic;
    this.sel = overlay(this.fw, 240);
    this.sel.classList.add("fades");
    this.pointer = el("div", "pointer", POINTER);
    f.append(sh, this.sel, this.pointer);
    s.append(f);
    this.m = new Motion((m) => this.draw(m.get("t"), m.get("ptr"))).add("t", 0, 0.0005).add("ptr", 0, 0.0005);
    return s;
  }
  draw(t, ptr) {
    this.note.x = lerp(this.from.x, this.to.x, t);
    this.note.y = lerp(this.from.y, this.to.y, t);
    this.pic.update([this.arrow, this.note]);
    const tag = [...this.pic.querySelectorAll("svg.marks rect")].find((r) => r.getAttribute("fill") === "#e03131");
    if (!tag) return;
    const k = this.k, pad = 4;
    const x = (+tag.getAttribute("x") - this.view.x) * k - pad, y = (+tag.getAttribute("y") - this.view.y) * k - pad;
    const w = +tag.getAttribute("width") * k + 2 * pad, h = +tag.getAttribute("height") * k + 2 * pad;
    // The selection as the editor draws it: a blue outline over a light edge, and four handles.
    this.sel.innerHTML = this.selected ? `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="none" stroke="rgb(255 255 255 / .9)" stroke-width="3.5"/>
      <rect x="${x}" y="${y}" width="${w}" height="${h}" fill="none" stroke="#3182ed" stroke-width="1.5"/>
      ${[[0, 0], [1, 0], [0, 1], [1, 1]].map(([i, j]) => `<rect x="${x + i * w - 4}" y="${y + j * h - 4}" width="8" height="8" fill="#101011" stroke="#3182ed" stroke-width="1.5"/>`).join("")}` : "";
    const px = x + w * 0.6, py = y + h * 0.45;
    this.pointer.style.transform = `translate(${lerp(this.fw - 30, px, ptr) - 10}px, ${lerp(232, py, ptr) - 7}px)`;
  }
  reset() {
    this.selected = false;
    this.pointer.classList.remove("down");
    for (const e of [this.sel, this.pointer, this.pic.querySelector("svg.marks")]) e.style.opacity = 1;
    this.m.jump("ptr", 0); this.m.jump("t", 0);
  }
  final() { this.selected = true; this.pointer.classList.remove("down"); this.m.jump("ptr", 1); this.m.jump("t", 1); }
  async play() {
    this.reset();
    await this.m.to("ptr", 1, 0.5);
    this.pointer.classList.add("down");
    this.selected = true;
    this.draw(0, 1);
    await wait(0.15);
    await this.m.to("t", 1, 0.6);
    this.pointer.classList.remove("down");
  }
  async rewind() {
    for (const e of [this.sel, this.pointer, this.pic.querySelector("svg.marks")]) e.style.opacity = 0;
    await wait(0.25);
  }
}
