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
  TLComponents,
  TLEditorSnapshot,
  TLImageShape,
  TLShapeId,
  Tldraw,
  createShapeId,
  getSnapshot,
  loadSnapshot,
  track,
  useEditor,
} from 'tldraw'
import 'tldraw/tldraw.css'
import { LoadPayload, postToNative } from './bridge'
import { COLORS, ColorId, DEFAULT_SIZE, DEFAULT_TOOL, REOPEN_TOOL, TOOLS, ToolId } from './config'

const IMAGE_ID: TLShapeId = createShapeId('screenshot')

/// Annotations in progress, by image key. A draft is the whole store so the image and camera come back with it.
const drafts = new Map<string, TLEditorSnapshot>()
let currentKey: string | null = null
/// True when the user changed the canvas since the host last saw a rendering of it.
let dirty = false
/// Longest side, in pixels, of the preview sent with a parked draft.
const PREVIEW_MAX = 1600

function hasAnnotations(editor: Editor) {
  return editor.getCurrentPageShapeIds().size > 1
}

/// Sends the host a rendering of the current draft if it changed, then stores the draft.
async function park(editor: Editor, scale: number) {
  if (currentKey && dirty && hasAnnotations(editor)) {
    const bounds = editor.getShapePageBounds(IMAGE_ID)
    const previewScale = bounds ? Math.min(scale, PREVIEW_MAX / Math.max(bounds.w, bounds.h)) : scale
    const preview = await render(editor, previewScale)
    if (preview) postToNative({ type: 'draft', key: currentKey, preview })
  }
  dirty = false
  saveDraft(editor)
}

/// Stores the current image's annotations, or drops its draft if they were all deleted.
function saveDraft(editor: Editor) {
  if (!currentKey) return
  if (hasAnnotations(editor)) drafts.set(currentKey, getSnapshot(editor.store))
  else drafts.delete(currentKey)
  postToNative({ type: 'drafts', keys: [...drafts.keys()] })
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
        if (editor) await park(editor, scaleRef.current)
      },
      reset() {
        if (!editor) return
        saveDraft(editor)
        clearCanvas(editor)
        currentKey = null
      },
      forget(keys) {
        for (const k of keys) drafts.delete(k)
        postToNative({ type: 'drafts', keys: [...drafts.keys()] })
      },
      export(keys) {
        if (!editor) return postToNative({ type: 'exported', items: [] })
        exportDrafts(editor, keys, scaleRef.current).catch((err) =>
          postToNative({ type: 'log', message: 'export failed: ' + (err instanceof Error ? err.stack ?? err.message : String(err)) })
        )
      },
      setTool(id) {
        if (editor && TOOLS.some((t) => t.id === id)) selectTool(editor, id as ToolId)
      },
      setColor(id) {
        if (editor && COLORS.some((c) => c.id === id)) setColor(editor, id as ColorId)
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
        components={components}
        onMount={(ed) => {
          ed.user.updateUserPreferences({ colorScheme: 'dark' })
          ed.updateInstanceState({ isDebugMode: false })
          ed.store.listen(() => { dirty = true }, { scope: 'document', source: 'user' })
          setEditor(ed)
          ;(window as unknown as { editor: Editor }).editor = ed // for `shotnote://eval` debugging
          postToNative({
            type: 'ready',
            tools: TOOLS.map(({ id, label, key, symbol }) => ({ id, label, key, symbol })),
            colors: COLORS.map(({ id, hex }) => ({ id, hex })),
          })
        }}
      />
    </div>
  )
}

function loadImage(editor: Editor, p: LoadPayload, scaleRef: { current: number }) {
  saveDraft(editor)
  clearCanvas(editor)
  currentKey = p.key
  // The shape is sized in points so the canvas matches the window; export scales back up to pixels.
  const ratio = window.devicePixelRatio || 1
  const w = p.pixelWidth / ratio
  const h = p.pixelHeight / ratio
  scaleRef.current = ratio

  const draft = drafts.get(p.key)
  if (draft) {
    loadSnapshot(editor.store, draft)
  } else {
    const assetId = AssetRecordType.createId()
    editor.createAssets([
      {
        id: assetId,
        typeName: 'asset',
        type: 'image',
        meta: {},
        props: { w, h, mimeType: 'image/png', src: p.dataUrl, name: 'screenshot', isAnimated: false },
      },
    ])
    editor.createShape({ id: IMAGE_ID, type: 'image', x: 0, y: 0, isLocked: true, props: { w, h, assetId } })
  }
  fitCamera(editor, w, h)

  editor.setStyleForNextShapes(DefaultColorStyle, COLORS[0].id)
  editor.setStyleForNextShapes(DefaultSizeStyle, DEFAULT_SIZE)
  editor.setStyleForNextShapes(DefaultDashStyle, 'solid')
  editor.setStyleForNextShapes(DefaultFillStyle, 'none')
  selectTool(editor, draft ? REOPEN_TOOL : DEFAULT_TOOL)
  editor.clearHistory()
}

