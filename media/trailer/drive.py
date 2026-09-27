"""The performance: sets a desktop with the game in Chrome and Claude Code in a terminal, then drives
the stage copy of Vignette through every beat while the screen is recorded, and logs each action
on the recorder's clock.

Claude Code is real. It runs in a herdr session of its own, with a config of its own, in a fresh
copy of the game, and Send and Reply reach it. So the driver waits on what Claude does: an edit to
the game, a sketch pushed to Vignette, the end of a turn.

Every action is checked before it is taken. A click needs the stage copy's window under the
pointer, and a key needs the stage copy's editor or toolbar to hold the keys. A check that fails
ends the take with the reason.
"""
import datetime
import http.server
import json
import math
import os
import random
import shutil
import signal
import socket
import subprocess
import threading
import time
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
INPUT = os.path.join(REPO, 'scripts', 'input.sh')
HERDR = os.path.expanduser('~/.local/bin/herdr')
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'


class TakeFailed(Exception):
    pass


class Stage:
    """Where everything for a take lives, and the handles to what a take starts."""

    def __init__(self, config, paths, app):
        self.config = config
        self.paths = paths
        self.app = app              # the stage copy: path, bundle id, scheme, name, log
        self.events = []
        self.lock = threading.Lock()
        self.desktop = None
        self.server = None
        self.recorder = None
        self.game = None            # the game's viewport on screen, points: x, y, w, h
        self.bounds = None          # the screen below the menu bar, which the camera may show
        self.pid = None
        self.scale = None
        self.hand = random.Random(config['stage'].get('seed', 7))
        # Log times are wall-clock; events are on the monotonic clock the recorder stamps.
        self.wall_minus_mono = time.time() - time.monotonic()

    # ---- Events ----------------------------------------------------------------------------

    def event(self, name, t=None, **rects):
        t = time.monotonic() if t is None else t
        with self.lock:
            self.events.append({'name': name, 't': t, 'rects': rects})
        print(f'  {name}' + (f' {rects}' if rects else ''), flush=True)
        return t

    def last(self, name, after=0.0):
        with self.lock:
            found = [e for e in self.events if e['name'] == name and e['t'] > after]
        return found[-1] if found else None

    def wait_event(self, name, after, timeout, what):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            e = self.last(name, after)
            if e:
                return e
            time.sleep(0.05)
        raise TakeFailed(f'{what} did not happen within {timeout} s')

    def mono_from_log(self, line):
        """The monotonic time of a log line, from its HH:mm:ss.SSS stamp."""
        stamp = line[:12]
        today = datetime.datetime.now()
        h, m, rest = stamp.split(':')
        s, ms = rest.split('.')
        wall = today.replace(hour=int(h), minute=int(m), second=int(s), microsecond=int(ms) * 1000).timestamp()
        # A line from before midnight read after it.
        if wall - time.time() > 3600:
            wall -= 86400
        return wall - self.wall_minus_mono

    # ---- The stage copy ----------------------------------------------------------------------

    def url(self, command):
        subprocess.run(['open', '-g', '-a', self.app['path'], f"{self.app['scheme']}://{command}"], check=True)

    def log_size(self):
        return os.path.getsize(self.app['log']) if os.path.exists(self.app['log']) else 0

    def wait_log(self, needle, offset, timeout=10, also=None):
        """The first line after `offset` holding `needle` (and `also`, when given)."""
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            with open(self.app['log'], 'rb') as f:
                f.seek(offset)
                text = f.read().decode('utf-8', 'replace')
            for line in text.splitlines():
                if needle in line and (also is None or also in line):
                    return line
            time.sleep(0.05)
        raise TakeFailed(f'no {needle!r} in the log within {timeout} s')

    def state(self):
        tag = f'trailer{random.randrange(10**9)}'
        offset = self.log_size()
        self.url(f'state?tag={tag}')
        line = self.wait_log('[state] ', offset, also=tag)
        s = json.loads(line.split('[state] ', 1)[1])
        if s['app']['bundle'] != self.app['path'] or s['app']['settingsFile'] != self.paths['settings']:
            raise TakeFailed(f"state came from {s['app']['bundle']} on {s['app']['settingsFile']}, not the stage copy")
        return s

    def wait_state(self, test, timeout=10, what='the stage'):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            s = self.state()
            if test(s):
                return s
            time.sleep(0.1)
        raise TakeFailed(f'{what} did not happen within {timeout} s')

    # ---- The terminal's herdr session ----------------------------------------------------------

    def herdr(self, *args, check=True, timeout=30):
        """Runs herdr against the trailer's own session, never the default one."""
        session = self.config['stage']['session']['herdr']
        out = subprocess.run([HERDR, '--session', session, *args], capture_output=True, text=True, timeout=timeout)
        if check and out.returncode != 0:
            raise TakeFailed(f"herdr {' '.join(args)}: {out.stderr.strip() or out.stdout.strip()}")
        try:
            return json.loads(out.stdout)
        except json.JSONDecodeError:
            return {'text': out.stdout}

    def agent_wait(self, until, timeout, what):
        name = self.config['stage']['session']['agent']
        out = self.herdr('agent', 'wait', name, '--until', until, '--timeout', str(int(timeout * 1000)),
                         check=False, timeout=timeout + 10)
        if 'error' in out:
            raise TakeFailed(f"{what}: {out['error'].get('message', out['error'])}")
        return time.monotonic()

    # ---- Input -------------------------------------------------------------------------------

    def input(self, *args):
        subprocess.run([INPUT, *map(str, args)], check=True)

    def pause(self, seconds):
        """A pause that varies around `seconds`, as a person's does."""
        time.sleep(seconds * (0.85 + 0.3 * self.hand.random()))

    def glide(self, to, seconds=None):
        """Moves the pointer like a hand: the time grows with the distance, and a long move
        overshoots a little and settles back."""
        now = self.pointer()
        d = math.dist(now, to)
        if seconds is None:
            seconds = 0.2 + 0.11 * math.log2(1 + d / 30)
        if d > 260:
            # Past the target along the line, by 1.5 to 3% of the way, then back.
            k = 0.015 + 0.015 * self.hand.random()
            over = (to[0] + (to[0] - now[0]) * k, to[1] + (to[1] - now[1]) * k)
            self.input('glide', round(over[0], 1), round(over[1], 1), round(seconds, 3))
            self.input('glide', *to, round(0.12 + 0.05 * self.hand.random(), 3))
        else:
            self.input('glide', *to, round(seconds, 3))

    def drag(self, a, b, seconds=None):
        d = math.dist(a, b)
        if seconds is None:
            seconds = 0.3 + 0.12 * math.log2(1 + d / 40)
        self.input('glidedrag', *a, *b, round(seconds, 3))

    def pointer(self):
        out = subprocess.run(['osascript', '-l', 'JavaScript', '-e',
                              'ObjC.import("AppKit"); var p = $.NSEvent.mouseLocation; '
                              'var h = $.NSScreen.screens.objectAtIndex(0).frame.size.height; p.x + " " + (h - p.y)'],
                             capture_output=True, text=True, check=True).stdout.split()
        return (float(out[0]), float(out[1]))

    def owner(self, x, y):
        return subprocess.run([self.paths['stage_bin'], 'owner', str(x), str(y)],
                              capture_output=True, text=True, check=True).stdout.strip()

    def require_owner(self, point, owner):
        found = self.owner(*point)
        if not found.startswith(owner + ' '):
            raise TakeFailed(f'the window under {point} is {found}, not {owner}')

    def require_editor(self, point=None):
        s = self.state()
        a = s['annotator']
        if not (a['windowVisible'] and a['key']):
            raise TakeFailed(f'the editor is not up and key: {a}')
        if point is not None:
            self.require_owner(point, self.app['name'])
        return s

    # ---- Geometry ----------------------------------------------------------------------------

    def screen(self, p):
        """A point of the scene, in the game's 1600 x 1000 units, on screen."""
        x, y, w, h = self.game
        return (round(x + p[0] / 1600 * w, 1), round(y + p[1] / 1000 * h, 1))

    def in_image(self, p, source, frame):
        """A point of the scene in an image of `source` (a screen rect), shown in `frame`."""
        sx, sy = self.screen(p)
        fx = (sx - source[0]) / source[2]
        fy = (sy - source[1]) / source[3]
        return (round(frame[0] + fx * frame[2], 1), round(frame[1] + fy * frame[3], 1))


