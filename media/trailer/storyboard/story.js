// The trailer's shots: the film and the feature loops. Each shot's anim(t) gives the screen and
// the caption at t seconds into the shot. The storyboard shows each shot at its `still` time,
// and the animatic plays every shot through. scene.js draws them.

// ---------------------------------------------------------------------------------------------
// Captions

const C_CAPTURE = { text: 'Take a screenshot', keys: ['⌘', '⇧', '4'] };
const C_CLICK = { text: 'Click to draw on it' };
const C_ASK = { text: 'Explain what you want, visually' };
const C_SEND = { text: 'Send it over', keys: ['⌘', '↩'] };
const C_ANSWER = { text: 'Your agent can show you things, too' };
const C_POINT = { text: 'Mark it up and send it back', keys: ['↩'] };
const C_BUILT = { text: 'Claude builds it' };

// A caption shown since t0: it fades in, and `lit` names the key caps pressed now.
const cap = (c, t, t0, lit = []) => ({ ...c, lit, age: t - t0 });
// The key caps light for 0.45 s from a press at `at`.
const litAt = (t, at, idx = [0, 1, 2]) => (t >= at && t < at + 0.45 ? idx : []);
// A click ring for 0.4 s from a click at `at`.
const ring = (t, at, p) => (t >= at && t < at + 0.4 ? [[p[0], p[1], t - at]] : []);

// ---------------------------------------------------------------------------------------------
// Marks, in image points (904 x 565).

const M_ASK_BOX = { t: 'rect', x: 598, y: 227, w: 287, h: 288 };
const M_ASK_NOTE = { t: 'note', x: 598, y: 525, text: 'make this pop, options?' };
const M_ASK = [M_ASK_BOX, M_ASK_NOTE];
// An arrow from the map's second stop to the Chianti day: it relates two parts of the page,
// which a comment pinned to one element cannot. The app puts its note beyond the tail.
const M_LINK_ARROW = { t: 'arrow', x1: 664, y1: 161, x2: 424, y2: 334 };
const M_LINK_NOTE = { t: 'note', x: 675, y: 146, text: 'number the days' };
const M_DRAW = [M_LINK_ARROW, M_LINK_NOTE, M_ASK_BOX, M_ASK_NOTE];
// Claude names a colour for its marks, so they read as its own next to the person's red ones.
const AGENT_COLOR = 'violet';
const CLAUDE_OPTS = [
  { t: 'note', x: 157, y: 100, text: 'A', agent: 1, size: 22 }, { t: 'note', x: 446, y: 100, text: 'B', agent: 1, size: 22 },
  { t: 'note', x: 735, y: 100, text: 'C', agent: 1, size: 22 }, { t: 'note', x: 392, y: 440, text: 'Which one?', agent: 1, size: 20 },
].map(m => ({ ...m, color: AGENT_COLOR }));
// The version you pick is C, on the right, so its note hangs below it; the flag is B's, beside it.
const M_PICK_BOX = { t: 'rect', x: 598, y: 138, w: 287, h: 288 };
const M_PICK_NOTE = { t: 'note', x: 598, y: 436, text: 'this one, with that flag' };
const M_PICK_ARROW = { t: 'arrow', x1: 410, y1: 147, x2: 640, y2: 178 };
const PICK = [M_PICK_BOX, M_PICK_NOTE, M_PICK_ARROW];

// A box being dragged out from its top left, an arrow from its tail, a note being typed.
const growRect = (m, p) => ({ ...m, w: m.w * p, h: m.h * p });
const growArrow = (m, p) => ({ ...m, x2: lerp(m.x1, m.x2, p), y2: lerp(m.y1, m.y2, p) });
const typing = (m, t, t0) => ({ ...m, text: typed(m.text, t, t0) });

// ---------------------------------------------------------------------------------------------
// Claude Code's transcript in the postcard terminal. [text, class]

