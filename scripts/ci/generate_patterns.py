#!/usr/bin/env python3
"""Fill placeholder tavern patterns with the responses of CI's mock-data database.

A placeholder is a `.pat.json` that is `{}` (or absent). The script pushes HEAD to a
scratch branch `patterns/<shortsha>` (with `-o ci.skip`), starts a pipeline there that
reuses a cached hivemind sync (POSTGREST_ONLY_CHANGE=true, AUTO_SKIP_SYNC=false), waits
for `e2e_benchmark_on_postgrest`, and copies each requested test's `.out.json` from the
job's artifacts to its `.pat.json`. The scratch branch is deleted at the end.

  generate_patterns.py [--dry-run] [--force] TEST... | --all-placeholders
  generate_patterns.py --artifacts DIR_OR_ZIP TEST...   # artifacts already downloaded

TEST is a `.tavern.yaml` or `.pat.json` path. Needs GITLAB_TOKEN (api scope) and push
access to the remote. Exit status: 0 when every requested pattern was written, 1 when a
test needs attention (no output, kept pattern, unusable output), 2 on errors.
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from collections import Counter
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

TAVERN_DIR = Path('tests/api_tests/hivemind/tavern')
TEST_EXT = '.tavern.yaml'
PATTERN_EXT = '.pat.json'
OUTPUT_EXT = '.out.json'

JOB_NAME = 'e2e_benchmark_on_postgrest'
PIPELINE_VARIABLES = {'POSTGREST_ONLY_CHANGE': 'true', 'AUTO_SKIP_SYNC': 'false'}
BRANCH_PREFIX = 'patterns/'

# The job keeps its artifacts `when: always`; with placeholder patterns it is expected to fail.
_JOB_DONE = {'success', 'failed'}
_JOB_WAITING = {
    'created',
    'pending',
    'preparing',
    'waiting_for_resource',
    'waiting_for_callback',
    'running',
    'scheduled',
}

_SUMMARY_KEYS = 12
_SUMMARY_NULLS = 10


class PatternError(Exception):
    """A request the script can't carry out: bad arguments, git or GitLab failures."""


@dataclass
class Report:
    """What `apply_artifacts` did, per test (paths are test stems relative to the repo root)."""

    written: dict[Path, str] = field(default_factory=dict)
    missing: list[Path] = field(default_factory=list)
    kept: list[Path] = field(default_factory=list)
    unusable: dict[Path, str] = field(default_factory=dict)

    @property
    def complete(self) -> bool:
        return not (self.missing or self.kept or self.unusable)


def is_placeholder(pattern: Path) -> bool:
    """True when `pattern` is absent or holds exactly `{}`; an unreadable pattern is not one."""
    if not pattern.exists():
        return True
    try:
        value: object = json.loads(pattern.read_text())
        return value == {}
    except json.JSONDecodeError:
        return False


def find_placeholders(root: Path) -> list[Path]:
    """Test stems (relative to `root`) whose existing `.pat.json` is `{}`."""
    stems = []
    for pattern in sorted((root / TAVERN_DIR).rglob('*' + PATTERN_EXT)):
        stem = pattern.with_name(pattern.name.removesuffix(PATTERN_EXT))
        if _with_ext(stem, TEST_EXT).exists() and is_placeholder(pattern):
            stems.append(stem.relative_to(root))
    return stems


def resolve_tests(root: Path, args: list[str]) -> list[Path]:
    """Test stems relative to `root` for `.tavern.yaml` / `.pat.json` paths; PatternError for anything else."""
    stems = []
    for arg in args:
        path = Path(arg).resolve()
        name = path.name
        for ext in (TEST_EXT, PATTERN_EXT):
            if name.endswith(ext):
                stem = path.with_name(name.removesuffix(ext))
                break
        else:
            raise PatternError(f'{arg}: expected a {TEST_EXT} or {PATTERN_EXT} path')
        if not _with_ext(stem, TEST_EXT).is_file():
            raise PatternError(f'{arg}: no {TEST_EXT} next to it')
        try:
            relative = stem.relative_to(root.resolve())
        except ValueError:
            raise PatternError(f'{arg}: outside the repository {root}') from None
        if not relative.is_relative_to(TAVERN_DIR):
            raise PatternError(f'{arg}: not under {TAVERN_DIR}')
        if relative not in stems:
            stems.append(relative)
    return stems


