import { el, Motion, UI, wait, tween } from "../vignette.js";
import { IMAGES } from "../cards.js";
import { clamp, GUTTER, card, whole, smallFit, selectionStrip, editorBar } from "./parts.js";
import { Flyer, CW, CH, passesTarget } from "./flight.js";
import { handEase } from "./drawing.js";

// The column, oldest first. The newest two are picked, in order.
const LIST = [
  [IMAGES.packing, whole(IMAGES.packing), []],
  [IMAGES.stays, whole(IMAGES.stays), [{ type: "rect", who: "person", x: 40, y: 192, w: 588, h: 86 }]],
  [IMAGES.chat, { x: 0, y: 252, w: 1040, h: 650 }, []],
];
const PICKS = [1, 2], STEP = CH + UI.cardSpacing, COLUMN = LIST.length * STEP - UI.cardSpacing;
// The editor's top, low enough that a flight's bow stays inside the picture.
const FRAME_TOP = 48;

export class Queue {
  // The newest two cards, picked in turn, take their numbers, and the selection strip comes up
  // beside them. Return, Draw in the strip, opens the first in the editor: the strip stands aside
  // and the stack narrows. A box is drawn, and Return again, Copy in the bar, sends it home Copied while the
  // second flies out to take its place.
  // The editor is laid out for the width; the column rests on the picture's bottom edge, however
  // tall the row makes it, and the oldest card runs off the top under the column's fade.
  static fit = (slotW, slotH = 0) => {
    const f = smallFit(236)(slotW), H = Math.max(f.rest, Math.ceil(slotH / f.k));
    return { ...f, H, key: `${f.W} ${H}` };
  };
  build({ W, H }) {
    const s = this.s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    this.R = W - 24; this.bottom = H - 14;
    const fade = el("div", "scol");
    fade.style.setProperty("--fade", `${Math.round(19 * CW / UI.cardMaxWidth)}px`);
    this.col = el("div", "qcol");
    Object.assign(this.col.style, { left: `${this.R - CW}px`, top: `${this.bottom - COLUMN}px`, width: `${CW}px`, height: `${COLUMN}px` });
    this.cards = LIST.map(([image, view], i) => {
      const c = card(image, view, [], { x: 0, y: i * STEP, w: CW, h: CH });
      c.append(el("div", "scircle"));
      this.col.append(c);
      return c;
    });
    fade.append(this.col);
    s.append(fade);
    this.m = new Motion((m) => { this.col.style.transform = `scale(${m.get("s")})`; }).add("s", 1, 0.0005);
    const fw = Math.round((this.R - GUTTER - UI.stackGap) * 0.72);
    this.frame = { x: GUTTER, y: FRAME_TOP, w: fw, h: fw * 0.625 };
    // StackLayout.widthScale: the widest the stack can be drawn and still clear the editor by the gap.
    this.narrow = clamp((this.R - (this.frame.x + this.frame.w + UI.stackGap)) / CW, UI.stackMinScale, 1);
    // The first two cards as they fly; each takes the editor's frame while it is open. The bar is
    // after them, as the toolbar's panel sits above the flight layer.
    const layer = el("div", "flights");
    s.append(layer);
    this.flyers = PICKS.map((i) => {
      const [image, view] = LIST[i], c = card(image, view, [], { x: 0, y: 0, w: this.frame.w, h: this.frame.h });
      c.classList.add("flying");
      layer.append(c);
      return new Flyer(c, this.frame);
    });
    this.bar = editorBar(this.frame);
    s.append(this.bar);
    this.copy = this.bar.querySelector(".copy");
    this.strip = selectionStrip();
    // Its right edge a strip gap left of the cards, as StackLayout.stripPlacement puts it.
    Object.assign(this.strip.style, { top: `${this.bottom - STEP - CH / 2 - 64}px`, right: `${W - (this.R - CW) + 12}px` });
    s.append(this.strip);
    this.drawRow = this.strip.querySelector('[data-row="draw"]');
    return s;
  }
  // The slot of the `n`th pick, in a column `k` of its width, narrowed about its bottom right.
  slot(n, k) {
    const i = PICKS[n];
    return { x: this.R - CW * k, y: this.bottom - (COLUMN - i * STEP) * k, w: CW * k, h: CH * k };
  }
  pick(n, on) {
    const c = this.cards[PICKS[n]], circle = c.querySelector(".scircle");
    c.classList.toggle("picked", on);
    circle.classList.toggle("on", on);
    if (on) circle.textContent = String(n + 1);
  }
  // The `n`th pick leaves its slot for the flight layer, or takes it back from the flight that landed there.
  lift(n, r, look) {
    this.cards[PICKS[n]].style.visibility = "hidden";
    this.flyers[n].c.style.visibility = "visible";
    this.flyers[n].at(r, look);
  }
  land(n) {
    this.cards[PICKS[n]].style.visibility = "visible";
    this.flyers[n].c.style.visibility = "hidden";
  }
  get first() { return this.cards[PICKS[0]]; }
  notice(on) {
    const old = this.first.querySelector(".notice");
    if (!on) { old?.remove(); return; }
    if (old) return;
    const n = el("div", "notice", '<span class="check"></span><b>Copied</b>');
    this.first.append(n);
    requestAnimationFrame(() => n.classList.add("in"));
  }
  // A press on a strip row or the bar's Copy: the key's own action, lit while its key is down.
  async press(button) {
    button.classList.add("down", "lit");
    await wait(0.16);
    button.classList.remove("down", "lit");
  }
  reset() {
    PICKS.forEach((_, n) => this.pick(n, false));
    this.cards.forEach((c) => { c.style.visibility = "visible"; c.pic.update([]); });
    this.first.querySelector("svg.marks").style.opacity = "";
    this.flyers.forEach((f) => { f.c.style.visibility = "hidden"; f.c.pic.update([]); });
    this.bar.classList.remove("up");
    this.strip.classList.remove("up");
    for (const b of [this.copy, this.drawRow]) b.classList.remove("down", "lit");
    this.notice(false);
    this.m.jump("s", 1);
  }
  // The first pick home and Copied, the second in the editor.
  final() {
    this.reset();
    PICKS.forEach((_, n) => this.pick(n, true));
    this.m.jump("s", this.narrow);
    this.first.pic.update(LIST[PICKS[0]][2]);
    this.notice(true);
    this.lift(1, this.frame, 1);
    this.bar.classList.add("up");
  }
  async play() {
    this.reset();
    for (let n = 0; n < PICKS.length; n++) {
      await wait(n ? 0.25 : 0.15);
      this.pick(n, true);
      if (n === 0) this.strip.classList.add("up");
    }
    await wait(0.25);
    await this.press(this.drawRow);
    this.strip.classList.remove("up");
    await wait(0.1);
    const [one, two] = this.flyers;
    this.lift(0, this.slot(0, 1), 0);
    this.m.to("s", this.narrow, UI.relayout, UI.flightBounce);
    const out = one.fly(this.frame, 1);
    await wait(passesTarget());
    this.bar.classList.add("up");
    await out;
    await wait(0.1);
    const marks = LIST[PICKS[0]][2], box = marks[0];
    await tween(0.35, (p) => { const t = handEase(p); one.c.pic.update([{ ...box, w: box.w * t, h: box.h * t }]); });
    one.c.pic.update(marks);
    await wait(0.25);
    await this.press(this.copy);
    // Copy sends the first home marked copied and opens the second in the same moment: two flights.
    this.first.pic.update(marks);
    const home = one.fly(this.slot(0, this.narrow), 0).then(() => { this.land(0); this.notice(true); });
    this.lift(1, this.slot(1, this.narrow), 0);
    await Promise.all([home, two.fly(this.frame, 1)]);
  }
  // The second goes home as the editor closes and the stack widens; the picks, the drawing and the
  // notice go.
  async rewind() {
    this.first.querySelector(".notice")?.classList.remove("in");
    PICKS.forEach((_, n) => this.pick(n, false));
    this.first.querySelector("svg.marks").style.opacity = 0;
    this.bar.classList.remove("up");
    this.m.to("s", 1, UI.relayout, UI.flightBounce);
    await this.flyers[1].fly(this.slot(1, 1), 0);
    this.land(1);
    await wait(0.15);
  }
}
