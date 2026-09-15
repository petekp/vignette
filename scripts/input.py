# Low-level input for testing: python3 scripts/input.py key <keycode> [cmd] [shift] [opt] | move X Y | click X Y | drag X1 Y1 X2 Y2 | scroll DY [steps] | tap <modifier keycode> [count]
# Coordinates are screen points, top-left origin. Needs: pip install pyobjc-framework-Quartz
# System Events keystrokes do not trigger Carbon hotkeys and only reach the frontmost app; CGEvent does both.
import sys, time
import Quartz as Q
def post(e): Q.CGEventPost(Q.kCGHIDEventTap, e)
def key(code, mods):
    flags = 0
    if 'cmd' in mods: flags |= Q.kCGEventFlagMaskCommand
    if 'shift' in mods: flags |= Q.kCGEventFlagMaskShift
    if 'opt' in mods: flags |= Q.kCGEventFlagMaskAlternate
    for down in (True, False):
        e = Q.CGEventCreateKeyboardEvent(None, code, down); Q.CGEventSetFlags(e, flags); post(e); time.sleep(0.03)
def move(x, y):
    post(Q.CGEventCreateMouseEvent(None, Q.kCGEventMouseMoved, (x, y), 0))
def drag(x1, y1, x2, y2, steps=12):
    move(x1, y1); time.sleep(0.15)
    post(Q.CGEventCreateMouseEvent(None, Q.kCGEventLeftMouseDown, (x1, y1), 0)); time.sleep(0.1)
    for i in range(1, steps + 1):
        x = x1 + (x2 - x1) * i / steps; y = y1 + (y2 - y1) * i / steps
        post(Q.CGEventCreateMouseEvent(None, Q.kCGEventLeftMouseDragged, (x, y), 0)); time.sleep(0.03)
    post(Q.CGEventCreateMouseEvent(None, Q.kCGEventLeftMouseUp, (x2, y2), 0))
def click(x, y):
    move(x, y); time.sleep(0.1)
    post(Q.CGEventCreateMouseEvent(None, Q.kCGEventLeftMouseDown, (x, y), 0)); time.sleep(0.05)
    post(Q.CGEventCreateMouseEvent(None, Q.kCGEventLeftMouseUp, (x, y), 0))
def scroll(dy, steps=10):
    # Trackpad-style precise deltas; positive dy pulls content down (reveals what is above).
    for _ in range(int(steps)):
        e = Q.CGEventCreateScrollWheelEvent(None, Q.kCGScrollEventUnitPixel, 1, int(dy / steps)); post(e); time.sleep(0.016)
def tap(code, count=2):
    # A modifier key pressed and released; the down event carries the modifier's flag like a real press.
    flag = {56: Q.kCGEventFlagMaskShift, 60: Q.kCGEventFlagMaskShift, 54: Q.kCGEventFlagMaskCommand, 55: Q.kCGEventFlagMaskCommand,
            58: Q.kCGEventFlagMaskAlternate, 61: Q.kCGEventFlagMaskAlternate, 59: Q.kCGEventFlagMaskControl, 62: Q.kCGEventFlagMaskControl}[code]
    for _ in range(int(count)):
        e = Q.CGEventCreateKeyboardEvent(None, code, True); Q.CGEventSetFlags(e, flag); post(e); time.sleep(0.05)
        e = Q.CGEventCreateKeyboardEvent(None, code, False); Q.CGEventSetFlags(e, 0); post(e); time.sleep(0.12)
a = sys.argv[1:]
if a[0] == 'key': key(int(a[1]), a[2:])
elif a[0] == 'move': move(float(a[1]), float(a[2]))
elif a[0] == 'drag': drag(*map(float, a[1:5]))
elif a[0] == 'click': click(float(a[1]), float(a[2]))
elif a[0] == 'scroll': scroll(float(a[1]), *map(int, a[2:3]))
elif a[0] == 'tap': tap(int(a[1]), *map(int, a[2:3]))
