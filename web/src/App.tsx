import { useEffect, useMemo, useRef, useState } from 'react'
import {
  AssetRecordType,
  Box,
  DefaultColorStyle,
  DefaultDashStyle,
  DefaultFillStyle,
  DefaultSizeStyle,
  Editor,
  GeoShapeGeoStyle,
  HistoryEntry,
  TLArrowShape,
  TLAssetStore,
  TLComponents,
  TLEditorSnapshot,
  TLImageShape,
  TLRecord,
  TLShape,
  TLShapeId,
  Tldraw,
  createShapeId,
  getSnapshot,
  loadSnapshot,
  toRichText,
  track,
  useEditor,
} from 'tldraw'
import 'tldraw/tldraw.css'
import { ExportItem, ExportResult, LoadPayload, Mark, PROTOCOL, ParkResult, ViewRequest, ViewResult, ZoomAnchor, postToNative } from './bridge'

/** One keyboard zoom step (cmd+plus / cmd+minus). */
const ZOOM_STEP = 1.25
/** Wheel and pinch: window scale per wheel unit; pinch-out (negative deltaY) grows the window. */
const WHEEL_ZOOM_RATE = 0.01
import {
  CANDIDATES,
  ColorId,
  DEFAULT_SIZE,
  DEFAULT_TEXT_POINTS,
  DEFAULT_TOOL,
  PUSHED_TEXT_MARGIN,
  PUSHED_TEXT_MIN_WIDTH,
  PUSHED_TEXT_SIZE,
  REOPEN_TOOL,
  TOOLS,
  ToolId,
} from './config'
import { Area, explain, hasSample, pickColor, prepareSample } from './contrast'

const IMAGE_ID: TLShapeId = createShapeId('screenshot')

/// The image on the canvas, by its key (file path). The host owns drafts; this page keeps no
/// state that outlives a load, so a restarted web process loses nothing the host has not seen.
let currentKey: string | null = null
/// True when the user changed the canvas since the host last saw a rendering of it.
let dirty = false
/// True while `load` or `export` mutate the store, so those changes are not reported as drafts.
let quiet = false
let draftTimer: ReturnType<typeof setTimeout> | null = null
/// Marks whose colour the heuristic has not picked for where they now are: drawn, moved, or
/// resized since the last pick. Emptied when the hand lets go, before the draft goes to the host.
let unpicked = new Set<TLShapeId>()
/// Longest side, in pixels, of the preview returned with the parked draft of the image on the
/// canvas. The host sends it with the image; `build` uses the one in its own payload.
let previewMax = 0
/// How long after the last change the draft snapshot goes to the host.
const DRAFT_DELAY_MS = 300
/// How many frames `setView` waits for the host's resize to reach this process before it draws.
const VIEW_FRAMES = 20
/// How long a rendering waits for a font it embeds the first time; see `waitForEmbeddedFonts`.
const FONT_RASTER_MS = 250

/// Asset `src` values are file paths; the host serves them from the page's own origin, under the
/// same per-launch token as the page, so a snapshot saved in one launch resolves in the next.
function fileUrl(path: string) {
  return location.origin + location.pathname.replace(/[^/]*$/, 'file?p=' + encodeURIComponent(path))
}

const assets: TLAssetStore = {
  async upload() {
    throw new Error('the page never uploads assets')
  },
  resolve(asset) {
    return asset.type === 'image' && asset.props.src?.startsWith('/') ? fileUrl(asset.props.src) : asset.props.src
  },
}

function hasAnnotations(editor: Editor) {
  return editor.getCurrentPageShapeIds().size > 1
}

/// Runs `fn` without touching undo history: loading a snapshot otherwise records an undo entry.
function silently(editor: Editor, fn: () => void) {
  editor.run(fn, { history: 'ignore' })
}

/// Runs `fn` with store changes not reported as drafts. Spans the whole operation, not just the
/// mutating calls: tldraw delivers a snapshot load's changes to listeners on the next transaction,
/// which for `load` is the camera fit one frame later.
async function quietly<T>(fn: () => Promise<T>): Promise<T> {
  quiet = true
  try {
    return await fn()
  } finally {
    quiet = false
  }
}

/// The operations that stand the canvas on its head run one at a time, in the order the host
/// called them. Each takes its snapshot after an await, so another one's shapes must never land in
/// between: `park` would store them, and `export` and `build` would wipe them when they put the
/// canvas back.
let pending: Promise<unknown> = Promise.resolve()
function oneAtATime<T>(work: () => Promise<T>): Promise<T> {
  const next = pending.then(work, work)
  pending = next.catch(() => {})
  return next
}

/// Sends the host the current annotations, or null when there are none. Debounced from the store
/// listener. The host asks for the zoom overlay when this arrives.
function scheduleDraft(editor: Editor) {
  if (draftTimer) clearTimeout(draftTimer)
  draftTimer = setTimeout(() => {
    // A drag is one motion, not its frames: the colours wait until the hand lets go.
    if (editor.inputs.isPointing) return scheduleDraft(editor)
    draftTimer = null
    pickColors(editor)
    if (currentKey) postToNative({ type: 'draft', key: currentKey, snapshot: hasAnnotations(editor) ? getSnapshot(editor.store) : null })
  }, DRAFT_DELAY_MS)
}

