// What part of the image the editor shows. The host owns the zoom: it moves the frame and sends
// the picture it wants painted, and the page draws that picture and says when it has. The zoom
// keys are collected here and passed straight to the host; the wheel and the pinch never reach
// the page.

import { useEffect } from 'react'
import { Editor } from 'tldraw'
import { PageRect, ViewRequest, ViewResult, ZoomAnchor, postToNative } from './bridge'
import { IMAGE_ID } from './canvas'
import { ZOOM_STEP } from './config'

/// How long a frame may take before `setView` stops waiting for it. WebKit pauses frame callbacks
/// while the window is hidden or the screen is locked, and `setView` runs in the canvas queue: a
/// wait that never ends there would hold every later load, park and build.
const VIEW_FRAME_TIMEOUT_MS = 100

/**
 * Where the image is drawn inside the editor, in the editor's own points (x and y from its top
 * left), as the host last asked; null while the image is fitted to the editor. The host draws its
 * own copy of this rect while a zoom is moving, so this is the whole of what the page is told
 * about a zoom.
 */
let view: PageRect | null = null

/// The next frame, or `timeoutMs` later when frames are paused (a hidden window, a locked screen).
function nextFrame(timeoutMs: number): Promise<void> {
  return new Promise((resolve) => {
    let done = false
    const once = () => {
      if (done) return
      done = true
      resolve()
    }
    requestAnimationFrame(once)
    setTimeout(once, timeoutMs)
  })
}

/**
 * Puts the editor at `frame` inside the page. The page itself is laid out by the host at the
 * whole room the annotator's frame may grow within, so a zoom never resizes it; the editor is the
 * frame's part of it, sized here in the same turn as the camera is set, so one paint carries both.
 */
export function placeEditor(frame: PageRect) {
  const el = document.querySelector<HTMLElement>('.editor')
  if (!el) return
  el.style.left = `${frame.x}px`
  el.style.top = `${frame.y}px`
  el.style.width = `${frame.width}px`
  el.style.height = `${frame.height}px`
}

/**
 * Draws the view the host asked for and answers once it is painted: the editor at the frame and
 * the image at its rect. The host takes its own copy of the picture away when this answers.
 */
export async function setView(editor: Editor, request: ViewRequest): Promise<ViewResult | null> {
  // Eight numbers from the host, checked before they reach the camera: one that is not finite
  // moves the camera where nothing can bring it back, and an empty rect has no scale. Answering
  // null leaves the camera where it was; the host logs the refusal and takes its stand-in down
  // anyway, since a picture that never leaves covers a live editor.
  const { frame, image } = request
  const numbers = [frame.x, frame.y, frame.width, frame.height, image.x, image.y, image.width, image.height]
  if (!numbers.every(Number.isFinite) || frame.width <= 0 || frame.height <= 0 || image.width <= 0 || image.height <= 0) return null
  placeEditor(frame)
  view = { x: image.x - frame.x, y: image.y - frame.y, width: image.width, height: image.height }
  applyView(editor)
  // Two frames: the first carries this camera into a paint, the second has been on screen.
  await nextFrame(VIEW_FRAME_TIMEOUT_MS)
  await nextFrame(VIEW_FRAME_TIMEOUT_MS)
  const box = editor.getContainer().getBoundingClientRect()
  const painted = imageRect(editor)
  return {
    width: box.width,
    height: box.height,
    image: painted ? { x: box.left + painted.x, y: box.top + painted.y, width: painted.width, height: painted.height } : { x: 0, y: 0, width: 0, height: 0 },
  }
}

/// Where the image is drawn, in the editor's points, from the camera as it is now.
function imageRect(editor: Editor): PageRect | null {
  const bounds = editor.getShapePageBounds(IMAGE_ID)
  if (!bounds) return null
  const { x, y, z } = editor.getCamera()
  return { x: (bounds.x + x) * z, y: (bounds.y + y) * z, width: bounds.w * z, height: bounds.h * z }
}

/**
 * Puts the stored view on the camera: the image at its rect inside the editor, or fitted when the
 * host has not asked for one. Idempotent, and the resize observer runs it too, so it does not
 * matter whether the host's call or the layout reaches tldraw first.
 */
export function applyView(editor: Editor) {
  const bounds = editor.getShapePageBounds(IMAGE_ID)
  if (!bounds) return
  editor.updateViewportScreenBounds(editor.getContainer())
  if (!view) {
    editor.setCamera(editor.getCamera(), { reset: true })
    return
  }
  const z = view.width / bounds.w
  editor.setCamera({ x: view.x / z - bounds.x, y: view.y / z - bounds.y, z })
}

export function fitCamera(editor: Editor, w: number, h: number) {
  view = null
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

/// Where the cursor is as a fraction of the window: what the host and the camera both hold in
/// place while zooming. The viewport is the window, so the same fraction reads in either space.
export function cursorAnchor(editor: Editor, e: MouseEvent): ZoomAnchor {
  const { x, y, w, h } = editor.getViewportScreenBounds()
  return { x: (e.clientX - x) / w, y: (e.clientY - y) / h }
}

/// The host takes a wheel with cmd or ctrl held, and the trackpad pinch, before WebKit sees them.
/// These are the leftovers if one gets through: swallowed, so tldraw's own zoom never runs. A plain
/// wheel still pans.
export function useZoomWheel(editor: Editor) {
  useEffect(() => {
    const swallow = (e: Event) => {
      if (e instanceof WheelEvent && !e.ctrlKey && !e.metaKey) return
      e.preventDefault()
      e.stopPropagation()
    }
    const events = ['wheel', 'gesturestart', 'gesturechange', 'gestureend']
    for (const g of events) window.addEventListener(g, swallow, { capture: true, passive: false })
    return () => {
      for (const g of events) window.removeEventListener(g, swallow, { capture: true })
    }
  }, [editor])
}

/// Cmd+plus, cmd+minus and cmd+0, sent to the host as a zoom. True when this was one of them.
export function zoomByKey(e: KeyboardEvent, mod: boolean): boolean {
  if (!mod || (e.key !== '=' && e.key !== '+' && e.key !== '-' && e.key !== '0')) return false
  e.preventDefault()
  // tldraw binds these too, on the document; stopping here keeps its camera zoom out of it.
  e.stopPropagation()
  // No anchor: a keyboard step zooms about the window's middle, as Preview does.
  postToNative({ type: 'zoom', factor: e.key === '0' ? null : e.key === '-' ? 1 / ZOOM_STEP : ZOOM_STEP, at: null })
  return true
}
