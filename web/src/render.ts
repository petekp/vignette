// Every operation that borrows the canvas to make a picture: the export and the card previews, the
// zoom overlay, and an agent's pushed marks. Each of them loads shapes the user never asked for and
// puts back what it found, which is why they all run in the canvas queue.

import { Box, Editor, TLImageShape, TLShapeId, createShapeId, getSnapshot, loadSnapshot, toRichText } from 'tldraw'
import { ExportItem, ExportResult, LoadPayload, Mark, ParkResult, postToNative } from './bridge'
import { IMAGE_ID, beginQuiet, endQuiet, fileUrl, hasAnnotations, imageFrame, placeImage, quietly, silently } from './canvas'
import { applyColors } from './colors'
import { CANDIDATES, ColorId, DEFAULT_SIZE, DEFAULT_TEXT_POINTS, PUSHED_TEXT_MARGIN, PUSHED_TEXT_MIN_WIDTH, PUSHED_TEXT_SIZE } from './config'
import { prepareSample } from './contrast'

/// How long a rendering waits for a font it embeds the first time; see `waitForEmbeddedFonts`.
const FONT_RASTER_MS = 250

/// The scale a rendering is made at: the image's own, cut back so its longest side stays within
/// `maxPixel`. `w` and `h` are the picture's size in canvas points.
export function cappedScale(scale: number, maxPixel: number, w: number, h: number) {
  return Math.min(scale, maxPixel / Math.max(w, h))
}