function fitCamera(editor: Editor, w: number, h: number) {
  // The host sizes the window to the image's aspect, so 'fit' makes the image flush with the window.
  editor.setCameraOptions({
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

function clearCanvas(editor: Editor) {
  const ids = [...editor.getCurrentPageShapeIds()]
  if (ids.length) {
    editor.updateShapes(ids.map((id) => ({ id, type: editor.getShape(id)!.type, isLocked: false })))
    editor.deleteShapes(ids)
  }
  const assets = editor.getAssets().map((a) => a.id)
  if (assets.length) editor.deleteAssets(assets)
  editor.clearHistory()
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
  if (current === 'geo') return editor.getStyleForNextShape(GeoShapeGeoStyle) === 'ellipse' ? 'ellipse' : 'rectangle'
  return TOOLS.find((t) => t.tool === current)?.id ?? null
}

async function finish(editor: Editor, scale: number) {
  const png = await render(editor, scale)
  if (!png) return cancel(editor, scale)
  dirty = false // the host has this rendering; no preview needed when the draft is parked
  postToNative({ type: 'done', png })
}

/// Parks the draft so the host can show it on the card, then asks to close.
async function cancel(editor: Editor, scale: number) {
  await park(editor, scale)
  postToNative({ type: 'cancel' })
}

/// The image with its annotations, as a PNG data URL. `scale` maps canvas points to output pixels.
/// The screenshot is drawn straight onto a canvas and only the annotations go through tldraw's
/// SVG export. WebKit loads raster images embedded in an SVG asynchronously, so an SVG that
/// carries the screenshot rasterizes blank unless it is small; tldraw's own toImage hits that.
async function render(editor: Editor, scale: number) {
  const bounds = editor.getShapePageBounds(IMAGE_ID)
  const shape = editor.getShape(IMAGE_ID)
  const asset = shape?.type === 'image' ? editor.getAsset((shape as TLImageShape).props.assetId!) : null
  if (!bounds || !asset || asset.type !== 'image' || !asset.props.src) return null
  editor.selectNone()
  const width = Math.round(bounds.w * scale)
  const height = Math.round(bounds.h * scale)
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext('2d')!
  ctx.drawImage(await decodeImage(asset.props.src), 0, 0, width, height)
  const ids = [...editor.getCurrentPageShapeIds()].filter((id) => id !== IMAGE_ID)
  if (ids.length) {
    const svg = await editor.getSvgString(ids, { bounds: Box.From(bounds), padding: 0, background: false, scale })
    if (svg) ctx.drawImage(await decodeImage('data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg.svg)), 0, 0, width, height)
  }
  return canvas.toDataURL('image/png')
}

async function decodeImage(src: string) {
  const img = new Image()
  img.src = src
  await img.decode()
  return img
}

/// Renders each key's draft by loading it into the live store, then puts the store back.
async function exportDrafts(editor: Editor, keys: string[], scale: number) {
  saveDraft(editor)
  const before = getSnapshot(editor.store)
  const items: { key: string; png: string }[] = []
  for (const key of keys) {
    const draft = drafts.get(key)
    if (!draft) continue
    loadSnapshot(editor.store, draft)
    const png = await render(editor, scale)
    if (png) items.push({ key, png })
  }
  loadSnapshot(editor.store, before)
  postToNative({ type: 'exported', items })
}

/// Keyboard shortcuts (tldraw's own are part of the UI we hide) and tool state for the native toolbar.
const Hotkeys = track(function Hotkeys({ scaleRef }: { scaleRef: { current: number } }) {
  const editor = useEditor()
  const tool = activeTool(editor)
  const color = editor.getStyleForNextShape(DefaultColorStyle)

  useEffect(() => {
    postToNative({ type: 'tool', tool, color })
  }, [tool, color])

  // Keep the image fitted when the window is resized.
  useEffect(() => {
    const refit = () => editor.setCamera(editor.getCamera(), { reset: true })
    window.addEventListener('resize', refit)
    return () => window.removeEventListener('resize', refit)
  }, [editor])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const editing = editor.getEditingShapeId() !== null
      const mod = e.metaKey || e.ctrlKey
      if (e.key === 'Escape' && !editing) {
        e.preventDefault()
        cancel(editor, scaleRef.current)
        return
      }
      if (e.key === 'Enter' && mod) {
        e.preventDefault()
        if (editing) editor.setEditingShape(null)
        finish(editor, scaleRef.current)
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
