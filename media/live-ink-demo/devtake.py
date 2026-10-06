#!/usr/bin/env python3
"""Performs live ink's developer demo on a stage `dev.py up` holds, and records it.

    devtake.py [--only BEAT,...] [--no-record]

Each beat draws on a window of the stage, types what to change in the note, sends it to the
trailer's Claude Code, and waits for Claude to change Postcard and answer on that window. Claude
takes 20 to 90 s a change, so a take lasts several minutes, and nobody may use the Mac meanwhile.
Every press checks first that the window under it is the stage's, and every key goes to Vignette
Demo's own process. A take that cannot go on lets go of everything, stops the recording and says
why. The movie and the beats' times go to `out/dev/takes/`.
"""
import json
import math
import os
import calendar
import glob
import random
import signal
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from take import Hand, TakeFailed   # noqa: E402


class ClaudeFailed(TakeFailed):
    """The stage's Claude Code stopped on an error of its own, such as an API it could not reach."""

OUT = os.path.join(HERE, 'out', 'dev')
RECORD = os.path.join(HERE, 'out', 'bin', 'record')
TAKES = os.path.join(OUT, 'takes')
STATE = os.path.join(OUT, 'stage.json')
DOWN, RETURN = 125, 36


class DevTake:
    def __init__(self):
        if not os.path.exists(STATE):
            raise TakeFailed('no stage; run `dev.py up` first')
        self.stage = json.load(open(STATE))
        self.app = self.stage['app']
        self.vignette = self.stage['pid']
        self.desktop, self.mobile, self.ghostty = self.stage['chrome_desktop'], self.stage['chrome_mobile'], self.stage['ghostty']
        self.hand = Hand()
        self.started = None
        self.beats = []

    # MARK: Looking

    def log_size(self):
        return os.path.getsize(self.app['log'])

    def log_since(self, offset):
        """The log after `offset`. At 5 MB the app moves the log to `.1` and starts a new one, so an
        offset past the log's end is in the old one."""
        path = self.app['log']
        before = b''
        if os.path.getsize(path) < offset and os.path.exists(path + '.1'):
            with open(path + '.1', 'rb') as f:
                f.seek(offset)
                before = f.read()
            offset = 0
        with open(path, 'rb') as f:
            f.seek(offset)
            return (before + f.read()).decode('utf-8', 'replace')

    def url(self, command):
        os.kill(self.vignette, 0)
        subprocess.run(['open', '-g', '-a', self.app['path'], f"{self.app['scheme']}://{command}"], check=True)

    def state(self):
        tag = f'dev{random.randrange(10**9)}'
        offset = self.log_size()
        self.url(f'state?tag={tag}')
        end = time.monotonic() + 5
        while time.monotonic() < end:
            for line in self.log_since(offset).splitlines():
                if '[state] ' in line and tag in line:
                    report = json.loads(line.split('[state] ', 1)[1])
                    if report['app']['bundle'] != self.app['path'] or report['app']['settingsFile'] != self.stage['settings']:
                        raise TakeFailed(f"state came from {report['app']['bundle']} on {report['app']['settingsFile']}")
                    return report
            time.sleep(0.05)
        raise TakeFailed('Vignette Demo did not answer')

    def live(self):
        return self.state()['liveInk']

    def wait(self, test, timeout, what, every=0.2):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            found = test()
            if found:
                return found
            time.sleep(every)
        raise TakeFailed(f'{what} did not happen within {timeout} s')

    def api_error(self, since):
        """The newest API error the stage's Claude Code wrote in its session's transcript after
        `since`, a time.time(), as its text; None when there is none."""
        found = None
        # The session the inbox holds now: /login or /clear starts another.
        with open(os.path.join(self.stage['inbox'], 'session')) as f:
            session = f.read().strip()
        for path in glob.glob(os.path.join(self.stage['claude'], 'projects', '*', session + '.jsonl')):
            if os.path.getmtime(path) < since:
                continue
            with open(path, errors='replace') as f:
                for line in f:
                    if '"isApiErrorMessage":true' not in line:
                        continue
                    entry = json.loads(line)
                    stamp = calendar.timegm(time.strptime(entry.get('timestamp', '')[:19], '%Y-%m-%dT%H:%M:%S'))
                    if stamp >= since:
                        content = entry.get('message', {}).get('content') or [{}]
                        found = (content[0].get('text') or 'an API error').strip()
        return found

    def turn(self):
        with open(os.path.join(self.stage['inbox'], 'turn')) as f:
            return f.read().strip()

    def find(self, pid, text):
        answer = self.hand('find', pid, text)
        if answer == 'none':
            raise TakeFailed(f'no "{text}" on screen')
        return tuple(map(float, answer.split()))

    def window(self, pid):
        windows = json.loads(self.hand('windows', pid))
        if not windows:
            raise TakeFailed(f'no window of {pid}')
        return max(windows, key=lambda w: w['frame'][2] * w['frame'][3])['frame']

    def require(self, x, y, pid):
        found = int(self.hand('owner', round(x, 1), round(y, 1), self.vignette))
        if found != pid:
            raise TakeFailed(f'the window under {x:.0f},{y:.0f} belongs to pid {found}, not {pid}')

    # MARK: Doing

    def front(self, pid):
        """Brings `pid`'s windows in front of every other app's, as a click on them would."""
        subprocess.run(['osascript', '-e', f'tell application "System Events" to set frontmost of '
                        f'(first process whose unix id is {pid}) to true'], check=True, capture_output=True)
        time.sleep(0.4)

    def beat(self, name):
        self.beats.append({'beat': name, 't': round(time.monotonic() - self.started, 2) if self.started else 0})
        print(f'[take] {name}', flush=True)

    def pause(self, seconds):
        time.sleep(seconds * random.uniform(0.9, 1.15))

    def glide(self, x, y, seconds=None):
        self.hand('glide', round(x, 1), round(y, 1), seconds or 0.55)

    def click(self, x, y, pid):
        self.glide(x, y)
        self.require(x, y, pid)
        self.pause(0.15)
        self.hand('click')

    def chord(self):
        self.hand('chord', 'down')
        self.wait(lambda: self.live()['chord'], 1.5, 'the chord')
        self.pause(0.2)

    def loop(self, box, pid, pad=(22, 12), seconds=1.0):
        """Holds ⌃⌥ and loops round `box` on `pid`'s window, then lets go."""
        x, y, w, h = box
        cx, cy = x + w / 2, y + h / 2
        self.require(cx, cy, pid)
        self.glide(cx - w / 2 - 50, cy + h / 2 + 40)
        self.pause(0.3)
        self.chord()
        self.hand('loop', round(cx, 1), round(cy, 1), round(w / 2 + pad[0], 1), round(h / 2 + pad[1], 1), seconds)
        self.pause(0.2)
        self.hand('chord', 'up')

    def arrow(self, tail, head, pid, seconds=0.9):
        """Holds ⌃⌥ and draws from `tail` to `head` on `pid`'s window, bowed a little, then lets go."""
        self.require(*tail, pid)
        self.require(*head, pid)
        self.glide(*tail)
        self.pause(0.3)
        self.chord()
        mid = ((tail[0] + head[0]) / 2 + (head[1] - tail[1]) * 0.12, (tail[1] + head[1]) / 2 - (head[0] - tail[0]) * 0.12)
        self.hand('press')
        self.glide(*mid, seconds * 0.5)
        self.glide(*head, seconds * 0.5)
        self.pause(0.05)
        self.hand('release')
        self.pause(0.2)
        self.hand('chord', 'up')

    def drag_window(self, pid, to):
        """Drags `pid`'s window by its title bar until its top-left corner is at `to`'s."""
        x, y, w, h = self.window(pid)
        grab = (x + w * 0.5, y + 12)
        self.require(*grab, pid)
        self.glide(*grab, 0.7)
        self.pause(0.25)
        self.hand('press')
        self.pause(0.1)
        dx, dy = to[0] - x, to[1] - y
        self.glide(grab[0] + dx * 0.55, grab[1] + dy * 0.55, 0.5)
        self.glide(grab[0] + dx, grab[1] + dy, 0.45)
        self.pause(0.15)
        self.hand('release')
        self.beat('mobile window moved')

    def send(self, words):
        """Types `words` in the note, picks the Claude Code session as its target, and sends it.
        Answers the log offset from before the send."""
        self.wait(lambda: self.live()['note'], 3, 'the note')
        self.pause(0.45)
        self.hand('type', self.vignette, 12, words)
        self.pause(0.5)
        # The note starts on the target picked last, so only the first beat picks the session.
        if self.live()['noteTarget'] != 'session':
            offset = self.log_size()
            self.hand('key', self.vignette, DOWN)
            self.pause(0.6)
            # The menu: Claude, on the screen; then the sessions. The second Down reaches the first session.
            self.hand('key', self.vignette, DOWN)
            self.pause(0.35)
            self.hand('key', self.vignette, DOWN)
            self.pause(0.45)
            self.hand('key', self.vignette, RETURN)
            self.wait(lambda: '[live-ink] note target session' in self.log_since(offset), 3, 'the session as the target')
            self.pause(0.6)
        offset = self.log_size()
        self.hand('key', self.vignette, RETURN)
        self.wait(lambda: '[live-ink] sent to a session' in self.log_since(offset), 15, 'the send')
        return offset

    def answered(self, offset, timeout=240, expect_answer=False):
        """Waits for Claude to start and for its turn to end, which ends the shimmer, or for an
        answer drawn on the window, which `expect_answer` requires."""
        sent = time.time() - 5

        def failing(test):
            def check():
                error = self.api_error(sent)
                if error:
                    raise ClaudeFailed(f"the stage's Claude Code stopped: {error}")
                return test()
            return check
        self.wait(failing(lambda: self.turn() == 'busy'), 60, 'Claude starting', every=0.3)
        self.beat('claude working')
        line = self.wait(failing(lambda: next((l for l in self.log_since(offset).splitlines()
                                               if any(k in l for k in ("session's turn ended", '[reply] shown', '[reply] published',
                                                                       '[reply] error'))), None)),
                         timeout, "Claude's turn ending", every=0.5)
        if '[reply] published' in line or '[reply] error' in line:
            raise TakeFailed(f'the answer was not drawn on the window: {line}')
        if expect_answer and '[reply] shown' not in line:
            raise TakeFailed('Claude answered in the terminal, not on the window')
        self.beat('answer shown' if '[reply] shown' in line else 'turn ended')
        self.pause(4.0)

    # MARK: The beats

    def number_days(self):
        """On the desktop window: an arrow from the map's first stop to the first day."""
        self.beat('1 number the days')
        stop = self.find(self.desktop, 'FLORENCE')
        day = self.find(self.desktop, 'Oct 12')
        tail = (stop[0] + stop[2] * 0.75, stop[1] + stop[3] + 26)
        head = (day[0] + day[2] * 0.4, day[1] - 4)
        self.arrow(tail, head, self.desktop)
        offset = self.send('number the days like the map')
        self.answered(offset)

    def stack_on_mobile(self):
        """On the mobile window: a loop round the squeezed day cards."""
        self.beat('2 stack on mobile')
        frame = self.window(self.mobile)
        # The card's title: the date above it wraps once the day has its number. Beat 1's number can
        # cover the title's first letters, so the date line answers instead.
        try:
            top = self.find(self.mobile, 'Arrive')[1] - 40
        except TakeFailed:
            top = self.find(self.mobile, 'OCT 12')[1] - 15
        box = (frame[0] + 24, top, frame[2] - 48, min(frame[1] + frame[3] - 40, top + 220) - top)
        self.loop(box, self.mobile, pad=(8, 14), seconds=1.2)
        offset = self.send('stack these on mobile')
        self.pause(1.2)
        self.drag_window(self.mobile, self.stage['frames']['mobile_inward'])
        self.answered(offset)

    def review_mobile(self):
        """On the mobile window: a loop round the page, asking what else to fix there. Claude
        answers on the window, pointing at the top bar running off the edge, with actions under
        its answer; the first is clicked, and Claude makes the fix."""
        self.beat('3 review on mobile')
        self.front(self.mobile)
        x, y, w, h = self.window(self.mobile)
        box = (x + 30, y + 60, w - 60, h - 110)
        self.loop(box, self.mobile, pad=(4, 8), seconds=1.4)
        offset = self.send('what else should we fix on mobile?')
        self.answered(offset, expect_answer=True)
        self.pause(2.5)
        buttons = self.wait(lambda: self.live()['actions'], 3, "the answer's actions")
        self.beat('actions: ' + ', '.join(b['title'] for b in buttons))
        bx, by, bw, bh = buttons[0]['frame']
        self.glide(bx + bw / 2, by + bh / 2, 0.6)
        self.pause(0.5)
        offset = self.log_size()
        self.hand('click')
        self.wait(lambda: '[live-ink] sent to a session' in self.log_since(offset), 15, 'the action sent')
        self.glide(x - 120, y + h - 60, 0.8)
        self.answered(offset)

    def dismiss(self):
        """Moves onto Claude's note, which shows its ×, and clicks the ×."""
        say = next((m for m in self.live()['marks'] if m['type'] == 'text' and m['agent'] and m['shown']), None)
        if not say:
            raise TakeFailed("no answer note on screen")
        x, y, w, h = say['frame']
        self.glide(x + w * 0.6, y + h / 2, 0.7)
        self.pause(0.3)
        self.glide(x + w * 0.35, y + h / 2, 0.4)
        button = self.wait(lambda: self.live()['dismiss'], 3, 'the answer\'s ×')
        self.pause(0.5)
        bx, by, bw, bh = button
        self.glide(bx + bw / 2, by + bh / 2, 0.45)
        self.pause(0.25)
        offset = self.log_size()
        self.hand('click')
        self.wait(lambda: '[live-ink] dismissed' in self.log_since(offset), 3, 'the dismissal')
        self.beat('dismissed')
        self.pause(2.0)

    BEATS = ['number_days', 'stack_on_mobile', 'review_mobile']

    def preflight(self):
        """Stops before recording when the take could not finish: Claude Code cannot reach its API,
        or another app's window covers part of the stage."""
        try:
            socket.getaddrinfo('api.anthropic.com', 443)
        except OSError as error:
            raise TakeFailed(f"Claude Code's API cannot be reached: {error}")
        frames = self.stage['frames']
        for window, pid in (('terminal', self.ghostty), ('desktop', self.desktop), ('mobile', self.mobile)):
            x, y, w, h = frames[window]
            for fx in (0.15, 0.5, 0.85):
                for fy in (0.15, 0.5, 0.85):
                    try:
                        self.require(x + w * fx, y + h * fy, pid)
                    except TakeFailed as error:
                        # The mobile window sits over the desktop one, so the desktop's points under it are the mobile's.
                        if not (window == 'desktop' and f'pid {self.mobile},' in str(error)):
                            raise TakeFailed(f'the {window} window is covered: {error}')

    def raise_stage(self):
        """The stage's windows above any other app's; the mobile window last, over the desktop one."""
        for pid in (self.ghostty, self.desktop, self.mobile):
            self.front(pid)

    def perform(self, only=None, record=True):
        os.makedirs(TAKES, exist_ok=True)
        name = time.strftime('take-%Y%m%d-%H%M%S')
        movie = os.path.join(TAKES, name + '.mov')
        self.url('live-ink-clear')
        if self.turn() != 'idle':
            raise TakeFailed("Claude Code is busy; wait for its turn to end")
        self.raise_stage()
        self.preflight()
        frames = self.stage['frames']
        self.glide(frames['desktop'][0] + 300, frames['desktop'][1] + frames['desktop'][3] - 60, 0.8)
        recorder = None
        if record:
            pids = [self.desktop, self.mobile, self.ghostty, self.vignette, self.stage['desktop']]
            recorder = subprocess.Popen([RECORD, movie, '0', *map(str, pids)], stdout=subprocess.PIPE, text=True)
            recorder.stdout.readline()
        self.started = time.monotonic()
        failed = None
        try:
            self.pause(1.5)
            for beat in self.BEATS:
                if only and beat not in only:
                    continue
                # A window that came forward during the last beat goes back under the stage.
                self.raise_stage()
                try:
                    getattr(self, beat)()
                except ClaudeFailed as error:
                    # Claude Code's own failure, not the take's: the beat starts over once, and the cut skips it.
                    self.beat(f'retry {beat}: {error}')
                    self.wait(lambda: self.turn() == 'idle', 60, 'Claude Code idle')
                    self.url('live-ink-clear')
                    self.pause(5)
                    getattr(self, beat)()
            self.beat('end')
            self.pause(1.5)
        except TakeFailed as error:
            failed = error
        finally:
            self.hand.close()
            if recorder:
                recorder.send_signal(signal.SIGINT)
                recorder.wait(timeout=30)
            json.dump({'beats': self.beats, 'failed': str(failed) if failed else None, 'movie': movie if record else None},
                      open(os.path.join(TAKES, name + '.beats.json'), 'w'), indent=2)
        print(f'[take] {"stopped: " + str(failed) if failed else "done"}' + (f'; {movie}' if record else ''))
        return failed


if __name__ == '__main__':
    only = sys.argv[sys.argv.index('--only') + 1].split(',') if '--only' in sys.argv else None
    try:
        failed = DevTake().perform(only, record='--no-record' not in sys.argv)
    except TakeFailed as error:
        sys.exit(f'[take] {error}')
    sys.exit(1 if failed else 0)
