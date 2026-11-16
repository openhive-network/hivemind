#!/usr/bin/env python3
"""Bucket [PHASE-SUMMARY] lines: phase.py <file> <bucket blocks> [first block] [last block]."""

import collections
import re
import sys

f, bucket = sys.argv[1], int(sys.argv[2])
lo = int(sys.argv[3]) if len(sys.argv) > 3 else 0
hi = int(sys.argv[4]) if len(sys.argv) > 4 else 10**10
agg: collections.OrderedDict[int, collections.defaultdict[str, float]] = collections.OrderedDict()
for line in open(f):
    m = re.search(r'blocks=(\d+)-(\d+) total=([\d.]+)s (.*)', line)
    if not m:
        continue
    b = int(m.group(1))
    if b < lo or b > hi:
        continue
    k = (b - 1) // bucket * bucket
    a = agg.setdefault(k, collections.defaultdict(float))
    a['n'] += 1
    a['total'] += float(m.group(3))
    for kv in m.group(4).split():
        name, v = kv.split('=')
        a[name] += float(v)
print('from\tbatches\ttotal/batch\tposts/batch\tvotes/batch\tparallel/batch\tload/batch\tflush/batch')
for k, a in agg.items():
    n = a['n']
    print(
        f"{k}\t{int(n)}\t{a['total'] / n:.3f}\t{a['posts'] / n:.3f}\t{a['votes'] / n:.3f}\t{a['parallel'] / n:.3f}\t{a['load'] / n:.3f}\t{a['flush'] / n:.3f}"
    )
