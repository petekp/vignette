// The picture of "Your recent screenshots": the stack sliding in at a screen's edge.
import { el, place, Motion, UI, wait } from "../vignette.js";
import { IMAGES } from "../cards.js";
import { GUTTER, whole, wideFit, shiftKey, twice, tap, menubar, backdrop } from "./parts.js";
import { Column, SHOTS, CW, SCALE, at } from "./stack.js";

// Recent's screenshots, oldest first: the design frame in place of the chat, which is open in
// Messages behind the stack.
const RECENT = [[IMAGES.frame, whole(IMAGES.frame), []], ...SHOTS.slice(1)];
// .menubar's height, in the screen's points.
const MENU_BAR = 25;
// The keys sit on the wallpaper under the menu bar, and Messages' window starts under them.
const KEYS_Y = MENU_BAR * SCALE + 14, WINDOW_Y = KEYS_Y + 46 + 16;
// Messages, mid-conversation with Maya about the trip.
const MESSAGES = '<div class="mhead"><span class="lights"><i></i><i></i><i></i></span><b class="av">M</b><span class="who">Maya</span></div>'
  + '<div class="mbody"><div class="ts">Today 9:12 AM</div><div class="b">Can we fit in Val d’Orcia at sunrise?</div>'
  + '<div class="b me">Day 3. We leave Greve at 5:30</div><div class="b me">Pecorino in Pienza after</div>'
  + '<div class="b">Perfect. Can the itinerary number the days?</div><div class="b">I keep losing track</div></div>';

export class Recent extends Column {
  // The bottom-right of a screen, Messages open on it. Right Shift goes down twice, and the cards
  // slide in at the screen's edge over the backdrop's blur, the newest first.
  static fit = wideFit(236);
  build({ W, H }) {
    const s = this.scene(W, H);
    // The column rests the app's margin from the screen's edge.
    this.R = W - UI.screenMargin * SCALE;
    s.insertBefore(this.screen(W, H), this.col);
    // The column fades out under the menu bar, which the stack's panel stays below.
    this.col.style.setProperty("--top", `${MENU_BAR * SCALE}px`);
    this.cards = this.column(RECENT);
    const keys = el("div", "fkeys up");
    keys.style.setProperty("--scale", 1);
    this.key = shiftKey();
    place(this.key, { x: 0, y: 0 });
    this.twice = twice();
    place(this.twice, { x: 104, y: 12 });
    keys.append(this.key, this.twice);
    place(keys, { x: GUTTER, y: KEYS_Y });
    s.append(keys);
    this.off = W - (this.R - CW) + 24;
    this.m = this.cards.map((c) => new Motion((m) => at(c, m.get("x"), 0)).add("x", this.off, 0.05));
    this.b = new Motion((m) => {
      const b = m.get("b");
      this.backdrop.style.setProperty("--shown", b);
      this.backdrop.style.transform = `translateX(${(1 - b) * UI.backdropWidth}px)`;
    }).add("b", 0);
    return s;
  }
  // The screen in its own points, scaled to the cards: the wallpaper, Messages' window from under
  // the keys to off the bottom, its right edge just under the stack so the stack covers only the
  // ends of the bubbles there, the backdrop, and the menu bar over it all.
  screen(W, H) {
    const d = el("div", "desk"), k = 1 / SCALE;
    Object.assign(d.style, { width: `${W * k}px`, height: `${H * k}px`, transform: `scale(${SCALE})` });
    const win = el("div", "window msgs", MESSAGES);
    const x = GUTTER * k, y = WINDOW_Y * k;
    place(win, { x, y, w: (this.R - CW + 20) * k - x, h: H * k - y + 40 });
    this.backdrop = backdrop();
    const wide = W >= 480;
    d.append(el("div", "wallpaper"), win, this.backdrop,
      menubar("Messages", wide ? ["File", "Edit", "View", "Conversation", "Window"] : ["File", "Edit", "View"], `${wide ? "Sun 1 Nov&nbsp;&nbsp;" : ""}9:41`));
    return d;
  }
  reset() { this.twice.classList.remove("on"); this.m.forEach((m) => m.jump("x", this.off)); this.b.jump("b", 0); }
  final() { this.reset(); this.twice.classList.add("on"); this.m.forEach((m) => m.jump("x", 0)); this.b.jump("b", 1); }
  // The stack slides out, as a dismissal takes it.
  // Done once the cards are past the edge, not when the spring's tail settles.
  async rewind() {
    this.twice.classList.remove("on");
    this.m.forEach((m) => m.to("x", this.off, UI.slideOut));
    this.b.to("b", 0, UI.slideOut);
    await wait(UI.slideOut * 1.2);
  }
  async play() {
    this.reset();
    await tap(this.key); await wait(0.11); await tap(this.key);
    this.twice.classList.add("on");
    await wait(0.08);
    this.b.to("b", 1, UI.slideIn);
    const newestFirst = [...this.m].reverse();
    await Promise.all(newestFirst.map(async (m, i) => {
      await wait(Math.min(UI.stagger * i, UI.staggerMax));
      await m.to("x", 0, UI.slideIn, UI.flightBounce);
    }));
  }
}
