#!/usr/bin/env python3
"""Checks that every `strings.<key>` reference in lib/ exists in app_en.arb.

Replaces the shell pipeline that ARCH_M §5 used to carry, which had two faults that each produced a wrong
answer rather than a noisy one:

1. **`sort` and `comm` disagree on collation.** `sort` orders by the current locale's rules; `comm` walks the
   two streams assuming an order it computes differently. One out-of-step line and `comm` starts reporting
   lines from file 1 that do exist in file 2 — then aborts, so the run is *silent* about everything after the
   desync rather than clean. A run reporting `actionDeleteItem`, `actionDeleteTransaction` and
   `billSetUpAction` as missing keys that were all three present is what prompted this file.

2. **It greps raw source, so it matches comments.** ARCH_M §7 says exactly this, about exactly this hazard:
   "A `grep` for a symbol matches comments that mention it. Strip comment lines before searching. This
   produced four false findings in one phase." §5's own snippet did not do it.

Comparison happens with Python sets, so there is no collation to get wrong. Comments are stripped with a
quote-aware scan, so a `//` inside a string literal does not truncate the line and a symbol named in a
trailing comment is not counted as a reference.

**Known limit:** block comments (`/* ... */`) are not tracked across lines. This codebase uses `//` and `///`
throughout; if that changes, this needs a real scanner rather than a line-wise one.

    python3 tool/check_arb_keys.py            # exits 1 if any reference is missing
    python3 tool/check_arb_keys.py --unused   # also lists keys nothing references
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

LIB = Path("lib")
ARB = Path("lib/app/l10n/app_en.arb")

# `strings.someKey`. The lookbehind stops `otherstrings.foo` counting; `AlayaStrings.delegate` never matches
# anyway, because the literal here is lowercase and that identifier capitalises the S.
REFERENCE = re.compile(r"(?<![A-Za-z0-9_$])strings\.([A-Za-z][A-Za-z0-9]*)")


def strip_comments(line: str) -> str:
    """Returns [line] with any `//` comment removed, ignoring `//` inside a string literal.

    Written character-wise rather than with a regex because the case that matters is a URL: a naive
    `s://.*//` turns `'https://example.com'` into `'https:'` and would hide a real reference sitting after it
    on the same line.
    """
    quote: str | None = None
    index = 0
    while index < len(line):
        char = line[index]
        if quote is not None:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = None
        elif char in "'\"":
            quote = char
        elif char == "/" and line.startswith("//", index):
            return line[:index]
        index += 1
    return line


def references() -> dict[str, list[str]]:
    """Every referenced key, mapped to the `file:line` sites that reference it."""
    found: dict[str, list[str]] = {}
    for path in sorted(LIB.rglob("*.dart")):
        # The generated localisations declare every getter, so they reference nothing and would otherwise
        # report every key as used — which would make --unused always empty and useless.
        if "l10n/generated" in path.as_posix():
            continue
        for number, raw in enumerate(
            path.read_text(encoding="utf-8").splitlines(), start=1
        ):
            for key in REFERENCE.findall(strip_comments(raw)):
                found.setdefault(key, []).append(f"{path}:{number}")
    return found


def declared() -> set[str]:
    """Every key in the ARB, excluding the `@`-prefixed metadata entries."""
    table = json.loads(ARB.read_text(encoding="utf-8"))
    return {key for key in table if not key.startswith("@")}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--unused",
        action="store_true",
        help="also list ARB keys nothing in lib/ references",
    )
    args = parser.parse_args()

    if not ARB.exists():
        print(f"no ARB at {ARB} — run from the repository root", file=sys.stderr)
        return 2

    used = references()
    have = declared()
    missing = sorted(set(used) - have)

    for key in missing:
        # Every site, not just the first. A key added to one screen and copied into three is three edits.
        print(f"MISSING  {key}")
        for site in used[key]:
            print(f"         {site}")

    if args.unused:
        for key in sorted(have - set(used)):
            print(f"unused   {key}")

    if missing:
        print(
            f"\n{len(missing)} key(s) referenced but not in the ARB — "
            f"`flutter gen-l10n` will generate no getter and the build will fail.",
            file=sys.stderr,
        )
        return 1

    print(f"{len(used)} referenced key(s), all present in {ARB}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
