import { el, Motion, UI, wait } from "../vignette.js";
import { IMAGES } from "../cards.js";
import { lerp, clamp, GUTTER, card, whole, smallFit } from "./parts.js";

const CW = 140, CH = 88;
// How wide the stack is drawn while the editor is open (StackLayout.widthScale).
const NARROW = 0.8;
const LIST = [
  [IMAGES.stays, whole(IMAGES.stays), [{ type: "rect", who: "person", x: 40, y: 192, w: 588, h: 86 }]],
  [IMAGES.packing, whole(IMAGES.packing), []],
  [IMAGES.chat, { x: 0, y: 200, w: 1040, h: 650 }, []],
];
// The selection strip's rows, as Config.stripRows shows them for three screenshots.
const ICONS = {
  copy: '<rect x="6" y="6" width="9" height="11" rx="2" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M4 13V5a2 2 0 0 1 2-2h6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',
  draw: '<path d="M4 16l1-4 8-8 3 3-8 8z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><path d="M11 17h6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',
  stitch: '<rect x="4" y="8" width="12" height="9" rx="2" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M6 5.5h8M8 3h4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',
  trash: '<path d="M4.5 6h11M8 6V4h4v2M6 6l.8 10.5h6.4L14 6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>',
};
const ROWS = [["copy", "Copy", "⌘C"], ["draw", "Draw", "↩"], ["stitch", "Stitch", "⌘S"], ["trash", "Delete", "⌘⌫"]];
const TOOLS = [
  '<path d="M5 3l12 8-5.5 1.2L9 18z" fill="currentColor"/>',
  '<rect x="3.5" y="5.5" width="15" height="11" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.8"/>',
  '<path d="M5 17L17 5M9 5h8v8" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
  '<text x="11" y="16" text-anchor="middle" font-size="13" font-weight="600" fill="currentColor" font-family="system-ui">Aa</text>',
];

