#!/usr/bin/env python3
"""Records Vignette's trailer and cuts it, from the current source.

    trailer.py build                   build the stage copy of the app and the helpers
    trailer.py claude                  set up the trailer's Claude Code, and sign it in once
    trailer.py record [--dry]          perform every beat once, recording the screen
    trailer.py cut [take]              render the trailer from a take (the newest by default)
    trailer.py events [take]           list a take's events, for writing times in beats.toml
    trailer.py all                     build, record and cut
    trailer.py restore                 put back what an interrupted take changed

`beats.toml` holds the wording, the timing, the framing and the marks.
docs/trailer-pipeline-2026-09-26.md says how the pieces fit. Needs Xcode, xcodegen, ffmpeg and
Python 3.11 or later, Google Chrome, Ghostty and Claude Code.
"""
import argparse
import datetime
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import time
import tomllib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, 'out')
sys.path.insert(0, HERE)

import cut      # noqa: E402
import drive    # noqa: E402

PATHS = {
    'app_src': os.path.join(OUT, 'app'),
    'bin': os.path.join(OUT, 'bin'),
    'record_bin': os.path.join(OUT, 'bin', 'record'),
    'stage_bin': os.path.join(OUT, 'bin', 'stage'),
    'cut_bin': os.path.join(OUT, 'bin', 'cut'),
    'game': os.path.join(HERE, 'stage', 'postcard'),
    'stage': os.path.join(OUT, 'stage'),
    'watch': os.path.join(OUT, 'stage', 'watch'),
    'cards': os.path.join(OUT, 'stage', 'cards'),
    'settings': os.path.join(OUT, 'stage', 'settings.json'),
    # Where the take's Claude Code works on a copy of the app, and the path its header shows. The
    # take makes it and removes it after.
    'work': os.path.expanduser('~/Code/postcard'),
    'chrome': os.path.join(OUT, 'stage', 'chrome'),
    'claude': os.path.join(OUT, 'stage', 'claude'),
    'pids': os.path.join(OUT, 'stage', 'pids.json'),
    'dock': os.path.join(OUT, 'stage', 'dock-autohide'),
    'pasteboard': os.path.join(OUT, 'stage', 'pasteboard'),
    'takes': os.path.join(OUT, 'takes'),
    'cut': os.path.join(OUT, 'cut'),
}
HELPERS = {'record': 'record.swift', 'stage': 'stage.swift', 'cut': 'cut.swift'}


def run(args, **kw):
    return subprocess.run(args, check=True, **kw)


def config():
    with open(os.path.join(HERE, 'beats.toml'), 'rb') as f:
        return tomllib.load(f)


# ---- build -------------------------------------------------------------------------------------

def identity(project):
    """The app's name, bundle id and URL scheme, as project.yml gives them."""
    name = re.search(r'^name: *(\S.*)$', project, re.M).group(1).strip()
    bundle = re.search(r'PRODUCT_BUNDLE_IDENTIFIER: *(\S+)', project).group(1)
    scheme = re.search(r'VIGNETTE_URL_SCHEME: *(\S+)', project).group(1)
    return name, bundle, scheme


def replace_once(text, old, new, where):
    count = text.count(old)
    if count != 1:
        sys.exit(f'build: expected one {old!r} in {where}, found {count}; the stage patch needs updating')
    return text.replace(old, new)


