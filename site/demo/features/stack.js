// The pictures of the tiles under the first stage: the recent stack sliding in, a stitch, and a
// card dragged out. Each column of cards rests against the picture's right edge, the newest at the
// bottom, as the stack does against the screen's.
import { el, place, Motion, UI, wait, cardSize, coverRect } from "../vignette.js";
import { IMAGES, PERSON_MARKS } from "../cards.js";
import { lerp, clamp, GUTTER, card, whole, shot, wideFit, POINTER } from "./parts.js";

const CW = 140, CH = 88, STEP = CH + UI.cardSpacing;
// The cards' scale against the app's: a 16:10 screenshot's card is 188 pt wide there.
const SCALE = CW / UI.cardMaxWidth;
const NOTE = { type: "note", who: "person", x: 40, y: 292, text: "make this quieter" };
const BOX = { type: "rect", who: "person", x: 40, y: 192, w: 588, h: 86 };
// Oldest first.
const SHOTS = [
  [IMAGES.itin, whole(IMAGES.itin), PERSON_MARKS.slice(0, 2)],
  [IMAGES.packing, whole(IMAGES.packing), []],
  [IMAGES.chat, { x: 0, y: 200, w: 1040, h: 650 }, []],
  [IMAGES.stays, whole(IMAGES.stays), [BOX, NOTE]],
];
const at = (node, x, y, s = 1) => { node.style.transform = `translate(${x}px, ${y}px) scale(${s})`; };
async function tap(key, hold = 0.09) { key.classList.add("down"); await wait(hold); key.classList.remove("down"); }

class Column {
  scene(W, H) {
    const s = this.s = el("div", "scene fades");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    this.W = W; this.R = W - 24; this.bottom = H - 14;
    return s;
  }
  // The cards for `list`, the last at the bottom.
  column(list) {
    return list.map(([image, view, marks], i) => {
      const c = card(image, view, marks, { x: this.R - CW, y: this.bottom - CH - (list.length - 1 - i) * STEP, w: CW, h: CH });
      this.s.append(c);
      return c;
    });
  }
  shown() { this.s.style.opacity = 1; }
  async rewind() { this.s.style.opacity = 0; await wait(0.25); }
}

export class Recent extends Column {
  // Right Shift goes down twice, and the cards slide in from the screen's edge, the newest first.
  static fit = wideFit(236);
  build({ W, H }) {
    const s = this.scene(W, H);
    this.cards = this.column(SHOTS);
    const y = this.bottom - CH - 38;
    this.key = el("div", "kcap shiftk", "<span>⇧</span>");
    place(this.key, { x: GUTTER, y });
    this.twice = el("div", "twice", "×2");
    place(this.twice, { x: GUTTER + 104, y: y + 12 });
    s.append(this.key, this.twice);
    this.off = W - (this.R - CW) + 24;
    this.m = this.cards.map((c) => new Motion((m) => at(c, m.get("x"), 0)).add("x", this.off, 0.05));
    return s;
  }
  reset() { this.shown(); this.twice.classList.remove("on"); this.m.forEach((m) => m.jump("x", this.off)); }
  final() { this.reset(); this.twice.classList.add("on"); this.m.forEach((m) => m.jump("x", 0)); }
  async play() {
    this.reset();
    await wait(0.25);
    await tap(this.key); await wait(0.11); await tap(this.key);
    this.twice.classList.add("on");
    await wait(0.08);
    const newestFirst = [...this.m].reverse();
    await Promise.all(newestFirst.map(async (m, i) => {
      await wait(Math.min(UI.stagger * i, UI.staggerMax));
      await m.to("x", 0, UI.slideIn, UI.flightBounce);
    }));
  }
}

