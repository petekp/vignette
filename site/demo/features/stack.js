// The pictures of the tiles under the first stage: the recent stack sliding in, a stitch, and a
// card dragged out. Each column of cards rests against the picture's right edge, the newest at the
// bottom, as the stack does against the screen's.
import { el, place, Motion, UI, wait, cardSize, coverRect } from "../vignette.js";
import { IMAGES, PERSON_MARKS } from "../cards.js";
import { lerp, clamp, GUTTER, card, whole, shot, wideFit, POINTER, selectionStrip, shiftKey, twice, tap } from "./parts.js";

const CW = 140, CH = 88, STEP = CH + UI.cardSpacing;
// The cards' scale against the app's: a 16:10 screenshot's card is 188 pt wide there.
const SCALE = CW / UI.cardMaxWidth;
// StackLayout.inset: the column fades out over the panel's padding at its ends.
const FADE = 19 * SCALE;
// Stitch's springs: the pieces' flight and fade, the column closing up, the push-in, and the
// rewind's slides of the new card out and of each piece back in.
const SPRINGS = ["p", "fade", "close", "zoom", "out", "in0", "in1", "in2"];
// Oldest first. The stays card answers Drag's question: the stay still waiting for its host.
const SHOTS = [
  [IMAGES.chat, { x: 0, y: 200, w: 1040, h: 650 }, []],
  [IMAGES.itin, whole(IMAGES.itin), PERSON_MARKS.slice(0, 2)],
  [IMAGES.packing, whole(IMAGES.packing), []],
  [IMAGES.stays, whole(IMAGES.stays), [
    { type: "rect", who: "person", x: 40, y: 752, w: 1728, h: 206 },
    { type: "note", who: "person", x: 40, y: 972, text: "this one" },
  ]],
];
// What Stitch joins, in the order they were picked: captures of the chat about a day, of three
// versions of that day's card, and of its stay's picture. Stitch lays them out in one column whose
// shape a card shows whole, and each badge sits on plain page at its piece's top-left. The first
// piece is narrower than the second, so the column centres it and its badge clears the card's
// rounded corner.
const PIECES = [
  [IMAGES.chat, { x: 0, y: 150, w: 1040, h: 960 }, []],
  [IMAGES.variants, { x: 24, y: 200, w: 1760, h: 720 }, []],
  [IMAGES.stays, { x: 0, y: 760, w: 325, h: 196 }, []],
];
// How far a card's shadow reaches above and below it: .cardx's box-shadow, 0 4px 8px.
const SHADOW = { above: 4, below: 12 };
const at = (node, x, y, s = 1) => { node.style.transform = `translate(${x}px, ${y}px) scale(${s})`; };

