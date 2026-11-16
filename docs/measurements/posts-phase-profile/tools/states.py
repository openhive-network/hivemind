#!/usr/bin/env python3
"""Split [PHASE-SUMMARY] batches by posts time around a threshold: states.py <file> <threshold s>."""

import re
import sys

f, thr = sys.argv[1], float(sys.argv[2])
good: list[float] = []
bad: list[float] = []
runs, prev = 0, None
for line in open(f):
    m = re.search(r'blocks=(\d+)-\d+ total=([\d.]+)s .*posts=([\d.]+)', line)
    if not m:
        continue
    p = float(m.group(3))
    s = p >= thr
    (bad if s else good).append(p)
    if s and prev is False:
        runs += 1
    prev = s
n = len(good) + len(bad)
print(
    f"batches={n} good={len(good)} mean={sum(good) / max(len(good), 1):.3f}s bad={len(bad)} mean={sum(bad) / max(len(bad), 1):.3f}s bad_stretches={runs}"
)
print(
    f"posts total={sum(good) + sum(bad):.0f}s; if every batch ran at the good mean: {n * sum(good) / max(len(good), 1):.0f}s"
)
