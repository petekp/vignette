#!/usr/bin/env python3
"""Core Animation commits from an Instruments trace recorded with the Core Animation Commits
instrument (AGENTS.md, "Measuring a stutter"). Standard library only.

usage: commits.py <trace> [--bin 0.25] [--at T ...] [--window 1.0]
  With no --at, prints every quarter second that had work: how many commits, their total and
  longest, and how many took over 8.3 ms, which drops a frame at 120 Hz.
  With --at, prints one line per time (seconds of trace time), over the window after it.
"""
import argparse, collections, statistics, subprocess, sys, xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('trace')
parser.add_argument('--bin', type=float, default=0.25)
parser.add_argument('--at', type=float, nargs='*', default=[])
parser.add_argument('--window', type=float, default=1.0)
args = parser.parse_args()

xml = subprocess.run(['xcrun', 'xctrace', 'export', '--input', args.trace, '--xpath',
                      '/trace-toc/run[@number="1"]/data/table[@schema="coreanimation-commit-interval"]'],
                     capture_output=True, text=True, check=True).stdout
root = ET.fromstring(xml)
# The export writes a repeated value once, with an id, and refers to it after that.
ids = {el.attrib['id']: el for el in root.iter() if 'id' in el.attrib}
def value(el):
    if el is not None and 'ref' in el.attrib: el = ids[el.attrib['ref']]
    return None if el is None or el.text is None else int(el.text)
commits = []
for row in root.iter('row'):
    start, duration = value(row.find('start-time')), value(row.find('duration'))
    if start is not None and duration is not None: commits.append((start / 1e9, duration / 1e6))
if not commits: sys.exit('no commits: was the trace recorded with --instrument "Core Animation Commits"?')
print(f'{len(commits)} commits over {commits[-1][0]:.1f} s')

def line(label, durations):
    over = sum(d > 8.3 for d in durations)
    return (f'{label}  commits={len(durations):4}  total={sum(durations):7.1f} ms  median={statistics.median(durations):5.2f} ms'
            f'  longest={max(durations):5.1f} ms  over 8.3 ms={over}')

if args.at:
    for t in args.at:
        durations = [d for s, d in commits if t <= s <= t + args.window]
        print(line(f'{t:7.2f} s', durations) if durations else f'{t:7.2f} s  no commits')
else:
    bins = collections.defaultdict(list)
    for s, d in commits: bins[int(s / args.bin)].append(d)
    for k in sorted(bins):
        durations = bins[k]
        if len(durations) > 5 or max(durations) > 3: print(line(f'{k * args.bin:7.2f} s', durations))
