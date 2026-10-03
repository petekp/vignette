// The screenshots the page draws on, and the marks on them, shared by the demos, the closer's fan
// and the share image (site/og/index.html).
import { picture, el } from "./vignette.js";

// Paths resolve from this file, so a page in another folder can use them.
const img = (name, w, h) => ({ src: new URL(name, import.meta.url).href, w, h });
export const IMAGES = {
  itin: img("itin.jpg", 1808, 1130),
  itinR1: img("itin-r1.jpg", 1808, 1130),
  itinFinal: img("itin-final.jpg", 1808, 1130),
  variants: img("variants.jpg", 1808, 1130),
  stays: img("stays.jpg", 1808, 1130),
  packing: img("packing.jpg", 1808, 1130),
  terminal: img("terminal.jpg", 1920, 1280),
  chat: img("chat.jpg", 1040, 1360),
  frame: img("frame.jpg", 1800, 1145),
};

export const PERSON_MARKS = [
  { type: "rect", who: "person", x: 1196, y: 452, w: 579, h: 580 },
  { type: "note", who: "person", x: 1196, y: 1050, text: "make this pop, options?" },
  { type: "arrow", who: "person", x1: 1322, y1: 332, x2: 852, y2: 668 },
  { type: "note", who: "person", x: 1222, y: 252, text: "number the days" },
];
// Claude's answer: a note on what sets each version apart, an arrow to it, and a question.
export const CLAUDE_MARKS = [
  { type: "note", who: "agent", x: 230, y: 160, text: "warm tint" },
  { type: "arrow", who: "agent", x1: 315, y1: 222, x2: 300, y2: 302 },
  { type: "note", who: "agent", x: 790, y: 160, text: "Highlight tag" },
  { type: "arrow", who: "agent", x1: 860, y1: 222, x2: 800, y2: 268 },
  { type: "note", who: "agent", x: 1100, y: 160, text: "photo fills the card" },
  { type: "arrow", who: "agent", x1: 1300, y1: 222, x2: 1400, y2: 345 },
  { type: "note", who: "agent", x: 722, y: 884, text: "Which one do you like?" },
];

// The closer's fan: five cards from the demos, drawn with the same marks, behind the app icon.
// Each card is a region screenshot: `view` is the part of the image it shows, so its marks read.
const FAN = [
  { image: IMAGES.stays, view: { x: 0, y: 110, w: 1100, h: 688 }, marks: [{ type: "rect", who: "person", x: 40, y: 192, w: 588, h: 86 }, { type: "note", who: "person", x: 40, y: 292, text: "make this\nquieter" }] },
  { image: IMAGES.chat, view: { x: 0, y: 250, w: 900, h: 562 }, marks: [{ type: "rect", who: "person", x: 22, y: 390, w: 478, h: 116 }, { type: "note", who: "person", x: 22, y: 522, text: "this road" }] },
  { image: IMAGES.variants, view: { x: 520, y: 60, w: 1260, h: 788 }, marks: CLAUDE_MARKS, from: "Claude" },
  { image: IMAGES.itin, view: { x: 860, y: 300, w: 940, h: 588 }, marks: [{ type: "rect", who: "person", x: 1196, y: 452, w: 579, h: 580 }, { type: "note", who: "person", x: 1480, y: 380, text: "make this pop" }] },
  { image: IMAGES.frame, view: { x: 520, y: 130, w: 880, h: 550 }, marks: [{ type: "rect", who: "person", x: 812, y: 168, w: 456, h: 462 }, { type: "note", who: "person", x: 1160, y: 586, text: "more space" }] },
];
export function buildFan(fan) {
  FAN.forEach((c, n) => {
    const i = n - 2;
    const card = el("div", "fan-card");
    card.style.setProperty("--i", i);
    card.style.zIndex = 5 - Math.abs(i);
    const pic = picture(c.image, c.marks);
    card.append(pic);
    if (c.from) card.append(el("div", "from", `<img src="${new URL("claude.svg", import.meta.url).href}" alt="">From ${c.from}`));
    fan.prepend(card);
    new ResizeObserver(([entry]) => {
      const k = Math.round(entry.contentRect.width) / c.view.w;
      pic.place({ x: -c.view.x * k, y: -c.view.y * k, w: c.image.w * k, h: c.image.h * k });
    }).observe(card);
  });
}