/// Notes the marks a change touched, so their colour is picked again for where they now sit.
function noteChanged(entry: HistoryEntry<TLRecord>) {
  const changes = entry.changes
  for (const record of Object.values(changes.added)) noteShape(record)
  for (const [, after] of Object.values(changes.updated)) noteShape(after)
  for (const record of Object.values(changes.removed)) if (record.typeName === 'shape') unpicked.delete(record.id)
}

function noteShape(record: TLRecord) {
  if (record.typeName === 'shape' && record.id !== IMAGE_ID) unpicked.add(record.id)
}

/// The colour of every mark that is waiting for one. Marks the decode has not caught up with stay
/// in the set, so the next pick colours them.
function pickColors(editor: Editor) {
  if (!currentKey || !unpicked.size || !hasSample(currentKey)) return
  const ids = [...unpicked]
  unpicked.clear()
  applyColors(editor, currentKey, ids)
}

/// What a mark's ink covers, in fractions of the screenshot. An arrow is the strip between its two
/// ends: its bounding box is the whole rectangle they span, most of which the stroke never touches,
/// so a banner in a corner of that box would colour an arrow that runs nowhere near it. A shape
/// drawn with no fill is its border band for the same reason.
function areaOf(editor: Editor, shape: TLShape, image: Box): Area | null {
  if (shape.type === 'arrow') {
    const arrow = shape as TLArrowShape
    const transform = editor.getShapePageTransform(shape.id)
    const from = transform.applyToPoint(arrow.props.start)
    const to = transform.applyToPoint(arrow.props.end)
    return {
      kind: 'line',
      from: { x: (from.x - image.x) / image.w, y: (from.y - image.y) / image.h },
      to: { x: (to.x - image.x) / image.w, y: (to.y - image.y) / image.h },
    }
  }
  const bounds = editor.getShapePageBounds(shape.id)
  if (!bounds) return null
  const rect = {
    x: (bounds.x - image.x) / image.w,
    y: (bounds.y - image.y) / image.h,
    w: bounds.w / image.w,
    h: bounds.h / image.h,
  }
  // A shape with no `fill` prop at all (text, a freehand stroke) keeps the whole box.
  const fill = (shape.props as { fill?: string }).fill
  return { kind: fill === 'none' ? 'border' : 'fill', rect }
}

/// Sets each mark's colour from the screenshot under it. The image shape is the frame every mark is
/// measured against, so a mark's bounds become the fraction of the screenshot it covers.
///
/// The change is outside undo history: the colour belongs to where the mark is, not to an edit of
/// its own, so one undo moves or removes the mark and the next pick colours it for where it lands.
function applyColors(editor: Editor, key: string, ids: TLShapeId[]) {
  const image = editor.getShapePageBounds(IMAGE_ID)
  if (!image) return
  const picked: { id: TLShapeId; color: ColorId }[] = []
  for (const id of ids) {
    const shape = editor.getShape(id)
    const props = shape?.props as { color?: string } | undefined
    if (!shape || shape.meta.colorChosen || props?.color === undefined) continue
    const area = areaOf(editor, shape, image)
    if (!area) continue
    const color = pickColor(key, area)
    if (color && color !== props.color) picked.push({ id, color })
  }
  if (!picked.length) return
  const was = quiet
  quiet = true // the caller reports the draft this belongs to
  silently(editor, () => {
    // One case per shape a mark can be: `updateShape` takes the shape's own type, not the union.
    for (const { id, color } of picked) {
      switch (editor.getShape(id)?.type) {
        case 'geo':
          editor.updateShape({ id, type: 'geo', props: { color } })
          break
        case 'arrow':
          editor.updateShape({ id, type: 'arrow', props: { color } })
          break
        case 'text':
          editor.updateShape({ id, type: 'text', props: { color } })
          break
      }
    }
  })
  quiet = was
}

/// The draft as the host should store it, with a rendering when the user changed it since the last one.
async function park(editor: Editor, scale: number): Promise<ParkResult> {
  if (draftTimer) {
    clearTimeout(draftTimer)
    draftTimer = null
  }
  if (!currentKey) return { snapshot: null, preview: null }
  pickColors(editor)
  const annotated = hasAnnotations(editor)
  let preview: string | null = null
  if (dirty && annotated) {
    const bounds = editor.getShapePageBounds(IMAGE_ID)
    const previewScale = bounds ? Math.min(scale, previewMax / Math.max(bounds.w, bounds.h)) : scale
    preview = await render(editor, previewScale)
  }
  dirty = false
  return { snapshot: annotated ? getSnapshot(editor.store) : null, preview }
}

