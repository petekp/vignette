import { el, Motion, UI, wait } from "../vignette.js";
import { IMAGES } from "../cards.js";
import { clamp, GUTTER, card, whole, smallFit, selectionStrip } from "./parts.js";
import { Flyer, CW, CH, passesTarget } from "./flight.js";

const LIST = [
  [IMAGES.stays, whole(IMAGES.stays), [{ type: "rect", who: "person", x: 40, y: 192, w: 588, h: 86 }]],
  [IMAGES.packing, whole(IMAGES.packing), []],
  [IMAGES.chat, { x: 0, y: 200, w: 1040, h: 650 }, []],
];
const TOOLS = [
  '<path d="M5 3l12 8-5.5 1.2L9 18z" fill="currentColor"/>',
  '<rect x="3.5" y="5.5" width="15" height="11" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.8"/>',
  '<path d="M5 17L17 5M9 5h8v8" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
  '<text x="11" y="16" text-anchor="middle" font-size="13" font-weight="600" fill="currentColor" font-family="system-ui">Aa</text>',
];
// The stack's top, and the editor's, which sits lower so a flight's bow stays inside the picture.
const TOP = 4, FRAME_TOP = 48;

export class Queue {
  // Three cards picked in turn take their numbers, and the selection strip comes up beside them.
  // Return, Draw in the strip, opens the first in the editor: the strip stands aside and the stack
  // narrows. A box is drawn, and Return again, Copy in the bar, sends it home Copied while the
  // second flies out to take its place.
  static fit = smallFit(236);
  build({ W, H }) {
    const s = this.s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    this.R = W - 24;
    this.col = el("div", "qcol");
    Object.assign(this.col.style, { left: `${this.R - CW}px`, top: `${TOP}px`, width: `${CW}px` });
    this.cards = LIST.map(([image, view], i) => {
      const c = card(image, view, [], { x: 0, y: i * (CH + UI.cardSpacing), w: CW, h: CH });
      c.append(el("div", "scircle"));
      this.col.append(c);
      return c;
    });
    s.append(this.col);
    this.m = new Motion((m) => { this.col.style.transform = `scale(${m.get("s")})`; }).add("s", 1, 0.0005);
    const fw = Math.round((this.R - GUTTER - UI.stackGap) * 0.72);
    this.frame = { x: GUTTER, y: FRAME_TOP, w: fw, h: fw * 0.625 };
    // StackLayout.widthScale: the widest the stack can be drawn and still clear the editor by the gap.
    this.narrow = clamp((this.R - (this.frame.x + this.frame.w + UI.stackGap)) / CW, UI.stackMinScale, 1);
    // The first two cards as they fly; each takes the editor's frame while it is open. The bar is
    // after them, as the toolbar's panel sits above the flight layer.
    const layer = el("div", "flights");
    s.append(layer);
    this.flyers = LIST.slice(0, 2).map(([image, view]) => {
      const c = card(image, view, [], { x: 0, y: 0, w: this.frame.w, h: this.frame.h });
      c.classList.add("flying");
      layer.append(c);
      return new Flyer(c, this.frame);
    });
    this.bar = el("div", "qbar", `<div class="bar">${TOOLS.map((t, i) => `<span class="tool${i === 1 ? " on" : ""}"><svg viewBox="0 0 22 22" width="22" height="22">${t}</svg></span>`).join("")}<span class="divider"></span><span class="copy">Copy <kbd>↩</kbd></span></div>`);
    Object.assign(this.bar.style, { left: `${this.frame.x + this.frame.w / 2}px`, top: `${this.frame.y + this.frame.h + UI.toolbarGap}px` });
    s.append(this.bar);
    this.copy = this.bar.querySelector(".copy");
    this.strip = selectionStrip();
    // Its right edge a strip gap left of the cards, as StackLayout.stripPlacement puts it.
    Object.assign(this.strip.style, { top: `${TOP + 32}px`, right: `${W - (this.R - CW) + 12}px` });
    s.append(this.strip);
    this.drawRow = this.strip.querySelector('[data-row="draw"]');
    return s;
  }
  slot(i, k) { return { x: this.R - CW * k, y: TOP + i * (CH + UI.cardSpacing) * k, w: CW * k, h: CH * k }; }
  pick(i, on) {
    const c = this.cards[i], circle = c.querySelector(".scircle");
    c.classList.toggle("picked", on);
    circle.classList.toggle("on", on);
    if (on) circle.textContent = String(i + 1);
  }
  // Card `i` leaves its slot for the flight layer, or takes it back from the flight that landed there.
  lift(i, r, look) {
    this.cards[i].style.visibility = "hidden";
    this.flyers[i].c.style.visibility = "visible";
    this.flyers[i].at(r, look);
  }
  land(i) {
    this.cards[i].style.visibility = "visible";
    this.flyers[i].c.style.visibility = "hidden";
  }
  notice(on) {
    const old = this.cards[0].querySelector(".notice");
    if (!on) { old?.remove(); return; }
    if (old) return;
    const n = el("div", "notice", '<span class="check"></span><b>Copied</b>');
    this.cards[0].append(n);
    requestAnimationFrame(() => n.classList.add("in"));
  }
  // A press on a strip row or the bar's Copy: the key's own action, lit while its key is down.
  async press(button) {
    button.classList.add("down", "lit");
    await wait(0.16);
    button.classList.remove("down", "lit");
  }
  reset() {
    this.cards.forEach((c, i) => { this.pick(i, false); c.style.visibility = "visible"; c.pic.update([]); });
    this.cards[0].querySelector("svg.marks").style.opacity = "";
    this.flyers.forEach((f) => { f.c.style.visibility = "hidden"; f.c.pic.update([]); });
    this.bar.classList.remove("up");
    this.strip.classList.remove("up");
    for (const b of [this.copy, this.drawRow]) b.classList.remove("down", "lit");
    this.notice(false);
    this.m.jump("s", 1);
  }
  // Card 1 home and Copied, card 2 in the editor, card 3 still waiting its turn.
  final() {
    this.reset();
    this.cards.forEach((_, i) => this.pick(i, true));
    this.m.jump("s", this.narrow);
    this.cards[0].pic.update(LIST[0][2]);
    this.notice(true);
    this.lift(1, this.frame, 1);
    this.bar.classList.add("up");
  }
  async play() {
    this.reset();
    for (let i = 0; i < this.cards.length; i++) {
      await wait(0.3);
      this.pick(i, true);
      if (i === 0) this.strip.classList.add("up");
    }
    await wait(0.45);
    await this.press(this.drawRow);
    this.strip.classList.remove("up");
    await wait(0.14);
    const [one, two] = this.flyers;
    this.lift(0, this.slot(0, 1), 0);
    this.m.to("s", this.narrow, UI.relayout, UI.flightBounce);
    const out = one.fly(this.frame, 1);
    await wait(passesTarget());
    this.bar.classList.add("up");
    await out;
    await wait(0.2);
    const box = LIST[0][2][0], r = { ...box, w: 0, h: 0 };
    await new Motion((m) => { const t = m.get("t"); r.w = box.w * t; r.h = box.h * t; one.c.pic.update([r]); }).add("t", 0, 0.001).to("t", 1, 0.35);
    one.c.pic.update(LIST[0][2]);
    await wait(0.4);
    await this.press(this.copy);
    // Copy sends card 1 home marked copied and opens card 2 in the same moment: two flights.
    this.cards[0].pic.update(LIST[0][2]);
    const home = one.fly(this.slot(0, this.narrow), 0).then(() => { this.land(0); this.notice(true); });
    this.lift(1, this.slot(1, this.narrow), 0);
    await Promise.all([home, two.fly(this.frame, 1)]);
  }
  // Card 2 goes home as the editor closes and the stack widens; the picks, the drawing and the
  // notice go.
  async rewind() {
    this.cards[0].querySelector(".notice")?.classList.remove("in");
    this.cards.forEach((_, i) => this.pick(i, false));
    this.cards[0].querySelector("svg.marks").style.opacity = 0;
    this.bar.classList.remove("up");
    this.m.to("s", 1, UI.relayout, UI.flightBounce);
    await this.flyers[1].fly(this.slot(1, 1), 0);
    this.land(1);
    await wait(0.15);
  }
}
