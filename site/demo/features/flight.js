import { el, Motion, Spring, UI, wait } from "../vignette.js";
import { IMAGES, PERSON_MARKS } from "../cards.js";
import { lerp, clamp, GUTTER, card, whole, smallFit } from "./parts.js";

const CW = 128, CH = 80;
// How long the card is in the air before Esc goes down, and how often the trace keeps an outline.
const ESC_AT = 0.22, TRACE_EVERY = 0.085;

export class Flight {
  // A card leaves its slot in the stack for the editor. Esc goes down while it is in the air, and
  // it turns around from where it is and lands back in its slot, which the stack held open. Faint
  // outlines of the card along the way stay as the picture of the flight.
  static fit = smallFit(222);
  build({ W, H }) {
    const s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    const x = W - GUTTER - CW;
    this.slot = { x, y: 4 + CH + UI.cardSpacing, w: CW, h: CH };
    const ew = Math.min(200, W * 0.54);
    this.editor = { x: GUTTER, y: 4, w: ew, h: ew * 0.625 };
    this.trace = el("div", "trace");
    s.append(this.trace);
    this.outlines = Flight.path().map(([t, p]) => {
      const o = el("div", "outline");
      o.t = t;
      const r = this.rect(p);
      Object.assign(o.style, { left: `${r.x}px`, top: `${r.y}px`, width: `${r.w}px`, height: `${r.h}px` });
      this.trace.append(o);
      return o;
    });
    // The cards above and below it in the stack.
    const rest = [[IMAGES.stays, whole(IMAGES.stays), 0], [IMAGES.packing, whole(IMAGES.packing), 2]];
    for (const [image, view, i] of rest) s.append(card(image, view, [], { x, y: 4 + i * (CH + UI.cardSpacing), w: CW, h: CH }));
    this.card = card(IMAGES.itin, { x: 1050, y: 230, w: 760, h: 475 }, PERSON_MARKS.slice(0, 2), { x: 0, y: 0, w: CW, h: CH });
    this.card.classList.add("flying");
    s.append(this.card);
    this.key = el("div", "kcap esc", "esc");
    this.key.style.left = `${GUTTER}px`; // Under the farthest outline, which the bow carries below the editor's own rect.
    this.key.style.top = `${this.editor.y + this.editor.h + 36}px`;
    s.append(this.key);
    this.m = new Motion((m) => this.draw(m.get("p"))).add("p", 0, 0.0005);
    return s;
  }
  // Where the flight is, every TRACE_EVERY seconds, worked out from the same spring a play runs, so
  // the poster shows the outlines a play leaves.
  static path() {
    if (Flight.points) return Flight.points;
    const s = new Spring(0, 0.0005).to(1, UI.expand, UI.flightBounce), dt = 1 / 240, points = [];
    let t = 0, next = TRACE_EVERY, turned = false;
    while (s.moving && t < 3) {
      if (!turned && t >= ESC_AT) { s.to(0, UI.expand, UI.flightBounce); turned = true; }
      s.step(dt); t += dt;
      if (t >= next) { next += TRACE_EVERY; if (s.x > 0.04) points.push([t, s.x]); }
    }
    return (Flight.points = points);
  }
  // p is 0 in the slot and 1 in the editor. The path bows to one side, as FlightCurve's does.
  rect(p) {
    const a = this.slot, b = this.editor;
    const bow = Math.sin(Math.PI * clamp(p, 0, 1)) * 24;
    return { x: lerp(a.x, b.x, p) + bow * 0.5, y: lerp(a.y, b.y, p) + bow, w: lerp(a.w, b.w, p), h: lerp(a.h, b.h, p) };
  }
  draw(p) {
    const r = this.rect(p), k = r.w / CW, lift = clamp(p, 0, 1);
    this.card.style.transform = `translate(${r.x}px, ${r.y}px) scale(${k})`;
    this.card.style.borderRadius = `${16 / k}px`;
    this.card.style.boxShadow = `0 ${(4 + 14 * lift) / k}px ${(8 + 26 * lift) / k}px rgb(0 0 0 / ${0.35 + 0.2 * lift})`;
  }
  // The outlines a play has left by `t` seconds into the flight.
  show(t) { this.outlines.forEach((o) => o.classList.toggle("on", o.t <= t)); }
  reset() {
    this.trace.style.opacity = 1;
    this.show(-1);
    this.key.classList.remove("down");
    this.m.jump("p", 0);
  }
  final() { this.reset(); this.show(Infinity); }
  async play() {
    this.reset();
    await wait(0.15);
    const start = performance.now();
    const tick = () => {
      this.show((performance.now() - start) / 1000);
      if (this.tracing) requestAnimationFrame(tick);
    };
    this.tracing = true;
    requestAnimationFrame(tick);
    this.m.to("p", 1, UI.expand, UI.flightBounce);
    await wait(ESC_AT);
    this.key.classList.add("down");
    const back = this.m.to("p", 0, UI.expand, UI.flightBounce);
    await wait(0.14);
    this.key.classList.remove("down");
    await back;
    this.tracing = false;
    this.show(Infinity);
  }
  async rewind() {
    this.trace.style.opacity = 0;
    await wait(0.25);
  }
}
