"""Send's end-to-end scenarios for a project with no Claude Code session running: Continue last
session and New session, started through the fake Herdr app and hc (`fake_herdr.py`)."""
import json
import time

import fake_herdr
from e2e import Failed
from scenarios import KEY_RETURN, KEY_SPACE, KEY_TAB, click_to_open, close_editor, needs_input, open_editor, push, start


def send_offers_start(app):
    """With no Claude Code session running and a project used lately, the bar offers an empty
    target to pick from rather than Send to anything, and nothing is started."""
    app.past_project('e2e-site')
    start(app, **app.fake_herdr())
    copy, _ = push(app, None, name='Site nav.png', agent='codex')
    open_editor(app, copy)
    s = app.wait_state(lambda s: (s['annotator'].get('offer') or {}).get('kind') == 'choose', 'the empty target', timeout=15)
    app.report.step('the bar offers a target to choose', detail=json.dumps(s['annotator']['offer']))
    started = [c for c in app.herdr_calls() if c[:2] == ['hc', 'run']]
    if started:
        raise Failed(f'hc was asked to start something nobody picked: {started}')
    close_editor(app)


@needs_input
def send_starts_session(app):
    """Picking Continue last session in the target's menu and sending starts a terminal in the
    project's folder, in a new tab of the space the Herdr window shows, resumes that session there,
    names the tab with the project, and puts the line in its inbox once it is up."""
    folder, session = app.past_project('e2e-site')
    start(app, **app.fake_herdr())
    path = app.image('Screenshot site.png', folder=app.watch)
    time.sleep(1)
    click_to_open(app, path)
    app.wait_state(lambda s: (s['annotator'].get('offer') or {}).get('kind') == 'choose' and s['annotator']['key'],
                   'the empty target', timeout=15)
    app.keys('annotator', 'key', KEY_TAB, 'shift')
    s = app.wait_state(lambda s: s['annotator'].get('toolbarFocus') == 'target', 'the target focused', timeout=5)
    app.keys('annotator', 'key', KEY_SPACE)
    time.sleep(0.8)
    app.capture(s['screen']['frame'], 'target-menu')
    app.input('type', 'e2e-site', 40)
    time.sleep(0.5)
    app.capture(s['screen']['frame'], 'target-menu-search')
    app.input('key', KEY_RETURN)
    s = app.wait_state(lambda s: (s['annotator'].get('offer') or {}).get('session') == session, 'Continue picked', timeout=5)
    app.report.step('Continue last session is the target', detail=json.dumps(s['annotator']['offer']))
    offset = app.log_size()
    app.keys('toolbar', 'key', KEY_RETURN)
    app.wait_log('[send] ok', offset, timeout=60)
    calls = app.herdr_calls()
    run = next((c for c in calls if c[:2] == ['hc', 'run']), None)
    if not run or run[run.index('--cwd') + 1] != folder or 'herdr.space=' + fake_herdr.SPACE not in run:
        raise Failed(f'no terminal in {folder} in the window\'s space: {calls}')
    tab = next((w.split('=', 1)[1] for w in run if w.startswith('herdr.tab=')), None)
    if run[run.index('--') + 1:][-3:] != ['claude', '--resume', session]:
        raise Failed(f'the terminal did not resume {session}: {run}')
    app.report.step('hc started a terminal in the folder and resumed the session', detail=' '.join(run))
    deadline = time.time() + 10
    while not any(c[:3] == ['herdr-app', 'do', 'tab.rename'] and json.loads(c[3]) == {'id': tab, 'name': 'e2e-site'}
                  for c in app.herdr_calls()):
        if time.time() > deadline:
            raise Failed(f'the tab {tab} was not named e2e-site: {app.herdr_calls()}')
        time.sleep(0.25)
    app.report.step('the tab is named with the project', detail=tab)
    inbox = app.inbox_of(session)
    if not inbox or len(app.lines_in(inbox)) != 1:
        raise Failed(f'the started session has no request line: {inbox}')
    app.report.step('one request line in the started session\'s inbox')


ALL = [send_offers_start, send_starts_session]
