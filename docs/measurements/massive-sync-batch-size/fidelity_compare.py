#!/usr/bin/env python3
"""fidelity_compare.py RUN_A RUN_B: diff two runs' natural-key dumps (logs/<run>/*.txt) file by file.

Surrogate ids are internal: the dumps key and print every row by natural keys, so two runs
that differ only in the ids they drew compare equal. post_ids and notif_ids hold the post
and notification ids as drawn; they are informational and do not count against the
verdict. Exits 1 when a count or a compared file differs, and 2 when the two runs were
dumped in different formats (counts.txt's dump_format).
"""

import collections
import subprocess
import sys

a, b = sys.argv[1], sys.argv[2]


def report(f: str) -> bool:
    out = subprocess.run(['diff', f'logs/{a}/{f}.txt', f'logs/{b}/{f}.txt'], capture_output=True, text=True).stdout
    lines = out.splitlines()
    only_a = [line[2:] for line in lines if line.startswith('< ')]
    only_b = [line[2:] for line in lines if line.startswith('> ')]
    if not only_a and not only_b:
        print(f'  {f}: IDENTICAL')
        return True
    print(f'  {f}: {len(only_a)} lines only in {a}, {len(only_b)} only in {b}')
    if f in ('notifs', 'notif_ids'):
        col = 0 if f == 'notifs' else 1
        ta = collections.Counter(line.split('\t')[col] for line in only_a)
        tb = collections.Counter(line.split('\t')[col] for line in only_b)
        print('     by type_id (only-a / only-b):', {t: (ta[t], tb[t]) for t in sorted(set(ta) | set(tb), key=int)})
    for line in only_a[:3] + only_b[:3]:
        print('     ', line[:420])
    return False


print(f'== {a} vs {b}')
ca = dict(line.rstrip('\n').split('\t') for line in open(f'logs/{a}/counts.txt'))
cb = dict(line.rstrip('\n').split('\t') for line in open(f'logs/{b}/counts.txt'))
if ca.get('dump_format') != cb.get('dump_format'):
    print(
        f'  dump_format {ca.get("dump_format", "-")} against {cb.get("dump_format", "-")}: dump both runs with one fidelity_dump.sql'
    )
    sys.exit(2)
differing = []
for k in ca | cb:
    same = ca.get(k) == cb.get(k)
    if not same:
        differing.append(f'counts:{k}')
    print(f'  {k:18} {ca.get(k, "-"):>12} {cb.get(k, "-"):>12}{"" if same else "   <-- differs"}')

FILES = (
    'posts',
    'votes',
    'notifs',
    'mentions',
    'postdata',
    'accounts',
    'follows',
    'muted',
    'blacklisted',
    'follow_muted',
    'follow_blacklisted',
    'reblogs',
    'feed_cache',
)
INFORMATIONAL = ('post_ids', 'notif_ids')
differing += [f for f in FILES if not report(f)]
print('  ids as drawn (informational, not in the verdict):')
for f in INFORMATIONAL:
    report(f)
print(f'== {"IDENTICAL" if not differing else "DIFFERENT: " + ", ".join(differing)}')
sys.exit(1 if differing else 0)
