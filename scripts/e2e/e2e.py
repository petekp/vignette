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
watch folder, so it never reads or writes the person's own. A test launch uses no codex and no
herdr unless `VIGNETTE_CODEX` or `VIGNETTE_HERDR` names one, and every agent session is a fake.
A Claude Code session is an inbox folder held by a `sleep` process, which is all Send looks for. A
Codex thread is listed by a fake codex (`fake_codex.py`) that `VIGNETTE_CODEX` names.

Before any key or click, a scenario reads the test copy's state in the same step and stops unless
the editor or the stack is up and key. docs/e2e-suite-plan-2026-09-29.md has the design.
"""
import argparse
import datetime
import html
import json
import os
import random
import re
import shutil
import signal
import subprocess
import sys
import time
import urllib.parse
import uuid

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


def test_copy():
    name, bundle, scheme = project_identity()
    app_name = f'{name} E2E'
    path = os.path.join(OUT, 'dd-e2e', 'Build', 'Products', 'Release', f'{app_name}.app')
    return {'name': app_name, 'bundle': f'{bundle}.e2e', 'scheme': f'{scheme}-e2e', 'path': path,
            'executable': os.path.join(path, 'Contents', 'MacOS', app_name)}


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
        env = dict(os.environ, CFFIXED_USER_HOME=self.home)
        subprocess.run(['defaults', 'write', domain, *args], env=env, check=True)

    def prepare(self, **settings):
        if not os.path.exists(self.settings):
            self.write_settings(**settings)
        # Apple's screenshot location, moved to this copy's own domain by VIGNETTE_SETTINGS.
        self.defaults(f"{self.copy['bundle']}.screencapture", 'location', self.watch)
        # No update checks: the test copy would ask the real feed.
        self.defaults(self.copy['bundle'], 'SUEnableAutomaticChecks', '-bool', 'false')

    # -- Launch and stop

    def launch(self, **env):
        for pid in running_pids(self.copy['executable']):
            raise Failed(f'another test copy is running (pid {pid}); stop it first')
        self.env = env
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
        # With the copy gone, `open` would launch it again without VIGNETTE_SETTINGS, on the
        # person's own settings and screenshots.
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
        """Stops unless `where` ('annotator' or 'stack') of this copy is up and key, read in the
        same step, so a key or a click never reaches another app."""
        if where == 'annotator':
            ok = s['annotator']['windowVisible'] and s['annotator']['key']
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


# ---- The report --------------------------------------------------------------------------------


class Report:
    def __init__(self, folder):
        self.folder = folder
        self.scenarios = []
        self.current = None

    def begin(self, name, doc):
        self.current = {'name': name, 'doc': doc, 'steps': [], 'status': 'running', 'images': []}
        self.scenarios.append(self.current)
        print(f'{name}', flush=True)

    def step(self, name, status='pass', detail=''):
        self.current['steps'].append({'name': name, 'status': status, 'detail': detail})
        mark = {'pass': 'ok  ', 'fail': 'FAIL', 'skip': 'skip', 'note': 'note'}[status]
        print(f'  {mark} {name}' + (f': {detail}' if detail else ''), flush=True)

    def image(self, path):
        self.current['images'].append(os.path.relpath(path, self.folder))

    def end(self, status, log=''):
        self.current['status'] = status
        self.current['log'] = log

    def write(self):
        with open(os.path.join(self.folder, 'report.json'), 'w') as f:
            json.dump(self.scenarios, f, indent=2)
        rows = []
        for s in self.scenarios:
            steps = ''.join(f"<li class='{st['status']}'><b>{html.escape(st['name'])}</b>"
                            f"{(' · ' + html.escape(st['detail'])) if st['detail'] else ''}</li>" for st in s['steps'])
            images = ''.join(f"<img src='{html.escape(i)}' alt=''>" for i in s['images'])
            log = f"<details><summary>Log</summary><pre>{html.escape(s.get('log', ''))}</pre></details>" if s.get('log') else ''
            rows.append(f"<section class='{s['status']}'><h2>{html.escape(s['name'])} <span>{s['status']}</span></h2>"
                        f"<p>{html.escape(s['doc'])}</p><ul>{steps}</ul>{images}{log}</section>")
        passed = sum(s['status'] == 'pass' for s in self.scenarios)
        page = f"""<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Vignette E2E</title>
