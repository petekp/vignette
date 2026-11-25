#!/usr/bin/env python3
"""Sets the live ink demo's stage: four windows on a plain desktop, each with something to ask about.

    demo.py up      relaunch Vignette as the demo's copy and lay out the stage
    demo.py reset   erase the ink and lay the stage out again, for the next take
    demo.py down    take the stage down and open your own Vignette again

The windows are an invoice and a settings page in a Chrome of the demo's own, launch notes in
TextEdit, and a failing test in a Ghostty of its own. `docs/live-ink-demo-2026-10-05.md` has the
beats. Everything the stage makes is under `out/`, which Git ignores.

A take presses keys and draws with the pointer, so it must never reach the Vignette you use.
`up` quits the running Vignette and opens the same app as the demo's copy: a test launch on a copy
of your settings file, with live ink on and a screenshot folder of its own, both under
`out/vignette/`. `down` quits the copy and opens your own Vignette again.
"""
import json
import os
import shutil
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')
PIDS = os.path.join(OUT, 'pids.json')
STAGE_BIN = os.path.join(OUT, 'bin', 'stage')
STAGE_SRC = os.path.join(HERE, '..', 'trailer', 'stage.swift')
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
GHOSTTY = '/Applications/Ghostty.app/Contents/MacOS/ghostty'
PROFILE = os.path.join(OUT, 'chrome')
TERMINAL = os.path.join(HERE, 'failing-test.sh')
NOTES = os.path.join(OUT, 'launch-notes.rtf')
REAL_SETTINGS = os.path.expanduser('~/.config/vignette/settings.json')
COPY = os.path.join(OUT, 'vignette')
SETTINGS = os.path.join(COPY, 'settings.json')
SHOTS = os.path.join(COPY, 'shots')
LOG = os.path.expanduser('~/Library/Logs/Vignette.log')


def run(*args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw)


def pids_of(pattern):
    found = []
    for line in run('ps', '-axo', 'pid=,command=').stdout.splitlines():
        pid, _, command = line.strip().partition(' ')
        if pattern(command):
            found.append(int(pid))
    return found


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def stop(pid, timeout=5):
    if not pid or not alive(pid):
        return
    os.kill(pid, signal.SIGTERM)
    end = time.monotonic() + timeout
    while alive(pid) and time.monotonic() < end:
        time.sleep(0.1)


def wait_for(what, find, timeout=15):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        found = find()
        if found:
            return found
        time.sleep(0.1)
    sys.exit(f'demo: {what} did not come up')


def place(pid, frame):
    x, y, w, h = (int(v) for v in frame)
    for _ in range(30):
        if run(STAGE_BIN, 'place', str(pid), str(x), str(y), str(w), str(h)).returncode == 0:
            return
        time.sleep(0.2)
    sys.exit(f'demo: could not place the window of {pid}')


def saved():
    return json.load(open(PIDS)) if os.path.exists(PIDS) else {}


def save(state):
    json.dump(state, open(PIDS, 'w'), indent=2)


# MARK: Vignette

def vignettes():
    """Every running Vignette's pid and bundle."""
    found = []
    for pid in pids_of(lambda c: c.endswith('.app/Contents/MacOS/Vignette')):
        command = run('ps', '-o', 'command=', '-p', str(pid)).stdout.strip()
        found.append((pid, command.split('/Contents/MacOS/')[0]))
    return found


def url(app, command):
    run('open', '-g', '-a', app, 'vignette://' + command)


def state(app):
    tag = f'demo{int(time.time() * 1000) % 10**8}'
    url(app, 'state?tag=' + tag)
    end = time.monotonic() + 5
    while time.monotonic() < end:
        time.sleep(0.1)
        for line in reversed(open(LOG, errors='replace').read().splitlines()[-300:]):
            if f'"tag":"{tag}"' in line:
                return json.loads(line.split('[state] ', 1)[1])
    sys.exit('demo: Vignette did not answer')


def bundle_id(app):
    return run('defaults', 'read', os.path.join(app, 'Contents', 'Info'), 'CFBundleIdentifier').stdout.strip()


def same_path(a, b):
    """Whether two paths name one file, with links resolved and without case, as APFS compares names."""
    def comparable(path):
        return os.path.realpath(os.path.expanduser(path)).lower()
    return comparable(a) == comparable(b)


