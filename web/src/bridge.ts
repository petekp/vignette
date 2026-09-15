// Messages between the tldraw page and the Swift host.

export interface LoadPayload {
  /** Identifies the image's draft; the host uses the file path. */
  key: string
  dataUrl: string
  pixelWidth: number
  pixelHeight: number
  viewWidth: number
  viewHeight: number
}

type NativeMessage =
  | { type: 'ready' }
  | { type: 'done'; png: string }
  | { type: 'cancel' }
  | { type: 'log'; message: string }
  /** Keys of every image that currently has unsaved annotations. */
  | { type: 'drafts'; keys: string[] }
  /** A rendering of one image with its draft, sent when the draft is parked. */
  | { type: 'draft'; key: string; preview: string }
  /** Result of `window.shotnote.export(keys)`, in the order requested. */
  | { type: 'exported'; items: { key: string; png: string }[] }

declare global {
  interface Window {
    shotnote?: {
      load(payload: LoadPayload): void
      /** Renders and stores the current image's draft; resolves once the `draft` message is posted. */
      park(): Promise<void>
      /** Clears the canvas. Call `park` first to keep the annotations. */
      reset(): void
      /** Drops drafts, e.g. when their files were deleted. */
      forget(keys: string[]): void
      /** Renders each key's draft to PNG and replies with an `exported` message. */
      export(keys: string[]): void
    }
    webkit?: { messageHandlers?: { shotnote?: { postMessage(msg: NativeMessage): void } } }
  }
}

export function postToNative(msg: NativeMessage) {
  const handler = window.webkit?.messageHandlers?.shotnote
  if (handler) handler.postMessage(msg)
  else console.log('[shotnote → native]', msg)
}
