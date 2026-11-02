import { el, place, Motion, UI, wait } from "../vignette.js";
import { IMAGES, CLAUDE_MARKS } from "../cards.js";
import { GUTTER, card, whole, smallFit } from "./parts.js";

export class Agent {
  // Claude Code offers three versions and asks which you prefer. Its command appears, then the
  // card it sent arrives.
  static fit = smallFit(258);
  build({ W, H }) {
    const s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    const lines = [
      '<span class="t-claude">●</span> Here are three versions.',
      '  Which do you prefer?',
      '<span class="t-dim">⎿</span> open <span class="t-hi">"vignette://add</span>',
      '    <span class="t-hi">?file=/tmp/itin.png&amp;agent=claude"</span>',
    ];
    const t = el("div", "term-x", `<div class="bar-t"><i></i><i></i><i></i></div><pre>${lines.map((l) => `<div class="ln">${l}</div>`).join("")}</pre>`);
    place(t, { x: GUTTER, y: 0, w: W - GUTTER + 40, h: 300 });
    this.lines = [...t.querySelectorAll(".ln")];
    s.append(t);
    this.card = card(IMAGES.variants, whole(IMAGES.variants), CLAUDE_MARKS, { x: Math.min(W - GUTTER - 160, 380), y: 138, w: 160, h: 100 }, "Claude");
    this.card.style.boxShadow = "0 14px 30px -8px rgb(0 0 0 / 0.6)";
    s.append(this.card);
    this.m = new Motion((m) => { this.card.style.transform = `translateY(${m.get("y") * 130}px)`; }).add("y", 1, 0.001);
    return s;
  }
  reset() { this.lines.forEach((l) => l.classList.add("hid")); this.m.jump("y", 1); }
  final() { this.lines.forEach((l) => l.classList.remove("hid")); this.m.jump("y", 0); }
  async play() {
    this.reset();
    for (const l of this.lines) { await wait(0.32); l.classList.remove("hid"); }
    await wait(0.45);
    await this.m.to("y", 0, UI.slideIn, UI.flightBounce);
  }
  async rewind() {
    this.m.to("y", 1, UI.slideOut);
    this.lines.forEach((l) => l.classList.add("hid"));
    await wait(0.3);
  }
}