# ---- The game's dev server -------------------------------------------------------------------

CLIENT = b"""<script>
(() => {
  new EventSource('/__reload').onmessage = () => location.reload();
  if (/Headless/.test(navigator.userAgent)) return;
  const report = () => requestAnimationFrame(() => requestAnimationFrame(() => {
    const q = new URLSearchParams({ x: screenX, y: screenY, ow: outerWidth, oh: outerHeight,
      iw: innerWidth, ih: innerHeight, page: location.pathname + location.search });
    fetch('/__shown?' + q, { cache: 'no-store' });
  }));
  report();
  addEventListener('resize', report);
})();
</script>
"""


class DevServer:
    """Serves the stage copy of the game the way a dev server does: a page reloads itself when a
    file of the game changes. It also reports when a page in the visible browser has drawn, and
    where its viewport is, as the events `game.changed` and `page.shown`."""

    WATCHED = ('.js', '.json', '.html', '.css')

    def __init__(self, stage, root, port):
        self.stage = stage
        self.root = root
        self.generation = 0
        self.changed = threading.Condition()
        self.metrics = None
        server = self

        class Handler(http.server.SimpleHTTPRequestHandler):
            def __init__(self, *a, **kw):
                super().__init__(*a, directory=root, **kw)

            def log_message(self, *a):
                pass

            def end_headers(self):
                self.send_header('Cache-Control', 'no-store')
                super().end_headers()

            def do_GET(self):
                path = urllib.parse.urlparse(self.path)
                if path.path == '/__reload':
                    return server.stream(self)
                if path.path == '/__shown':
                    q = {k: v[0] for k, v in urllib.parse.parse_qs(path.query).items()}
                    server.metrics = {k: float(v) for k, v in q.items() if k != 'page'} | {'page': q.get('page', '')}
                    stage.event('page.shown', page=[server.metrics[k] for k in ('x', 'y', 'ow', 'oh')])
                    self.send_response(204)
                    self.end_headers()
                    return
                file = self.translate_path(path.path)
                if os.path.isdir(file):
                    file = os.path.join(file, 'index.html')
                if file.endswith('.html') and os.path.isfile(file):
                    with open(file, 'rb') as f:
                        body = f.read().replace(b'</body>', CLIENT + b'</body>')
                    self.send_response(200)
                    self.send_header('Content-Type', 'text/html; charset=utf-8')
                    self.send_header('Content-Length', str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return
                super().do_GET()

        self.httpd = http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler)
        self.httpd.daemon_threads = True
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        threading.Thread(target=self.watch, daemon=True).start()

    def stream(self, handler):
        handler.send_response(200)
        handler.send_header('Content-Type', 'text/event-stream')
        handler.end_headers()
        seen = self.generation
        try:
            while True:
                with self.changed:
                    self.changed.wait(timeout=5)
                    now = self.generation
                handler.wfile.write(b'data: reload\n\n' if now != seen else b': ping\n\n')
                handler.wfile.flush()
                seen = now
        except (BrokenPipeError, ConnectionResetError):
            pass

    def snapshot(self, only=None):
        found = {}
        for folder, dirs, files in os.walk(self.root):
            dirs[:] = [d for d in dirs if not d.startswith('.')]
            for name in files:
                path = os.path.join(folder, name)
                if name.endswith(self.WATCHED) and (only is None or path in only):
                    try:
                        found[path] = os.stat(path).st_mtime_ns
                    except FileNotFoundError:
                        pass
        return found

    def watch(self):
        # The game's own files: a file Claude adds beside them, such as its marks, is not a change
        # to the game.
        before = self.snapshot()
        game = set(before)
        while True:
            time.sleep(0.1)
            now = self.snapshot(only=game)
            if now != before:
                changed = sorted(os.path.relpath(p, self.root) for p in set(now) ^ set(before) | {p for p in now if now.get(p) != before.get(p)})
                self.stage.event('game.changed')
                print(f'    changed {changed}', flush=True)
                before = now
                with self.changed:
                    self.generation += 1
                    self.changed.notify_all()

    def stop(self):
        self.httpd.shutdown()


