"""Send's end-to-end scenarios for a send Codex holds in a thread's queue, with the fake codex's
held queue (`fake_codex.py`: `<folder>/hold` and `<folder>/release`)."""
import os
import time

from e2e import Failed
from scenarios import KEY_RETURN, capture_sent_card, click_to_open, draw_box, field_has_keys, needs_input, start


@needs_input
def send_codex_held(app):
    """A send Codex holds behind a running turn is watched in its queue: it is reported as queued,
    with the turn as the reason. Don't send takes one line out of the queue, and the thread's
    turn ending lets Codex take the other, which turns that send to sent."""
    thread, env = app.fake_codex('e2e-codex-project')
    open(os.path.join(app.folder, 'codex', 'hold'), 'w').close()
    start(app, **env)
    for step in ('withdraw', 'release'):
        path = app.image(f'Screenshot held {step}.png', folder=app.watch)
        time.sleep(1)
        click_to_open(app, path)
        draw_box(app, field_has_keys(app, thread))
        offset = app.log_size()
        app.keys('annotator', 'key', KEY_RETURN, 'cmd')
        line = app.wait_log('[send] queued', offset, timeout=20)
        if 'turn-running' not in line:
            raise Failed(f'the send was not reported as held behind a running turn: {line}')
        app.report.step(f'{step}: the send is queued behind the running turn', detail=line.strip()[:160])
        if step == 'withdraw':
            app.command('unsend', app.file_query(path))
            line = app.wait_log('[send] withdrawn', offset, timeout=10)
            if not any(c.get('answered') == 'thread/queue/delete' for c in app.codex_calls('app-server')):
                raise Failed(f'Don\'t send never asked codex to delete the line: {app.codex_calls("app-server")}')
            app.report.step('Don\'t send took the line out of the queue', detail=line.strip()[:160])
            capture_sent_card(app, path, 'withdrawn-card')
        else:
            open(os.path.join(app.folder, 'codex', 'release'), 'w').close()
            line = app.wait_log('[send] taken', offset, timeout=20)
            app.report.step('the turn ended and Codex took the line', detail=line.strip()[:160])
            capture_sent_card(app, path, 'taken-card')


ALL = [send_codex_held]
