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
  SVGContainer,
  TLComponents,
  TLShapeId,
  Tldraw,
  createShapeId,
  track,
  useEditor,
} from 'tldraw'
import 'tldraw/tldraw.css'
import { LoadPayload, postToNative } from './bridge'

const IMAGE_ID: TLShapeId = createShapeId('screenshot')
const TOOLS = [
  { id: 'select', label: 'Select', key: 'V', tool: 'select' },
  { id: 'ellipse', label: 'Circle', key: 'O', tool: 'geo', geo: 'ellipse' },
  { id: 'rectangle', label: 'Rectangle', key: 'R', tool: 'geo', geo: 'rectangle' },
  { id: 'arrow', label: 'Arrow', key: 'A', tool: 'arrow' },
  { id: 'text', label: 'Text', key: 'T', tool: 'text' },
] as const
type ToolId = (typeof TOOLS)[number]['id']
const COLORS = ['red', 'yellow', 'light-blue'] as const
const DEFAULT_TOOL: ToolId = 'ellipse'

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
      reset() {
        if (editor) clearCanvas(editor)
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
      InFrontOfTheCanvas: () => (
        <>
          <ImageMask />
          <Toolbar scaleRef={scaleRef} />
        </>
      ),
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
          setEditor(ed)
          postToNative({ type: 'ready' })
        }}
      />
    </div>
  )
}

function loadImage(editor: Editor, p: LoadPayload, scaleRef: { current: number }) {
  clearCanvas(editor)
  // The shape is sized in points so the canvas matches the window; export scales back up to pixels.
  const ratio = window.devicePixelRatio || 1
  const w = p.pixelWidth / ratio
  const h = p.pixelHeight / ratio
  scaleRef.current = ratio

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
  editor.setCamera(editor.getCamera(), { reset: true })

  editor.setStyleForNextShapes(DefaultColorStyle, 'red')
  editor.setStyleForNextShapes(DefaultSizeStyle, 'm')
  editor.setStyleForNextShapes(DefaultDashStyle, 'solid')
  editor.setStyleForNextShapes(DefaultFillStyle, 'none')
  selectTool(editor, DEFAULT_TOOL)
  editor.clearHistory()
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
  const bounds = editor.getShapePageBounds(IMAGE_ID)
  if (!bounds) return postToNative({ type: 'cancel' })
  editor.selectNone()
  const { blob } = await editor.toImage([...editor.getCurrentPageShapeIds()], {
    format: 'png',
    background: true,
    bounds: Box.From(bounds),
    padding: 0,
    scale,
  })
  const png = await blobToDataUrl(blob)
  postToNative({ type: 'done', png })
}

function blobToDataUrl(blob: Blob) {
  return new Promise<string>((resolve, reject) => {
    const r = new FileReader()
    r.onload = () => resolve(String(r.result))
    r.onerror = () => reject(r.error)
    r.readAsDataURL(blob)
  })
}

/// Dims everything outside the image so the export bounds are obvious.
const ImageMask = track(function ImageMask() {
  const editor = useEditor()
  const b = editor.getShapePageBounds(IMAGE_ID)
  if (!b) return null
  const vp = editor.getViewportScreenBounds()
  const tl = editor.pageToViewport({ x: b.minX, y: b.minY })
  const br = editor.pageToViewport({ x: b.maxX, y: b.maxY })
  const d = [
    `M -10 -10 L ${vp.maxX + 10} -10 L ${vp.maxX + 10} ${vp.maxY + 10} L -10 ${vp.maxY + 10} Z`,
    `M ${tl.x} ${tl.y} L ${br.x} ${tl.y} L ${br.x} ${br.y} L ${tl.x} ${br.y} Z`,
  ].join(' ')
  return (
    <SVGContainer className="mask">
      <path d={d} fillRule="evenodd" />
    </SVGContainer>
  )
})

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
        postToNative({ type: 'cancel' })
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

  return (
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
        <button className="text" onClick={() => postToNative({ type: 'cancel' })}>
          Cancel
        </button>
        <button className="primary" title="Done (⌘↩)" onClick={() => finish(editor, scaleRef.current)}>
          Copy &amp; Done
        </button>
      </div>
    </div>
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
