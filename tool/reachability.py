#!/usr/bin/env python3
"""Finds capabilities that exist and nothing reaches.

Run from the repo root:  python3 tool/reachability.py

The recurring fault in this codebase is not missing code — it is code that was written, tested, and never
wired to a user. Five instances found so far: `QuickAddSheet`, `ShoppingActions.delete`,
`BalanceService.convertOne`, `ReminderPort.refreshSchedule`, and `AppLock.changePin`/`disable`. Each was
discovered by a user reporting a missing feature rather than by anything in the build.

This finds them before the user does. It is deliberately crude — it greps rather than parses — so treat the
output as a list to check, not a list of bugs. A method used only through a variable of interface type will
be caught; one invoked reflectively or through a tear-off will not.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else '.')
LIB = ROOT / 'lib'
TEST = ROOT / 'test'

# A capability worth checking: a public async or stream method on a port, repository or service.
DECL = re.compile(r'^\s*(?:Future|Stream)<[^;]+?>\s+(\w+)\(', re.M)
INTERESTING = ('/services/', '/repositories/', '/ports/')


def dart_files(base: Path) -> list[Path]:
    return sorted(base.rglob('*.dart')) if base.exists() else []


def main() -> int:
    declared: dict[str, Path] = {}
    for path in dart_files(LIB):
        if not any(k in path.as_posix() for k in INTERESTING):
            continue
        if path.name.endswith('.g.dart'):
            continue
        for match in DECL.finditer(path.read_text()):
            name = match.group(1)
            if not name.startswith('_'):
                declared.setdefault(name, path)

    prod_calls: dict[str, set[Path]] = {}
    test_calls: dict[str, set[Path]] = {}
    for path in dart_files(LIB) + dart_files(TEST):
        text = path.read_text()
        target = test_calls if TEST in path.parents or 'test/' in path.as_posix() else prod_calls
        for match in re.finditer(r'\.(\w+)\(', text):
            target.setdefault(match.group(1), set()).add(path)

    unreachable = []
    for name, home in sorted(declared.items()):
        prod = {p for p in prod_calls.get(name, set()) if p != home}
        if prod:
            continue
        tests = len(test_calls.get(name, set()))
        unreachable.append((name, home, tests))

    if not unreachable:
        print('Nothing unreachable. Every domain capability has a production caller.')
        return 0

    print(f'{len(unreachable)} domain capabilities have no production caller outside their own file.\n')
    print('The ones with test callers are the dangerous kind: they are proven to work and')
    print('unreachable, so the suite is green and the feature does not exist.\n')
    for name, home, tests in sorted(unreachable, key=lambda row: -row[2]):
        flag = 'TESTED BUT UNREACHABLE' if tests else 'no callers at all'
        print(f'  {name:28} {home.relative_to(ROOT).as_posix():52} {flag}')
    print('\nNot every line is a bug — a deliberately dropped method (see ARCH_4 §5.1) belongs')
    print('here too, and the fix for that one is deletion rather than wiring.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())