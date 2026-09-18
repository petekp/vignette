// Messages between the tldraw page and the Swift host.

import type { TLEditorSnapshot } from 'tldraw'

/** Goes up with any change to this contract; the host refuses a page built for another version. */
export const PROTOCOL = 8

export interface LoadPayload {
  /** Identifies the image's draft: its file path. Also the asset `src` the page resolves to a URL. */
  key: string
  mimeType: string
  pixelWidth: number
  pixelHeight: number
  viewWidth: number
  viewHeight: number
  /** The image's draft as the host stored it, or null for a fresh canvas. */
  snapshot: TLEditorSnapshot | null
}

/**
 * The picture the page draws when a zoom comes to rest. `ratio` is how far the image is magnified
 * inside the window (1 fits it); `x` and `y` are the middle of the visible part, as fractions of
 * the image; `width` and `height` are the size the host has laid the window out at, which the page
 * waits for before it applies the view.
 */
export interface ViewRequest {
  ratio: number
  x: number
  y: number
  width: number
  height: number
}

/** What the page painted, once it has: the size it used, the magnification it ended up at, and
 *  how many frames it waited for the host's resize to reach this process. */
export interface ViewResult {
  width: number
  height: number
  ratio: number
  waited: number
}

/**
 * One annotation an agent supplied with `add?marks=`. Every number is a fraction of the image:
 * `x` and `y` from its top-left corner, `w` and `h` of its size, `x2` and `y2` where an arrow
 * points. `build` turns these into ordinary shapes, which the user then edits like their own.
 */
export interface Mark {
  type: 'ellipse' | 'rectangle' | 'arrow' | 'text'
  x: number
  y: number
  w?: number
  h?: number
  x2?: number
  y2?: number
  text?: string
  /** A color id from config.ts; the first color when absent. */
  color?: string
}

/** A point zoom keeps in place: a fraction of the window, x from the left and y from the top. */
export interface ZoomAnchor { x: number; y: number }

export interface ToolInfo { id: string; label: string; key: string; symbol: string }
export interface ColorInfo { id: string; hex: string }

/** What `park` returns: the annotations to store (null when there are none) and a rendering when they changed. */
export interface ParkResult {
  snapshot: TLEditorSnapshot | null
  preview: string | null
}

export interface ExportItem { key: string; snapshot: TLEditorSnapshot }
/** What `export` returns: the renderings that succeeded, and the error that stopped the run, if any. */
export interface ExportResult {
  items: { key: string; png: string }[]
  error: string | null
}

type NativeMessage =
  /** The editor is mounted. Carries the protocol version and what the host's toolbar should offer. */
  | { type: 'ready'; protocol: number; tools: ToolInfo[]; colors: ColorInfo[] }
  /** The active tool or color changed. */
  | { type: 'tool'; tool: string | null; color: string }
  /** The image from `load` is on the canvas. */
  | { type: 'loaded'; key: string }
  /** Finished. `png` is the rendering, or null when nothing was drawn: the host copies the original. */
  | { type: 'done'; png: string | null }
  | { type: 'cancel' }
  | { type: 'log'; message: string }
  /** The current image's annotations changed; null means they were all removed. Sent shortly after each change. */
  | { type: 'draft'; key: string; snapshot: TLEditorSnapshot | null }
  /**
   * Zoom is the host's: it resizes the window. `factor` multiplies the current size; null asks for
   * the fitted size. `at` is the cursor, whose point both sides keep in place; null (the keyboard)
   * means the window's middle.
   */
  | { type: 'zoom'; factor: number | null; at: ZoomAnchor | null }

declare global {
  interface Window {
    shotnote?: {
      load(payload: LoadPayload): void
      /** The current draft for the host to store, with a preview when it changed. Does not clear the canvas. */
      park(): Promise<ParkResult>
      /** Clears the canvas. Call `park` first to keep the annotations. */
      reset(): void
      /**
       * An agent's marks as a draft, without the editor being shown: the shapes go on the canvas,
       * the snapshot and a rendering come back, and whatever was on the canvas is put back.
       */
      build(payload: LoadPayload, marks: Mark[]): Promise<ParkResult>
      /** Renders each item's draft to PNG. */
      export(items: ExportItem[]): Promise<ExportResult>
      /**
       * The current image's annotations alone, on a transparent canvas covering the image, as a
       * PNG data URL; null when nothing is drawn. `maxPixel` caps its longest side. The host lays
       * it over the screenshot while a zoom is moving.
       */
      overlay(maxPixel: number): Promise<string | null>
      setTool(id: string): void
      setColor(id: string): void
      /**
       * Draws the exact picture the host's zoom stand-in is showing, and answers once it has been
       * painted: the host waits for that answer before it takes the stand-in away.
       */
      setView(view: ViewRequest): Promise<ViewResult | null>
      /** Exports the current image and replies with `done`. */
      finish(): void
    }
    webkit?: { messageHandlers?: { shotnote?: { postMessage(msg: NativeMessage): void } } }
  }
}

export function postToNative(msg: NativeMessage) {
  const handler = window.webkit?.messageHandlers?.shotnote
  if (handler) handler.postMessage(msg)
  else console.log('[shotnote → native]', msg)
}
