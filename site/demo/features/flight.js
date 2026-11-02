import { el, Motion, UI, wait, motion } from "../vignette.js";
import { IMAGES, PERSON_MARKS } from "../cards.js";
import { lerp, clamp, GUTTER, card, whole, smallFit, POINTER } from "./parts.js";

const CW = 128, CH = 80;
// The three cards in the stack, top to bottom. The first starts in the editor.
const LIST = [
  [IMAGES.itin, { x: 1050, y: 230, w: 760, h: 475 }, PERSON_MARKS.slice(0, 2)],
  [IMAGES.stays, whole(IMAGES.stays), []],
  [IMAGES.packing, whole(IMAGES.packing), []],
];
// Look.card and Look.annotator: the shadow a card casts in the stack and the editor's frame casts.
const LOOK = {
  card: { y: 4, blur: 8, spread: 0, alpha: 0.35 },
  annotator: { y: 18, blur: 40, spread: -14, alpha: 0.5 },
};

export class Flight {
  // A card is in the editor. The pointer clicks the bottom card in the stack, then the middle one:
  // each time the card in the editor flies home while the clicked one flies out, two bowed flights
  // at once, and the stack holds the slot of the card that is out.
  static fit = smallFit(222);
  build({ W, H }) {
    const s = this.s = el("div", "scene fades");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    this.W = W;
    const x = W - GUTTER - CW;
    this.slots = LIST.map((_, i) => ({ x, y: 4 + i * (CH + UI.cardSpacing), w: CW, h: CH }));
    const fw = x - GUTTER - 16;
    this.frame = { x: GUTTER, y: 4, w: fw, h: fw * (CH / CW) };
    // Each card is laid out at the frame's size and scaled down to its slot, so it stays sharp in
    // the editor.
    this.cards = LIST.map(([image, view, marks], i) => {
      const c = card(image, view, marks, { x: 0, y: 0, w: this.frame.w, h: this.frame.h });
      c.classList.add("flying");
      s.append(c);
      c.m = new Motion((m) => this.draw(c, i, m.get("p"), m.get("h"))).add("p", 0, 0.0008).add("h", 0, 0.001);
      return c;
    });
    this.pointer = el("div", "pointer", POINTER);
    s.append(this.pointer);
    this.pm = new Motion((m) => {
      this.pointer.style.transform = `translate(${m.get("x") - 10}px, ${m.get("y") - 7}px)`;
    }).add("x", W + 20, 0.05).add("y", 120, 0.05);
    return s;
  }
  // p is 0 in the slot and 1 in the editor; h is the hover. The path bows to one side of the line
  // between slot and frame and swells in the middle, as FlightCurve does, and the shadow goes from
  // the card's to the editor's.
  draw(c, i, p, h) {
    const slot = this.slots[i], to = this.frame, grow = 1 + (UI.hoverScale - 1) * h;
    const from = { x: slot.x - (slot.w * (grow - 1)) / 2, y: slot.y - (slot.h * (grow - 1)) / 2, w: slot.w * grow, h: slot.h * grow };
    const dx = to.x + to.w / 2 - (from.x + from.w / 2), dy = to.y + to.h / 2 - (from.y + from.h / 2);
    const len = Math.hypot(dx, dy) || 1, nx = -dy / len, ny = dx / len, side = nx < 0 ? -1 : 1;
    const t = clamp(p, 0, 1), m = motion();
    const off = Math.min(UI.flightArc * len, UI.flightArcMax) * m * Math.sin(Math.PI * t) * side;
    const swell = 1 + UI.flightDepth * m * Math.sin(Math.PI * t);
    const w = lerp(from.w, to.w, p) * swell, hh = lerp(from.h, to.h, p) * swell;
    const cx = lerp(from.x + from.w / 2, to.x + to.w / 2, p) + nx * off, cy = lerp(from.y + from.h / 2, to.y + to.h / 2, p) + ny * off;
    const k = w / this.frame.w;
    c.style.transform = `translate(${cx - w / 2}px, ${cy - hh / 2}px) scale(${k})`;
    c.style.borderRadius = `${UI.cardCorner / k}px`;
    const a = LOOK.card, b = LOOK.annotator;
    c.style.boxShadow = `0 ${lerp(a.y, b.y, t) / k}px ${lerp(a.blur, b.blur, t) / k}px ${lerp(a.spread, b.spread, t) / k}px rgb(0 0 0 / ${lerp(a.alpha, b.alpha, t)})`;
    if (!c.leading) c.style.zIndex = p > 0.001 ? 2 : 1;
  }
  // `open` in the editor, and the pointer resting at `at`, or off the right edge.
  hold(open, at) {
    this.cards.forEach((c, i) => { c.leading = false; c.m.jump("h", 0); c.m.jump("p", i === open ? 1 : 0); });
    this.pm.jump("x", at ? at.x : this.W + 20); this.pm.jump("y", at ? at.y : 120);
    this.pointer.classList.remove("down");
  }
  aim(i) { const r = this.slots[i]; return { x: r.x + r.w * 0.55, y: r.y + r.h * 0.4 }; }
  reset() { this.s.style.opacity = 1; this.hold(0); }
  final() { this.reset(); this.hold(1, this.aim(1)); }
  // The pointer reaches card `next`, which grows under it, and clicks: the card in the editor
  // flies home as `next` flies out, over it.
  async swap(open, next) {
    const at = this.aim(next), c = this.cards[next];
    await Promise.all([this.pm.to("x", at.x, 0.4), this.pm.to("y", at.y, 0.4)]);
    c.m.to("h", 1, 0.25);
    await wait(0.18);
    this.pointer.classList.add("down");
    await wait(0.09);
    this.pointer.classList.remove("down");
    this.cards[open].leading = false;
    c.leading = true;
    c.style.zIndex = 3;
    this.cards[open].m.to("p", 0, UI.expand, UI.flightBounce);
    c.m.to("h", 0, UI.expand, UI.flightBounce);
    await c.m.to("p", 1, UI.expand, UI.flightBounce);
  }
  async play() {
    this.reset();
    await wait(0.2);
    await this.swap(0, 2);
    await wait(0.25);
    await this.swap(2, 1);
  }
  async rewind() {
    this.s.style.opacity = 0;
    await wait(0.25);
  }
}
