// Draws the trailer's scenes: the Mac's screen in points, with Chrome, Claude Code, and Vignette's
// cards, editor and toolbar. The storyboard and the animatic both draw with it, so a storyboard
// panel is a frame of the animatic. The shots themselves are in story.js.

const W = 1512, H = 982, IW = 904, IH = 565;
const IMG = {
  itin: 'assets/itin.jpg', itinR1: 'assets/itin-r1.jpg', itinFinal: 'assets/itin-final.jpg', stays: 'assets/stays.jpg',
  packing: 'assets/packing.jpg', map: 'assets/map.jpg', chianti: 'assets/chianti.jpg',
  variants: 'assets/variants.jpg',
};

// Camera frames, in screen points: x, y, w, h. All 16:10, at least 800 points wide, and inside
// [0, 38, 1512, 944], so no pixel is enlarged past 1:1 and the menu bar never shows.
const CAM = {
  WIDE:    { r: [0, 38, 1510.4, 944],  what: 'The whole desktop below the menu bar.' },
  EDITOR:  { r: [74, 98, 1363, 852],   what: 'The editor and its toolbar, for a 16:10 image.' },
  RESULT:  { r: [568, 128, 944, 590],  what: 'The whole page, with both things Claude built: the day numbers and the Oct 14 card.' },
  STACK5:  { r: [504, 350, 1008, 630], what: 'Five cards in the stack and the selection strip. Loops only.' },
  TOOLBAR: { r: [356, 470, 800, 500],  what: "The editor's toolbar and the target's menu. Loops only." },
};

// The editor's fitted frame for a 16:10 image, measured from the last take, and the image-to-screen scale.
const F0 = [142, 98, 1228, 767.5], ES = F0[2] / IW;
const toScreen = (x, y) => [F0[0] + x * ES, F0[1] + y * ES];
// Stack slots, counted from the bottom, at full width and narrowed beside the editor.
const slot = i => [1357, 851 - i * 124, 138, 114];
const narrowSlot = i => [1426, 908 - i * 62, 69, 57];
const THUMB = slot(0);
// Postcard's top bar links, on screen.
const LINK = { itin: [792, 168], stays: [861, 168] };

// ---------------------------------------------------------------------------------------------
// Motion helpers. Times are in seconds from the start of a shot.

const clamp01 = x => Math.max(0, Math.min(1, x));
const lerp = (a, b, p) => a + (b - a) * p;
const lerpR = (a, b, p) => a.map((v, i) => lerp(v, b[i], p));
// A critically damped spring's progress from t0, 99% there at t0 + dur.
function spring(t, t0, dur) {
  if (t <= t0) return 0;
  const x = 6.6 * (t - t0) / dur;
  return Math.min(1, 1 - (1 + x) * Math.exp(-x));
}
// Ease in and out, for the pointer's glides and drags.
function ease(t, t0, dur) { const p = clamp01((t - t0) / dur); return p * p * (3 - 2 * p); }
const glide = (a, b, t, t0, dur) => lerpR(a, b, ease(t, t0, dur));
// Text typed from t0 at cps characters a second.
const typed = (text, t, t0, cps = 16) => text.slice(0, Math.max(0, Math.floor((t - t0) * cps)));
// A card's flight between two rects: its centre bows to one side and it swells a little mid-way.
function flight(from, to, p) {
  const c0 = [from[0] + from[2] / 2, from[1] + from[3] / 2], c1 = [to[0] + to[2] / 2, to[1] + to[3] / 2];
  const dx = c1[0] - c0[0], dy = c1[1] - c0[1], len = Math.hypot(dx, dy) || 1;
  const bow = Math.min(0.12 * len, 120);
  const ctrl = [(c0[0] + c1[0]) / 2 - dy / len * bow * 2, (c0[1] + c1[1]) / 2 + dx / len * bow * 2];
  const q = (a, b, c) => (1 - p) * (1 - p) * a + 2 * (1 - p) * p * b + p * p * c;
  const swell = 1 + 0.06 * Math.sin(Math.PI * p);
  const w = lerp(from[2], to[2], p) * swell, h = lerp(from[3], to[3], p) * swell;
  return [q(c0[0], ctrl[0], c1[0]) - w / 2, q(c0[1], ctrl[1], c1[1]) - h / 2, w, h];
}

// ---------------------------------------------------------------------------------------------
// Scene pieces. Each returns HTML positioned in screen points.

