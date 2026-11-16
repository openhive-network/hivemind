#!/usr/bin/env python3
"""sampler.py OUT PG_CONTAINER HIVE_CONTAINER: every second, per-process RssAnon/VmRSS of both containers; peaks to OUT."""

import json
import os
import signal
import subprocess
import sys
import time

out, pg, hive = sys.argv[1:4]
stop = False
signal.signal(signal.SIGTERM, lambda *a: globals().__setitem__('stop', True))


def cid(name: str) -> str | None:
    r = subprocess.run(['docker', 'inspect', '-f', '{{.Id}}', name], capture_output=True, text=True)
    return r.stdout.strip() or None


def procs(c: str) -> tuple[list[int], str | None]:
    path = f'/sys/fs/cgroup/system.slice/docker-{c}.scope/cgroup.procs'
    try:
        return [int(p) for p in open(path).read().split()], path.rsplit('/', 1)[0]
    except OSError:
        return [], None


def status(pid: int) -> dict[str, str] | None:
    d: dict[str, str] = {}
    try:
        for line in open(f'/proc/{pid}/status'):
            k, _, v = line.partition(':')
            if k in ('VmRSS', 'RssAnon', 'RssShmem', 'Name'):
                d[k] = v.strip()
        d['cmd'] = open(f'/proc/{pid}/cmdline').read().replace('\0', ' ')[:120]
    except OSError:
        return None
    return d


def kb(s: str | None) -> int:
    return int(s.split()[0]) if s else 0


peak: dict[str, int] = {
    'pg_backend_anon_kb': 0,
    'pg_anon_sum_kb': 0,
    'pg_backend_rss_kb': 0,
    'hive_rss_kb': 0,
    'hive_anon_kb': 0,
    'samples': 0,
}
peak_cmd = ''
ids: dict[str, str | None] = {}
while not stop:
    for name in (pg, hive):
        if name not in ids or ids[name] is None:
            ids[name] = cid(name)
    pg_id = ids.get(pg)
    if pg_id:
        ps, cg = procs(pg_id)
        s = 0
        for p in ps:
            st = status(p)
            if not st or 'postgres' not in st.get('cmd', ''):
                continue
            a = kb(st.get('RssAnon'))
            s += a
            if a > peak['pg_backend_anon_kb']:
                peak['pg_backend_anon_kb'] = a
                peak_cmd = st['cmd']
            peak['pg_backend_rss_kb'] = max(peak['pg_backend_rss_kb'], kb(st.get('VmRSS')))
        peak['pg_anon_sum_kb'] = max(peak['pg_anon_sum_kb'], s)
    hive_id = ids.get(hive)
    if hive_id:
        ps, _ = procs(hive_id)
        for p in ps:
            st = status(p)
            if st and 'hive.cli' in st.get('cmd', ''):
                peak['hive_rss_kb'] = max(peak['hive_rss_kb'], kb(st.get('VmRSS')))
                peak['hive_anon_kb'] = max(peak['hive_anon_kb'], kb(st.get('RssAnon')))
    peak['samples'] += 1
    with open(out, 'w') as f:
        json.dump({**peak, 'pg_backend_anon_cmd': peak_cmd}, f, indent=1)
    time.sleep(1)
