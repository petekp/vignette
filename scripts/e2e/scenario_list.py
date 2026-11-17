"""Every end-to-end scenario, in the order `e2e.py run` runs them. The modules import `e2e`, so
they are imported when the list is asked for."""


def all_scenarios():
    import codex_queue
    import live_ink
    import scenarios
    import session_starts
    return scenarios.ALL + codex_queue.ALL + session_starts.ALL + live_ink.ALL
