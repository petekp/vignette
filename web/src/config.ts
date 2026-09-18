// The editor's knobs. Tool ids map to tldraw tools; `geo` picks the shape for the geo tool.
// `symbol` is the SF Symbol the host draws in its native toolbar; `key` is the shortcut in the editor.

export const TOOLS = [
  { id: 'select', label: 'Select', key: 'v', symbol: 'cursorarrow', tool: 'select' },
  { id: 'rectangle', label: 'Rectangle', key: 'r', symbol: 'rectangle', tool: 'geo', geo: 'rectangle' },
  { id: 'arrow', label: 'Arrow', key: 'a', symbol: 'arrow.up.right', tool: 'arrow' },
  { id: 'text', label: 'Text', key: 't', symbol: 'textformat', tool: 'text' },
] as const
export type ToolId = (typeof TOOLS)[number]['id']

/// Tool active when an image opens for the first time.
export const DEFAULT_TOOL: ToolId = 'rectangle'
/// Tool active when an image that already has annotations reopens: the first click lands on the
/// work that is there instead of drawing over it.
export const REOPEN_TOOL: ToolId = 'select'

/// tldraw color names with the hex the host shows as swatches, left to right. The first is the default.
export const COLORS = [
  { id: 'red', hex: '#e03131' },
  { id: 'yellow', hex: '#ffc034' },
  { id: 'light-blue', hex: '#4dabf7' },
] as const
export type ColorId = (typeof COLORS)[number]['id']

/// tldraw stroke size for new shapes: 's' | 'm' | 'l' | 'xl'.
export const DEFAULT_SIZE = 'm'
