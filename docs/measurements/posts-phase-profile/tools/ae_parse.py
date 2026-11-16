#!/usr/bin/env python3
"""Aggregate auto_explain (log_format=json, jsonlog destination) plans of hivemind's posts phase.

usage: ae_parse.py <postgresql.json> <outdir>
Writes statements.tsv (per statement label), nodes.tsv (per label and plan node, exclusive
time and buffers) and plans/<label>.txt (the median and the slowest instance as a text tree).
"""

import collections
import json
import os
import re
import statistics
import sys
from typing import Any

sys.path.insert(0, os.path.dirname(__file__))
from labels import label_of

PlanNode = dict[str, Any]
NodeRow = tuple[str, float, int, int, int, float, int]


def walk(node: PlanNode, path: str, out: list[NodeRow]) -> None:
    name = node.get('Node Type', '?')
    rel = node.get('Relation Name') or node.get('Index Name') or node.get('CTE Name') or node.get('Function Name') or ''
    key = f"{path}/{name}{('(' + rel + ')') if rel else ''}"
    loops = node.get('Actual Loops', 1) or 0
    t = node.get('Actual Total Time', 0.0) * loops
    hit = node.get('Shared Hit Blocks', 0)
    rd = node.get('Shared Read Blocks', 0)
    walb = node.get('WAL Bytes', 0)
    ch = node.get('Plans', [])
    ct = sum(c.get('Actual Total Time', 0.0) * (c.get('Actual Loops', 1) or 0) for c in ch)
    chit = sum(c.get('Shared Hit Blocks', 0) for c in ch)
    crd = sum(c.get('Shared Read Blocks', 0) for c in ch)
    cwal = sum(c.get('WAL Bytes', 0) for c in ch)
    out.append((key, max(t - ct, 0.0), hit - chit, rd - crd, walb - cwal, node.get('Actual Rows', 0) * loops, loops))
    for c in ch:
        walk(c, key, out)


def tree(node: PlanNode, ind: int = 0, lines: list[str] | None = None) -> list[str]:
    lines = [] if lines is None else lines
    loops = node.get('Actual Loops', 1)
    rel = node.get('Relation Name') or node.get('CTE Name') or node.get('Function Name') or ''
    idx = node.get('Index Name', '')
    s = ('  ' * ind) + ('-> ' if ind else '') + node.get('Node Type', '?')
    if node.get('Join Type'):
        s += f" {node['Join Type']}"
    if rel:
        s += f" on {rel}"
    if idx:
        s += f" using {idx}"
    s += f"  (est rows={node.get('Plan Rows')}) (actual time={node.get('Actual Total Time', 0):.3f} rows={node.get('Actual Rows')} loops={loops})"
    s += f" hit={node.get('Shared Hit Blocks', 0)} read={node.get('Shared Read Blocks', 0)} dirtied={node.get('Shared Dirtied Blocks', 0)}"
    if node.get('WAL Bytes'):
        s += f" wal={node.get('WAL Bytes')}B/{node.get('WAL Records')}rec"
    lines.append(s)
    for k in (
        'Index Cond',
        'Hash Cond',
        'Merge Cond',
        'Join Filter',
        'Filter',
        'Conflict Resolution',
        'Conflict Arbiter Indexes',
        'Tuples Inserted',
        'Conflicting Tuples',
        'Rows Removed by Filter',
        'Rows Removed by Join Filter',
        'Sort Method',
        'Hash Batches',
        'Peak Memory Usage',
    ):
        if k in node:
            lines.append(('  ' * ind) + f"     {k}: {node[k]}")
    for c in node.get('Plans', []):
        tree(c, ind + 1, lines)
    return lines


def main() -> None:
    src, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(f'{outdir}/plans', exist_ok=True)
    stmts: collections.defaultdict[str, list[tuple[float, int, int, int, int, float, dict[str, Any]]]] = (
        collections.defaultdict(list)
    )
    nodes: collections.defaultdict[str, list[float]] = collections.defaultdict(lambda: [0.0] * 6)
    unlabeled: collections.defaultdict[str, float] = collections.defaultdict(float)
    with open(src, errors='replace') as f:
        for line in f:
            if '"message":"duration:' not in line or 'WITH insert_values' in line[:3000]:
                continue
            try:
                e = json.loads(line)
            except ValueError:
                continue
            m = e.get('message', '')
            if not m.startswith('duration:') or 'plan:' not in m:
                continue
            dm = re.match(r'duration: ([0-9.]+) ms', m)
            if dm is None:
                continue
            dur = float(dm.group(1))
            p = json.loads(m.split('plan:', 1)[1])
            qt = re.sub(r'\s+', ' ', p.get('Query Text', '')).strip()
            lab = label_of(qt)
            if lab is None:
                unlabeled[qt[:100]] += dur
                continue
            top = p['Plan']
            stmts[lab].append(
                (
                    dur,
                    top.get('Shared Hit Blocks', 0),
                    top.get('Shared Read Blocks', 0),
                    top.get('Shared Dirtied Blocks', 0),
                    top.get('WAL Bytes', 0),
                    top.get('Actual Rows', 0),
                    p,
                )
            )
            out: list[NodeRow] = []
            walk(top, lab, out)
            for key, t, h, r, w, rows, loops in out:
                a = nodes[key]
                a[0] += t
                a[1] += h
                a[2] += r
                a[3] += w
                a[4] += rows
                a[5] += loops
    with open(f'{outdir}/statements.tsv', 'w') as o:
        o.write('label\tcalls\ttotal_ms\tmean_ms\tp50_ms\tmax_ms\tshared_hit\tshared_read\tdirtied\twal_bytes\trows\n')
        for lab, v in sorted(stmts.items(), key=lambda kv: -sum(x[0] for x in kv[1])):
            d = [x[0] for x in v]
            o.write(
                f"{lab}\t{len(v)}\t{sum(d):.1f}\t{sum(d) / len(v):.3f}\t{statistics.median(d):.3f}\t{max(d):.3f}\t{sum(x[1] for x in v)}\t{sum(x[2] for x in v)}\t{sum(x[3] for x in v)}\t{sum(x[4] for x in v)}\t{sum(x[5] for x in v)}\n"
            )
            srt = sorted(v, key=lambda x: x[0])
            with open(f'{outdir}/plans/{lab}.txt', 'w') as pf:
                for title, inst in (('median', srt[len(srt) // 2]), ('slowest', srt[-1])):
                    pf.write(f"## {lab}: {title} of {len(v)} instances, {inst[0]:.3f} ms\n")
                    pf.write(inst[6].get('Query Text', '').strip()[:4000] + '\n\n')
                    pf.write('\n'.join(tree(inst[6]['Plan'])) + '\n\n')
    with open(f'{outdir}/nodes.tsv', 'w') as o:
        o.write('node_path\texcl_ms\texcl_shared_hit\texcl_shared_read\texcl_wal_bytes\trows\tloops\n')
        for k, a in sorted(nodes.items(), key=lambda kv: -kv[1][0]):
            o.write(f"{k}\t{a[0]:.1f}\t{a[1]:.0f}\t{a[2]:.0f}\t{a[3]:.0f}\t{a[4]:.0f}\t{a[5]:.0f}\n")
    with open(f'{outdir}/unlabeled.tsv', 'w') as o:
        for k, total in sorted(unlabeled.items(), key=lambda kv: -kv[1])[:60]:
            o.write(f"{total:.1f}\t{k}\n")


if __name__ == '__main__':
    main()
