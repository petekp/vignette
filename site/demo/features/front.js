import { el, cardSize, place, coverRect, Motion, UI, wait } from "../vignette.js";
import { IMAGES, PERSON_MARKS } from "../cards.js";
import { card, whole, shiftKey, escKey, twice, tap } from "./parts.js";

// BackdropPanel's strip at the app's defaults: bands of blur whose radius grows toward the screen's
// edge, each fading in over the band before it and out over the next, under a tint that darkens to
// the edge.
const BANDS = 7, BLUR = 25, RAMP = 1.2;
function backdrop() {
  const b = el("div", "backdrop");
  b.style.width = `${UI.backdropWidth}px`;
  const step = 100 / BANDS;
  for (let i = 0; i < BANDS; i++) {
    const stops = i === 0 ? ["transparent 0%", `#000 ${step}%`] : [`transparent ${step * (i - 1)}%`, `#000 ${step * i}%`];
    stops.push(...(i === BANDS - 1 ? ["#000 100%"] : [`#000 ${step * (i + 1)}%`, `transparent ${Math.min(100, step * (i + 2))}%`]));
    const mask = `linear-gradient(90deg, ${stops.join(", ")})`;
    const blur = `blur(${(BLUR * ((i + 1) / BANDS) ** RAMP).toFixed(2)}px)`;
    const band = el("i");
    Object.assign(band.style, { backdropFilter: blur, webkitBackdropFilter: blur, maskImage: mask, webkitMaskImage: mask });
    b.append(band);
  }
  b.append(el("b"));
  return b;
}

// Where the stays page's right edge shows, in its own pixels: wide, past the dates (which end at
// 1320) and short of the badges, avatars and button (from 1517); compact, past the descriptions (to
// 967) and short of the dates (from 1168).
const PAGE_EDGE = { wide: 1420, compact: 1060 };

