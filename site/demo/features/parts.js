// What the feature tiles' pictures are made of: parts of screenshots, cards as the stack draws them,
// and the layout every small picture shares.
import { picture, el, place, wait } from "../vignette.js";

export const lerp = (a, b, t) => a + (b - a) * t;
export const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
// The copy's inset inside a tile, which every picture's left edge lines up with.
export const GUTTER = 28;
const SVG_NS = "http://www.w3.org/2000/svg";

// A part of a screenshot: `view` (image px) fills a w by h box, with the screenshot's marks.
export function shot(image, view, marks, w, h) {
  const box = el("div", "shot");
  box.style.width = `${w}px`; box.style.height = `${h}px`;
  const pic = picture(image, marks);
  const k = w / view.w;
  pic.place({ x: -view.x * k, y: -view.y * k, w: image.w * k, h: image.h * k });
  box.append(pic);
  box.pic = pic;
  return box;
}
// A card as the stack draws it, showing `view` of its screenshot.
export function card(image, view, marks, rect, from) {
  const c = el("div", "cardx");
  place(c, rect);
  const s = shot(image, view, marks, rect.w, rect.h);
  c.append(s);
  c.pic = s.pic;
  if (from) c.append(el("div", "from", `<img src="${new URL("../claude.svg", import.meta.url).href}" alt="">From ${from}`));
  return c;
}
export const whole = (image) => ({ x: 0, y: 0, w: image.w, h: image.h });
export function overlay(w, h, html = "") {
  const svg = document.createElementNS(SVG_NS, "svg");
  svg.setAttribute("class", "over");
  svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
  svg.innerHTML = html;
  return svg;
}
export const POINTER = '<svg width="24" height="24" viewBox="0 0 32 32"><g transform="translate(10 7)"><path d="m6.148 18.473 1.863-1.003 1.615-.839-2.568-4.816h4.332l-11.379-11.408v16.015l3.316-3.221z" fill="#fff"/><path d="m6.431 17 1.765-.941-2.775-5.202h3.604l-8.025-8.043v11.188l2.53-2.442z" fill="#000"/></g></svg>';

// Small tiles are laid out for their width, at about the app's own size. `rest` is how much of a
// scene's height must show: its payoff, whole, with a gutter under it.
export const smallFit = (rest) => (slotW) => {
  const k = clamp(slotW / 375, 0.86, 1.15);
  const W = Math.round(slotW / k);
  return { W, H: 250, rest, k, key: String(W) };
};
// The tiles under the first stage are wider than the feature tiles. Their pictures keep the feature
// tiles' scale from 375 pt up, so a wider tile shows more rather than drawing larger, and fill the
// slot's height, which the tile beside them can stretch.
export const wideFit = (rest) => (slotW, slotH = 0) => {
  const k = clamp(slotW / 375, 0.86, 1);
  const W = Math.round(slotW / k), H = Math.max(rest, Math.ceil(slotH / k));
  return { W, H, rest, k, key: `${W} ${H}` };
};

// The selection strip's rows, as Config.stripRows shows them for three screenshots.
const ICONS = {
  copy: '<rect x="6" y="6" width="9" height="11" rx="2" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M4 13V5a2 2 0 0 1 2-2h6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',
  draw: '<path d="M4 16l1-4 8-8 3 3-8 8z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><path d="M11 17h6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',
  stitch: '<rect x="4" y="8" width="12" height="9" rx="2" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M6 5.5h8M8 3h4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',
  trash: '<path d="M4.5 6h11M8 6V4h4v2M6 6l.8 10.5h6.4L14 6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>',
};
const ROWS = [["copy", "Copy", "⌘C"], ["draw", "Draw", "↩"], ["stitch", "Stitch", "⌘S"], ["trash", "Delete", "⌘⌫"]];
export const selectionStrip = () => el("div", "qstrip", ROWS.map(([icon, label, key]) =>
  `<div class="row" data-row="${icon}"><svg viewBox="0 0 20 20" width="15" height="15">${ICONS[icon]}</svg><span>${label}</span><kbd>${key}</kbd></div>`).join(""));

// Keys as a Mac's keyboard draws them, for the tiles whose beat a key causes: right Shift with its
// glyph over its name, and Esc.
export const shiftKey = () => el("div", "kcap shiftk", "<span>⇧</span><span>shift</span>");
export const escKey = () => el("div", "kcap esck", "<span>esc</span>");
export const twice = () => el("div", "twice", "×2");
export async function tap(key, hold = 0.09) { key.classList.add("down"); await wait(hold); key.classList.remove("down"); }