def isolation_problem(report, stage):
    """Why the Vignette that wrote `report`, a `[state]` line, is not the stage's copy, or None
    when it is. A take sends nothing to a Vignette this does not pass."""
    app = report['app']
    if same_path(app['settingsFile'], REAL_SETTINGS):
        return f"Vignette is on your own settings file, {REAL_SETTINGS}, not the demo's copy"
    if not same_path(app['settingsFile'], SETTINGS):
        return f"Vignette is on {app['settingsFile']}, not the demo's copy {SETTINGS}"
    if not same_path(app['watchFolder'], SHOTS):
        return f"Vignette watches {app['watchFolder']}, not the demo's folder {SHOTS}"
    if not stage.get('app') or not same_path(app['bundle'], stage['app']):
        return f"the Vignette that answered is {app['bundle']}, not the stage's {stage.get('app')}"
    if app['pid'] != stage.get('vignette'):
        return f"the Vignette that answered is pid {app['pid']}, not the stage's copy, pid {stage.get('vignette')}"
    return None


def copy_settings():
    """Writes the demo's settings file: yours, with live ink on and the demo's screenshot folder."""
    try:
        with open(REAL_SETTINGS) as f:
            settings = json.load(f)
    except (OSError, ValueError) as error:
        sys.exit(f'demo: could not read {REAL_SETTINGS} to copy it: {error}')
    settings.update(liveInk=True, screenshotsFolder=SHOTS)
    os.makedirs(SHOTS, exist_ok=True)
    with open(SETTINGS, 'w') as f:
        json.dump(settings, f, indent=2)


def isolate(stage):
    """Quits the running Vignette and opens the same app as the demo's copy, a test launch on
    `SETTINGS` that watches `SHOTS`. Saves the stage as soon as yours has quit, so `down` can open
    it again even when the rest of `up` fails."""
    running = vignettes()
    if not running:
        sys.exit('demo: Vignette is not running; open it, then run `demo.py up` again')
    if len(running) > 1:
        sys.exit('demo: more than one Vignette is running; quit all but one: '
                 + ', '.join(f'{app} (pid {pid})' for pid, app in running))
    pid, app = running[0]
    copy_settings()
    # A test launch reads its save location from this domain, never com.apple.screencapture.
    run('defaults', 'write', bundle_id(app) + '.screencapture', 'location', SHOTS)
    stop(pid, timeout=10)
    if alive(pid):
        sys.exit(f'demo: Vignette (pid {pid}) did not quit')
    stage['app'] = app
    save(stage)
    claude = shutil.which('claude') or os.path.expanduser('~/.local/bin/claude')
    run('open', '-g', '--env', f'VIGNETTE_SETTINGS={SETTINGS}', '--env', f'VIGNETTE_CLAUDE={claude}', app)
    stage['vignette'] = wait_for("the demo's copy of Vignette", lambda: next((p for p, _ in vignettes()), None))
    save(stage)
    time.sleep(2)
    problem = isolation_problem(state(app), stage)
    if problem:
        sys.exit(f'demo: {problem}; run `demo.py down` to open your own Vignette again')
    print(f"Vignette is the demo's copy now, on {SETTINGS}")


def restore(stage):
    """Quits the demo's copy and opens your own Vignette again, after `isolate`."""
    if not stage.get('app'):
        return
    stop(stage.get('vignette'), timeout=10)
    if stage.get('vignette') and alive(stage['vignette']):
        sys.exit(f"demo: the demo's copy of Vignette (pid {stage['vignette']}) did not quit")
    run('open', '-g', stage['app'])
    wait_for('Vignette', vignettes)
    time.sleep(2)
    report = state(stage['app'])
    if not same_path(report['app']['settingsFile'], REAL_SETTINGS):
        print(f"demo: Vignette came back on {report['app']['settingsFile']}; quit it and open it again")
    else:
        print('Vignette is back on its own settings')


# MARK: The stage

def layout(screen):
    """The four windows' frames in the screen below the menu bar, leaving the Dock its room."""
    x, y, w, h = screen
    h -= 60
    return {
        'invoice': (x + 24, y + 24, w * 0.40, h * 0.68),
        'notes': (x + w * 0.44, y + 24, w * 0.34, h * 0.50),
        'settings': (x + w * 0.53, y + h * 0.42, w * 0.42, h * 0.50),
        'terminal': (x + 24, y + h * 0.72, w * 0.47, h * 0.28),
    }


def build_stage_bin():
    if os.path.exists(STAGE_BIN) and os.path.getmtime(STAGE_BIN) >= os.path.getmtime(STAGE_SRC):
        return
    os.makedirs(os.path.dirname(STAGE_BIN), exist_ok=True)
    result = run('swiftc', '-O', '-o', STAGE_BIN, STAGE_SRC)
    if result.returncode != 0:
        sys.exit('demo: could not build the stage helper\n' + result.stderr)


