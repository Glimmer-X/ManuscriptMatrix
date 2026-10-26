#!/usr/bin/env python3
"""Reject common private artifacts and machine paths without printing their contents."""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATTERNS = {
    "machine home path": re.compile(rb"/(?:Users|home)/[A-Za-z0-9_.-]+/|[A-Z]:\\\\Users\\\\"),
    "access credential": re.compile(rb"gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,}|AKIA[A-Z0-9]{16}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
}
PRIVATE_NAMES = {"board-v1.json", "board-v1.lock", ".DS_Store", "signing.env"}


def main():
    if len(sys.argv) > 1:
        paths = []
        for raw in sys.argv[1:]:
            path = Path(raw)
            paths.extend(p for p in path.rglob("*") if p.is_file()) if path.is_dir() else paths.append(path)
    else:
        tracked = subprocess.check_output(["git", "ls-files", "--cached", "-z"], cwd=ROOT)
        paths = [ROOT / p.decode() for p in tracked.split(b"\0") if p]
    failures = []
    for path in paths:
        if path.is_symlink():
            failures.append((path.name, "unreviewed symbolic link"))
            continue
        if path.name in PRIVATE_NAMES or path.suffix in {".p12", ".p8", ".mobileprovision", ".jsonl"}:
            failures.append((path.name, "private artifact"))
        data = path.read_bytes()
        if path.suffix == ".json":
            try:
                value = json.loads(data)
                if isinstance(value, dict) and {"journals", "manuscripts", "submissionEvents"} <= value.keys():
                    failures.append((path.name, "board or backup payload"))
            except (ValueError, UnicodeDecodeError):
                pass
        for label, pattern in PATTERNS.items():
            if pattern.search(data):
                failures.append((path.name, label))
    for name, reason in failures:
        print(f"FAIL: {name}: {reason}", file=sys.stderr)
    if failures:
        raise SystemExit(1)
    print(f"Privacy audit passed for {len(paths)} files. Manual review is still required.")


if __name__ == "__main__":
    main()
