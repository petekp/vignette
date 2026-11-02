"""Live ink's end-to-end scenarios. Each draws on a window of known text (`probe window`), through the
debug commands a script reaches the note with (`live-ink-chord-down`, `live-ink-stroke`,
`live-ink-chord-up`, `live-ink-ask`), and posts no keys or clicks. Claude is `fake_claude.py`, which
`VIGNETTE_CLAUDE` names. They read `state?section=liveInk`, since the whole report runs to tens of KB
and polled it rotates the log the waits read (docs/live-ink.md)."""
import json
import math
import os
import random
import re
import subprocess
import sys
import time
import urllib.parse

from e2e import PROBE, Failed
from scenarios import card_for, start

# x, y, w and h in global top-left points, inside the VM's 1024 by 768 screen.
PAGE = [150, 140, 660, 360]
LINES = ['Order summary', 'Shipping to the office', 'Total due 42 dollars']
WORDS = 'is this the right total'


def on_fresh_copy(scenario):
    """Runs the scenario on `Vignette E2E Fresh`, which is granted nothing (`build.sh fresh`)."""
    scenario.copy = 'fresh'
    return scenario


# ---- Shared steps ------------------------------------------------------------------------------


def ink_state(app):
    """The state's `app` and `liveInk` sections, from this copy on its scratch files."""
    tag = f'e2e{random.randrange(10 ** 9)}'
    offset = app.log_size()
    app.url(f'state?tag={tag}&section=liveInk')
    line = app.wait_log('[state] ', offset, also=tag)
    s = json.loads(line.split('[state] ', 1)[1])
    if (os.path.realpath(s['app']['bundle']) != os.path.realpath(app.copy['path'])
            or os.path.realpath(s['app']['settingsFile']) != os.path.realpath(app.settings)):
        raise Failed(f"state came from {s['app']['bundle']} on {s['app']['settingsFile']}, not the test copy on its scratch file")
    return s


def wait_ink(app, test, what, timeout=15):
    end = time.monotonic() + timeout
    while True:
        s = ink_state(app)
        if test(s['liveInk']):
            return s['liveInk']
        if time.monotonic() > end:
            raise Failed(f"{what} did not happen within {timeout} s; liveInk.ask is {s['liveInk']['ask']}")
        time.sleep(0.2)


def launch(app, **env):
    """Live ink on, Send with no grace, and every capture able to see the marks, for the report."""
    app.write_settings(liveInk=True, debug=True, ui={'sendGraceSeconds': 0})
    start(app, VIGNETTE_SHARE_LIVE_INK='1', **env)


def require_screen_recording(app, granted):
    s = ink_state(app)
    if s['app']['screenRecording'] != granted:
        raise Failed(f"{app.copy['name']} {'lacks' if granted else 'has'} Screen Recording, which this scenario needs "
                     f"{'granted' if granted else 'refused'}")
    app.report.step('Screen Recording is ' + ('granted' if granted else 'refused'))


def fake_claude(app):
    """A claude that answers live ink (`fake_claude.py`) and records every call in its folder.
    Returns the folder and the env that points the launch at it."""
    folder = os.path.join(app.folder, 'claude')
    os.makedirs(folder, exist_ok=True)
    claude = os.path.join(folder, 'claude')
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fake_claude.py')
    # This Python, by path: the app runs claude with launchd's PATH, where python3 can be Apple's stub.
    with open(claude, 'w') as f:
        f.write(f"#!/bin/sh\nexec '{sys.executable}' '{script}' '{folder}' \"$@\"\n")
    os.chmod(claude, 0o755)
    return folder, {'VIGNETTE_CLAUDE': claude}


def claude_messages(folder):
    """The messages the fake claude was sent, oldest first: each one's text and image sizes."""
    path = os.path.join(folder, 'calls.jsonl')
    calls = [json.loads(line) for line in open(path)] if os.path.exists(path) else []
    return [c for c in calls if 'text' in c]


def page(app):
    """A window of `LINES` at `PAGE`, in front. Returns its window number and each line's frame."""
    out = os.path.join(app.folder, 'page.txt')
    with open(out, 'w') as f:
        holder = subprocess.Popen([PROBE, 'window', *map(str, PAGE), *LINES], stdout=f)
    app.fakes.append(holder.pid)
    end = time.monotonic() + 10
    while 'up' not in open(out).read().split():
        if holder.poll() is not None or time.monotonic() > end:
            raise Failed(f'the test window did not come up: {open(out).read()!r}')
        time.sleep(0.1)
    words = open(out).read().split('\n')
    number = int(next(w for w in words if w.startswith('window ')).split()[1])
    frames = [[int(v) for v in w.split()[1:]] for w in words if w.startswith('line ')]
    time.sleep(0.5)
    app.report.step('a window of text is in front', detail=f'window {number} at {PAGE}')
    return number, frames


