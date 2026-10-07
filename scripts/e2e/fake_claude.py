"""A stand-in for the claude CLI that answers live ink, run as `fake_claude.py <folder> <claude args>`.

A test launch runs only the claude that `VIGNETTE_CLAUDE` names (`LiveResponder`), which runs this
with its own folder. It speaks what `LiveResponder` reads of `claude -p --input-format stream-json
--output-format stream-json --include-partial-messages --json-schema`, as claude 2.1.289 writes it:
an `init` line before its first answer, the answer's JSON in `input_json_delta` pieces of a
`StructuredOutput` call, and a `result` line carrying it as `structured_output`.

`<folder>/calls.jsonl` gets one line for the arguments and one per message, with its text and the
size of each image, never the image. `<folder>/answer.json` is the answer it gives, or else it
circles the first text line the message names. `<folder>/tools` holds tool names its `init` line
lists, one a line, to stand in for a CLI that ignores `--tools ""`.
"""
import json
import os
import re
import sys
import time


def main():
    folder, args = sys.argv[1], sys.argv[2:]
    record(folder, {'args': args})
    started = False
    for line in sys.stdin:
        message = json.loads(line)
        if message.get('type') != 'user':
            continue
        content = message['message']['content']
        text = ' '.join(block.get('text', '') for block in content if block.get('type') == 'text')
        images = [len(block['source']['data']) for block in content if block.get('type') == 'image']
        record(folder, {'text': text, 'images': images})
        if not started:
            started = True
            emit({'type': 'system', 'subtype': 'init', 'tools': ['StructuredOutput'] + tools(folder), 'mcp_servers': []})
        answer = {'say': 'Ready.', 'marks': []} if 'starting you up' in text else reply(folder, text)
        encoded = json.dumps(answer)
        for start in range(0, len(encoded), 12):
            emit({'type': 'stream_event', 'event': {'type': 'content_block_delta', 'index': 0,
                  'delta': {'type': 'input_json_delta', 'partial_json': encoded[start:start + 12]}}})
            time.sleep(0.02)
        emit({'type': 'result', 'subtype': 'success', 'is_error': False, 'duration_ms': 300,
              'total_cost_usd': 0, 'result': encoded, 'structured_output': answer})


def reply(folder, text):
    path = os.path.join(folder, 'answer.json')
    if os.path.exists(path):
        return json.load(open(path))
    # The window's text lines each start with their id: `t2 12 34 640 14 words`.
    lines = re.findall(r'(?m)^(t\d+) ', text)
    marks = [{'kind': 'circle', 'line': lines[0], 'label': 'This one'}] if lines else []
    return {'say': f'The fake responder read {len(lines)} lines.', 'marks': marks}


def tools(folder):
    path = os.path.join(folder, 'tools')
    return open(path).read().split() if os.path.exists(path) else []


def emit(line):
    sys.stdout.write(json.dumps(line) + '\n')
    sys.stdout.flush()


def record(folder, call):
    with open(os.path.join(folder, 'calls.jsonl'), 'a') as f:
        f.write(json.dumps(call) + '\n')


if __name__ == '__main__':
    main()
