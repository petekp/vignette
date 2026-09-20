// The canvas everything on this page shares: which shape the screenshot is, the queue the
// operations that stand it on its head take their turn in, and the two brackets that keep their
// own changes out of undo history and out of the drafts the host is sent.

import { AssetRecordType, Editor, TLShapeId, createShapeId, loadSnapshot } from 'tldraw'
import { LoadPayload } from './bridge'

export const IMAGE_ID: TLShapeId = createShapeId('screenshot')

/// Asset `src` values are file paths; the host serves them from the page's own origin, under the
/// same per-launch token as the page, so a snapshot saved in one launch resolves in the next.
export function fileUrl(path: string) {
  return location.origin + location.pathname.replace(/[^/]*$/, 'file?p=' + encodeURIComponent(path))
}

export function hasAnnotations(editor: Editor) {
  return editor.getCurrentPageShapeIds().size > 1
}

/// Runs `fn` without touching undo history: loading a snapshot otherwise records an undo entry.
export function silently(editor: Editor, fn: () => void) {
  editor.run(fn, { history: 'ignore' })
}

/// Above zero while `load`, `export`, `build` or the colour pass mutate the store, so those
/// changes are not reported as drafts. A count rather than a flag: `load` stays quiet for two
/// frames after its queue slot ends, and an export queued behind it must not be unquieted when
/// those frames pass.
let quietDepth = 0

export function isQuiet() {
  return quietDepth > 0
}

/// The halves of `quietly` for a caller that does not end where it started: a load goes quiet in
/// its queue slot and comes back two frames later.
export function beginQuiet() {
  quietDepth++
}

export function endQuiet() {
  quietDepth--
}

/// Runs `fn` with store changes not reported as drafts. Spans the whole operation, not just the
/// mutating calls: tldraw delivers a snapshot load's changes to listeners on the next transaction,
/// which for `load` is the camera fit one frame later.
export async function quietly<T>(fn: () => Promise<T>): Promise<T> {
  beginQuiet()
  try {
    return await fn()
  } finally {
    endQuiet()
  }
}

/// The operations that stand the canvas on its head run one at a time, in the order the host
/// called them. Each takes its snapshot after an await, so another one's shapes must never land in
/// between: `park` would store them, and `export` and `build` would wipe them when they put the
/// canvas back.
let queueTail: Promise<unknown> = Promise.resolve()
export function oneAtATime<T>(work: () => Promise<T>): Promise<T> {
  const next = queueTail.then(work, work)
  queueTail = next.catch(() => {})
  return next
}

/// The size the screenshot is drawn at, in canvas points, and the ratio that turns those points
/// back into its pixels. The shape is sized in points so the canvas matches the window; a
/// rendering scales back up.
export function imageFrame(p: LoadPayload) {
  const ratio = window.devicePixelRatio || 1
  return { w: p.pixelWidth / ratio, h: p.pixelHeight / ratio, ratio }
}

/// The screenshot on an empty canvas, or the draft the host stored for it, which carries the image
/// shape with it. The caller owns `quiet`, the camera, and `currentKey`, and runs this silently.
export function placeImage(editor: Editor, p: LoadPayload, w: number, h: number) {
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

/// Every shape and asset, gone. The image shape is locked, so it is unlocked first.
export function removeAll(editor: Editor) {
  const ids = [...editor.getCurrentPageShapeIds()]
  if (ids.length) {
    editor.updateShapes(ids.map((id) => ({ id, type: editor.getShape(id)!.type, isLocked: false })))
    editor.deleteShapes(ids)
  }
  const assets = editor.getAssets().map((a) => a.id)
  if (assets.length) editor.deleteAssets(assets)
}