// Vignette's mark colours (MarkColor in Drawing.swift). A mark with no colour is drawn in the red
// the colour pass picks for these pages.
const MARK_HEX = { red: '#e03131', yellow: '#ffc034', 'light-blue': '#4dabf7', white: '#f3f3f3', violet: '#ae3ec9' };

function marksSVG(marks, view = [0, 0, IW, IH], slice = false) {
  const els = (marks || []).map(m => {
    const col = MARK_HEX[m.color] || MARK_HEX.red;
    if (m.t === 'arrow') {
      const a = Math.atan2(m.y2 - m.y1, m.x2 - m.x1), hx = s => `${m.x2 - 16 * Math.cos(a + s * 0.5)},${m.y2 - 16 * Math.sin(a + s * 0.5)}`;
      if (Math.hypot(m.x2 - m.x1, m.y2 - m.y1) < 4) return '';
      return `<path d="M${m.x1},${m.y1} L${m.x2},${m.y2} M${hx(1)} L${m.x2},${m.y2} L${hx(-1)}" fill="none" stroke="${col}" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>`;
    }
    if (m.t === 'rect') return `<rect x="${m.x}" y="${m.y}" width="${m.w}" height="${m.h}" rx="2" fill="none" stroke="${col}" stroke-width="3.2"/>`;
    // The editor's own sizes: a person's note is 24 pt, an agent's text about 2.2% of the image's width.
    const font = m.agent ? 'ui-monospace, SF Mono, Menlo, monospace' : 'ui-rounded, SF Pro Rounded, -apple-system, sans-serif';
    const size = m.size || (m.agent ? 20 : 24);
    return `<text x="${m.x}" y="${m.y + size * 0.93}" font-family="${font}" font-size="${size}" font-weight="${m.agent ? 600 : 560}"
      fill="${col}" stroke="#101012" stroke-width="2" paint-order="stroke" stroke-linejoin="round">${m.text}</text>`;
  }).join('');
  return `<svg viewBox="${view.join(' ')}" preserveAspectRatio="${slice ? 'xMidYMid slice' : 'none'}" style="position:absolute;inset:0;width:100%;height:100%">${els}</svg>`;
}

// Claude Code in Ghostty, left. Lines are [text, class]; the prompt sits at the bottom.
function terminal(s) {
  const lines = (s.lines || T_START).slice(-40);
  let h = `<div class="pt term" style="left:118px;top:148px;width:450px;height:20px;background:#080a0e"><span class="g">~/Code/postcard</span></div>`;
  h += `<div class="pt term" style="left:22px;top:178px;width:548px;height:700px;background:#080a0e;padding:4px 12px 0 14px">${
    lines.map(([t, c]) => `<div class="${c}">${t || ' '}</div>`).join('')}</div>`;
  h += `<div class="pt" style="left:200px;top:58px;width:200px;height:18px;background:#080a0e"></div>`;
  h += `<div class="pt" style="left:0;top:58px;width:592px;height:18px;text-align:center;font:600 13px -apple-system;color:#5d6066">Itinerary page</div>`;
  h += `<div class="pt term" style="left:400px;top:880px;width:170px;height:17px;background:#080a0e;text-align:right"><span class="g">Itinerary page ─</span></div>`;
  h += `<div class="pt term" style="left:30px;top:896px;width:540px;height:19px;background:#080a0e">❯ ${s.prompt || ''}<span style="background:#d6d6d6;color:#080a0e"> </span></div>`;
  if (s.hint) h += `<div class="pt term" style="left:40px;top:930px;width:530px;height:18px;background:#080a0e"><span class="hint" style="color:#c9d1d9">Image in clipboard · ctrl+v to paste</span></div>`;
  return h;
}

// A stitched image: pieces in one column, the gap and padding a fraction of the piece.
function stitchPieces(w, pieces) {
  const pw = w * 1808 / 1888, ph = pw * IH / IW, pad = w * 40 / 1888;
  return pieces.map(([k, m], i) =>
    `<div style="position:absolute;left:${pad}px;top:${pad + i * (ph + pad)}px;width:${pw}px;height:${ph}px;overflow:hidden;border-radius:${pad / 3}px">
      <img src="${IMG[k]}" style="position:absolute;inset:0;width:100%;height:100%">${marksSVG(m)}
      <span style="position:absolute;left:${pad}px;top:${pad}px;width:${pad * 2.2}px;height:${pad * 2.2}px;border-radius:50%;background:#fff;color:#111;
        font:800 ${pad * 1.3}px/1 -apple-system;display:flex;align-items:center;justify-content:center">${i + 1}</span></div>`).join('');
}

