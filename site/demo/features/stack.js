// The column of cards the tiles under the first stage share: Recent's stack sliding in, a stitch
// (stitch.js) and a card dragged out (drag.js), each on the bottom-right of a screen. Each column
// rests the app's margin from the picture's right edge, the newest at the bottom, as the stack does
// against the screen's.
import { el, place, UI } from "../vignette.js";
import { IMAGES, PERSON_MARKS } from "../cards.js";
import { GUTTER, card, whole, menubar, backdrop } from "./parts.js";

export const CW = 140, CH = 88, STEP = CH + UI.cardSpacing;
// The cards' scale against the app's: a 16:10 screenshot's card is 188 pt wide there.
export const SCALE = CW / UI.cardMaxWidth;
// StackLayout.inset: the column fades out over the panel's padding at its ends.
const FADE = 19 * SCALE;
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
  // `top` down the picture to off its bottom, its right edge at `right`, by default just under the
  // column, the stack's backdrop, and the menu bar over it all, naming `app`, which is frontmost.
  // The column fades out under the menu bar, which the stack's panel stays below.
  screen(app, menus, win, top, right = this.R - CW + 20) {
    const { W, H } = this, k = 1 / SCALE, wide = W >= 480;
    const d = el("div", "desk");
    Object.assign(d.style, { width: `${W * k}px`, height: `${H * k}px`, transform: `scale(${SCALE})` });
    const x = GUTTER * k, y = top * k;
    place(win, { x, y, w: right * k - x, h: H * k - y + 40 });
    this.backdrop = backdrop();
    d.append(el("div", "wallpaper"), win, this.backdrop,
      menubar(app, wide ? menus : menus.slice(0, 3), `${wide ? "Sun 1 Nov&nbsp;&nbsp;" : ""}9:41`));
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