export function App() {
  const [editor, setEditor] = useState<Editor | null>(null)
  const pending = useRef<LoadPayload | null>(null)
  const scaleRef = useRef(1)

  // Expose the host API as soon as the page runs, even before the editor mounts.
  useEffect(() => {
    window.shotnote = {
      load(payload) {
        if (editor) loadImage(editor, payload, scaleRef)
        else pending.current = payload
      },
      async park() {
        return editor ? oneAtATime(() => park(editor, scaleRef.current)) : { snapshot: null, preview: null }
      },
      reset() {
        if (!editor) return
        void oneAtATime(async () => {
          clearCanvas(editor)
          currentKey = null
        })
      },
      async build(payload, marks) {
        if (!editor) return { snapshot: null, preview: null }
        return oneAtATime(() => build(editor, payload, marks))
      },
      async export(items) {
        if (!editor) return { items: [], error: 'editor not mounted' }
        return oneAtATime(() => exportDrafts(editor, items, scaleRef.current))
      },
      async overlay(maxPixel) {
        return editor ? oneAtATime(() => overlay(editor, maxPixel)) : null
      },
      setTool(id) {
        if (editor && TOOLS.some((t) => t.id === id)) selectTool(editor, id as ToolId)
      },
      async setView(request) {
        // In the queue like every other canvas call: `export` and `build` put the camera back when
        // they restore their snapshot, so a view applied in the middle of one is undone behind the
        // stand-in. The stand-in covers the page for as long as this waits.
        return editor ? oneAtATime(() => setView(editor, request)) : null
      },
      finish() {
        if (editor) finish(editor, scaleRef.current)
      },
    }
    if (editor && pending.current) {
      loadImage(editor, pending.current, scaleRef)
      pending.current = null
    }
  }, [editor])

  const components = useMemo<TLComponents>(
    () => ({
      ContextMenu: null,
      InFrontOfTheCanvas: () => <Hotkeys scaleRef={scaleRef} />,
    }),
    []
  )

  return (
    <div className="editor">
      <Tldraw
        hideUi
        // A double click on the canvas is the zoom's (see `Hotkeys`), so it must not also leave a
        // text shape behind. The text tool is how text is drawn here.
        options={{ createTextOnCanvasDoubleClick: false }}
        licenseKey={import.meta.env.VITE_TLDRAW_LICENSE_KEY}
        assets={assets}
        components={components}
        onMount={(ed) => {
          ed.user.updateUserPreferences({ colorScheme: 'dark' })
          ed.updateInstanceState({ isDebugMode: false })
          ed.store.listen(
            (entry) => {
              if (quiet) return
              dirty = true
              noteChanged(entry)
              scheduleDraft(ed)
            },
            { scope: 'document', source: 'user' }
          )
          setEditor(ed)
          ;(window as unknown as { editor: Editor }).editor = ed // for `shotnote://eval` debugging
          ;(window as unknown as { contrast: unknown }).contrast = { pick: pickColor, explain }
          postToNative({
            type: 'ready',
            protocol: PROTOCOL,
            tools: TOOLS.map(({ id, label, key, symbol }) => ({ id, label, key, symbol })),
            markColors: CANDIDATES.map(({ id, hex }) => ({ id, hex })),
          })
        }}
      />
    </div>
  )
}

/// Puts the image on the canvas, in its turn in the queue. Only the canvas change waits there:
/// `loaded` follows two frames later, outside the queue, because WebKit pauses frames while the
/// window is hidden or the screen is locked and the next operation must not wait for that.
function loadImage(editor: Editor, p: LoadPayload, scaleRef: { current: number }) {
  void oneAtATime(async () => {
    if (draftTimer) {
      clearTimeout(draftTimer)
      draftTimer = null
    }
    quiet = true
    try {
      loadImageQuietly(editor, p, scaleRef)
    } catch (err) {
      quiet = false
      // The message only. A WebKit stack names the bundle's served URL, and every served URL
      // starts with the per-launch token, which must never reach the log.
      postToNative({ type: 'log', message: 'load failed: ' + (err instanceof Error ? err.message : String(err)) })
    }
  })
}

function loadImageQuietly(editor: Editor, p: LoadPayload, scaleRef: { current: number }) {
  currentKey = p.key
  previewMax = p.previewMaxPixel
  unpicked.clear()
  // The decode runs alongside the load: `loaded` must not wait for it, and a mark drawn before it
  // lands keeps the first candidate until the next pick.
  void prepareSample(p.key, fileUrl(p.key)).catch(() => {})
  // The shape is sized in points so the canvas matches the window; export scales back up to pixels.
  const ratio = window.devicePixelRatio || 1
  const w = p.pixelWidth / ratio
  const h = p.pixelHeight / ratio
  scaleRef.current = ratio

  silently(editor, () => {
    placeImage(editor, p, w, h)
    // A draft comes back with whatever selection it was parked with. A reopen picks up the
    // annotation drawn last instead, and only that one: the select tool is what opens, so a color
    // press, a drag, or Delete acts on it. A fresh image has nothing to pick up.
    const last = p.snapshot ? lastAnnotation(editor) : null
    editor.setSelectedShapes(last ? [last] : [])
  })
  fitCamera(editor, w, h)

  editor.setStyleForNextShapes(DefaultColorStyle, CANDIDATES[0].id)
  editor.setStyleForNextShapes(DefaultSizeStyle, DEFAULT_SIZE)
  editor.setStyleForNextShapes(DefaultDashStyle, 'solid')
  editor.setStyleForNextShapes(DefaultFillStyle, 'none')
  selectTool(editor, p.snapshot ? REOPEN_TOOL : DEFAULT_TOOL)
  editor.clearHistory()
  // Two frames: fitCamera re-measures on the next frame, so the image has been laid out by then.
  // The load's store changes reach the listener during that first frame; drafts report from here on.
  requestAnimationFrame(() =>
    requestAnimationFrame(() => {
      quiet = false
      dirty = false
      postToNative({ type: 'loaded', key: p.key })
    })
  )
}

