"""Turns a take and beats.toml into the trailer: which frames of the take each output frame shows,
where the camera is, and which caption is up. `cut` renders the pixels; ffmpeg encodes them.

The cut keeps spans of the take and plays each at the take's own speed. A span after the first
dissolves in over the end of the one before, so where the cut skips ahead the picture blends
instead of jumping. The camera and the captions run on the cut's own clock, across spans, so
neither ever jumps: the camera follows each move's target on a spring, keeping its speed when a
new move starts, and a caption turns into the next one.
"""
import bisect
import json
import math
import os
import re
import subprocess
import sys

TIME = re.compile(r'^\s*([\w.]+)\s*(?:([+-])\s*([\d.]+))?\s*$')


def load_take(take):
    with open(os.path.join(take, 'events.json')) as f:
        data = json.load(f)
    if data.get('failed'):
        sys.exit(f'cut: this take failed ({data["failed"]}); record another')
    return data


def list_events(take):
    data = load_take(take)
    events = data['events']
    t0 = events[0]['t'] if events else 0
    for e in events:
        rects = ' '.join(f'{k}={[round(v) for v in r]}' for k, r in e['rects'].items() if r)
        print(f"{e['t'] - t0:8.3f}  {e['name']:<20} {rects}")


class Resolver:
    """Reads the times and rects beats.toml writes against a take's events."""

    def __init__(self, data):
        self.data = data
        self.times = {}
        for e in data['events']:
            # A name logged twice keeps its first time.
            self.times.setdefault(e['name'], e['t'])

    def time(self, expr, beat=None):
        m = TIME.match(str(expr))
        if not m:
            sys.exit(f'cut: cannot read the time {expr!r}')
        name, sign, amount = m.groups()
        if name == 'from' and beat is not None:
            base = self.time(beat['from'])
        elif name in self.times:
            base = self.times[name]
        else:
            sys.exit(f'cut: no event {name!r} in this take; `trailer.py events` lists them')
        return base + (float(amount) * (1 if sign == '+' else -1) if sign else 0)

    def rect(self, spec, t):
        """A rect in screen points: `desktop`, a rect an event recorded, a list of those names for
        the rect around all of them, or [x, y, w]."""
        if isinstance(spec, list) and spec and isinstance(spec[0], str):
            rects = [self.rect(name, t) for name in spec]
            x1, y1 = min(r[0] for r in rects), min(r[1] for r in rects)
            x2, y2 = max(r[0] + r[2] for r in rects), max(r[1] + r[3] for r in rects)
            return [x1, y1, x2 - x1, y2 - y1]
        if isinstance(spec, list):
            x, y, w = spec
            return [x, y, w, w / 1.6]
        if spec == 'desktop':
            return list(self.data['bounds'])
        recorded = [e for e in self.data['events'] if e['rects'].get(spec)]
        if not recorded:
            sys.exit(f'cut: no event recorded a {spec!r} rect')
        before = [e for e in recorded if e['t'] <= t + 1e-6]
        return list((before[-1] if before else recorded[0])['rects'][spec])


def framed(rect, pad, bounds, least):
    """The rect grown by `pad` of its width on every side, made 16:10 around its centre, at least
    `least` points wide, and kept inside `bounds`."""
    x, y, w, h = rect
    grow = pad * w
    x, y, w, h = x - grow, y - grow, w + 2 * grow, h + 2 * grow
    cx, cy = x + w / 2, y + h / 2
    if w / h > 1.6:
        h = w / 1.6
    else:
        w = h * 1.6
    if w < least:
        w, h = least, least / 1.6
    gx, gy, gw, gh = bounds
    if w > gw:
        w, h = gw, gw / 1.6
    if h > gh:
        w, h = gh * 1.6, gh
    x = min(max(cx - w / 2, gx), gx + gw - w)
    y = min(max(cy - h / 2, gy), gy + gh - h)
    return [x, y, w, h]


def ease(u):
    """Ease in and out: a cubic that starts and ends at rest."""
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


# Two critically damped springs in a row, each with this rate over a move's settling time, come
# within 1% of the target at that time and halfway at 0.37 of it.
SETTLE = 10.045


def spring(x, v, target, w, dt):
    """One step of a critically damped spring toward a target that holds still for the step."""
    d = x - target
    e = math.exp(-w * dt)
    return target + (d + (v + w * d) * dt) * e, (v - w * (v + w * d) * dt) * e


