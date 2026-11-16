#!/usr/bin/env python3
"""Cut the auto_explain entries of chosen batches' posts phase out of a jsonlog file.

usage: ae_excerpt.py <postgresql.json> <first block of the run> <batch first block> [...] > out.jsonl
The k-th top-level process_posts_from_staging entry is batch k; every entry of the same
backend logged since the previous one is a statement nested in it.
"""

import json
import sys

src, first = sys.argv[1], int(sys.argv[2])
want = {(int(b) - first) // 1000 for b in sys.argv[3:]}
pending, k, posts_pid = [], 0, None
with open(src, errors='replace') as f:
    for line in f:
        if '"message":"duration:' not in line or 'WITH insert_values' in line[:3000]:
            continue
        e = json.loads(line)
        is_posts = 'process_posts_from_staging(' in e['message'][:400]
        if posts_pid is None and is_posts:
            posts_pid = e['pid']
        if posts_pid is not None and e['pid'] != posts_pid:
            continue
        if is_posts or 'process_posts_from_staging' in e.get('context', ''):
            pending.append(line)
        if is_posts:
            if k in want:
                sys.stdout.write(''.join(pending))
            pending, k = [], k + 1
