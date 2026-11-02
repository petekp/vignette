import { el, UI, wait } from "../vignette.js";
import { IMAGES } from "../cards.js";
import { GUTTER, card, whole, smallFit } from "./parts.js";

export class Queue {
  // Cards picked in turn take their numbers, then Return opens the first.
  static fit = smallFit(236);
  build({ W, H }) {
    const s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    const list = [[IMAGES.stays, whole(IMAGES.stays)], [IMAGES.packing, whole(IMAGES.packing)], [IMAGES.chat, { x: 0, y: 200, w: 1040, h: 650 }]];
    const cw = 140, ch = 88;
    this.cards = list.map(([image, view], i) => {
      const c = card(image, view, [], { x: W - GUTTER - cw - 10, y: 4 + i * (ch + UI.cardSpacing), w: cw, h: ch });
      c.append(el("div", "scircle"));
      s.append(c);
      return c;
    });
    this.key = el("div", "kcap", "↩");
    this.key.style.left = `${GUTTER}px`; this.key.style.top = `${4 + ch + UI.cardSpacing / 2 - 23}px`;
    s.append(this.key);
    return s;
  }
  pick(i, on) {
    const c = this.cards[i], circle = c.querySelector(".scircle");
    c.classList.toggle("picked", on);
    circle.classList.toggle("on", on);
    if (on) circle.textContent = String(i + 1);
  }
  reset() { this.cards.forEach((_, i) => this.pick(i, false)); this.key.classList.remove("down"); }
  final() { this.cards.forEach((_, i) => this.pick(i, true)); }
  async play() {
    this.reset();
    for (let i = 0; i < this.cards.length; i++) { await wait(0.3); this.pick(i, true); }
    await wait(0.45);
    this.key.classList.add("down");
    await wait(0.16);
    this.key.classList.remove("down");
  }
  async rewind() { this.reset(); await wait(0.3); }
}