export class Queue {
  // Three cards picked in turn take their numbers, and the selection strip comes up beside them.
  // Return, Draw in the strip, opens the first in the editor: the strip stands aside and the stack
  // narrows. A box is drawn, and Return again, Copy in the bar, sends it home Copied while the
  // second flies out to take its place.
  static fit = smallFit(236);
  build({ W, H }) {
    const s = this.s = el("div", "scene fades");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    this.R = W - GUTTER - 10;
    this.col = el("div", "qcol");
    Object.assign(this.col.style, { left: `${this.R - CW}px`, top: "4px", width: `${CW}px` });
    this.cards = LIST.map(([image, view], i) => {
      const c = card(image, view, [], { x: 0, y: i * (CH + UI.cardSpacing), w: CW, h: CH });
      c.append(el("div", "scircle"));
      this.col.append(c);
      return c;
    });
    s.append(this.col);
    this.m = new Motion((m) => { this.col.style.transform = `scale(${m.get("s")})`; }).add("s", 1, 0.0005);
    const fw = this.R - CW * NARROW - 16 - GUTTER;
    this.frame = { x: GUTTER, y: 4, w: fw, h: fw * 0.625 };
    this.bar = el("div", "qbar", `<div class="bar">${TOOLS.map((t, i) => `<span class="tool${i === 1 ? " on" : ""}"><svg viewBox="0 0 22 22" width="22" height="22">${t}</svg></span>`).join("")}<span class="divider"></span><span class="copy">Copy <kbd>↩</kbd></span></div>`);
    Object.assign(this.bar.style, { left: `${this.frame.x + this.frame.w / 2}px`, top: `${this.frame.y + this.frame.h + UI.toolbarGap}px` });
    s.append(this.bar);
    this.copy = this.bar.querySelector(".copy");
    // The first two cards as they fly; each takes the editor's frame while it is open.
    this.flyers = LIST.slice(0, 2).map(([image, view]) => {
      const c = card(image, view, [], { x: 0, y: 0, w: this.frame.w, h: this.frame.h });
      c.classList.add("flying");
      s.append(c);
      return c;
    });
    this.strip = el("div", "qstrip", ROWS.map(([icon, label, key]) =>
      `<div class="row" data-row="${icon}"><svg viewBox="0 0 20 20" width="15" height="15">${ICONS[icon]}</svg><span>${label}</span><kbd>${key}</kbd></div>`).join(""));
    // Its right edge a strip gap left of the cards, as StackLayout.stripPlacement puts it.
    Object.assign(this.strip.style, { top: "36px", right: `${W - (this.R - CW) + 12}px` });
    s.append(this.strip);
    this.drawRow = this.strip.querySelector('[data-row="draw"]');
    return s;
  }
  slot(i, k) { return { x: this.R - CW * k, y: 4 + i * (CH + UI.cardSpacing) * k, w: CW * k, h: CH * k }; }
  pick(i, on) {
    const c = this.cards[i], circle = c.querySelector(".scircle");
    c.classList.toggle("picked", on);
    circle.classList.toggle("on", on);
    if (on) circle.textContent = String(i + 1);
  }
  // p is 0 at `a` and 1 at `b`; the path bows to one side, as FlightCurve's does.
  place(c, a, b, p) {
    const bow = Math.sin(Math.PI * clamp(p, 0, 1)) * 22;
    const r = { x: lerp(a.x, b.x, p) + bow * 0.5, y: lerp(a.y, b.y, p) + bow, w: lerp(a.w, b.w, p), h: lerp(a.h, b.h, p) };
    const k = r.w / this.frame.w, lift = b === this.frame ? p : 1 - p;
    c.style.transform = `translate(${r.x}px, ${r.y}px) scale(${k})`;
    c.style.borderRadius = `${16 / k}px`;
    c.style.boxShadow = `0 ${(4 + 14 * lift) / k}px ${(8 + 26 * lift) / k}px rgb(0 0 0 / ${0.35 + 0.2 * lift})`;
  }
  fly(c, a, b) {
    c.style.visibility = "visible";
    return new Motion((m) => this.place(c, a, b, m.get("p"))).add("p", 0, 0.0005).to("p", 1, UI.expand, UI.flightBounce);
  }
  notice(on) {
    this.cards[0].querySelector(".notice")?.remove();
    if (!on) return;
    const n = el("div", "notice", '<span class="check"></span><b>Copied</b>');
    this.cards[0].append(n);
    requestAnimationFrame(() => n.classList.add("in"));
  }
  // A press on a strip row or the bar's Copy: the key's own action, lit as it runs.
  async press(button) {
    button.classList.add("down", "lit");
    await wait(0.16);
    button.classList.remove("down");
  }
  reset() {
    this.cards.forEach((c, i) => { this.pick(i, false); c.style.visibility = "visible"; c.pic.update([]); });
    this.flyers.forEach((c) => { c.style.visibility = "hidden"; c.pic.update([]); });
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
    this.m.jump("s", NARROW);
    this.cards[0].pic.update(LIST[0][2]);
    this.notice(true);
    this.cards[1].style.visibility = "hidden";
    this.flyers[1].style.visibility = "visible";
    this.place(this.flyers[1], this.frame, this.frame, 1);
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
    this.cards[0].style.visibility = "hidden";
    this.m.to("s", NARROW, UI.expand);
    await this.fly(one, this.slot(0, 1), this.frame);
    this.bar.classList.add("up");
    await wait(0.2);
    const box = LIST[0][2][0], r = { ...box, w: 0, h: 0 };
    await new Motion((m) => { const t = m.get("t"); r.w = box.w * t; r.h = box.h * t; one.pic.update([r]); }).add("t", 0, 0.001).to("t", 1, 0.35);
    one.pic.update(LIST[0][2]);
    await wait(0.4);
    await this.press(this.copy);
    await wait(0.06);
    this.cards[1].style.visibility = "hidden";
    const home = this.fly(one, this.frame, this.slot(0, NARROW)).then(() => {
      this.cards[0].pic.update(LIST[0][2]);
      this.cards[0].style.visibility = "visible";
      one.style.visibility = "hidden";
      this.notice(true);
    });
    await wait(0.05);
    await Promise.all([home, this.fly(two, this.slot(1, NARROW), this.frame)]);
  }
  async rewind() {
    this.s.style.opacity = 0;
    await wait(0.25);
    this.reset();
    this.s.style.opacity = 1;
  }
}
