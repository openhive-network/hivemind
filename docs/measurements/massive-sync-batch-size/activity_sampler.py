#!/usr/bin/env python3
"""activity_sampler.py OUT PG_CONTAINER [DB [USER]]: every second, host CPU and iowait from /proc/stat deltas and
pg_stat_activity of DB counted by application (or role), state and wait event; one JSON line per sample to OUT.

activity_sampler.py --summary FILE...: per file (one run), mean CPU busy, user, system and iowait, and the top
wait events of non-idle backends by sample count.
"""

import json
import signal
import subprocess
import sys
import time
from collections import Counter

# Each row: application_name (else the role, else the backend type), state, wait_event_type, wait_event, count.
QUERY = """SET statement_timeout = 500;
SELECT coalesce(nullif(application_name, ''), usename::text, backend_type), coalesce(state, ''),
       coalesce(wait_event_type, ''), coalesce(wait_event, ''), count(*)
FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid()
GROUP BY 1, 2, 3, 4 ORDER BY 5 DESC"""
TOP = 15


def cpu_ticks() -> list[int]:
    with open('/proc/stat') as f:
        return [int(v) for v in f.readline().split()[1:]]


def cpu_pct(before: list[int], after: list[int]) -> dict[str, float]:
    d = [a - b for a, b in zip(after, before, strict=True)]
    total = sum(d[:8]) or 1  # guest and guest_nice are already counted in user and nice
    user, nice, system, idle, iowait, irq, softirq, steal = d[:8]

    def pct(v: int) -> float:
        return round(100 * v / total, 2)

    return {
        'busy': pct(total - idle - iowait),
        'user': pct(user + nice),
        'system': pct(system + irq + softirq),
        'iowait': pct(iowait),
        'idle': pct(idle),
        'steal': pct(steal),
    }


def activity(pg: str, db: str, user: str) -> tuple[list[dict[str, object]], str | None]:
    cmd = ['docker', 'exec', pg, 'psql', '-h', '127.0.0.1', '-U', user, '-d', db, '-AtqX', '-F', '\t', '-c', QUERY]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=0.9)
    except subprocess.TimeoutExpired:
        return [], 'psql timed out'
    if r.returncode != 0:
        return [], r.stderr.strip()[:200] or f'psql exited {r.returncode}'
    rows: list[dict[str, object]] = []
    for line in r.stdout.splitlines():
        app, state, wtype, wevent, n = line.split('\t')
        rows.append({'app': app, 'state': state, 'wait_event_type': wtype, 'wait_event': wevent, 'n': int(n)})
    return rows, None


def sample(out: str, pg: str, db: str, user: str) -> None:
    stop = False

    def on_term(*_: object) -> None:
        nonlocal stop
        stop = True

    signal.signal(signal.SIGTERM, on_term)
    prev = cpu_ticks()
    tick = time.monotonic()
    with open(out, 'a') as f:
        while not stop:
            tick += 1
            # A slow tick is skipped rather than caught up, so samples never pile up behind it.
            while tick <= time.monotonic():
                tick += 1
            time.sleep(max(0.0, tick - time.monotonic()))
            if stop:
                break
            now = cpu_ticks()
            line: dict[str, object] = {'ts': round(time.time(), 3), 'cpu': cpu_pct(prev, now)}
            prev = now
            line['activity'], err = activity(pg, db, user)
            if err:
                line['error'] = err
            f.write(json.dumps(line) + '\n')
            f.flush()


def wait_label(row: dict[str, object]) -> str:
    if row['wait_event_type']:
        return f"{row['wait_event_type']}:{row['wait_event']}"
    return 'CPU (no wait event)'


def summary(path: str) -> None:
    samples = [json.loads(line) for line in open(path) if line.strip()]
    print(f'== {path}')
    if not samples:
        print('no samples')
        return
    n = len(samples)
    errors = sum(1 for s in samples if 'error' in s)
    span = samples[-1]['ts'] - samples[0]['ts']
    print(f'samples={n} span_s={span:.0f} errors={errors}')
    print(
        '  '.join(
            f'mean_{k}={sum(s["cpu"][k] for s in samples) / n:.1f}%' for k in ('busy', 'user', 'system', 'iowait')
        )
    )
    in_samples: Counter[str] = Counter()
    backend_samples: Counter[str] = Counter()
    for s in samples:
        seen: set[str] = set()
        for row in s['activity']:
            if row['state'] in ('', 'idle'):
                continue
            label = wait_label(row)
            backend_samples[label] += row['n']
            seen.add(label)
        in_samples.update(seen)
    print(f'top wait events of non-idle backends ({TOP}): samples seen, backend-samples, mean backends')
    for label, k in in_samples.most_common(TOP):
        print(f'  {k:>7} {backend_samples[label]:>9} {backend_samples[label] / n:>7.2f}  {label}')


def main() -> None:
    if sys.argv[1:2] == ['--summary']:
        for path in sys.argv[2:]:
            summary(path)
        return
    out, pg = sys.argv[1:3]
    db = sys.argv[3] if len(sys.argv) > 3 else 'haf_block_log'
    user = sys.argv[4] if len(sys.argv) > 4 else 'haf_admin'
    sample(out, pg, db, user)


main()