# ---- Setup and teardown ----------------------------------------------------------------------

def port_free(port):
    with socket.socket() as sock:
        try:
            sock.bind(('127.0.0.1', port))
            return True
        except OSError:
            return False


def dock_autohide(value=None):
    script = 'tell application "System Events" to get autohide of dock preferences'
    if value is not None:
        script = f'tell application "System Events" to set autohide of dock preferences to {"true" if value else "false"}'
    out = subprocess.run(['osascript', '-e', script], capture_output=True, text=True, check=True).stdout.strip()
    return out == 'true'


def stop_pid(pid, timeout=5):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    raise TakeFailed(f'process {pid} did not stop')


def running_pids(pattern):
    out = subprocess.run(['pgrep', '-f', pattern], capture_output=True, text=True).stdout.split()
    return [int(p) for p in out if int(p) != os.getpid()]


def main_pids(executable, marker):
    """The pids of processes whose command runs `executable` with `marker` among its arguments."""
    out = subprocess.run(['ps', '-axo', 'pid=,command='], capture_output=True, text=True).stdout
    found = []
    for line in out.splitlines():
        pid, _, command = line.strip().partition(' ')
        if command.startswith(executable + ' ') and marker in command:
            found.append(int(pid))
    return found


def stop_stage_app(stage):
    for pid in running_pids(os.path.join(stage.app['path'], 'Contents', 'MacOS')):
        stop_pid(pid)


def save_pids(stage, **pids):
    path = stage.paths['pids']
    known = json.load(open(path)) if os.path.exists(path) else {}
    known.update({k: v for k, v in pids.items() if v})
    with open(path, 'w') as f:
        json.dump(known, f)


def command_of(pid):
    return subprocess.run(['ps', '-o', 'command=', '-p', str(pid)], capture_output=True, text=True).stdout.strip()


def clear_leftovers(paths, config):
    """Stops what an interrupted take left running: the trailer's Chrome, its terminal, its herdr
    session and the stage copy. Each is found by what only the trailer's copy has, never by a
    name alone."""
    for pid in main_pids(CHROME, f"--user-data-dir={paths['chrome']}"):
        stop_pid(pid, timeout=10)
    session = config['stage']['session']['herdr']
    subprocess.run([HERDR, 'session', 'stop', session], capture_output=True)
    subprocess.run([HERDR, 'session', 'delete', session], capture_output=True)
    if os.path.exists(paths['pids']):
        pids = json.load(open(paths['pids']))
        if pids.get('ghostty') and f"--command={paths['stage']}/terminal.sh" in command_of(pids['ghostty']):
            stop_pid(pids['ghostty'], timeout=10)
        os.remove(paths['pids'])


def stage_game(stage):
    """A fresh copy of the game for Claude to work in, with the permissions its session needs."""
    p = stage.paths
    shutil.rmtree(p['mew'], ignore_errors=True)
    shutil.copytree(p['game'], p['mew'])
    # A rule's path starting with ~/ is in the home folder; one starting with / would be relative
    # to this settings file.
    requests = f"~/Library/Application Support/{stage.app['bundle']}/**"
    reply = os.path.join(p['claude'], 'skills', 'vignette', 'scripts', 'reply')
    settings = {
        'permissions': {
            # Anything not allowed here is refused without a question, so a take never stops on one.
            'defaultMode': 'dontAsk',
            'allow': [
                'Edit(./**)', 'Write(./**)', 'Bash(./screenshot:*)', 'Bash(open -g:*)',
                f'Read({requests})', f'Bash({reply}:*)',
            ],
        },
    }
    os.makedirs(os.path.join(p['mew'], '.claude'))
    with open(os.path.join(p['mew'], '.claude', 'settings.json'), 'w') as f:
        json.dump(settings, f, indent=2)


