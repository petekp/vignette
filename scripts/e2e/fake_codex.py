"""A stand-in for the codex CLI in the end-to-end tests, run as `fake_codex.py <folder> <codex args>`.

`App.fake_codex` writes the `codex` that `VIGNETTE_CODEX` names, which runs this with its own
folder. `<folder>/threads.json` holds the threads it lists. `<folder>/calls.jsonl` gets one line per
call, with its arguments, and one per request `app-server` answers, written before the answer:
Vignette ends the server once it has its answers, so nothing after the last one is sure to run.
Each line carries its process and the time it was written, and an exception is a line of its own,
since Vignette drops codex's standard error.

It speaks only what Vignette asks of codex: `app-server` answers `initialize`, `thread/list` and
`thread/read` (`AppServer.swift`), and `queue --thread <id> --message <line>` succeeds, as the real
one does once the thread's engine has the line (`CodexConnection.submit`). A thread whose id is a
line of `<folder>/gone` was deleted: queueing to it fails with the real CLI's words. Anything else
succeeds and does nothing.

Each thread's rollout is `<folder>/rollouts/rollout-<id>.jsonl`, which `thread/read` names as its
`path`. A queued line becomes a turn there, as the real engine writes one (`CodexRollout.swift`):
`task_started`, the line as a user message, and `task_complete` once the number of seconds in
`<folder>/turn-seconds` has passed, 1 without it.

It also answers as live ink's responder (`CodexDriver`): `debug models` prints a catalog, and
`app-server` reads the account, lists two models, and runs turns. The account is signed in while
`auth.json` is in the `CODEX_HOME` Vignette gives it. A turn on a thread whose provider is the
isolation check's posts that provider the request the real codex sends, with `<folder>/tools` adding
a tool to it. Any other turn answers `<folder>/answer.json`, or "A fake answer.".

And as Vignette's sign-in to Codex (`CodexLogin`): `account/login/start` with type `chatgpt` answers
a page, then with `<folder>/login-completes` writes a fake `auth.json` into `CODEX_HOME` and
reports the login completed. With `<folder>/login-port-busy` it answers the real codex's error for
taken ports.
"""
import json
import os
import re
import shlex
import subprocess
import sys
import time
import traceback
import urllib.request


def main():
    folder, args = sys.argv[1], sys.argv[2:]
    record(folder, {'args': args})
    if args[:2] == ['debug', 'models']:
        print(json.dumps({'models': [{'slug': 'gpt-6-astra'}, {'slug': 'gpt-5.5'}]}))
    elif args[:1] == ['app-server']:
        serve(folder, args)
    elif args[:2] == ['queue', '--thread'] and args[2] in gone(folder):
        # What codex queue 0.159.2 prints for a thread id no thread has.
        print('Error: failed to queue session message: thread/queue/add failed: failed to read thread: '
              f'invalid thread-store request: no rollout found for thread id {args[2]} (code -32603)', file=sys.stderr)
        sys.exit(1)
    elif args[:2] == ['queue', '--thread'] and '--message' in args:
        take_turn(folder, args[2], args[args.index('--message') + 1])


def rollout(folder, thread):
    return os.path.join(folder, 'rollouts', f'rollout-{thread}.jsonl')