def apply_artifacts(root: Path, artifacts: Path, tests: list[Path], force: bool = False) -> Report:
    """Copy each test's `.out.json` under `artifacts` to its `.pat.json` under `root`.

    A pattern that isn't a placeholder is kept unless `force`. An output that isn't one
    JSON document, or is a whole JSON-RPC envelope (what the validator saves when the call
    failed or returned a null result), is reported as unusable and not written.
    """
    report = Report()
    for test in tests:
        pattern = _with_ext(root / test, PATTERN_EXT)
        output = _with_ext(artifacts / test, OUTPUT_EXT)
        if not force and not is_placeholder(pattern):
            report.kept.append(test)
            continue
        if not output.is_file():
            report.missing.append(test)
            continue
        try:
            value = json.loads(output.read_text())
        except json.JSONDecodeError as e:
            report.unusable[test] = f'not one JSON document ({e.msg} at line {e.lineno})'
            continue
        if isinstance(value, dict) and 'jsonrpc' in value:
            report.unusable[test] = 'whole JSON-RPC response saved: ' + json.dumps(value)[:300]
            continue
        pattern.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')
        report.written[test] = summarize(value)
    return report


def summarize(value: object) -> str:
    """One line for a reviewer: the shape of `value`, its list lengths and where it holds nulls."""
    if isinstance(value, dict):
        shape = f'{{{len(value)} keys: {_names(value)}}}'
        lists = [f'{key}[{len(item)}]' for key, item in sorted(value.items()) if isinstance(item, list)]
        if lists:
            shape += ' lists: ' + ', '.join(lists)
    elif isinstance(value, list):
        shape = f'list[{len(value)}]'
        if value and isinstance(value[0], dict):
            shape += f' of {{{_names(value[0])}}}'
    else:
        shape = f'{type(value).__name__}: {json.dumps(value)[:80]}'
    nulls = Counter(_null_paths(value, ''))
    if nulls:
        listed = [f'{path}×{count}' if count > 1 else path for path, count in sorted(nulls.items())]
        more = len(listed) - _SUMMARY_NULLS
        shape += '; nulls: ' + ', '.join(listed[:_SUMMARY_NULLS]) + (f' +{more} more' if more > 0 else '')
    return shape


def _names(record: dict[str, Any]) -> str:
    keys = sorted(record)
    more = len(keys) - _SUMMARY_KEYS
    return ', '.join(keys[:_SUMMARY_KEYS]) + (f', +{more} more' if more > 0 else '')


def _null_paths(value: object, path: str) -> Iterator[str]:
    if value is None:
        yield path or '(root)'
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from _null_paths(item, f'{path}.{key}' if path else key)
    elif isinstance(value, list):
        for item in value:
            yield from _null_paths(item, path + '[]')


def _with_ext(stem: Path, ext: str) -> Path:
    return stem.with_name(stem.name + ext)


