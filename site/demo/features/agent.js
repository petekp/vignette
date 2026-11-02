import { el, place, Motion, UI, wait } from "../vignette.js";
import { IMAGES, CLAUDE_MARKS } from "../cards.js";
import { GUTTER, card, whole, smallFit } from "./parts.js";

const CW = 140, CH = 88, RIGHT = 24;

export class Agent {
  // Claude Code offers three versions and asks which you prefer, then runs `open` on a
  // vignette:// URL, and the card it pushed slides in at the screen's edge as a lone thumbnail.
  // The tool call is drawn as Claude Code draws a shell command while it runs: a completed one
  // folds into "Ran 1 shell command" and no longer shows the command.
  static fit = smallFit(258);
  build({ W, H }) {
    const s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    const out = (l) => `<span class="t-out">${l}</span>`;
    const command = W < 560
      ? [out('  ⎿  $ open "vignette://add?file='), out('       /tmp/variants.png&amp;agent=claude"')]
      : [out('  ⎿  $ open "vignette://add?file=/tmp/variants.png&amp;agent=claude"')];
    const said = ['<span class="t-said">●</span> Here are three versions.', "  Which do you prefer?", " "];
    const ran = ['<span class="t-run">●</span> Running <b>1</b> shell command…', ...command];
    const line = (l, cls) => `<div class="ln${cls}">${l}</div>`;
    const t = el("div", "term-x", `<pre>${said.map((l) => line(l, "")).join("")}${ran.map((l) => line(l, " ran")).join("")}</pre>`);
    place(t, { x: GUTTER, y: 0, w: W - GUTTER + 40, h: H + 40 });
    this.ran = [...t.querySelectorAll(".ran")];
    s.append(t);
    this.card = card(IMAGES.variants, whole(IMAGES.variants), CLAUDE_MARKS, { x: W - RIGHT - CW, y: 150, w: CW, h: CH }, "Claude");
    s.append(this.card);
    const away = CW + RIGHT + 24;
    this.m = new Motion((m) => { this.card.style.transform = `translateX(${m.get("x") * away}px)`; }).add("x", 1, 0.001);
    return s;
  }
  reset() { this.ran.forEach((l) => l.classList.add("hid")); this.m.jump("x", 1); }
  final() { this.ran.forEach((l) => l.classList.remove("hid")); this.m.jump("x", 0); }
  async play() {
    this.reset();
    await wait(0.35);
    this.ran.forEach((l) => l.classList.remove("hid"));
    await wait(0.5);
    await this.m.to("x", 0, UI.slideIn, UI.flightBounce);
  }
  async rewind() {
    this.m.to("x", 1, UI.slideOut);
    this.ran.forEach((l) => l.classList.add("hid"));
    await wait(0.3);
  }
}
