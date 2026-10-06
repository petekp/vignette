#!/usr/bin/env python3
"""Sets the stage for live ink's developer demo (docs/live-ink-dev-demo-plan-2026-10-05.md).

    dev.py up      set the stage and hold it until Ctrl-C, SIGTERM or `dev.py down`
    dev.py down    take a held stage down

The stage is the trailer's, with live ink: Postcard served with live reload to a Chrome window at
desktop width and another at mobile width, and the trailer's Claude Code working on it in Ghostty.
Vignette Demo, the trailer's stage copy, runs on a settings file of its own with live ink on, and
lets screen recordings see the ink. Build it first with `../trailer/trailer.py build`.

`up` writes what a take needs to `out/dev/stage.json`: the pids, the frames and the app. Everything
it makes is under `out/dev/`, and `~/Code/postcard` is the copy Claude works in, removed after.
"""
import json
import os
import shutil
import signal
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TRAILER = os.path.join(HERE, '..', 'trailer')
sys.path.insert(0, TRAILER)

import drive      # noqa: E402
import trailer    # noqa: E402

OUT = os.path.join(HERE, 'out', 'dev')
STATE = os.path.join(OUT, 'stage.json')
CHROME = drive.CHROME
# The trailer's Claude Code is signed in once, in the main checkout's stage folder; a worktree's
# own would need a sign-in of its own.
SIGNED_IN = os.path.expanduser('~/Code/vignette/media/trailer/out/stage/claude')

PATHS = dict(trailer.PATHS, **{
    'claude': SIGNED_IN if os.path.isdir(SIGNED_IN) else trailer.PATHS['claude'],
    'stage': OUT,
    'watch': os.path.join(OUT, 'watch'),
    'settings': os.path.join(OUT, 'settings.json'),
    'pids': os.path.join(OUT, 'pids.json'),
    'dock': os.path.join(OUT, 'dock-autohide'),
    'chrome': os.path.join(OUT, 'chrome'),
})

CONFIG = {
    'app': {'settings': {
        'setup': 'done', 'copyOnCapture': False, 'agentSkill': 'off', 'hideMenuBarIcon': True,
        'launchAtLogin': False, 'recentHotkey': 'ctrl+opt+cmd+9', 'debug': True, 'liveInk': True,
    }},
    'stage': {
        'port': 5391,
        'seed': 7,
        'terminal_args': ['--font-size=12'],
        # An earlier exchange fills the terminal and titles the session, which the note's menu shows.
        'session': {'prompt': 'Which files make up the itinerary page? One line each.', 'settle': 15, 'args': []},
    },
}

# The project's instructions for this demo, in place of the trailer's, which are about a designer's
# screenshots.
INSTRUCTIONS = """# Postcard

Postcard plans trips. This folder is its front end, with a week in Tuscany as the trip it shows.

## How it is built

- Plain HTML and CSS, no build step. `index.html` is the itinerary, `stays.html` and
  `packing.html` are the other pages, and `styles.css` styles all three.
- The look: warm paper (`--page`), white cards (`--panel`), serif headings (`--serif`), terracotta
  for what matters (`--accent`) and olive for status (`--olive`). Use these variables rather than
  new colours.
- A dev server serves this folder to two browser windows beside you, one at desktop width and one
  at mobile width. Both reload by themselves when a file changes.

## When I draw on the app

I draw on the running app with Vignette's live ink and send you what I drew. Make the change I ask
for, in the app's own look, and keep it to what I marked. I am looking at the page, so I see your
change when it reloads; say in one line here what you changed. Answer on the window only when the
vignette skill says it helps, with the answer file at `answer.json` in this folder.

This folder allows editing its files and running the vignette skill's reply helper, and no other
shell commands.
"""


# The work copy's mobile layout. Two bugs are left: the day cards squeezed into three columns, which
# beat 2 asks Claude to fix, and the top bar running off the right edge, which beat 3 asks Claude
# to find and show on the window.
MOBILE_CSS = """
/* Mobile */

@media (max-width: 600px) {
  .main { padding: 18px 16px; }
  .hero { grid-template-columns: 1fr; height: auto; }
  .map { height: 120px; }
}
"""


def layout(bounds):
    """The windows' frames in the screen below the menu bar: Claude Code on the left, the desktop
    browser on the right, and the mobile-width browser tucked into the lower right corner over the
    desktop one. `mobile_inward` is where a take drags the mobile window once there is ink on it,
    clear of the screen's edges, so Claude's labels and buttons beside it fit."""
    x, y, w, h = bounds
    terminal = [x + 14, y + 14, 470, h - 28]
    desktop = [x + 498, y + 14, w - 512, round(h * 0.66)]
    height = h - round(h * 0.3) - 64
    mobile = [x + w - 14 - 410, y + h - 14 - height, 410, height]
    inward = [x + w - 190 - 410, y + round(h * 0.3), 410, height]
    return {'terminal': terminal, 'desktop': desktop, 'mobile': mobile, 'mobile_inward': inward}


