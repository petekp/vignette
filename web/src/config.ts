// The editor's knobs. Tool ids map to tldraw tools; `geo` picks the shape for the geo tool.

export const TOOLS = [
  { id: 'select', label: 'Select', key: 'V', tool: 'select' },
  { id: 'ellipse', label: 'Circle', key: 'O', tool: 'geo', geo: 'ellipse' },
  { id: 'rectangle', label: 'Rectangle', key: 'R', tool: 'geo', geo: 'rectangle' },
  { id: 'arrow', label: 'Arrow', key: 'A', tool: 'arrow' },
  { id: 'text', label: 'Text', key: 'T', tool: 'text' },
] as const
export type ToolId = (typeof TOOLS)[number]['id']

/// Tool active when the editor opens.
export const DEFAULT_TOOL: ToolId = 'ellipse'

/// tldraw color names, shown as swatches left to right. The first is the default.
export const COLORS = ['red', 'yellow', 'light-blue'] as const

/// tldraw stroke size for new shapes: 's' | 'm' | 'l' | 'xl'.
export const DEFAULT_SIZE = 'm'
