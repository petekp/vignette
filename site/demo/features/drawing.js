import { el, place, Motion, wait } from "../vignette.js";
import { IMAGES, PERSON_MARKS } from "../cards.js";
import { lerp, GUTTER, shot, overlay, POINTER, smallFit } from "./parts.js";

export class Marks {
  // Claude's three versions of a day: a box drawn on the dark one, an arrow from the light page, and
  // a note typed beside it.
  static fit = smallFit(196);
  static MARKS = [
    { type: "rect", who: "person", x: 1222, y: 572, w: 520, h: 210 },
    { type: "arrow", who: "person", x1: 1130, y1: 850, x2: 1225, y2: 760 },
    { type: "note", who: "person", x: 900, y: 860, text: "this one, but lighter" },
  ];
  build({ W, H }) {
    const s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    const fw = W - GUTTER + 40, k = 400 / 940;
    const f = el("div", "frame-x");
    place(f, { x: GUTTER, y: 0, w: fw, h: 230 });
    const sh = shot(IMAGES.variants, { x: 860, y: 520, w: fw / k, h: 230 / k }, [], fw, 230);
    this.pic = sh.pic;
    f.append(sh);
    s.append(f);
    return s;
  }
  show(marks, typing) { this.pic.update(marks, typing); }
  reset() { this.show([]); this.pic.querySelector("svg.marks").style.opacity = 1; }
  final() { this.show(Marks.MARKS); }
  async play() {
    this.reset();
    const [box, arrow, note] = Marks.MARKS;
    const r = { ...box, w: 0, h: 0 };
    await new Motion((m) => { const t = m.get("t"); r.w = box.w * t; r.h = box.h * t; this.show([r]); }).add("t", 0, 0.001).to("t", 1, 0.35);
    const a = { ...arrow, x2: arrow.x1, y2: arrow.y1 };
    await new Motion((m) => { const t = m.get("t"); a.x2 = lerp(arrow.x1, arrow.x2, t); a.y2 = lerp(arrow.y1, arrow.y2, t); this.show([box, a]); }).add("t", 0, 0.001).to("t", 1, 0.3);
    const n = { ...note, text: "" };
    for (const ch of note.text) { n.text += ch; this.show([box, arrow, n], n); await wait(0.045); }
    this.show(Marks.MARKS);
  }
  async rewind() { this.pic.querySelector("svg.marks").style.opacity = 0; await wait(0.25); }
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
