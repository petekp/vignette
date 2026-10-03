import { Stage, wait, motion, el } from "./vignette.js";
import { IMAGES, PERSON_MARKS, CLAUDE_MARKS, buildFan } from "./cards.js";

Object.values(IMAGES).forEach((i) => { new Image().src = i.src; });

const coarse = matchMedia("(pointer: coarse)").matches;

// A hint is a note on the page under its stage, and a button that takes the step it describes.
function hint(button) {
  let action = null;
  button.addEventListener("click", () => action?.());
  return (text, act, { justify = "flex-end", arrow = "70%" } = {}) => {
    action = act;
    const row = button.parentElement;
    const apply = () => {
      button.textContent = text;
      row.style.setProperty("--hint-justify", justify);
      button.style.setProperty("--arrow-x", arrow);
      button.classList.remove("swap");
    };
    if (button.textContent === text) return apply();
    button.classList.add("swap");
    setTimeout(apply, 120 * motion());
  };
}

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
  { image: IMAGES.terminal, demo: { box: { x: 70, y: 560, w: 1150, h: 170 }, words: "fix this test" } },
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
let shots = 0;
const staysImage = new Image();
staysImage.src = IMAGES.stays.src;

// A capture puts its picture on the clipboard, as Vignette does when macOS saves the file.
function takeScreenshot() {
  const shot = SHOTS[shots++ % SHOTS.length], c = shot.crop;
  const canvas = document.createElement("canvas");
  canvas.width = c.w; canvas.height = c.h;
  canvas.getContext("2d").drawImage(staysImage, c.x, c.y, c.w, c.h, 0, 0, c.w, c.h);
  const src = canvas.toDataURL("image/jpeg", 0.9);
  try {
    const png = new Promise((r) => canvas.toBlob(r, "image/png"));
    navigator.clipboard.write([new ClipboardItem({ "image/png": png })]).catch(() => {});
  } catch {}
  const k = STAYS.w / IMAGES.stays.w;
  const rect = { x: STAYS.x + c.x * k, y: STAYS.y + 40 + c.y * k, w: c.w * k, h: c.h * k };
  hintOne("Copied as you take it", null, { justify: "center", arrow: "50%" });
  return one.capture(rect, { image: { src, w: c.w, h: c.h }, demo: shot.demo, fresh: true });
}

const hintOne = hint(document.getElementById("hint-one"));
// What the hint offers when nothing is open: a screenshot, then the way to it.
function idleOne() {
  const newest = one.cards.at(-1);
  if (newest?.fresh && !newest.marks.length) {
    if (shots < 2 && one.stackOpen) return stackHint();
    if (shots < 2) return hintOne(coarse ? "Tap here to show your screenshots" : "Double-tap right Shift", () => one.showStack());
    return hintOne(coarse ? "Tap here to draw on it" : "Double-tap and hold right Shift", () => {
      one.showStack();
      one.annotate(one.cards.at(-1));
    });
  }
  hintOne(shots ? "Take another screenshot" : "Take a screenshot", takeScreenshot, { justify: "center", arrow: "50%" });
}
idleOne();

// What "show me" draws when the hint is pressed in the annotator: a box and a note, by hand.
async function drawForMe(stage, box, words) {
  stage.snapshot();
  const mark = { type: "rect", who: "person", x: box.x, y: box.y, w: 0, h: 0 };
  stage.marks.push(mark);
  const steps = motion() ? 18 : 1;
  for (let i = 1; i <= steps; i++) {
    const t = i / steps, e = 1 - Math.pow(1 - t, 3);
    mark.w = box.w * e; mark.h = box.h * e;
    stage.redraw();
    await new Promise((r) => requestAnimationFrame(r));
  }
  stage.noteFor = mark;
  for (const ch of words) {
    if (!stage.typing) { stage.startNote(mark, ch); continue; }
    stage.typing.text += ch;
    stage.redraw();
    await wait(0.045);
  }
  stage.endTyping();
  stage.emit("mark");
}