def loop_around(rect, pad=16, count=48):
    """A closed stroke round `rect`, as a hand draws a loop, in the `points=` form."""
    x, y, w, h = rect
    cx, cy, rx, ry = x + w / 2, y + h / 2, w / 2 + pad, h / 2 + pad
    points = [(cx + rx * math.cos(2 * math.pi * i / count), cy + ry * math.sin(2 * math.pi * i / count)) for i in range(count + 1)]
    return ';'.join(f'{px:.0f},{py:.0f}' for px, py in points)


def draw_note(app, rect):
    """Holds the chord, loops `rect` and lets go, as a hand does: the note opens on the ink."""
    app.command('live-ink-chord-down')
    detail = app.command('live-ink-stroke', 'points=' + urllib.parse.quote(loop_around(rect), safe=''))
    if not detail.startswith('drew ellipse'):
        raise Failed(f'the loop drew {detail}, not an ellipse')
    app.command('live-ink-chord-up')
    ink = wait_ink(app, lambda ink: ink['note'] is not None and ink['new'] == 1, 'the note opening on the ink')
    app.report.step('the loop is ink and its note opened', detail=f"target={ink['noteTarget']}")
    return ink


def person_marks(ink):
    return [m for m in ink['marks'] if not m['agent']]


def inside(frame, rect):
    x, y, w, h = frame
    return rect[0] <= x + w / 2 <= rect[0] + rect[2] and rect[1] <= y + h / 2 <= rect[1] + rect[3]


def ask(app, words=WORDS, session=None):
    query = 'message=' + urllib.parse.quote(words, safe='') + (f'&session={session}' if session else '')
    detail = app.command('live-ink-ask', query, timeout=20)
    app.report.step('asked about the ink', detail=detail)
    return detail


def failed_ask(app, reason):
    """The newest ask failed for `reason`, said in a reply beside the ink, which stays."""
    ink = wait_ink(app, lambda ink: (ink['ask'] or {}).get('phase') == 'failed' and ink['reply'] is not None,
                   'the ask failing with its reason beside the ink')
    if reason not in ink['ask'].get('reason', ''):
        raise Failed(f"the ask failed for {ink['ask'].get('reason')!r}, not {reason!r}")
    app.report.step('the ask failed and a reply beside the ink says why', detail=ink['ask']['reason'])
    if len(person_marks(ink)) != 1:
        raise Failed(f'the ink did not stay: {person_marks(ink)}')
    app.report.step('the ink stays on the window')
    return ink


def capture_reply(app, ink, name):
    x, y, w, h = ink['reply']
    left, top = min(x, PAGE[0]) - 10, min(y, PAGE[1]) - 10
    right, bottom = max(x + w, PAGE[0] + PAGE[2]) + 10, max(y + h, PAGE[1] + PAGE[3]) + 10
    app.capture([left, top, right - left, bottom - top], name)


# ---- Scenarios ---------------------------------------------------------------------------------