export class Front {
  // The top-right of a screen: Chrome in front, its address bar taking the typing. The typing
  // pauses, right Shift goes down twice, and the stack slides in at the screen's edge and takes the
  // keys, so the caret goes. Esc closes it: the caret is back in the same field and the typing goes
  // on. Chrome stays the active app throughout, as the stack's panel never activates Vignette. Wide,
  // the window and the stack; compact, the stack beside the address bar.
  // The screen is as tall as the picture's slot, which the grid can make taller than the scene needs
  // (beside a taller column of tiles), so the wallpaper, the backdrop and the stack always reach the
  // tile's bottom edge.
  static fit(slotW, slotH = 0) {
    const compact = slotW < 560;
    const W = compact ? 440 : 900;
    const rest = compact ? 440 : 660;
    const k = slotW / W;
    const H = Math.max(rest, Math.ceil(slotH / k));
    return { W, H, rest, k, key: `${compact ? "compact" : "wide"} ${H}` };
  }
  build({ W, H }) {
    const compact = W < 900;
    const s = el("div", "scene");
    s.style.width = `${W}px`; s.style.height = `${H}px`;
    s.append(el("div", "wallpaper"));
    s.append(el("div", "menubar", `<span class="apple">\uF8FF</span><b>Chrome</b><span>File</span><span>Edit</span><span>View</span>${compact ? "" : "<span>History</span><span>Bookmarks</span>"}<i>${compact ? "" : "Sun 1 Nov&nbsp;&nbsp;"}9:41</i>`));
    const win = el("div", "window", `<div class="chrome"><i></i><i></i><i></i><span class="field"><span class="typed">postcard.app/</span><span class="added"></span><b class="tcaret"></b></span></div><div class="page"><img src="${IMAGES.stays.src}" alt=""></div>`);
    // The window runs off the screen's bottom edge however tall the screen is. Compact, the screen's
    // bottom falls between the second stay and the third's name.
    const r = compact ? { x: 12, y: 76, w: 600, h: H + 80 } : { x: 48, y: 76, w: 760, h: H - 20 };
    place(win, r);
    // The page is drawn to the window's width, or to the picture's edge where the window runs past
    // it, so that edge falls between two of the page's columns of text and cuts no word.
    const page = win.querySelector(".page");
    page.style.height = `${r.h - 40}px`;
    const shown = Math.min(r.w, W - r.x), k = shown / (compact ? PAGE_EDGE.compact : PAGE_EDGE.wide);
    Object.assign(page.querySelector("img").style, { width: `${IMAGES.stays.w * k}px`, height: `${IMAGES.stays.h * k}px` });
    if (compact) Object.assign(win.querySelector(".field").style, { margin: "0 0 0 18px", maxWidth: "300px" });
    s.append(win);
    this.field = win.querySelector(".field");
    this.added = win.querySelector(".added");
    // Compact, the address is shorter, so its typing stays clear of the stack's blur.
    this.first = "stays";
    this.more = compact ? "/villa" : "/belvedere";
    this.backdrop = backdrop();
    s.append(this.backdrop);
    const list = compact ? [[IMAGES.chat, []], [IMAGES.itin, PERSON_MARKS]] : [[IMAGES.packing, []], [IMAGES.chat, []], [IMAGES.itin, PERSON_MARKS]];
    this.cards = [];
    let y = H - UI.screenMargin;
    for (let i = list.length - 1; i >= 0; i--) {
      const [image, marks] = list[i];
      const size = cardSize(image);
      y -= size.h;
      const c = card(image, whole(image), marks, { x: W - UI.screenMargin - size.w, y, ...size });
      const cover = coverRect(size, image);
      c.pic.place(cover);
      if (i === list.length - 1) c.append(el("i", "focusring"));
      c.away = size.w + UI.screenMargin + 30;
      s.append(c);
      this.cards.unshift(c);
      y -= UI.cardSpacing;
    }
    // The keys sit on the wallpaper over the address field, which takes the typing they interrupt.
    const keysAt = compact ? { x: 150, y: 30, scale: 0.68 } : { x: 520, y: 30, scale: 0.85 };
    this.shift = shiftKey();
    this.twice = twice();
    place(this.shift, { x: 0, y: 0 });
    place(this.twice, { x: 104, y: 12 });
    this.shiftKeys = el("div", "fkeys");
    this.shiftKeys.append(this.shift, this.twice);
    place(this.shiftKeys, keysAt);
    this.esc = escKey();
    this.escKeys = el("div", "fkeys");
    this.escKeys.append(this.esc);
    place(this.escKeys, keysAt);
    for (const k of [this.shiftKeys, this.escKeys]) k.style.setProperty("--scale", keysAt.scale);
    s.append(this.shiftKeys, this.escKeys);
    this.m = new Motion((m) => {
      const b = m.get("backdrop");
      this.backdrop.style.setProperty("--shown", b);
      this.backdrop.style.transform = `translateX(${(1 - b) * UI.backdropWidth}px)`;
      this.cards.forEach((c, i) => { c.style.transform = `translateX(${m.get(`x${i}`) * c.away}px)`; });
    }).add("backdrop", 0);
    this.cards.forEach((_, i) => this.m.add(`x${i}`, 1, 0.001));
    return s;
  }
  // While the stack holds the keys, Chrome's field draws no caret.
  keys(stack) { this.field.classList.toggle("caret-off", stack); }
  stack(open) {
    this.m.jump("backdrop", open ? 1 : 0);
    this.cards.forEach((_, i) => this.m.jump(`x${i}`, open ? 0 : 1));
  }
  showKeys(shift, esc) {
    this.shiftKeys.classList.toggle("up", shift);
    this.twice.classList.toggle("on", shift);
    this.escKeys.classList.toggle("up", esc);
  }
  reset() {
    this.added.textContent = ""; this.added.style.opacity = "";
    this.field.classList.remove("typing");
    this.keys(false); this.stack(false); this.showKeys(false, false);
  }
  final() { this.reset(); this.added.textContent = this.first + this.more; }
  poster() { this.reset(); this.added.textContent = this.first; this.keys(true); this.stack(true); this.showKeys(true, false); }
  async type(text) {
    for (const ch of text) { this.added.textContent += ch; await wait(0.09); }
  }
  async play() {
    this.reset();
    this.field.classList.add("typing");
    await wait(0.2);
    await this.type(this.first);
    await wait(0.15);
    this.shiftKeys.classList.add("up");
    await wait(0.15);
    await tap(this.shift); await wait(0.11); await tap(this.shift);
    this.twice.classList.add("on");
    this.keys(true);
    this.m.to("backdrop", 1, UI.slideIn);
    for (let i = this.cards.length - 1; i >= 0; i--) {
      this.m.to(`x${i}`, 0, UI.slideIn, UI.flightBounce);
      await wait(UI.stagger);
    }
    await wait(1.2);
    this.showKeys(false, true);
    await wait(0.2);
    const pressing = tap(this.esc);
    this.m.to("backdrop", 0, UI.slideOut);
    this.cards.forEach((_, i) => this.m.to(`x${i}`, 1, UI.slideOut));
    this.keys(false);
    await pressing;
    await wait(0.25);
    this.showKeys(false, false);
    await this.type(this.more);
    this.field.classList.remove("typing");
  }
  async rewind() {
    this.keys(true);
    this.showKeys(false, false);
    this.added.style.opacity = 0;
    await wait(0.3);
    this.reset();
  }
}
