// The picture of "Quicker drawing": the editor open on the same screen as Recent, Stitch and Drag,
// over Notes, with the stays page's screenshot in its frame.
import { el, place, wait, tween, UI } from "../vignette.js";
import { IMAGES } from "../cards.js";
import { MARK, POINT_SCALE } from "../marks.js";
import { lerp, GUTTER, shot } from "./parts.js";
import { Column, SHOTS, CW, SCALE, MENU_BAR, BELOW_MENU_BAR, STEP, deskFit } from "./stack.js";
import { handEase, CROSSHAIR } from "./drawing.js";

// Notes, which the editor's dim blurs: the folders, the trip's notes with one picked, and the note.
const NOTES = '<div class="nside"><span class="lights"><i></i><i></i><i></i></span><b>iCloud</b><span>All iCloud</span><span>Notes</span><span class="on">Trips</span><span>Recipes</span></div><div class="ntool"></div>'
  + '<div class="nlist">' + [["Tuscany, October", "Day 3: Val d’Orcia"], ["Packing", "Linen shirts"], ["Restaurants", "Osteria in Greve"], ["Florence", "Uffizi at 9"]]
    .map(([t, s], i) => `<div class="nrow${i === 0 ? " on" : ""}"><b>${t}</b><span>${s}</span></div>`).join("") + "</div>"
  + '<div class="nnote"><b>Tuscany, October</b><span></span><span></span><span class="short"></span><span></span><span class="short"></span></div>';

export class Quick extends Column {
  // A card's screenshot is open in the editor, which dims and blurs the screen behind it and has
  // narrowed the stack to make room, the card's slot kept empty. The crosshair comes in from the
  // space above the page's title and drags a box around it from its top left. Typing starts the
  // moment the button comes up, and the note appears beside the box. A narrow picture shows the
  // editor alone, short of the screen's right edge, as a lone thumbnail's leaves the stack.
  static fit = deskFit;
  static BOX = { type: "rect", who: "person", x: 40, y: 192, w: 588, h: 86 };
  // EditorGeometry.notePlace: a note for a box with room to its right starts there, the note gap
  // beyond the stroke, level with the box's top when the box is taller than one line.
  static NOTE = (() => {
    const b = Quick.BOX, ink = (MARK.stroke * POINT_SCALE) / 2;
    return { type: "note", who: "person", x: b.x + b.w + ink + MARK.noteGap * POINT_SCALE, y: b.y - ink, text: "make this quieter" };
  })();
  static REST = [430, 156];
  // How much of the page the frame shows across, in image px: past the note's end and the stays'
  // descriptions, short of their dates, so the frame's edge cuts no word.
  static ACROSS = 1040;
  // Bands of the page, in image px, where its text column has no words, less a margin.
  static CLEAR = [[315, 394], [488, 602], [696, 810], [901, 1119]];
  build({ W, H }) {
    const s = this.scene(W, H);
    const wide = W >= 440;
    // Under the column, the stack at its narrowest, as Recent and Drag hold it: the cards above the
    // one in the editor.
    const narrow = UI.stackMinScale, inner = this.R - CW * narrow - UI.stackGap * SCALE;
    this.screen("Notes", ["File", "Edit", "Format", "View", "Window"], el("div", "window notes", NOTES),
      { top: MENU_BAR * SCALE + 8, left: GUTTER + 36, right: wide ? inner + 30 : W + 16, clock: wide });
    this.backdrop.before(el("div", "dim on"));
    if (wide) {
      this.showBackdrop(1);
      const cards = el("div", "narrow");
      cards.style.transformOrigin = `${this.R}px ${this.bottom}px`;
      cards.style.transform = `scale(${narrow})`;
      cards.append(...this.column(SHOTS.slice(1, 3), this.bottom - STEP));
      this.col.append(cards);
    } else {
      this.backdrop.remove();
    }
    // The frame, its left edge on the copy's, runs off the picture's bottom, and off its right edge
    // where the picture ends short of the screen's.
    const fw = wide ? inner - GUTTER : W - GUTTER + 40, k = this.k = (wide ? fw : W - GUTTER) / Quick.ACROSS;
    // The page runs past the picture's bottom edge, its foot never short of it, and the edge falls
    // between the stays' lines.
    let top = Math.max(BELOW_MENU_BAR + 16, H + 24 - IMAGES.stays.h * k);
    const edge = () => (H - top) / k;
    while (top < H && !Quick.CLEAR.some(([a, b]) => edge() >= a && edge() <= b)) top += 1;
    const fh = H + 40 - top;
    this.view = { x: 0, y: 0, w: fw / k, h: fh / k };
    const f = el("div", "frame-x");
    place(f, { x: GUTTER, y: top, w: fw, h: fh });
    const sh = shot(IMAGES.stays, this.view, [], fw, fh);
    this.pic = sh.pic;
    this.marks = this.pic.querySelector("svg.marks");
    this.cursor = el("div", "crosshair", CROSSHAIR);
    f.append(sh, this.cursor);
    s.append(f);
    return s;
  }
  // `p` is the crosshair's way to the box's first corner and `t` the drag, each 0 to 1.
  draw(p, t) {
    const b = Quick.BOX;
    const box = { ...b, w: b.w * t, h: b.h * t };
    this.pic.update(t > 0.01 ? [box] : []);
    const [x, y] = t > 0 ? [box.x + box.w, box.y + box.h] : [lerp(Quick.REST[0], b.x, p), lerp(Quick.REST[1], b.y, p)];
    this.cursor.style.transform = `translate(${(x - this.view.x) * this.k - 10.5}px, ${(y - this.view.y) * this.k - 10.5}px)`;
  }
  reset() { this.draw(0, 0); this.marks.style.opacity = 1; this.cursor.style.opacity = 1; }
  final() { this.draw(1, 1); this.cursor.style.opacity = 0; this.marks.style.opacity = 1; this.pic.update([Quick.BOX, Quick.NOTE]); }
  async play() {
    this.reset();
    await tween(0.3, (p) => this.draw(handEase(p), 0));
    await tween(0.55, (t) => this.draw(1, handEase(t)));
    await wait(0.1);
    this.cursor.style.opacity = 0;
    const text = Quick.NOTE.text;
    for (let n = 1; n <= text.length; n++) {
      const note = { ...Quick.NOTE, text: text.slice(0, n) };
      this.pic.update([Quick.BOX, note], note);
      await wait(n === 1 ? 0.12 : 0.055);
    }
    this.pic.update([Quick.BOX, Quick.NOTE]);
  }
  async rewind() { this.marks.style.opacity = 0; this.cursor.style.opacity = 0; await wait(0.25); }
}