const T_START = [
  ['> Walk me through how the itinerary page is built.', 'u'], ['', ''],
  ['● Read 2 files', 'g'], ['', ''],
  ['● The itinerary is index.html. It is plain HTML', ''],
  ['  with no build step, and styles.css styles it and', ''],
  ['  the other two pages, Stays and Packing.', ''], ['', ''],
  ['  Top bar', ''],
  ['  - .top holds the Postcard stamp, the nav links', ''],
  ['    and the people on the trip, with Share.', ''], ['', ''],
  ['  Trip summary', ''],
  ['  - .hero is a two-column grid: the title and the', ''],
  ['    facts on the left, the route map on the right.', ''],
  ['  - The facts show nights, cost and plans. The', ''],
  ['    booked count is a status pill (.status).', ''], ['', ''],
  ['  Days', ''],
  ['  - Three cards in a three-column grid (.days).', ''],
  ['  - Each card (.day) has a picture (.art), the', ''],
  ['    date, a title with its status pill, the plans', ''],
  ['    for the day and a Details button.', ''],
  ['  - Oct 14, Val d’Orcia at sunrise, is the', ''],
  ['    trip’s highlight.', ''], ['', ''],
  ['  The map and the pictures are inline SVG.', ''],
  ['  Colours come from the variables at the top of', ''],
  ['  styles.css: --page, --panel, --ink, --accent.', ''], ['', ''],
  ['✻ Worked for 12s', 'g'],
];
const T_ARRIVED = [...T_START, ['', ''], ['● Monitor event: "Drawing from Vignette"', '']];
const T_SENT = [...T_ARRIVED, ['', ''], ['  Read 1 file', 'g']];
const T_ASKED = [...T_SENT, ['', ''],
  ['● Update(index.html)', ''], ['● Update(styles.css)', ''],
  ['● Write(variants.html)', ''], ['● Bash(./screenshot variants.png variants.html)', ''],
  ['● Bash(./push variants.png variants.json)', ''], ['', ''],
  ['● Numbered the days to match the map.', ''], ['', ''],
  ['  You asked for options on the Oct 14 card.', ''],
  ['  Three versions are in Vignette. Which one?', ''],
];
const T_REPLY_ARRIVED = [...T_ASKED, ['', ''], ['● Monitor event: "Drawing from Vignette"', '']];
const T_REPLIED = [...T_REPLY_ARRIVED, ['', ''], ['● Update(index.html)', ''], ['● Update(styles.css)', ''], ['', ''],
  ['● The Oct 14 card is now C, with the Highlight', ''], ['  flag from B.', ''],
];

// ---------------------------------------------------------------------------------------------
// The film

const REST = [1180, 880];
const OPTIONS = { img: 'variants', marks: CLAUDE_OPTS, agent: 1 };

