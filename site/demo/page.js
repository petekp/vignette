import { Stage, wait, tween, motion, el, copyPNG } from "./vignette.js";
import { IMAGES, PERSON_MARKS, CLAUDE_MARKS, buildFan } from "./cards.js";

Object.values(IMAGES).forEach((i) => { new Image().src = i.src; });

const coarse = matchMedia("(pointer: coarse)").matches;

// A hint under a stage, and the step it names. A step the visitor can take is a button, which
// takes the step when pressed: `keys` draws the keys that take it, `glyph` the kind of press, and
// `ring` names what to click in the stage, which a halo rings until the hint changes. A hint with no
// action is a status line.
const svg = (d) => `<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
const GLYPHS = {
  click: svg('<path d="M7.5 6.5l8 4.6-3.6.9-1.7 3.4z" fill="currentColor"/><path d="M5.2 2.8l.7 1.9M2.6 5.3l1.9.7M8.6 2.4l-.4 1.9"/>'),
  capture: svg('<path d="M3 6.5V4.2c0-.7.5-1.2 1.2-1.2h2.3M13.5 3h2.3c.7 0 1.2.5 1.2 1.2v2.3M17 13.5v2.3c0 .7-.5 1.2-1.2 1.2h-2.3M6.5 17H4.2c-.7 0-1.2-.5-1.2-1.2v-2.3"/><path d="M10 7v6M7 10h6"/>'),
  draw: svg('<rect x="3" y="4.5" width="14" height="11" rx="1.6"/>'),
  replay: svg('<path d="M4.5 10a5.5 5.5 0 1 0 1.7-4"/><path d="M4.2 3.2v3.3h3.3"/>'),
  check: svg('<path class="draw" d="M4.5 10.5l3.5 3.5 7.5-8"/>'),
  failed: svg('<path d="M5 5l10 10M15 5L5 15"/>'),
  busy: '<i class="busy"></i>',
};
const KEYS = {
  shift2: [["ShiftRight", "⇧"], ["ShiftRight", "⇧"]],
  ret: [["Enter", "↩"]],
  cmdRet: [["MetaLeft", "⌘"], ["Enter", "↩"]],
};
function hint(button) {
  let action = null, ringed = null, shown = null, swapTimer = 0, update = 0;
  button.addEventListener("click", () => action?.());
  // Springs the button from its width now to the width it has with `html` inside, before the
  // words change, so the new words never fade in cut off by a button still growing.
  const resize = (html, status) => {
    const probe = button.cloneNode(false);
    probe.removeAttribute("id");
    probe.className = `hint${status ? " status" : ""}`;
    probe.style.cssText = "position: absolute; visibility: hidden; width: auto; white-space: nowrap";
    probe.innerHTML = html;
    button.after(probe);
    const before = button.getBoundingClientRect().width, after = probe.getBoundingClientRect().width;
    probe.remove();
    if (!motion() || Math.abs(after - before) <= 1) return;
    button.classList.add("resizing");
    button.style.width = `${before}px`;
    button.getBoundingClientRect();
    button.style.width = `${after}px`;
  };
  return (text, act, { keys, glyph = "click", ring } = {}) => {
    const current = ++update;
    clearTimeout(swapTimer);
    action = null;
    button.disabled = true;
    const lead = act && keys && !coarse
      ? KEYS[keys].map(([code, label]) => `<kbd data-code="${code}">${label}</kbd>`).join("")
      : `<span class="glyph">${GLYPHS[act ? glyph : glyph === "click" ? "busy" : glyph]}</span>`;
    const html = `<span class="lead" aria-hidden="true">${lead}</span><span>${text}</span>`;
    const apply = () => {
      if (current !== update) return;
      ringed?.remove();
      const target = act && ring ? ring() : null;
      ringed = target ? target.appendChild(el("i", "halo")) : null;
      ringed?.addEventListener("animationend", (e) => e.target.classList.add("breathe"), { once: true });
      button.innerHTML = html;
      action = act;
      button.disabled = !act;
      button.classList.toggle("status", !act);
      requestAnimationFrame(() => { if (current === update) button.classList.remove("swap"); });
    };
    if (shown === text) return apply();
    shown = text;
    // The words fade out while the button springs to its new width, then the new words fade in. A
    // button that becomes a line of text fades its background with its words; a line of text that
    // becomes a button gets its background with the new words. Either way it never stands empty.
    button.classList.add("swap");
    if (!act) button.classList.add("status");
    resize(html, !act);
    swapTimer = setTimeout(apply, 140 * motion());
  };
}
// Every keycap a hint will show is laid out, hidden, from the start: the first layout of ⌘ or ↩
// looks for a font that has it, which took 10 to 13 ms in the frame that showed it.
document.querySelectorAll(".hint-row").forEach((row) => row.append(el("span", "hint warm", "<kbd>⇧⌘↩</kbd>")));
document.querySelectorAll(".hint").forEach((b) => b.addEventListener("transitionend", (e) => {
  if (e.target !== b || e.propertyName !== "width") return;
  b.style.width = "";
  b.classList.remove("resizing");
}));

// The keycaps go down with the real keys, the first ⇧ on the first tap and the second on the next.
const held = new Map();
addEventListener("keydown", (e) => {
  if (e.repeat) return;
  const caps = [...document.querySelectorAll(`.hint kbd[data-code="${e.code === "MetaRight" ? "MetaLeft" : e.code}"]:not(.down)`)];
  const cap = caps.find((k) => !k.dataset.hit) || caps[0];
  if (!cap) return;
  cap.classList.add("down");
  cap.dataset.hit = "1";
  held.set(e.code, cap);
  clearTimeout(cap.hitTimer);
});
addEventListener("keyup", (e) => {
  const cap = held.get(e.code);
  if (!cap) return;
  held.delete(e.code);
  cap.classList.remove("down");
  const group = cap.parentElement.querySelectorAll("kbd");
  clearTimeout(group[0].hitTimer);
  group[0].hitTimer = setTimeout(() => group.forEach((k) => delete k.dataset.hit), 500);
});

function browser(stage, rect, image, url) {
  const w = stage.addWindow(`<div class="chrome"><i></i><i></i><i></i><span>${url}</span></div><div class="page"></div>`, rect, "browser");
  const page = w.querySelector(".page");
  page.style.height = `${rect.h - 40}px`;
  const show = (image) => {
    const next = el("img"); next.src = image.src; next.alt = ""; next.style.opacity = 0;
    page.append(next);
    requestAnimationFrame(() => requestAnimationFrame(() => { next.style.opacity = 1; }));
    setTimeout(() => [...page.querySelectorAll("img")].slice(0, -1).forEach((o) => o.remove()), 600);
  };
  const first = el("img"); first.src = image.src; first.alt = ""; page.append(first);
  return { show };
}

// ---------------------------------------------------------------------------------------------
// Act one: the stack on a double tap, a card into the annotator, a drawing, and Copy.

const one = new Stage(document.getElementById("stage-one"), { shortcut: true, app: "Chrome", keep: 6, home: { x: 270, y: 0, w: 900, h: 900 } });
const STAYS = { x: 220, y: 70, w: 1000, h: 665 };
browser(one, STAYS, IMAGES.stays, "postcard.app/stays");
// Each card's "show me": the box the hint draws on it, and the note typed beside it.
const ONE_CARDS = [
  { image: IMAGES.chat, demo: { box: { x: 22, y: 390, w: 478, h: 116 }, words: "this road" } },
  { image: IMAGES.frame, demo: { box: { x: 812, y: 168, w: 456, h: 462 }, words: "use this spacing" } },
  { image: IMAGES.terminal, demo: { box: { x: 96, y: 628, w: 630, h: 50 }, words: "number the days like this" } },
  { image: IMAGES.packing, demo: { box: { x: 1200, y: 330, w: 575, h: 440 }, words: "add sunscreen" } },
  { image: IMAGES.itin, demo: { box: { x: 1196, y: 452, w: 579, h: 580 }, words: "make this pop" } },
];
one.setCards(ONE_CARDS);

// The parts of the stays page the hint captures, in turn, in the page image's pixels, with what
// "show me" then draws on each.
const SHOTS = [
  { crop: { x: 300, y: 545, w: 1480, h: 420 }, demo: { box: { x: 1205, y: 262, w: 240, h: 96 }, words: "ask the host" } },
  { crop: { x: 30, y: 130, w: 1750, h: 420 }, demo: { box: { x: 1515, y: 105, w: 230, h: 100 }, words: "make this quieter" } },
  { crop: { x: 40, y: 330, w: 960, h: 620 }, demo: { box: { x: 20, y: 22, w: 250, h: 590 }, words: "use real photos" } },
];
let shots = 0, oneActivity = 0;
const copyActivities = new WeakMap();
const staysImage = new Image();
staysImage.src = IMAGES.stays.src;

// Each capture's picture, cut from the page and encoded once, while the page is idle: encoding it
// on the press held the main thread for 80 ms on a Mac and 120 ms on a phone. `png` is the file the
// clipboard gets and `src` the card's picture.
const crops = new Map();
function crop(shot) {
  if (!crops.has(shot)) {
    crops.set(shot, staysImage.decode().then(() => {
      const c = shot.crop;
      const canvas = document.createElement("canvas");
      canvas.width = c.w; canvas.height = c.h;
      canvas.getContext("2d").drawImage(staysImage, c.x, c.y, c.w, c.h, 0, 0, c.w, c.h);
      return new Promise((r) => canvas.toBlob(r, "image/png"));
    }).then(async (png) => {
      const src = URL.createObjectURL(png);
      const img = new Image();
      img.src = src;
      await img.decode().catch(() => {});
      return { png, src };
    }));
  }
  return crops.get(shot);
}
const idle = window.requestIdleCallback || ((f) => setTimeout(f, 200));
idle(() => SHOTS.forEach(crop));

// A capture puts its picture on the clipboard, as Vignette does when macOS saves the file.
let capturing = false;
async function takeScreenshot() {
  if (capturing) return;
  capturing = true;
  const activity = ++oneActivity;
  const shot = SHOTS[shots++ % SHOTS.length], c = shot.crop;
  const ready = crop(shot);
  const copied = copyPNG(ready.then((r) => r.png));
  const k = STAYS.w / IMAGES.stays.w;
  const rect = { x: STAYS.x + c.x * k, y: STAYS.y + 40 + c.y * k, w: c.w * k, h: c.h * k };
  hintOne("Taking a screenshot", null, { glyph: "capture" });
  const card = ready.then(({ src }) => ({ image: { src, w: c.w, h: c.h }, demo: shot.demo, fresh: true }));
  try {
    const made = await one.capture(rect, card, copied);
    if (activity === oneActivity && !one.open) {
      copyNoticeOne(made.copied, 1400);
    }
    return made;
  } finally { capturing = false; }
}

const hintOne = hint(document.getElementById("hint-one"));
// What the hint offers when nothing is open: a screenshot, then the way to it.
function idleOne() {
  const newest = one.cards.at(-1);
  if (newest?.fresh && !newest.marks.length) {
    if (shots < 2 && one.stackOpen) return stackHint();
    if (shots < 2) return hintOne(coarse ? "Show your screenshots" : "Double-tap right Shift", () => one.showStack(), { keys: "shift2" });
    return hintOne(coarse ? "Draw on the newest one" : "Double-tap and hold right Shift", () => {
      one.showStack();
      one.annotate(one.cards.at(-1));
    }, { keys: "shift2" });
  }
  hintOne(shots ? "Take another screenshot" : "Take a screenshot", takeScreenshot, { glyph: "capture" });
}
idleOne();

// What "show me" draws when the hint is pressed in the annotator: a box and a note, by hand.
const drawings = new WeakMap();
async function drawForMe(stage, box, words) {
  if (!stage.open || !stage.framePic || stage.closing || drawings.has(stage)) return false;
  const drawing = { card: stage.open, marks: stage.marks, note: null };
  drawings.set(stage, drawing);
  const active = () => drawings.get(stage) === drawing && stage.open === drawing.card && stage.marks === drawing.marks
    && !stage.closing && !!stage.framePic && (!drawing.note || stage.typing === drawing.note);
  try {
    stage.endTyping();
    stage.snapshot();
    const mark = { type: "rect", who: "person", x: box.x, y: box.y, w: 0, h: 0 };
    stage.marks.push(mark);
    await tween(0.3, (t) => {
      if (!active()) return;
      const e = 1 - Math.pow(1 - t, 3);
      mark.w = box.w * e; mark.h = box.h * e;
      stage.redraw();
    });
    if (!active()) return false;
    stage.noteFor = mark;
    for (const ch of words) {
      if (!active()) return false;
      if (!drawing.note) { stage.startNote(mark, ch); drawing.note = stage.typing; continue; }
      drawing.note.text += ch;
      stage.redraw();
      await wait(0.045);
    }
    if (!active()) return false;
    stage.endTyping();
    stage.emit("mark");
    return true;
  } finally {
    if (drawings.get(stage) === drawing) drawings.delete(stage);
  }
}

let oneMarked = false;
const shown = () => one.cards[one.focused] || one.cards.at(-1);
const stackHint = () => hintOne(coarse ? "Tap a card to draw on it" : "Click a card to draw on it", () => one.annotate(shown()), { ring: () => shown()?.el });
const copyHint = () => hintOne(coarse ? "Copy it" : "Press Return to copy it", () => one.copy(), { keys: "ret", ring: () => one.toolbar.querySelector('[data-act="copy"]') });
function editorHintOne() {
  oneMarked = one.marks.length > 0;
  if (oneMarked) return copyHint();
  const card = one.open, frame = one.framePic;
  hintOne(coarse ? "Draw a box and a note" : "Drag to draw a box, then type a note", async () => {
    hintOne("Drawing a box and a note", null, { glyph: "draw" });
    const complete = await drawForMe(one, card.demo.box, card.demo.words);
    if (!complete && one.open === card && one.framePic === frame && !one.closing && !drawings.has(one)) editorHintOne();
  }, { glyph: "draw" });
}
function copyNoticeOne(ok, after) {
  hintOne(ok ? "Copied to your clipboard" : "Not copied to your clipboard", null, { glyph: ok ? "check" : "failed" });
  clearTimeout(one.idleTimer);
  one.idleTimer = setTimeout(() => { if (!one.open) idleOne(); }, after);
}
one.on((event, detail) => {
  if (["opening", "stack", "dismiss", "lone-gone"].includes(event)) oneActivity++;
  if (["opening", "closing", "stack", "dismiss", "lone-gone"].includes(event)) clearTimeout(one.idleTimer);
  if (["opening", "closing", "tool", "editing"].includes(event)) drawings.delete(one);
  if (event === "opening") hintOne("Opening your drawing", null);
  if (event === "closing") hintOne("Closing your drawing", null);
  if (event === "copying") { copyActivities.set(detail, ++oneActivity); hintOne("Copying to your clipboard", null); }
  if (event === "dismiss" || event === "lone-gone") idleOne();
  if (event === "stack") stackHint();
  if (event === "open") editorHintOne();
  if (event === "mark" && !oneMarked) {
    oneMarked = true;
    copyHint();
  }
  if (event === "copied") {
    if (copyActivities.get(detail) !== oneActivity || one.open || one.closing) return;
    copyNoticeOne(detail.ok, 2400);
  }
  if (event === "closed") { if (one.stackOpen) stackHint(); else idleOne(); }
});

// ---------------------------------------------------------------------------------------------
// Act two: Send to Claude Code, Claude's drawing back as a card, and Reply.


const CLAUDE_LOGO = '<img src="demo/claude.svg" alt="">';
const CHEVRON = '<svg width="9" height="9" viewBox="0 0 10 10"><path d="M2 3.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';

const two = new Stage(document.getElementById("stage-two"), {
  app: "Ghostty",
  alwaysOpen: true,
  offer(stage) {
    if (stage.open?.from) {
      return `<input type="text" placeholder="Add a message" aria-label="Message to Claude"><button type="button" class="send" data-act="send">Reply <kbd>↩</kbd></button>`;
    }
    return `<button type="button" data-act="copy">Copy <kbd>↩</kbd></button>
      <button type="button" class="target" aria-label="Send to postcard, in Claude Code">${CLAUDE_LOGO}postcard ${CHEVRON}</button>
      <input type="text" placeholder="Add a message" aria-label="Message to Claude">
      <button type="button" class="send" data-act="send">Send <kbd>⌘↩</kbd></button>`;
  },
  wireOffer(stage) {
    const send = stage.toolbar.querySelector('[data-act="send"]');
    const input = stage.toolbar.querySelector("input");
    send?.addEventListener("click", () => sendIt(input?.value));
    input?.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); sendIt(input.value); }
      if (e.key === "Escape") input.blur();
      e.stopPropagation();
    });
  },
  // Return copies, except on a card that names its session, where it replies; Cmd+Return sends.
  onFinish(stage, event) { stage.open?.from || event?.metaKey || event?.ctrlKey ? sendIt() : stage.copy(); },
});

const term = two.addWindow(`<div class="chrome"><i></i><i></i><i></i><span>postcard</span></div><div class="out"></div>`, { x: 26, y: 46, w: 440, h: 828 }, "term");
const out = term.querySelector(".out");
const SITE = { x: 488, y: 170, w: 728, h: 495 };
const site = browser(two, SITE, IMAGES.itin, "localhost:5391");
// Where a phone's camera looks while Claude answers: the session, then the page it changed.
const TERM_VIEW = { x: 16, y: 36, w: 470, h: 600 };
const SITE_VIEW = { x: SITE.x - 20, y: SITE.y - 20, w: SITE.w + 40, h: SITE.h + 40 };

const TERM_START = [
  ['<span class="t-claude">✻</span> Welcome to <b>Claude Code</b>\n\n<span class="t-dim">  cwd: ~/Code/postcard</span>', "welcome"],
  ['<span class="t-you">&gt; the day cards need more personality</span>', ""],
  ["", ""],
  ['<span class="t-claude">●</span> I gave each day an illustration and', ""],
  ["  a warmer palette. Take a look.", ""],
];
function termReset() {
  out.innerHTML = "";
  TERM_START.forEach(([h, cls]) => out.append(el("div", `line ${cls}`, h || " ")));
  out.append(el("div", "line prompt", '<span class="t-you">&gt;</span> <span class="cursor"></span>'));
  out.append(el("span", "warm", "⎿")); // laid out early, as the keycaps are
}
async function say(lines) {
  const prompt = out.querySelector(".prompt");
  for (const [html, pause] of lines) {
    const line = el("div", "line new", html || " ");
    out.insertBefore(line, prompt);
    requestAnimationFrame(() => line.classList.remove("new"));
    await wait(pause ?? 0.35);
  }
}

const hintTwo = hint(document.getElementById("hint-two"));
let round = 0; // 0 before Send, 1 after Claude's card arrived, 2 after Reply
let busy = false;

function setupTwo() {
  round = 0; busy = false;
  two.reset();
  termReset();
  site.show(IMAGES.itin);
  two.setCards([{ image: IMAGES.packing }, { image: IMAGES.stays }, { image: IMAGES.itin, marks: PERSON_MARKS }]);
  two.stackOpen = true;
  two.stackMotion.jump("backdrop", 1);
  two.cards.forEach((c) => c.motion.jump("x", 0));
  two.reframe(true);
  // The visitor has just drawn on the planner: the drawing is the newest card, ready to open.
  const mine = two.cards.at(-1);
  two.focus(two.cards.length - 1);
  hintTwo(coarse ? "Tap your drawing to open it" : "Click your drawing to open it", () => two.annotate(mine), { ring: () => mine.el });
}

async function sendIt(message = "") {
  if (busy || !two.open || two.closing || !two.framePic) return;
  busy = true;
  const card = two.open;
  const reply = !!card.from;
  const typed = message || two.toolbar.querySelector("input")?.value || "";
  two.toolbar.querySelector(".send")?.classList.add("sending");
  const closing = two.close({ notice: { kind: "sending", project: "postcard" } });
  hintTwo(reply ? "Claude builds the one you picked" : "Claude reads your drawing", null);
  await closing;
  const notice = card.el.querySelector(".notice");
  await wait(0.45);
  two.look(TERM_VIEW);
  notice?.setState({ kind: "sent", project: "postcard" });
  notice?.leave(1.4);
  const words = typed ? ` ${typed.replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch])}` : "";
  if (!reply) {
    await say([
      ["", 0],
      [`<span class="t-from">Drawing from Vignette</span>${words}`, 0.6],
      ['<span class="t-dim">  ⎿ Read image.png</span>', 0.8],
      ['<span class="t-claude">●</span> I numbered the days to match the map,', 0.1],
      ["  and made three versions of the day you", 0.1],
      ["  boxed, for you to pick from.", 0.6],
      ['<span class="t-dim">  ⎿ Edit itinerary.html</span>', 0.5],
    ]);
    two.look(SITE_VIEW);
    await wait(0.5);
    site.show(IMAGES.itinR1);
    await wait(1.1);
    two.look(TERM_VIEW);
    await say([['<span class="t-dim">  ⎿ Sent you a screenshot of all three</span>', 0.6]]);
    two.look(null);
    await wait(0.4);
    const claude = await two.insert({ image: IMAGES.variants, marks: CLAUDE_MARKS, from: "Claude" });
    round = 1; busy = false;
    hintTwo(coarse ? "Tap Claude’s card to open it" : "Click Claude’s card to open it", () => two.annotate(claude), { ring: () => claude.el });
  } else {
    await say([
      ["", 0],
      [`<span class="t-from">Drawing from Vignette</span>${words}`, 0.6],
      ['<span class="t-dim">  ⎿ Read image.png</span>', 0.8],
      ['<span class="t-claude">●</span> Building the version you picked.', 0.6],
      ['<span class="t-dim">  ⎿ Edit itinerary.html</span>', 0.5],
    ]);
    two.look(SITE_VIEW);
    await wait(0.5);
    site.show(IMAGES.itinFinal);
    await wait(0.4);
    await say([['<span class="t-claude">●</span> Done. It’s in the browser.', 0.2]]);
    round = 2; busy = false;
    hintTwo("Play it again", () => setupTwo(), { glyph: "replay" });
  }
}

function replyHint() {
  const card = two.open, frame = two.framePic;
  hintTwo(coarse ? "Pick one and reply" : "Box the one you like, then press Reply", async () => {
    hintTwo("Drawing a box and a note", null, { glyph: "draw" });
    if (await drawForMe(two, { x: 1218, y: 300, w: 560, h: 560 }, "this one")) sendIt();
    else if (two.open === card && two.framePic === frame && !two.closing && !drawings.has(two)) replyHint();
  }, { glyph: "draw" });
}
two.on((event, card) => {
  if (["opening", "closing", "tool", "editing"].includes(event)) drawings.delete(two);
  if (event === "opening") hintTwo(card.from ? "Opening Claude’s drawing" : "Opening your drawing", null);
  if (event === "closing" && !busy) hintTwo("Closing your drawing", null);
  if (event === "open" && card.from) replyHint();
  if (event === "closed" && !busy && round === 1) {
    const claude = two.cards.find((c) => c.from);
    hintTwo(coarse ? "Tap Claude’s card to open it" : "Click Claude’s card to open it", () => two.annotate(claude), { ring: () => claude.el });
  }
  if (event === "closed" && !busy && round === 0) {
    const mine = two.cards.at(-1);
    hintTwo(coarse ? "Tap your drawing to open it" : "Click your drawing to open it", () => two.annotate(mine), { ring: () => mine.el });
  }
  if (event === "open" && !card.from && round === 0) hintTwo("Send it to Claude", () => sendIt(), { keys: "cmdRet", ring: () => two.toolbar.querySelector(".send") });
});

setupTwo();

buildFan(document.getElementById("fan"));

// Safari applies :active to a pressed button only when the page listens for touches.
addEventListener("touchstart", () => {}, { passive: true });

// The trailer plays only while it is on screen, unless Reduce Motion stopped it. Coming back on
// screen resumes it only when leaving paused it, so a visitor's own pause holds.
const trailer = document.getElementById("trailer");
if (motion()) {
  let pausedOffscreen = false;
  new IntersectionObserver(([entry]) => {
    if (entry.isIntersecting) {
      if (pausedOffscreen) trailer.play().catch(() => {});
      pausedOffscreen = false;
    } else if (!trailer.paused) {
      pausedOffscreen = true;
      trailer.pause();
    }
  }).observe(trailer);
}
