"""The end-to-end scenarios. Each takes an `App` on a fresh scratch home and raises `Failed` at the
first check that does not hold. A scenario marked `needs_input` posts keys or clicks, gated on the
test copy's own state, and runs only with `e2e.py run --input`."""
import json
import os
import re
import shutil
import subprocess
import time
import urllib.parse

from e2e import AGENT, PERSON, PROBE, Failed, color_near, pixels

KEY_R, KEY_RETURN = 15, 36


def needs_input(scenario):
    scenario.needs_input = True
    return scenario


# ---- Shared steps ------------------------------------------------------------------------------


def start(app, **env):
    app.prepare()
    line = app.launch(**env)
    app.report.step('launched', detail=line.split('] ', 1)[1])


def push(app, marks=None, name='Checkout at 1600.png', agent='claude'):
    """An agent's push through `add`, optionally with marks. Returns the copy's path in the watch
    folder and the command's detail."""
    source = app.image(name)
    query = app.file_query(source) + f'&agent={agent}'
    if marks is not None:
        marks_path = os.path.join(app.folder, 'marks.json')
        with open(marks_path, 'w') as f:
            json.dump(marks, f)
        query += '&marks=' + urllib.parse.quote(marks_path, safe='')
    detail = app.command('add', query)
    copy = os.path.join(app.watch, detail.split(' marks=')[0].split(' agent=')[0].strip())
    if not os.path.exists(copy):
        copy = os.path.join(app.watch, name)
    if not os.path.exists(copy):
        raise Failed(f'add answered {detail!r} but {name} is not in the watch folder')
    return copy, detail


def card_for(s, path):
    return next((c for c in s['stack']['cards'] if os.path.realpath(c['file']) == os.path.realpath(path)), None)


def open_editor(app, path):
    offset = app.log_size()
    detail = app.command('annotate', app.file_query(path))
    app.report.step('annotate', detail=detail)
    app.wait_log('[annotate] loaded', offset, timeout=10)
    line = app.wait_log('[annotate] takes events', offset, timeout=10)
    if 'reached=true' not in line:
        raise Failed(f'the editor never took presses: {line}')
    s = app.wait_state(lambda s: s['annotator']['windowVisible'] and s['annotator']['key'] and s['editor']['open'],
                       'the editor coming up and taking the keys')
    app.report.step('editor up and key', detail=line.split('] ', 1)[1])
    return s


def close_editor(app):
    app.command('cancel')
    app.wait_state(lambda s: not s['annotator']['windowVisible'], 'the editor closing')
    app.report.step('editor closed')


def scan_row(png, y, x0, x1):
    size, colors = pixels(png, [(x, y) for x in range(x0, x1)])
    return [colors.get((x, y)) for x in range(x0, x1)]


