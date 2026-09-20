// Which colour each mark is drawn in, once it is on the canvas. `contrast.ts` measures the
// screenshot; this is what asks it, for which marks, and writes the answer back.

import { Box, Editor, HistoryEntry, TLArrowShape, TLRecord, TLShape, TLShapeId } from 'tldraw'
import { IMAGE_ID, beginQuiet, endQuiet, silently } from './canvas'
import { ColorId } from './config'
import { Area, hasSample, pickColor } from './contrast'

/// Marks whose colour the heuristic has not picked for where they now are: drawn, moved, or
/// resized since the last pick. Emptied when the hand lets go, before the draft goes to the host.
const unpicked = new Set<TLShapeId>()

export function clearUnpicked() {
  unpicked.clear()
}

/// Notes the marks a change touched, so their colour is picked again for where they now sit.
export function noteChanged(entry: HistoryEntry<TLRecord>) {
  const changes = entry.changes
  for (const record of Object.values(changes.added)) noteShape(record)
  for (const [, after] of Object.values(changes.updated)) noteShape(after)
  for (const record of Object.values(changes.removed)) if (record.typeName === 'shape') unpicked.delete(record.id)
}

function noteShape(record: TLRecord) {
  if (record.typeName === 'shape' && record.id !== IMAGE_ID) unpicked.add(record.id)
}

/// The colour of every mark that is waiting for one, for the image `key` names. Marks the decode
/// has not caught up with stay in the set, so the next pick colours them.
export function pickColors(editor: Editor, key: string | null) {
  if (!key || !unpicked.size || !hasSample(key)) return
  const ids = [...unpicked]
  unpicked.clear()
  applyColors(editor, key, ids)
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
export function applyColors(editor: Editor, key: string, ids: TLShapeId[]) {
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
  beginQuiet() // the caller reports the draft this belongs to
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
  endQuiet()
}