function fitCamera(editor: Editor, w: number, h: number) {
  view = { ratio: 1, x: 0.5, y: 0.5 }
  // An image opens in a window of its own aspect, so 'fit' makes it flush with the window there.
  // A zoom grows each side of the window on its own, and `setView` then asks for the magnification
  // past this fit; 'fit-max' keeps that fit the side the window has grown least in.
  editor.setCameraOptions({
    // No step below the fit: nothing tldraw does on its own can zoom the image out of the window.
    zoomSteps: [1, 2, 4, 8],
    constraints: {
      initialZoom: 'fit-max',
      baseZoom: 'fit-max',
      bounds: { x: 0, y: 0, w, h },
      padding: { x: 0, y: 0 },
      origin: { x: 0.5, y: 0.5 },
      behavior: 'contain',
    },
  })
  // The host resizes the view right before loading; re-measure so the fit uses the final size.
  editor.updateViewportScreenBounds(editor.getContainer())
  editor.setCamera(editor.getCamera(), { reset: true })
  requestAnimationFrame(() => {
    editor.updateViewportScreenBounds(editor.getContainer())
    editor.setCamera(editor.getCamera(), { reset: true })
  })
}

/**
 * The picture the host last asked for: how far the image is magnified inside the window, and the
 * middle of the part that is visible, as fractions of the image. The host holds the same three
 * numbers and draws its own copy of this picture while a zoom is moving, so this is the whole of
 * what the page is told about a zoom.
 */
let view = { ratio: 1, x: 0.5, y: 0.5 }

/**
 * Draws the view the host asked for and answers once it is painted. The host has already laid the
 * window out at `width` by `height`; that resize crosses a process boundary, so the page waits for
 * it to arrive rather than drawing this camera at the old size. The host takes its own copy of the
 * picture away when this answers.
 */
async function setView(editor: Editor, request: ViewRequest): Promise<ViewResult | null> {
  // Five numbers from the host, checked before they reach the camera: a ratio below 1 would zoom
  // the image out of a window sized to fit it, and one number that is not finite moves the camera
  // where nothing can bring it back. The host keeps its stand-in up when this answers null.
  const numbers = [request.ratio, request.x, request.y, request.width, request.height]
  if (!numbers.every(Number.isFinite) || request.ratio < 1) return null
  view = { ratio: request.ratio, x: request.x, y: request.y }
  const container = editor.getContainer()
  let waited = 0
  for (; waited < VIEW_FRAMES; waited++) {
    const box = container.getBoundingClientRect()
    // Within a pixel: the host's frame is fractional and a layout viewport is whole pixels, so the
    // size that arrives here can be one short of the size the host asked for.
    if (Math.abs(box.width - request.width) <= 1 && Math.abs(box.height - request.height) <= 1) break
    await new Promise((r) => requestAnimationFrame(r))
  }
  applyView(editor)
  // Two frames: the first carries this camera into a paint, the second has been on screen.
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))
  const box = container.getBoundingClientRect()
  return { width: box.width, height: box.height, ratio: editor.getZoomLevel() / editor.getBaseZoom(), waited }
}

/**
 * Puts the stored view on the camera: the image magnified by `ratio` with the point it names in
 * the middle of the window. Idempotent, and the resize observer runs it too, so it does not matter
 * whether the host's call or the resize reaches the page first.
 */
function applyView(editor: Editor) {
  const bounds = editor.getShapePageBounds(IMAGE_ID)
  if (!bounds) return
  editor.updateViewportScreenBounds(editor.getContainer())
  const z = editor.getBaseZoom() * view.ratio
  const { w, h } = editor.getViewportScreenBounds()
  editor.setCamera({ x: w / 2 / z - (bounds.x + view.x * bounds.w), y: h / 2 / z - (bounds.y + view.y * bounds.h), z })
}

/// The screenshot on an empty canvas, or the draft the host stored for it, which carries the image
/// shape with it. The caller owns `quiet`, the camera, and `currentKey`, and runs this silently.
function placeImage(editor: Editor, p: LoadPayload, w: number, h: number) {
  removeAll(editor)
  if (p.snapshot) {
    loadSnapshot(editor.store, p.snapshot)
    return
  }
  const assetId = AssetRecordType.createId()
  editor.createAssets([
    {
      id: assetId,
      typeName: 'asset',
      type: 'image',
      meta: {},
      props: { w, h, mimeType: p.mimeType, src: p.key, name: 'screenshot', isAnimated: false },
    },
  ])
  editor.createShape({ id: IMAGE_ID, type: 'image', x: 0, y: 0, isLocked: true, props: { w, h, assetId } })
}

