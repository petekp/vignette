import { el, Motion, Spring, UI, wait } from "../vignette.js";
import { IMAGES, PERSON_MARKS } from "../cards.js";
import { lerp, clamp, GUTTER, card, whole, smallFit } from "./parts.js";

const CW = 128, CH = 80;
// How long the card is in the air before Esc goes down.
const ESC_AT = 0.22;
// The onion skins: where they sit along the way out, as fractions of how far the card got, and how
// strongly each shows, faintest by the slot.
const SKINS = [[0.3, 0.018], [0.55, 0.026], [0.78, 0.034], [1, 0.042]];
const SVG_NS = "http://www.w3.org/2000/svg";

export class Flight {
  // A card leaves its slot in the stack for the editor. Esc goes down while it is in the air, and
  // it turns around from where it is and lands back in its slot, which the stack held open. The
  // trace stays as the picture of the flight: a line along the arc its leading corner travelled,
  // fuller toward the dot where it turned, over soft onion skins of the card along the way.
  static fit = smallFit(222);
  build({ W, H }) {
    const s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    const x = W - GUTTER - CW;
    this.slot = { x, y: 4 + CH + UI.cardSpacing, w: CW, h: CH };
    const ew = Math.min(200, W * 0.54);
    this.editor = { x: GUTTER, y: 4, w: ew, h: ew * 0.625 };
    this.trace = el("div", "trace");
    this.skins = SKINS.map(([at, o]) => {
      const g = el("div", "skin");
      const r = this.rect(at * Flight.farthest());
      Object.assign(g.style, { left: `${r.x}px`, top: `${r.y}px`, width: `${r.w}px`, height: `${r.h}px` });
      g.style.setProperty("--o", o);
      g.at = at * Flight.farthest();
      this.trace.append(g);
      return g;
    });
    const svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("class", "over");
    svg.setAttribute("viewBox", `0 0 ${W} ${H}`);
    svg.innerHTML = '<path class="arc" fill="currentColor"/><g class="turn"><circle r="7" fill="currentColor" opacity="0.12"/><circle r="3.2" fill="currentColor" opacity="0.75"/></g>';
    this.trace.append(svg);
    this.arc = svg.querySelector(".arc");
    this.turn = svg.querySelector(".turn");
    s.append(this.trace);
    // The cards above and below it in the stack.
    const rest = [[IMAGES.stays, whole(IMAGES.stays), 0], [IMAGES.packing, whole(IMAGES.packing), 2]];
    for (const [image, view, i] of rest) s.append(card(image, view, [], { x, y: 4 + i * (CH + UI.cardSpacing), w: CW, h: CH }));
    this.card = card(IMAGES.itin, { x: 1050, y: 230, w: 760, h: 475 }, PERSON_MARKS.slice(0, 2), { x: 0, y: 0, w: CW, h: CH });
    this.card.classList.add("flying");
    s.append(this.card);
    this.key = el("div", "kcap esc", "esc");
    // Under the farthest skin, which the bow carries below the editor's own rect.
    this.key.style.left = `${GUTTER}px`;
    this.key.style.top = `${this.editor.y + this.editor.h + 36}px`;
    s.append(this.key);
    this.m = new Motion((m) => this.draw(m.get("p"))).add("p", 0, 0.0005);
    return s;
  }
  // How far out the card gets before Esc turns it, from the same spring a play runs, so the poster
  // shows the trace a play leaves.
  static farthest() {
    if (Flight.far) return Flight.far;
    const s = new Spring(0, 0.0005).to(1, UI.expand, UI.flightBounce), dt = 1 / 240;
    let t = 0, far = 0;
    while (t < ESC_AT) { s.step(dt); t += dt; far = Math.max(far, s.x); }
    s.to(0, UI.expand, UI.flightBounce);
    while (s.moving && t < 3) { s.step(dt); t += dt; far = Math.max(far, s.x); }
    return (Flight.far = far);
  }
  // The card's leading corner, which stays outside the card as it flies, so its path shows.
  corner(p) { const r = this.rect(p); return [r.x, r.y]; }
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
    if (this.tracing && p > this.reached) this.show(p, this.turned);
  }
  // The trace out to `far`: the skins the card has passed, and the arc as a filled shape 0.4 pt
  // wide at the slot and 3 pt at the far end, so it tapers without joins.
  show(far, turned) {
    this.reached = far; this.turned = turned;
    this.skins.forEach((g) => g.classList.toggle("on", g.at <= far + 0.03));
    this.turn.classList.toggle("on", turned);
    const [tx, ty] = this.corner(far);
    this.turn.setAttribute("transform", `translate(${tx} ${ty})`);
    if (far < 0.02) { this.arc.setAttribute("d", ""); return; }
    const n = 40, pts = Array.from({ length: n + 1 }, (_, i) => this.corner((i / n) * far));
    const left = [], right = [];
    pts.forEach(([x, y], i) => {
      const [ax, ay] = pts[Math.max(0, i - 1)], [bx, by] = pts[Math.min(n, i + 1)];
      const len = Math.hypot(bx - ax, by - ay) || 1, nx = -(by - ay) / len, ny = (bx - ax) / len;
      const w = (0.4 + 2.6 * (i / n)) / 2;
      left.push([x + nx * w, y + ny * w]); right.push([x - nx * w, y - ny * w]);
    });
    this.arc.setAttribute("d", `M${[...left, ...right.reverse()].map(([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`).join(" L")} Z`);
  }
  reset() {
    this.trace.style.opacity = 1;
    this.tracing = false;
    this.show(0, false);
    this.key.classList.remove("down");
    this.m.jump("p", 0);
  }
  final() { this.reset(); this.show(Flight.farthest(), true); }
  async play() {
    this.reset();
    await wait(0.15);
    this.tracing = true;
    this.m.to("p", 1, UI.expand, UI.flightBounce);
    await wait(ESC_AT);
    this.key.classList.add("down");
    this.show(this.reached, true);
    const back = this.m.to("p", 0, UI.expand, UI.flightBounce);
    await wait(0.14);
    this.key.classList.remove("down");
    await back;
    this.tracing = false;
  }
  async rewind() {
    this.trace.style.opacity = 0;
    await wait(0.25);
  }
}
