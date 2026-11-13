"""A stand-in for Herdr's two tools in the end-to-end tests, run as `fake_herdr.py <folder> <tool> <args>`,
where `<tool>` is `herdr-app` or `hc`.

`install` writes the `herdr-app` and `hc` that `VIGNETTE_HERDR_APP` and `VIGNETTE_HC` name,
which run this with its folder. `<folder>/calls.jsonl` gets one line per call, with the tool and
its arguments.

It speaks only what Vignette asks, as the real tools print it. `herdr-app status` answers a window on one space and one tab, and
`herdr-app ls` that tab with no terminals, and `hc connect` answers `terminal.list` with no
terminals, so Herdr's focus marks nothing (`HerdrFocus`). `herdr-app do tab.rename` succeeds.
`hc run … -- <shell> -lic <line> <shell> claude --resume|--session-id <id>` stands for herdr-core
running `claude` in a new terminal (`HerdrLauncher`): unless `<folder>/stays-down` exists, it starts a
process that keeps a plugin inbox for that session under the folder `<folder>/inboxes` names, as the
plugin's monitor would, and records its pid in `<folder>/pids` for the runner to stop.
"""
import json
import os
import subprocess
import sys
import time

SPACE = 'sp' + 'e2e0' * 8
TAB = 'tb' + 'e2e1' * 8


def main():
    folder, tool, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    record(folder, {'args': [tool] + args})
    if tool == 'herdr-app' and args == ['status']:
        answer({'space': SPACE, 'tab': TAB, 'focused_pane': 'p' + 'e2e2' * 8, 'agent': None, 'errors': []}, indent=2)
    elif tool == 'herdr-app' and args == ['ls']:
        answer({'spaces': [{'id': SPACE, 'name': 'e2e', 'active': True,
                            'tabs': [{'id': TAB, 'name': 'e2e', 'active': True, 'terminals': []}]}], 'recent': []}, indent=2)
    elif tool == 'herdr-app' and args[:2] == ['do', 'tab.rename']:
        answer({'ok': True})
    elif tool == 'hc' and args == ['connect']:
        for line in sys.stdin:
            request = json.loads(line)
            if 'id' in request:
                answer({'id': request['id'], 'jsonrpc': '2.0', 'result': {'hidden_finished': 0, 'machines': [], 'terminals': []}})
    elif tool == 'hc' and args[:1] == ['run']:
        n = len([c for c in calls(folder) if c['args'][:2] == ['hc', 'run']])
        program = args[args.index('--') + 1:]
        session = next((program[i + 1] for i, w in enumerate(program[:-1]) if w in ('--resume', '--session-id')), None)
        cwd = args[args.index('--cwd') + 1] if '--cwd' in args else os.getcwd()
        if session and not os.path.exists(os.path.join(folder, 'stays-down')):
            come_up(folder, session, cwd)
        answer({'address': f't{n}', 'argv': program, 'cwd': cwd})
    else:
        print(f'fake_herdr: {tool} {" ".join(args)} is not faked', file=sys.stderr)
        sys.exit(2)


def install(folder, inboxes):
    """Writes the two tools into `folder`, with `inboxes` as the plugin's inbox root. Returns the env
    that points a launch at them."""
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, 'inboxes'), 'w') as f:
        f.write(inboxes)
    tools = {}
    for tool, variable in [('herdr-app', 'VIGNETTE_HERDR_APP'), ('hc', 'VIGNETTE_HC')]:
        path = os.path.join(folder, tool)
        # This Python, by path: the app runs tools with launchd's PATH, where python3 can be Apple's stub.
        with open(path, 'w') as f:
            f.write(f"#!/bin/sh\nexec '{sys.executable}' '{os.path.abspath(__file__)}' '{folder}' {tool} \"$@\"\n")
        os.chmod(path, 0o755)
        tools[variable] = path
    return tools


def come_up(folder, session, cwd):
    root = open(os.path.join(folder, 'inboxes')).read().strip()
    script = ('mkdir -p "$1/$$" && printf "%s\\n" "$2" > "$1/$$/session" && printf "%s\\n" "$3" > "$1/$$/cwd"'
              ' && echo idle > "$1/$$/turn" && while :; do touch "$1/$$/alive"; sleep 2; done')
    holder = subprocess.Popen(['/bin/sh', '-c', script, 'sh', root, session, cwd], start_new_session=True,
                              stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with open(os.path.join(folder, 'pids'), 'a') as f:
        f.write(f'{holder.pid}\n')


def answer(message, indent=None):
    print(json.dumps(message, indent=indent), flush=True)


def calls(folder):
    path = os.path.join(folder, 'calls.jsonl')
    return [json.loads(line) for line in open(path)] if os.path.exists(path) else []


def record(folder, call):
    call = dict(call, pid=os.getpid(), at=round(time.time(), 3))
    with open(os.path.join(folder, 'calls.jsonl'), 'a') as f:
        f.write(json.dumps(call) + '\n')


if __name__ == '__main__':
    main()
