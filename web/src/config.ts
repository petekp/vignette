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

/// Every colour a mark may be: what the heuristic picks from, in order, and what an agent's
/// `marks=` may name. It keeps the first one far enough from the pixels under it, so red only
/// gives way over a red or a washed-out region. The first is also what a fresh image opens on.
/// The hexes are tldraw's dark-theme strokes, which is what the editor draws, so the measure uses
/// the colour the user sees (`black` is not among them: in that theme it renders near white).
export const CANDIDATES = [
  { id: 'red', hex: '#e03131' },
  { id: 'yellow', hex: '#ffc034' },
  { id: 'light-blue', hex: '#4dabf7' },
  { id: 'white', hex: '#f3f3f3' },
  { id: 'violet', hex: '#ae3ec9' },
] as const
export type ColorId = (typeof CANDIDATES)[number]['id']

/// How far a colour must be from what it covers, as a CIE76 distance in CIELAB (not a WCAG ratio).
/// 55 keeps red over every grey and over white, and moves it off red, dark red, and orange.
/// docs/annotation-colour-2026-09-17.md has the measurements.
export const MIN_COLOR_DISTANCE = 55

/// tldraw stroke size for new shapes: 's' | 'm' | 'l' | 'xl'.
export const DEFAULT_SIZE = 'm'

/// What tldraw draws a text shape at, in canvas points, at `DEFAULT_SIZE` and scale 1: its theme's
/// 16-point base times the multiple it keeps for that size. The multiple is private to tldraw, so
/// it is written here; it moves with `DEFAULT_SIZE` and is checked when tldraw is bumped.
export const DEFAULT_TEXT_POINTS = 24

/// A pushed text mark's font size, as a fraction of the image's width. The image gives a pushed
/// mark its size instead of tldraw's fixed one, so the same sentence covers the same part of a
/// 900-pixel crop as of a 5120-pixel capture. docs/pushed-text-2026-09-19.md has the numbers.
export const PUSHED_TEXT_SIZE = 0.022

/// The room a pushed text mark keeps from the image's edges, as a fraction of the image's width.
/// It is what the default width leaves on the right, and where a box that would run off the image
/// is pulled back to.
export const PUSHED_TEXT_MARGIN = 0.02

/// The narrowest box a pushed text mark falls back to when it names no `w`, as a fraction of the
/// image's width. A mark whose `x` leaves less room than this is pulled left rather than wrapped
/// into a column too narrow to hold a word. A `w` the mark does name is used as it stands.
export const PUSHED_TEXT_MIN_WIDTH = 0.15

/// How far one keyboard zoom step (cmd+plus, cmd+minus) magnifies, as a multiple of the window's
/// current size.
export const ZOOM_STEP = 1.25

