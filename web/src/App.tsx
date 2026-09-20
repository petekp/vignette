import { useEffect, useMemo, useRef, useState } from 'react'
import {
  DefaultColorStyle,
  DefaultDashStyle,
  DefaultFillStyle,
  DefaultSizeStyle,
  Editor,
  GeoShapeGeoStyle,
  TLAssetStore,
  TLComponents,
  TLShapeId,
  Tldraw,
  getSnapshot,
  track,
  useEditor,
} from 'tldraw'
import 'tldraw/tldraw.css'
import { LoadPayload, PROTOCOL, ParkResult, postToNative } from './bridge'
import {
  IMAGE_ID,
  beginQuiet,
  endQuiet,
  fileUrl,
  hasAnnotations,
  imageFrame,
  isQuiet,
  oneAtATime,
  placeImage,
  removeAll,
  silently,
} from './canvas'
import { clearUnpicked, noteChanged, pickColors } from './colors'
import { CANDIDATES, DEFAULT_SIZE, DEFAULT_TOOL, REOPEN_TOOL, TOOLS, ToolId } from './config'
import { explain, pickColor, prepareSample } from './contrast'
import { build, cappedScale, exportDrafts, overlay, render } from './render'
import { applyView, cursorAnchor, fitCamera, placeEditor, setView, useZoomWheel, zoomByKey } from './view'

/// The image on the canvas, by its key (file path). The host owns drafts; this page keeps no
/// state that outlives a load, so a restarted web process loses nothing the host has not seen.
let currentKey: string | null = null
/// True when the user changed the canvas since the host last saw a rendering of it.
let dirty = false
let draftTimer: ReturnType<typeof setTimeout> | null = null
/// Longest side, in pixels, of the preview returned with the parked draft of the image on the
/// canvas. The host sends it with the image; `build` uses the one in its own payload.
let previewMax = 0
/// How long after the last change the draft snapshot goes to the host.
const DRAFT_DELAY_MS = 300

const assets: TLAssetStore = {
  async upload() {
    throw new Error('the page never uploads assets')
  },
  resolve(asset) {
    return asset.type === 'image' && asset.props.src?.startsWith('/') ? fileUrl(asset.props.src) : asset.props.src
  },
}

/// Sends the host the current annotations, or null when there are none. Debounced from the store
/// listener. The host asks for the zoom overlay when this arrives.
function scheduleDraft(editor: Editor) {
  if (draftTimer) clearTimeout(draftTimer)
  draftTimer = setTimeout(() => {
    // A drag is one motion, not its frames: the colours wait until the hand lets go.
    if (editor.inputs.isPointing) return scheduleDraft(editor)
    draftTimer = null
    pickColors(editor, currentKey)
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
  pickColors(editor, currentKey)
  const annotated = hasAnnotations(editor)
  let preview: string | null = null
  if (dirty && annotated) {
    const bounds = editor.getShapePageBounds(IMAGE_ID)
    preview = await render(editor, bounds ? cappedScale(scale, previewMax, bounds.w, bounds.h) : scale)
  }
  dirty = false
  return { snapshot: annotated ? getSnapshot(editor.store) : null, preview }
}

export function App() {
  const [editor, setEditor] = useState<Editor | null>(null)
  const pendingLoad = useRef<LoadPayload | null>(null)
  const scaleRef = useRef(1)

  // Expose the host API as soon as the page runs, even before the editor mounts.
  useEffect(() => {
    window.vignette = {
      load(payload) {
        if (editor) loadImage(editor, payload, scaleRef)
        else pendingLoad.current = payload
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
        return oneAtATime(() => exportDrafts(editor, items, scaleRef.current, currentKey))
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
    if (editor && pendingLoad.current) {
      loadImage(editor, pendingLoad.current, scaleRef)
      pendingLoad.current = null
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
              if (isQuiet()) return
              dirty = true
              noteChanged(entry)
              scheduleDraft(ed)
            },
            { scope: 'document', source: 'user' }
          )
          setEditor(ed)
          ;(window as unknown as { editor: Editor }).editor = ed // for `vignette://eval` debugging
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
    beginQuiet()
    try {
      loadImageQuietly(editor, p, scaleRef)
    } catch (err) {
      endQuiet()
      // The message only. A WebKit stack names the bundle's served URL, and every served URL
      // starts with the per-launch token, which must never reach the log.
      postToNative({ type: 'log', message: 'load failed: ' + (err instanceof Error ? err.message : String(err)) })
    }
  })
}

function loadImageQuietly(editor: Editor, p: LoadPayload, scaleRef: { current: number }) {
  currentKey = p.key
  previewMax = p.previewMaxPixel
  clearUnpicked()
  // The decode runs alongside the load: `loaded` must not wait for it, and a mark drawn before it
  // lands keeps the first candidate until the next pick.
  void prepareSample(p.key, fileUrl(p.key)).catch(() => {})
  const { w, h, ratio } = imageFrame(p)
  scaleRef.current = ratio

  if (p.frame) placeEditor(p.frame)
  silently(editor, () => {
    placeImage(editor, p, w, h)
    // A reopen selects the annotation drawn last, and only that one, whatever the draft was parked
    // with: the select tool is what opens, so a color press, a drag, or Delete acts on it. A fresh
    // image has nothing to pick up.
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
      endQuiet()
      dirty = false
      postToNative({ type: 'loaded', key: p.key })
    })
  )
}

/// The annotation drawn last: the top of the page's z-order, which is where tldraw puts each new
/// shape (`getHighestIndexForParent`). Nothing here reorders shapes, so top is newest. The
/// screenshot is under all of them and is never it.
function lastAnnotation(editor: Editor): TLShapeId | null {
  const shapes = editor.getCurrentPageShapesSorted().filter((s) => s.id !== IMAGE_ID)
  return shapes.length ? shapes[shapes.length - 1].id : null
}

function clearCanvas(editor: Editor) {
  clearUnpicked()
  silently(editor, () => removeAll(editor))
  editor.clearHistory()
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
  pickColors(editor, currentKey)
  if (!hasAnnotations(editor)) {
    dirty = false
    postToNative({ type: 'done', png: null })
    return
  }
  let png: string | null = null
  try {
    png = await render(editor, scale)
  } catch (err) {
    // The host waits for `done` or `cancel` with no deadline of its own, so a rendering that
    // throws (an image that will not decode, an SVG export that fails) still answers. The message
    // only: a WebKit stack can name a served URL, which starts with the per-launch token.
    postToNative({ type: 'log', message: 'done failed: ' + (err instanceof Error ? err.message : String(err)) })
  }
  if (!png) return cancel()
  dirty = false // the host has this rendering; no preview needed when the draft is parked
  postToNative({ type: 'done', png })
}

/// Asks the host to close; it parks the draft on the way out.
function cancel() {
  postToNative({ type: 'cancel' })
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

  useZoomWheel(editor)

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
        cancel()
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
      if (zoomByKey(e, mod)) return
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
