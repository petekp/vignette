#!/bin/sh
# run-vis.sh <pid> <overlay flags...>: four scrolls, slow and fast, then stats
cd "$(dirname "$0")"
pid=$1; shift
(tail -n0 -f o.in | ./overlay $pid mask rec "$@" > o.out 2>&1 &)
sleep 2.5
echo "smooth 200 0.8" >> t.in; sleep 1.3
echo "smooth -200 0.8" >> t.in; sleep 1.3
echo "smooth 600 0.5" >> t.in; sleep 1
echo "smooth -600 0.5" >> t.in; sleep 1
echo stats >> o.in; sleep 0.3; echo quit >> o.in
grep -v "^frame" o.out; python3 lagy.py o.out 2