def build():
    src = PATHS['app_src']
    os.makedirs(src, exist_ok=True)
    for folder in ['Sources', 'Resources', 'skills', 'agent-plugin', 'Tests']:
        run(['rsync', '-a', '--delete', '--exclude', '__pycache__', f'{REPO}/{folder}/', f'{src}/{folder}/'])
    for file in ['LICENSE', 'project.yml']:
        shutil.copy2(os.path.join(REPO, file), os.path.join(src, file))

    # The stage copy has its own bundle id, name and URL scheme, so it never touches the real app's
    # settings, drawings, log or URLs.
    project_path = os.path.join(src, 'project.yml')
    with open(project_path) as f:
        project = f.read()
    name, bundle, scheme = identity(project)
    stage_name, stage_bundle, stage_scheme = f'{name} Demo', f'{bundle}.demo', f'{scheme}-demo'
    project = project.replace(f'PRODUCT_BUNDLE_IDENTIFIER: {bundle}', f'PRODUCT_BUNDLE_IDENTIFIER: {stage_bundle}')
    project = replace_once(project, f'VIGNETTE_URL_SCHEME: {scheme}', f'VIGNETTE_URL_SCHEME: {stage_scheme}', 'project.yml')
    # A take never checks for updates: a found version would put a dot on the menu bar icon.
    project = replace_once(project, 'SUEnableAutomaticChecks: true', 'SUEnableAutomaticChecks: false', 'project.yml')
    with open(project_path, 'w') as f:
        f.write(project)

    # Send lists the Claude Code sessions running the stage copy's own plugin, which only the
    # trailer's Claude Code has. A take launches the copy with VIGNETTE_SETTINGS, so it runs no
    # codex and no herdr (`AgentTools.forSessions`), whose focus would name one of your panes.
    # The skill in the plugin names the real app's URL scheme and log; the stage copy's must name
    # its own, or the trailer's Claude Code would drive your Vignette.
    path = os.path.join(src, 'skills', 'vignette', 'SKILL.md')
    with open(path) as f:
        text = f.read()
    text = text.replace(f'{scheme}://', f'{stage_scheme}://').replace(f'Logs/{name}.log', f'Logs/{stage_name}.log')
    if f'{scheme}://' in text.replace(f'{stage_scheme}://', ''):
        sys.exit('build: the skill still names the real URL scheme')
    with open(path, 'w') as f:
        f.write(text)

    run(['xcodegen', 'generate'], cwd=src, stdout=subprocess.DEVNULL)
    signing = []
    env_file = os.path.join(REPO, 'scripts', 'signing.env')
    if os.path.exists(env_file):
        values = dict(re.findall(r'^(?:export +)?(\w+)=["\']?([^"\'\n]*)["\']?$', open(env_file).read(), re.M))
        signing = [f"CODE_SIGN_IDENTITY={values.get('CODE_SIGN_IDENTITY', '-')}",
                   f"DEVELOPMENT_TEAM={values.get('DEVELOPMENT_TEAM', '')}"]
    log = os.path.join(OUT, 'build.log')
    print(f'building {stage_name} ({stage_bundle}), log in {log}', flush=True)
    with open(log, 'w') as f:
        result = subprocess.run(['xcodebuild', '-project', f'{name}.xcodeproj', '-scheme', name,
                                 '-configuration', 'Release', '-derivedDataPath', 'build', 'build', '-quiet',
                                 f'PRODUCT_NAME={stage_name}', *signing], cwd=src, stdout=f, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        sys.exit(f'build: xcodebuild failed; see {log}')

    app = stage_app()
    if app['bundle'] != stage_bundle or app['scheme'] != stage_scheme:
        sys.exit(f'build: the stage copy came out as {app}')
    print(f"built {app['path']}", flush=True)

    os.makedirs(PATHS['bin'], exist_ok=True)
    for binary, source in HELPERS.items():
        source = os.path.join(HERE, source)
        target = os.path.join(PATHS['bin'], binary)
        if not os.path.exists(target) or os.path.getmtime(target) < os.path.getmtime(source):
            run(['swiftc', '-O', '-o', target, source])
            print(f'built {target}', flush=True)


def stage_app():
    """The built stage copy: its path, bundle id, URL scheme, name and log."""
    products = os.path.join(PATHS['app_src'], 'build', 'Build', 'Products', 'Release')
    apps = [a for a in os.listdir(products) if a.endswith('.app')] if os.path.isdir(products) else []
    if len(apps) != 1:
        sys.exit('no stage copy; run trailer.py build first')
    path = os.path.join(products, apps[0])
    with open(os.path.join(path, 'Contents', 'Info.plist'), 'rb') as f:
        info = plistlib.load(f)
    name = info['CFBundleName']
    return {'path': path, 'bundle': info['CFBundleIdentifier'], 'name': name,
            'scheme': info['CFBundleURLTypes'][0]['CFBundleURLSchemes'][0],
            'log': os.path.expanduser(f'~/Library/Logs/{name}.log')}


# ---- claude ------------------------------------------------------------------------------------

def claude():
    """The trailer's Claude Code config, signed in once in a terminal. A take installs the stage
    copy's plugin into it (`drive.install_plugin`); this clears what the config held before the
    plugin: the skill on its own, and herdr's hook."""
    home = PATHS['claude']
    os.makedirs(home, exist_ok=True)
    shutil.rmtree(os.path.join(home, 'skills', 'vignette'), ignore_errors=True)
    settings_path = os.path.join(home, 'settings.json')
    if os.path.exists(settings_path):
        with open(settings_path) as f:
            settings = json.load(f)
        if settings.get('hooks', {}).pop('SessionStart', None) is not None:
            if not settings['hooks']:
                del settings['hooks']
            with open(settings_path, 'w') as f:
                json.dump(settings, f, indent=2)
            print("removed herdr's hook from the trailer's config")
    shutil.rmtree(os.path.join(home, 'hooks'), ignore_errors=True)

    env = dict(os.environ, CLAUDE_CONFIG_DIR=home)
    status = subprocess.run(['claude', 'auth', 'status'], capture_output=True, text=True, env=env).stdout
    if json.loads(status or '{}').get('loggedIn'):
        print("the trailer's Claude Code is signed in")
        return
    # The first run asks for a theme and a sign-in. A take marks its own folder trusted.
    home_folder = os.path.join(PATHS['stage'], 'sign-in')
    os.makedirs(home_folder, exist_ok=True)
    script = os.path.join(PATHS['stage'], 'sign-in.sh')
    with open(script, 'w') as f:
        f.write(f"""#!/bin/zsh
unset -m 'HERDR_*' 'CLAUDE*'
export CLAUDE_CONFIG_DIR={json.dumps(home)}
cd {json.dumps(home_folder)}
echo "Sign in the trailer's Claude Code, then type /exit."
exec claude
""")
    os.chmod(script, 0o755)
    run(['open', '-na', 'Ghostty', '--args', f'--command={script}', '--window-save-state=never',
         '--quit-after-last-window-closed=true'])
    print('a terminal is open for the sign-in; waiting for it')
    while True:
        time.sleep(2)
        status = subprocess.run(['claude', 'auth', 'status'], capture_output=True, text=True, env=env).stdout
        if json.loads(status or '{}').get('loggedIn'):
            print("the trailer's Claude Code is signed in; close its terminal when you are done")
            return


# ---- record ------------------------------------------------------------------------------------

def record(dry=False):
    for binary in HELPERS:
        if not os.path.exists(os.path.join(PATHS['bin'], binary)):
            sys.exit('no helpers; run trailer.py build first')
    app = stage_app()
    take = os.path.join(PATHS['takes'], datetime.datetime.now().strftime('%Y-%m-%d-%H%M%S') + ('-dry' if dry else ''))
    os.makedirs(take)
    paths = dict(PATHS, movie=os.path.join(take, 'screen.mov'))
    stage = drive.Stage(config(), paths, app)
    log_start = stage.log_size()
    failure = None
    try:
        drive.perform(stage, record=not dry)
    except drive.TakeFailed as e:
        failure = str(e)
    finally:
        with open(os.path.join(take, 'events.json'), 'w') as f:
            json.dump({'game': stage.game, 'bounds': stage.bounds, 'capture': getattr(stage, 'capture', None),
                       'scale': stage.scale, 'failed': failure, 'events': stage.events}, f, indent=1)
        with open(app['log'], 'rb') as f:
            f.seek(log_start)
            with open(os.path.join(take, 'app.log'), 'wb') as out:
                out.write(f.read())
    if failure:
        sys.exit(f'take failed: {failure}\n  {take}')
    print(f'take {take}')
    return take


def restore():
    """Puts back what a take changes on this Mac, and stops what it started, if a take was
    interrupted."""
    drive.clear_leftovers(PATHS, config())
    drive.remove_work(PATHS)
    if os.path.exists(PATHS['dock']):
        if open(PATHS['dock']).read().strip() == 'false':
            drive.dock_autohide(False)
            print('the Dock shows again')
        os.remove(PATHS['dock'])
    if os.path.exists(os.path.join(PATHS['pasteboard'], 'manifest.json')):
        run([PATHS['stage_bin'], 'pasteboard', 'restore', PATHS['pasteboard']])
    app = stage_app()
    for pid in drive.running_pids(os.path.join(app['path'], 'Contents', 'MacOS')):
        drive.stop_pid(pid)
        print(f'stopped the stage copy, pid {pid}')


def newest_take(name=None):
    if name:
        return name if os.path.isdir(name) else os.path.join(PATHS['takes'], name)
    takes = sorted(t for t in os.listdir(PATHS['takes']) if not t.endswith('-dry')) if os.path.isdir(PATHS['takes']) else []
    if not takes:
        sys.exit('no take; run trailer.py record first')
    return os.path.join(PATHS['takes'], takes[-1])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('build')
    sub.add_parser('claude')
    r = sub.add_parser('record')
    r.add_argument('--dry', action='store_true', help='perform the beats without recording')
    c = sub.add_parser('cut')
    c.add_argument('take', nargs='?')
    e = sub.add_parser('events')
    e.add_argument('take', nargs='?')
    sub.add_parser('all')
    sub.add_parser('restore')
    args = parser.parse_args()

    if args.command == 'build':
        build()
    elif args.command == 'claude':
        claude()
    elif args.command == 'record':
        record(args.dry)
    elif args.command == 'cut':
        cut.cut(config(), newest_take(args.take), PATHS)
    elif args.command == 'events':
        cut.list_events(newest_take(args.take))
    elif args.command == 'all':
        build()
        cut.cut(config(), record(), PATHS)
    elif args.command == 'restore':
        restore()


if __name__ == '__main__':
    main()
