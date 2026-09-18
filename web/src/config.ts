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

/// Whether the toolbar offers the colours. Off, the page sends no swatches in `ready` and the bar
/// is tools, one divider, Done; a mark's colour is then the heuristic's alone (`CANDIDATES` below).
export const SHOW_COLORS = false

/// tldraw color names with the hex the host shows as swatches, left to right. The first is the default.
export const COLORS = [
  { id: 'red', hex: '#e03131' },
  { id: 'yellow', hex: '#ffc034' },
  { id: 'light-blue', hex: '#4dabf7' },
] as const

/// The colours a mark may be drawn in, in order: it keeps the first one far enough from the pixels
/// under it, so red only gives way over a red or a washed-out region. The hexes are tldraw's
/// dark-theme strokes, which is what the editor draws, so the measure uses the colour the user sees
/// (`black` is not among them: in that theme it renders near white).
export const CANDIDATES = [
  { id: 'red', hex: '#e03131' },
  { id: 'yellow', hex: '#ffc034' },
  { id: 'light-blue', hex: '#4dabf7' },
  { id: 'white', hex: '#f3f3f3' },
  { id: 'violet', hex: '#ae3ec9' },
] as const
export type ColorId = (typeof COLORS)[number]['id'] | (typeof CANDIDATES)[number]['id']

/// Every colour a mark may be: what an agent's `marks=` may name and what the heuristic may pick.
/// The swatches are in it whether or not the toolbar shows them.
export const MARK_COLORS = [...CANDIDATES, ...COLORS.filter((c) => !CANDIDATES.some((k) => k.id === c.id))]

/// How far a colour must be from what it covers, as a CIE76 distance in CIELAB (not a WCAG ratio).
/// 55 keeps red over every grey and over white, and moves it off red, dark red, and orange.
/// docs/annotation-colour-2026-09-17.md has the measurements.
export const MIN_COLOR_DISTANCE = 55

/// tldraw stroke size for new shapes: 's' | 'm' | 'l' | 'xl'.
export const DEFAULT_SIZE = 'm'
