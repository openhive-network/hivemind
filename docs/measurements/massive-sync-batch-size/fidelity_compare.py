#!/usr/bin/env python3
"""fidelity_compare.py RUN_A RUN_B: diff two runs' natural-key dumps (logs/<run>/*.txt) file by file.

Surrogate ids drawn in processing order (permlink_id, category_id) are dropped first:
the dumps already replace post ids with natural keys, and account ids are drawn in
operation order, the same in every run. post_ids and notif_ids hold the post and
notification ids as drawn, reblogs the hive_reblogs ids as drawn.
"""

import collections
import re
import subprocess
import sys

a, b = sys.argv[1], sys.argv[2]
SURROGATE = re.compile(r'"(permlink_id|category_id)": \d+, ')


def normalized(run: str, f: str) -> str:
    path = f'/tmp/cmp-{run}-{f}.txt'
    with open(f'logs/{run}/{f}.txt') as src, open(path, 'w') as dst:
        for line in src:
            dst.write(SURROGATE.sub('', line))
    return path


print(f'== {a} vs {b}')
ca = dict(line.rstrip('\n').split('\t') for line in open(f'logs/{a}/counts.txt'))
cb = dict(line.rstrip('\n').split('\t') for line in open(f'logs/{b}/counts.txt'))
for k in ca:
    mark = '' if ca[k] == cb.get(k) else '   <-- differs'
    print(f'  {k:18} {ca[k]:>12} {cb.get(k, "-"):>12}{mark}')

FILES = (
    'posts',
    'votes',
    'notifs',
    'mentions',
    'postdata',
    'post_ids',
    'notif_ids',
    'accounts',
    'follows',
    'muted',
    'blacklisted',
    'follow_muted',
    'follow_blacklisted',
    'reblogs',
    'feed_cache',
)
for f in FILES:
    out = subprocess.run(['diff', normalized(a, f), normalized(b, f)], capture_output=True, text=True).stdout
    lines = out.splitlines()
    only_a = [line[2:] for line in lines if line.startswith('< ')]
    only_b = [line[2:] for line in lines if line.startswith('> ')]
    if not only_a and not only_b:
        print(f'  {f}: IDENTICAL')
        continue
    print(f'  {f}: {len(only_a)} lines only in {a}, {len(only_b)} only in {b}')
    if f in ('notifs', 'notif_ids'):
        col = 0 if f == 'notifs' else 1
        ta = collections.Counter(line.split('\t')[col] for line in only_a)
        tb = collections.Counter(line.split('\t')[col] for line in only_b)
        print('     by type_id (only-a / only-b):', {t: (ta[t], tb[t]) for t in sorted(set(ta) | set(tb), key=int)})
    for line in only_a[:3] + only_b[:3]:
        print('     ', line[:420])