const FILM = [
  { id: 'F1', title: 'Capture', dur: 4.2, cam: 'WIDE', still: 2.6,
    move: 'Holds.',
    action: 'Pointer glides to the viewport’s top left <code>[592, 141]</code>. ⌘⇧4 at 1.5 s. Drag to <code>[1496, 706]</code> over 1.2 s. The card slides in bottom right 0.4 s after the release.',
    screen: 'Claude Code (postcard) on the left, with an earlier answer about the app. Postcard’s itinerary on the right: a week in Tuscany, a route map, three day cards. The Oct 14 day is marked Highlight in its date line and looks like the other two.',
    events: 'open, capture.press, capture.release, thumb.shown',
    annot: { path: [[1180, 880], [700, 300], [598, 146]] },
    anim: t => {
      const s = { page: 'itin' };
      let p = glide(REST, [592, 141], t, 0.4, 0.8), kind = 'arrow';
      if (t >= 1.5 && t < 3.1) kind = 'cross';
      if (t >= 1.9 && t < 3.1) {
        const q = ease(t, 1.9, 1.2);
        p = [lerp(592, 1496, q), lerp(141, 706, q)];
        s.select = [592, 141, p[0] - 592, p[1] - 141];
      }
      if (t >= 3.1) p = [1496, 706];
      if (t >= 3.5) { s.thumb = { img: 'itin' }; s.thumbDx = (1 - spring(t, 3.5, 0.5)) * 170; }
      s.pointer = p; s.pointerKind = kind;
      return { scene: s, caption: cap(C_CAPTURE, t, -1, litAt(t, 1.5)) };
    } },

  { id: 'F2', title: 'Ask', dur: 9.8, cam: 'EDITOR', from: 'WIDE', camMove: [2.0, 2.0], still: 9.4,
    move: 'Holds WIDE through the click. At the landing, WIDE → EDITOR over 2.0 s. The drawing starts once it settles.',
    action: 'Pointer to the card, click at 0.9 s. The card flies into the editor and the desktop dims. A at 3.0 s picks the arrow. At 4.0 s, drag from the map’s stop 2 into the Chianti day, image <code>[664, 161] → [424, 334]</code>, and type “number the days”. At 5.95 s click the empty space beside the title to end the note, and R at 6.15 s picks the box. At 6.7 s, drag a box around the Val d’Orcia card, <code>[598, 227] → [885, 515]</code>, and type “make this pop, options?”. Typing at 16 characters a second.',
    screen: 'Two marks. The first is an arrow from a stop on the map to the day it belongs to, with its note beside the stop: it relates two parts of the page, which a comment pinned to one element cannot. The second asks for options, its note under the box.',
    events: 'thumb.click, editor.landed, link.drawn, link.noted, ask.press, ask.noted',
    anim: t => {
      const s = { page: 'itin' };
      let p = glide([1496, 706], [1426, 908], t, 0.1, 0.6);
      if (t < 0.9) s.thumb = { img: 'itin' };
      s.clicks = ring(t, 0.9, [1426, 908]);
      if (t >= 0.9 && t < 1.9) { const q = spring(t, 0.9, 1.0); s.dim = q; s.flights = [{ img: 'itin', rect: flight(THUMB, F0, q) }]; }
      if (t >= 1.9) {
        const marks = [];
        if (t >= 4.0) marks.push(growArrow(M_LINK_ARROW, ease(t, 4.0, 0.5)));
        if (t >= 4.7) marks.push(typing(M_LINK_NOTE, t, 4.7));
        if (t >= 6.7) marks.push(growRect(M_ASK_BOX, ease(t, 6.7, 0.6)));
        if (t >= 7.4) marks.push(typing(M_ASK_NOTE, t, 7.4));
        s.editor = { img: 'itin', marks, toolbar: { offer: 'send', tool: t >= 3.0 && t < 6.15 ? 2 : 1 } };
        p = glide([1426, 908], toScreen(664, 161), t, 3.1, 0.6);
        if (t >= 4.0) p = glide(toScreen(664, 161), toScreen(424, 334), t, 4.0, 0.5);
        if (t >= 5.7) p = glide(toScreen(424, 334), toScreen(470, 140), t, 5.7, 0.25);
        if (t >= 6.2) p = glide(toScreen(470, 140), toScreen(598, 227), t, 6.2, 0.4);
        if (t >= 6.7) p = glide(toScreen(598, 227), toScreen(885, 515), t, 6.7, 0.6);
        s.clicks = ring(t, 5.95, toScreen(470, 140));
      }
      s.pointer = p;
      return { scene: s, caption: t < 1.9 ? cap(C_CLICK, t, 0) : cap(C_ASK, t, 1.9) };
    } },

  { id: 'F3', title: 'Send', dur: 3.4, cam: 'WIDE', from: 'EDITOR', camMove: [0.6, 1.6], still: 2.8,
    move: 'At the press, EDITOR → WIDE over 1.6 s.',
    action: '⌘↩ at 0.5 s, with no message: the note says it. The editor closes and the card flies home to the corner.',
    screen: 'The card in the corner with “✳ postcard” on it. In Claude Code, the drawing arrives as a monitor event.',
    events: 'send.press, send.closed, claude.working',
    outT: 'Dissolve 0.5 s over Claude’s working time.',
    anim: t => {
      const s = { page: 'itin', term: { lines: t < 1.7 ? T_START : t < 2.4 ? T_ARRIVED : T_SENT }, pointer: toScreen(885, 515) };
      if (t < 0.6) s.editor = { img: 'itin', marks: M_DRAW, toolbar: { offer: 'send' } };
      else if (t < 1.5) { const q = spring(t, 0.6, 0.9); s.dim = 1 - q; s.flights = [{ img: 'itin', marks: M_DRAW, rect: flight(F0, THUMB, q) }]; }
      else s.thumb = { img: 'itin', marks: M_DRAW, sent: 'postcard' };
      return { scene: s, caption: cap(C_SEND, t, 0, litAt(t, 0.5, [0, 1])) };
    } },

  { id: 'F4', title: 'The answer', dur: 2.8, cam: 'WIDE', dissolveIn: 0.5, still: 2.4,
    move: 'Holds.',
    action: 'Nothing. At 0.7 s Claude’s card slides in. Hold 1.6 s after it lands. This is the moment the film is built around: give it room.',
    screen: 'Each day has a gold numbered stop now, like the map’s. Claude’s last lines: “Numbered the days to match the map. You asked for options on the Oct 14 card. Three versions are in Vignette. Which one?” The card, with a “From Claude” tab, bottom right.',
    events: 'push, card.shown',
    anim: t => {
      const s = { page: 'itinR1', term: { lines: T_ASKED }, pointer: REST };
      if (t >= 0.7) { s.thumb = OPTIONS; s.thumbDx = (1 - spring(t, 0.7, 0.5)) * 170; }
      return { scene: s, caption: cap(C_ANSWER, t, 0) };
    } },

  { id: 'F5', title: 'Look', dur: 3.6, cam: 'EDITOR', from: 'WIDE', camMove: [1.4, 1.8], still: 3.4,
    move: 'WIDE → EDITOR from the landing, over 1.8 s.',
    action: 'Pointer to the card, click at 0.7 s. It flies into the editor.',
    screen: 'Three versions of the Oct 14 card: A tinted with the sunrise, with a terracotta title and button; B with a terracotta outline and a “Highlight” flag; C with the sunrise filling the whole card. Claude’s labels in violet SF Mono. The toolbar offers Reply. <span class="approx">Approximate: Claude designs the three.</span>',
    events: 'options.click, options.landed',
    anim: t => {
      const s = { page: 'itinR1', term: { lines: T_ASKED } };
      let p = glide(REST, [1426, 908], t, 0, 0.5);
      if (t < 0.7) s.thumb = OPTIONS;
      s.clicks = ring(t, 0.7, [1426, 908]);
      if (t >= 0.7 && t < 1.6) { const q = spring(t, 0.7, 0.9); s.dim = q; s.flights = [{ img: 'variants', marks: CLAUDE_OPTS, rect: flight(THUMB, F0, q) }]; }
      if (t >= 1.6) s.editor = { img: 'variants', marks: CLAUDE_OPTS, toolbar: { offer: 'reply' } };
      s.pointer = p;
      return { scene: s, caption: cap(C_ANSWER, t, -1) };
    } },

  { id: 'F6', title: 'Point', dur: 5.4, cam: 'EDITOR', still: 5.0,
    move: 'Holds.',
    action: 'Box C, image <code>[598, 138] → [885, 426]</code>. Type “this one, with that flag”, which hangs below the box. At 3.0 s click an empty spot to end the note, press A for the arrow tool, and drag from B’s flag into C, <code>[410, 147] → [640, 178]</code>.',
    screen: 'Your red box, note and arrow in SF Pro Rounded beside Claude’s violet mono labels. The arrow says what words would have to describe.',
    events: 'pick.press, pick.noted, arrow.drawn',
    anim: t => {
      const s = { page: 'itinR1', term: { lines: T_ASKED } };
      const marks = [...CLAUDE_OPTS];
      let p = glide([1426, 908], toScreen(598, 138), t, 0, 0.3);
      if (t >= 0.3) { marks.push(growRect(M_PICK_BOX, ease(t, 0.3, 0.6))); p = glide(toScreen(598, 138), toScreen(885, 426), t, 0.3, 0.6); }
      if (t >= 1.1) marks.push(typing(M_PICK_NOTE, t, 1.1));
      if (t >= 2.8) p = glide(toScreen(885, 426), toScreen(80, 500), t, 2.8, 0.2);
      if (t >= 3.3) p = glide(toScreen(80, 500), toScreen(410, 147), t, 3.3, 0.4);
      if (t >= 3.8) { marks.push(growArrow(M_PICK_ARROW, ease(t, 3.8, 0.6))); p = glide(toScreen(410, 147), toScreen(640, 178), t, 3.8, 0.6); }
      s.clicks = ring(t, 3.0, toScreen(80, 500));
      s.editor = { img: 'variants', marks, toolbar: { offer: 'reply', tool: t >= 3.2 ? 2 : 1 } };
      s.pointer = p;
      return { scene: s, caption: cap(C_POINT, t, 0) };
    } },

  { id: 'F7', title: 'Reply', dur: 2.6, cam: 'WIDE', from: 'EDITOR', camMove: [0.3, 1.6], still: 2.2,
    move: 'At the press, EDITOR → WIDE over 1.6 s.',
    action: '↩ at 0.2 s. The editor closes and the card goes home.',
    screen: 'The card with its reply mark, and the drawing arriving in Claude Code.',
    events: 'reply.press, reply.closed, claude.working',
    outT: 'Dissolve 0.5 s over Claude’s working time.',
    anim: t => {
      const all = [...CLAUDE_OPTS, ...PICK];
      const s = { page: 'itinR1', term: { lines: t < 1.4 ? T_ASKED : T_REPLY_ARRIVED }, pointer: toScreen(640, 178) };
      if (t < 0.3) s.editor = { img: 'variants', marks: all, toolbar: { offer: 'reply', tool: 2 } };
      else if (t < 1.2) { const q = spring(t, 0.3, 0.9); s.dim = 1 - q; s.flights = [{ img: 'variants', marks: all, rect: flight(F0, THUMB, q) }]; }
      else s.thumb = { img: 'variants', marks: all, agent: 1, sent: 'replied' };
      return { scene: s, caption: cap(C_POINT, t, -1, litAt(t, 0.2, [0])) };
    } },

  { id: 'F8', title: 'Built', dur: 3.6, cam: 'RESULT', from: 'WIDE', camMove: [0.3, 1.8], dissolveIn: 0.5, still: 3.3,
    move: 'WIDE → RESULT over 1.8 s, done before the page changes.',
    action: 'Nothing. At 2.2 s the page reloads by itself when Claude saves.',
    screen: 'The Oct 14 card is C: the sunrise fills it, with B’s Highlight flag and a light Details button. The day numbers Claude added in its first turn are in frame too. <span class="approx">Approximate: Claude designs both.</span>',
    events: 'page.changed',
    anim: t => {
      const s = { page: 'itinR1', term: { lines: T_REPLIED } };
      if (t >= 2.2) { s.pageNext = 'itinFinal'; s.pageMix = clamp01((t - 2.2) / 0.15); }
      return { scene: s, caption: cap(C_BUILT, t, 0) };
    } },
];