// A card in the stack or the corner. c: { img, marks, agent, badge, sent, stitch: pieces, opacity }.
function card(c, r, { focus = false, sel = 0 } = {}) {
  let [x, y, w, h] = r;
  if (c.stitch) { const pw = h * 0.793; x = x + w - pw; w = pw; }
  const inner = c.stitch
    ? `<div style="position:absolute;inset:0;background:#26282e">${stitchPieces(w, c.stitch)}</div>`
    : `<img src="${IMG[c.img]}">${c.marks ? marksSVG(c.marks, undefined, true) : ''}`;
  const op = c.opacity ?? 1;
  let h2 = `<div class="card-img" style="left:${x}px;top:${y}px;width:${w}px;height:${h}px;opacity:${op}">${inner}</div>`;
  if (c.agent) h2 += `<div class="tab" style="left:${x + w - 84}px;top:${y + 6}px;opacity:${op}"><span style="color:#d97757">✳</span>From Claude</div>`;
  if (c.badge) h2 += `<div class="badge" style="left:${x + w - 36}px;top:${y + h - 20}px;opacity:${op}">${c.badge}</div>`;
  if (c.sent) h2 += `<div class="tab" style="left:${x + 6}px;top:${y + h - 24}px;opacity:${op}"><span style="color:#d97757">✳</span>${c.sent}</div>`;
  if (sel) h2 += `<div class="ring-sel" style="left:${x - 4}px;top:${y - 4}px;width:${w + 8}px;height:${h + 8}px"></div>`;
  else if (focus) h2 += `<div class="ring-focus" style="left:${x - 4}px;top:${y - 4}px;width:${w + 8}px;height:${h + 8}px"></div>`;
  if (sel) h2 += `<div class="selcircle on" style="left:${x + 6}px;top:${y + 6}px">${sel}</div>`;
  return h2;
}

// The editor's toolbar. t: { offer: 'send' | 'reply', tool, target, menu, menuHot, message, typing, cx }.
function toolbar(t) {
  const tools = ['↖', '▭', '↗', 'Aa'].map((g, i) => `<div class="tool ${i === (t.tool ?? 1) ? 'on' : ''}">${g}</div>`).join('');
  const field = w => `<div class="field ${t.typing ? 'focus' : ''}" style="width:${w}px">${t.message ? t.message + (t.typing ? '<span style="opacity:.8">|</span>' : '') : '<span class="ph">Add a message</span>'}</div>`;
  const cx = t.cx || 756, target = t.target || 'postcard';
  if (t.offer === 'reply') {
    return `<div class="toolbar" style="left:${cx - 240}px;top:878px;width:480px">${tools}<div class="sep"></div>${field(212)}
      <div class="btn blue">Reply <span class="kbd">↩</span></div></div>`;
  }
  let h = `<div class="toolbar" style="left:${cx - 321}px;top:878px;width:642px">${tools}<div class="sep"></div>
    <div class="btn">Copy <span class="kbd">↩</span></div>
    <div class="btn" style="${t.menu ? 'background:rgba(255,255,255,0.22)' : ''}"><span style="color:#d97757">✳</span>${target} <span class="kbd">⌄</span></div>
    ${field(target.length > 8 ? 160 : 196)}<div class="btn blue">Send <span class="kbd">⌘↩</span></div></div>`;
  if (t.menu) {
    const row = (i, name, sub) => `<div class="row ${t.menuHot === i ? 'hot' : ''}"><span>${name === target ? '✓' : ''}</span><span style="color:#d97757">✳</span><span>${name}<small>${sub}</small></span></div>`;
    h += `<div class="menu" style="left:${cx - 92}px;top:${878 - 124}px;width:196px"><div class="hd">Send to</div>
      ${row(0, 'postcard', 'Itinerary page')}${row(1, 'postcard-api', 'Booking sync')}</div>`;
  }
  return h;
}

// The dimmed, blurred desktop behind the editor.
const dimLayer = o => `<div class="pt" style="left:0;top:0;width:${W}px;height:${H}px;opacity:${o};background:rgba(6,6,8,0.55);backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px)"></div>`;

