// The picture of "Drag 'n drop": a card dragged out of the stack into Claude Code, in Ghostty on the
// same screen.
import { el, Motion, UI, wait } from "../vignette.js";
import { lerp, GUTTER, card, POINTER, claudeCode, said, you, gap, LINE } from "./parts.js";
import { Column, SHOTS, CW, CH, SCALE, BELOW_MENU_BAR, at, deskFit } from "./stack.js";

// Ghostty's title bar, in the screen's points (.chrome).
const TITLE_BAR = 40;

export class Drag extends Column {
  // The bottom-right of a screen, the stack open at its edge over Ghostty. The newest card, which
  // has a drawing, is dragged out of the stack into Claude Code, and the prompt takes it as an image.
  // The card stays in the stack. Claude Code keeps its prompt at the bottom of the terminal, with a
  // hint line under it, and the conversation scrolls up under the title bar.
  static fit = deskFit;
  build({ W, H }) {
    const s = this.scene(W, H);
    // Every line ends left of the column, at every width deskFit gives.
    const talk = [said("Mapped the stays."), gap, you("&gt; Number the days."), gap, said("Done."), gap, you("&gt; Remind the host"), you("  to confirm.")];
    const win = el("div", "window term ghostty", '<div class="chrome"><i></i><i></i><i></i><span>postcard</span></div>');
    this.screen("Ghostty", ["File", "Edit", "View", "Window", "Help"], win, { top: BELOW_MENU_BAR });
    this.showBackdrop(1);
    // The terminal is drawn at the picture's own size inside the window, which is in the screen's
    // points, so its text stays as large as Agent's.
    const top = TITLE_BAR * SCALE, w = this.R - CW + 20 - GUTTER, h = H - BELOW_MENU_BAR + 40 * SCALE;
    const t = claudeCode([...talk, gap, said("Which stay is it?")].join(""), { x: 0, y: top, w, h: h - top }, H - 10 - BELOW_MENU_BAR);
    t.style.zoom = 1 / SCALE;
    win.append(t);
    this.typed = t.querySelector(".typed");
    // The newest card grows under the pointer, as a hovered card does in the stack.
    this.newest = this.column(SHOTS.slice(1)).at(-1);
    this.newest.style.transition = "scale 0.2s cubic-bezier(0.2, 0.9, 0.3, 1.15)";
    // The drag image is the card at its own size, held where the pointer took it.
    const [image, view, marks] = SHOTS[3];
    this.ghost = card(image, view, marks, { x: 0, y: 0, w: CW, h: CH });
    this.ghost.classList.add("ghost");
    s.append(this.ghost);
    this.pointer = el("div", "pointer", POINTER);
    s.append(this.pointer);
    this.grab = { x: CW * 0.55, y: CH * 0.55 };
    this.from = { x: this.R - CW + this.grab.x, y: this.bottom - CH + this.grab.y };
    // The drop lands on the prompt's line: above the hint line, the box's lower border and padding.
    this.drop = { x: Math.min(GUTTER + 250, this.R - CW - 50), y: BELOW_MENU_BAR + t.end - LINE - 7 - LINE / 2 };
    this.m = new Motion((m) => {
      const t = m.get("t"), p = m.get("p");
      const x = t > 0 ? lerp(this.from.x, this.drop.x, t) : lerp(W + 10, this.from.x, p);
      const y = t > 0 ? lerp(this.from.y, this.drop.y, t) - Math.sin(Math.PI * t) * 30 : lerp(this.from.y + 50, this.from.y, p);
      at(this.pointer, x - 10, y - 7);
      at(this.ghost, x - this.grab.x, y - this.grab.y);
      // The newest card is hovered while the pointer is over it, as a tracking area hovers it.
      this.hover(x >= this.R - CW && x <= this.R && y >= this.bottom - CH && y <= this.bottom);
    }).add("t", 0, 0.001).add("p", 0, 0.001);
    return s;
  }
  hover(on) { if (on !== this.hovered) this.newest.style.scale = (this.hovered = on) ? String(UI.hoverScale) : ""; }
  dropped(on) { this.typed.textContent = on ? "[Image #1] " : ""; this.typed.style.width = ""; }
  reset() {
    this.ghost.style.opacity = 0; this.pointer.classList.remove("down"); this.dropped(false); this.hover(false);
    this.pointer.style.opacity = "";
    this.m.jump("p", 0); this.m.jump("t", 0);
  }
  // The pointer fades, and the dropped image's text closes up from its end with the caret after it,
  // as deleting it would take it.
  async rewind() {
    this.pointer.style.opacity = 0;
    this.typed.style.width = `${this.typed.scrollWidth}px`;
    void this.typed.offsetWidth;
    this.typed.style.width = "0px";
    await wait(0.3);
  }
  final() { this.reset(); this.m.jump("p", 1); this.m.jump("t", 1); this.dropped(true); }
  // The drag in mid-flight over the prompt. A narrow picture has no room for it beside the
  // question, so it shows the dropped image instead.
  poster() {
    if (this.W < 440) return this.final();
    this.reset(); this.m.jump("p", 1); this.m.jump("t", 0.65); this.ghost.style.opacity = 1; this.pointer.classList.add("down");
  }
  async play() {
    this.reset();
    await wait(0.25);
    await this.m.to("p", 1, 0.45);
    await wait(0.15);
    this.pointer.classList.add("down");
    await wait(0.12);
    this.ghost.style.opacity = 1;
    await this.m.to("t", 1, 0.7);
    this.pointer.classList.remove("down");
    this.ghost.style.opacity = 0;
    this.dropped(true);
  }
}