const END = { id: 'End', title: 'End card', dur: OUTRO.length, end: 1, dissolveIn: 0.8, still: 3.2, leaves: 1,
  move: 'None. The film eases back, softens and fades into the card over 0.8 s.',
  action: 'At 0.5 s the app icon rises into place. At 1.0 s the wordmark writes itself on, left to right, over 1 s. The tagline at 1.9 s, the line under it at 2.15 s. From 4.0 s the parts leave, the lines first and the icon last. The last 0.8 s dissolve into the film’s first frame.',
  screen: 'Near black, warmed behind the icon. The Vignette icon, the handwritten wordmark, “The modern Mac screenshot tool for the agentic age.”, and “Free for macOS 14 or later · vignette.pete.design”.' };

// ---------------------------------------------------------------------------------------------
// The feature loops. Each is one shot that loops, with a short dissolve back to its start.

const ITIN_A = { img: 'itin', marks: M_ASK };
const STAYS_MARKS = [{ t: 'rect', x: 578, y: 198, w: 90, h: 40 }, { t: 'note', x: 678, y: 198, text: 'check-in 3pm?' }];
const STAYS_B = { img: 'stays', marks: STAYS_MARKS };
const EARLIER = [{ img: 'map' }, { img: 'chianti' }, { img: 'packing', badge: '0:08' }];
const Z_MARKS = [{ t: 'rect', x: 718, y: 158, w: 28, h: 28 }, { t: 'note', x: 754, y: 157, text: 'lunch here?', size: 14 }];
const FZ = [16, 46, 1480, 826], VZ = [360, 20, 544, 304];
// Where an image point lands on screen in a zoomed editor.
const zoomed = (x, y, F, V) => [F[0] + (x - V[0]) * F[2] / V[2], F[1] + (y - V[1]) * F[3] / V[3]];