/// The annotation drawn last: the top of the page's z-order, which is where tldraw puts each new
/// shape (`getHighestIndexForParent`). Nothing here reorders shapes, so top is newest. The
/// screenshot is under all of them and is never it.
function lastAnnotation(editor: Editor): TLShapeId | null {
  const shapes = editor.getCurrentPageShapesSorted().filter((s) => s.id !== IMAGE_ID)
  return shapes.length ? shapes[shapes.length - 1].id : null
}

function clearCanvas(editor: Editor) {
  unpicked.clear()
  silently(editor, () => removeAll(editor))
  editor.clearHistory()
}

/// Every shape and asset, gone. The image shape is locked, so it is unlocked first.
function removeAll(editor: Editor) {
  const ids = [...editor.getCurrentPageShapeIds()]
  if (ids.length) {
    editor.updateShapes(ids.map((id) => ({ id, type: editor.getShape(id)!.type, isLocked: false })))
    editor.deleteShapes(ids)
  }
  const assets = editor.getAssets().map((a) => a.id)
  if (assets.length) editor.deleteAssets(assets)
}

/// An agent's marks as ordinary shapes, in canvas points: `image` is the box the screenshot
/// occupies, and every mark number is a fraction of it. The host has already checked the numbers
/// and the color.
function createMarks(editor: Editor, marks: Mark[], image: Box): { unnamed: TLShapeId[]; texts: TLShapeId[] } {
  const unnamed: TLShapeId[] = []
  const texts: TLShapeId[] = []
  const margin = PUSHED_TEXT_MARGIN * image.w
  for (const m of marks) {
    const x = image.x + m.x * image.w
    const y = image.y + m.y * image.h
    const color = (m.color ?? CANDIDATES[0].id) as ColorId
    // A mark that names a colour keeps it; one that names none is the heuristic's to colour.
    const meta = m.color ? { colorChosen: true } : {}
    const id = createShapeId()
    if (!m.color) unnamed.push(id)
    if (m.type === 'arrow') {
      editor.createShape({
        id,
        type: 'arrow',
        x,
        y,
        meta,
        props: {
          start: { x: 0, y: 0 },
          end: { x: (m.x2! - m.x) * image.w, y: (m.y2! - m.y) * image.h },
          color,
          size: DEFAULT_SIZE,
          dash: 'solid',
          fill: 'none',
        },
      })
    } else if (m.type === 'text') {
      // A pushed text is drawn at a size the image gives it and wrapped in a box, so a sentence is
      // neither huge on a crop nor one line that runs off the edge. `scale` multiplies both the
      // font and `w`, so the box on the canvas is `w * scale`: dividing here is what makes the
      // wrap land where the mark asked for it.
      const scale = (PUSHED_TEXT_SIZE * image.w) / DEFAULT_TEXT_POINTS
      const room = image.x + image.w - margin - x
      const box = m.w === undefined ? Math.max(PUSHED_TEXT_MIN_WIDTH * image.w, room) : m.w * image.w
      editor.createShape({
        id,
        type: 'text',
        x,
        y,
        meta,
        props: { richText: toRichText(m.text!), color, size: DEFAULT_SIZE, scale, autoSize: false, w: box / scale },
      })
      texts.push(id)
    } else {
      editor.createShape({
        id,
        type: 'geo',
        x,
        y,
        meta,
        props: { geo: m.type, w: m.w! * image.w, h: m.h! * image.h, color, size: DEFAULT_SIZE, dash: 'solid', fill: 'none' },
      })
    }
  }
  return { unnamed, texts }
}

/// Moves pushed text marks back inside the image. How tall a box is depends on where the text
/// wraps and how wide the font draws it, neither of which the agent that sent the mark can know,
/// so each box is measured once it exists. A box with no room to spare rests against the top left
/// margin: the start of the text is what has to show.
///
/// The measure needs the font the text is drawn in. A page that has not drawn text yet has not
/// loaded it, and measures the fallback instead, so the wait comes first: it is the font already
/// in `web/dist`, and every later push finds it loaded.
async function pullTextsInside(editor: Editor, texts: TLShapeId[], image: Box) {
  await editor.fonts.loadRequiredFontsForCurrentPage()
  const margin = PUSHED_TEXT_MARGIN * image.w
  silently(editor, () => {
    for (const id of texts) {
      const bounds = editor.getShapePageBounds(id)
      const shape = editor.getShape(id)
      if (!bounds || !shape) continue
      const x = within(bounds.x, image.x + margin, image.x + image.w - margin - bounds.w)
      const y = within(bounds.y, image.y + margin, image.y + image.h - margin - bounds.h)
      if (x === bounds.x && y === bounds.y) continue
      editor.updateShape({ id, type: 'text', x: shape.x + (x - bounds.x), y: shape.y + (y - bounds.y) })
    }
  })
}

