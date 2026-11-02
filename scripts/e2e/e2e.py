#!/usr/bin/env python3
"""Vignette's end-to-end tests, run against a test copy built from the current source.

    e2e.py list                      the scenarios, and which post keys or clicks
    e2e.py run [scenario …]          build the test copy, run the scenarios (all without input by
                                     default), and write a report
    e2e.py run --input [scenario …]  also run the scenarios that post keys and clicks
    e2e.py run --no-build …          use the copy already built
    e2e.py restore                   put back the pasteboard an interrupted run saved

The test copy (`scripts/e2e/build.sh`) has its own bundle id, name and URL scheme. Each scenario
launches it on a fresh scratch home (`CFFIXED_USER_HOME`), settings file (`VIGNETTE_SETTINGS`) and
watch folder, so it never reads or writes the person's own. Preferences ignore that home, so the
copy's two domains are cleared before each scenario. A launch with no environment, such as
macOS's Quit & Reopen, takes the home the copy's Info.plist names (build.sh), which the runner links
to the scenario's. A test launch uses no codex and no herdr unless `VIGNETTE_CODEX` or
`VIGNETTE_HERDR` names one, and every agent session is a fake.
A Claude Code session is an inbox folder held by a `sleep` process, which is all Send looks for. A
Codex thread is listed by a fake codex (`fake_codex.py`) that `VIGNETTE_CODEX` names.
A scenario whose `copy` is 'fresh' runs on a second copy, `build.sh fresh`, granted nothing and
reset with tccutil before it, for the paths without a permission.

Before any key or click, a scenario reads the test copy's state in the same step and stops unless
the editor or the stack is up and key. docs/e2e-suite-plan-2026-09-29.md has the design.
"""
import argparse
import datetime
import json
import os
import plistlib
import random
import re
import shutil
import signal
import subprocess
import sys
import time
import urllib.parse
import uuid

from report import Report

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, 'out')
PROBE = os.path.join(OUT, 'bin', 'probe')
INPUT = os.path.join(REPO, 'scripts', 'input.sh')
SAVED_PASTEBOARD = os.path.join(OUT, 'pasteboard')

# The colours a default install draws in (UITweaks' personColor and agentColor).
PERSON = (0xe0, 0x31, 0x31)
AGENT = (0x36, 0x4f, 0xc7)


class Failed(Exception):
    pass


def project_identity():
    text = open(os.path.join(REPO, 'project.yml')).read()
    name = re.search(r'^name: *(\S.*)$', text, re.M).group(1).strip()
    bundle = re.search(r'PRODUCT_BUNDLE_IDENTIFIER: *(com\S+)', text).group(1)
    scheme = re.search(r'VIGNETTE_URL_SCHEME: *(\S+)', text).group(1)
    return name, bundle, scheme


def test_copy(kind=''):
    """The copy `build.sh <kind>` builds: '' for the one granted Accessibility and Screen Recording
    by hand, 'fresh' for the one granted nothing."""
    name, bundle, scheme = project_identity()
    suffix, label = ('e2e-fresh', 'E2E Fresh') if kind == 'fresh' else ('e2e', 'E2E')
    app_name = f'{name} {label}'
    path = os.path.join(OUT, f'dd-{suffix}', 'Build', 'Products', 'Release', f'{app_name}.app')
    return {'kind': kind, 'name': app_name, 'bundle': f'{bundle}.{suffix}', 'scheme': f'{scheme}-{suffix}', 'path': path,
            'executable': os.path.join(path, 'Contents', 'MacOS', app_name), 'relaunchHome': relaunch_home(path)}


def relaunch_home(app):
    """The home the copy's Info.plist names for a launch with no environment (build.sh), or None."""
    try:
        with open(os.path.join(app, 'Contents', 'Info.plist'), 'rb') as f:
            return plistlib.load(f).get('LSEnvironment', {}).get('CFFIXED_USER_HOME')
    except FileNotFoundError:
        return None


def running_pids(executable):
    out = subprocess.run(['ps', '-axo', 'pid=,args='], capture_output=True, text=True).stdout
    return [int(line.split(None, 1)[0]) for line in out.splitlines()
            if line.split(None, 1)[1:] and line.split(None, 1)[1].startswith(executable)]


def wait_gone(pid, timeout=10):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        time.sleep(0.1)
    return False