def desktop():
    """The trailer's plain desktop, kept up by a `sleep` that holds its input open."""
    ready = os.path.join(OUT, 'desktop.out')
    process = subprocess.Popen(['/bin/sh', '-c', f'sleep 86400 | "{STAGE_BIN}" desktop > "{ready}"'],
                               start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    def screen():
        text = open(ready).read() if os.path.exists(ready) else ''
        return next((tuple(float(v) for v in line.split()[1:5]) for line in text.splitlines() if line.startswith('ready')), None)
    return process.pid, wait_for('the desktop', screen)


def chrome(page, frame):
    args = [CHROME, f'--user-data-dir={PROFILE}', '--force-renderer-accessibility', '--no-first-run',
            '--no-default-browser-check', '--disable-features=Translate', '--hide-crash-restore-bubble']
    # App windows: no toolbar, so the page is all there is to see.
    subprocess.Popen(args + ['--app=file://' + os.path.join(HERE, 'pages', page)], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    pid = wait_for('Chrome', lambda: pids_of(lambda c: c.startswith(CHROME) and f'--user-data-dir={PROFILE}' in c
                                              and '--type=' not in c))[0]
    time.sleep(1.5)
    place(pid, frame)
    return pid


def textedit(frame):
    was_running = bool(pids_of(lambda c: c.endswith('TextEdit.app/Contents/MacOS/TextEdit')))
    shutil.copyfile(os.path.join(HERE, 'launch-notes.rtf'), NOTES)
    run('open', '-a', 'TextEdit', NOTES)
    pid = wait_for('TextEdit', lambda: pids_of(lambda c: c.endswith('TextEdit.app/Contents/MacOS/TextEdit')))[0]
    time.sleep(1.0)
    place(pid, frame)
    return pid, was_running


def ghostty(frame):
    run('open', '-na', 'Ghostty', '--args', f'--command={TERMINAL}', f'--working-directory={HERE}',
        '--window-save-state=never', '--confirm-close-surface=false', '--quit-after-last-window-closed=true',
        '--title=juniper — tests')
    pid = wait_for('Ghostty', lambda: pids_of(lambda c: c.startswith(GHOSTTY) and f'--command={TERMINAL}' in c))[0]
    time.sleep(1.0)
    place(pid, frame)
    return pid


def up():
    stage = saved()
    if stage.get('desktop'):
        sys.exit('demo: the stage is up already; run `demo.py down` or `demo.py reset`')
    os.makedirs(OUT, exist_ok=True)
    build_stage_bin()
    if not (stage.get('vignette') and alive(stage['vignette'])):
        isolate(stage)
    stage['desktop'], screen = desktop()
    frames = layout(screen)
    stage['terminal'] = ghostty(frames['terminal'])
    stage['textedit'], stage['textedit_was_running'] = textedit(frames['notes'])
    stage['chrome'] = chrome('settings.html', frames['settings'])
    chrome('invoice.html', frames['invoice'])
    save(stage)
    print('The stage is up. The invoice is in front; docs/live-ink-demo-2026-10-05.md has the beats.')


def take_down(stage):
    if stage.get('vignette') and alive(stage['vignette']):
        url(stage['app'], 'live-ink-clear')
    stop(stage.get('chrome'))
    stop(stage.get('terminal'))
    if stage.get('textedit') and not stage.get('textedit_was_running'):
        stop(stage['textedit'])
    elif stage.get('textedit'):
        print(f'demo: TextEdit was open before the demo; close {NOTES} yourself')
    if stage.get('desktop'):
        try:
            os.killpg(stage['desktop'], signal.SIGTERM)
        except OSError:
            pass
    for key in ('desktop', 'chrome', 'terminal', 'textedit', 'textedit_was_running'):
        stage.pop(key, None)


def down():
    stage = saved()
    take_down(stage)
    restore(stage)
    if os.path.exists(PIDS):
        os.remove(PIDS)
    print('The stage is down.')


def reset():
    stage = saved()
    take_down(stage)
    save(stage)
    time.sleep(1.0)
    up()


if __name__ == '__main__':
    command = sys.argv[1] if len(sys.argv) > 1 else ''
    if command == 'up':
        up()
    elif command == 'down':
        down()
    elif command == 'reset':
        reset()
    else:
        print(__doc__)
