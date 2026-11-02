"""The end-to-end run's report: each scenario's steps, captures and log, as report.json and report.html."""
import html
import json
import os


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
