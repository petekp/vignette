import { el, cardSize, place, coverRect, Motion, UI, wait } from "../vignette.js";
import { IMAGES, PERSON_MARKS } from "../cards.js";
import { card, whole } from "./parts.js";

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

export class Front {
  // The top-right of a screen: Chrome in front, its address bar taking the typing. The typing
  // pauses, the stack slides in at the screen's edge and takes the keys, so the caret goes, and Esc
  // closes it: the caret is back in the same field and the typing goes on. Chrome stays the active
  // app throughout, as the stack's panel never activates Vignette. Wide, the window and the stack;
  // compact, the stack beside the address bar.
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
    s.append(el("div", "menubar", `<span class="apple"></span><b>Chrome</b><span>File</span><span>Edit</span><span>View</span>${compact ? "" : "<span>History</span><span>Bookmarks</span>"}<i>${compact ? "" : "Sun 1 Nov&nbsp;&nbsp;"}9:41</i>`));
    const win = el("div", "window", `<div class="chrome"><i></i><i></i><i></i><span class="field"><span class="typed">postcard.app/</span><span class="added"></span><b class="tcaret"></b></span></div><div class="page"><img src="${IMAGES.stays.src}" alt=""></div>`);
    // The window runs off the screen's bottom edge however tall the screen is.
    const r = compact ? { x: 12, y: 64, w: 600, h: H + 80 } : { x: 48, y: 76, w: 760, h: H - 20 };
    place(win, r);
    win.querySelector(".page").style.height = `${r.h - 40}px`;
    Object.assign(win.querySelector(".page img").style, { objectFit: "cover", objectPosition: "0 0" });
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
  reset() {
    this.added.textContent = ""; this.added.style.opacity = "";
    this.field.classList.remove("typing");
    this.keys(false); this.stack(false);
  }
  final() { this.reset(); this.added.textContent = this.first + this.more; }
  poster() { this.reset(); this.added.textContent = this.first; this.keys(true); this.stack(true); }
  async type(text) {
    for (const ch of text) { this.added.textContent += ch; await wait(0.09); }
  }
  async play() {
    this.reset();
    this.field.classList.add("typing");
    await wait(0.2);
    await this.type(this.first);
    await wait(0.3);
    this.keys(true);
    this.m.to("backdrop", 1, UI.slideIn);
    for (let i = this.cards.length - 1; i >= 0; i--) {
      this.m.to(`x${i}`, 0, UI.slideIn, UI.flightBounce);
      await wait(UI.stagger);
    }
    await wait(1.2);
    this.m.to("backdrop", 0, UI.slideOut);
    this.cards.forEach((_, i) => this.m.to(`x${i}`, 1, UI.slideOut));
    this.keys(false);
    await wait(0.35);
    await this.type(this.more);
    this.field.classList.remove("typing");
  }
  async rewind() {
    this.keys(true);
    this.added.style.opacity = 0;
    await wait(0.3);
    this.reset();
  }
}