const LOOPS = [
  { id: 'zoom', title: 'Zoom', loop: 0.4, shots: [
    { id: 'L-zoom', title: 'Zoom in on small details', dur: 6.6, cam: 'WIDE', still: 3.8,
      move: 'Holds WIDE: the zoomed frame fills the screen.',
      action: 'The editor is open on the itinerary. Pointer to Siena on the map. ⌘ + five scroll notches at 0.9 s. Box it and type “lunch here?”. ⌘0 at 4.6 s springs back to the fit.',
      screen: 'The frame grows to the edges of the screen, then the picture magnifies to about 2×, the stop staying under the pointer. <span class="approx">Approximate: the app sets the frame.</span>',
      events: 'zoom.press, zoom.noted, fit.done',
      anim: t => {
        const z = t < 4.6 ? spring(t, 0.9, 0.8) : 1 - spring(t, 4.6, 0.8);
        const F = lerpR(F0, FZ, z), V = lerpR([0, 0, IW, IH], VZ, z);
        const marks = [];
        if (t >= 2.0) marks.push(growRect(Z_MARKS[0], ease(t, 2.0, 0.4)));
        if (t >= 2.6) marks.push(typing(Z_MARKS[1], t, 2.6));
        let p = glide(REST, toScreen(732, 172), t, 0, 0.6);
        if (t >= 0.6) p = zoomed(732, 172, F, V);
        if (t >= 2.0) p = zoomed(lerp(718, 746, ease(t, 2.0, 0.4)), lerp(158, 186, ease(t, 2.0, 0.4)), F, V);
        return { scene: { page: 'itin', editor: { img: 'itin', marks, frame: F, view: V, toolbar: { offer: 'send' } }, pointer: p },
          caption: { text: 'Zoom in for the small stuff', keys: ['⌘', 'scroll'], lit: (t >= 0.9 && t < 1.7) || (t >= 4.6 && t < 5.05) ? [0, 1] : [] } };
      } } ] },

  { id: 'recent', title: 'Recent screenshots', loop: 0.4, shots: [
    { id: 'L-recent', title: 'Your recent screenshots, recordings included', dur: 5.4, cam: 'STACK5', still: 3.6,
      move: 'Holds.',
      action: '⇧⇧ at 0.5 s: the stack slides in with the newest focused. ↑ at 2.2 s and 2.8 s walks up to the recording. The stack is dismissed at 4.5 s.',
      screen: 'Five cards: a crop of the map, a crop of the Chianti card, an 8-second recording of the packing list with its “0:08” badge, the itinerary and Stays.',
      events: 'history, walk, dismiss',
      anim: t => {
        const cards = [...EARLIER, { img: 'itin' }, { img: 'stays' }];
        const inP = spring(t, 0.5, 0.5), outP = t >= 4.5 ? ease(t, 4.5, 0.4) : 0;
        const show = t >= 0.5 ? inP * (1 - outP) : 0;
        const focus = t < 2.2 ? 4 : t < 2.8 ? 3 : 2;
        const s = { page: 'itin', pointer: REST };
        if (show > 0) s.stack = { cards, focus, dx: (1 - show) * 320, opacity: show };
        const c1 = { text: 'Double-tap right Shift for your recent screenshots', keys: ['⇧', '⇧'] };
        return { scene: s, caption: t < 2.2 ? { ...c1, lit: litAt(t, 0.5, [0, 1]) } : cap({ text: 'Recordings too' }, t, 2.2) };
      } } ] },

  { id: 'hold', title: 'Hold to draw', loop: 0.4, shots: [
    { id: 'L-hold', title: 'Double tap and hold to draw on the newest', dur: 4.4, cam: 'WIDE', still: 2.8,
      move: 'Holds.',
      action: '⇧⇧ at 0.5 s with the second press held. The stack comes up, and 0.4 s into the hold the newest card lifts into the editor.',
      screen: 'The editor with the itinerary, and the stack narrowed on the right. Loops back after a hold.',
      events: 'hold.press, editor.landed',
      anim: t => {
        const cards = [...EARLIER, { img: 'stays' }, { img: 'itin' }];
        const s = { page: 'itin', pointer: REST };
        if (t >= 0.5 && t < 0.9) s.stack = { cards, focus: 4, dx: (1 - spring(t, 0.5, 0.4)) * 320 };
        if (t >= 0.9 && t < 1.8) {
          const q = spring(t, 0.9, 0.9);
          s.stack = { cards: cards.slice(0, 4).map((c, i) => ({ ...c, r: lerpR(slot(4 - i), narrowSlot(3 - i), q) })) };
          s.dim = q; s.flights = [{ img: 'itin', rect: flight(slot(0), F0, q) }];
        }
        if (t >= 1.8) s.editor = { img: 'itin', stackNarrow: cards.slice(0, 4), toolbar: { offer: 'send' } };
        const c = { text: 'Double-tap and hold to draw on the latest', keys: ['⇧', '⇧'] };
        return { scene: s, caption: { ...c, lit: t >= 0.5 && t < 1.2 ? [0, 1] : [] } };
      } } ] },

  { id: 'stitch', title: 'Stitch', loop: 0.4, shots: [
    { id: 'L-stitch', title: 'Select several and stitch them into one', dur: 6.0, cam: 'STACK5', still: 2.6,
      move: 'Holds.',
      action: 'The stack is up with two drawings on top. ↑, Space: the itinerary is 1. ↓, Space: Stays is 2. ⌘S at 3.0 s: both fly into one slot while the stitched image fades in under them.',
      screen: 'Blue rings, numbered circles, and the strip: Copy, Draw, Stitch ⌘S, Delete. Then one stitched card, badged 1 and 2. <span class="approx">Approximate: the strip’s look.</span>',
      events: 'select.done, stitch.press, stitch.shown',
      anim: t => {
        const s = { page: 'stays', pointer: REST };
        if (t < 3.0) {
          const focus = t < 0.6 ? 4 : t < 1.4 ? 3 : 4, selected = t < 1.0 ? [] : t < 1.8 ? [3] : [3, 4];
          s.stack = { cards: [...EARLIER, ITIN_A, STAYS_B], focus, selected, strip: selected.length ? 700 : 0 };
        } else {
          const q = spring(t, 3.0, 0.8);
          const early = EARLIER.map((c, i) => ({ ...c, r: lerpR(slot(4 - i), slot(3 - i), q) }));
          const stitched = { stitch: [['itin', M_ASK], ['stays', STAYS_MARKS]], opacity: q };
          s.stack = { cards: [...early, stitched], focus: 3 };
          if (q < 0.98) s.flights = [
            { img: 'itin', marks: M_ASK, rect: flight(slot(1), slot(0), q), opacity: 1 - q },
            { img: 'stays', marks: STAYS_MARKS, rect: flight(slot(0), slot(0), q), opacity: 1 - q }];
        }
        return { scene: s, caption: { text: 'Stitch a few into one image', keys: ['⌘', 'S'], lit: litAt(t, 3.0, [0, 1]) } };
      } } ] },

  { id: 'session', title: 'Any session', loop: 0.4, shots: [
    { id: 'L-session', title: 'Send to any Claude Code session', dur: 5.0, cam: 'TOOLBAR', still: 2.0,
      move: 'Holds.',
      action: 'The editor is open with a drawing. Click the target at 1.0 s. The menu lists both sessions. Pick postcard-api at 2.4 s.',
      screen: '“Send to”: postcard, subtitle “Itinerary page”, checked; postcard-api, subtitle “Booking sync”. Then the target reads “✳ postcard-api”. <span class="approx">Approximate: the menu’s position is macOS’s.</span>',
      events: 'target.click, menu.pick',
      anim: t => {
        let p = glide([900, 940], [712, 900], t, 0.2, 0.6);
        if (t >= 1.5) p = glide([712, 900], [720, 816], t, 1.5, 0.5);
        const tb = { offer: 'send', target: t < 2.4 ? 'postcard' : 'postcard-api', menu: t >= 1.0 && t < 2.4, menuHot: t < 1.9 ? 0 : 1 };
        const clicksL = [...ring(t, 1.0, [712, 900]), ...ring(t, 2.4, [720, 816])];
        return { scene: { page: 'itin', editor: { img: 'itin', marks: M_ASK, toolbar: tb }, pointer: p, clicks: clicksL },
          caption: { text: 'Pick which Claude session gets it' } };
      } } ] },

  { id: 'paste', title: 'Paste', loop: 0.4, shots: [
    { id: 'L-paste', title: 'It is on your clipboard at once', dur: 5.4, cam: 'WIDE', still: 4.2,
      move: 'Holds.',
      action: '⌘⇧4 and drag over the Oct 14 card. The card lands. Click Claude Code’s prompt and press ⌃V at 3.6 s.',
      screen: 'Claude Code’s footer offers the image at once, and the prompt shows “[Image #1]”.',
      events: 'capture.release, prompt.click, paste',
      anim: t => {
        const s = { page: 'itin' };
        let p = glide(REST, [1190, 368], t, 0, 0.5), kind = t >= 0.5 && t < 1.6 ? 'cross' : 'arrow';
        if (t >= 0.8 && t < 1.6) { const q = ease(t, 0.8, 0.8); p = [lerp(1190, 1478, q), lerp(368, 656, q)]; s.select = [1190, 368, p[0] - 1190, p[1] - 368]; }
        if (t >= 1.6) p = [1478, 656];
        if (t >= 1.8) { s.thumb = { img: 'itin' }; s.thumbDx = (1 - spring(t, 1.8, 0.5)) * 170; }
        if (t >= 2.4) p = glide([1478, 656], [220, 905], t, 2.4, 0.7);
        s.clicks = ring(t, 3.2, [220, 905]);
        s.term = { hint: t >= 1.8 && t < 3.6, prompt: t >= 3.6 ? '[Image #1] ' : '' };
        s.pointer = p; s.pointerKind = kind;
        const c = t < 2.4 ? { ...C_CAPTURE, lit: litAt(t, 0.5) } : cap({ text: 'Already on your clipboard', keys: ['⌃', 'V'] }, t, 2.4, litAt(t, 3.6, [0, 1]));
        return { scene: s, caption: c };
      } } ] },
];

