#!/usr/bin/env python3
"""Run mypy over the given paths and print its findings as SARIF on stdout.

    mypy_sarif.py PATH...

AIDEV's quality evaluation reads a project's own checker through
`quality.commands` in .aidev/project.yaml, and it accepts SARIF or ESLint JSON
only; mypy writes neither, so this wraps `mypy -O json` (one JSON object per
finding per line). mypy runs at its default strictness with
--ignore-missing-imports: functions without annotations are not checked, so
this type-checks what the project annotates without demanding annotations
everywhere.

The exit code is mypy's (0 clean, 1 findings); AIDEV judges the stage by
whether stdout parses as SARIF, not by the exit code. A mypy crash (exit 2)
prints its stderr and exits 2 with nothing on stdout, which AIDEV reports as a
lost measurement rather than a clean scan.
"""
import json
import subprocess
import sys

MYPY_ARGS = ["--ignore-missing-imports", "--no-error-summary", "--hide-error-context", "-O", "json"]
LEVELS = {"error": "error", "note": "note"}


def result(finding):
    region = {"startLine": finding["line"]}
    if finding.get("column", -1) >= 0:
        region["startColumn"] = finding["column"] + 1
    message = finding["message"]
    if finding.get("hint"):
        message += f" ({finding['hint']})"
    return {
        "ruleId": finding.get("code") or "mypy",
        "level": LEVELS.get(finding.get("severity"), "warning"),
        "message": {"text": message},
        "locations": [{"physicalLocation": {"artifactLocation": {"uri": finding["file"]}, "region": region}}],
    }


def main(paths):
    proc = subprocess.run([sys.executable, "-m", "mypy", *MYPY_ARGS, *paths], capture_output=True, text=True)
    if proc.returncode not in (0, 1):
        sys.stderr.write(proc.stdout + proc.stderr)
        return proc.returncode
    findings = [json.loads(line) for line in proc.stdout.splitlines() if line.startswith("{")]
    # Notes attached to an error repeat its location; keep errors (and stand-alone notes).
    results = [result(f) for f in findings if f.get("severity") != "note" or not f.get("code")]
    sarif = {
        "version": "2.1.0",
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "runs": [{"tool": {"driver": {"name": "mypy", "informationUri": "https://mypy-lang.org"}}, "results": results}],
    }
    json.dump(sarif, sys.stdout)
    return proc.returncode


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(f"usage: {sys.argv[0]} PATH...")
    sys.exit(main(sys.argv[1:]))
