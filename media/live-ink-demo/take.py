#!/usr/bin/env python3
"""Performs the live ink demo on the stage and records it (docs/live-ink-demo-2026-10-05.md).

    take.py [--only BEAT,...]

The stage must be up with `demo.py up --capture`. The take moves the pointer and holds ⌃⌥ for
about three minutes, so nobody may use the Mac meanwhile. Every press checks first that the window
under it is the stage's, and every key goes to Vignette's own process, except ⌘M, which is sent
only while the stage's Chrome is frontmost. A take that cannot go on lets go of everything, stops
the recording and says why. The movie and a log of the beats' times go to `out/takes/`.
"""
import json
import math
import os
import random
import signal
import subprocess
import sys
import time

import demo

HAND = os.path.join(demo.OUT, 'bin', 'hand')
RECORD = os.path.join(demo.OUT, 'bin', 'record')
TAKES = os.path.join(demo.OUT, 'takes')


class TakeFailed(Exception):
    pass


class Hand:
    def __init__(self):
        self.process = subprocess.Popen([HAND], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)

    def __call__(self, *words):
        self.process.stdin.write(' '.join(str(w) for w in words) + '\n')
        self.process.stdin.flush()
        answer = self.process.stdout.readline().strip()
        if not answer.startswith('ok'):
            raise TakeFailed(f'hand: {" ".join(map(str, words))}: {answer or "no answer"}')
        return answer[2:].strip()

    def close(self):
        # Closing its input makes it let go of the chord and the button.
        self.process.stdin.close()
        self.process.wait(timeout=5)