def color_near(hex_color, rgb, tolerance=40):
    got = tuple(int(hex_color[i:i + 2], 16) for i in (1, 3, 5))
    return all(abs(a - b) <= tolerance for a, b in zip(got, rgb))


def pixels(png, points):
    out = subprocess.run([PROBE, 'pixels', png, *[f'{x},{y}' for x, y in points]],
                         capture_output=True, text=True, check=True).stdout.splitlines()
    size = tuple(int(v) for v in out[0].split()[1:])
    colors = {}
    for line in out[1:]:
        point, color = line.split()
        x, y = point.split(',')
        colors[(int(x), int(y))] = color
    return size, colors


# ---- One launch of the test copy -------------------------------------------------------------


class App:
    """The test copy on one scratch home. Every command goes to this copy by path and scheme."""

    def __init__(self, copy, folder, report):
        self.copy = copy
        self.folder = folder
        self.report = report
        self.home = os.path.join(folder, 'home')
        self.settings = os.path.join(self.home, 'settings.json')
        self.watch = os.path.join(self.home, 'Screenshots')
        self.log = os.path.join(self.home, 'Library', 'Logs', f"{copy['name']}.log")
        self.support = os.path.join(self.home, 'Library', 'Application Support', copy['bundle'])
        self.pid = None
        self.env = {}
        self.fakes = []
        for d in [self.watch, os.path.dirname(self.log)]:
            os.makedirs(d, exist_ok=True)

    # -- Setup

    def write_settings(self, **overrides):
        data = {'version': 2, 'setup': 'done', 'agentSkill': 'off', 'launchAtLogin': False,
                # Not a double tap: the person's own Vignette answers that one.
                'recentHotkey': 'ctrl+opt+cmd+9'}
        data.update(overrides)
        with open(self.settings, 'w') as f:
            json.dump(data, f, indent=2)

    def defaults(self, domain, *args):
        subprocess.run(['defaults', 'write', domain, *args], check=True)

    def reset_defaults(self):
        """Clears the copy's preference domains, which every scenario shares: macOS keeps them in
        the real ~/Library/Preferences whatever the home."""
        for domain in (self.copy['bundle'], f"{self.copy['bundle']}.screencapture"):
            subprocess.run(['defaults', 'delete', domain], capture_output=True)
            if subprocess.run(['defaults', 'read', domain], capture_output=True).returncode == 0:
                raise Failed(f'{domain} still holds values after defaults delete')

    def prepare(self, **settings):
        if not os.path.exists(self.settings):
            self.write_settings(**settings)
        # Apple's screenshot location, moved to this copy's own domain by VIGNETTE_SETTINGS.
        self.defaults(f"{self.copy['bundle']}.screencapture", 'location', self.watch)
        # No update checks: the test copy would ask the real feed.
        self.defaults(self.copy['bundle'], 'SUEnableAutomaticChecks', '-bool', 'false')

    # -- Launch and stop

    def link_relaunch_home(self):
        """Points the home the copy's Info.plist names at this scenario's, so a launch with no
        environment comes back on this scenario's files. A folder there was made by such a launch
        while nothing was linked."""
        link = self.copy['relaunchHome']
        os.makedirs(os.path.dirname(link), exist_ok=True)
        if os.path.isdir(link) and not os.path.islink(link):
            shutil.rmtree(link)
        temp = f'{link}.{os.getpid()}'
        os.symlink(self.home, temp)
        os.replace(temp, link)

    def unlink_relaunch_home(self):
        link = self.copy['relaunchHome']
        if os.path.islink(link) and os.readlink(link) == self.home:
            os.remove(link)

    def launch(self, **env):
        for pid in running_pids(self.copy['executable']):
            raise Failed(f'another test copy is running (pid {pid}); stop it first')
        self.env = env
        self.link_relaunch_home()
        offset = self.log_size()
        args = ['open', '-g', '--env', f'VIGNETTE_SETTINGS={self.settings}', '--env', f'CFFIXED_USER_HOME={self.home}']
        for key, value in env.items():
            args += ['--env', f'{key}={value}']
        subprocess.run(args + [self.copy['path']], check=True)
        line = self.wait_log('[app] ready', offset, timeout=30)
        self.pid = int(re.search(r'pid=(\d+)', line).group(1))
        self.state()
        return line

    def stop(self):
        if not self.pid:
            return
        try:
            os.kill(self.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        if not wait_gone(self.pid):
            os.kill(self.pid, signal.SIGKILL)
            wait_gone(self.pid, 5)
        self.pid = None

    def close(self):
        self.stop()
        self.unlink_relaunch_home()
        pids = os.path.join(self.folder, 'herdr', 'pids')
        if os.path.exists(pids):
            self.fakes += [int(line) for line in open(pids).read().split()]
        for pid in self.fakes:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        self.fakes = []

    # -- Commands, the log and the state

    def log_size(self):
        return os.path.getsize(self.log) if os.path.exists(self.log) else 0

    def log_since(self, offset):
        if not os.path.exists(self.log):
            return ''
        with open(self.log, 'rb') as f:
            f.seek(offset)
            return f.read().decode('utf-8', 'replace')

    def wait_log(self, needle, offset, timeout=10, also=None):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            for line in self.log_since(offset).splitlines():
                if needle in line and (also is None or also in line):
                    return line
            time.sleep(0.05)
        raise Failed(f'no {needle!r}{f" with {also!r}" if also else ""} in the log within {timeout} s')

    def url(self, command):
        # With the copy gone, `open` would launch it again without this scenario's environment.
        if not self.pid:
            raise Failed(f'the test copy is not running; not sending {command.split("?")[0]}')
        try:
            os.kill(self.pid, 0)
        except ProcessLookupError:
            raise Failed(f'the test copy (pid {self.pid}) is gone; not sending {command.split("?")[0]}')
        subprocess.run(['open', '-g', '-a', self.copy['path'], f"{self.copy['scheme']}://{command}"], check=True)

    def answer(self, name, offset, timeout=15):
        """The `[name] ok` or `[name] error` line after `offset`."""
        pattern = re.compile(rf'\[{re.escape(name)}\] (ok|error)')
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            for line in self.log_since(offset).splitlines():
                if pattern.search(line):
                    return line
            time.sleep(0.05)
        raise Failed(f'{name} did not answer within {timeout} s')

    def command(self, name, query='', timeout=15):
        """Sends a command and returns its `ok` detail; an `error` line fails the step."""
        offset = self.log_size()
        self.url(name + (f'?{query}' if query else ''))
        line = self.answer(name, offset, timeout)
        if f'[{name}] error' in line:
            raise Failed(line.split(' ', 1)[1])
        return line.split(f'[{name}] ok', 1)[1].strip()

    def command_error(self, name, query=''):
        """Sends a command that should fail and returns its error line."""
        offset = self.log_size()
        self.url(name + (f'?{query}' if query else ''))
        line = self.answer(name, offset)
        if f'[{name}] error' not in line:
            raise Failed(f'{name} should have failed: {line}')
        return line

    def state(self):
        tag = f'e2e{random.randrange(10 ** 9)}'
        offset = self.log_size()
        self.url(f'state?tag={tag}')
        line = self.wait_log('[state] ', offset, also=tag)
        s = json.loads(line.split('[state] ', 1)[1])
        app = s['app']
        if (os.path.realpath(app['bundle']) != os.path.realpath(self.copy['path'])
                or os.path.realpath(app['settingsFile']) != os.path.realpath(self.settings)
                or os.path.realpath(app['watchFolder']) != os.path.realpath(self.watch)):
            raise Failed(f"state came from {app['bundle']} on {app['settingsFile']} watching {app['watchFolder']}, "
                         'not the test copy on its scratch files')
        return s

    def wait_state(self, test, what, timeout=10):
        end = time.monotonic() + timeout
        while True:
            s = self.state()
            if test(s):
                return s
            if time.monotonic() > end:
                raise Failed(f'{what} did not happen within {timeout} s')
            time.sleep(0.1)

    def file_query(self, *paths):
        return '&'.join('file=' + urllib.parse.quote(p, safe='') for p in paths)

    # -- Test material

    def image(self, name, w=1600, h=1000, folder=None):
        path = os.path.join(folder or self.folder, name)
        subprocess.run([PROBE, 'image', path, str(w), str(h)], check=True)
        return path

    def fake_session(self, project='fake-project'):
        """A Claude Code session as Send sees one: an inbox under this copy's Application Support,
        named by a live pid, with its session id, its project, and a fresh `alive`. Returns the
        session id and the inbox folder."""
        holder = subprocess.Popen(['sleep', '3600'])
        self.fakes.append(holder.pid)
        inbox = os.path.join(self.support, 'claude-sessions', str(holder.pid))
        os.makedirs(inbox, exist_ok=True)
        session = str(uuid.uuid4())
        for name, text in [('session', session), ('cwd', f'/tmp/e2e/{project}'), ('turn', 'idle')]:
            with open(os.path.join(inbox, name), 'w') as f:
                f.write(text + '\n')
        self.touch_alive(inbox)
        return session, inbox

    def fake_codex(self, project='codex-project', name='Fix the checkout', loaded=True):
        """A codex that lists one thread, used just now, in `/tmp/e2e/<project>`, and records every
        call. With `loaded`, an engine has the thread open: its writer lock is in the scratch home's
        `.codex`, which is where Vignette looks (`CodexConnection.isLoaded`). Returns the thread id
        and the env that points the launch at it."""
        folder = os.path.join(self.folder, 'codex')
        os.makedirs(folder, exist_ok=True)
        thread = str(uuid.uuid4())
        with open(os.path.join(folder, 'threads.json'), 'w') as f:
            json.dump([{'id': thread, 'name': name, 'cwd': f'/tmp/e2e/{project}', 'recencyAt': int(time.time()),
                        'preview': name}], f)
        codex = os.path.join(folder, 'codex')
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fake_codex.py')
        # This Python, by path: the app runs codex with launchd's PATH, where python3 can be Apple's stub.
        with open(codex, 'w') as f:
            f.write(f"#!/bin/sh\nexec '{sys.executable}' '{script}' '{folder}' \"$@\"\n")
        os.chmod(codex, 0o755)
        if loaded:
            locks = os.path.join(self.home, '.codex', 'thread-writer-locks')
            os.makedirs(locks, exist_ok=True)
            open(os.path.join(locks, f'{thread}.lock'), 'w').close()
        return thread, {'VIGNETTE_CODEX': codex}

    def fake_herdr(self):
        """A herdr that opens tabs and, for `claude` typed into one, brings up a plugin inbox for that
        session (`fake_herdr.py`). Returns the env that points the launch at it."""
        folder = os.path.join(self.folder, 'herdr')
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, 'inboxes'), 'w') as f:
            f.write(os.path.join(self.support, 'claude-sessions'))
        herdr = os.path.join(folder, 'herdr')
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fake_herdr.py')
        with open(herdr, 'w') as f:
            f.write(f"#!/bin/sh\nexec '{sys.executable}' '{script}' '{folder}' \"$@\"\n")
        os.chmod(herdr, 0o755)
        return {'VIGNETTE_HERDR': herdr}

    def herdr_calls(self):
        path = os.path.join(self.folder, 'herdr', 'calls.jsonl')
        return [json.loads(line)['args'] for line in open(path)] if os.path.exists(path) else []

    def past_project(self, name='e2e-site', title='Fix the nav spacing'):
        """A project with one past Claude Code session and none running: its folder, a prompt in the
        scratch home's Claude Code history, and the session's transcript where Claude Code keeps it.
        Returns the folder and the session id."""
        folder = os.path.join(self.folder, 'projects', name)
        os.makedirs(folder, exist_ok=True)
        session = str(uuid.uuid4())
        now = time.time()
        claude = os.path.join(self.home, '.claude')
        os.makedirs(claude, exist_ok=True)
        with open(os.path.join(claude, 'history.jsonl'), 'a') as f:
            f.write(json.dumps({'display': 'hi', 'pastedContents': {}, 'timestamp': int(now * 1000),
                                'project': folder, 'sessionId': session}, separators=(',', ':')) + '\n')
        transcripts = os.path.join(claude, 'projects', re.sub(r'[^A-Za-z0-9]', '-', folder))
        os.makedirs(transcripts, exist_ok=True)
        stamp = time.strftime('%Y-%m-%dT%H:%M:%S.000Z', time.gmtime(now))
        with open(os.path.join(transcripts, f'{session}.jsonl'), 'w') as f:
            f.write(json.dumps({'type': 'ai-title', 'aiTitle': title, 'sessionId': session}, separators=(',', ':')) + '\n')
            f.write(json.dumps({'type': 'user', 'timestamp': stamp, 'cwd': folder,
                                'message': {'role': 'user', 'content': 'hi'}}, separators=(',', ':')) + '\n')
        return folder, session

    def inbox_of(self, session):
        """The inbox folder that holds `session`, or None."""
        root = os.path.join(self.support, 'claude-sessions')
        for pid in os.listdir(root) if os.path.isdir(root) else []:
            path = os.path.join(root, pid, 'session')
            if os.path.exists(path) and open(path).read().strip() == session:
                return os.path.join(root, pid)
        return None

    def codex_calls(self, verb=None):
        """The fake codex's calls and the requests it answered, oldest first (`fake_codex.py`); with
        `verb`, only those whose first argument it is."""
        path = os.path.join(self.folder, 'codex', 'calls.jsonl')
        calls = [json.loads(line) for line in open(path)] if os.path.exists(path) else []
        return [c for c in calls if verb is None or c['args'][:1] == [verb]]

    def touch_alive(self, inbox):
        with open(os.path.join(inbox, 'alive'), 'w'):
            pass

    def lines_in(self, inbox):
        return sorted(n for n in os.listdir(inbox) if n.endswith('.line') and not n.startswith('.'))

    # -- Input, gated on the state

    def require_key(self, s, where):
        """Stops unless `where` ('annotator', 'toolbar' or 'stack') of this copy is up and key, read
        in the same step, so a key or a click never reaches another app."""
        if where == 'annotator':
            ok = s['annotator']['windowVisible'] and s['annotator']['key']
        elif where == 'toolbar':
            ok = s['annotator']['windowVisible'] and s['annotator']['toolbarKey']
        else:
            ok = s['stack'].get('visible') and s['stack'].get('key')
        if not ok:
            raise Failed(f'the {where} is not up and key; not posting input')

    def input(self, *args):
        subprocess.run([INPUT, *map(str, args)], check=True)

    def keys(self, where, *args):
        self.require_key(self.state(), where)
        self.input(*args)

    # -- The report

    def capture(self, rect, name):
        """A capture of `rect`, [x, y, w, h] in global top-left points, into the report."""
        path = os.path.join(self.folder, f'{name}.png')
        x, y, w, h = (round(v) for v in rect)
        subprocess.run(['screencapture', '-x', '-R', f'{x},{y},{w},{h}', path], check=True)
        self.report.image(path)
        return path


