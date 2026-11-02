// The picture of "Stitch several into one": three cards picked in the stack, stitched into one,
// over Calendar on the same screen.
import { el, place, Motion, UI, wait, cardSize, coverRect } from "../vignette.js";
import { IMAGES } from "../cards.js";
import { lerp, clamp, GUTTER, card, shot, whole, wideFit, selectionStrip, tap } from "./parts.js";
import { Column, SHOTS, CW, CH, SCALE, BELOW_MENU_BAR, at } from "./stack.js";

// Calendar's day view of the day Stitch's pieces are about, in the screen's points: an hour is
// HOUR tall from 05:00, and each event is its start, its length in hours, its colour and its title.
const HOUR = 40;
const EVENTS = [
  [5.5, 1, "blue", "Leave Greve"],
  [6 + 40 / 60, 1.33, "orange", "Val d’Orcia at sunrise"],
  [10, 1.5, "green", "Pecorino tasting, Pienza"],
  [15, 1, "purple", "Check in, Belvedere"],
];
const hhmm = (h) => `${String(Math.floor(h)).padStart(2, "0")}:${String(Math.round((h % 1) * 60)).padStart(2, "0")}`;
// The window `w` points wide. Its toolbar holds the view's buttons where they fit.
const calendar = (w) => `<div class="ctool"><span class="lights"><i></i><i></i><i></i></span>${w >= 300 ? '<span class="seg"><b>Day</b><span>Week</span><span>Month</span><span>Year</span></span>' : ""}</div>`
  + '<div class="chead"><b>14 October</b><span>Tuesday</span></div><div class="cday">'
  + Array.from({ length: 13 }, (_, i) => `<div class="hr" style="top:${i * HOUR}px"><span>${hhmm(5 + i)}</span></div>`).join("")
  + EVENTS.map(([at, len, colour, title]) => `<div class="ev ${colour}" style="top:${(at - 5) * HOUR}px;height:${len * HOUR - 2}px"><b>${title}</b><span>${hhmm(at)}</span></div>`).join("")
  + "</div>";

// Stitch's springs: the pieces' flight and fade, the column closing up, the push-in, and the
// rewind's slides of the new card out and of each piece back in.
const SPRINGS = ["p", "fade", "close", "zoom", "out", "in0", "in1", "in2"];
// What Stitch joins, in the order they were picked: captures of the chat asking about a day, of
// that day in the itinerary, and of the stay it ends at. Short, wide captures stack into one column
// whose shape a card shows whole, and each takes the badge's 32 px floor, so the badges read once
// the view pushes in. Each badge sits on plain page at its piece's top-left, and the first piece is
// the narrowest, so the column centres it and its badge clears the card's rounded corner.
const PIECES = [
  [IMAGES.chat, { x: 0, y: 284, w: 580, h: 228 }, []],
  [IMAGES.itin, { x: 1194, y: 650, w: 570, h: 262 }, []],
  [IMAGES.stays, { x: 24, y: 740, w: 820, h: 220 }, []],
];

// Stitch.compose's layout and badges: every column count is tried and the one a reader's resize
// keeps most of wins (Stitch.readerScale: a long side of 1568 px and 1568 patches of 28 px).
function readerScale(w, h) {
  const tokens = (s) => Math.ceil(Math.round(w * s) / 28) * Math.ceil(Math.round(h * s) / 28);
  let s = Math.min(1, 1568 / Math.max(w, h), Math.sqrt((1568 * 28 * 28) / (w * h)));
  while (s > 0.01 && tokens(s) > 1568) s *= 0.995;
  return s;
}
function stitchLayout(sizes) {
  const sum = (a) => a.reduce((x, y) => x + y, 0);
  const gap = clamp(Math.round(0.02 * Math.min(...sizes.map((s) => Math.min(s.w, s.h)))), 12, 48);
  let best = null;
  for (let columns = 1; columns <= sizes.length; columns++) {
    const rows = Math.ceil(sizes.length / columns), cw = Array(columns).fill(0), rh = Array(rows).fill(0);
    sizes.forEach((s, i) => { cw[i % columns] = Math.max(cw[i % columns], s.w); rh[Math.floor(i / columns)] = Math.max(rh[Math.floor(i / columns)], s.h); });
    const w = gap * 2 + sum(cw) + gap * (columns - 1), h = gap * 2 + sum(rh) + gap * (rows - 1);
    const frames = sizes.map((s, i) => {
      const c = i % columns, r = Math.floor(i / columns);
      return { x: gap + sum(cw.slice(0, c)) + gap * c + (cw[c] - s.w) / 2, y: gap + sum(rh.slice(0, r)) + gap * r + (rh[r] - s.h) / 2, w: s.w, h: s.h };
    });
    const plan = { w, h, frames, scale: readerScale(w, h) };
    if (!best || plan.scale > best.scale + 0.001) best = plan;
  }
  return best;
}
const badgeDiameter = (s) => { const short = Math.min(s.w, s.h); return Math.min(clamp(Math.round(0.06 * short), 32, 128), Math.round(0.8 * short)); };
// A card's picture filling `r`, cropped to it, as a flight draws a card whose shape is changing.
function fill(c, [image, view], r) {
  place(c, r);
  const k = Math.max(r.w / view.w, r.h / view.h);
  c.pic.place({ x: (r.w - view.w * k) / 2 - view.x * k, y: (r.h - view.h * k) / 2 - view.y * k, w: image.w * k, h: image.h * k });
}

