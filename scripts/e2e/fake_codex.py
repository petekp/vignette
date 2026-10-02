"""A stand-in for the codex CLI in the end-to-end tests, run as `fake_codex.py <folder> <codex args>`.

`App.fake_codex` writes the `codex` that `VIGNETTE_CODEX` names, which runs this with its own
folder. `<folder>/threads.json` holds the threads it lists. `<folder>/calls.jsonl` gets one line per
call, with its arguments, and one per request `app-server` answers, written before the answer:
Vignette ends the server once it has its answers, so nothing after the last one is sure to run.

It speaks only what Vignette asks of codex: `app-server` answers `initialize` and `thread/list`
(`AppServer.swift`), and `queue --thread <id> --message <line>` succeeds, as the real one does once
the thread's engine has the line (`CodexConnection.submit`). A thread whose id is a line of
`<folder>/gone` was deleted: queueing to it fails with the real CLI's words. Anything else succeeds
and does nothing.
"""
import json
import os
import sys


def main():
    folder, args = sys.argv[1], sys.argv[2:]
    record(folder, {'args': args})
    if args[:1] == ['app-server']:
        serve(folder, args)
    elif args[:2] == ['queue', '--thread'] and args[2] in gone(folder):
        # What codex queue 0.159.2 prints for a thread id no thread has.
        print('Error: failed to queue session message: thread/queue/add failed: failed to read thread: '
              f'invalid thread-store request: no rollout found for thread id {args[2]} (code -32603)', file=sys.stderr)
        sys.exit(1)


def gone(folder):
    path = os.path.join(folder, 'gone')
    return open(path).read().split() if os.path.exists(path) else []


def record(folder, call):
    with open(os.path.join(folder, 'calls.jsonl'), 'a') as f:
        f.write(json.dumps(call) + '\n')


def serve(folder, args):
    """Answers each request on standard input, one JSON line each, until the app closes it."""
    with open(os.path.join(folder, 'threads.json')) as f:
        threads = json.load(f)
    for line in sys.stdin:
        message = json.loads(line)
        if 'id' not in message:
            continue
        record(folder, {'args': args, 'answered': message.get('method')})
        if message.get('method') == 'thread/list':
            answer = {'id': message['id'], 'result': {'data': threads, 'nextCursor': None}}
        elif message.get('method') == 'initialize':
            answer = {'id': message['id'], 'result': {'userAgent': 'fake-codex'}}
        else:
            answer = {'id': message['id'], 'error': {'code': -32601, 'message': 'not in the fake'}}
        print(json.dumps(answer), flush=True)


if __name__ == '__main__':
    main()
