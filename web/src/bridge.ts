// Messages between the tldraw page and the Swift host.

import type { TLEditorSnapshot } from 'tldraw'

/** Goes up with any change to this contract; the host refuses a page built for another version. */
export const PROTOCOL = 4

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
  | { type: 'done'; png: string }
  | { type: 'cancel' }
  | { type: 'log'; message: string }
  /** The current image's annotations changed; null means they were all removed. Sent shortly after each change. */
  | { type: 'draft'; key: string; snapshot: TLEditorSnapshot | null }
  /** Zoom is the host's: it resizes the window. `factor` multiplies the current size; null asks for the fitted size. */
  | { type: 'zoom'; factor: number | null }

declare global {
  interface Window {
    shotnote?: {
      load(payload: LoadPayload): void
      /** The current draft for the host to store, with a preview when it changed. Does not clear the canvas. */
      park(): Promise<ParkResult>
      /** Clears the canvas. Call `park` first to keep the annotations. */
      reset(): void
      /** Renders each item's draft to PNG. */
      export(items: ExportItem[]): Promise<ExportResult>
      setTool(id: string): void
      setColor(id: string): void
      /** Magnifies the image inside the window once the window cannot grow; 1 fits the image. */
      setCanvasZoom(ratio: number): void
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
