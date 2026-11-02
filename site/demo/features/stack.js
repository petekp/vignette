// The column of cards the tiles under the first stage share: Recent's stack sliding in, a stitch
// (stitch.js) and a card dragged out (drag.js), each on the bottom-right of a screen. Each column
// rests the app's margin from the picture's right edge, the newest at the bottom, as the stack does
// against the screen's.
import { el, place, UI } from "../vignette.js";
import { IMAGES, PERSON_MARKS } from "../cards.js";
import { GUTTER, clamp, card, whole, menubar, backdrop } from "./parts.js";

export const CW = 140, CH = 88, STEP = CH + UI.cardSpacing;
// The cards' scale against the app's: a 16:10 screenshot's card is 188 pt wide there.
export const SCALE = CW / UI.cardMaxWidth;
// StackLayout.inset: the column fades out over the panel's padding at its ends.
export const FADE = 19 * SCALE;
// .menubar's height, in the screen's points, and where what sits on the wallpaper under it starts.
export const MENU_BAR = 25, BELOW_MENU_BAR = MENU_BAR * SCALE + 14;
// Oldest first. The stays card answers Drag's question: the stay still waiting for its host.
export const SHOTS = [
  [IMAGES.chat, { x: 0, y: 200, w: 1040, h: 650 }, []],
  [IMAGES.itin, whole(IMAGES.itin), PERSON_MARKS.slice(0, 2)],
  [IMAGES.packing, whole(IMAGES.packing), []],
  [IMAGES.stays, whole(IMAGES.stays), [
    { type: "rect", who: "person", x: 40, y: 752, w: 1728, h: 206 },
    { type: "note", who: "person", x: 40, y: 972, text: "this one" },
  ]],
];
// The four tiles show one picture height whatever their copy, so a row's pictures line up and a
// column of them reads as one set. Each draws the same part of the screen, DESK_H points tall, at
// the same scale, so the menu bar and the cards are one size across the set: from 375 pt wide, up to
// 1.15 times the feature tiles' scale, the most the small tiles draw at, so the cards read at the
// tile's size. DESK_H holds Stitch's three picked cards under the menu bar.
export const DESK_H = 332;
export const deskFit = (slotW) => {
  const k = clamp(slotW / 375, 0.86, 1.15);
  return { W: Math.round(slotW / k), H: DESK_H, rest: DESK_H, k, key: String(Math.round(slotW / k)) };
};
export const at = (node, x, y, s = 1) => { node.style.transform = `translate(${x}px, ${y}px) scale(${s})`; };

export class Column {
  scene(W, H) {
    const s = this.s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    this.W = W; this.H = H; this.R = W - UI.screenMargin * SCALE; this.bottom = H - 14;
    this.col = el("div", "scol");
    this.col.style.setProperty("--fade", `${FADE}px`);
    s.append(this.col);
    return s;
  }
  // The screen behind the column, in its own points scaled to the cards: the wallpaper, `win` from
  // `top` down the picture to off its bottom, from `left` to `right`, by default just under the
  // column, the stack's backdrop, and the menu bar over it all, naming `app`, which is frontmost.
  // The column fades out under the menu bar, which the stack's panel stays below. A picture of
  // the screen short of its right edge (`clock: false`) has no clock, which sits at that edge.
  screen(app, menus, win, { top, left = GUTTER, right = this.R - CW + 20, clock = true }) {
    const { W, H } = this, k = 1 / SCALE, wide = W >= 440;
    const d = el("div", "desk");
    Object.assign(d.style, { width: `${W * k}px`, height: `${H * k}px`, transform: `scale(${SCALE})` });
    const x = left * k, y = top * k;
    place(win, { x, y, w: right * k - x, h: H * k - y + 40 });
    this.backdrop = backdrop();
    this.desk = d;
    d.append(el("div", "wallpaper"), win, this.backdrop,
      menubar(app, wide ? menus : menus.slice(0, 3), clock ? `${wide ? "Sun 1 Nov&nbsp;&nbsp;" : ""}9:41` : ""));
    this.s.insertBefore(d, this.col);
    this.col.style.setProperty("--top", `${MENU_BAR * SCALE}px`);
  }
  // The backdrop shown by `b`, from 0 to 1: it fades in as it slides in from the screen's edge.
  showBackdrop(b) {
    this.backdrop.style.setProperty("--shown", b);
    this.backdrop.style.transform = `translateX(${(1 - b) * UI.backdropWidth}px)`;
  }
  // The cards for `list` in the column, the last at the bottom.
  column(list, bottom = this.bottom) {
    return list.map(([image, view, marks], i) => {
      const c = card(image, view, marks, { x: this.R - CW, y: bottom - CH - (list.length - 1 - i) * STEP, w: CW, h: CH });
      this.col.append(c);
      return c;
    });
  }
}
