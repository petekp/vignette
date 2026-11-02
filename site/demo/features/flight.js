import { el, Motion, Spring, UI, wait, motion } from "../vignette.js";
import { IMAGES, PERSON_MARKS } from "../cards.js";
import { lerp, clamp, GUTTER, card, whole, smallFit, POINTER } from "./parts.js";

export const CW = 140, CH = 88;
// Look.card and Look.annotator: the shadow a card casts in the stack and the editor's frame casts.
const LOOK = {
  card: { y: 4, blur: 8, spread: 0, alpha: 0.35 },
  annotator: { y: 18, blur: 40, spread: -14, alpha: 0.5 },
};
const center = (r) => ({ x: r.x + r.w / 2, y: r.y + r.h / 2 });

// Anim.passesTarget: when the flight's spring first reaches its target, which is when the editor's
// window, and its bar, come up behind the flight.
export function passesTarget() {
  const s = new Spring(0, 1e-6).to(1, UI.expand, UI.flightBounce);
  let t = 0;
  while (s.moving && s.x < 1) { s.step(1 / 240); t += 1 / 240; }
  return t;
}

// FlightCurve.placement: how far a card the straight path has carried to `p` is drawn to one side
// of it, and how much larger. Both peak in the middle and are nothing at the ends. The side belongs
// to the line, not the direction of travel: up from a path that runs mostly sideways, left from
// one that runs mostly up or down.
function placement(path, p, amount) {
  const dx = path.to.x - path.from.x, dy = path.to.y - path.from.y, len = Math.hypot(dx, dy);
  if (len <= 0.5) return { x: 0, y: 0, s: 1 };
  const t = clamp(((p.x - path.from.x) * dx + (p.y - path.from.y) * dy) / (len * len), 0, 1);
  const peak = 4 * t * (1 - t);
  let nx = -dy / len, ny = dx / len;
  if (Math.abs(dx) >= Math.abs(dy) ? ny > 0 : nx > 0) { nx = -nx; ny = -ny; }
  const bow = Math.min(len * UI.flightArc, UI.flightArcMax) * amount * peak;
  return { x: nx * bow, y: ny * bow, s: 1 + UI.flightDepth * amount * peak };
}