def ink_answered(app):
    """Live ink: a loop round a line of a window, asked about, is answered on that window. Claude is
    sent the window's picture and its text, and its circle lands on the words it names."""
    claude, env = fake_claude(app)
    with open(os.path.join(claude, 'answer.json'), 'w') as f:
        json.dump({'say': 'That is the order summary.', 'marks': [{'kind': 'circle', 'words': LINES[0], 'label': 'here'}]}, f)
    launch(app, **env)
    require_screen_recording(app, True)
    window, lines = page(app)
    ink = draw_note(app, lines[1])
    if ink['noteTarget'] != 'responder claude':
        raise Failed(f"the note is aimed at {ink['noteTarget']}, not Claude on the screen")
    offset = app.log_size()
    ask(app)
    answered = app.wait_log('[live-ink] answered', offset, timeout=30)
    app.report.step('Claude answered', detail=answered.split('] ', 1)[1])
    drew = app.wait_log('[live-ink] drew answer', offset)
    if ' dropped=0 ' not in drew:
        raise Failed(f'the answer was not drawn whole: {drew}')
    ink = wait_ink(app, lambda ink: (ink['ask'] or {}).get('phase') == 'answered' and ink['reply'] is not None,
                   'the answer and its reply on the screen')
    if not ink['ask'].get('sayLength'):
        raise Failed(f"the reply has no words: {ink['ask']}")
    asks = [m for m in claude_messages(claude) if 'starting you up' not in m['text']]
    if len(asks) != 1 or not asks[0]['images']:
        raise Failed(f'Claude was not sent one ask with a picture: {asks}')
    sent = re.findall(r'(?m)^t\d+ \d+ \d+ \d+ \d+ (.*)$', asks[0]['text'])
    if not any(LINES[1] in words for words in sent):
        raise Failed(f"the window's text did not reach Claude: {sent}")
    app.report.step("Claude was sent the window's picture and its text", detail=f'{len(sent)} lines')
    shapes = [m for m in ink['marks'] if m['agent'] and m['type'] in ('ellipse', 'rectangle')]
    if len(shapes) != 1 or shapes[0]['window'] != window or not inside(lines[0], shapes[0]['frame']):
        raise Failed(f'the answer\'s marks {shapes} are not one ring round {LINES[0]!r} at {lines[0]} on window {window}')
    app.report.step('the answer rings the words Claude named, on the window', detail=f"{shapes[0]['type']} {shapes[0]['frame']}")
    time.sleep(1)
    capture_reply(app, ink, 'answer')
    app.command('live-ink-clear')


