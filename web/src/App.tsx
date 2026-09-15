import { useEffect, useMemo, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
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
import { COLORS, DEFAULT_SIZE, DEFAULT_TOOL, TOOLS, ToolId } from './config'

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
    }
    if (editor && pending.current) {
      loadImage(editor, pending.current, scaleRef)
      pending.current = null
    }
  }, [editor])

  const components = useMemo<TLComponents>(
    () => ({
      ContextMenu: null,
      InFrontOfTheCanvas: () => <Toolbar scaleRef={scaleRef} />,
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
          postToNative({ type: 'ready' })
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

  editor.setStyleForNextShapes(DefaultColorStyle, COLORS[0])
  editor.setStyleForNextShapes(DefaultSizeStyle, DEFAULT_SIZE)
  editor.setStyleForNextShapes(DefaultDashStyle, 'solid')
  editor.setStyleForNextShapes(DefaultFillStyle, 'none')
  selectTool(editor, DEFAULT_TOOL)
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

const Toolbar = track(function Toolbar({ scaleRef }: { scaleRef: { current: number } }) {
  const editor = useEditor()
  const currentTool = editor.getCurrentToolId()
  const currentGeo = editor.getStyleForNextShape(GeoShapeGeoStyle)
  const currentColor = editor.getStyleForNextShape(DefaultColorStyle)
  const activeId: ToolId | null =
    currentTool === 'geo' ? (currentGeo === 'ellipse' ? 'ellipse' : 'rectangle') : (TOOLS.find((t) => t.tool === currentTool)?.id ?? null)

  // Keep the image fitted when the window is resized.
  useEffect(() => {
    const refit = () => editor.setCamera(editor.getCamera(), { reset: true })
    window.addEventListener('resize', refit)
    return () => window.removeEventListener('resize', refit)
  }, [editor])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const editing = editor.getEditingShapeId() !== null
      if (e.key === 'Escape' && !editing) {
        e.preventDefault()
        cancel(editor, scaleRef.current)
      }
      if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
        e.preventDefault()
        if (editing) editor.setEditingShape(null)
        finish(editor, scaleRef.current)
      }
    }
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
  }, [editor, scaleRef])

  // Portaled to the body so tldraw's canvas never swallows its pointer events.
  return createPortal(
    <div className="toolbar" onPointerDown={(e) => e.stopPropagation()}>
      <div className="group">
        {TOOLS.map((t) => (
          <button key={t.id} className="tool" data-active={activeId === t.id} title={`${t.label} (${t.key})`} onClick={() => selectTool(editor, t.id)}>
            <ToolIcon id={t.id} />
          </button>
        ))}
      </div>
      <div className="group">
        {COLORS.map((c) => (
          <button
            key={c}
            className="swatch"
            data-active={currentColor === c}
            data-color={c}
            title={c}
            onClick={() => {
              editor.setStyleForNextShapes(DefaultColorStyle, c)
              if (editor.getSelectedShapeIds().length) editor.setStyleForSelectedShapes(DefaultColorStyle, c)
            }}
          />
        ))}
      </div>
      <div className="group">
        <button className="tool" title="Undo (⌘Z)" disabled={!editor.getCanUndo()} onClick={() => editor.undo()}>
          <ToolIcon id="undo" />
        </button>
        <button className="tool" title="Redo (⇧⌘Z)" disabled={!editor.getCanRedo()} onClick={() => editor.redo()}>
          <ToolIcon id="redo" />
        </button>
      </div>
      <div className="group actions">
        <button className="text" onClick={() => cancel(editor, scaleRef.current)}>
          Cancel
        </button>
        <button className="primary" title="Done (⌘↩)" onClick={() => finish(editor, scaleRef.current)}>
          Copy &amp; Done
        </button>
      </div>
    </div>,
    document.body
  )
})

function ToolIcon({ id }: { id: ToolId | 'undo' | 'redo' }) {
  const p = { fill: 'none', stroke: 'currentColor', strokeWidth: 1.6, strokeLinecap: 'round', strokeLinejoin: 'round' } as const
  switch (id) {
    case 'select':
      return <svg width="18" height="18" viewBox="0 0 18 18"><path {...p} d="M4 3l10 6-4.5 1L7 15z" /></svg>
    case 'ellipse':
      return <svg width="18" height="18" viewBox="0 0 18 18"><ellipse {...p} cx="9" cy="9" rx="6.5" ry="5.5" /></svg>
    case 'rectangle':
      return <svg width="18" height="18" viewBox="0 0 18 18"><rect {...p} x="3" y="4" width="12" height="10" rx="1.5" /></svg>
    case 'arrow':
      return <svg width="18" height="18" viewBox="0 0 18 18"><path {...p} d="M3 15L15 3M8 3h7v7" /></svg>
    case 'text':
      return <svg width="18" height="18" viewBox="0 0 18 18"><path {...p} d="M4 4h10M9 4v10M7 14h4" /></svg>
    case 'undo':
      return <svg width="18" height="18" viewBox="0 0 18 18"><path {...p} d="M6 5L3 8l3 3M3 8h7a4 4 0 010 8H8" /></svg>
    case 'redo':
      return <svg width="18" height="18" viewBox="0 0 18 18"><path {...p} d="M12 5l3 3-3 3M15 8H8a4 4 0 000 8h2" /></svg>
  }
}
