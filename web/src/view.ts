// What part of the image the window shows. The host owns the zoom: it moves the window and sends
// the picture it wants painted, and the page draws that picture and says when it has. The wheel,
// the pinch and the zoom keys are collected here and passed straight to the host.

import { useEffect } from 'react'
import { Editor } from 'tldraw'
import { ViewRequest, ViewResult, ZoomAnchor, postToNative } from './bridge'
import { IMAGE_ID } from './canvas'
import { WHEEL_ZOOM_RATE, ZOOM_STEP } from './config'

/// How many frames `setView` waits for the host's resize to reach this process before it draws.
const VIEW_FRAMES = 20
/// How long one of those frames may take before `setView` stops waiting for it. WebKit pauses
/// frame callbacks while the window is hidden or the screen is locked, and `setView` runs in the
/// canvas queue: a wait that never ends there would hold every later load, park and build.
const VIEW_FRAME_TIMEOUT_MS = 100

/**
 * The picture the host last asked for: how far the image is magnified inside the window, and the
 * middle of the part that is visible, as fractions of the image. The host holds the same three
 * numbers and draws its own copy of this picture while a zoom is moving, so this is the whole of
 * what the page is told about a zoom.
 */
let view = { ratio: 1, x: 0.5, y: 0.5 }

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
 * Draws the view the host asked for and answers once it is painted. The host has already laid the
 * window out at `width` by `height`; that resize crosses a process boundary, so the page waits for
 * it to arrive rather than drawing this camera at the old size. The host takes its own copy of the
 * picture away when this answers.
 */
export async function setView(editor: Editor, request: ViewRequest): Promise<ViewResult | null> {
  // Five numbers from the host, checked before they reach the camera: a ratio below 1 would zoom
  // the image out of a window sized to fit it, and one number that is not finite moves the camera
  // where nothing can bring it back. Answering null leaves the camera where it was; the host logs
  // the refusal and takes its stand-in down anyway, since a picture that never leaves covers a
  // live editor.
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
    await nextFrame(VIEW_FRAME_TIMEOUT_MS)
  }
  applyView(editor)
  // Two frames: the first carries this camera into a paint, the second has been on screen.
  await nextFrame(VIEW_FRAME_TIMEOUT_MS)
  await nextFrame(VIEW_FRAME_TIMEOUT_MS)
  const box = container.getBoundingClientRect()
  return { width: box.width, height: box.height, ratio: editor.getZoomLevel() / editor.getBaseZoom(), waited }
}

/**
 * Puts the stored view on the camera: the image magnified by `ratio` with the point it names in
 * the middle of the window. Idempotent, and the resize observer runs it too, so it does not matter
 * whether the host's call or the resize reaches the page first.
 */
export function applyView(editor: Editor) {
  const bounds = editor.getShapePageBounds(IMAGE_ID)
  if (!bounds) return
  editor.updateViewportScreenBounds(editor.getContainer())
  const z = editor.getBaseZoom() * view.ratio
  const { w, h } = editor.getViewportScreenBounds()
  editor.setCamera({ x: w / 2 / z - (bounds.x + view.x * bounds.w), y: h / 2 / z - (bounds.y + view.y * bounds.h), z })
}

export function fitCamera(editor: Editor, w: number, h: number) {
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

/// Where the cursor is as a fraction of the window: what the host and the camera both hold in
/// place while zooming. The viewport is the window, so the same fraction reads in either space.
export function cursorAnchor(editor: Editor, e: MouseEvent): ZoomAnchor {
  const { x, y, w, h } = editor.getViewportScreenBounds()
  return { x: (e.clientX - x) / w, y: (e.clientY - y) / h }
}

/// A pinch arrives as a wheel event with ctrlKey; cmd+wheel zooms too. Both go to the host,
/// coalesced to one message per frame, and never reach tldraw's own zoom. Plain wheel still pans.
/// Each message carries where the cursor was, so the host and the camera hold that point.
export function useZoomWheel(editor: Editor) {
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