# ---- Running ---------------------------------------------------------------------------------


def build_probe():
    source = os.path.join(HERE, 'probe.swift')
    if not os.path.exists(PROBE) or os.path.getmtime(PROBE) < os.path.getmtime(source):
        os.makedirs(os.path.dirname(PROBE), exist_ok=True)
        subprocess.run(['swiftc', '-O', '-o', PROBE, source], check=True)


def first_run(copy, timeout=60):
    """Runs the test copy once and returns the tries and the seconds it took.

    macOS checks a new executable the first time it runs, and now and then refuses that first run:
    syspolicyd logs "Terminating process due to Gatekeeper rejection" and kills it, while `open`
    still answers 0. `reply --help` exits before the app starts."""
    start = time.monotonic()
    tries = 0
    while True:
        tries += 1
        result = subprocess.run([copy['executable'], 'reply', '--help'], capture_output=True, text=True)
        if result.returncode == 0:
            return tries, time.monotonic() - start
        killed = result.returncode == -signal.SIGKILL
        if not killed:
            sys.exit(f'the test copy did not run: exit {result.returncode} {result.stderr.strip()}')
        if time.monotonic() - start > timeout:
            sys.exit(f'macOS killed every run of the test copy for {timeout} s; '
                     "`log show --last 5m --predicate 'process == \"syspolicyd\"'` says why")
        time.sleep(1)