export class Stitch extends Column {
  // Three cards are picked, with the selection strip beside them, and ⌘S lights its Stitch row. As
  // in ThumbnailController.stitched, the pieces leave the column, which closes up around the new
  // card's slot at once, and each flies into that slot (TransitionLayer.converge). The stitched
  // image waits there unseen and takes over in the last part of the flight, and the new card says
  // Copied. The view pushes in on it only once Copied has gone, since the app draws the notice at
  // card size.
  static fit = wideFit(318);
  build({ W, H }) {
    const s = this.scene(W, H);
    const picked = PIECES;
    const plan = stitchLayout(picked.map(([, view]) => view));
    const size = cardSize(plan);
    this.slot = { w: size.w * SCALE, h: size.h * SCALE };
    Object.assign(this.slot, { x: this.R - this.slot.w, y: this.bottom - this.slot.h });
    // The view pushes in on the screen's bottom-right corner, which stays put, so the screen fills
    // the picture throughout. It stops once the new card, every piece and badge whole, fills the
    // picture's height between margins as deep as the screen's margin under it, which holds its
    // shadow.
    const margin = H - this.slot.y - this.slot.h;
    this.zoom = Math.min(H / (this.slot.h + 2 * margin), (W - margin) / (W - this.slot.x));
    this.focus = this.look = { x: W, y: H };
    // Calendar's window ends where the push-in takes it past the picture's left edge, so the new
    // card ends on the wallpaper under the backdrop's blur. Short of the column, it ends under it.
    const right = Math.min(this.R - CW + 20, W - W / this.zoom - 4);
    this.screen("Calendar", ["File", "Edit", "View", "Window", "Help"], el("div", "window cal", calendar((right - GUTTER) / SCALE)), BELOW_MENU_BAR, right);
    this.showBackdrop(1);
    // Each picked card takes its capture's shape by the stack's card-size rule, newest at the bottom.
    let top = this.bottom + UI.cardSpacing;
    const from = [];
    for (let i = picked.length - 1; i >= 0; i--) {
      const { w, h } = cardSize(picked[i][1]);
      top -= h * SCALE + UI.cardSpacing;
      from[i] = { x: this.R - w * SCALE, y: top, w: w * SCALE, h: h * SCALE };
    }
    // The cards above the three, which move down to the new card.
    this.kept = this.column([[IMAGES.frame, whole(IMAGES.frame), []], SHOTS[1]], top - UI.cardSpacing);
    this.drop = this.slot.y - top;
    this.off = W - (this.R - CW) + 24;
    this.result = el("div", "cardx");
    place(this.result, this.slot);
    const clip = el("div", "shot");
    const pic = coverRect(this.slot, plan), k = pic.w / plan.w;
    const sheet = el("div", "stitched");
    place(sheet, pic);
    plan.frames.forEach((f, i) => {
      const r = { x: f.x * k, y: f.y * k, w: f.w * k, h: f.h * k };
      const [image, view, marks] = picked[i];
      const p = shot(image, view, marks, r.w, r.h);
      place(p, r);
      const d = badgeDiameter(f) * k;
      // A vector number, so it stays centred in its circle when the view pushes in on a badge a few
      // pixels wide.
      const b = el("div", "sbadge", `<svg viewBox="0 0 10 10" width="100%" height="100%"><text x="5" y="5" dy="0.35em" text-anchor="middle" font-size="6" font-weight="700" fill="#fff">${i + 1}</text></svg>`);
      Object.assign(b.style, { left: `${d / 4}px`, top: `${d / 4}px`, width: `${d}px`, height: `${d}px` });
      p.append(b);
      sheet.append(p);
    });
    clip.append(sheet);
    this.notice = el("div", "notice", '<div class="check"></div><b>Copied</b>');
    this.result.append(clip, this.notice);
    s.append(this.result);
    this.cards = picked.map(([image, view, marks], i) => {
      const c = card(image, view, marks, { x: 0, y: 0, w: CW, h: CH });
      c.pic.parentNode.style.width = c.pic.parentNode.style.height = "";
      c.num = el("div", "scircle", String(i + 1));
      c.append(c.num);
      c.from = from[i];
      s.append(c);
      return c;
    });
    // The selection strip, a strip gap left of the cards and centred on the picked ones
    // (StackLayout.stripPlacement), with the rows Config.stripRows shows for three screenshots.
    this.strip = selectionStrip();
    this.strip.classList.add("material");
    Object.assign(this.strip.style, { right: `${W - (this.R - CW) + 16 * SCALE}px`, top: `${(top + this.bottom) / 2 - 64}px` });
    this.stitchRow = this.strip.children[2];
    s.append(this.strip);
    this.m = new Motion((m) => {
      const p = m.get("p"), fade = m.get("fade");
      this.cards.forEach((c, i) => {
        fill(c, picked[i], this.flight(c.from, this.slot, p));
        c.style.opacity = 1 - fade;
      });
      this.result.style.opacity = fade;
      at(this.result, m.get("out") * this.off, 0);
      this.cards.forEach((c, i) => at(c, m.get(`in${i}`) * this.off, 0));
      const z = m.get("zoom"), k = lerp(1, this.zoom, z);
      // The cards above leave the view as it pushes in, and take their shadows with them.
      this.kept.forEach((c) => { c.style.transform = `translateY(${m.get("close") * this.drop}px)`; c.style.opacity = 1 - z; });
      cam.style.transform = `translate(${lerp(this.focus.x, this.look.x, z) - this.focus.x * k}px, ${lerp(this.focus.y, this.look.y, z) - this.focus.y * k}px) scale(${k})`;
    });
    for (const name of SPRINGS) this.m.add(name, 0, name === "zoom" ? 0.001 : 0.002);
    const cam = el("div", "cam");
    cam.append(...s.childNodes);
    s.append(cam);
    return s;
  }
  // FlightCurve: the path bows to the left of one that runs mostly up or down, and the card swells,
  // both most in the middle and nothing at the ends.
  flight(a, b, p) {
    const t = clamp(p, 0, 1), peak = 4 * t * (1 - t);
    const dx = b.x + b.w / 2 - a.x - a.w / 2, dy = b.y + b.h / 2 - a.y - a.h / 2, len = Math.hypot(dx, dy);
    let nx = len ? -dy / len : 0, ny = len ? dx / len : 0;
    if (Math.abs(dx) >= Math.abs(dy) ? ny > 0 : nx > 0) { nx = -nx; ny = -ny; }
    const bow = Math.min(len * UI.flightArc, UI.flightArcMax * SCALE) * peak, swell = 1 + UI.flightDepth * peak;
    const w = lerp(a.w, b.w, p) * swell, h = lerp(a.h, b.h, p) * swell;
    const cx = lerp(a.x + a.w / 2, b.x + b.w / 2, p) + nx * bow, cy = lerp(a.y + a.h / 2, b.y + b.h / 2, p) + ny * bow;
    return { x: cx - w / 2, y: cy - h / 2, w, h };
  }
  // A flight's image is the card's picture alone, so the selection leaves the pieces as they lift.
  pick(on, lifted = false) {
    this.cards.forEach((c) => { c.classList.toggle("picked", on); c.classList.toggle("lifted", lifted); c.num.classList.toggle("on", on); });
    this.strip.classList.toggle("up", on);
    if (on) this.stitchRow.classList.remove("lit");
  }
  reset() {
    this.pick(true); this.notice.classList.remove("in");
    for (const name of SPRINGS) this.m.jump(name, 0);
  }
  final() { this.reset(); this.pick(false); for (const name of ["p", "fade", "close", "zoom"]) this.m.jump(name, 1); }
  // The view pulls back as the new card slides off the screen's edge on its own. The column opens
  // up again, and the picked cards slide back into their slots, newest first, already selected.
  async rewind() {
    this.notice.classList.remove("in");
    const back = this.m.to("zoom", 0, 0.35);
    await wait(0.1);
    this.m.to("out", 1, UI.slideOut);
    await wait(UI.slideOut);
    this.cards.forEach((_, i) => this.m.jump(`in${i}`, 1));
    for (const name of ["p", "fade", "out"]) this.m.jump(name, 0);
    this.pick(true);
    await Promise.all([back, this.m.to("close", 0, UI.relayout), ...[2, 1, 0].map(async (i, n) => {
      await wait(Math.min(UI.stagger * n, UI.staggerMax));
      await this.m.to(`in${i}`, 0, UI.slideIn, UI.flightBounce);
    })]);
  }
  async play() {
    this.reset();
    await wait(0.15);
    this.stitchRow.classList.add("lit");
    await tap(this.stitchRow, 0.12);
    this.pick(false, true);
    this.m.to("close", 1, UI.relayout);
    const landed = this.m.to("p", 1, UI.expand, UI.flightBounce);
    const fade = UI.expand * 0.45;
    await wait(UI.expand - fade);
    this.m.to("fade", 1, fade);
    await landed;
    this.notice.classList.add("in");
    await wait(UI.noticeSeconds);
    this.notice.classList.remove("in");
    // The notice's fade, .notice's opacity transition.
    await wait(0.25);
    await this.m.to("zoom", 1, 0.8);
  }
}