class Take:
    def __init__(self):
        stage = demo.saved()
        if not stage.get('desktop') or not stage.get('capture'):
            raise TakeFailed('the stage is not up with --capture; run `demo.py up --capture` first')
        self.app = stage['app']
        self.chrome, self.textedit, self.ghostty = stage['chrome'], stage['textedit'], stage['terminal']
        self.vignette = demo.vignette()[0]
        self.desktop = demo.pids_of(lambda c: c.endswith('out/bin/stage desktop'))
        self.hand = Hand()
        self.started = None
        self.beats = []

    # MARK: Looking

    def live(self):
        report = demo.state(self.app)
        if report['app']['settingsFile'] != os.path.join(demo.OUT, 'vignette', 'settings.json'):
            raise TakeFailed(f"Vignette is on {report['app']['settingsFile']}, not the demo's copy")
        return report['liveInk']

    def wait(self, test, timeout, what):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            found = test(self.live())
            if found:
                return found
            time.sleep(0.15)
        raise TakeFailed(f'{what} did not happen within {timeout} s')

    def find(self, pid, text):
        answer = self.hand('find', pid, text)
        if answer == 'none':
            raise TakeFailed(f'no "{text}" on screen')
        x, y, w, h = map(float, answer.split())
        return x, y, w, h

    def window(self, pid, title=''):
        for window in json.loads(self.hand('windows', pid)):
            if title in window['title']:
                return window['frame']
        raise TakeFailed(f'no window of {pid} titled "{title}"')

    def require(self, x, y, pid):
        """The window a press at x, y reaches is `pid`'s. Vignette's mark overlays let presses through."""
        found = int(self.hand('owner', round(x, 1), round(y, 1), self.vignette))
        if found != pid:
            raise TakeFailed(f'the window under {x:.0f},{y:.0f} belongs to pid {found}, not {pid}')

    def frontmost(self):
        return int(demo.run('osascript', '-e', 'tell application "System Events" to unix id of first process whose frontmost is true').stdout.strip())

    # MARK: Doing

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

    def ink(self, box, pid, rx_pad=22, ry_pad=12, seconds=1.0):
        """Holds ⌃⌥ and loops round `box` on `pid`'s window, then lets go."""
        x, y, w, h = box
        cx, cy = x + w / 2, y + h / 2
        self.require(cx, cy, pid)
        self.glide(cx - w / 2 - 60, cy + h / 2 + 50)
        self.pause(0.3)
        self.hand('chord', 'down')
        self.wait(lambda s: s['chord'], 1.5, 'the chord')
        self.pause(0.25)
        self.hand('loop', round(cx, 1), round(cy, 1), round(w / 2 + rx_pad, 1), round(h / 2 + ry_pad, 1), seconds)
        self.pause(0.2)
        self.hand('chord', 'up')

    def ask(self, words, wait_for_note=True):
        if wait_for_note:
            self.wait(lambda s: s['note'], 3, 'the note')
        self.pause(0.45)
        if words:
            self.hand('type', self.vignette, 11, words)
            self.pause(0.45)
        self.hand('key', self.vignette, 36)
        answer = self.wait(lambda s: s['ask'] if s['ask'] and s['ask']['phase'] in ('answered', 'failed') else None, 40, 'the answer')
        if answer['phase'] == 'failed':
            raise TakeFailed(f"the ask failed: {answer.get('reason')}")
        # The marks draw on after the reply, then time to read it.
        self.pause(2.2 + min(5, answer.get('sayLength', 60) / 30))
        return answer

    def agent_marks(self):
        return [m for m in self.live()['marks'] if m['agent'] and m['type'] != 'text' and m['shown']]

    # MARK: The beats

    def check_this(self):
        self.beat('1 check the total')
        total = self.find(self.chrome, '4,008.20')
        self.ink(total, self.chrome, rx_pad=24, ry_pad=12)
        self.ask('is this right?')

    def drag_and_cover(self):
        self.beat('2 drag the invoice')
        invoice = self.window(self.chrome, 'Invoice')
        notes = self.window(self.textedit)
        grab = (invoice[0] + invoice[2] * 0.5, invoice[1] + 14)
        self.glide(*grab)
        self.require(*grab, self.chrome)
        self.pause(0.3)
        dx = min(notes[0] + notes[2] * 0.55 - (invoice[0] + invoice[2] * 0.8), 360)
        self.hand('press')
        self.glide(grab[0] + dx, grab[1] + 6, 1.1)
        self.pause(0.1)
        self.hand('release')
        self.pause(1.4)
        self.beat('3 cover and uncover')
        notes = self.window(self.textedit)
        self.click(notes[0] + notes[2] - 70, notes[1] + 14, self.textedit)
        self.pause(1.8)
        invoice = self.window(self.chrome, 'Invoice')
        self.click(invoice[0] + 60, invoice[1] + 14, self.chrome)
        self.pause(1.4)
        grab = (invoice[0] + invoice[2] * 0.5, invoice[1] + 14)
        self.glide(*grab)
        self.require(*grab, self.chrome)
        self.hand('press')
        self.glide(grab[0] - dx, grab[1] - 6, 0.9)
        self.pause(0.1)
        self.hand('release')
        self.pause(1.0)

    def notes(self):
        self.beat('4 say it simply')
        notes = self.window(self.textedit)
        self.click(notes[0] + notes[2] * 0.5, notes[1] + 14, self.textedit)
        self.pause(0.6)
        self.glide(notes[0] + notes[2] * 0.5, notes[1] + notes[3] * 0.55)
        start = self.find(self.textedit, 'Notwithstanding')
        self.hand('scroll', round(start[1] - (notes[1] + 110), 1), 0.4, 0.5)
        self.pause(1.6)
        start = self.find(self.textedit, 'Notwithstanding')
        end = self.find(self.textedit, 'has elapsed')
        top, bottom = start[1], end[1] + end[3]
        left, right = notes[0] + 18, notes[0] + notes[2] - 18
        self.ink((left + 10, top, right - left - 20, bottom - top), self.textedit, rx_pad=16, ry_pad=18, seconds=1.2)
        self.ask('say this simply')
        self.beat('5 scroll away and back')
        self.glide(notes[0] + notes[2] * 0.4, notes[1] + notes[3] * 0.45)
        self.pause(0.4)
        # Less than the document has left below, so the way back lands where it started.
        self.hand('scroll', 110, 0.3, 0.4)
        self.pause(1.8)
        self.hand('scroll', -110, 0.3, 0.4)
        self.pause(2.4)

    def ask_back(self):
        self.beat('6 ask back')
        settings = self.window(self.chrome, 'Notifications')
        # Its title bar's right end: the launch notes cover the rest of it.
        self.click(settings[0] + settings[2] - 60, settings[1] + 14, self.chrome)
        self.pause(0.6)
        discard = self.find(self.chrome, 'Discard')
        save = self.find(self.chrome, 'Save changes')
        both = (discard[0] - 8, discard[1] - 6, save[0] + save[2] - discard[0] + 16, discard[3] + 12)
        self.ink(both, self.chrome, rx_pad=26, ry_pad=14, seconds=1.1)
        self.ask('what does this do?')
        marks = self.agent_marks()
        if len(marks) < 2:
            print(f'[take] the answer drew {len(marks)} marks, not two; going on without the pick')
            return
        self.beat('7 pick one')
        dx, dy = discard[0] + discard[2] / 2, discard[1] + discard[3] / 2
        mark = min(marks, key=lambda m: math.dist((m['frame'][0] + m['frame'][2] / 2, m['frame'][1] + m['frame'][3] / 2), (dx, dy)))
        mx, my = mark['frame'][0] + mark['frame'][2] / 2, mark['frame'][1] + mark['frame'][3] / 2
        self.glide(mx - 70, my + 40)
        self.hand('chord', 'down')
        self.wait(lambda s: s['chord'], 1.5, 'the chord')
        self.glide(mx, my, 0.6)
        self.pause(1.1)
        self.hand('click')
        self.pause(0.4)
        self.hand('chord', 'up')
        self.ask('')

    def steps(self):
        self.beat('8 steps')
        account = self.find(self.chrome, 'your account')
        heading = (account[0] - 4, account[1] - 30, max(account[2], 150) + 8, account[3] + 32)
        self.ink(heading, self.chrome, rx_pad=24, ry_pad=12)
        self.ask('how do I get the weekly summary?')
        targets = {'Weekly summary email': self.find(self.chrome, 'Weekly summary email'),
                   'Save changes': self.find(self.chrome, 'Save changes')}
        for _ in range(3):
            live = self.live()
            if not live['steps']:
                break
            marks = self.agent_marks()
            if not marks:
                break
            m = marks[-1]['frame']
            centre = (m[0] + m[2] / 2, m[1] + m[3] / 2)
            name, box = min(targets.items(), key=lambda t: math.dist(centre, (t[1][0] + t[1][2] / 2, t[1][1] + t[1][3] / 2)))
            print(f'[take] step on {name}')
            self.pause(0.6)
            self.click(box[0] + min(box[2] / 2, 60), box[1] + box[3] / 2, self.chrome)
            self.pause(1.8)
        else:
            print('[take] the steps did not end in three clicks')

    def terminal(self):
        self.beat('9 the failing test')
        window = self.window(self.ghostty)
        self.click(window[0] + window[2] * 0.5, window[1] + 14, self.ghostty)
        self.pause(0.5)
        error = self.find(self.ghostty, 'AssertionError')
        width = error[2] / len('AssertionError') * len("AssertionError: assert Decimal('4008.20') == Decimal('3975.48')")
        self.ink((error[0], error[1], width, error[3]), self.ghostty, rx_pad=18, ry_pad=12, seconds=1.1)
        self.ask('why?')

    def minimise(self):
        self.beat('10 minimise and restore')
        invoice = self.window(self.chrome, 'Invoice')
        self.click(invoice[0] + invoice[2] * 0.5, invoice[1] + 14, self.chrome)
        self.pause(0.8)
        if self.frontmost() != self.chrome:
            raise TakeFailed("the stage's Chrome is not frontmost, so ⌘M is not sent")
        self.hand('key', 0, 46, 'cmd')
        self.pause(2.2)
        self.hand('unminimize', self.chrome)
        self.pause(2.8)

    BEATS = ['check_this', 'drag_and_cover', 'notes', 'ask_back', 'steps', 'terminal', 'minimise']

    def perform(self, only=None):
        os.makedirs(TAKES, exist_ok=True)
        name = time.strftime('take-%Y%m%d-%H%M%S')
        movie = os.path.join(TAKES, name + '.mov')
        demo.url(self.app, 'live-ink-clear')
        self.live()
        # Holding the chord starts the responder and its warm-up ask, before the camera rolls.
        self.glide(30, 300)
        self.hand('chord', 'down')
        self.pause(0.3)
        self.hand('chord', 'up')
        self.wait(lambda s: s['responder']['state'] == 'ready', 30, 'the responder')
        self.glide(300, 640, 0.8)
        pids = [self.chrome, self.textedit, self.ghostty, self.vignette, *self.desktop]
        recorder = subprocess.Popen([RECORD, movie, '0', *map(str, pids)], stdout=subprocess.PIPE, text=True)
        recorder.stdout.readline()
        self.started = time.monotonic()
        failed = None
        try:
            self.pause(1.5)
            for beat in self.BEATS:
                if not only or beat in only:
                    getattr(self, beat)()
            self.beat('end')
            self.pause(1.0)
            demo.url(self.app, 'live-ink-clear')
            self.pause(1.5)
        except TakeFailed as error:
            failed = error
        finally:
            self.hand.close()
            recorder.send_signal(signal.SIGINT)
            recorder.wait(timeout=30)
            json.dump({'beats': self.beats, 'failed': str(failed) if failed else None},
                      open(os.path.join(TAKES, name + '.json'), 'w'), indent=2)
        print(f'[take] {"stopped: " + str(failed) if failed else "done"}; {movie}')
        return movie, failed


if __name__ == '__main__':
    only = None
    if '--only' in sys.argv:
        only = sys.argv[sys.argv.index('--only') + 1].split(',')
    try:
        movie, failed = Take().perform(only)
    except TakeFailed as error:
        sys.exit(f'[take] {error}')
    sys.exit(1 if failed else 0)
