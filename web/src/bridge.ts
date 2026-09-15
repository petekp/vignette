// Messages between the tldraw page and the Swift host.

/** Goes up with any change to this contract; the host refuses a page built for another version. */
export const PROTOCOL = 2

export interface LoadPayload {
  /** Identifies the image's draft; the host uses the file path. */
  key: string
  /** Same-origin URL of the image, served by the host's loopback server. */
  imageUrl: string
  mimeType: string
  pixelWidth: number
  pixelHeight: number
  viewWidth: number
  viewHeight: number
}

export interface ToolInfo { id: string; label: string; key: string; symbol: string }
export interface ColorInfo { id: string; hex: string }

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
      setTool(id: string): void
      setColor(id: string): void
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