def _git(*args: str) -> str:
    try:
        result = subprocess.run(['git', *args], check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        raise PatternError(f'git {" ".join(args)}: {e.stderr.strip()}') from e
    return result.stdout.strip()


class _GitLab:
    def __init__(self, url: str, project: str, token: str):
        self._api = f'{url.rstrip("/")}/api/v4/projects/{urllib.parse.quote(project, safe="")}'
        self._token = token

    def _open(self, method: str, path: str, body: dict[str, Any] | None = None) -> http.client.HTTPResponse:
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(self._api + path, data=data, method=method)
        request.add_header('PRIVATE-TOKEN', self._token)
        if data is not None:
            request.add_header('Content-Type', 'application/json')
        try:
            response: http.client.HTTPResponse = urllib.request.urlopen(request, timeout=120)
        except urllib.error.HTTPError as e:
            raise PatternError(f'GitLab {method} {path}: HTTP {e.code} {e.read()[:300]!r}') from e
        except urllib.error.URLError as e:
            raise PatternError(f'GitLab {method} {path}: {e.reason}') from e
        return response

    def _json(self, method: str, path: str, body: dict[str, Any] | None = None) -> Any:
        with self._open(method, path, body) as response:
            return json.load(response)

    def create_pipeline(self, ref: str, variables: dict[str, str]) -> dict[str, Any]:
        body = {'ref': ref, 'variables': [{'key': k, 'value': v} for k, v in variables.items()]}
        pipeline: dict[str, Any] = self._json('POST', '/pipeline', body)
        return pipeline

    def pipeline_job(self, pipeline_id: int, name: str) -> dict[str, Any] | None:
        jobs: list[dict[str, Any]] = self._json('GET', f'/pipelines/{pipeline_id}/jobs?per_page=100')
        return next((job for job in jobs if job['name'] == name), None)

    def download_artifacts(self, job_id: int, target: Path) -> None:
        with self._open('GET', f'/jobs/{job_id}/artifacts') as response, target.open('wb') as out:
            shutil.copyfileobj(response, out)


def _wait_for_job(gitlab: _GitLab, pipeline_id: int, timeout: float, interval: float) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    last = None
    while True:
        job = gitlab.pipeline_job(pipeline_id, JOB_NAME)
        status = job['status'] if job else None
        if status != last:
            print(f'{JOB_NAME}: {status or "not created yet"}', file=sys.stderr)
            last = status
        if job is not None and status in _JOB_DONE:
            return job
        if job is not None and status not in _JOB_WAITING:
            raise PatternError(f'{JOB_NAME} ended {status}: {job.get("web_url")}')
        if time.monotonic() > deadline:
            raise PatternError(f'{JOB_NAME} not finished after {timeout / 60:.0f} min (pipeline {pipeline_id})')
        time.sleep(interval)


def _extract_outputs(archive: Path, target: Path) -> None:
    with zipfile.ZipFile(archive) as zf:
        # extractall drops absolute and `..` components from member names.
        zf.extractall(target, [name for name in zf.namelist() if name.endswith(OUTPUT_EXT)])


def _artifact_root(path: Path, scratch: Path) -> Path:
    if path.is_dir():
        return path
    if zipfile.is_zipfile(path):
        _extract_outputs(path, scratch)
        return scratch
    raise PatternError(f'{path}: neither a directory nor a zip archive')


def _check_committed(tests: list[Path]) -> None:
    files = [str(_with_ext(t, ext)) for t in tests for ext in (TEST_EXT, PATTERN_EXT)]
    dirty = _git('status', '--porcelain', '--', *files)
    if dirty:
        raise PatternError(f'commit these first; CI runs the pushed commit:\n{dirty}')


def _print_plan(root: Path, branch: str, args: argparse.Namespace, tests: list[Path]) -> None:
    print(f'branch:    {branch} (pushed to {args.remote} with -o ci.skip, deleted afterwards)')
    print(f'project:   {args.gitlab_url} {args.project}')
    print('variables: ' + ' '.join(f'{k}={v}' for k, v in PIPELINE_VARIABLES.items()))
    print(f'job:       {JOB_NAME}')
    print(f'tests ({len(tests)}):')
    for test in tests:
        fillable = args.force or is_placeholder(_with_ext(root / test, PATTERN_EXT))
        print(f'  {test}' + ('' if fillable else '  (has a pattern; kept without --force)'))


def _print_report(report: Report) -> None:
    for test, summary in report.written.items():
        print(f'written  {test}{PATTERN_EXT}: {summary}')
    for test in report.missing:
        print(f'MISSING  {test}: no {OUTPUT_EXT} (the test passed against its pattern, or did not run)')
    for test in report.kept:
        print(f'KEPT     {test}: pattern is not a placeholder (use --force to overwrite)')
    for test, reason in report.unusable.items():
        print(f'UNUSABLE {test}: {reason}')
    print(
        f'{len(report.written)} written, {len(report.missing)} missing, '
        f'{len(report.kept)} kept, {len(report.unusable)} unusable. '
        'Check each written value against independent data before committing.'
    )


def _run_ci(args: argparse.Namespace, branch: str, scratch: Path) -> Path:
    token = os.environ.get('GITLAB_TOKEN')
    if not token:
        raise PatternError('GITLAB_TOKEN is not set')
    gitlab = _GitLab(args.gitlab_url, args.project, token)
    _git('push', '--force', '-o', 'ci.skip', args.remote, f'HEAD:refs/heads/{branch}')
    try:
        pipeline = gitlab.create_pipeline(branch, PIPELINE_VARIABLES)
        print(f'pipeline: {pipeline.get("web_url", pipeline["id"])}', file=sys.stderr)
        job = _wait_for_job(gitlab, pipeline['id'], args.timeout * 60, args.poll_interval)
        archive = scratch / 'artifacts.zip'
        gitlab.download_artifacts(job['id'], archive)
        _extract_outputs(archive, scratch / 'artifacts')
        return scratch / 'artifacts'
    finally:
        try:
            _git('push', args.remote, '--delete', branch)
        except PatternError as e:
            print(f'warning: scratch branch {branch} not deleted: {e}', file=sys.stderr)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('tests', nargs='*', help=f'{TEST_EXT} or {PATTERN_EXT} paths')
    parser.add_argument('--all-placeholders', action='store_true', help=f'every test whose {PATTERN_EXT} is {{}}')
    parser.add_argument('--force', action='store_true', help='overwrite patterns that are not placeholders')
    parser.add_argument('--dry-run', action='store_true', help='print the plan; push nothing')
    parser.add_argument('--artifacts', type=Path, help='use these extracted artifacts (dir or zip) instead of CI')
    parser.add_argument('--remote', default='origin')
    parser.add_argument('--gitlab-url', default='https://gitlab.syncad.com')
    parser.add_argument('--project', default='hive/hivemind')
    parser.add_argument('--timeout', type=float, default=120, help='minutes to wait for the job')
    parser.add_argument('--poll-interval', type=float, default=30, help='seconds')
    args = parser.parse_args(argv)
    if bool(args.tests) == args.all_placeholders:
        parser.error('give test paths or --all-placeholders, not both')
    if args.dry_run and args.artifacts:
        parser.error('--dry-run plans a CI run; --artifacts skips it')

    try:
        root = Path(_git('rev-parse', '--show-toplevel'))
        tests = find_placeholders(root) if args.all_placeholders else resolve_tests(root, args.tests)
        if not tests:
            print('no tests to fill', file=sys.stderr)
            return 0
        with tempfile.TemporaryDirectory() as scratch:
            if args.artifacts:
                artifacts = _artifact_root(args.artifacts, Path(scratch))
            else:
                branch = BRANCH_PREFIX + _git('rev-parse', '--short=8', 'HEAD')
                _check_committed(tests)
                _print_plan(root, branch, args, tests)
                if args.dry_run:
                    return 0
                artifacts = _run_ci(args, branch, Path(scratch))
            report = apply_artifacts(root, artifacts, tests, args.force)
    except PatternError as e:
        print(f'error: {e}', file=sys.stderr)
        return 2
    _print_report(report)
    return 0 if report.complete else 1


if __name__ == '__main__':
    sys.exit(main())