class Column {
  scene(W, H) {
    const s = this.s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    this.W = W; this.R = W - 24; this.bottom = H - 14;
    this.col = el("div", "scol");
    this.col.style.setProperty("--fade", `${FADE}px`);
    s.append(this.col);
    return s;
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

export class Recent extends Column {
  // Right Shift goes down twice, and the cards slide in from the screen's edge, the newest first.
  static fit = wideFit(236);
  build({ W, H }) {
    const s = this.scene(W, H);
    this.cards = this.column(SHOTS);
    // Beside the column, level with the newest card.
    const y = this.bottom - CH / 2 - 23, twiceX = this.R - CW - 40;
    this.key = shiftKey();
    place(this.key, { x: twiceX - 104, y });
    this.twice = twice();
    place(this.twice, { x: twiceX, y: y + 12 });
    s.append(this.key, this.twice);
    this.off = W - (this.R - CW) + 24;
    this.m = this.cards.map((c) => new Motion((m) => at(c, m.get("x"), 0)).add("x", this.off, 0.05));
    return s;
  }
  reset() { this.twice.classList.remove("on"); this.m.forEach((m) => m.jump("x", this.off)); }
  final() { this.reset(); this.twice.classList.add("on"); this.m.forEach((m) => m.jump("x", 0)); }
  // The stack slides out, as a dismissal takes it.
  async rewind() {
    this.twice.classList.remove("on");
    await Promise.all(this.m.map((m) => m.to("x", this.off, UI.slideOut)));
  }
  async play() {
    this.reset();
    await tap(this.key); await wait(0.11); await tap(this.key);
    this.twice.classList.add("on");
    await wait(0.08);
    const newestFirst = [...this.m].reverse();
    await Promise.all(newestFirst.map(async (m, i) => {
      await wait(Math.min(UI.stagger * i, UI.staggerMax));
      await m.to("x", 0, UI.slideIn, UI.flightBounce);
    }));
  }
}

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
    // The view pushes in until the new card, every piece and badge whole, fills the picture's height
    // with its shadow inside it, centred across the picture.
    const cam = el("div", "cam");
    cam.append(...s.childNodes);
    s.append(cam);
    const edge = 8;
    this.zoom = Math.min((W - 2 * edge) / this.slot.w, (H - 2 * edge) / (this.slot.h + SHADOW.above + SHADOW.below));
    this.focus = { x: this.slot.x + this.slot.w / 2, y: this.slot.y };
    this.look = { x: W / 2, y: edge + SHADOW.above * this.zoom };
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
  // The new card slides off the screen's edge on its own. The column opens up again, the picked
  // cards slide back into their slots, newest first, and their selection comes back.
  async rewind() {
    this.notice.classList.remove("in");
    await this.m.to("zoom", 0, 0.5);
    await this.m.to("out", 1, UI.slideOut);
    this.cards.forEach((_, i) => this.m.jump(`in${i}`, 1));
    for (const name of ["p", "fade", "out"]) this.m.jump(name, 0);
    await Promise.all([this.m.to("close", 0, UI.relayout), ...[2, 1, 0].map(async (i, n) => {
      await wait(Math.min(UI.stagger * n, UI.staggerMax));
      await this.m.to(`in${i}`, 0, UI.slideIn, UI.flightBounce);
    })]);
    this.pick(true);
    await wait(0.35);
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

export class Drag extends Column {
  // The newest card, which has a drawing, is dragged out of the stack into Claude Code, and the
  // prompt takes it as an image. The card stays in the stack. Claude Code keeps its prompt at the
  // bottom of the terminal, with a hint line under it, and the conversation scrolls above.
  static fit = wideFit(236);
  build({ W, H }) {
    const s = this.scene(W, H);
    const ln = (html, cls = "") => `<div class="ln${cls}">${html}</div>`;
    const said = (text) => ln(`<span class="t-said">●</span> ${text}`), you = (text) => ln(text, " t-dim"), gap = ln(" ");
    // Every line ends left of the column, at every width.
    const talk = W >= 520
      ? [said("Added the three stays to the map."), gap, you("&gt; Number the days."), gap, said("Done. Each day has its number now."), gap, you("&gt; Remind the host to confirm our stay.")]
      : [said("Mapped the stays."), gap, you("&gt; Number the days."), gap, said("Done."), gap, you("&gt; Remind the host"), you("  to confirm.")];
    const box = '<div class="pbox">&gt; <span class="typed"></span><span class="tcur"></span></div>';
    const t = el("div", "term-x claude", `<pre>${[...talk, gap, said("Which stay is it?"), box, you("  ? for shortcuts")].join("")}</pre>`);
    const below = 40, inset = 10;
    place(t, { x: GUTTER, y: 0, w: W - GUTTER + 40, h: H + below });
    t.firstChild.style.paddingBottom = `${below + inset}px`;
    this.typed = t.querySelector(".typed");
    s.insertBefore(t, this.col);
    this.column(SHOTS.slice(1));
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
    const line = 13 * 1.65;
    this.drop = { x: Math.min(GUTTER + 250, this.R - CW - 50), y: H - inset - line - 7 - line / 2 };
    this.m = new Motion((m) => {
      const t = m.get("t"), p = m.get("p");
      const x = t > 0 ? lerp(this.from.x, this.drop.x, t) : lerp(W + 10, this.from.x, p);
      const y = t > 0 ? lerp(this.from.y, this.drop.y, t) - Math.sin(Math.PI * t) * 30 : lerp(this.from.y + 50, this.from.y, p);
      at(this.pointer, x - 10, y - 7);
      at(this.ghost, x - this.grab.x, y - this.grab.y);
    }).add("t", 0, 0.001).add("p", 0, 0.001);
    return s;
  }
  dropped(on) { this.typed.textContent = on ? "[Image #1] " : ""; this.typed.style.width = ""; }
  reset() {
    this.ghost.style.opacity = 0; this.pointer.classList.remove("down"); this.dropped(false);
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
  // The drag in mid-flight over the prompt.
  poster() { this.reset(); this.m.jump("p", 1); this.m.jump("t", 0.65); this.ghost.style.opacity = 1; this.pointer.classList.add("down"); }
  async play() {
    this.reset();
    await wait(0.25);
    await this.m.to("p", 1, 0.45);
    this.pointer.classList.add("down");
    await wait(0.12);
    this.ghost.style.opacity = 1;
    await this.m.to("t", 1, 0.7);
    this.pointer.classList.remove("down");
    this.ghost.style.opacity = 0;
    this.dropped(true);
  }
}