def open_browser(stage):
    """Chrome with a profile made for the take, showing the game, fitted so the game is 16:10."""
    c, p = stage.config['stage'], stage.paths
    shutil.rmtree(p['chrome'], ignore_errors=True)
    x, y, w, h = c['browser']
    since = time.monotonic()
    subprocess.run(['open', '-na', 'Google Chrome', '--args', f"--user-data-dir={p['chrome']}", '--no-first-run',
                    '--no-default-browser-check', '--use-mock-keychain', '--disable-session-crashed-bubble',
                    '--hide-crash-restore-bubble', f'--window-position={x},{y}', f'--window-size={w},{h}',
                    '--new-window', stage.page_url], check=True)
    stage.wait_event('page.shown', since, 30, 'the game showing in Chrome')
    pids = main_pids(CHROME, f"--user-data-dir={p['chrome']}")
    if len(pids) != 1:
        raise TakeFailed(f'expected one Chrome for the take, found {pids}')
    stage.chrome = pids[0]
    save_pids(stage, chrome=stage.chrome)
    m = stage.server.metrics
    # The window's height, less what the viewport lacks of 16:10.
    height = round(m['oh'] + m['iw'] / 1.6 - m['ih'])
    since = time.monotonic()
    subprocess.run([p['stage_bin'], 'place', str(stage.chrome), str(x), str(y), str(w), str(height)],
                   capture_output=True, check=True)
    time.sleep(0.6)
    m = stage.server.metrics
    if abs(m['iw'] / m['ih'] - 1.6) > 0.01:
        raise TakeFailed(f"the game's viewport is {m['iw']} x {m['ih']}, not 16:10")
    stage.game = (m['x'] + (m['ow'] - m['iw']) / 2, m['y'] + m['oh'] - m['ih'], m['iw'], m['ih'])
    stage.event('browser.ready', game=list(stage.game))


def open_terminal(stage):
    """Ghostty running the trailer's herdr session, and Claude Code started in its pane."""
    c, p = stage.config['stage'], stage.paths
    session = c['session']
    script = os.path.join(p['stage'], 'terminal.sh')
    with open(script, 'w') as f:
        f.write(f"""#!/bin/zsh
# Written by drive.py: the trailer's terminal runs its own herdr session, whose Claude Code uses
# the trailer's config.
export CLAUDE_CONFIG_DIR={json.dumps(p['claude'])}
export MEW_URL={json.dumps(stage.page_url)}
cd {json.dumps(p['mew'])}
exec {json.dumps(HERDR)} --session {json.dumps(session['herdr'])}
""")
    os.chmod(script, 0o755)
    x, y, w, h = c['terminal']
    subprocess.run(['open', '-na', 'Ghostty', '--args', f'--command={script}', f"--working-directory={p['mew']}",
                    f"--title={session['title']}", '--window-save-state=never', '--confirm-close-surface=false',
                    '--quit-after-last-window-closed=true', *c.get('terminal_args', [])], check=True)
    end = time.monotonic() + 15
    found = []
    while time.monotonic() < end and not found:
        found = main_pids('/Applications/Ghostty.app/Contents/MacOS/ghostty', f'--command={script}')
        time.sleep(0.1)
    if len(found) != 1:
        raise TakeFailed(f"expected one Ghostty running the trailer's terminal, found {found}")
    stage.ghostty = found[0]
    save_pids(stage, ghostty=stage.ghostty)
    time.sleep(1.0)
    subprocess.run([p['stage_bin'], 'place', str(stage.ghostty), str(x), str(y), str(w), str(h)],
                   capture_output=True, check=True)

    # The session's first pane, then Claude Code in it.
    end = time.monotonic() + 20
    panes = []
    while time.monotonic() < end and not panes:
        panes = stage.herdr('pane', 'list', check=False).get('result', {}).get('panes', [])
        time.sleep(0.2)
    if not panes:
        raise TakeFailed(f"herdr session {session['herdr']} has no pane")
    pane = panes[0]['pane_id']
    stage.herdr('agent', 'start', session['agent'], '--kind', 'claude', '--pane', pane, '--timeout', '30000',
                '--', '-n', session['title'], *session.get('args', []))
    stage.agent_wait('idle', 60, 'Claude Code starting')
    panes = stage.herdr('pane', 'list').get('result', {}).get('panes', [])
    found = [q for q in panes if q.get('pane_id') == pane and (q.get('agent_session') or {}).get('value')]
    if not found:
        raise TakeFailed('herdr does not know the Claude Code session; run trailer.py claude to install its hook')
    stage.session_id = found[0]['agent_session']['value']
    stage.event('terminal.ready', terminal=list(c['terminal']))