/// `value` between the two, `low` winning when the box is bigger than the room between them.
function within(value: number, low: number, high: number) {
  return Math.min(Math.max(value, low), Math.max(low, high))
}

/// An agent's marks as a draft, with the editor never shown: the image and the marks go on the
/// canvas, the snapshot and a rendering come back, and whatever the canvas held is put back. The
/// host stores the result, so the card shows the marks and Copy Drawing has them before anyone
/// opens the editor. `p.snapshot` is the image's existing draft, so marks add to it.
async function build(editor: Editor, p: LoadPayload, marks: Mark[]): Promise<ParkResult> {
  const before = getSnapshot(editor.store)
  const selected = editor.getSelectedShapeIds()
  const ratio = window.devicePixelRatio || 1
  const w = p.pixelWidth / ratio
  const h = p.pixelHeight / ratio
  quiet = true
  try {
    let made: { unnamed: TLShapeId[]; texts: TLShapeId[] } = { unnamed: [], texts: [] }
    // The image's own box, not the payload's: a stored draft carries the image shape it was made
    // with, and every mark is a fraction of the box the screenshot is actually drawn in.
    let image = new Box(0, 0, w, h)
    silently(editor, () => {
      placeImage(editor, p, w, h)
      image = editor.getShapePageBounds(IMAGE_ID) ?? image
      made = createMarks(editor, marks, image)
    })
    const { unnamed, texts } = made
    // Before the colours: the heuristic samples what a mark covers, so a text has to be where it
    // will be drawn first.
    if (texts.length) await pullTextsInside(editor, texts, image)
    // The snapshot is stored as it stands, so the colours are picked before it is taken.
    if (unnamed.length) {
      // A screenshot that will not decode leaves no sample: the marks keep the colour they were
      // given, and the draft is still stored. Losing an agent's marks over a colour is not a trade.
      await prepareSample(p.key, fileUrl(p.key)).catch(() => {})
      applyColors(editor, p.key, unnamed)
    }
    const snapshot = getSnapshot(editor.store)
    const preview = await render(editor, Math.min(ratio, p.previewMaxPixel / Math.max(w, h)))
    return { snapshot, preview }
  } finally {
    silently(editor, () => {
      loadSnapshot(editor.store, before)
      editor.setSelectedShapes(selected)
    })
    quiet = false
  }
}

function selectTool(editor: Editor, id: ToolId) {
  const t = TOOLS.find((t) => t.id === id)!
  if ('geo' in t) editor.setStyleForNextShapes(GeoShapeGeoStyle, t.geo)
  editor.setCurrentTool(t.tool)
}

function activeTool(editor: Editor): ToolId | null {
  const current = editor.getCurrentToolId()
  if (current === 'geo') {
    const geo = editor.getStyleForNextShape(GeoShapeGeoStyle)
    return TOOLS.find((t) => 'geo' in t && t.geo === geo)?.id ?? null
  }
  return TOOLS.find((t) => t.tool === current)?.id ?? null
}

/// Done, from the toolbar or from Return. It renders after an await like `park` and `export`, so
/// it takes its turn with them rather than reading a canvas one of them is part way through.
function finish(editor: Editor, scale: number) {
  void oneAtATime(() => renderDone(editor, scale))
}

async function renderDone(editor: Editor, scale: number) {
  pickColors(editor)
  if (!hasAnnotations(editor)) {
    dirty = false
    postToNative({ type: 'done', png: null })
    return
  }
  const png = await render(editor, scale)
  if (!png) return cancel(editor)
  dirty = false // the host has this rendering; no preview needed when the draft is parked
  postToNative({ type: 'done', png })
}

/// Asks the host to close; it parks the draft on the way out.
function cancel(_editor: Editor) {
  postToNative({ type: 'cancel' })
}

/// The image with its annotations, as a PNG data URL. `scale` maps canvas points to output pixels.
/// The screenshot is drawn straight onto a canvas and only the annotations go through tldraw's
/// SVG export. WebKit loads raster images embedded in an SVG asynchronously, so an SVG that
/// carries the screenshot rasterizes blank unless it is small; tldraw's own toImage hits that.
async function render(editor: Editor, scale: number) {
  const bounds = editor.getShapePageBounds(IMAGE_ID)
  const shape = editor.getShape(IMAGE_ID)
  const assetId = shape?.type === 'image' ? (shape as TLImageShape).props.assetId : null
  const src = assetId ? await editor.resolveAssetUrl(assetId, { shouldResolveToOriginal: true }) : null
  if (!bounds || !src) return null
  silently(editor, () => editor.selectNone())
  const width = Math.round(bounds.w * scale)
  const height = Math.round(bounds.h * scale)
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext('2d')!
  ctx.drawImage(await decodeImage(src), 0, 0, width, height)
  await drawAnnotations(editor, ctx, bounds, width, height, scale)
  return canvas.toDataURL('image/png')
}

