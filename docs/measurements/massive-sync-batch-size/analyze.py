#!/usr/bin/env python3
"""analyze.py LOG...: per-window blocks/s (wall between batch completions) and phase sums."""

import json
import re
import sys

WINDOWS = [
    (0, 1_000_000),
    (1_000_000, 2_000_000),
    (2_000_000, 3_000_000),
    (3_000_000, 4_000_000),
    (4_000_000, 4_990_000),
    (0, 4_990_000),
]
pat = re.compile(r'^(\d+\.\d+) .*\[PHASE-SUMMARY\] blocks=(\d+)-(\d+) total=([\d.]+)s (.*)$')
for path in sys.argv[1:]:
    done = []  # (ts, first, last, total, phases)
    first_ts: float | None = None
    for line in open(path, errors='replace'):
        if first_ts is None and 'Next block range' in line and line[:1].isdigit():
            first_ts = float(line.split()[0])
        m = pat.match(line)
        if m:
            ph = dict(kv.split('=') for kv in m.group(5).split())
            done.append(
                (
                    float(m.group(1)),
                    int(m.group(2)),
                    int(m.group(3)),
                    float(m.group(4)),
                    {k: float(v) for k, v in ph.items()},
                )
            )
    if not done or first_ts is None:
        print(path, 'no timestamped batches')
        continue
    out = {'log': path, 'batches': len(done), 'massive_wall_s': round(done[-1][0] - first_ts, 1)}
    for lo, hi in WINDOWS:
        sel = [d for d in done if d[1] > lo and d[2] <= hi]
        if not sel:
            continue
        prev = [d for d in done if d[2] <= lo]
        t0 = prev[-1][0] if prev else first_ts
        wall = sel[-1][0] - t0
        blocks = sel[-1][2] - (prev[-1][2] if prev else 0)
        phases: dict[str, float] = {}
        for d in sel:
            for k, v in d[4].items():
                phases[k] = phases.get(k, 0) + v
        out[f'{lo / 1e6:g}-{hi / 1e6:g}M'] = {
            'batches': len(sel),
            'wall_s': round(wall, 1),
            'bps': round(blocks / wall),
            'phase_sum_s': round(sum(d[3] for d in sel), 1),
            'max_batch_s': round(max(d[3] for d in sel), 2),
            'top': {k: round(v, 1) for k, v in sorted(phases.items(), key=lambda kv: -kv[1])[:6]},
        }
    print(json.dumps(out, indent=1))
