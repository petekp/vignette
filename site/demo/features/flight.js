import { el, Motion, UI, wait } from "../vignette.js";
import { IMAGES, PERSON_MARKS } from "../cards.js";
import { lerp, clamp, GUTTER, card, overlay, smallFit } from "./parts.js";

export class Flight {
  // A card leaves its slot in the stack for the editor, turns around part way, and lands back in
  // its slot, which the stack keeps empty while it is away. The trail stays: out as far as it got,
  // and back.
  static fit = smallFit(200);
  build({ W, H }) {
    const s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    this.slot = { x: W - GUTTER - 128, y: 92, w: 128, h: 80 };
    const ew = Math.min(210, W * 0.56);
    this.editor = { x: GUTTER, y: 4, w: ew, h: ew * 0.625 };
    const e = this.editor, o = this.slot;
    this.svg = overlay(W, H, `<defs><marker id="flight-head" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M1 1 L8 5 L1 9" fill="none" stroke="#0a84ff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></marker></defs>
      <rect x="${e.x}" y="${e.y}" width="${e.w}" height="${e.h}" rx="16" fill="none" stroke="currentColor" stroke-opacity=".2" stroke-width="1.5" stroke-dasharray="4 5"/>
      <rect x="${o.x}" y="${o.y}" width="${o.w}" height="${o.h}" rx="16" fill="none" stroke="currentColor" stroke-opacity=".28" stroke-width="1.5" stroke-dasharray="4 5"/>
      <g class="fades"><polyline class="out" fill="none" stroke="currentColor" stroke-opacity=".35" stroke-width="2" stroke-dasharray="1 5" stroke-linecap="round"/>
      <circle class="turn" r="4" fill="#0a84ff"/>
      <polyline class="back" fill="none" stroke="#0a84ff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></g>`);
    s.append(this.svg);
    this.trail = this.svg.querySelector(".fades");
    this.out = this.svg.querySelector(".out");
    this.back = this.svg.querySelector(".back");
    this.turn = this.svg.querySelector(".turn");
    this.card = card(IMAGES.itin, { x: 1050, y: 230, w: 760, h: 475 }, PERSON_MARKS.slice(0, 2), { x: 0, y: 0, w: 128, h: 80 });
    this.card.style.transformOrigin = "0 0";
    s.append(this.card);
    this.m = new Motion((m) => this.draw(m.get("p"))).add("p", 0, 0.0005);
    return s;
  }
  // p is 0 in the slot and 1 in the editor. The path bows to one side, as FlightCurve's does.
  rect(p) {
    const a = this.slot, b = this.editor;
    const bow = Math.sin(Math.PI * clamp(p, 0, 1)) * 26;
    return { x: lerp(a.x, b.x, p) + bow * 0.5, y: lerp(a.y, b.y, p) + bow, w: lerp(a.w, b.w, p), h: lerp(a.h, b.h, p) };
  }
  path(from, to, off = 0) {
    return Array.from({ length: 28 }, (_, i) => {
      const r = this.rect(lerp(from, to, i / 27));
      return `${(r.x + r.w / 2 + off * 0.55).toFixed(1)},${(r.y + r.h / 2 + off).toFixed(1)}`;
    }).join(" ");
  }
  draw(p) {
    const r = this.rect(p);
    this.card.style.transform = `translate(${r.x}px, ${r.y}px) scale(${r.w / this.slot.w})`;
    this.card.style.boxShadow = `0 ${4 + 14 * p}px ${8 + 26 * p}px -${4 * p}px rgb(0 0 0 / ${0.35 + 0.2 * p})`;
    if (!this.flying) return;
    if (!this.turned) this.far = Math.max(this.far, p);
    this.lines(this.turned ? this.far : p, this.turned ? p : null);
  }
  lines(far, back) {
    this.out.setAttribute("points", this.path(0, far));
    this.back.setAttribute("points", back == null ? "" : this.path(far, back, 16));
    this.back.setAttribute("marker-end", back == null ? "" : "url(#flight-head)");
    const r = this.rect(far);
    this.turn.setAttribute("cx", r.x + r.w / 2);
    this.turn.setAttribute("cy", r.y + r.h / 2);
    this.turn.style.opacity = back == null ? 0 : 1;
  }
  reset() {
    this.flying = false; this.far = 0;
    this.out.setAttribute("points", ""); this.back.setAttribute("points", ""); this.turn.style.opacity = 0;
    this.trail.style.opacity = 1;
    this.m.jump("p", 0);
  }
  final() { this.reset(); this.lines(0.85, 0.12); }
  async play() {
    this.reset();
    this.flying = true; this.turned = false;
    this.m.to("p", 1, UI.expand, UI.flightBounce);
    await wait(0.26);
    this.turned = true;
    await this.m.to("p", 0, UI.expand, UI.flightBounce);
    this.flying = false;
    this.lines(this.far, 0.12);
  }
  async rewind() { this.trail.style.opacity = 0; await wait(0.25); }
}
