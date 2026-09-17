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
  TLAssetStore,
  TLComponents,
  TLEditorSnapshot,
  TLImageShape,
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
import { ExportItem, ExportResult, LoadPayload, Mark, PROTOCOL, ParkResult, postToNative } from './bridge'

/** One keyboard zoom step (cmd+plus / cmd+minus). */
const ZOOM_STEP = 1.25
/** Wheel and pinch: window scale per wheel unit; pinch-out (negative deltaY) grows the window. */
const WHEEL_ZOOM_RATE = 0.01
import { COLORS, ColorId, DEFAULT_SIZE, DEFAULT_TOOL, REOPEN_TOOL, TOOLS, ToolId } from './config'

const IMAGE_ID: TLShapeId = createShapeId('screenshot')

/// The image on the canvas, by its key (file path). The host owns drafts; this page keeps no
/// state that outlives a load, so a restarted web process loses nothing the host has not seen.
let currentKey: string | null = null
/// True when the user changed the canvas since the host last saw a rendering of it.
let dirty = false
/// True while `load` or `export` mutate the store, so those changes are not reported as drafts.
let quiet = false
let draftTimer: ReturnType<typeof setTimeout> | null = null
/// Longest side, in pixels, of the preview returned with a parked draft.
const PREVIEW_MAX = 1600
/// How long after the last change the draft snapshot goes to the host.
const DRAFT_DELAY_MS = 300
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

/// The operations that stand the canvas on its head run one at a time. Each takes its snapshot
/// after an await, so another one's shapes must never land in between: `park` would store them.
let pending: Promise<unknown> = Promise.resolve()
function oneAtATime<T>(work: () => Promise<T>): Promise<T> {
  const next = pending.then(work, work)
  pending = next.catch(() => {})
  return next
}

/// Sends the host the current annotations, or null when there are none. Debounced from the store listener.
function scheduleDraft(editor: Editor) {
  if (draftTimer) clearTimeout(draftTimer)
  draftTimer = setTimeout(() => {
    draftTimer = null
    if (currentKey) postToNative({ type: 'draft', key: currentKey, snapshot: hasAnnotations(editor) ? getSnapshot(editor.store) : null })
  }, DRAFT_DELAY_MS)
}

/// The draft as the host should store it, with a rendering when the user changed it since the last one.
async function park(editor: Editor, scale: number): Promise<ParkResult> {
  if (draftTimer) {
    clearTimeout(draftTimer)
    draftTimer = null
  }
  if (!currentKey) return { snapshot: null, preview: null }
  const annotated = hasAnnotations(editor)
  let preview: string | null = null
  if (dirty && annotated) {
    const bounds = editor.getShapePageBounds(IMAGE_ID)
    const previewScale = bounds ? Math.min(scale, PREVIEW_MAX / Math.max(bounds.w, bounds.h)) : scale
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
        try {
          if (editor) loadImage(editor, payload, scaleRef)
          else pending.current = payload
        } catch (err) {
          postToNative({ type: 'log', message: 'load failed: ' + (err instanceof Error ? err.stack ?? err.message : String(err)) })
        }
      },
      async park() {
        return editor ? oneAtATime(() => park(editor, scaleRef.current)) : { snapshot: null, preview: null }
      },
      reset() {
        if (!editor) return
        clearCanvas(editor)
        currentKey = null
      },
      async build(payload, marks) {
        if (!editor) return { snapshot: null, preview: null }
        return oneAtATime(() => build(editor, payload, marks))
      },
      async export(items) {
        if (!editor) return { items: [], error: 'editor not mounted' }
        return oneAtATime(() => exportDrafts(editor, items, scaleRef.current))
      },
      setTool(id) {
        if (editor && TOOLS.some((t) => t.id === id)) selectTool(editor, id as ToolId)
      },
      setColor(id) {
        if (editor && COLORS.some((c) => c.id === id)) setColor(editor, id as ColorId)
      },
      setCanvasZoom(ratio) {
        if (editor && Number.isFinite(ratio) && ratio >= 1) setCanvasZoom(editor, ratio)
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
        licenseKey={import.meta.env.VITE_TLDRAW_LICENSE_KEY}
        assets={assets}
        components={components}
        onMount={(ed) => {
          ed.user.updateUserPreferences({ colorScheme: 'dark' })
          ed.updateInstanceState({ isDebugMode: false })
          ed.store.listen(
            () => {
              if (quiet) return
              dirty = true
              scheduleDraft(ed)
            },
            { scope: 'document', source: 'user' }
          )
          setEditor(ed)
          ;(window as unknown as { editor: Editor }).editor = ed // for `shotnote://eval` debugging
          postToNative({
            type: 'ready',
            protocol: PROTOCOL,
            tools: TOOLS.map(({ id, label, key, symbol }) => ({ id, label, key, symbol })),
            colors: COLORS.map(({ id, hex }) => ({ id, hex })),
          })
        }}
      />
    </div>
  )
}