def camera_path(moves, times, bounds, least, drift):
    """The camera's rect at each time on the cut's clock. It follows the current move's target with
    two springs in a row, in centre and in the log of the width, so it starts gently, lands
    softly, keeps its speed when the target changes, and zooms at one speed to the eye. While a
    target holds, it creeps in by `rate` of its width a second, up to `most`."""
    def point(rect):
        x, y, w, h = rect
        return [x + w / 2, y + h / 2, math.log(w)]

    first = point(moves[0]['rect'])
    stage1 = [[c, 0.0] for c in first]
    stage2 = [[c, 0.0] for c in first]
    rects, last, index = [], times[0], 0
    for u in times:
        while index + 1 < len(moves) and u >= moves[index + 1]['at']:
            index += 1
        move = moves[index]
        target = point(move['rect'])
        held = max(u - move['at'], 0.0)
        target[2] += math.log(1 - min(drift['rate'] * held, drift['most']))
        w = SETTLE / max(move['ease'], 1e-3)
        steps = 4
        dt = (u - last) / steps
        for _ in range(steps):
            for k in range(3):
                stage1[k] = list(spring(*stage1[k], target[k], w, dt))
                stage2[k] = list(spring(*stage2[k], stage1[k][0], w, dt))
        last = u
        cx, cy, lw = (c[0] for c in stage2)
        width = max(math.exp(lw), least * (1 - drift['most']))
        rects.append(inside([cx - width / 2, cy - width / 3.2, width, width / 1.6], bounds))
    return rects


def inside(rect, bounds, soft=10.0):
    """The rect kept on the desktop. A move started while the camera is still travelling can carry
    it a little past an edge; instead of stopping it dead there, the edge eases it in over about
    `soft` points, with no step in its speed. So a rect flush with an edge sits `soft` * 0.7
    points inside it."""
    x, y, w, h = rect
    bx, by, bw, bh = bounds
    if w > bw:
        w, h = bw, bw / 1.6
    if h > bh:
        w, h = bh * 1.6, bh

    def keep(v, lo, hi):
        def softplus(a):
            return a + math.log1p(math.exp(-a)) if a > 0 else math.log1p(math.exp(a))
        if hi - lo < 4 * soft:
            return min(max(v, lo), hi)
        v = lo + soft * softplus((v - lo) / soft)
        return hi - soft * softplus((hi - v) / soft)

    return [keep(x, bx, bx + bw - w), keep(y, by, by + bh - h), w, h]


def frame_times(movie):
    """The time of every frame the recorder wrote. It writes one only when the screen changes."""
    out = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v', '-show_entries', 'frame=pts_time',
                          '-of', 'csv=p=0', movie], capture_output=True, text=True, check=True).stdout
    return sorted(float(x.strip(',')) for x in out.split() if x.strip(','))


class Edit:
    """The spans the cut keeps, placed on the cut's clock."""

    def __init__(self, config, r):
        self.spans = []
        for i, s in enumerate(config['span']):
            t0, t1 = r.time(s['from']), r.time(s['to'])
            if t1 <= t0:
                sys.exit(f'cut: span {i + 1} ends before it starts')
            dissolve = s.get('dissolve', 0) if i else 0
            if self.spans:
                last = self.spans[-1]
                if dissolve > min(last['length'], t1 - t0):
                    sys.exit(f'cut: span {i + 1} dissolves for longer than a span lasts')
                if t0 < last['to']:
                    sys.exit(f'cut: span {i + 1} starts before span {i} ends')
                at = last['at'] + last['length'] - dissolve
            else:
                at = 0.0
            self.spans.append({'from': t0, 'to': t1, 'length': t1 - t0, 'at': at, 'dissolve': dissolve})
        last = self.spans[-1]
        self.length = last['at'] + last['length']

    def place(self, t):
        """Where a time in the take plays in the cut. A time the cut skips takes effect where the cut
        goes on."""
        for s in self.spans:
            if t < s['from']:
                return s['at']
            if t <= s['to']:
                return s['at'] + t - s['from']
        return self.length

    def layers(self, u):
        """The spans on screen at `u`, bottom first, each with the time in the take and its opacity."""
        found = []
        for i, s in enumerate(self.spans):
            into = u - s['at']
            if 0 <= into < s['length'] or (i == len(self.spans) - 1 and into == s['length']):
                alpha = ease(into / s['dissolve']) if s['dissolve'] > 0 else 1.0
                found.append((i, s['from'] + into, alpha))
        return found