// The editor. e: { img, marks, view, frame, stitch: pieces, stackNarrow, toolbar, dim }.
function editor(e) {
  const F = e.frame || F0, V = e.view || [0, 0, IW, IH];
  let h = dimLayer(e.dim ?? 1);
  if (e.stackNarrow) h += e.stackNarrow.map((c, i) => card(c, narrowSlot(e.stackNarrow.length - 1 - i))).join('');
  let inner;
  if (e.stitch) inner = `<div style="position:absolute;inset:0;background:#26282e">${stitchPieces(F[2], e.stitch)}</div>`;
  else {
    const sx = F[2] / V[2], sy = F[3] / V[3];
    inner = `<img src="${IMG[e.img]}" style="position:absolute;left:${-V[0] * sx}px;top:${-V[1] * sy}px;width:${IW * sx}px;height:${IH * sy}px">${marksSVG(e.marks, V)}`;
  }
  h += `<div class="pt" style="left:${F[0]}px;top:${F[1]}px;width:${F[2]}px;height:${F[3]}px;overflow:hidden;border-radius:10px;background:#1a1a1a;
    box-shadow:0 20px 60px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.35)">${inner}</div>`;
  if (e.toolbar) h += toolbar(e.toolbar);
  return h;
}

function pointer(p, kind = 'arrow') {
  if (!p) return '';
  if (kind === 'cross') return `<svg class="pt" style="left:${p[0] - 12}px;top:${p[1] - 12}px" width="24" height="24" viewBox="0 0 24 24">
    <path d="M12 0v24M0 12h24" stroke="#fff" stroke-width="3"/><path d="M12 0v24M0 12h24" stroke="#000" stroke-width="1"/></svg>`;
  return `<svg class="pt" style="left:${p[0] - 2}px;top:${p[1] - 1}px;filter:drop-shadow(0 1px 1px rgba(0,0,0,.5))" width="18" height="26" viewBox="0 0 18 26">
    <path d="M1 1 L1 20 L6 15.5 L9.5 23.5 L12.5 22.2 L9.2 14.5 L15.5 14.5 Z" fill="#000" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/></svg>`;
}

// A dashed arrow showing the pointer's path. The storyboard draws these; the animatic moves the pointer instead.
function path(pts, color = '#ffd60a') {
  if (!pts) return '';
  const d = pts.length === 3 ? `M${pts[0]} Q${pts[1]} ${pts[2]}` : 'M' + pts.map(p => p.join(' ')).join(' L');
  const end = pts[pts.length - 1], prev = pts[pts.length - 2];
  const a = Math.atan2(end[1] - prev[1], end[0] - prev[0]);
  const hx = s => [end[0] - 16 * Math.cos(a + s * 0.45), end[1] - 16 * Math.sin(a + s * 0.45)].join(' ');
  return `<svg class="pt" style="left:0;top:0;overflow:visible" width="${W}" height="${H}">
    <path d="${d}" fill="none" stroke="${color}" stroke-width="3" stroke-dasharray="9 7" stroke-linecap="round"/>
    <path d="M${hx(1)} L${end.join(' ')} L${hx(-1)}" fill="none" stroke="${color}" stroke-width="3" stroke-linecap="round"/></svg>`;
}

// Click rings: [x, y] is a still marker; [x, y, age] grows and fades over 0.4 s.
const clicks = list => (list || []).map(([x, y, age]) => {
  const r = 14 + (age || 0) * 40, o = age === undefined ? 1 : 1 - age / 0.4;
  return `<div class="pt" style="left:${x - r}px;top:${y - r}px;width:${2 * r}px;height:${2 * r}px;border-radius:50%;border:3px solid #ffd60a;opacity:${o}"></div>`;
}).join('');