// A card as the flight layer draws it. It is laid out at the editor frame's size and moved only by
// transforms, so it stays sharp there. Its straight-path rect, its look (0 the card's, 1 the
// editor's) and the blend between its paths are springs, as TransitionLayer animates them: a flight
// aimed somewhere else in mid-air keeps its speed and bends from the old path's bow to the new one's.
export class Flyer {
  constructor(c, size) {
    this.c = c; this.size = size;
    this.path = this.was = null;
    this.flying = false;
    this.gen = 0;
    // Arrival is the rect within half a point of its target, as Anim.settle times it.
    this.m = new Motion(() => this.draw())
      .add("x", 0, 0.5).add("y", 0, 0.5).add("w", size.w, 0.5).add("h", size.h, 0.5)
      .add("look", 0, 0.001).add("blend", 1, 0.001);
  }
  rect() { const m = this.m; return { x: m.get("x"), y: m.get("y"), w: m.get("w"), h: m.get("h") }; }
  draw(amount = motion()) {
    const r = this.rect(), o = center(r), b = this.m.get("blend");
    const flat = { x: 0, y: 0, s: 1 };
    const was = this.was ? placement(this.was, o, amount) : flat, now = this.path ? placement(this.path, o, amount) : flat;
    const s = lerp(was.s, now.s, b), w = r.w * s, h = r.h * s;
    const x = o.x + lerp(was.x, now.x, b) - w / 2, y = o.y + lerp(was.y, now.y, b) - h / 2;
    const sx = w / this.size.w, sy = h / this.size.h, c = this.c;
    c.style.transform = `translate(${x}px, ${y}px) scale(${sx}, ${sy})`;
    c.style.borderRadius = `${UI.cardCorner / sx}px / ${UI.cardCorner / sy}px`;
    c.style.setProperty("--ring", `${0.5 / sx}px`);
    const t = clamp(this.m.get("look"), 0, 1), a = LOOK.card, e = LOOK.annotator;
    c.style.boxShadow = `0 ${lerp(a.y, e.y, t) / sy}px ${lerp(a.blur, e.blur, t) / sx}px ${lerp(a.spread, e.spread, t) / sx}px rgb(0 0 0 / ${lerp(a.alpha, e.alpha, t)})`;
  }
  // Put it at `r` with `look`, on no path. `amount` draws the bow as a moment of a flight would show
  // it, for a still.
  at(r, look, path, amount) {
    this.gen++;
    this.flying = false;
    for (const k of ["x", "y", "w", "h"]) this.m.springs[k].jump(r[k]);
    this.m.springs.look.jump(look);
    this.m.springs.blend.jump(1);
    this.path = path || null; this.was = null;
    this.draw(amount);
  }
  // A change of size where it is, such as the hover: no flight, so no bow.
  grow(r, duration, bounce) {
    if (!this.flying) this.path = this.was = null;
    for (const k of ["x", "y", "w", "h"]) this.m.to(k, r[k], duration, bounce);
  }
  // Flies to `to` on the app's flight spring. A new flight is drawn over every flight before it; one
  // aimed again keeps its place. Answers true on arrival, or false when aimed elsewhere first.
  async fly(to, look) {
    const path = { from: center(this.rect()), to: center(to) };
    if (this.flying) {
      this.was = this.path;
      this.m.jump("blend", 0);
    } else {
      this.was = null;
      this.c.parentNode.append(this.c);
    }
    this.path = path;
    this.flying = true;
    const gen = ++this.gen;
    const spring = (k, v) => this.m.to(k, v, UI.expand, UI.flightBounce);
    spring("look", look); spring("blend", 1);
    await Promise.all(["x", "y", "w", "h"].map((k) => spring(k, to[k])));
    if (gen !== this.gen) return false;
    this.at(to, look, null);
    return true;
  }
}

// The three cards in the stack, top to bottom. The first starts in the editor.
const LIST = [
  [IMAGES.itin, { x: 1050, y: 230, w: 760, h: 475 }, PERSON_MARKS.slice(0, 2)],
  [IMAGES.stays, whole(IMAGES.stays), []],
  [IMAGES.packing, whole(IMAGES.packing), []],
];
// The card in the editor at first, the card clicked first, which turns home in mid-air, and the
// card clicked while it is in the air, which ends in the editor. The two clicked last are the top
// and the bottom, so the turning flight and the new one take paths apart.
const START = 1, TURNS = 0, LAST = 2;
// How far down the picture the stack and the editor start: room for a flight's bow above them.
const TOP = 26;