def render_cards(stage):
    """The history's earlier captures, rendered from the game before the app is up. A card with a
    `size` renders only that much of its page, from the top left."""
    p = stage.paths
    shutil.rmtree(p['cards'], ignore_errors=True)
    os.makedirs(p['cards'])
    cards = []
    for i, card in enumerate(stage.config['stage'].get('card', [])):
        path = os.path.join(p['cards'], f"{card.get('name', f'Capture {i + 1}')}.png")
        size = [f"{card['size'][0]},{card['size'][1]}"] if card.get('size') else []
        subprocess.run([os.path.join(p['mew'], 'screenshot'), path, card['page'], *size],
                       env=dict(os.environ, MEW_URL=stage.base_url), check=True, capture_output=True, timeout=60)
        cards.append((path, card))
    return cards


def write_herdr(stage):
    """The stage copy's herdr: the real one, pointed at the trailer's session, so Send lists only
    the trailer's Claude Code and never one of yours."""
    session = stage.config['stage']['session']['herdr']
    os.makedirs(os.path.dirname(stage.paths['herdr']), exist_ok=True)
    with open(stage.paths['herdr'], 'w') as f:
        f.write(f'#!/bin/sh\n# Written by drive.py for the stage copy of Vignette.\nexec {json.dumps(HERDR)} --session {json.dumps(session)} "$@"\n')
    os.chmod(stage.paths['herdr'], 0o755)


