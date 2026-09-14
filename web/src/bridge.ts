// Messages between the tldraw page and the Swift host.

export interface LoadPayload {
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

declare global {
  interface Window {
    shotnote?: { load(payload: LoadPayload): void; reset(): void }
    webkit?: { messageHandlers?: { shotnote?: { postMessage(msg: NativeMessage): void } } }
  }
}

export function postToNative(msg: NativeMessage) {
  const handler = window.webkit?.messageHandlers?.shotnote
  if (handler) handler.postMessage(msg)
  else console.log('[shotnote → native]', msg)
}