// The whole screen. s: { page, pageNext, pageMix, term, select, stack, thumb, thumbDx, dim,
// flights, editor, path, clicks, pointer, pointerKind }.
function scene(s) {
  const tab = { itin: 'Tuscany', itinR1: 'Tuscany', itinFinal: 'Tuscany', stays: 'Stays' }[s.page || 'itin'];
  let h = `<img class="pt" src="assets/desk.jpg" style="left:0;top:0;width:${W}px;height:${H}px">`;
  h += `<div class="pt" style="left:745px;top:64px;width:175px;height:21px;background:#373737;font:13px/21px -apple-system;color:#e6e6e6">${tab} · Postcard</div>`;
  h += terminal(s.term || {});
  h += `<img class="pt" src="${IMG[s.page || 'itin']}" style="left:592px;top:141px;width:${IW}px;height:${IH}px">`;
  if (s.pageNext) h += `<img class="pt" src="${IMG[s.pageNext]}" style="left:592px;top:141px;width:${IW}px;height:${IH}px;opacity:${s.pageMix ?? 1}">`;
  if (s.select) {
    const [x, y, w, hh] = s.select;
    h += `<div class="pt" style="left:${x}px;top:${y}px;width:${w}px;height:${hh}px;background:rgba(160,160,170,0.25);border:1px solid rgba(255,255,255,0.7)"></div>`;
  }
  if (s.stack) {
    const st = s.stack, dx = st.dx || 0, op = st.opacity ?? 1;
    h += `<div class="pt" style="left:${1060 + dx}px;top:38px;width:452px;height:944px;opacity:${op};backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);
      background:rgba(10,4,12,0.18);-webkit-mask-image:linear-gradient(to right,transparent,#000 45%);mask-image:linear-gradient(to right,transparent,#000 45%)"></div>`;
    const n = st.cards.length;
    st.cards.forEach((c, i) => {
      const r = c.r || slot(n - 1 - i);
      h += card({ ...c, opacity: (c.opacity ?? 1) * op }, [r[0] + dx, r[1], r[2], r[3]], { focus: st.focus === i, sel: (st.selected || []).indexOf(i) + 1 });
    });
    if (st.strip) h += `<div class="strip" style="left:1180px;top:${st.strip}px;width:160px">
      <div>Copy <span>⌘C</span></div><div>Draw <span>↩</span></div><div>Stitch <span>⌘S</span></div><div>Delete <span>⌘⌫</span></div></div>`;
  }
  if (s.thumb) { const dx = s.thumbDx || 0; h += card(s.thumb, [THUMB[0] + dx, THUMB[1], THUMB[2], THUMB[3]]); }
  if (s.dim) h += dimLayer(s.dim);
  (s.flights || []).forEach(f => {
    const [x, y, w, hh] = f.rect;
    const inner = f.stitch ? `<div style="position:absolute;inset:0;background:#26282e">${stitchPieces(w, f.stitch)}</div>`
      : `<img src="${IMG[f.img]}">${f.marks ? marksSVG(f.marks, undefined, true) : ''}`;
    h += `<div class="card-img" style="left:${x}px;top:${y}px;width:${w}px;height:${hh}px;opacity:${f.opacity ?? 1};box-shadow:0 20px 50px rgba(0,0,0,.6)">${inner}</div>`;
  });
  if (s.editor) h += editor(s.editor);
  h += path(s.path);
  h += clicks(s.clicks);
  h += pointer(s.pointer, s.pointerKind);
  return h;
}

// The caption pill, top left, sized for a frame `scale` times 1600 wide. It fades in over 0.25 s
// from `age` 0; without an age it is fully shown.
function captionHTML(c, scale) {
  if (!c) return '';
  const pad = 16 * scale, o = c.age === undefined ? 1 : clamp01(c.age / 0.25);
  const keys = (c.keys || []).map((k, i) => `<span class="k ${c.lit && c.lit.includes(i) ? 'lit' : ''}" style="font-size:${22 * scale}px">${k}</span>`).join('');
  return `<div class="cap" style="left:${44 * scale}px;top:${40 * scale}px;font-size:${34 * scale}px;padding:${pad * 0.7}px ${pad * 1.6}px;opacity:${o}">${c.text}${keys ? `<span style="width:${8 * scale}px"></span>` + keys : ''}</div>`;
}

