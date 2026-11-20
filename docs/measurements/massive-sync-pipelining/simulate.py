#!/usr/bin/env python3
"""Replay a massive sync's [PHASE-SUMMARY] times as a two-stage batch pipeline.

    simulate.py [data/phase_summary_20261120.csv]

Stage A is load + accounts_community + posts + community_post; Stage B is every other
phase (votes, rshares_incr, cache_merge, parallel, flush, notify, vacuum,
staging_reset). Batch i's Stage A starts when batch i-1's Stage A has ended and batch
i-2's Stage B has freed its handoff set (two sets); its Stage B starts when its own
Stage A and batch i-1's Stage B have ended. `slow` multiplies every stage's time, a
crude stand-in for the contention of running both stages at once.

`--no-stalls` takes out the votes phase's plan-flip stalls (#495): a batch's votes time
above three times the median of its ten neighbours is cut to that median.
"""

import argparse
import csv
import gzip
import statistics
from pathlib import Path

_STAGE_A = ('load', 'accounts_community', 'posts', 'community_post')
_STAGE_B = ('votes', 'rshares_incr', 'cache_merge', 'parallel', 'flush', 'notify', 'vacuum', 'staging_reset')
_SLOWDOWNS = (1.0, 1.15, 1.3, 1.5)
_RANGES = (
    ('all', 0, 10**10),
    ('0-10M', 0, 10_000_000),
    ('10-30M', 10_000_000, 30_000_000),
    ('30M+', 30_000_000, 10**10),
)


def _read(path: Path) -> list[dict[str, float]]:
    opener = gzip.open if path.suffix == '.gz' else open
    with opener(path, 'rt', newline='') as f:
        rows = []
        for r in csv.DictReader(f):
            phases = {k: float(r[k]) for k in _STAGE_A + _STAGE_B if r.get(k)}
            rows.append({'first': int(r['first_block']), 'last': int(r['last_block']), **phases})
        return rows


def _remove_vote_stalls(rows: list[dict[str, float]]) -> float:
    votes = [r.get('votes', 0.0) for r in rows]
    removed = 0.0
    for i, r in enumerate(rows):
        neighbours = votes[max(0, i - 5) : i] + votes[i + 1 : i + 6]
        median = statistics.median(neighbours) if neighbours else votes[i]
        if votes[i] > 3 * median and votes[i] - median > 5:
            removed += votes[i] - median
            r['votes'] = median
    return removed


def _stages(r: dict[str, float]) -> tuple[float, float]:
    return sum(r.get(k, 0.0) for k in _STAGE_A), sum(r.get(k, 0.0) for k in _STAGE_B)


def _pipelined(rows: list[dict[str, float]], slow: float) -> float:
    end_a = end_b = end_b_prev = 0.0
    for r in rows:
        a, b = _stages(r)
        end_a = max(end_a, end_b_prev) + a * slow
        end_b_prev, end_b = end_b, max(end_a, end_b) + b * slow
    return end_b


def _report(name: str, rows: list[dict[str, float]]) -> None:
    sequential = sum(sum(_stages(r)) for r in rows)
    total_a = sum(_stages(r)[0] for r in rows)
    total_b = sum(_stages(r)[1] for r in rows)
    blocks = rows[-1]['last'] - rows[0]['first'] + 1
    a_heavier = sum(1 for r in rows if _stages(r)[0] > _stages(r)[1])
    print(
        f"{name}: {len(rows)} batches, blocks {rows[0]['first']}-{rows[-1]['last']}, "
        f"sequential {sequential / 3600:.2f} h ({blocks / sequential:.0f} blocks/s), "
        f"A {total_a / 3600:.2f} h, B {total_b / 3600:.2f} h, A heavier in {a_heavier} batches"
    )
    for slow in _SLOWDOWNS:
        t = _pipelined(rows, slow)
        print(
            f"  slow {slow:.2f}: pipelined {t / 3600:.2f} h ({blocks / t:.0f} blocks/s), saving {(1 - t / sequential) * 100:.1f} %"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        'csv', nargs='?', type=Path, default=Path(__file__).parent / 'data' / 'phase_summary_20261120.csv'
    )
    parser.add_argument('--no-stalls', action='store_true', help="take out #495's votes-phase stalls")
    args = parser.parse_args()
    rows = _read(args.csv)
    if args.no_stalls:
        print(f'votes stalls removed: {_remove_vote_stalls(rows):.0f} s')
    for name, lo, hi in _RANGES:
        selected = [r for r in rows if r['first'] > lo and r['last'] <= hi]
        if selected:
            _report(name, selected)


if __name__ == '__main__':
    main()