def chrome(stage, name, frame, app_window):
    """A Chrome with a profile of its own, so each window is its own process to place and record."""
    profile = os.path.join(OUT, f'chrome-{name}')
    shutil.rmtree(profile, ignore_errors=True)
    x, y, w, h = frame
    page = [f'--app={stage.page_url}'] if app_window else ['--new-window', stage.page_url]
    since = time.monotonic()
    subprocess.run(['open', '-na', 'Google Chrome', '--args', f'--user-data-dir={profile}', '--no-first-run',
                    '--no-default-browser-check', '--use-mock-keychain', '--disable-session-crashed-bubble',
                    '--hide-crash-restore-bubble', '--force-renderer-accessibility',
                    f'--window-position={x},{y}', f'--window-size={w},{h}', *page], check=True)
    stage.wait_event('page.shown', since, 30, f'the page showing in the {name} browser')
    pids = drive.main_pids(CHROME, f'--user-data-dir={profile}')
    if len(pids) != 1:
        raise drive.TakeFailed(f'expected one {name} Chrome, found {pids}')
    time.sleep(0.4)
    subprocess.run([PATHS['stage_bin'], 'place', str(pids[0]), *map(str, frame)], capture_output=True, check=True)
    drive.save_pids(stage, **{f'chrome_{name}': pids[0]})
    return pids[0]


def quiet_claude(paths):
    """What the trailer's setup answers in the trailer's Claude Code config before a session."""
    with open(os.path.join(paths['claude'], '.claude.json')) as f:
        state = json.load(f)
    project = state.setdefault('projects', {}).setdefault(paths['work'], {})
    project.update({'hasTrustDialogAccepted': True, 'hasClaudeMdExternalIncludesApproved': False,
                    'hasClaudeMdExternalIncludesWarningShown': True})
    state['claudeInChromeDefaultEnabled'] = False
    with open(os.path.join(paths['claude'], '.claude.json'), 'w') as f:
        json.dump(state, f, indent=2)
    settings_path = os.path.join(paths['claude'], 'settings.json')
    settings = json.load(open(settings_path)) if os.path.exists(settings_path) else {}
    settings.update({'promptSuggestionEnabled': False, 'spinnerTipsEnabled': False})
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)


def up():
    if os.path.exists(STATE):
        sys.exit('dev: a stage is up already; run `dev.py down` first')
    os.makedirs(OUT, exist_ok=True)
    app = trailer.stage_app()
    stage = drive.Stage(CONFIG, PATHS, app)
    status = subprocess.run(['claude', 'auth', 'status'], capture_output=True, text=True,
                            env=dict(os.environ, CLAUDE_CONFIG_DIR=PATHS['claude']))
    if not json.loads(status.stdout or '{}').get('loggedIn'):
        sys.exit("dev: the trailer's Claude Code is not signed in; run trailer.py claude once")
    if not drive.port_free(CONFIG['stage']['port']):
        sys.exit(f"dev: port {CONFIG['stage']['port']} is taken")
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    try:
        set_stage(stage)
        print('the stage is up; Ctrl-C or `dev.py down` takes it down', flush=True)
        while not stop.is_set():
            if stage.pid and not alive(stage.pid):
                print('dev: Vignette Demo quit', flush=True)
                break
            stop.wait(1.0)
    except drive.TakeFailed as e:
        print(f'dev: {e}', flush=True)
    finally:
        take_down(stage)


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def pause_vignettes():
    """Quits every other running Vignette, and answers the apps to open again after. Another copy
    with live ink on hears the take's ⌃⌥ too, and its overlay, above the stage copy's, takes the strokes."""
    paused = []
    listing = subprocess.run(['ps', '-axo', 'pid=,command='], capture_output=True, text=True).stdout
    for line in listing.splitlines():
        pid, _, command = line.strip().partition(' ')
        if not command.endswith('.app/Contents/MacOS/Vignette'):
            continue
        pid = int(pid)
        paused.append(command.split('/Contents/MacOS/')[0])
        drive.stop_pid(pid, timeout=10)
        print(f'  quit {paused[-1]} for the stage', flush=True)
    return paused