// Stitch.compose's layout and badges: every column count is tried and the one a reader's resize
// keeps most of wins (Stitch.readerScale: a long side of 1568 px and 1568 patches of 28 px).
function readerScale(w, h) {
  const tokens = (s) => Math.ceil(Math.round(w * s) / 28) * Math.ceil(Math.round(h * s) / 28);
  let s = Math.min(1, 1568 / Math.max(w, h), Math.sqrt((1568 * 28 * 28) / (w * h)));
  while (s > 0.01 && tokens(s) > 1568) s *= 0.995;
  return s;
}
function stitchLayout(sizes) {
  const sum = (a) => a.reduce((x, y) => x + y, 0);
  const gap = clamp(Math.round(0.02 * Math.min(...sizes.map((s) => Math.min(s.w, s.h)))), 12, 48);
  let best = null;
  for (let columns = 1; columns <= sizes.length; columns++) {
    const rows = Math.ceil(sizes.length / columns), cw = Array(columns).fill(0), rh = Array(rows).fill(0);
    sizes.forEach((s, i) => { cw[i % columns] = Math.max(cw[i % columns], s.w); rh[Math.floor(i / columns)] = Math.max(rh[Math.floor(i / columns)], s.h); });
    const w = gap * 2 + sum(cw) + gap * (columns - 1), h = gap * 2 + sum(rh) + gap * (rows - 1);
    const frames = sizes.map((s, i) => {
      const c = i % columns, r = Math.floor(i / columns);
      return { x: gap + sum(cw.slice(0, c)) + gap * c + (cw[c] - s.w) / 2, y: gap + sum(rh.slice(0, r)) + gap * r + (rh[r] - s.h) / 2, w: s.w, h: s.h };
    });
    const plan = { w, h, frames, scale: readerScale(w, h) };
    if (!best || plan.scale > best.scale + 0.001) best = plan;
  }
  return best;
}
const badgeDiameter = (s) => { const short = Math.min(s.w, s.h); return Math.min(clamp(Math.round(0.06 * short), 32, 128), Math.round(0.8 * short)); };

export class Stitch extends Column {
  // Three cards are picked and ⌘S goes down: they fly into one slot while the stitched image fades
  // in under them, each into its place in it, and the new card says Copied. The card above them
  // moves down to it.
  static fit = wideFit(236);
  build({ W, H }) {
    const s = this.scene(W, H);
    const picked = SHOTS.slice(1);
    const plan = stitchLayout(picked.map(([, view]) => view));
    const size = cardSize(plan);
    this.slot = { w: size.w * SCALE, h: size.h * SCALE };
    Object.assign(this.slot, { x: this.R - this.slot.w, y: this.bottom - this.slot.h });
    this.result = el("div", "cardx");
    place(this.result, this.slot);
    const clip = el("div", "shot");
    const pic = coverRect(this.slot, plan), k = pic.w / plan.w;
    const sheet = el("div", "stitched");
    place(sheet, pic);
    this.pieces = plan.frames.map((f, i) => {
      const r = { x: f.x * k, y: f.y * k, w: f.w * k, h: f.h * k };
      const [image, view, marks] = picked[i];
      const p = shot(image, view, marks, r.w, r.h);
      place(p, r);
      const d = badgeDiameter(f) * k;
      const b = el("div", "sbadge", String(i + 1));
      Object.assign(b.style, { left: `${d / 4}px`, top: `${d / 4}px`, width: `${d}px`, height: `${d}px`, fontSize: `${d * 0.6}px` });
      p.append(b);
      sheet.append(p);
      return { x: this.slot.x + pic.x + r.x, y: this.slot.y + pic.y + r.y, w: r.w };
    });
    clip.append(sheet);
    this.notice = el("div", "notice", '<div class="check"></div><b>Copied</b>');
    this.result.append(clip, this.notice);
    // The oldest card stays out of the stitch; the three under it are picked top to bottom.
    this.keep = this.column(SHOTS.slice(0, 1))[0];
    this.keepFrom = this.bottom - CH - 3 * STEP;
    this.keepTo = this.slot.y - UI.cardSpacing - CH;
    this.keep.style.top = `${this.keepFrom}px`;
    s.append(this.result);
    this.cards = picked.map(([image, view, marks], i) => {
      const c = card(image, view, marks, { x: 0, y: 0, w: CW, h: CH });
      c.classList.add("flying");
      c.num = el("div", "scircle", String(i + 1));
      c.append(c.num);
      c.from = { x: this.R - CW, y: this.bottom - CH - (2 - i) * STEP };
      s.append(c);
      return c;
    });
    this.key = el("div", "kcap", "⌘S");
    place(this.key, { x: GUTTER, y: this.bottom - CH - 30 });
    s.append(this.key);
    this.m = new Motion((m) => {
      const t = m.get("t");
      this.cards.forEach((c, i) => {
        const to = this.pieces[i];
        at(c, lerp(c.from.x, to.x, t), lerp(c.from.y, to.y, t), lerp(1, to.w / CW, t));
        c.style.opacity = clamp((1 - t) / 0.25, 0, 1);
      });
      this.result.style.opacity = clamp(t * 1.4, 0, 1);
      this.keep.style.transform = `translateY(${m.get("close") * (this.keepTo - this.keepFrom)}px)`;
    }).add("t", 0, 0.001).add("close", 0, 0.001);
    return s;
  }
  pick(on) { this.cards.forEach((c) => { c.classList.toggle("picked", on); c.num.classList.toggle("on", on); }); }
  reset() { this.shown(); this.pick(true); this.notice.classList.remove("in"); this.m.jump("t", 0); this.m.jump("close", 0); }
  final() { this.reset(); this.pick(false); this.m.jump("t", 1); this.m.jump("close", 1); }
  async play() {
    this.reset();
    await wait(0.5);
    await tap(this.key, 0.12);
    this.pick(false);
    this.m.to("close", 1, UI.relayout);
    await this.m.to("t", 1, UI.expand, UI.flightBounce);
    this.notice.classList.add("in");
    await wait(UI.noticeSeconds);
    this.notice.classList.remove("in");
  }
}