def check_marks_drawn(app, png, rect, rgb, who):
    """The rectangle's left edge, `rect` in the image's px, is drawn in `rgb` with the white edge
    beside it, and the middle of the rectangle is the screenshot's own pixels."""
    x, y, w, h = rect
    row = scan_row(png, y + h // 2, max(0, x - 20), x + 20)
    if not any(c and color_near(c, rgb) for c in row):
        raise Failed(f"no {who} colour across the rectangle's left edge in {os.path.basename(png)}: {row}")
    if not any(c and color_near(c, (255, 255, 255), 30) for c in row):
        raise Failed(f"no white edge beside the rectangle in {os.path.basename(png)}: {row}")
    app.report.step(f'the rendering has the {who} colour and the white edge')


# ---- Without input -----------------------------------------------------------------------------


def launch(app):
    """A test launch comes up on its scratch files and reaches nothing of the person's.

    It uses no codex and no herdr, registers no login item, answers every command it lists, and
    answers a bad file with an error line."""
    start(app)
    app.wait_log('[tools] test launch: codex=none herdr=none', 0)
    app.report.step('no codex and no herdr in a test launch')
    s = app.state()
    if s['app']['launchAtLogin'] or s['app']['loginItem'] == 'enabled':
        raise Failed(f"login item: launchAtLogin={s['app']['launchAtLogin']} loginItem={s['app']['loginItem']}")
    app.report.step('no login item', detail=s['app']['loginItem'])
    offset = app.log_size()
    app.command('help')
    listed = set(re.findall(r'\[help\] ([a-z-]+):', app.log_since(offset)))
    wanted = {'add', 'annotate', 'copy', 'copy-annotated', 'stitch', 'trash', 'open', 'paths', 'state', 'recent',
              'last', 'dismiss', 'cancel', 'reply', 'requests', 'help', 'settings', 'restore-apple-defaults'}
    missing = wanted - listed
    if missing:
        raise Failed(f"help does not list {', '.join(sorted(missing))}")
    app.report.step('help lists every command', detail=f'{len(listed)} commands')
    outside = app.command_error('annotate', app.file_query('/etc/hosts'))
    if 'outside-watch-folder' not in outside:
        raise Failed(f'a file outside the watch folder: {outside}')
    missing_file = app.command_error('copy', app.file_query(os.path.join(app.watch, 'nothing here.png')))
    if 'missing-file' not in missing_file:
        raise Failed(f'a missing file: {missing_file}')
    missing_file = app.command_error('add', app.file_query(os.path.join(app.folder, 'nothing here.png')))
    if 'missing-file' not in missing_file:
        raise Failed(f'a missing file: {missing_file}')
    app.report.step('bad files answer with error lines')


def agent_push(app):
    """An agent's push shows a card with its marks, drawn in the agent's colour.

    A colour the agent names is ignored and logged, and Copy Drawing renders the marks with the
    white edge over the screenshot's own pixels."""
    start(app)
    offset = app.log_size()
    marks = [{'type': 'rectangle', 'x': 0.1, 'y': 0.1, 'w': 0.3, 'h': 0.3, 'color': 'red'},
             {'type': 'arrow', 'x': 0.6, 'y': 0.7, 'x2': 0.45, 'y2': 0.35},
             {'type': 'text', 'x': 0.55, 'y': 0.75, 'text': 'this column overflows'}]
    copy, detail = push(app, marks)
    if 'marks=3' not in detail:
        raise Failed(f'add did not join 3 marks: {detail}')
    app.report.step('add joined 3 marks', detail=detail)
    app.wait_log('[marks] color ignored', offset)
    app.report.step("the agent's colour was ignored and logged")
    s = app.wait_state(lambda s: (c := card_for(s, copy)) is not None and c['drawing'] and c['agent'] == 'claude',
                       'a card with the drawing and the agent')
    card = card_for(s, copy)
    app.report.step('the card names the agent and has the drawing')
    time.sleep(0.6)
    app.capture(card['frame'], 'card')
    detail = app.command('copy-annotated', app.file_query(copy), timeout=30)
    if '1 with annotations' not in detail:
        raise Failed(f'copy-annotated: {detail}')
    rendering = copy[:-4] + '-annotated.png'
    if not os.path.exists(rendering):
        raise Failed(f'no {os.path.basename(rendering)}')
    app.report.image(rendering)
    check_marks_drawn(app, rendering, (160, 100, 480, 300), AGENT, 'agent')
    _, before = pixels(copy, [(400, 250)])
    _, after = pixels(rendering, [(400, 250)])
    if before != after:
        raise Failed(f"the rendering changed the screenshot's pixels inside the mark: {before} → {after}")
    types = subprocess.run([PROBE, 'pasteboard', 'types'], capture_output=True, text=True).stdout
    if 'public.file-url' not in types:
        raise Failed(f'the pasteboard does not hold the rendering: {types}')
    app.report.step('Copy Drawing put the rendering on the pasteboard')
    app.command('dismiss')


def annotate_open(app):
    """Draw opens the editor on a pushed card with the agent's marks, and the bar offers Copy
    alone when no session is listening.

    Copy alone is also what shows that the test launch listed none of the person's Codex threads."""
    start(app)
    copy, _ = push(app, [{'type': 'rectangle', 'x': 0.2, 'y': 0.2, 'w': 0.2, 'h': 0.2},
                         {'type': 'text', 'x': 0.5, 'y': 0.5, 'text': 'look here'}])
    s = open_editor(app, copy)
    marks = s['editor']['marks']
    if len(marks) != 2 or not all(m.get('agent') for m in marks):
        raise Failed(f"the editor has {marks}, not the agent's two marks")
    app.report.step("the editor has the agent's marks")
    s = app.wait_state(lambda s: (s['annotator'].get('offer') or {}).get('listed'), 'the session list', timeout=15)
    offer = s['annotator']['offer']
    if offer.get('kind') != 'copy':
        raise Failed(f'the bar offers {offer}; a test launch with no fake session should offer Copy alone')
    app.report.step('the bar offers Copy alone', detail=json.dumps(offer))
    frame = s['annotator']['frame']
    toolbar = s['annotator']['toolbar'] or frame
    top, bottom = min(frame[1], toolbar[1]), max(frame[1] + frame[3], toolbar[1] + toolbar[3])
    app.capture([frame[0] - 20, top - 20, frame[2] + 40, bottom - top + 40], 'editor')
    close_editor(app)


def send_target(app):
    """With a fake Claude Code session listening, Send goes to it and to nothing else."""
    session, inbox = app.fake_session('e2e-project')
    start(app)
    copy, _ = push(app, None, name='Settings page.png', agent='codex')
    app.touch_alive(inbox)
    open_editor(app, copy)
    s = app.wait_state(lambda s: (s['annotator'].get('offer') or {}).get('listed'), 'the session list', timeout=15)
    offer = s['annotator']['offer']
    if offer.get('kind') != 'send' or offer.get('session') != session or offer.get('client') != 'claude':
        raise Failed(f'the bar offers {offer}, not Send to the fake session {session}')
    app.report.step('the bar offers Send to the fake session', detail=json.dumps(offer))
    close_editor(app)


def pasteboard_types():
    out = subprocess.run([PROBE, 'pasteboard', 'types'], capture_output=True, text=True, check=True).stdout.splitlines()
    return out[1].split() if len(out) > 1 else []


def copy_types(app):
    """Copy puts a capture's own bytes on the pasteboard under its own type: a JPEG as
    public.jpeg, a PNG as public.png."""
    start(app)
    for name, uti in [('Screenshot copy.jpg', 'public.jpeg'), ('Screenshot copy.png', 'public.png')]:
        path = app.image(name, folder=app.watch)
        time.sleep(1)
        app.command('copy', app.file_query(path))
        types = pasteboard_types()
        if uti not in types or (uti == 'public.png' and 'public.jpeg' in types):
            raise Failed(f'copying {name} put {types} on the pasteboard')
        out = os.path.join(app.folder, 'pasted.' + name.rsplit('.', 1)[1])
        subprocess.run([PROBE, 'pasteboard', 'data', uti, out], check=True)
        if open(out, 'rb').read() != open(path, 'rb').read():
            raise Failed(f"the {uti} on the pasteboard is not {name}'s own bytes")
        app.report.step(f'{name} copies as its own {uti} bytes', detail=' '.join(types))
    app.command('dismiss')


def stitch(app):
    """Stitch makes one image from two and puts it in the watch folder."""
    start(app)
    a = app.image('Screenshot a.png', folder=app.watch)
    b = app.image('Screenshot b.png', 1200, 900, folder=app.watch)
    time.sleep(1)
    detail = app.command('stitch', app.file_query(a, b), timeout=30)
    out = detail.split(' from ')[0]
    if not os.path.exists(out) or '2 images' not in detail:
        raise Failed(f'stitch: {detail}')
    app.report.image(out)
    app.report.step('stitched', detail=detail)
    # With no stack showing, the stitched card comes up wearing the copied mark.
    app.wait_state(lambda s: (c := card_for(s, out)) is not None and c['copied'], 'the stitched card with its copied mark')
    app.report.step('the stitched card shows the copied mark')
    app.command('dismiss')


def relaunch(app):
    """Drawings and settings survive a relaunch."""
    start(app)
    copy, _ = push(app, [{'type': 'rectangle', 'x': 0.3, 'y': 0.3, 'w': 0.2, 'h': 0.2}])
    s = app.wait_state(lambda s: len(s['drawings']) == 1, 'the drawing being written')
    keys = s['drawings']
    app.stop()
    app.report.step('stopped')
    start(app)
    s = app.state()
    if s['drawings'] != keys:
        raise Failed(f"drawings after the relaunch: {s['drawings']}, before: {keys}")
    app.report.step('the drawing is still there')
    settings = json.load(open(app.settings))
    if settings.get('setup') != 'done' or settings.get('recentHotkey') != 'ctrl+opt+cmd+9':
        raise Failed(f'the settings file changed: {settings}')
    app.report.step('the settings are unchanged')


def settings_repair(app):
    """A bad value in settings.json is repaired and logged, and a file that does not parse is
    set aside as settings.json.invalid."""
    app.write_settings(ui={'personColor': 'not a colour', 'strokeWidth': 900})
    start(app)
    log = app.log_since(0)
    if 'personColor' not in log or 'strokeWidth' not in log:
        raise Failed('the bad colour and the bad width were not both logged')
    app.report.step('the bad colour and width were repaired and logged')
    app.stop()
    with open(app.settings, 'w') as f:
        f.write('{"version": 2, "setup": "done",')
    start(app)
    if not os.path.exists(app.settings + '.invalid'):
        raise Failed('the file that does not parse was not set aside')
    app.report.step('the file that does not parse was set aside')
    # A file replaced with defaults runs setup again; that window is this launch's to close.
    app.stop()


def apple_thumbnail(app):
    """Apple's show-thumbnail in the test copy's own screencapture domain, or None when unset."""
    env = dict(os.environ, CFFIXED_USER_HOME=app.home)
    out = subprocess.run(['defaults', 'read', f"{app.copy['bundle']}.screencapture", 'show-thumbnail'],
                         env=env, capture_output=True, text=True)
    return None if out.returncode else out.stdout.strip() == '1'


def first_launch(app):
    """A first launch shows setup and turns Apple's thumbnail off. Quitting during setup puts the
    thumbnail back and leaves setup to show again at the next launch."""
    # No settings file: this is a first launch. Only Apple's location and the update checks are set.
    app.defaults(f"{app.copy['bundle']}.screencapture", 'location', app.watch)
    app.defaults(app.copy['bundle'], 'SUEnableAutomaticChecks', '-bool', 'false')
    offset = app.log_size()
    app.launch()   # not start(), which writes a settings file with setup done
    app.wait_log('[setup] shown', offset)
    if apple_thumbnail(app) is not False:
        raise Failed(f"Apple's thumbnail is {apple_thumbnail(app)} while Vignette runs, not off")
    app.report.step("setup is shown and Apple's thumbnail is off")
    app.stop()
    if apple_thumbnail(app) is not True:
        raise Failed(f"Apple's thumbnail is {apple_thumbnail(app)} after quitting, not back on")
    with open(app.settings) as f:
        if json.load(f).get('setup') != 'unasked':
            raise Failed('setup was recorded as done though it was quit part way')
    app.report.step("quitting put Apple's thumbnail back and left setup to ask again")
    offset = app.log_size()
    app.launch()
    app.wait_log('[setup] shown', offset)
    if apple_thumbnail(app) is not False:
        raise Failed("the next launch did not turn Apple's thumbnail off again")
    app.report.step("the next launch shows setup again and turns the thumbnail off")
    app.stop()


def upgrade(app):
    """A settings file from 0.1.1, which wrote every ui value, keeps only what differs from
    0.1.1's defaults: those are the person's choices."""
    old_defaults = {'newTextSize': 24, 'textWeight': 500, 'textLineHeight': 1.35, 'slideInDuration': 0.75,
                    'annotationScreenInset': 65}
    app.write_settings(version=1, ui=dict(old_defaults, motion=0.5))
    start(app)
    app.wait_state(lambda s: True, 'the state')
    with open(app.settings) as f:
        data = json.load(f)
    if data.get('version') != 2 or data.get('ui') != {'motion': 0.5}:
        raise Failed(f"after the upgrade the file is version {data.get('version')} with ui {data.get('ui')}")
    app.report.step("0.1.1's defaults were dropped and the one choice kept", detail=json.dumps(data['ui']))
    app.stop()


# ---- With input --------------------------------------------------------------------------------


def draw_box(app, s):
    """Draws a rectangle in the middle of the open editor's frame, gated on the editor being key."""
    app.require_key(s, 'annotator')
    x, y, w, h = s['annotator']['frame']
    app.keys('annotator', 'key', KEY_R)
    app.wait_state(lambda s: s['annotator'].get('tool') == 'rectangle', 'the rectangle tool')
    s = app.state()
    app.require_key(s, 'annotator')
    app.input('glidedrag', round(x + w * 0.3), round(y + h * 0.3), round(x + w * 0.6), round(y + h * 0.6), 0.5)
    s = app.wait_state(lambda s: len(s['editor']['marks']) == 1, 'the box being drawn')
    app.report.step('drew a box')
    return s


@needs_input
def draw_and_done(app):
    """A person draws a box and presses Return: the rendering is on the pasteboard, in the
    person's colour."""
    start(app)
    path = app.image('Screenshot draw.png', folder=app.watch)
    time.sleep(1)
    s = open_editor(app, path)
    s = draw_box(app, s)
    mark = s['editor']['marks'][0]['frame']
    offset = app.log_size()
    app.keys('annotator', 'key', KEY_RETURN)
    line = app.wait_log('[annotate] done', offset, timeout=15)
    rendering = path[:-4] + '-annotated.png'
    if not os.path.exists(rendering):
        raise Failed(f'no rendering after Return: {line}')
    app.report.image(rendering)
    check_marks_drawn(app, rendering, [round(v) for v in mark], PERSON, 'person')


@needs_input
def send_and_reply(app):
    """Send puts one request line in a fake session's inbox, and a reply through the skill's helper
    comes back as a card. The helper refuses a ticket other than the one beside the image."""
    session, inbox = app.fake_session('e2e-project')
    start(app)
    path = app.image('Screenshot send.png', folder=app.watch)
    time.sleep(1)
    app.touch_alive(inbox)
    s = open_editor(app, path)
    app.wait_state(lambda s: (s['annotator'].get('offer') or {}).get('session') == session, 'Send to the fake session')
    s = draw_box(app, app.state())
    app.touch_alive(inbox)
    offset = app.log_size()
    app.keys('annotator', 'key', KEY_RETURN, 'cmd')
    app.wait_log('[send] ok', offset, timeout=20)
    end = time.monotonic() + 10
    while not app.lines_in(inbox) and time.monotonic() < end:
        time.sleep(0.1)
    lines = app.lines_in(inbox)
    if len(lines) != 1:
        raise Failed(f'the inbox has {lines}')
    line = open(os.path.join(inbox, lines[0])).read()
    image = re.search(r'"([^"]+/image\.png)"', line)
    if not image:
        raise Failed(f'the request line names no image: {line}')
    app.report.step('one request line in the inbox', detail=line.strip()[:120])
    ticket = os.path.join(os.path.dirname(image.group(1)), 'ticket.json')
    marks = os.path.join(app.folder, 'reply.json')
    with open(marks, 'w') as f:
        json.dump([{'type': 'text', 'x': 0.1, 'y': 0.1, 'text': 'here'}], f)
    helper = os.path.join(app.support, 'agent-plugin', 'plugins', 'vignette', 'skills', 'vignette', 'scripts', 'reply')
    env = dict(os.environ, HOME=app.home, CFFIXED_USER_HOME=app.home)
    # The helper takes only the ticket.json Vignette wrote beside the image; a copy elsewhere is
    # refused before anything reaches the app. A guessed secret is ScreenshotRequestsTests' case.
    copy = os.path.join(os.path.dirname(ticket), 'ticket-copy.json')
    shutil.copy(ticket, copy)
    try:
        refused = subprocess.run(['sh', helper, '--ticket', copy, '--marks', marks], env=env, capture_output=True, text=True)
    finally:
        os.remove(copy)
    if refused.returncode == 0 or 'not a ticket Vignette wrote' not in refused.stdout:
        raise Failed(f'a ticket copied elsewhere was not refused: exit {refused.returncode} {refused.stdout}')
    app.report.step('a ticket copied elsewhere is refused', detail=refused.stdout.strip()[:160])
    result = subprocess.run(['sh', helper, '--ticket', ticket, '--marks', marks], env=env, capture_output=True, text=True)
    if result.returncode != 0:
        raise Failed(f'the reply was not accepted: exit {result.returncode} {result.stdout} {result.stderr}')
    app.report.step('the reply was accepted', detail=result.stdout.strip()[:120])
    s = app.wait_state(lambda s: any('Agent reply' in c['file'] for c in s['stack']['cards']), 'the reply card', timeout=15)
    app.report.step('the reply is a card')


@needs_input
def corner_select(app):
    """Two captures share the corner. Hovering one shows its selection circle, and a click on the
    circle makes the corner the stack, with the card selected and the strip out."""
    start(app)
    app.image('Screenshot one.png', folder=app.watch)
    time.sleep(0.8)
    second = app.image('Screenshot two.png', folder=app.watch)
    s = app.wait_state(lambda s: s['stack']['visible'] and not s['stack']['isStack'] and len(s['stack']['cards']) == 2,
                       'both captures in the corner')
    app.report.step('two thumbnails in the corner')
    # The corner never takes the keys, so the gate is this copy's own card, read in the same step.
    card = card_for(s, second)
    if card is None or card['frame'] is None:
        raise Failed(f'no frame for {os.path.basename(second)} in the corner')
    x, y, w, h = card['frame']
    app.input('glide', round(x + w / 2), round(y + h / 2), 0.4)
    s = app.wait_state(lambda s: (s['stack']['hovered'] or '').endswith('Screenshot two.png'), 'the card being hovered', timeout=3)
    app.capture([x - 10, y - 10, w + 20, h + 20], 'corner-hover')
    card = card_for(s, second)
    if card is None or s['stack']['isStack']:
        raise Failed('the corner changed before the click')
    x, y, w, h = card['frame']
    # The circle sits CardView.buttonPad in from the top-left corner, ui.selectionCircleSize across.
    circle = (round(x + 6 + 9.5), round(y + 6 + 9.5))
    app.input('glide', *circle, 0.2)
    app.input('click', *circle)
    s = app.wait_state(lambda s: s['stack']['isStack'] and len(s['stack']['selected']) == 1 and s['stack']['strip'] is not None,
                       'the corner becoming the stack with the card selected', timeout=3)
    if not s['stack']['key']:
        raise Failed('the stack the corner became does not hold the keys')
    app.report.step('a click on the circle makes the corner the stack', detail=f"selected={len(s['stack']['selected'])}")
    app.command('dismiss')


def to_screen(s, image_width, px):
    """A point of the image, in px, on screen, for the editor at its fitted size."""
    x, y, w, h = s['annotator']['frame']
    k = w / image_width
    return round(x + px[0] * k), round(y + px[1] * k)


@needs_input
def agent_marks_editable(app):
    """A person can select an agent's mark with a click and move it by dragging."""
    start(app)
    copy, _ = push(app, [{'type': 'rectangle', 'x': 0.25, 'y': 0.25, 'w': 0.3, 'h': 0.3}])
    s = open_editor(app, copy)
    mark = s['editor']['marks'][0]
    if not mark.get('agent'):
        raise Failed(f"the pushed mark is not the agent's: {mark}")
    x, y, w, h = mark['frame']
    edge = to_screen(s, 1600, (x, y + h / 2))
    app.require_key(app.state(), 'annotator')
    app.input('glide', *edge, 0.3)
    app.input('click', *edge)
    s = app.wait_state(lambda s: s['editor']['selection'] == [0], "the agent's mark being selected", timeout=3)
    app.report.step("a click on the agent's rectangle selects it")
    app.require_key(s, 'annotator')
    app.input('glidedrag', *edge, edge[0] + 80, edge[1] + 40, 0.5)
    s = app.wait_state(lambda s: s['editor']['marks'][0]['frame'][0] > x + 20, "the agent's mark moving", timeout=3)
    moved = s['editor']['marks'][0]
    app.report.step('a drag moves it', detail=f"x {round(x)} → {round(moved['frame'][0])}, agent={moved.get('agent')}")
    close_editor(app)


ALL = [launch, first_launch, upgrade, agent_push, annotate_open, send_target, copy_types, stitch, relaunch, settings_repair, draw_and_done, send_and_reply, agent_marks_editable, corner_select]