def set_stage(stage):
    p = PATHS
    stage.paused = pause_vignettes()
    drive.stop_stage_app(stage)
    drive.clear_leftovers(p, CONFIG)
    shutil.rmtree(p['watch'], ignore_errors=True)
    os.makedirs(p['watch'])
    with open(p['settings'], 'w') as f:
        json.dump(CONFIG['app']['settings'], f, indent=2)
    subprocess.run(['defaults', 'write', f"{stage.app['bundle']}.screencapture", 'location', p['watch']], check=True)
    drive.stage_game(stage)
    with open(os.path.join(p['work'], 'CLAUDE.md'), 'w') as f:
        f.write(INSTRUCTIONS)
    with open(os.path.join(p['work'], 'styles.css'), 'a') as f:
        f.write(MOBILE_CSS)
    quiet_claude(p)

    stage.dock_was = drive.dock_autohide()
    with open(p['dock'], 'w') as f:
        f.write('true' if stage.dock_was else 'false')
    if not stage.dock_was:
        drive.dock_autohide(True)
        time.sleep(1.0)

    port = CONFIG['stage']['port']
    stage.base_url = stage.page_url = f'http://localhost:{port}/'
    stage.server = drive.DevServer(stage, p['work'], port)
    stage.desktop = subprocess.Popen([p['stage_bin'], 'desktop'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    ready = stage.desktop.stdout.readline().split()
    if not ready or ready[0] != 'ready':
        raise drive.TakeFailed(f'the desktop did not come up: {ready}')
    stage.bounds = [float(v) for v in ready[1:]]
    frames = layout(stage.bounds)
    CONFIG['stage']['terminal'] = frames['terminal']
    stage.chrome_desktop = chrome(stage, 'desktop', frames['desktop'], app_window=False)
    stage.chrome_mobile = chrome(stage, 'mobile', frames['mobile'], app_window=True)

    offset = stage.log_size()
    # DEV_CLAUDE names a claude for Claude on the screen, such as scripts/e2e/fake_claude.py's
    # wrapper; without it, the stage's Vignette has none and only sessions answer.
    responder = ['--env', f"VIGNETTE_CLAUDE={os.environ['DEV_CLAUDE']}"] if os.environ.get('DEV_CLAUDE') else []
    subprocess.run(['open', '-g', '--env', f"VIGNETTE_SETTINGS={p['settings']}", '--env', 'VIGNETTE_SHARE_LIVE_INK=1',
                    *responder, stage.app['path']], check=True)
    stage.wait_log('[app] ready', offset, timeout=20)
    s = stage.state()
    stage.pid = s['app']['pid']
    drive.save_pids(stage, app=stage.pid)
    drive.install_plugin(stage)
    drive.open_terminal(stage)
    with open(STATE, 'w') as f:
        json.dump({'app': stage.app, 'pid': stage.pid, 'settings': p['settings'], 'bounds': stage.bounds,
                   'frames': frames, 'chrome_desktop': stage.chrome_desktop, 'chrome_mobile': stage.chrome_mobile,
                   'ghostty': stage.ghostty, 'desktop': stage.desktop.pid, 'inbox': stage.inbox,
                   'session': stage.session_id, 'claude': p['claude'], 'work': p['work'], 'url': stage.page_url,
                   'accessibility': s['app'].get('accessibility'), 'paused': stage.paused, 'held_by': os.getpid()}, f, indent=2)
    print(f"  Vignette Demo pid={stage.pid} accessibility={s['app'].get('accessibility')}", flush=True)


def take_down(stage):
    print('taking the stage down', flush=True)
    for name in ('chrome_desktop', 'chrome_mobile'):
        pid = getattr(stage, name, None)
        if pid:
            try:
                drive.stop_pid(pid, timeout=10)
            except drive.TakeFailed as e:
                print(f'  {e}', flush=True)
    drive.teardown(stage)
    paused = getattr(stage, 'paused', [])
    if os.path.exists(STATE):
        paused = json.load(open(STATE)).get('paused', paused)
        os.remove(STATE)
    # Opened as you would open it, without the stage's settings file.
    for app in paused:
        subprocess.run(['open', '-g', app])
        print(f'  opened {app} again', flush=True)


def down():
    if not os.path.exists(STATE):
        sys.exit('dev: no stage is up')
    holder = json.load(open(STATE))['held_by']
    if alive(holder):
        os.kill(holder, signal.SIGTERM)
        end = time.monotonic() + 30
        while alive(holder) and time.monotonic() < end:
            time.sleep(0.2)
    print('the stage is down')


if __name__ == '__main__':
    command = sys.argv[1] if len(sys.argv) > 1 else ''
    if command == 'up':
        up()
    elif command == 'down':
        down()
    else:
        print(__doc__)