/// tldraw's SVG of the annotations alone, drawn over the whole image. False when nothing is drawn.
async function drawAnnotations(editor: Editor, ctx: CanvasRenderingContext2D, bounds: Box, width: number, height: number, scale: number) {
  const ids = [...editor.getCurrentPageShapeIds()].filter((id) => id !== IMAGE_ID)
  if (!ids.length) return false
  const svg = await editor.getSvgString(ids, { bounds: Box.From(bounds), padding: 0, background: false, scale })
  if (!svg) return false
  const annotations = await decodeImage('data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg.svg))
  await waitForEmbeddedFonts(svg.svg)
  ctx.drawImage(annotations, 0, 0, width, height)
  return true
}

/// The annotations alone on a transparent canvas, covering the image: what the host lays over the
/// screenshot while a zoom is moving. Null when nothing is drawn. The selection is put back, since
/// the user is editing this canvas.
async function overlay(editor: Editor, maxPixel: number): Promise<string | null> {
  const bounds = editor.getShapePageBounds(IMAGE_ID)
  if (!bounds || !hasAnnotations(editor)) return null
  const scale = Math.min(window.devicePixelRatio || 1, maxPixel / Math.max(bounds.w, bounds.h))
  const width = Math.round(bounds.w * scale)
  const height = Math.round(bounds.h * scale)
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const selected = editor.getSelectedShapeIds()
  silently(editor, () => editor.selectNone())
  try {
    if (!(await drawAnnotations(editor, canvas.getContext('2d')!, bounds, width, height, scale))) return null
  } finally {
    silently(editor, () => editor.setSelectedShapes(selected))
  }
  return canvas.toDataURL('image/png')
}

async function decodeImage(src: string) {
  const img = new Image()
  img.src = src
  await img.decode()
  return img
}

/// WebKit starts loading a font embedded in an SVG image when it renders it, after `decode()` has
/// resolved, and paints nothing where that font is still loading: the first text annotation the
/// page rasterizes comes out blank. tldraw's own export sleeps 250 ms for browsers it detects as
/// Safari, which WKWebView is not. One wait per font: WebKit keeps it for every rendering after.
const rasterizedFonts = new Set<string>()
async function waitForEmbeddedFonts(svg: string) {
  // Enough of each embedded font's data URL to tell one from another, not the whole 100 KB of it.
  const fresh = (svg.match(/url\(["']?data:font\/[^"')]{0,48}/g) ?? []).filter((font) => !rasterizedFonts.has(font))
  if (!fresh.length) return
  await new Promise((resolve) => setTimeout(resolve, FONT_RASTER_MS))
  for (const url of fresh) rasterizedFonts.add(url)
}

/// Renders each item's draft by loading it into the live store, then puts the store back. The
/// current image's draft is what is on the canvas, not the host's copy. Undo history is left as
/// it was. A failure stops the run and is reported; whatever rendered before it is returned.
function exportDrafts(editor: Editor, items: ExportItem[], scale: number): Promise<ExportResult> {
  return quietly(() => exportDraftsQuietly(editor, items, scale))
}

async function exportDraftsQuietly(editor: Editor, items: ExportItem[], scale: number): Promise<ExportResult> {
  const before = getSnapshot(editor.store)
  const selected = editor.getSelectedShapeIds()
  const rendered: { key: string; png: string }[] = []
  let error: string | null = null
  try {
    for (const item of items) {
      const snapshot = item.key === currentKey ? before : item.snapshot
      silently(editor, () => loadSnapshot(editor.store, snapshot))
      const png = await render(editor, scale)
      if (png) rendered.push({ key: item.key, png })
    }
  } catch (err) {
    error = err instanceof Error ? err.message : String(err)
  } finally {
    silently(editor, () => {
      loadSnapshot(editor.store, before)
      editor.setSelectedShapes(selected)
    })
  }
  return { items: rendered, error }
}

/// Where the cursor is as a fraction of the window: what the host and the camera both hold in
/// place while zooming. The viewport is the window, so the same fraction reads in either space.
function cursorAnchor(editor: Editor, e: MouseEvent): ZoomAnchor {
  const { x, y, w, h } = editor.getViewportScreenBounds()
  return { x: (e.clientX - x) / w, y: (e.clientY - y) / h }
}

/// Keyboard shortcuts (tldraw's own are part of the UI we hide) and tool state for the native toolbar.
const Hotkeys = track(function Hotkeys({ scaleRef }: { scaleRef: { current: number } }) {
  const editor = useEditor()
  const tool = activeTool(editor)
  const color = editor.getStyleForNextShape(DefaultColorStyle)

  useEffect(() => {
    postToNative({ type: 'tool', tool, color })
  }, [tool, color])

  // Refit as soon as the window is laid out at a new size, before that frame paints, so the image
  // never shows at the old fit: tldraw's own bounds update waits for the next frame. The view the
  // host asked for is what it refits to, so a resize cannot undo where a zoom left the camera.
  useEffect(() => {
    const container = editor.getContainer()
    const observer = new ResizeObserver(() => applyView(editor))
    observer.observe(container)
    return () => observer.disconnect()
  }, [editor])

  // A pinch arrives as a wheel event with ctrlKey; cmd+wheel zooms too. Both go to the host,
  // coalesced to one message per frame, and never reach tldraw's own zoom. Plain wheel still pans.
  // Each message carries where the cursor was, so the host and the camera hold that point.
  useEffect(() => {
    let factor = 1
    let at: ZoomAnchor | null = null
    let scheduled = false
    const onWheel = (e: WheelEvent) => {
      if (!e.ctrlKey && !e.metaKey) return
      e.preventDefault()
      e.stopPropagation()
      factor *= Math.exp(-e.deltaY * WHEEL_ZOOM_RATE)
      at = cursorAnchor(editor, e)
      if (scheduled) return
      scheduled = true
      requestAnimationFrame(() => {
        scheduled = false
        if (factor !== 1) postToNative({ type: 'zoom', factor, at })
        factor = 1
      })
    }
    // The host takes the trackpad pinch before WebKit; these are the leftovers if one gets through.
    const swallow = (e: Event) => {
      e.preventDefault()
      e.stopPropagation()
    }
    const gestures = ['gesturestart', 'gesturechange', 'gestureend']
    window.addEventListener('wheel', onWheel, { capture: true, passive: false })
    for (const g of gestures) window.addEventListener(g, swallow, { capture: true, passive: false })
    return () => {
      window.removeEventListener('wheel', onWheel, { capture: true })
      for (const g of gestures) window.removeEventListener(g, swallow, { capture: true })
    }
  }, [editor])

  // A double-click with the select tool zooms in on the point clicked, the same step the
  // trackpad's two-finger double tap takes, and comes home from above the fitted size. The page
  // decides, because it knows the tool and what is under the pointer; the host owns the zoom.
  // Over a mark, or while a mark's text is being edited, tldraw's own meaning stands.
  useEffect(() => {
    const onDoubleClick = (e: MouseEvent) => {
      if (editor.getCurrentToolId() !== 'select' || editor.getEditingShapeId() !== null) return
      // The select tool's own double click asks these three in this order, so asking the same
      // three is the only way the page and tldraw never both act. A selected shape is hit
      // anywhere inside it, hollow or not, which is why the middle one cannot be left out: a
      // reopened card comes back with its last mark selected. The screenshot is locked and a
      // locked shape is not hit-tested, so anything here is a mark.
      const point = editor.screenToPage({ x: e.clientX, y: e.clientY })
      const hovered = editor.getHoveredShape()
      const mark = (hovered && !editor.isShapeOfType(hovered, 'group') ? hovered : null)
        ?? editor.getSelectedShapeAtPoint(point)
        ?? editor.getShapeAtPoint(point, { margin: editor.getHitTestMargin(), hitInside: false })
      if (mark) return
      postToNative({ type: 'smartZoom', at: cursorAnchor(editor, e) })
    }
    window.addEventListener('dblclick', onDoubleClick, true)
    return () => window.removeEventListener('dblclick', onDoubleClick, true)
  }, [editor])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const editing = editor.getEditingShapeId() !== null
      const mod = e.metaKey || e.ctrlKey
      if (e.key === 'Escape' && !editing) {
        e.preventDefault()
        cancel(editor)
        return
      }
      if (e.key === 'Enter' && !e.shiftKey && !e.altKey) {
        // Return finishes; while typing it only ends the text, and Cmd+Return finishes from there.
        e.preventDefault()
        if (editing) {
          editor.setEditingShape(null)
          if (!mod) return
        }
        finish(editor, scaleRef.current)
        return
      }
      if (mod && (e.key === '=' || e.key === '+' || e.key === '-' || e.key === '0')) {
        e.preventDefault()
        // tldraw binds these too, on the document; stopping here keeps its camera zoom out of it.
        e.stopPropagation()
        // No anchor: a keyboard step zooms about the window's middle, as Preview does.
        postToNative({ type: 'zoom', factor: e.key === '0' ? null : e.key === '-' ? 1 / ZOOM_STEP : ZOOM_STEP, at: null })
        return
      }
      if (editing) return
      if (mod && e.key.toLowerCase() === 'z') {
        e.preventDefault()
        if (e.shiftKey) editor.redo()
        else editor.undo()
        return
      }
      if ((e.key === 'Backspace' || e.key === 'Delete') && !mod) {
        const ids = editor.getSelectedShapeIds()
        if (ids.length) {
          e.preventDefault()
          editor.deleteShapes(ids)
        }
        return
      }
      if (!mod && !e.altKey && /^[a-z]$/.test(e.key.toLowerCase())) {
        // Tool keys are the page's. tldraw registers its own on the document body, which `hideUi`
        // leaves in place, so a letter it binds would reach a tool the toolbar does not show: this
        // capture-phase listener stops every plain letter before that.
        e.stopPropagation()
        const t = TOOLS.find((t) => t.key === e.key.toLowerCase())
        if (t) {
          e.preventDefault()
          selectTool(editor, t.id)
        }
      }
    }
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
  }, [editor, scaleRef])

  return null
})
