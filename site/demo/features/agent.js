import { el, place, Motion, UI, wait } from "../vignette.js";
import { IMAGES, CLAUDE_MARKS } from "../cards.js";
import { GUTTER, card, whole, smallFit } from "./parts.js";

const CW = 140, CH = 88, RIGHT = 24;
const TERM_MAX = 460;
const RUNNING = '<span class="t-run">●</span> Running <b>1</b> shell command…';
const RAN = '<span class="t-done">  Ran <b>1</b> shell command</span>';

export class Agent {
  // Claude Code offers three versions and asks which you prefer, then runs `open` on a
  // vignette:// URL, and the card it pushed slides in at the screen's edge as a lone thumbnail.
  // The tool call is drawn as Claude Code draws a shell command: while it runs, a blinking dot over
  // the command; once it has run, one dim line, "Ran 1 shell command", with no dot and no command.
  static fit = smallFit(258);
  build({ W, H }) {
    const s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    const out = (l) => `<span class="t-out">${l}</span>`;
    const command = [out('  ⎿  $ open "vignette://add?file='), out('       /tmp/variants.png&amp;agent=claude"')];
    const said = ['<span class="t-said">●</span> Here are three versions.', "  Which do you prefer?", " "];
    const ran = [RUNNING, ...command];
    const line = (l, cls) => `<div class="ln${cls}">${l}</div>`;
    const t = el("div", "term-x", `<pre>${said.map((l) => line(l, "")).join("")}${ran.map((l) => line(l, " ran")).join("")}</pre>`);
    place(t, { x: GUTTER, y: 0, w: Math.min(W - GUTTER + 40, TERM_MAX), h: H + 40 });
    this.ran = [...t.querySelectorAll(".ran")];
    [this.label, ...this.command] = this.ran;
    s.append(t);
    this.card = card(IMAGES.variants, whole(IMAGES.variants), CLAUDE_MARKS, { x: W - RIGHT - CW, y: 150, w: CW, h: CH }, "Claude");
    s.append(this.card);
    const away = CW + RIGHT + 24;
    this.m = new Motion((m) => { this.card.style.transform = `translateX(${m.get("x") * away}px)`; }).add("x", 1, 0.001);
    return s;
  }
  reset() {
    this.label.innerHTML = RUNNING;
    this.ran.forEach((l) => l.classList.add("hid"));
    this.m.jump("x", 1);
  }
  finish() {
    this.label.innerHTML = RAN;
    this.command.forEach((l) => l.classList.add("hid"));
  }
  final() { this.reset(); this.label.classList.remove("hid"); this.finish(); this.m.jump("x", 0); }
  async play() {
    this.reset();
    await wait(0.35);
    this.ran.forEach((l) => l.classList.remove("hid"));
    await wait(0.5);
    const landed = this.m.to("x", 0, UI.slideIn, UI.flightBounce);
    await wait(UI.slideIn);
    this.finish();
    await landed;
  }
  async rewind() {
    this.m.to("x", 1, UI.slideOut);
    this.ran.forEach((l) => l.classList.add("hid"));
    await wait(0.3);
  }
}