def take_turn(folder, thread, line):
    """Writes the turn that takes `line` into the thread's rollout, and ends it from a process of its
    own once `<folder>/turn-seconds` have passed, after this one has answered."""
    path = rollout(folder, thread)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    turn = f'turn-{time.time_ns()}'
    entries = [{'type': 'event_msg', 'payload': {'type': 'task_started', 'turn_id': turn}},
               {'type': 'response_item', 'payload': {'type': 'message', 'role': 'user',
                                                     'content': [{'type': 'input_text', 'text': line}]}}]
    with open(path, 'a') as f:
        f.write(''.join(json.dumps(e) + '\n' for e in entries))
    seconds = open(os.path.join(folder, 'turn-seconds')).read().strip() if os.path.exists(os.path.join(folder, 'turn-seconds')) else '1'
    end = json.dumps({'type': 'event_msg', 'payload': {'type': 'task_complete', 'turn_id': turn, 'last_agent_message': 'Done.'}})
    subprocess.Popen(['/bin/sh', '-c', f'sleep {shlex.quote(seconds)}; printf "%s\\n" {shlex.quote(end)} >> {shlex.quote(path)}'],
                     start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    record(folder, {'turn': turn, 'thread': thread, 'endsAfter': seconds})


def gone(folder):
    path = os.path.join(folder, 'gone')
    return open(path).read().split() if os.path.exists(path) else []


def record(folder, call):
    call = dict(call, pid=os.getpid(), at=round(time.time(), 3))
    with open(os.path.join(folder, 'calls.jsonl'), 'a') as f:
        f.write(json.dumps(call) + '\n')


def serve(folder, args):
    """Answers each request on standard input, one JSON line each, until the app closes it."""
    path = os.path.join(folder, 'threads.json')
    threads = json.load(open(path)) if os.path.exists(path) else []
    provider = check_provider(args)
    started = {}
    home = os.environ.get('CODEX_HOME', '')
    for line in sys.stdin:
        message = json.loads(line)
        if 'id' not in message or 'method' not in message:
            continue
        method, params = message.get('method'), message.get('params') or {}
        record(folder, {'args': args, 'answered': method})
        if method == 'thread/list':
            answer = {'id': message['id'], 'result': {'data': threads, 'nextCursor': None}}
        elif method == 'thread/read':
            found = next((t for t in threads if t['id'] == params.get('threadId')), None)
            answer = ({'id': message['id'], 'result': {'thread': dict(found, path=rollout(folder, found['id']))}} if found else
                      {'id': message['id'], 'error': {'code': -32603, 'message': f"no rollout found for thread id {params.get('threadId')}"}})
        elif method == 'initialize':
            answer = {'id': message['id'], 'result': {'userAgent': 'fake-codex'}}
        elif method == 'account/read':
            signed_in = os.path.exists(os.path.join(home, 'auth.json'))
            answer = {'id': message['id'], 'result': {'account': {'type': 'chatgpt', 'email': 'e2e@example.invalid'} if signed_in else None,
                                                      'requiresOpenaiAuth': True}}
        elif method == 'account/login/start':
            record(folder, {'login': params.get('type')})
            if os.path.exists(os.path.join(folder, 'login-port-busy')):
                answer = {'id': message['id'], 'error': {'code': -32603, 'message': 'failed to start login server: Port 127.0.0.1:1457 is already in use'}}
            else:
                print(json.dumps({'id': message['id'], 'result': {'type': 'chatgpt', 'loginId': 'login-1',
                                  'authUrl': 'https://auth.openai.com/oauth/authorize?redirect_uri=http%3A%2F%2F127.0.0.1%3A1455%2Fauth%2Fcallback'}}), flush=True)
                if os.path.exists(os.path.join(folder, 'login-completes')):
                    with open(os.path.join(home, 'auth.json'), 'w') as f:
                        json.dump({'auth_mode': 'chatgpt', 'tokens': {'access_token': 'fake', 'refresh_token': 'fake', 'id_token': 'fake', 'account_id': 'fake'}}, f)
                    emit('account/login/completed', {'loginId': 'login-1', 'success': True, 'error': None})
                continue
        elif method == 'model/list':
            answer = {'id': message['id'], 'result': {'data': [{'model': 'gpt-6-astra', 'isDefault': False},
                                                               {'model': 'gpt-5.5', 'isDefault': True}]}}
        elif method == 'thread/start':
            thread = f'thread-{len(started) + 1}'
            started[thread] = params
            record(folder, {'thread': thread, 'provider': params.get('modelProvider'), 'model': params.get('model')})
            answer = {'id': message['id'], 'result': {'thread': {'id': thread}}}
        elif method == 'turn/start':
            print(json.dumps({'id': message['id'], 'result': {}}), flush=True)
            turn = {'thread': params['threadId'], 'id': f'turn-{message["id"]}', 'input': params.get('input') or []}
            emit('turn/started', {'threadId': turn['thread'], 'turn': {'id': turn['id']}})
            asks = any(part.get('type') == 'image' for part in turn['input'])
            if started.get(turn['thread'], {}).get('modelProvider') == 'vignette_check':
                post_check(folder, provider, started[turn['thread']], turn)
                complete(turn, '{"say":"Ready.","marks":[],"steps":null,"actions":null}')
            else:
                complete(turn, answer_text(folder, asks))
            continue
        else:
            answer = {'id': message['id'], 'error': {'code': -32601, 'message': 'not in the fake'}}
        print(json.dumps(answer), flush=True)


def check_provider(args):
    """The isolation check's base URL, from its `-c model_providers.vignette_check=…`."""
    for arg in args:
        if arg.startswith('model_providers.vignette_check='):
            found = re.search(r'base_url="([^"]+)"', arg)
            return found.group(1) if found else None
    return None


def post_check(folder, provider, thread, turn):
    """Posts the check's provider what the real codex sends: the base instructions as a developer
    message, the turn's text as the user's, and no tools."""
    text = ''.join(part.get('text', '') for part in turn['input'] if part.get('type') == 'text')
    tools = [{'type': 'function', 'name': 'exec_command'}] if os.path.exists(os.path.join(folder, 'tools')) else []
    body = {'model': thread.get('model'), 'stream': True, 'tools': tools, 'input': [
        {'type': 'message', 'role': 'developer', 'content': [{'type': 'input_text', 'text': thread.get('baseInstructions', '')}]},
        {'type': 'message', 'role': 'user', 'content': [{'type': 'input_text', 'text': text}]}]}
    request = urllib.request.Request(provider + '/responses', data=json.dumps(body).encode(), method='POST',
                                     headers={'content-type': 'application/json'})
    with urllib.request.urlopen(request, timeout=10) as answer:
        record(folder, {'checkPosted': answer.status, 'tools': len(tools)})
        answer.read()


def answer_text(folder, asks):
    path = os.path.join(folder, 'answer.json')
    if asks and os.path.exists(path):
        return open(path).read().strip()
    return json.dumps({'say': 'A fake answer.' if asks else 'Ready.', 'marks': [], 'steps': None, 'actions': None})


def complete(turn, text):
    emit('item/agentMessage/delta', {'threadId': turn['thread'], 'delta': text})
    emit('turn/completed', {'threadId': turn['thread'], 'turn': {
        'id': turn['id'], 'status': 'completed', 'durationMs': 5, 'items': [{'type': 'agentMessage', 'text': text}]}})


def emit(method, params):
    print(json.dumps({'method': method, 'params': params}), flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        record(sys.argv[1], {'args': sys.argv[2:], 'error': traceback.format_exc()})
        raise