<style>
:root {{ --bg: #fff; --fg: #1a1a1a; --muted: #666; --line: #ddd; --pass: #2b8a3e; --fail: #e03131; --skip: #868e96; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg: #161616; --fg: #eee; --muted: #999; --line: #333; --pass: #51cf66; --fail: #ff6b6b; }} }}
body {{ background: var(--bg); color: var(--fg); font: 14px/1.5 -apple-system, system-ui, sans-serif; margin: 0 auto; max-width: 900px; padding: 16px; }}
section {{ border-top: 1px solid var(--line); padding: 8px 0 16px; }}
h2 span {{ font-size: 13px; text-transform: uppercase; margin-left: 8px; }}
section.pass h2 span, li.pass b {{ color: var(--pass); }} section.fail h2 span, li.fail b {{ color: var(--fail); }}
section.skip h2 span, li.skip b {{ color: var(--skip); }}
p {{ color: var(--muted); margin: 0 0 8px; }} ul {{ padding-left: 18px; margin: 0 0 8px; }}
img {{ max-width: 100%; border: 1px solid var(--line); margin: 4px 0; }}
pre {{ white-space: pre-wrap; font-size: 11px; overflow-wrap: anywhere; }}
</style>
<h1>Vignette E2E · {passed} of {len(self.scenarios)} passed</h1>
<p>{html.escape(os.path.basename(self.folder))}</p>
{''.join(rows)}"""
        path = os.path.join(self.folder, 'report.html')
        with open(path, 'w') as f:
            f.write(page)
        return path


# ---- Running ---------------------------------------------------------------------------------


def build_probe():
    source = os.path.join(HERE, 'probe.swift')
    if not os.path.exists(PROBE) or os.path.getmtime(PROBE) < os.path.getmtime(source):
        os.makedirs(os.path.dirname(PROBE), exist_ok=True)
        subprocess.run(['swiftc', '-O', '-o', PROBE, source], check=True)


def save_pasteboard():
    if os.path.exists(SAVED_PASTEBOARD):
        sys.exit(f'a pasteboard from an earlier run is still saved at {SAVED_PASTEBOARD}; run `e2e.py restore` first')
    subprocess.run([PROBE, 'pasteboard', 'save', SAVED_PASTEBOARD], check=True, stdout=subprocess.DEVNULL)


def restore_pasteboard():
    if not os.path.exists(SAVED_PASTEBOARD):
        return
    subprocess.run([PROBE, 'pasteboard', 'restore', SAVED_PASTEBOARD], check=True, stdout=subprocess.DEVNULL)
    shutil.rmtree(SAVED_PASTEBOARD)


def run(names, with_input, build):
    import scenarios
    chosen = [s for s in scenarios.ALL if not names or s.__name__ in names]
    unknown = set(names) - {s.__name__ for s in scenarios.ALL}
    if unknown:
        sys.exit(f'no scenario named {", ".join(sorted(unknown))}; see `e2e.py list`')
    build_probe()
    if build:
        result = subprocess.run([os.path.join(HERE, 'build.sh')], capture_output=True, text=True)
        if result.returncode != 0:
            sys.exit(result.stderr.strip() or 'build failed')
    copy = test_copy()
    if not os.path.exists(copy['executable']):
        sys.exit('no test copy; run without --no-build')
    for pid in running_pids(copy['executable']):
        sys.exit(f'a test copy is already running (pid {pid})')

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
            app = App(copy, os.path.join(folder, scenario.__name__), report)
            try:
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
        import scenarios
        for s in scenarios.ALL:
            first = (s.__doc__ or '').strip().split('\n')[0]
            print(f"{s.__name__:<18} {'input ' if getattr(s, 'needs_input', False) else '      '}{first}")
    elif args.cmd == 'restore':
        build_probe()
        restore_pasteboard()
    else:
        sys.exit(run(args.names, args.input, not args.no_build))


if __name__ == '__main__':
    main()