def setup(stage):
    c, p = stage.config, stage.paths
    print('setting the stage', flush=True)
    status = subprocess.run(['claude', 'auth', 'status'], capture_output=True, text=True,
                            env=dict(os.environ, CLAUDE_CONFIG_DIR=p['claude']))
    if not json.loads(status.stdout or '{}').get('loggedIn'):
        raise TakeFailed("the trailer's Claude Code is not signed in; run trailer.py claude once")
    port = c['stage'].get('port', 5173)
    if not port_free(port):
        raise TakeFailed(f'port {port} is taken; stop what uses it or change [stage] port')

    # Nothing may be left from an earlier take: its drawings are swept when their files are gone.
    stop_stage_app(stage)
    clear_leftovers(p, c)
    shutil.rmtree(p['watch'], ignore_errors=True)
    os.makedirs(p['watch'])
    with open(p['settings'], 'w') as f:
        json.dump(c['app']['settings'], f, indent=2)
    # Launched with VIGNETTE_SETTINGS, the copy follows this domain's location, never Apple's own.
    subprocess.run(['defaults', 'write', f"{stage.app['bundle']}.screencapture", 'location', p['watch']], check=True)
    stage_game(stage)
    write_herdr(stage)

    # The Dock would cover the bottom of the desktop, so it hides for the take and comes back after.
    stage.dock_was = dock_autohide()
    with open(p['dock'], 'w') as f:
        f.write('true' if stage.dock_was else 'false')
    if not stage.dock_was:
        dock_autohide(True)
        time.sleep(1.0)

    stage.base_url = f'http://localhost:{port}/'
    stage.page_url = stage.base_url
    stage.server = DevServer(stage, p['mew'], port)
    stage.desktop = subprocess.Popen([p['stage_bin'], 'desktop'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    ready = stage.desktop.stdout.readline().split()
    if not ready or ready[0] != 'ready':
        raise TakeFailed(f'the desktop did not come up: {ready}')
    stage.bounds = [float(v) for v in ready[1:]]
    stage.event('desktop.ready', desktop=stage.bounds)
    open_browser(stage)
    open_terminal(stage)
    cards = render_cards(stage)

    offset = stage.log_size()
    subprocess.run(['open', '-g', '--env', f"VIGNETTE_SETTINGS={p['settings']}", stage.app['path']], check=True)
    stage.wait_log('[app] ready', offset, timeout=20)
    s = stage.state()
    stage.pid = s['app']['pid']
    save_pids(stage, app=stage.pid)
    # Pixels a point on the recorded display, which the cut needs to crop the recording.
    stage.scale = s['screen']['scale']
    print(f"  stage copy pid={stage.pid} accessibility={s['app'].get('accessibility')}", flush=True)

    for path, card in cards:
        marks = path + '.json'
        with open(marks, 'w') as f:
            json.dump(card.get('marks', []), f)
        query = {'file': path, 'marks': marks}
        if card.get('agent'):
            query['agent'] = card['agent']
        offset = stage.log_size()
        stage.url('add?' + urllib.parse.urlencode(query, quote_via=urllib.parse.quote))
        stage.wait_log('[add] ok', offset)
        time.sleep(0.6)
        stage.url('dismiss')
        stage.wait_state(lambda s: not s['stack']['visible'], what='the thumbnail leaving')
        # A second apart, so the stack's order by date is certain.
        time.sleep(1.0)

    # The game's browser is the app in front when the take starts, as if you were playing it.
    subprocess.run(['osascript', '-e', f'tell application "System Events" to set frontmost of '
                    f'(first process whose unix id is {stage.chrome}) to true'], check=True)
    stage.glide(tuple(c['stage']['rest']))
    stage.url('dismiss')
    time.sleep(0.8)


def teardown(stage):
    print('clearing the stage', flush=True)
    errors = []

    def attempt(what, action):
        try:
            action()
        except Exception as e:     # every step runs, whatever the one before it did
            errors.append(f'{what}: {e}')

    if stage.recorder:
        attempt('recorder', lambda: stop_recorder(stage))
    if stage.pid:
        attempt('cancel', lambda: stage.url('cancel'))
        attempt('dismiss', lambda: stage.url('dismiss'))
        time.sleep(0.5)
        attempt('stage copy', lambda: stop_pid(stage.pid))
    attempt('herdr session', lambda: clear_leftovers(stage.paths, stage.config))
    if getattr(stage, 'ghostty', None):
        attempt('terminal', lambda: stop_pid(stage.ghostty, timeout=10))
    if stage.desktop:
        attempt('desktop', lambda: (stage.desktop.stdin.close(), stage.desktop.wait(timeout=5)))
    if stage.server:
        attempt('server', lambda: stage.server.stop())
    if hasattr(stage, 'dock_was'):
        if stage.dock_was is False:
            attempt('dock', lambda: dock_autohide(False))
        if not any(e.startswith('dock') for e in errors):
            os.remove(stage.paths['dock'])
    if not errors and os.path.exists(stage.paths['pids']):
        os.remove(stage.paths['pids'])
    for e in errors:
        print(f'  teardown: {e}', flush=True)


# ---- Helpers the beats share -----------------------------------------------------------------

def start_recorder(stage):
    stage.recorder = subprocess.Popen([stage.paths['record_bin'], stage.paths['movie']],
                                      stdout=subprocess.PIPE, text=True)
    line = stage.recorder.stdout.readline().strip()
    if not line.startswith('recording'):
        raise TakeFailed(f'the recorder did not start: {line!r}')
    time.sleep(0.8)


def stop_recorder(stage):
    stage.recorder.send_signal(signal.SIGINT)
    stage.recorder.wait(timeout=60)
    stage.recorder = None


def editor_rects(s):
    a = s['annotator']
    frame = a['frame']
    rects = {'frame': frame}
    if a.get('toolbar'):
        t = a['toolbar']
        x1, y1 = min(frame[0], t[0]), min(frame[1], t[1])
        x2, y2 = max(frame[0] + frame[2], t[0] + t[2]), max(frame[1] + frame[3], t[1] + t[3])
        rects['editor'] = [x1, y1, x2 - x1, y2 - y1]
    else:
        rects['editor'] = frame
    return rects


def newest_card(s):
    cards = s['stack']['cards']
    if not cards:
        raise TakeFailed('the stack has no cards')
    # The newest card is the lowest on screen.
    return max(cards, key=lambda c: c['frame'][1])


def png_size(path):
    with open(path, 'rb') as f:
        head = f.read(24)
    if head[:8] != b'\x89PNG\r\n\x1a\n':
        raise TakeFailed(f'{path} is not a PNG')
    return int.from_bytes(head[16:20], 'big'), int.from_bytes(head[20:24], 'big')


def union(rects):
    x1 = min(r[0] for r in rects)
    y1 = min(r[1] for r in rects)
    x2 = max(r[0] + r[2] for r in rects)
    y2 = max(r[1] + r[3] for r in rects)
    return [x1, y1, x2 - x1, y2 - y1]


def on_screen(frame, image, r):
    """A rect in an image's pixels, in the editor frame showing that image."""
    w, h = image
    return [frame[0] + r[0] / w * frame[2], frame[1] + r[1] / h * frame[3], r[2] / w * frame[2], r[3] / h * frame[3]]


def marks_on_screen(s, image, types):
    """The frames of the newest mark of each type, from image pixels to screen points."""
    frame = s['annotator']['frame']
    found = []
    for kind in types:
        marks = [m for m in s['editor']['marks'] if m['type'] == kind]
        if marks:
            found.append(on_screen(frame, image, marks[-1]['frame']))
    return found


def centre(r):
    return (round(r[0] + r[2] / 2, 1), round(r[1] + r[3] / 2, 1))


def home(s):
    """Whether the annotator is down and every card is back in its slot."""
    cards = s['stack']['cards']
    return not s['annotator']['windowVisible'] and cards and not any(c['out'] for c in cards)


def open_card(stage, card, event):
    """Glides to a card, clicks it, and waits for the editor to take presses."""
    point = centre(card['frame'])
    stage.glide(point)
    stage.pause(0.08)
    stage.require_owner(point, stage.app['name'])
    offset = stage.log_size()
    stage.event(event + '.click')
    stage.input('click', *point)
    line = stage.wait_log('[annotate] takes events', offset)
    t = stage.mono_from_log(line)
    s = stage.wait_state(lambda s: s['annotator']['key'] and s['annotator'].get('toolbar'), what='the editor coming up')
    rects = editor_rects(s)
    stage.event(event + '.landed', t=t, editor=rects['editor'], frame=rects['frame'])
    return s


def message_field(stage, s):
    """The toolbar's message field, found through Accessibility inside the toolbar's frame."""
    toolbar = s['annotator']['toolbar']
    out = subprocess.run([stage.paths['stage_bin'], 'fields', str(stage.pid)], capture_output=True, text=True, check=True)
    for line in out.stdout.splitlines():
        x, y, w, h = map(float, line.split())
        if toolbar[0] <= x and x + w <= toolbar[0] + toolbar[2] + 1 and toolbar[1] <= y and y + h <= toolbar[1] + toolbar[3] + 1:
            return [x, y, w, h]
    raise TakeFailed(f'no message field in the toolbar at {toolbar}')


def tower_top(stage):
    """The top of the water tower Claude built, in the scene's units, from the level's data."""
    with open(os.path.join(stage.paths['mew'], 'level4.json')) as f:
        layout = json.load(f)
    tower = layout.get('waterTower')
    if not tower:
        raise TakeFailed('Claude built no water tower')
    roofs = [(-10, 520, 720), (706, 1080, 700), (1120, 1570, 550)]
    roof = next((top for a, b, top in roofs if a <= tower['x'] <= b), None)
    if roof is None:
        raise TakeFailed(f"the water tower at x {tower['x']} stands on no roof")
    # scene.js: legs 128, tank 100, and a cap 0.42 of the tank's 124 width.
    return tower['x'], roof - 128 - 100 - 124 * 0.42


# ---- The beats -------------------------------------------------------------------------------

def beat_open(stage):
    stage.event('open')
    stage.pause(1.2)


def beat_capture(stage):
    c = stage.config
    x, y, w, h = stage.game
    start, end = (round(x, 1), round(y, 1)), (round(x + w, 1), round(y + h, 1))
    stage.capture = (start[0], start[1], end[0] - start[0], end[1] - start[1])
    stage.capture_path = os.path.join(stage.paths['watch'], c['marks'].get('file', 'Level 4.png'))
    # The crosshair comes up where the pointer is, so the pointer goes to the drag's start first.
    stage.glide(start)
    stage.pause(0.3)
    shot = subprocess.Popen(['screencapture', '-i', '-x', stage.capture_path])
    stage.event('capture.crosshair', capture=list(stage.capture))
    stage.pause(0.45)
    stage.event('capture.press')
    stage.drag(start, end, 0.9)
    stage.event('capture.release')
    if shot.wait(timeout=10) != 0 or not os.path.exists(stage.capture_path):
        raise TakeFailed('screencapture wrote nothing')
    s = stage.wait_state(lambda s: s['stack']['visible'] and s['stack']['cards'], what='the thumbnail')
    card = newest_card(s)
    stage.event('thumb.shown', card=card['frame'])
    stage.pause(0.35)
    s = open_card(stage, card, 'editor')
    stage.editor_frame = s['annotator']['frame']
    if s['annotator'].get('tool', '').lower() != 'rectangle':
        raise TakeFailed(f"the editor opened with {s['annotator'].get('tool')}, not the rectangle tool")


def beat_marks(stage):
    c = stage.config['marks']
    at = lambda p: stage.in_image(p, stage.capture, stage.editor_frame)
    image = png_size(stage.capture_path)
    for name in c['order']:
        mark = c[name]
        x, y, w, h = mark['box']
        a, b = at((x, y)), at((x + w, y + h))
        stage.glide(a)
        stage.require_editor(a)
        stage.pause(0.1)
        stage.event(f'{name}.press')
        stage.drag(a, b)
        stage.event(f'{name}.release')
        stage.pause(0.18)
        if 'note' in mark:
            stage.require_editor()
            stage.input('type', mark['note'], c.get('typing', 11))
        else:
            stage.require_editor()
            stage.input('key', 17)                  # T, then a click keeps the Text tool
            stage.pause(0.15)
            point = at(mark['at'])
            stage.glide(point)
            stage.require_editor(point)
            stage.input('click', *point)
            stage.pause(0.2)
            stage.input('type', mark['label'], c.get('typing', 11))
        stage.event(f'{name}.noted')
        rects = marks_on_screen(stage.state(), image, ['rectangle', 'text'])
        stage.event(f'{name}.framed', **{name: union(rects)})
        stage.pause(0.15)
        stage.require_editor()
        stage.input('key', 36)                      # Return ends the typing
        stage.pause(0.3)
        if 'label' in mark:
            stage.input('key', 15)                  # R, back to boxes
            stage.pause(0.1)
    # The drawing as it is sent: nothing selected.
    empty = at(c['empty'])
    stage.require_editor(empty)
    stage.input('click', *empty)
    stage.event('marks.done')
    stage.pause(0.6)


def beat_send(stage):
    """Types the message in the toolbar and sends the drawing to Claude Code with Cmd+Return."""
    c = stage.config['marks']
    s = stage.require_editor()
    offer = s['annotator'].get('offer') or {}
    if offer.get('kind') != 'send':
        raise TakeFailed(f'the toolbar offers {offer}, not Send')
    field = message_field(stage, s)
    point = centre(field)
    stage.glide(point)
    stage.require_owner(point, stage.app['name'])
    stage.event('message.click', field=field)
    stage.input('click', *point)
    stage.pause(0.25)
    s = stage.state()
    # The field holds the keys when the editor has given them up; typed into the editor instead,
    # the letters would be tool keys.
    if not s['annotator']['windowVisible'] or s['annotator']['key']:
        raise TakeFailed('the message field did not take the keys')
    stage.input('type', c['message'], c.get('typing', 11))
    stage.event('message.typed')
    stage.pause(0.5)
    offset = stage.log_size()
    stage.event('send.press')
    stage.input('key', 36, 'cmd')
    stage.wait_log('[send] prepared', offset)
    stage.wait_state(lambda s: not s['annotator']['windowVisible'], what='the editor closing')
    stage.event('send.closed')
    stage.claude_log = stage.log_size()
    stage.agent_wait('working', 30, 'Claude Code taking the drawing')
    stage.event('claude.working')


def beat_build(stage):
    """Claude edits the level, and the page reloads with what you marked."""
    since = stage.last('claude.working')['t']
    changed = stage.wait_event('game.changed', since, 600, 'Claude changing the game')
    shown = stage.wait_event('page.shown', changed['t'], 30, 'the game reloading')
    stage.event('build.shown', t=shown['t'], game=list(stage.game))


def beat_sketch(stage):
    """Claude renders the level and pushes its sketch of a way up; the card arrives and leaves."""
    line = stage.wait_log('[add] ok', stage.claude_log, timeout=600)
    stage.event('push', t=stage.mono_from_log(line))
    s = stage.wait_state(lambda s: s['stack']['visible'] and s['stack']['cards'], timeout=15, what="Claude's card")
    card = newest_card(s)
    stage.sketch_file = card['file']
    stage.event('card.shown', card=card['frame'])
    stage.agent_wait('idle', 300, 'Claude finishing its turn')
    stage.event('claude.idle')
    stage.wait_state(lambda s: not s['stack']['visible'], timeout=30, what="Claude's card leaving")
    stage.event('card.gone')
    stage.pause(0.8)


def beat_history(stage):
    offset = stage.log_size()
    stage.event('history')
    stage.url('recent')
    line = stage.wait_log('[stack] shown', offset)
    s = stage.wait_state(lambda s: s['stack']['visible'] and s['stack']['isStack'], what='the stack')
    frames = [c['frame'] for c in s['stack']['cards']]
    stage.event('stack.shown', t=stage.mono_from_log(line), stack=union(frames))
    stage.pause(0.5)
    s = open_card(stage, newest_card(s), 'editor2')
    stage.route_frame = s['annotator']['frame']
    offer = s['annotator'].get('offer') or {}
    if offer.get('kind') != 'reply':
        raise TakeFailed(f"Claude's card offers {offer}, not Reply")


def beat_adjust(stage):
    """Drags one of Claude's boxes onto the water tower it built."""
    c = stage.config['adjust']
    s = stage.require_editor()
    image = png_size(stage.sketch_file)
    boxes = sorted((m for m in s['editor']['marks'] if m['type'] == 'rectangle'), key=lambda m: m['frame'][1])
    if len(boxes) < 2:
        raise TakeFailed(f"Claude's sketch has {len(boxes)} boxes")
    box = boxes[len(boxes) // 2] if c.get('ledge', 'middle') == 'middle' else boxes[int(c['ledge'])]
    bx, by, bw, bh = box['frame']
    tx, ty = tower_top(stage)
    # The scene's units in the image's pixels.
    k = image[0] / 1600
    target = (tx * k - bw / 2, (ty - c.get('above', 16)) * k - bh)
    frame = stage.route_frame
    grab = on_screen(frame, image, [bx + bw / 2, by, 0, 0])[:2]
    drop = on_screen(frame, image, [target[0] + bw / 2, target[1], 0, 0])[:2]
    stage.glide(tuple(grab))
    stage.pause(0.15)
    stage.require_editor(tuple(grab))
    stage.event('move.press')
    stage.drag(tuple(grab), tuple(drop), 0.7)
    before = on_screen(frame, image, box['frame'])
    after = on_screen(frame, image, [target[0], target[1], bw, bh])
    stage.event('move.release', ledge=union([before, after]))
    s = stage.state()
    marks = [on_screen(frame, image, m['frame']) for m in s['editor']['marks']]
    stage.event('move.framed', sketch=union(marks + [before, after]))
    stage.pause(1.0)


def beat_reply(stage):
    stage.require_editor()
    offset = stage.log_size()
    stage.event('reply.press')
    stage.input('key', 36)                          # Return replies on a card that names its session
    stage.wait_log('[send] prepared', offset)
    stage.wait_state(home, what='the card flying home')
    stage.event('reply.home')
    stage.agent_wait('working', 30, 'Claude Code taking the reply')
    stage.event('reply.working')
    changed = stage.wait_event('game.changed', stage.last('reply.working')['t'], 600, 'Claude building the ledges')
    shown = stage.wait_event('page.shown', changed['t'], 30, 'the game reloading')
    stage.event('ledges.shown', t=shown['t'])
    stage.agent_wait('idle', 300, 'Claude finishing')
    stage.event('claude.done')
    stage.pause(2.0)
    stage.event('end')


BEATS = [beat_open, beat_capture, beat_marks, beat_send, beat_build, beat_sketch, beat_history, beat_adjust, beat_reply]


def perform(stage, record=True):
    """One take: setup, every beat, teardown. Returns the events, or raises TakeFailed."""
    try:
        setup(stage)
        stage.pasteboard_saved = subprocess.run([stage.paths['stage_bin'], 'pasteboard', 'save', stage.paths['pasteboard']],
                                                capture_output=True, text=True, check=True).stdout.strip()
        if record:
            start_recorder(stage)
        for beat in BEATS:
            print(beat.__name__.replace('beat_', ''), flush=True)
            beat(stage)
        if record:
            stop_recorder(stage)
    finally:
        teardown(stage)
        if getattr(stage, 'pasteboard_saved', None):
            restored = subprocess.run([stage.paths['stage_bin'], 'pasteboard', 'restore', stage.paths['pasteboard']])
            # Kept only while it has not been put back, so `trailer.py restore` never puts back an old one.
            if restored.returncode == 0:
                shutil.rmtree(stage.paths['pasteboard'])
    return stage.events