def ink_to_session(app):
    """Live ink: a note sent to a Claude Code session leaves the window as a card, puts one line in the
    session's inbox and starts no responder. The session's answer is a result card from it."""
    session, inbox = app.fake_session('e2e-ink-project')
    claude, env = fake_claude(app)
    launch(app, **env)
    require_screen_recording(app, True)
    _, lines = page(app)
    app.touch_alive(inbox)
    draw_note(app, lines[2])
    app.touch_alive(inbox)
    offset = app.log_size()
    ask(app, session=session)
    sent = app.wait_log('[live-ink] sent to a session', offset, timeout=20)
    app.report.step('the note was sent', detail=sent.split('] ', 1)[1])
    end = time.monotonic() + 10
    while not app.lines_in(inbox) and time.monotonic() < end:
        time.sleep(0.1)
    if len(app.lines_in(inbox)) != 1:
        raise Failed(f'the inbox has {app.lines_in(inbox)}')
    line = open(os.path.join(inbox, app.lines_in(inbox)[0])).read()
    if not line.startswith(WORDS) or "Drawn with Vignette's live ink on" not in line:
        raise Failed(f'the request line does not carry the words and the place: {line[:200]}')
    app.report.step('one line in the inbox with the words and where they were drawn', detail=line.strip()[:160])
    ink = wait_ink(app, lambda ink: not person_marks(ink) and ink['note'] is None, 'the ink leaving the window')
    app.report.step('the ink left the window')
    s = app.wait_state(lambda s: any(os.path.basename(c['file']).startswith('Live ink note') and c['drawing']
                                     for c in s['stack']['cards']), 'the note card with its drawing in the corner')
    card = next(c for c in s['stack']['cards'] if os.path.basename(c['file']).startswith('Live ink note'))
    app.report.step('the note is a card with the ink as its drawing', detail=os.path.basename(card['file']))
    if claude_messages(claude):
        raise Failed(f'a responder was sent {claude_messages(claude)}')
    app.report.step('no responder was started')

    image = re.search(r'"([^"]+/image\.png)"', line)
    if not image:
        raise Failed(f'the request line names no image: {line[:200]}')
    answer = os.path.join(app.folder, 'answer.json')
    with open(answer, 'w') as f:
        json.dump({'say': 'That total is right.', 'marks': [{'kind': 'circle', 'words': LINES[2], 'label': 'checked'}]}, f)
    helper = os.path.join(app.support, 'agent-plugin', 'plugins', 'vignette', 'skills', 'vignette', 'scripts', 'reply')
    offset = app.log_size()
    result = subprocess.run(['sh', helper, '--ticket', os.path.join(os.path.dirname(image.group(1)), 'ticket.json'),
                             '--answer', answer], env=dict(os.environ, HOME=app.home, CFFIXED_USER_HOME=app.home),
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise Failed(f'the answer was not accepted: exit {result.returncode} {result.stdout} {result.stderr}')
    app.report.step('the session answered with the reply helper', detail=result.stdout.strip()[:160])
    drawn = app.wait_log('[live-ink] result for request=', offset, timeout=15)
    if 'marks=1 notFound=0' not in drawn:
        raise Failed(f'the answer\'s circle was not found on the window: {drawn}')
    made = app.wait_log('[live-ink] result card', offset, timeout=15)
    s = app.wait_state(lambda s: any(os.path.basename(c['file']).startswith('Live ink result') and c['drawing']
                                     and c['agent'] == 'claude' for c in s['stack']['cards']), 'the result card from Claude')
    card = next(c for c in s['stack']['cards'] if os.path.basename(c['file']).startswith('Live ink result'))
    app.report.step('the answer is a result card from the session, with its circle', detail=made.split('] ', 1)[1])
    time.sleep(1)
    x, y, w, h = card['frame']
    app.capture([x - 10, y - 10, w + 20, h + 20], 'result-card')
    app.command('dismiss')


@on_fresh_copy
def ink_no_recording(app):
    """Live ink without Screen Recording: the chord says so beside the pointer, the ink still draws,
    and an ask fails with the reason beside the ink, having sent Claude nothing of the screen."""
    claude, env = fake_claude(app)
    launch(app, **env)
    require_screen_recording(app, False)
    _, lines = page(app)
    screen = app.state()['screen']['frame']
    app.command('live-ink-chord-down')
    time.sleep(0.8)
    # The notice is drawn beside the pointer and is not in the state, so it is evidence for a reader.
    app.capture(screen, 'chord-notice')
    detail = app.command('live-ink-stroke', 'points=' + urllib.parse.quote(loop_around(lines[1]), safe=''))
    if not detail.startswith('drew ellipse'):
        raise Failed(f'the loop drew {detail}, not an ellipse')
    app.command('live-ink-chord-up')
    wait_ink(app, lambda ink: ink['note'] is not None and ink['new'] == 1, 'the note opening on the ink')
    app.report.step('the ink drew and its note opened')
    offset = app.log_size()
    ask(app)
    app.wait_log('[live-ink] error packet screen-recording', offset)
    ink = failed_ask(app, 'Live ink needs Screen Recording permission to see the screen.')
    if any(m['images'] for m in claude_messages(claude)):
        raise Failed('Claude was sent a picture')
    app.report.step('Claude was sent no picture')
    time.sleep(1)
    capture_reply(app, ink, 'failure')
    app.command('live-ink-clear')


def ink_no_claude(app):
    """Live ink with no `claude` on the Mac: the note still opens, aimed at Claude, and an ask says
    Vignette couldn't find Claude Code, beside the ink, which stays."""
    launch(app)
    app.wait_log('claude=none', 0)
    require_screen_recording(app, True)
    app.wait_log('[live-ink] responder notInstalled agent=claude', 0)
    _, lines = page(app)
    ink = draw_note(app, lines[1])
    if ink['noteTarget'] != 'responder claude' or ink['responders']['claude']['availability'] != 'notInstalled':
        raise Failed(f"the note is aimed at {ink['noteTarget']} with Claude {ink['responders']['claude']}")
    app.report.step('the note is aimed at Claude, which is not installed')
    offset = app.log_size()
    ask(app)
    app.wait_log('[live-ink] not asking: claude cannot answer', offset)
    ink = failed_ask(app, "Vignette couldn't find Claude Code. You can send your ink to a session.")
    time.sleep(1)
    capture_reply(app, ink, 'failure')
    app.command('live-ink-clear')


def ink_claude_shows_no_tools(app):
    """Live ink with a `claude` that writes no `init` line, so nothing shows it started without tools:
    Vignette stops it after the warm-up, and an ask fails beside the ink having sent it nothing of the
    screen."""
    claude, env = fake_claude(app)
    open(os.path.join(claude, 'no-init'), 'w').close()
    launch(app, **env)
    require_screen_recording(app, True)
    _, lines = page(app)
    # The first stroke starts Claude, so its refusal may come before the ask.
    offset = app.log_size()
    draw_note(app, lines[1])
    ask(app)
    app.wait_log('[live-ink] responder error not-isolated', offset, timeout=20)
    ink = failed_ask(app, 'Live ink stopped Claude, which started with tools.')
    if any(m['images'] for m in claude_messages(claude)):
        raise Failed('Claude was sent a picture')
    app.report.step('Claude was stopped after its warm-up and sent no picture')
    time.sleep(1)
    capture_reply(app, ink, 'failure')
    app.command('live-ink-clear')


ALL = [ink_answered, ink_to_session, ink_no_recording, ink_no_claude, ink_claude_shows_no_tools]
