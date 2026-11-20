"""The keys while the bar's message field holds them, after it took them on its own as the image
opened: which keys the field keeps, and which do what they do on the image. Each scenario has a
fake Claude Code session listening, so the bar offers Send and the field takes the keys. All of
them post keys, so they run only with `e2e.py run --input`."""
import os
import subprocess
import time

from e2e import PROBE, Failed
from scenarios import KEY_A, KEY_EQUALS, KEY_RETURN, KEY_ZERO, click_to_open, close_editor, field_has_keys, needs_input, start

KEY_C, KEY_V, KEY_W, KEY_ESC, KEY_DOWN = 8, 9, 13, 53, 125


def open_with_field(app, name):
    """Opens a new screenshot with a click, as a person does, and waits for the message field to
    take the keys. Returns the fake session and its inbox."""
    session, inbox = app.fake_session('e2e-project')
    start(app)
    path = app.image(name, folder=app.watch)
    time.sleep(1)
    app.touch_alive(inbox)
    click_to_open(app, path)
    field_has_keys(app, session)
    return session, inbox


def send_from_field(app, inbox):
    """Return in the field, then the one line Send put in the session's inbox."""
    app.touch_alive(inbox)
    offset = app.log_size()
    app.keys('toolbar', 'key', KEY_RETURN)
    app.wait_log('[send] ok', offset, timeout=20)
    end = time.monotonic() + 10
    while not app.lines_in(inbox) and time.monotonic() < end:
        time.sleep(0.1)
    lines = app.lines_in(inbox)
    if len(lines) != 1:
        raise Failed(f'the inbox has {lines}')
    return open(os.path.join(inbox, lines[0])).read()


def require_field_keys(app, what):
    s = app.state()
    if not (s['annotator']['toolbarKey'] and s['annotator']['toolbarFocus'] == 'message'):
        raise Failed(f"the message field lost the keys after {what}: focus {s['annotator']['toolbarFocus']}")
    return s


@needs_input
def field_esc_closes(app):
    """Esc in a message field that took the keys on its own and is still empty closes the editor,
    as Esc on the image does."""
    open_with_field(app, 'Screenshot field esc.png')
    offset = app.log_size()
    app.keys('toolbar', 'key', KEY_ESC)
    app.wait_log('[annotate] cancelled', offset, timeout=5)
    app.wait_state(lambda s: not s['annotator']['windowVisible'], 'the editor closing')
    app.report.step('Esc in the untouched field closed the editor')


@needs_input
def field_esc_with_words(app):
    """Esc in a message field with words in it hands the keys to the image, and the editor stays
    open."""
    open_with_field(app, 'Screenshot field words.png')
    app.keys('toolbar', 'type', 'nudge', 40)
    require_field_keys(app, 'typing')
    app.keys('toolbar', 'key', KEY_ESC)
    app.wait_state(lambda s: s['annotator']['key'] and not s['annotator']['toolbarKey'], 'the image taking the keys', timeout=3)
    time.sleep(0.5)
    if not app.state()['annotator']['windowVisible']:
        raise Failed('Esc in a field with words closed the editor')
    app.report.step('Esc in a field with words handed the keys to the image')
    close_editor(app)


@needs_input
def field_keys_after_pick(app):
    """After a pick in the target's menu the message field holds the keys with the caret after its
    words, so what is typed next adds to them: the line Send puts in the session holds both parts."""
    session, inbox = open_with_field(app, 'Screenshot field pick.png')
    app.keys('toolbar', 'type', 'add a', 40)
    offset = app.log_size()
    app.keys('toolbar', 'key', KEY_DOWN)
    # The menu tracks its own events, and the copy answers no command while it is open, so Return
    # in its search is posted without a gate. The field held the keys a moment before: with no
    # menu up, Return there sends at once, and the wait for the pick below fails.
    time.sleep(0.5)
    app.input('key', KEY_RETURN)
    line = app.wait_log('[send] picked', offset, timeout=5)
    if f'session={session}' not in line:
        raise Failed(f'the menu picked another session: {line}')
    app.wait_state(lambda s: s['annotator']['toolbarKey'] and s['annotator']['toolbarFocus'] == 'message',
                   'the message field holding the keys after the pick', timeout=3)
    app.report.step('the message field held the keys after the pick')
    app.keys('toolbar', 'type', ' border', 40)
    sent = send_from_field(app, inbox)
    if not sent.startswith('add a border [From Vignette: '):
        raise Failed(f'the words typed after the pick did not follow the ones before: {sent[:160]}')
    app.report.step('the words typed after the pick followed the ones before', detail=sent.strip()[:120])