let oneMarked = false;
const stackHint = () => hintOne(coarse ? "Tap a card to draw on it" : "Click a card to draw on it", () => one.annotate(one.cards[one.focused] || one.cards.at(-1)));
one.on((event, card) => {
  if (event === "captured") { clearTimeout(one.idleTimer); one.idleTimer = setTimeout(() => { if (!one.open) idleOne(); }, 1400 * motion()); }
  if (event === "dismiss" || event === "lone-gone") idleOne();
  if (event === "stack") stackHint();
  if (event === "open") {
    oneMarked = card.marks.length > 0;
    if (oneMarked) hintOne(coarse ? "Tap here to copy it" : "Press Return to copy it", () => one.copy(), { justify: "center", arrow: "50%" });
    else hintOne(coarse ? "Tap here to draw a box and a note" : "Drag to draw a box, then type a note", () => {
      drawForMe(one, card.demo.box, card.demo.words);
    }, { justify: "center", arrow: "50%" });
  }
  if (event === "mark" && !oneMarked) {
    oneMarked = true;
    hintOne(coarse ? "Tap here to copy it" : "Press Return to copy it", () => one.copy(), { justify: "center", arrow: "50%" });
  }
  if (event === "copied") {
    hintOne("Copied to your clipboard", idleOne);
    clearTimeout(one.idleTimer);
    one.idleTimer = setTimeout(() => { if (!one.open) idleOne(); }, 2400);
  }
  if (event === "closed" && !one.stackOpen && !card.marks.length) idleOne();
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
  onFinish(stage) { stage.open?.from ? sendIt() : stage.copy(); },
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
const CENTER = { justify: "center", arrow: "50%" };
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
  hintTwo(coarse ? "Tap your drawing to open it" : "Click your drawing to open it", () => two.annotate(mine));
}

async function sendIt(message = "") {
  if (busy || !two.open) return;
  busy = true;
  const card = two.open;
  const reply = !!card.from;
  const typed = message || two.toolbar.querySelector("input")?.value || "";
  two.toolbar.querySelector(".send")?.classList.add("sending");
  const closing = two.close({ notice: { kind: "sending", project: "postcard" } });
  hintTwo(reply ? "Claude builds the one you picked" : "Claude reads your drawing", null, { justify: "flex-start", arrow: "18%" });
  await closing;
  const notice = card.el.querySelector(".notice");
  await wait(0.45);
  two.look(TERM_VIEW);
  notice?.setState({ kind: "sent", project: "postcard" });
  notice?.leave(1.4);
  const words = typed ? ` ${typed}` : "";
  if (!reply) {
    await say([
      ["", 0],
      [`<span class="t-from">Drawing from Vignette</span>${words}`, 0.6],
      ['<span class="t-dim">  ⎿ Read image.png</span>', 0.8],
      ['<span class="t-claude">●</span> I numbered the days to match the map,', 0.1],
      ["  and made three versions of the highlight", 0.1],
      ["  day for you to pick from.", 0.6],
      ['<span class="t-dim">  ⎿ Edit itinerary.html</span>', 0.5],
    ]);
    two.look(SITE_VIEW);
    await wait(0.5);
    site.show(IMAGES.itinR1);
    await wait(1.1);
    two.look(TERM_VIEW);
    await say([['<span class="t-dim">  ⎿ Sent you a screenshot, marked A, B and C</span>', 0.6]]);
    two.look(null);
    await wait(0.4);
    const claude = await two.insert({ image: IMAGES.variants, marks: CLAUDE_MARKS, from: "Claude" });
    round = 1; busy = false;
    hintTwo(coarse ? "Tap Claude’s card to open it" : "Click Claude’s card to open it", () => two.annotate(claude));
  } else {
    await say([
      ["", 0],
      [`<span class="t-from">Reply from Vignette</span>${words}`, 0.6],
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
    hintTwo("Play it again", () => setupTwo(), { justify: "flex-start", arrow: "30%" });
  }
}

two.on((event, card) => {
  if (event === "open" && card.from) {
    hintTwo(coarse ? "Tap here to pick one and reply" : "Box the one you like, then press Reply", async () => {
      await drawForMe(two, { x: 1218, y: 300, w: 560, h: 560 }, "this one");
      sendIt();
    }, CENTER);
  }
  if (event === "closed" && !busy && round === 1) {
    const claude = two.cards.find((c) => c.from);
    hintTwo(coarse ? "Tap Claude’s card to open it" : "Click Claude’s card to open it", () => two.annotate(claude));
  }
  if (event === "closed" && !busy && round === 0) {
    const mine = two.cards.at(-1);
    hintTwo(coarse ? "Tap your drawing to open it" : "Click your drawing to open it", () => two.annotate(mine));
  }
  if (event === "open" && !card.from && round === 0) hintTwo("Press Send", () => sendIt(), CENTER);
});

setupTwo();

buildFan(document.getElementById("fan"));