export class Drag extends Column {
  // The newest card, which has a drawing, is dragged out of the stack into Claude Code, and the
  // prompt takes it as an image. The card stays in the stack.
  static fit = wideFit(236);
  build({ W, H }) {
    const s = this.scene(W, H);
    const t = el("div", "term-x", '<div class="bar-t"><i></i><i></i><i></i></div><pre><div class="ln"><span class="t-claude">●</span> Which stay should we change?</div><div class="ln"> </div><div class="pbox">&gt; <span class="typed"></span><span class="tcur"></span></div></pre>');
    place(t, { x: GUTTER, y: 0, w: W - GUTTER + 40, h: H + 40 });
    this.typed = t.querySelector(".typed");
    s.append(t);
    this.column(SHOTS.slice(1));
    // The drag image is the card at its own size, held where the pointer took it.
    const [image, view, marks] = SHOTS[3];
    this.ghost = card(image, view, marks, { x: 0, y: 0, w: CW, h: CH });
    this.ghost.classList.add("ghost");
    s.append(this.ghost);
    this.pointer = el("div", "pointer", POINTER);
    s.append(this.pointer);
    this.grab = { x: CW * 0.55, y: CH * 0.55 };
    this.from = { x: this.R - CW + this.grab.x, y: this.bottom - CH + this.grab.y };
    this.drop = { x: Math.min(GUTTER + 250, this.R - CW - 30), y: 108 };
    this.m = new Motion((m) => {
      const t = m.get("t"), p = m.get("p");
      const x = t > 0 ? lerp(this.from.x, this.drop.x, t) : lerp(W + 10, this.from.x, p);
      const y = t > 0 ? lerp(this.from.y, this.drop.y, t) - Math.sin(Math.PI * t) * 30 : lerp(this.from.y + 50, this.from.y, p);
      at(this.pointer, x - 10, y - 7);
      at(this.ghost, x - this.grab.x, y - this.grab.y);
    }).add("t", 0, 0.001).add("p", 0, 0.001);
    return s;
  }
  dropped(on) { this.typed.textContent = on ? "[Image #1] " : ""; }
  reset() { this.shown(); this.ghost.style.opacity = 0; this.pointer.classList.remove("down"); this.dropped(false); this.m.jump("p", 0); this.m.jump("t", 0); }
  final() { this.reset(); this.m.jump("p", 1); this.m.jump("t", 1); this.dropped(true); }
  async play() {
    this.reset();
    await wait(0.25);
    await this.m.to("p", 1, 0.45);
    this.pointer.classList.add("down");
    await wait(0.12);
    this.ghost.style.opacity = 1;
    await this.m.to("t", 1, 0.7);
    this.pointer.classList.remove("down");
    this.ghost.style.opacity = 0;
    this.dropped(true);
  }
}