def plan(config, take):
    data = load_take(take)
    r = Resolver(data)
    out = config['output']
    style = config['caption']
    fps = out['fps']
    scale = data['scale']
    movie = os.path.join(take, 'screen.mov')
    with open(os.path.join(take, 'screen.json')) as f:
        start = json.load(f)['firstFrameHostTime']
    bounds = data['bounds']
    # Narrower than this, the camera would enlarge the recording's pixels.
    least = out['width'] / scale
    edit = Edit(config, r)
    change = style.get('change', 0.45)
    loop = out.get('loop', 0)

    captions, cues, presses, moves = [], [], [], []
    for beat in (b for b in config['beat'] if b.get('enabled', True)):
        at = edit.place(r.time(beat['from']))
        index = -1
        if beat.get('caption'):
            captions.append({'text': beat['caption'], 'keys': beat.get('keys', [])})
            index = len(captions) - 1
        cues.append((at, index))
        if beat.get('press'):
            presses.append((edit.place(r.time(beat['press'], beat)), index))
        for m in beat.get('camera', []):
            t = r.time(m['at'], beat)
            moves.append({'at': edit.place(t), 'ease': m.get('ease', 0.001),
                          'rect': framed(r.rect(m['rect'], t), m.get('pad', 0), bounds, m.get('least', least))})
    if not moves:
        sys.exit('cut: no beat moves the camera; the first beat needs a camera')
    moves.sort(key=lambda m: m['at'])
    cues.sort()
    # A looping cut turns its last caption back into its first while the picture dissolves back.
    if loop and cues and cues[0][0] <= 0 and cues[0][1] >= 0:
        cues.append((edit.length - change, cues[0][1]))

    def caption_at(u):
        i = bisect.bisect_right([c[0] for c in cues], u + 1e-9) - 1
        if i < 0:
            return -1, -1, 1.0
        at, index = cues[i]
        previous = cues[i - 1][1] if i > 0 else -1
        # The caption up when the cut starts is up from the first frame.
        morph = 1.0 if at <= 0 else min(max((u - at) / change, 0.0), 1.0)
        return index, previous, morph

    def lit_at(u, index):
        hold, fade = style.get('lit', 0.45), 0.2
        best = 0.0
        for at, i in presses:
            if i == index and u >= at:
                d = u - at
                best = max(best, 1.0 if d < hold else 1.0 - ease((d - hold) / fade))
        return round(best, 4)

    # Each span reads the movie from the frame on screen when it starts, rather than decoding from
    # the top. The loop reads the first span again, as a source of its own.
    times = frame_times(movie)
    starts = []
    for s in edit.spans + ([edit.spans[0]] if loop else []):
        t = s['from'] - start
        i = bisect.bisect_right(times, t + 1e-6) - 1
        starts.append(max(times[max(i, 0)] - 0.01, 0.0))

    poster_at = edit.place(r.time(out['poster']['at'])) if out.get('poster') else 0.0
    frames, poster = [], None
    count = round(edit.length * fps)
    camera = config.get('camera', {})
    path = camera_path(moves, [n / fps for n in range(count)], bounds, least,
                       {'rate': camera.get('drift', 0.01), 'most': camera.get('drift_most', 0.03)})
    for n in range(count):
        u = n / fps
        if poster is None and u >= poster_at:
            poster = n
        layers = [[i, round(t - start, 5), round(a, 4)] for i, t, a in edit.layers(u)]
        if loop and u >= edit.length - loop:
            layers.append([len(edit.spans), round(edit.spans[0]['from'] - start, 5),
                           round(ease((u - (edit.length - loop)) / loop), 4)])
        x, y, w, h = path[n]
        index, previous, morph = caption_at(u)
        frames.append({'layers': layers, 'crop': [round(v * scale, 2) for v in (x, y, w, h)],
                       'caption': index, 'previous': previous, 'morph': round(ease(morph), 4),
                       'lit': lit_at(u, index)})
    return {
        'source': movie, 'starts': starts,
        'width': out['width'], 'height': out['height'], 'fps': fps,
        'style': {'size': style['size'], 'key_size': style['key_size'], 'x': style['x'], 'y': style['y']},
        'captions': captions, 'frames': frames, 'poster_frame': poster if poster is not None else 0,
    }


def cut(config, take, paths):
    os.makedirs(paths['cut'], exist_ok=True)
    p = plan(config, take)
    master = os.path.join(paths['cut'], 'master.mov')
    poster = os.path.join(paths['cut'], 'poster.png')
    p['output'], p['poster'] = master, poster
    plan_path = os.path.join(paths['cut'], 'plan.json')
    with open(plan_path, 'w') as f:
        json.dump(p, f)
    print(f"cutting {len(p['frames'])} frames ({len(p['frames']) / p['fps']:.1f} s) from {take}", flush=True)
    subprocess.run([paths['cut_bin'], plan_path], check=True, stdout=subprocess.DEVNULL)

    colour = ['-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709']
    mp4 = os.path.join(paths['cut'], 'trailer.mp4')
    webm = os.path.join(paths['cut'], 'trailer.webm')
    jpg = os.path.join(paths['cut'], 'poster.jpg')
    log = os.path.join(paths['cut'], 'ffmpeg.log')
    with open(log, 'w') as f:
        for args in (
            ['-i', master, '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-profile:v', 'high',
             '-pix_fmt', 'yuv420p', *colour, '-movflags', '+faststart', '-an', mp4],
            ['-i', master, '-c:v', 'libvpx-vp9', '-b:v', '0', '-crf', '33', '-row-mt', '1', '-deadline', 'good',
             '-cpu-used', '2', '-pix_fmt', 'yuv420p', *colour, '-an', webm],
            ['-i', poster, '-q:v', '3', jpg],
        ):
            subprocess.run(['ffmpeg', '-y', '-hide_banner', *args], check=True, stdout=f, stderr=subprocess.STDOUT)
    for path in (mp4, webm, jpg):
        print(f'{path}  {os.path.getsize(path) / 1e6:.1f} MB')