function loadImage(editor: Editor, p: LoadPayload, scaleRef: { current: number }) {
  if (draftTimer) {
    clearTimeout(draftTimer)
    draftTimer = null
  }
  quiet = true
  try {
    loadImageQuietly(editor, p, scaleRef)
  } catch (err) {
    quiet = false
    throw err
  }
}

function loadImageQuietly(editor: Editor, p: LoadPayload, scaleRef: { current: number }) {
  currentKey = p.key
  // The shape is sized in points so the canvas matches the window; export scales back up to pixels.
  const ratio = window.devicePixelRatio || 1
  const w = p.pixelWidth / ratio
  const h = p.pixelHeight / ratio
  scaleRef.current = ratio

  silently(editor, () => {
    placeImage(editor, p, w, h)
    // A stored draft carries the selection it was parked with. On the select tool those handles
    // would be back, and a color picked for the next shape repaints the selected ones instead.
    editor.selectNone()
  })
  fitCamera(editor, w, h)

  editor.setStyleForNextShapes(DefaultColorStyle, COLORS[0].id)
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
  canvasRatio = 1
  // The host sizes the window to the image's aspect, so 'fit' makes the image flush with the window.
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

/** The host's last in-window magnification; a window resize refits and then puts it back. */
let canvasRatio = 1

/** Magnification inside the window about its center: 1 fits the image, larger zooms in. */
function setCanvasZoom(editor: Editor, ratio: number) {
  canvasRatio = ratio
  const { x: cx, y: cy, z: cz } = editor.getCamera()
  const z = editor.getBaseZoom() * ratio
  const { w, h } = editor.getViewportScreenBounds()
  const sx = w / 2
  const sy = h / 2
  editor.setCamera({ x: cx + sx / z - sx / cz, y: cy + sy / z - sy / cz, z })
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

function clearCanvas(editor: Editor) {
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

/// An agent's marks as ordinary shapes, in canvas points: the image is at the origin, `w` by `h`,
/// and every mark number is a fraction of it. The host has already checked the numbers and the color.
function createMarks(editor: Editor, marks: Mark[], w: number, h: number) {
  for (const m of marks) {
    const x = m.x * w
    const y = m.y * h
    const color = (m.color ?? COLORS[0].id) as ColorId
    if (m.type === 'arrow') {
      editor.createShape({
        type: 'arrow',
        x,
        y,
        props: { start: { x: 0, y: 0 }, end: { x: (m.x2! - m.x) * w, y: (m.y2! - m.y) * h }, color, size: DEFAULT_SIZE, dash: 'solid', fill: 'none' },
      })
    } else if (m.type === 'text') {
      editor.createShape({ type: 'text', x, y, props: { richText: toRichText(m.text!), color, size: DEFAULT_SIZE } })
    } else {
      editor.createShape({
        type: 'geo',
        x,
        y,
        props: { geo: m.type, w: m.w! * w, h: m.h! * h, color, size: DEFAULT_SIZE, dash: 'solid', fill: 'none' },
      })
    }
  }
}

/// An agent's marks as a draft, with the editor never shown: the image and the marks go on the
/// canvas, the snapshot and a rendering come back, and whatever the canvas held is put back. The
/// host stores the result, so the card shows the marks and Copy Annotated has them before anyone
/// opens the editor. `p.snapshot` is the image's existing draft, so marks add to it.
async function build(editor: Editor, p: LoadPayload, marks: Mark[]): Promise<ParkResult> {
  const before = getSnapshot(editor.store)
  const beforeKey = currentKey
  const selected = editor.getSelectedShapeIds()
  const ratio = window.devicePixelRatio || 1
  const w = p.pixelWidth / ratio
  const h = p.pixelHeight / ratio
  quiet = true
  try {
    silently(editor, () => {
      placeImage(editor, p, w, h)
      createMarks(editor, marks, w, h)
    })
    const snapshot = getSnapshot(editor.store)
    const preview = await render(editor, Math.min(ratio, PREVIEW_MAX / Math.max(w, h)))
    // A `load` landed while the rendering was in flight: it drew the other image, so drop it.
    return { snapshot, preview: currentKey === beforeKey ? preview : null }
  } finally {
    if (currentKey === beforeKey) {
      silently(editor, () => {
        loadSnapshot(editor.store, before)
        editor.setSelectedShapes(selected)
      })
      quiet = false
    }
    // Else the page is loading another image and owns `quiet`; its canvas stays.
  }
}

function selectTool(editor: Editor, id: ToolId) {
  const t = TOOLS.find((t) => t.id === id)!
  if ('geo' in t) editor.setStyleForNextShapes(GeoShapeGeoStyle, t.geo)
  editor.setCurrentTool(t.tool)
}

function setColor(editor: Editor, id: ColorId) {
  editor.setStyleForNextShapes(DefaultColorStyle, id)
  if (editor.getSelectedShapeIds().length) editor.setStyleForSelectedShapes(DefaultColorStyle, id)
}

function activeTool(editor: Editor): ToolId | null {
  const current = editor.getCurrentToolId()
  if (current === 'geo') {
    const geo = editor.getStyleForNextShape(GeoShapeGeoStyle)
    return TOOLS.find((t) => 'geo' in t && t.geo === geo)?.id ?? null
  }
  return TOOLS.find((t) => t.tool === current)?.id ?? null
}

async function finish(editor: Editor, scale: number) {
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
  const ids = [...editor.getCurrentPageShapeIds()].filter((id) => id !== IMAGE_ID)
  if (ids.length) {
    const svg = await editor.getSvgString(ids, { bounds: Box.From(bounds), padding: 0, background: false, scale })
    if (svg) {
      const annotations = await decodeImage('data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg.svg))
      await waitForEmbeddedFonts(svg.svg)
      ctx.drawImage(annotations, 0, 0, width, height)
    }
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

/// Keyboard shortcuts (tldraw's own are part of the UI we hide) and tool state for the native toolbar.
const Hotkeys = track(function Hotkeys({ scaleRef }: { scaleRef: { current: number } }) {
  const editor = useEditor()
  const tool = activeTool(editor)
  const color = editor.getStyleForNextShape(DefaultColorStyle)

  useEffect(() => {
    postToNative({ type: 'tool', tool, color })
  }, [tool, color])

  // Refit as soon as the window is laid out at a new size, before that frame paints, so the image
  // never shows at the old fit. tldraw's own bounds update waits for the next frame. The reset
  // drops any magnification, so it goes back on afterwards.
  useEffect(() => {
    const container = editor.getContainer()
    const observer = new ResizeObserver(() => {
      editor.updateViewportScreenBounds(container)
      editor.setCamera(editor.getCamera(), { reset: true })
      if (canvasRatio > 1) setCanvasZoom(editor, canvasRatio)
    })
    observer.observe(container)
    return () => observer.disconnect()
  }, [editor])

  // A pinch arrives as a wheel event with ctrlKey; cmd+wheel zooms too. Both go to the host,
  // coalesced to one message per frame, and never reach tldraw's own zoom. Plain wheel still pans.
  useEffect(() => {
    let factor = 1
    let scheduled = false
    const onWheel = (e: WheelEvent) => {
      if (!e.ctrlKey && !e.metaKey) return
      e.preventDefault()
      e.stopPropagation()
      factor *= Math.exp(-e.deltaY * WHEEL_ZOOM_RATE)
      if (scheduled) return
      scheduled = true
      requestAnimationFrame(() => {
        scheduled = false
        if (factor !== 1) postToNative({ type: 'zoom', factor })
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
  }, [])

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
        postToNative({ type: 'zoom', factor: e.key === '0' ? null : e.key === '-' ? 1 / ZOOM_STEP : ZOOM_STEP })
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
      if (!mod && !e.altKey) {
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