/// The image with its annotations, as a PNG data URL. `scale` maps canvas points to output pixels.
/// The screenshot is drawn straight onto a canvas and only the annotations go through tldraw's
/// SVG export. WebKit loads raster images embedded in an SVG asynchronously, so an SVG that
/// carries the screenshot rasterizes blank unless it is small; tldraw's own toImage hits that.
export async function render(editor: Editor, scale: number) {
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
export async function overlay(editor: Editor, maxPixel: number): Promise<string | null> {
  const bounds = editor.getShapePageBounds(IMAGE_ID)
  if (!bounds || !hasAnnotations(editor)) return null
  const scale = cappedScale(window.devicePixelRatio || 1, maxPixel, bounds.w, bounds.h)
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
/// image on the canvas, which `canvasKey` names, is rendered from what is there rather than from
/// the host's copy of its draft. Undo history is left as it was. A failure stops the run and is
/// reported; whatever rendered before it is returned.
export function exportDrafts(editor: Editor, items: ExportItem[], scale: number, canvasKey: string | null): Promise<ExportResult> {
  return quietly(() => exportDraftsQuietly(editor, items, scale, canvasKey))
}

async function exportDraftsQuietly(editor: Editor, items: ExportItem[], scale: number, canvasKey: string | null): Promise<ExportResult> {
  const before = getSnapshot(editor.store)
  const selected = editor.getSelectedShapeIds()
  const rendered: { key: string; png: string }[] = []
  let error: string | null = null
  try {
    for (const item of items) {
      const snapshot = item.key === canvasKey ? before : item.snapshot
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

/// An agent's marks as a draft, with the editor never shown: the image and the marks go on the
/// canvas, the snapshot and a rendering come back, and whatever the canvas held is put back. The
/// host stores the result, so the card shows the marks and Copy Drawing has them before anyone
/// opens the editor. `p.snapshot` is the image's existing draft, so marks add to it.
export async function build(editor: Editor, p: LoadPayload, marks: Mark[]): Promise<ParkResult> {
  const before = getSnapshot(editor.store)
  const selected = editor.getSelectedShapeIds()
  const { w, h, ratio } = imageFrame(p)
  beginQuiet()
  try {
    let made: { unnamed: TLShapeId[]; texts: PushedText[] } = { unnamed: [], texts: [] }
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
    const overflowing = texts.length ? await fitTextsInside(editor, texts, image) : []
    // The export and the card's preview both take tldraw's SVG within the image's bounds, so a box
    // that reaches past it is cut everywhere the mark is seen. The host cannot tell from `ok` that
    // it happened, and the agent that sent the mark cannot either, so it is said here.
    if (overflowing.length) {
      postToNative({
        type: 'log',
        message: `pushed text too long for this image: mark ${overflowing.join(', ')} is cut off at its edge`,
      })
    }
    // The snapshot is stored as it stands, so the colours are picked before it is taken.
    if (unnamed.length) {
      // A screenshot that will not decode leaves no sample: the marks keep the colour they were
      // given, and the draft is still stored. Losing an agent's marks over a colour is not a trade.
      await prepareSample(p.key, fileUrl(p.key)).catch(() => {})
      applyColors(editor, p.key, unnamed)
    }
    const snapshot = getSnapshot(editor.store)
    const preview = await render(editor, cappedScale(ratio, p.previewMaxPixel, w, h))
    return { snapshot, preview }
  } finally {
    silently(editor, () => {
      loadSnapshot(editor.store, before)
      editor.setSelectedShapes(selected)
    })
    endQuiet()
  }
}

/// A pushed text mark on the canvas: the shape, which mark it came from (counted from 1, the way
/// `invalid-marks` counts them), and the scale its box is drawn at, which turns a width in canvas
/// points into the `w` the shape carries.
type PushedText = { id: TLShapeId; mark: number; scale: number }

/// The room a pushed text has to sit in: the image less `PUSHED_TEXT_MARGIN` on every side. The
/// margin is a fraction of the image's width on all four edges, so the inset is the same number of
/// points all round rather than the same fraction of two sides of different lengths. On an image
/// wider than it is tall that leaves less of the height than of the width, which is why a box is
/// measured against this rather than against the image.
function textRoom(image: Box): Box {
  const margin = PUSHED_TEXT_MARGIN * image.w
  return new Box(image.x + margin, image.y + margin, image.w - 2 * margin, image.h - 2 * margin)
}

/// An agent's marks as ordinary shapes, in canvas points: `image` is the box the screenshot
/// occupies, and every mark number is a fraction of it. The host has already checked the numbers
/// and the color.
function createMarks(editor: Editor, marks: Mark[], image: Box): { unnamed: TLShapeId[]; texts: PushedText[] } {
  const unnamed: TLShapeId[] = []
  const texts: PushedText[] = []
  const margin = PUSHED_TEXT_MARGIN * image.w
  for (const [index, m] of marks.entries()) {
    const x = image.x + m.x * image.w
    const y = image.y + m.y * image.h
    const color = (m.color ?? CANDIDATES[0].id) as ColorId
    // A mark that names a colour keeps it; one that names none is the heuristic's to colour.
    // `agent` says who drew it: a reopen never selects an agent's mark as if it were the user's own.
    const meta = { agent: true, ...(m.color ? { colorChosen: true } : {}) }
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
      texts.push({ id, mark: index + 1, scale })
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

/// How many times a box is widened and measured again. Wrapping is discrete — a pass can land a
/// word short of the line it aimed for — so the first estimate is checked rather than trusted.
/// Each pass costs one measurement, and four reach the room's width from any box this can make.
const TEXT_FIT_PASSES = 4

/// Widens one text box until its words wrap short enough to fit the room's height, so a long
/// sentence becomes a wide block rather than a column running off the bottom edge. The box's area
/// is roughly what the sentence needs at its font size, so the width the height wants is about
/// `w * h / room.h`; wrapping makes that an estimate, which is what the passes are for. The width
/// stops at the room's own, the widest a box can be and still sit inside the image.
///
/// A box still too tall at that width is a sentence this image has no room for. Nothing here can
/// fix that, so it is left as wide as it can be — the most of it that can show — and the caller
/// reports it rather than letting `[add] ok` stand for a mark the picture cut in half.
function widenToFit(editor: Editor, text: PushedText, room: Box) {
  if (room.w <= 0 || room.h <= 0) return
  for (let pass = 0; pass < TEXT_FIT_PASSES; pass++) {
    const bounds = editor.getShapePageBounds(text.id)
    if (!bounds || bounds.h <= room.h) return
    const wanted = Math.min(room.w, (bounds.w * bounds.h) / room.h)
    // Within a point of the width it already has: no later pass can widen it either, because the
    // room is the limit or the estimate has converged.
    if (wanted <= bounds.w + 1) return
    editor.updateShape({ id: text.id, type: 'text', props: { w: wanted / text.scale } })
  }
}

/// Fits pushed text marks inside the image: each box is first widened until its wrapped height has
/// room, then moved so the whole of it is inside. How wide the font draws a sentence and where it
/// wraps are neither of them things the agent that sent the mark can know, so every box is measured
/// once it exists rather than predicted.
///
/// Returns the marks whose box still reaches past the image after both — a sentence too long for
/// this picture at this font size.
///
/// The measure needs the font the text is drawn in. A page that has not drawn text yet has not
/// loaded it, and measures the fallback instead, so the wait comes first: it is the font already
/// in `web/dist`, and every later push finds it loaded.
async function fitTextsInside(editor: Editor, texts: PushedText[], image: Box): Promise<number[]> {
  await editor.fonts.loadRequiredFontsForCurrentPage()
  const room = textRoom(image)
  const margin = PUSHED_TEXT_MARGIN * image.w
  const overflowing: number[] = []
  silently(editor, () => {
    for (const text of texts) {
      widenToFit(editor, text, room)
      const bounds = editor.getShapePageBounds(text.id)
      const shape = editor.getShape(text.id)
      if (!bounds || !shape) continue
      if (bounds.w > image.w || bounds.h > image.h) overflowing.push(text.mark)
      // A box with no room to spare in a direction is put against the image's own edge in that
      // direction rather than the margin's: the margin is room to spare, and a box that already
      // fitted the image exactly — a caption asked for at the full width — must not be pushed out
      // of it by being given room it has not got. A box bigger than the image itself keeps its
      // start showing, which is what the low bound wins.
      const insetX = bounds.w <= room.w ? margin : 0
      const insetY = bounds.h <= room.h ? margin : 0
      const x = within(bounds.x, image.x + insetX, image.x + image.w - insetX - bounds.w)
      const y = within(bounds.y, image.y + insetY, image.y + image.h - insetY - bounds.h)
      if (x === bounds.x && y === bounds.y) continue
      editor.updateShape({ id: text.id, type: 'text', x: shape.x + (x - bounds.x), y: shape.y + (y - bounds.y) })
    }
  })
  return overflowing
}

/// `value` between the two, `low` winning when the box is bigger than the room between them.
function within(value: number, low: number, high: number) {
  return Math.min(Math.max(value, low), Math.max(low, high))
}
