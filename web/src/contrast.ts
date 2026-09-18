// Which colour a mark is drawn in, from what it is drawn over. The page holds the screenshot, so
// this is the only side that can see what is under a mark.

import { CANDIDATES, ColorId, MIN_COLOR_DISTANCE } from './config'

/// The screenshot is kept at this long side for sampling. A few hundred pixels is enough to tell
/// one region of a screenshot from another, and the downscale blends text into its background,
/// which is what a mark is really drawn across.
const SAMPLE_LONG_SIDE = 320
/// At most this many sample points across a mark's bounds, each way.
const GRID = 20
/// The share of the sampled pixels allowed to be closer to a colour than `MIN_COLOR_DISTANCE`, so
/// a few stray pixels do not move a mark off red. The mean colour is no use for this: black and
/// white average to a grey that is nothing like either.
const TOLERANCE = 0.1

/// A rectangle over the screenshot, every number a fraction of it.
export interface Rect {
  x: number
  y: number
  w: number
  h: number
}

type Lab = [number, number, number]

let sample: { key: string; w: number; h: number; pixels: Uint8ClampedArray } | null = null
/// Which `prepareSample` call owns `sample`: a second load must not be overwritten by the first
/// one finishing its decode later.
let generation = 0

/// Decodes the screenshot once per load, small, for the picks that follow. A failure leaves no
/// sample, and every mark then keeps the first candidate.
export async function prepareSample(key: string, src: string) {
  const mine = ++generation
  sample = null
  const img = new Image()
  img.src = src
  await img.decode()
  const scale = Math.min(1, SAMPLE_LONG_SIDE / Math.max(img.naturalWidth, img.naturalHeight))
  const w = Math.max(1, Math.round(img.naturalWidth * scale))
  const h = Math.max(1, Math.round(img.naturalHeight * scale))
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d', { willReadFrequently: true })!
  ctx.drawImage(img, 0, 0, w, h)
  if (mine === generation) sample = { key, w, h, pixels: ctx.getImageData(0, 0, w, h).data }
}

export function hasSample(key: string) {
  return sample?.key === key
}

/// The colour a mark should have where it sits: the first candidate far enough from the pixels
/// under it, or the furthest one when none is far enough. Null when there is nothing to measure.
export function pickColor(key: string, rect: Rect): ColorId | null {
  const under = pixelsUnder(key, rect)
  if (!under.length) return null
  let furthest: { id: ColorId; distance: number } | null = null
  for (const candidate of CANDIDATES) {
    const distance = distanceFrom(labOf(candidate.hex), under)
    if (distance >= MIN_COLOR_DISTANCE) return candidate.id
    if (!furthest || distance > furthest.distance) furthest = { id: candidate.id, distance }
  }
  return furthest!.id
}

/// Every candidate with its distance from the pixels under `rect`, for `shotnote://eval`.
export function explain(key: string, rect: Rect) {
  const under = pixelsUnder(key, rect)
  return {
    pixels: under.length,
    min: MIN_COLOR_DISTANCE,
    candidates: CANDIDATES.map((c) => ({ id: c.id, distance: Math.round(distanceFrom(labOf(c.hex), under) * 10) / 10 })),
  }
}

/// A grid of sample points from inside `rect`, clamped to the image, as CIELAB.
function pixelsUnder(key: string, rect: Rect): Lab[] {
  if (!sample || sample.key !== key) return []
  const { w, h, pixels } = sample
  const left = Math.max(0, Math.min(w - 1, Math.floor(rect.x * w)))
  const top = Math.max(0, Math.min(h - 1, Math.floor(rect.y * h)))
  const right = Math.max(left, Math.min(w - 1, Math.ceil((rect.x + rect.w) * w) - 1))
  const bottom = Math.max(top, Math.min(h - 1, Math.ceil((rect.y + rect.h) * h) - 1))
  const cols = Math.min(GRID, right - left + 1)
  const rows = Math.min(GRID, bottom - top + 1)
  const out: Lab[] = []
  for (let row = 0; row < rows; row++) {
    const y = rows === 1 ? top : top + Math.round((row * (bottom - top)) / (rows - 1))
    for (let col = 0; col < cols; col++) {
      const x = cols === 1 ? left : left + Math.round((col * (right - left)) / (cols - 1))
      const i = (y * w + x) * 4
      out.push(toLab(pixels[i], pixels[i + 1], pixels[i + 2]))
    }
  }
  return out
}

/// How far a colour is from the pixels under a mark: the distance the closest `TOLERANCE` of them
/// are within, so a small patch of the colour does not decide the pick on its own.
function distanceFrom(colour: Lab, under: Lab[]): number {
  const distances = under.map((p) => distance(colour, p)).sort((a, b) => a - b)
  return distances[Math.min(distances.length - 1, Math.floor(TOLERANCE * distances.length))]
}

/// CIE76: the straight line between two colours in CIELAB, where equal steps look about equally
/// different. Luminance alone cannot do this job: red on dark grey and red on dark red have the
/// same WCAG ratio to two decimal places, and only one of them is legible.
function distance(a: Lab, b: Lab): number {
  return Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2])
}

const labCache = new Map<string, Lab>()
function labOf(hex: string): Lab {
  let lab = labCache.get(hex)
  if (!lab) {
    const n = parseInt(hex.replace('#', ''), 16)
    lab = toLab((n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff)
    labCache.set(hex, lab)
  }
  return lab
}

/// sRGB to CIELAB, D65.
function toLab(r: number, g: number, b: number): Lab {
  const lr = linear(r)
  const lg = linear(g)
  const lb = linear(b)
  const x = f((0.4124 * lr + 0.3576 * lg + 0.1805 * lb) / 0.95047)
  const y = f(0.2126 * lr + 0.7152 * lg + 0.0722 * lb)
  const z = f((0.0193 * lr + 0.1192 * lg + 0.9505 * lb) / 1.08883)
  return [116 * y - 16, 500 * (x - y), 200 * (y - z)]
}

function linear(c: number) {
  const v = c / 255
  return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
}

function f(t: number) {
  return t > 0.008856 ? Math.cbrt(t) : 7.787 * t + 16 / 116
}
