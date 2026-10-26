"""A stand-in for the herdr CLI in the end-to-end tests, run as `fake_herdr.py <folder> <herdr args>`.

`App.fake_herdr` writes the `herdr` that `VIGNETTE_HERDR` names, which runs this with its own
folder. `<folder>/calls.jsonl` gets one line per call, with its arguments.

It speaks only what Vignette asks of herdr: `pane list` and `tab list` answer with no panes and no
tabs, so herdr's focus marks nothing (`HerdrFocus`), and `tab create` answers a new tab and its
pane (`HerdrLauncher`). `pane run <pane> <command>` stands for the person's shell running
`claude --resume <id>` or `claude --session-id <id>`: unless `<folder>/stays-down` exists, it starts
a process that keeps a plugin inbox for that session under the folder `<folder>/inboxes` names, as
the plugin's monitor would, and records its pid in `<folder>/pids` for the runner to stop.
"""
import json
import os
import shlex
import subprocess
import sys
import time


def main():
    folder, args = sys.argv[1], sys.argv[2:]
    record(folder, {'args': args})
    if args[:2] == ['pane', 'list']:
        answer({'id': 'cli:pane:list', 'result': {'type': 'pane_list', 'panes': []}})
    elif args[:2] == ['tab', 'list']:
        answer({'id': 'cli:tab:list', 'result': {'tabs': []}})
    elif args[:2] == ['tab', 'create']:
        n = len([c for c in calls(folder) if c['args'][:2] == ['tab', 'create']])
        cwd = args[args.index('--cwd') + 1] if '--cwd' in args else os.getcwd()
        with open(os.path.join(folder, f'pane-w1:p{n}.cwd'), 'w') as f:
            f.write(cwd)
        answer({'id': 'cli:tab:create', 'result': {'tab': {'tab_id': f'w1:t{n}'}, 'root_pane': {'pane_id': f'w1:p{n}'}}})
    elif args[:2] == ['pane', 'run']:
        pane, words = args[2], shlex.split(args[3])
        session = next((words[i + 1] for i, w in enumerate(words[:-1]) if w in ('--resume', '--session-id')), None)
        if session and not os.path.exists(os.path.join(folder, 'stays-down')):
            come_up(folder, session, open(os.path.join(folder, f'pane-{pane}.cwd')).read())


def come_up(folder, session, cwd):
    root = open(os.path.join(folder, 'inboxes')).read().strip()
    script = ('mkdir -p "$1/$$" && printf "%s\\n" "$2" > "$1/$$/session" && printf "%s\\n" "$3" > "$1/$$/cwd"'
              ' && echo idle > "$1/$$/turn" && while :; do touch "$1/$$/alive"; sleep 2; done')
    holder = subprocess.Popen(['/bin/sh', '-c', script, 'sh', root, session, cwd], start_new_session=True,
                              stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with open(os.path.join(folder, 'pids'), 'a') as f:
        f.write(f'{holder.pid}\n')


def answer(message):
    print(json.dumps(message))


def calls(folder):
    path = os.path.join(folder, 'calls.jsonl')
    return [json.loads(line) for line in open(path)] if os.path.exists(path) else []


def record(folder, call):
    call = dict(call, pid=os.getpid(), at=round(time.time(), 3))
    with open(os.path.join(folder, 'calls.jsonl'), 'a') as f:
        f.write(json.dumps(call) + '\n')


if __name__ == '__main__':
    main()
