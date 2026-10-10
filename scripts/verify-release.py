#!/usr/bin/env python3
"""Inspect release members without ever printing a matching secret."""
import argparse
import pathlib
import re
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('archives', type=pathlib.Path, nargs='+')
args = parser.parse_args()
patterns = [rb'sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{24,}', rb'gh[pousr]_[A-Za-z0-9]{30,}', rb'github_pat_[A-Za-z0-9_]{30,}', rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----']
root = pathlib.Path(__file__).resolve().parent.parent
# Compare the local configured key as a literal as well as provider formats.
known = []
env = root / '.env'
if env.exists():
    for line in env.read_bytes().splitlines():
        if line.strip().startswith(b'OPENAI_API_KEY='):
            value = line.split(b'=', 1)[1].strip().strip(b'\"\'')
            if len(value) >= 20:
                known.append(value)
failures = []
for archive in args.archives:
    with zipfile.ZipFile(archive) as z:
        members = z.infolist()
        for item in members:
            path = pathlib.PurePosixPath(item.filename)
            if path.is_absolute() or '..' in path.parts:
                failures.append((archive.name, item.filename, 'unsafe path'))
                continue
            if any(p in {'.git', '.build', 'private-data', 'test-results', '__pycache__'} for p in path.parts):
                failures.append((archive.name, item.filename, 'private/build content'))
            name = path.name.lower()
            if (name.startswith('.env') and name != '.env.example') or name.endswith(('.sqlite3', '.sqlite3-wal', '.sqlite3-shm', '.pcm', '.aiff', '.wav', '.log')):
                failures.append((archive.name, item.filename, 'private/runtime file'))
            if item.is_dir():
                continue
            if item.file_size > 200_000_000:
                failures.append((archive.name, item.filename, 'unexpectedly large member'))
                continue
            data = z.read(item)
            if any(re.search(pattern, data) for pattern in patterns) or any(key in data for key in known):
                failures.append((archive.name, item.filename, 'credential pattern'))
        print(f'{archive.name}: inspected {len(members)} members')
if failures:
    for archive, path, reason in failures:
        print(f'FAIL {archive}: {path}: {reason}')
    raise SystemExit(1)
print('PASS: no credential patterns, private runtime files, or unsafe paths detected.')