def save_pasteboard():
    if os.path.exists(SAVED_PASTEBOARD):
        sys.exit(f'a pasteboard from an earlier run is still saved at {SAVED_PASTEBOARD}; run `e2e.py restore` first')
    subprocess.run([PROBE, 'pasteboard', 'save', SAVED_PASTEBOARD], check=True, stdout=subprocess.DEVNULL)


def restore_pasteboard():
    if not os.path.exists(SAVED_PASTEBOARD):
        return
    subprocess.run([PROBE, 'pasteboard', 'restore', SAVED_PASTEBOARD], check=True, stdout=subprocess.DEVNULL)
    shutil.rmtree(SAVED_PASTEBOARD)


def all_scenarios():
    import live_ink
    import scenarios
    return scenarios.ALL + live_ink.ALL


def run(names, with_input, build):
    everything = all_scenarios()
    chosen = [s for s in everything if not names or s.__name__ in names]
    unknown = set(names) - {s.__name__ for s in everything}
    if unknown:
        sys.exit(f'no scenario named {", ".join(sorted(unknown))}; see `e2e.py list`')
    build_probe()
    if with_input:
        # Compiling takes seconds, longer than a lone thumbnail stays, so it is done before any scenario.
        subprocess.run([INPUT, 'build'], check=True)
    # A scenario's `copy` names the copy it runs on (`test_copy`); only the copies chosen ones use are built.
    copies = {kind: test_copy(kind) for kind in sorted({getattr(s, 'copy', '') for s in chosen})}
    for kind, copy in copies.items():
        if build:
            result = subprocess.run([os.path.join(HERE, 'build.sh'), *([kind] if kind else [])], capture_output=True, text=True)
            if result.returncode != 0:
                sys.exit(result.stderr.strip() or 'build failed')
        if not os.path.exists(copy['executable']):
            sys.exit(f"no {copy['name']}; run without --no-build")
        if not copy['relaunchHome']:
            sys.exit(f"{copy['name']} names no home for a launch with no environment; run without --no-build")
        for pid in running_pids(copy['executable']):
            sys.exit(f"{copy['name']} is already running (pid {pid})")
        # A new build's first run pays macOS's check of it, or is killed by it, so no scenario's launch does.
        tries, seconds = first_run(copy)
        line = f"{copy['name']} ran once before the scenarios in {seconds * 1000:.0f} ms"
        if tries > 1:
            killed = 'try 1' if tries == 2 else f'tries 1 to {tries - 1}'
            line += f', on try {tries}; macOS killed {killed} (SIGKILL: Gatekeeper refused it)'
        print(line, flush=True)

    folder = os.path.join(OUT, 'runs', datetime.datetime.now().strftime('%Y-%m-%d-%H%M%S'))
    os.makedirs(folder)
    report = Report(folder)
    save_pasteboard()
    # A stopped run still puts the pasteboard back and stops the copy.
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    failed = 0
    try:
        for scenario in chosen:
            doc = (scenario.__doc__ or '').strip().split('\n\n')[0].replace('\n', ' ')
            report.begin(scenario.__name__, doc)
            if getattr(scenario, 'needs_input', False) and not with_input:
                report.step('posts keys or clicks; run with --input', 'skip')
                report.end('skip')
                continue
            app = App(copies[getattr(scenario, 'copy', '')], os.path.join(folder, scenario.__name__), report)
            try:
                app.reset_defaults()
                if app.copy['kind'] == 'fresh':
                    # Whatever was granted to it by hand since the last run.
                    subprocess.run(['tccutil', 'reset', 'All', app.copy['bundle']], capture_output=True)
                scenario(app)
                report.end('pass', app.log_since(0))
            except Failed as error:
                failed += 1
                report.step(str(error), 'fail')
                report.end('fail', app.log_since(0))
            except Exception as error:
                failed += 1
                report.step(f'{type(error).__name__}: {error}', 'fail')
                report.end('fail', app.log_since(0))
            finally:
                app.close()
    except KeyboardInterrupt:
        print('stopped', flush=True)
        failed += 1
    finally:
        restore_pasteboard()
        path = report.write()
    print(f'report: {path}')
    return 1 if failed else 0


def main():
    sys.path.insert(0, HERE)
    # The scenarios import this module by name; run as a script, it is __main__, and a second copy
    # would have its own Failed.
    sys.modules.setdefault('e2e', sys.modules[__name__])
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='cmd', required=True)
    sub.add_parser('list')
    r = sub.add_parser('run')
    r.add_argument('--input', action='store_true')
    r.add_argument('--no-build', action='store_true')
    r.add_argument('names', nargs='*')
    sub.add_parser('restore')
    args = parser.parse_args()
    if args.cmd == 'list':
        for s in all_scenarios():
            first = (s.__doc__ or '').strip().split('\n')[0]
            print(f"{s.__name__:<18} {'input ' if getattr(s, 'needs_input', False) else '      '}{first}")
    elif args.cmd == 'restore':
        build_probe()
        restore_pasteboard()
    else:
        sys.exit(run(args.names, args.input, not args.no_build))


if __name__ == '__main__':
    main()
