import { el, place, Motion, wait, motion, tween } from "../vignette.js";
import { IMAGES, PERSON_MARKS } from "../cards.js";
import { lerp, GUTTER, shot, overlay, POINTER, smallFit, wideFit } from "./parts.js";

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
// A hand's pace along a path: slow to start, quick in the middle, slow to stop.
const handEase = (t) => (t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2);
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
    this.k = 0.6;
    // A region inside the map card, so the editor's frame is the only rounded edge, wide enough
    // that Pienza's stop is whole with room to its right.
    const fh = Math.round((426 - 158) * this.k);
    this.view = { x: 1100, y: 158, w: this.fw / this.k, h: fh / this.k };
    const f = el("div", "frame-x");
    place(f, { x: GUTTER, y: 0, w: this.fw, h: fh });
    const sh = shot(IMAGES.itin, this.view, [], this.fw, fh);
    this.pic = sh.pic;
    this.cursor = el("div", "crosshair", CROSSHAIR);
    f.append(sh, this.cursor);
    s.append(f);
    const [x, y] = Arrows.STROKE[0];
    this.rest = [x - 50, y + 85];
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
        const e = handEase(t);
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
  static fit = smallFit(206);
  build({ W, H }) {
    const s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    this.fw = W - GUTTER + 40;
    this.k = 0.4;
    // Both ends of the arrow and both places of the note, inside the height every tile shows.
    this.view = { x: 790, y: 218, w: this.fw / this.k, h: 240 / this.k };
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
    // The note is gripped in its tag's right padding, so the pointer never covers its words.
    const px = x + w - pad - 6, py = y + h * 0.5;
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

export class Quick {
  // The crosshair comes in from the space beside the stays page's title and drags a box around it
  // from its top right. Typing starts the moment the button comes up, and the note appears under
  // the box, where the drag ended.
  static fit = wideFit(236);
  static BOX = { type: "rect", who: "person", x: 40, y: 192, w: 588, h: 86 };
  static NOTE = { type: "note", who: "person", x: 40, y: 292, text: "make this quieter" };
  static REST = [420, 152];
  build({ W, H }) {
    const s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    const fw = W - GUTTER + 40, fh = H + 40, k = this.k = 0.5;
    this.view = { x: 0, y: 120, w: fw / k, h: fh / k };
    const f = el("div", "frame-x");
    place(f, { x: GUTTER, y: 0, w: fw, h: fh });
    const sh = shot(IMAGES.stays, this.view, [], fw, fh);
    this.pic = sh.pic;
    this.marks = this.pic.querySelector("svg.marks");
    this.cursor = el("div", "crosshair", CROSSHAIR);
    f.append(sh, this.cursor);
    s.append(f);
    return s;
  }
  // `p` is the crosshair's way to the box's first corner and `t` the drag, each 0 to 1.
  draw(p, t) {
    const b = Quick.BOX, corner = [b.x + b.w, b.y];
    const box = { ...b, x: corner[0] - b.w * t, w: b.w * t, h: b.h * t };
    this.pic.update(t > 0.01 ? [box] : []);
    const [x, y] = t > 0 ? [box.x, box.y + box.h] : [lerp(Quick.REST[0], corner[0], p), lerp(Quick.REST[1], corner[1], p)];
    this.cursor.style.transform = `translate(${(x - this.view.x) * this.k - 10.5}px, ${(y - this.view.y) * this.k - 10.5}px)`;
  }
  reset() { this.draw(0, 0); this.marks.style.opacity = 1; this.cursor.style.opacity = 1; }
  final() { this.draw(1, 1); this.cursor.style.opacity = 0; this.marks.style.opacity = 1; this.pic.update([Quick.BOX, Quick.NOTE]); }
  async play() {
    this.reset();
    await tween(0.3, (p) => this.draw(handEase(p), 0));
    await tween(0.55, (t) => this.draw(1, handEase(t)));
    await wait(0.1);
    this.cursor.style.opacity = 0;
    const text = Quick.NOTE.text;
    for (let n = 1; n <= text.length; n++) {
      const note = { ...Quick.NOTE, text: text.slice(0, n) };
      this.pic.update([Quick.BOX, note], note);
      await wait(n === 1 ? 0.12 : 0.055);
    }
    this.pic.update([Quick.BOX, Quick.NOTE]);
  }
  async rewind() { this.marks.style.opacity = 0; this.cursor.style.opacity = 0; await wait(0.25); }
}