const REELS = [
  { id: 'film', title: 'The film, with its end card (loops)', shots: [...FILM, END], loop: 0.8 },
  ...LOOPS.map(l => ({ ...l, title: 'Loop: ' + l.title })),
];

// ---------------------------------------------------------------------------------------------
// Before recording

const VERIFY = [
  '<b>The options flow.</b> Given Postcard’s CLAUDE.md and the note “make this pop, options?”, Claude writes <code>variants.html</code>, renders it and pushes it. On the reply it builds C with B’s flag. Check that the permission rules allow writing <code>variants.html</code>.',
  '<b>Claude’s colour.</b> Claude’s marks come in violet because it names the colour. Your marks on its image get theirs from the colour pass: check it doesn’t pick violet there too.',
  '<b>A drag while typing.</b> Dragging out a new box while a note is being typed ends the note and draws the box, with no click in between.',
  '<b>Send with no message.</b> ⌘↩ with an empty message field sends, and Claude acts on the note alone.',
  '<b>Clicking the corner card</b> opens it in the editor, and after Send it comes back to the corner with “✳ postcard” on it.',
  '<b>The arrows.</b> A before any mark picks the arrow tool. A character typed right after an arrow starts its note beyond the tail, beside the map stop, on one line. After a note, a click on empty space ends it, and R or A then picks a tool instead of typing a letter.',
  '<b>The day numbers.</b> Given the arrow and “number the days”, Claude numbers each day to match the map’s stops, on its first turn, without asking.',
  '<b>The clipboard hint.</b> In the film, Claude Code’s footer may offer to paste each capture. If it does, turn Copy on capture off for the film take. The paste loop needs it on.',
  '<b>The zoom loop.</b> <code>scripts/input.sh scroll</code> needs a ⌘ option. Then check the frame the zoom reaches with no stack open.',
  '<b>The hold loop.</b> Needs Accessibility granted to Vignette Demo. The take should stop at once if <code>app.accessibility</code> is false.',
  '<b>The recording.</b> An 8-second .mov made with ffmpeg decodes in the watch folder and shows “0:08”.',
];
const DECISIONS = [
  '<b>The sentence.</b> “Your agent can show you things, and you answer by pointing.” Every beat of the film serves it. Change the wording if it is not what you want people to leave with.',
  '<b>The loops are separate short takes,</b> each from its own starting state, so none of them depends on the film’s take.',
  '<b>The folder name in Claude Code’s header.</b> Recommended: run the takes from <code>~/Code/postcard</code>, made by the take and removed after. The frames are drawn that way.',
  '<b>The earlier exchange in the postcard terminal.</b> One prompt before the take, “Walk me through how the itinerary page is built.”, about 35 lines. It fills the terminal and makes postcard the session used last.',
];