// The end card, as cut.swift draws it: the icon rises in and settles, the wordmark writes itself on
// from the left, then the two lines. From `exit` each part leaves, the lines first and the icon last.
const OUTRO = { exit: 4.0, length: 5.5 };
const smooth = x => { const u = clamp01(x); return u * u * (3 - 2 * u); };
const settle = (t, t0, len) => { if (t <= t0) return 0; const w = 6.64 / len, u = t - t0; return 1 - (1 + w * u) * Math.exp(-w * u); };
const leaving = (t, delay) => Math.pow(clamp01((t - OUTRO.exit - delay) / 0.5), 3);
function endcardHTML(scale, t = 3) {
  const px = v => v * scale;
  const rise = settle(t, 0.5, 1.1), iconOut = leaving(t, 0.16);
  const iconA = smooth((t - 0.5) / 0.5) * (1 - iconOut), iconS = 248 * (0.88 + 0.12 * rise) * (1 - 0.04 * iconOut);
  const iconY = 372 + 34 * (1 - rise) - 10 * iconOut;
  const write = smooth((t - 1.0) / 1.0), markOut = leaving(t, 0.08);
  const markH = 78, markW = markH * 1504 / 324;
  const edge = -90 + (markW + 180) * write;
  const line = (text, y, start, size, weight, color) => {
    const inP = smooth((t - start) / 0.6), out = leaving(t, 0), a = inP * (1 - out);
    return `<div style="position:absolute;left:0;right:0;top:${px(y - size * 0.62 + 10 * (1 - inP) - 8 * out)}px;text-align:center;font-size:${px(size)}px;font-weight:${weight};color:${color};opacity:${a}">${text}</div>`;
  };
  return `<div class="endcard" style="background:radial-gradient(circle at 50% 56%, rgba(255,237,214,0.07), rgba(255,237,214,0) 42%), #0b0a09">
    <img src="../outro/icon.png" style="position:absolute;left:${px(800 - iconS / 2)}px;top:${px(iconY - iconS / 2)}px;width:${px(iconS)}px;height:${px(iconS)}px;opacity:${iconA}">
    <img src="../outro/wordmark.png" style="position:absolute;left:${px(800 - markW / 2)}px;top:${px(560 - markH / 2 - 10 * markOut + 8 * (1 - write))}px;width:${px(markW)}px;height:${px(markH)}px;opacity:${1 - markOut};
      -webkit-mask-image:linear-gradient(90deg,#000 ${px(edge - 90)}px,transparent ${px(edge)}px);mask-image:linear-gradient(90deg,#000 ${px(edge - 90)}px,transparent ${px(edge)}px)">
    ${line('The modern Mac screenshot tool for the agentic age.', 652, 1.9, 27, 400, '#d6cfc4')}
    ${line('Free for macOS 14 or later &nbsp;·&nbsp; vignette.pete.design', 700, 2.15, 18, 500, '#8c8479')}
  </div>`;
}

// ---------------------------------------------------------------------------------------------
// Shots and reels. A shot: { id, dur, cam, from, camMove: [start, duration], dissolveIn, end, anim(t) }.

function camAt(shot, t) {
  const to = CAM[shot.cam].r;
  if (!shot.camMove || !shot.from || shot.from === shot.cam) return to;
  return lerpR(CAM[shot.from].r, to, spring(t, shot.camMove[0], shot.camMove[1]));
}

function frameAt(shot, t) {
  if (shot.end) return { end: true, t };
  const f = shot.anim ? shot.anim(Math.max(0, Math.min(shot.dur, t))) : {};
  return { scene: f.scene || {}, caption: f.caption || null, cam: camAt(shot, t) };
}

// One frame as HTML for a box `w` pixels wide.
function layerHTML(frame, w, captions = true) {
  const scale = w / 1600;
  if (frame.end) return endcardHTML(scale, frame.t);
  const r = frame.cam, s = w / r[2];
  return `<div class="scene" style="width:${W}px;height:${H}px;transform:scale(${s}) translate(${-r[0]}px,${-r[1]}px)">${scene(frame.scene)}</div>${
    captions ? captionHTML(frame.caption, scale) : ''}`;
}

function reelStarts(reel) { let t = 0; return reel.shots.map(s => { const a = t; t += s.dur; return a; }); }
const reelDur = reel => reel.shots.reduce((a, s) => a + s.dur, 0);
const fmt = t => `${Math.floor(t / 60)}:${(t % 60).toFixed(1).padStart(4, '0')}`;

// Replaces el's content with html by changing only what differs, so an image whose src is
// unchanged is not reloaded. The animatic calls this every frame.
const patchTemplate = document.createElement('template');
function patch(el, html) { patchTemplate.innerHTML = html; syncChildren(el, patchTemplate.content); }
function syncChildren(a, b) {
  const bn = Array.from(b.childNodes);
  bn.forEach((n, i) => { const o = a.childNodes[i]; if (!o) a.appendChild(n); else syncNode(o, n); });
  while (a.childNodes.length > bn.length) a.removeChild(a.lastChild);
}
function syncNode(o, n) {
  if (o.nodeType !== n.nodeType || o.nodeName !== n.nodeName) { o.replaceWith(n); return; }
  if (o.nodeType === 3) { if (o.nodeValue !== n.nodeValue) o.nodeValue = n.nodeValue; return; }
  if (o.nodeType !== 1) return;
  for (const at of Array.from(o.attributes)) if (!n.hasAttribute(at.name)) o.removeAttribute(at.name);
  for (const at of Array.from(n.attributes)) if (o.getAttribute(at.name) !== at.value) o.setAttribute(at.name, at.value);
  syncChildren(o, n);
}