export class Flight {
  // The middle card is in the editor. The pointer clicks the top card in the stack: the card in the
  // editor flies home while the clicked one flies out, two bowed flights at once, and the stack
  // holds the slot of the card that is out. Before that card reaches the editor the pointer clicks
  // the bottom one, and it turns home in mid-air. The stack is drawn narrowed for the editor
  // throughout.
  static fit = smallFit(214);
  build({ W, H }) {
    const s = this.s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    this.W = W;
    const right = W - 24, room = right - GUTTER - UI.stackGap;
    const fw = Math.round(room * 0.72);
    this.frame = { x: GUTTER, y: TOP, w: fw, h: fw * (CH / CW) };
    // StackLayout.widthScale: the widest the stack can be drawn and still clear the editor by the gap.
    const k = clamp((right - (this.frame.x + this.frame.w + UI.stackGap)) / CW, UI.stackMinScale, 1);
    this.slots = LIST.map((_, i) => ({ x: right - CW * k, y: TOP + i * (CH + UI.cardSpacing) * k, w: CW * k, h: CH * k }));
    const layer = el("div", "flights");
    s.append(layer);
    this.cards = LIST.map(([image, view, marks]) => {
      const c = card(image, view, marks, { x: 0, y: 0, w: this.frame.w, h: this.frame.h });
      c.classList.add("flying");
      layer.append(c);
      return new Flyer(c, this.frame);
    });
    this.pointer = el("div", "pointer", POINTER);
    s.append(this.pointer);
    this.pm = new Motion((m) => {
      this.pointer.style.transform = `translate(${m.get("x") - 10}px, ${m.get("y") - 7}px)`;
    }).add("x", W + 20, 0.05).add("y", 120, 0.05);
    return s;
  }
  hovered(i) {
    const r = this.slots[i], g = UI.hoverScale;
    return { x: r.x - (r.w * (g - 1)) / 2, y: r.y - (r.h * (g - 1)) / 2, w: r.w * g, h: r.h * g };
  }
  // `open` in the editor, and the pointer resting at `at`, or off the right edge.
  hold(open, at) {
    this.cards.forEach((f, i) => f.at(i === open ? this.frame : this.slots[i], i === open ? 1 : 0));
    this.pm.jump("x", at ? at.x : this.W + 20); this.pm.jump("y", at ? at.y : 120);
    this.pointer.classList.remove("down");
  }
  aim(i) { const r = this.slots[i]; return { x: r.x + r.w * 0.55, y: r.y + r.h * 0.45 }; }
  reset() { this.hold(START); }
  final() { this.hold(LAST, this.aim(LAST)); }
  // With Reduce Motion: the first swap mid-air, the card from the editor crossing the clicked card
  // on its way out, both slots held.
  poster() {
    this.hold(START, this.aim(TURNS));
    const at = (i, from, to, p, look) => {
      const r = { x: lerp(from.x, to.x, p), y: lerp(from.y, to.y, p), w: lerp(from.w, to.w, p), h: lerp(from.h, to.h, p) };
      this.cards[i].at(r, look, { from: center(from), to: center(to) }, 1);
    };
    at(START, this.frame, this.slots[START], 0.34, 0.66);
    at(TURNS, this.hovered(TURNS), this.frame, 0.34, 0.34);
    this.cards[TURNS].c.parentNode.append(this.cards[TURNS].c);
  }
  // The pointer reaches card `next`, which grows under it, and clicks: the card in the editor
  // flies home as `next` flies out, over it.
  async swap(open, next) {
    const at = this.aim(next), c = this.cards[next];
    await Promise.all([this.pm.to("x", at.x, 0.4), this.pm.to("y", at.y, 0.4)]);
    c.grow(this.hovered(next), 0.25);
    await wait(0.18);
    this.pointer.classList.add("down");
    await wait(0.09);
    this.pointer.classList.remove("down");
    this.cards[open].fly(this.slots[open], 0);
    c.fly(this.frame, 1);
  }
  async play() {
    this.reset();
    await wait(0.2);
    await this.swap(START, TURNS);
    // The last card is clicked while the first is still on its way out, before the editor's window
    // comes up. As in AnnotatorTransition's flyingOut, the first turns home from where it is and the
    // last flies out.
    const turn = passesTarget() * 0.45, at = this.aim(LAST);
    this.pm.to("x", at.x, turn); this.pm.to("y", at.y, turn);
    this.cards[LAST].grow(this.hovered(LAST), 0.25);
    await wait(turn * 0.6);
    this.pointer.classList.add("down");
    await wait(turn * 0.4);
    this.pointer.classList.remove("down");
    this.cards[TURNS].fly(this.slots[TURNS], 0);
    await this.cards[LAST].fly(this.frame, 1);
  }
  // The card in the editor goes home as the first one comes back out, and the pointer leaves.
  async rewind() {
    this.pm.to("x", this.W + 20, 0.4);
    this.cards[LAST].fly(this.slots[LAST], 0);
    await this.cards[START].fly(this.frame, 1);
    await wait(0.1);
  }
}
