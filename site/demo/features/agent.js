import { el, Motion, UI, wait } from "../vignette.js";
import { IMAGES, CLAUDE_MARKS } from "../cards.js";
import { GUTTER, card, whole, wideFit, claudeCode, line, said, you, gap } from "./parts.js";

const CW = 140, CH = 88, RIGHT = 24;
// The command the vignette skill has an agent run, wrapped to end left of the card at each width.
const COMMAND = {
  narrow: ['open -g "vignette://add?file=', "%2Ftmp%2Fvariants.png&amp;agent=claude", '&amp;marks=%2Ftmp%2Fmarks.json"'],
  wide: ['open -g "vignette://add?file=%2Ftmp%2Fvariants.png', '&amp;agent=claude&amp;marks=%2Ftmp%2Fmarks.json"'],
};
const TALK = {
  narrow: [said("The day numbers match the map's stops."), gap, you("&gt; Make the highlight card pop."), gap,
    said("Three versions, each a different"), line("  idea: a warm tint, a Highlight tag,"), line("  and a photo that fills the card."), gap],
  wide: [said("The day numbers match the map's stops on the itinerary."), gap, you("&gt; Make the highlight card pop."), gap,
    said("Three versions, each a different idea: a warm tint, a"), line("  Highlight tag, and a photo that fills the card."), gap],
};
// Level with the card once it has landed.
const ASK = { narrow: "Which one?", wide: "Which one do you prefer?" };
const out = (l) => `<span class="t-out">${l}</span>`;
// A shell command as Claude Code draws it with its tool calls shown in full (verbose, or ctrl+o):
// the call with its command under a dot that blinks while it runs and turns green once it has, and
// its result. `open` prints nothing, which Claude Code shows as "(No output)".
const call = (command, dot, result) => [
  ...command.map((l, i) => line(i ? `  ${l}${i === command.length - 1 ? ")" : ""}` : `<span class="${dot}">●</span> <b>Bash</b>(${l}`)),
  line(out(`  ⎿  ${result}`)),
].join("");
const running = (command) => call(command, "t-run", "Running…");
const ran = (command) => call(command, "t-ok", "(No output)");

export class Agent {
  // Claude Code offers three versions of a card, then runs `open` on a vignette:// URL, and the
  // card it pushed slides in at the screen's edge as a lone thumbnail. Claude Code then asks which
  // one you prefer. Its prompt box stays at the terminal's bottom, and each line it prints moves
  // the conversation up.
  static fit = wideFit(258);
  build({ W, H }) {
    const s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    // Every line ends left of the card, which lands over the terminal's right side.
    const size = W >= 520 ? "wide" : "narrow";
    this.command = COMMAND[size];
    // The terminal spans the picture from the gutter and runs off its right and bottom edges.
    const t = claudeCode(`${TALK[size].join("")}<div class="grp"></div><div class="grp">${gap}${said(ASK[size])}</div>`, { x: GUTTER, y: 0, w: W - GUTTER + 40, h: H + 40 }, H - 10);
    [this.ran, this.asked] = t.querySelectorAll(".grp");
    s.append(t);
    this.card = card(IMAGES.variants, whole(IMAGES.variants), CLAUDE_MARKS, { x: W - RIGHT - CW, y: 150, w: CW, h: CH }, "Claude");
    s.append(this.card);
    const away = CW + RIGHT + 24;
    this.m = new Motion((m) => { this.card.style.transform = `translateX(${m.get("x") * away}px)`; }).add("x", 1, 0.001);
    return s;
  }
  // A group of lines printed at once: a terminal shows it in one frame, and a rewind closes it up.
  show(g, html) {
    if (html !== undefined) g.innerHTML = html;
    g.style.transition = "none"; g.style.height = ""; g.style.opacity = "";
    void g.offsetHeight; g.style.transition = "";
  }
  hide(g, animate) {
    if (!animate) g.style.transition = "none";
    g.style.height = `${g.scrollHeight}px`;
    void g.offsetHeight;
    g.style.height = "0px"; g.style.opacity = 0;
    if (!animate) { void g.offsetHeight; g.style.transition = ""; }
  }
  reset() {
    this.hide(this.ran, false); this.hide(this.asked, false);
    this.m.jump("x", 1);
  }
  final() { this.reset(); this.show(this.ran, ran(this.command)); this.show(this.asked); this.m.jump("x", 0); }
  async play() {
    this.reset();
    await wait(0.35);
    this.show(this.ran, running(this.command));
    await wait(0.45);
    this.show(this.ran, ran(this.command));
    await wait(0.1);
    await this.m.to("x", 0, UI.slideIn, UI.flightBounce);
    await wait(0.25);
    this.show(this.asked);
  }
  async rewind() {
    this.m.to("x", 1, UI.slideOut);
    this.hide(this.ran, true); this.hide(this.asked, true);
    await wait(0.3);
  }
}
