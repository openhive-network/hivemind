#!/usr/bin/env python3
"""Per-statement table of the posts phase from run directories' pg_stat_statements dumps.

usage: stmt_table.py <run dir> [<run dir> ...]
Each run dir holds pss.tsv and queries.tsv as run_sample.sh writes them. The first run's
order is used; times are exclusive of the nested statements listed in NESTED.
"""

import collections
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from labels import label_of

csv.field_size_limit(10**9)

# parent -> children whose time pg_stat_statements also counts in the parent
NESTED = {
    'posts_fn': [
        'pr_wave_comments',
        'pr_root',
        'permlink_ins',
        'category_ins',
        'tags_5d',
        'tags_5e',
        'cs_ins',
        'cs_norm',
        'wave_count',
        'del_create_pairs',
        'ineff_keys',
        'edits_5b',
        'edits_5c',
        'co_ops',
        'simple_deletes',
        'step7e',
        'step8_notif',
        'return_query',
        'del_cs',
        'del_pr',
        'del_rp',
        'replay_pairs',
        'replay_loop',
        'delete_hive_post',
        'process_hive_post_op',
    ],
    'pr_wave_comments': ['pb_ins_comments', 'hp_ins_comments'],
    'pr_root': ['pb_ins_root', 'hp_ins_root'],
}
ORDER = [
    'hp_ins_comments',
    'pb_ins_comments',
    'pr_wave_comments',
    'hp_ins_root',
    'pb_ins_root',
    'pr_root',
    'permlink_ins',
    'tags_5d',
    'tags_5e',
    'cs_ins',
    'wave_count',
    'co_ops',
    'cs_norm',
    'del_create_pairs',
    'edits_5b',
    'edits_5c',
    'replay_pairs',
    'return_query',
    'del_cs',
    'del_pr',
    'category_ins',
    'step7e',
    'simple_deletes',
    'step8_notif',
    'posts_fn',
]


def load(d: str) -> tuple[dict[str, list[float]], dict[str, list[float]]]:
    q: dict[str, str] = {}
    for row in csv.reader(open(f'{d}/queries.tsv'), delimiter='\t', quoting=csv.QUOTE_NONE):
        if len(row) >= 3:
            q[row[0]] = row[2]
    agg: collections.defaultdict[str, list[float]] = collections.defaultdict(lambda: [0.0] * 7)
    for r in csv.reader(open(f'{d}/pss.tsv'), delimiter='\t', quoting=csv.QUOTE_NONE):
        if len(r) < 17:
            continue
        lab = label_of(q.get(r[16], ''))
        if not lab:
            continue
        a = agg[lab]
        a[0] += int(r[4])
        a[1] += float(r[5])
        a[2] += int(r[6])
        a[3] += int(r[7])
        a[4] += int(r[8])
        a[5] += int(r[13])
        a[6] += float(r[14])
    excl: dict[str, list[float]] = {}
    for lab, a in agg.items():
        e = list(a)
        for c in NESTED.get(lab, []):
            if c in agg:
                e[1] -= agg[c][1]
                e[3] -= agg[c][3]
                e[4] -= agg[c][4]
                e[5] -= agg[c][5]
        excl[lab] = e
    return agg, excl


runs = [(os.path.basename(d.rstrip('/')), *load(d)) for d in sys.argv[1:]]
name0, agg0, excl0 = runs[0]
posts = agg0['posts_fn'][1]
batches = agg0['posts_fn'][0]
hdr = ['statement', 'calls', 'excl s', '% of posts', 'ms/batch', 'rows', 'µs/row', 'hit/row', 'reads', 'WAL MB']
for name, _, _ in runs[1:]:
    hdr += [f'{name} excl s', f'{name} WAL MB']
print('| ' + ' | '.join(hdr) + ' |')
print('|' + '---|' * len(hdr))
for lab in ORDER:
    if lab not in excl0:
        continue
    c, t, rows, hit, rd, wal, rt = excl0[lab]
    a = agg0[lab]
    rows = a[2]
    line = [
        lab,
        f'{c:.0f}',
        f'{t / 1000:.1f}',
        f'{100 * t / posts:.1f}',
        f'{t / batches:.1f}',
        f'{rows:.0f}',
        f'{1000 * t / max(rows, 1):.1f}' if rows > c else '',
        f'{a[3] / max(rows, 1):.0f}' if rows > c else f'{a[3] / max(c, 1):.0f}/call',
        f'{rd:.0f}',
        f'{wal / 1e6:.0f}',
    ]
    for name, agg, excl in runs[1:]:
        e = excl.get(lab)
        line += [f'{e[1] / 1000:.1f}' if e else '', f'{e[5] / 1e6:.0f}' if e else '']
    print('| ' + ' | '.join(line) + ' |')
