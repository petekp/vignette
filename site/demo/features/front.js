import { el, cardSize, place, coverRect, Motion, UI, wait } from "../vignette.js";
import { IMAGES, PERSON_MARKS } from "../cards.js";
import { card, whole } from "./parts.js";

export class Front {
  // The top-right of a screen: Chrome in front, its address bar taking the typing, while the stack
  // slides in at the screen's edge. Wide, the window and the stack; compact, the stack beside the
  // address bar.
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
    const win = el("div", "window", `<div class="chrome"><i></i><i></i><i></i><span class="field"><span class="typed"></span><b class="tcaret"></b></span></div><div class="page"><img src="${IMAGES.stays.src}" alt=""></div>`);
    // The window runs off the screen's bottom edge however tall the screen is.
    const r = compact ? { x: 12, y: 64, w: 600, h: H + 80 } : { x: 48, y: 76, w: 760, h: H - 20 };
    place(win, r);
    win.querySelector(".page").style.height = `${r.h - 40}px`;
    Object.assign(win.querySelector(".page img").style, { objectFit: "cover", objectPosition: "0 0" });
    if (compact) Object.assign(win.querySelector(".field").style, { margin: "0 0 0 18px", maxWidth: "300px" });
    s.append(win);
    this.typed = win.querySelector(".typed");
    // Compact, the address is shorter, so its typing stays clear of the stack's blur.
    this.base = compact ? "postcard.app" : "postcard.app/stays";
    this.more = compact ? "/stays" : "/belvedere";
    this.backdrop = el("div", "backdrop", "<i></i><i></i><i></i><i></i><i></i><b></b>");
    this.backdrop.style.width = compact ? "200px" : "240px";
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
      this.backdrop.style.setProperty("--shown", m.get("backdrop"));
      this.cards.forEach((c, i) => { c.style.transform = `translateX(${m.get(`x${i}`) * c.away}px)`; });
    }).add("backdrop", 0);
    this.cards.forEach((_, i) => this.m.add(`x${i}`, 1, 0.001));
    return s;
  }
  reset() {
    this.typed.textContent = this.base;
    this.m.jump("backdrop", 0);
    this.cards.forEach((_, i) => this.m.jump(`x${i}`, 1));
  }
  final() {
    this.typed.textContent = this.base + this.more;
    this.m.jump("backdrop", 1);
    this.cards.forEach((_, i) => this.m.jump(`x${i}`, 0));
  }
  async play() {
    const typing = (async () => {
      await wait(0.15);
      for (const ch of this.more) { this.typed.textContent += ch; await wait(0.1); }
    })();
    await wait(0.35);
    this.m.to("backdrop", 1, UI.slideIn);
    for (let i = this.cards.length - 1; i >= 0; i--) {
      this.m.to(`x${i}`, 0, UI.slideIn, UI.flightBounce);
      await wait(UI.stagger);
    }
    await typing;
  }
  async rewind() {
    this.m.to("backdrop", 0, UI.slideOut);
    this.cards.forEach((_, i) => this.m.to(`x${i}`, 1, UI.slideOut));
    await wait(UI.slideOut + 0.1);
    while (this.typed.textContent.length > this.base.length) {
      this.typed.textContent = this.typed.textContent.slice(0, -1);
      await wait(0.03);
    }
  }
}