@needs_input
def field_paste(app):
    """Cmd+V in a message field that took the keys on its own pastes the pasteboard's words into
    the message, not onto the image."""
    _, inbox = open_with_field(app, 'Screenshot field paste.png')
    subprocess.run(['pbcopy'], input='make it pop', text=True, check=True)
    app.keys('toolbar', 'key', KEY_V, 'cmd')
    time.sleep(0.3)
    s = require_field_keys(app, 'Cmd+V')
    if s['editor']['marks']:
        raise Failed(f"Cmd+V put {len(s['editor']['marks'])} marks on the image")
    sent = send_from_field(app, inbox)
    if not sent.startswith('make it pop [From Vignette: '):
        raise Failed(f'the pasted words are not the message: {sent[:160]}')
    app.report.step('Cmd+V pasted the words into the message', detail=sent.strip()[:120])


@needs_input
def field_cmd_w_closes(app):
    """Cmd+W in the message field closes the editor, as it does on the image."""
    open_with_field(app, 'Screenshot field close.png')
    offset = app.log_size()
    app.keys('toolbar', 'key', KEY_W, 'cmd')
    app.wait_log('[annotate] cancelled', offset, timeout=5)
    app.wait_state(lambda s: not s['annotator']['windowVisible'], 'the editor closing')
    app.report.step('Cmd+W in the field closed the editor')


@needs_input
def field_zoom_keys(app):
    """Cmd+Plus and Cmd+0 in the message field zoom the image, and the field keeps the keys."""
    open_with_field(app, 'Screenshot field zoom.png')
    s = app.wait_state(lambda s: s['annotator']['zoomPhase'] == 'landed', 'the flight landing')
    fitted = s['annotator']['frame']
    app.keys('toolbar', 'key', KEY_EQUALS, 'cmd')
    app.wait_state(lambda s: abs(s['annotator']['zoomLevel'] - 1.25) < 1e-6, 'a zoom step from the field')
    require_field_keys(app, 'Cmd+Plus')
    app.keys('toolbar', 'key', KEY_ZERO, 'cmd')
    app.wait_state(lambda s: s['annotator']['zoomLevel'] == 1 and s['annotator']['frame'] == fitted, 'Cmd+0 back to the fitted frame')
    require_field_keys(app, 'Cmd+0')
    app.report.step('Cmd+Plus and Cmd+0 in the field zoomed the image and the field kept the keys')
    close_editor(app)


@needs_input
def field_copy(app):
    """Cmd+C in a message field that took the keys on its own copies the drawing, as on the image.
    Once the field holds words and some are selected, Cmd+C copies those words instead."""
    open_with_field(app, 'Screenshot field copy.png')
    offset = app.log_size()
    app.keys('toolbar', 'key', KEY_C, 'cmd')
    app.wait_log('[annotate] copied', offset, timeout=5)
    require_field_keys(app, 'Cmd+C')
    app.report.step('Cmd+C in the untouched field copied the drawing')
    app.keys('toolbar', 'type', 'tidy', 40)
    app.keys('toolbar', 'key', KEY_A, 'cmd')
    offset = app.log_size()
    app.keys('toolbar', 'key', KEY_C, 'cmd')
    time.sleep(0.3)
    if '[annotate] copied' in app.log_since(offset):
        raise Failed('Cmd+C with words selected copied the drawing')
    out = os.path.join(app.folder, 'field-copy.txt')
    subprocess.run([PROBE, 'pasteboard', 'data', 'public.utf8-plain-text', out], check=True)
    with open(out, encoding='utf-8') as f:
        copied = f.read()
    if copied != 'tidy':
        raise Failed(f'Cmd+C with the words selected put {copied!r} on the pasteboard')
    app.report.step('Cmd+C with the words selected copied the words')
    close_editor(app)


ALL = [field_esc_closes, field_esc_with_words, field_keys_after_pick, field_paste, field_cmd_w_closes, field_zoom_keys,
       field_copy]
