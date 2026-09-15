# Low-level input for testing: python3 scripts/input.py key <keycode> [cmd] [shift] [opt] | move X Y | click X Y | drag X1 Y1 X2 Y2
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
a = sys.argv[1:]
if a[0] == 'key': key(int(a[1]), a[2:])
elif a[0] == 'move': move(float(a[1]), float(a[2]))
elif a[0] == 'drag': drag(*map(float, a[1:5]))
elif a[0] == 'click': click(float(a[1]), float(a[2]))
