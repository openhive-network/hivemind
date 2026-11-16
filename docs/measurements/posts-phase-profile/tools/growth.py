#!/usr/bin/env python3
"""Per-range growth table from the recorder's pg_stat_statements dumps (sync_pss.tsv)."""

import collections
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from labels import label_of

csv.field_size_limit(10**9)
d = sys.argv[1]
q = {}
for row in csv.reader(open(f'{d}/sync_queries.tsv'), delimiter='\t', quoting=csv.QUOTE_NONE):
    if len(row) >= 3:
        q[row[0]] = row[2]
sizes: collections.defaultdict[str, dict[str, tuple[int, int]]] = collections.defaultdict(dict)
for r in csv.reader(open(f'{d}/sync_sizes.tsv'), delimiter='\t', quoting=csv.QUOTE_NONE):
    if len(r) >= 8:
        sizes[r[1]][r[2]] = (int(r[3]), int(r[4]))
Counters = collections.defaultdict[str, list[float]]
dumps: collections.OrderedDict[str, Counters] = collections.OrderedDict()
for r in csv.reader(open(f'{d}/sync_pss.tsv'), delimiter='\t', quoting=csv.QUOTE_NONE):
    if len(r) < 17:
        continue
    lab = label_of(q.get(r[16], ''))
    if not lab:
        continue
    a = dumps.setdefault(r[1], collections.defaultdict(lambda: [0.0] * 6))[lab]
    a[0] += int(r[4])
    a[1] += float(r[5])
    a[2] += int(r[6])
    a[3] += int(r[7])
    a[4] += int(r[8])
    a[5] += int(r[13])
cols = ['hp_ins_comments', 'hp_ins_root', 'pb_ins_comments', 'permlink_ins', 'tags_5d', 'cs_ins']
print(
    'range_end\tbatches\tposts_ms_per_batch\tcomment_rows_per_batch\thive_posts_rows\t'
    + '\t'.join(f'{c}_pct\t{c}_us_per_row\t{c}_hit_per_row' for c in cols)
    + '\tposts_wal_MB_per_batch'
)
prev = None
for blk, agg in dumps.items():
    pf = agg['posts_fn']
    n = pf[0] or 1
    tot = pf[1] or 1
    rng = f"{prev or '?'}-{blk}"
    hp = sizes.get(blk, {}).get('hive_posts', (0, 0))[0]
    line = [rng, f"{pf[0]:.0f}", f"{pf[1] / n:.1f}", f"{pf[2] / n:.0f}", str(hp)]
    for c in cols:
        a = agg.get(c, [0.0] * 6)
        rows = a[2] if c != 'tags_5d' else agg.get('tags_inner', [0.0] * 6)[2]
        line += [f"{100 * a[1] / tot:.1f}", f"{1000 * a[1] / max(rows, 1):.1f}", f"{a[3] / max(rows, 1):.1f}"]
    line.append(f"{pf[5] / n / 1e6:.1f}")
    print('\t'.join(line))
    prev = blk
