#!/usr/bin/env python3
"""Regenerate Alaya's maintenance bundles from the working tree.

Run from the repo root:      python3 tool/make_bundles.py
One bundle only:             python3 tool/make_bundles.py F_EXPENSE

A bundle is a download set, not a partition — every file lands in exactly one, and the routing table in
ARCH_M §3 says which sets a given change needs. The bundles are a snapshot of the repo, so regenerate the
ones a change touched immediately after applying it. A stale bundle is worse than no bundle: it looks
authoritative and describes code that no longer exists.

`_manifest.json` records when each bundle was written, so `--stale` can answer "which of these no longer
match the tree" without opening any of them.
"""
import datetime
import hashlib
import json
import os
import sys

# Every extension worth bundling. **A file whose extension is missing here is invisible twice over**:
# `collect()` skips it, and the unbundled report at the bottom filters on this same table, so nothing
# warns. `.drift` was absent for the whole of Phase R and took six view files with it — including the
# authored definition of the read model Law L7 says every repository depends on.
LANG = {'.dart': 'dart', '.arb': 'json', '.kt': 'kotlin', '.kts': 'kotlin',
        '.xml': 'xml', '.pro': 'text', '.json': 'json', '.drift': 'sql',
        '.py': 'python'}

# Extensions deliberately not bundled. Listed rather than assumed, so the report below can tell
# "we decided not to" from "nobody has thought about it yet".
IGNORED_EXT = {
    '.png', '.jpg', '.jpeg', '.webp', '.gif', '.svg', '.ico',
    '.ttf', '.otf',
    '.md', '.yaml', '.yml', '.lock', '.txt', '.properties', '.gradle',
    '.jar', '.iml', '.sh', '.bat', '.g', '',
}

BLURB = {
    'B1_CORE': 'Money, Qty, DateKey, Result, ids, enums. No Flutter, no drift.',
    'B2_SCHEMA': 'Drift tables, converters, migrations, DAOs, and the .drift views and indexes. '
                 'Changing this changes the database.',
    'B3_DOMAIN': 'Entities, repository contracts, service contracts, pure engines.',
    'B4_DATA': 'Repository implementations, security, backup, platform channels.',
    'B5_APP': 'Router, providers, theme, bootstrap. The router imports every screen.',
    'B6_SHARED': 'The widget vocabulary.',
    'B7_TESTKIT': 'Harnesses, fakes, the layout-overflow suite, the layering checker, the tools.',
    'B8_ANDROID': 'MainActivity, the SAF platform channel, and the manifest.',
    'F_EXPENSE': 'Transactions, lines, tags, payees, ledger, editor.',
    'F_INVENTORY': 'Items, batches, stock movements.',
    'F_SHOPPING': 'Shopping lists, entries, convert-to-purchase.',
    'F_RECIPE': 'Recipes, ingredients, steps, the cookability engine and cooking.',
    'F_RECURRING': 'Recurring templates and occurrences.',
    'F_SERVICE': 'Assets, service records, warranties.',
    'F_SPLIT': 'Shared expenses, groups, balances, settling up, the shareable summary.',
    'F_DASHBOARD': 'Funds header, module grid, insight cards.',
    'F_CALENDAR': 'Calendar screen and day sheet.',
    'F_ANALYTICS': 'Analytics home, query surfaces, drill-down.',
    'F_SETTINGS': 'Settings tree and branches, onboarding, PIN, lock, recovery.',
    'F_OPS': 'Backup, restore, trash, reminders, attachments, Support Us.',
    'ARB': 'Every user-visible string.',
}

# A feature bundle is every path containing `/features/<name>/`, in lib and test alike.
FEATURES = {
    'F_EXPENSE': ['expense'], 'F_INVENTORY': ['inventory'], 'F_SHOPPING': ['shopping'],
    'F_RECIPE': ['recipe'], 'F_SPLIT': ['split'],
    'F_RECURRING': ['recurring'], 'F_SERVICE': ['service'], 'F_DASHBOARD': ['dashboard'],
    'F_CALENDAR': ['calendar'], 'F_ANALYTICS': ['analytics'],
    'F_SETTINGS': ['settings', 'lock', 'onboarding'],
    'F_OPS': ['backup', 'trash', 'reminders', 'attachments', 'support', 'ops'],
}

SOURCE_DIRS = ('lib', 'test', 'tool', 'android')


def bundle_of(path):
    """The one bundle a path belongs to, or None if it is not bundled."""
    p = path.replace(os.sep, '/')
    if p.endswith('app_en.arb'):
        return 'ARB'
    for name, feats in FEATURES.items():
        if any(f'/features/{x}/' in p for x in feats):
            return name
    if p.startswith('lib/core/') or p.startswith('test/core/'):
        return 'B1_CORE'
    if p.startswith(('lib/data/db/', 'lib/data/daos/', 'test/data/')):
        return 'B2_SCHEMA'
    if p.startswith('lib/domain/') or p.startswith('test/domain/'):
        return 'B3_DOMAIN'
    if p.startswith('lib/data/'):
        return 'B4_DATA'
    if p.startswith('lib/app/') or p == 'lib/main.dart':
        return 'B5_APP'
    if p.startswith('lib/shared/'):
        return 'B6_SHARED'
    if p.startswith(('test/shared/', 'test/support/', 'tool/')):
        return 'B7_TESTKIT'
    # **Everything Android that is source, not just Kotlin.** The manifest is the file that decides
    # whether notifications survive a reboot, whether the plaintext database is uploaded to Drive, and
    # which permissions the Play form has to declare — and it sat in no bundle for the project's whole
    # life because this rule tested the extension instead of the directory.
    if p.startswith('android/'):
        return 'B8_ANDROID'
    return None


def collect():
    found = {}
    for base in SOURCE_DIRS:
        if not os.path.isdir(base):
            continue
        for root, _, names in os.walk(base):
            # Build output is not source, and android/build alone is thousands of files.
            if any(part in root.split(os.sep) for part in ('build', '.dart_tool', '.gradle')):
                continue
            for n in names:
                path = os.path.join(root, n).replace(os.sep, '/')
                if os.path.splitext(n)[1] not in LANG:
                    continue
                if '.g.dart' in n or '.freezed.dart' in n:
                    continue  # generated; regenerated by build_runner, never hand-edited
                b = bundle_of(path)
                if b:
                    found.setdefault(b, []).append(path)
    return {k: sorted(v) for k, v in sorted(found.items())}


def digest(paths):
    """A hash of what a bundle would contain, so staleness is detectable without reading the .md."""
    h = hashlib.sha256()
    for p in paths:
        h.update(p.encode())
        with open(p, 'rb') as fh:
            h.update(fh.read())
    return h.hexdigest()[:16]


def report_gaps(groups):
    """Everything a future change would not be able to see.

    Two lists, because they are different mistakes. An **unbundled** file has an extension the script
    understands and no rule to place it — add one to `bundle_of`. An **unknown extension** is a file the
    script never even looked at, and it is the more dangerous of the two: nothing downstream can notice
    its absence, which is how `.drift` stayed invisible through nine phases.
    """
    unbundled, unknown = [], []
    for base in SOURCE_DIRS:
        if not os.path.isdir(base):
            continue
        for root, _, names in os.walk(base):
            if any(part in root.split(os.sep) for part in ('build', '.dart_tool', '.gradle')):
                continue
            for n in names:
                p = os.path.join(root, n).replace(os.sep, '/')
                ext = os.path.splitext(n)[1]
                if '.g.dart' in n or '.freezed.dart' in n:
                    continue
                if ext in LANG:
                    if not bundle_of(p):
                        unbundled.append(p)
                elif ext not in IGNORED_EXT:
                    unknown.append(p)

    if unbundled:
        print('\nUNBUNDLED — add a rule in bundle_of() for each:')
        for p in unbundled:
            print('   ', p)
    if unknown:
        print('\nUNKNOWN EXTENSION — add to LANG to bundle, or to IGNORED_EXT to say it is deliberate:')
        for p in sorted(unknown):
            print('   ', p)
    if not unbundled and not unknown:
        print('\nEvery source file is in a bundle.')


def main():
    only = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('-') else None
    stale_only = '--stale' in sys.argv
    out = 'bundles'
    os.makedirs(out, exist_ok=True)
    groups = collect()

    # **The previous manifest is loaded, not discarded.** Rewriting every entry while writing one file
    # made `_manifest.json` claim bundles were current when their `.md` had not been touched — the exact
    # trap that let a file be regenerated from a bundle two sessions out of date, silently reverting the
    # edits in between.
    manifest_path = os.path.join(out, '_manifest.json')
    manifest = {}
    if os.path.exists(manifest_path):
        try:
            with open(manifest_path, encoding='utf-8') as fh:
                manifest = json.load(fh)
        except (OSError, ValueError):
            manifest = {}

    if stale_only:
        print('Bundles whose files have changed since they were written:\n')
        any_stale = False
        for name, paths in groups.items():
            recorded = manifest.get(name, {}).get('digest')
            current = digest(paths)
            if recorded != current:
                any_stale = True
                when = manifest.get(name, {}).get('generated', 'never')
                print(f'  {name:14} STALE   last written {when}')
        if not any_stale:
            print('  none — every bundle matches the tree.')
        return

    now = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
    for name, paths in groups.items():
        if only and name != only:
            continue
        total = 0
        parts = []
        for p in paths:
            with open(p, encoding='utf-8') as fh:
                code = fh.read().rstrip('\n')
            total += len(code.splitlines())
            lang = LANG[os.path.splitext(p)[1]]
            parts.append(f'### `{p}`\n\n```{lang}\n{code}\n```\n')
        head = (f'# {name}\n\n{BLURB.get(name, "")}\n\n'
                f'**{len(paths)} files · {total:,} lines.**  Written {now}.\n\n'
                'Every file below is complete and current. Paths are destinations.\n\n---\n\n')
        with open(os.path.join(out, name + '.md'), 'w', encoding='utf-8') as fh:
            fh.write(head + '\n'.join(parts))
        manifest[name] = {
            'files': len(paths), 'lines': total, 'paths': paths,
            'generated': now, 'digest': digest(paths),
        }
        print(f'  {name:14} {len(paths):3} files {total:6} lines')

    # A bundle that no longer exists in the tree should not linger in the manifest claiming to.
    for gone in [k for k in manifest if k not in groups]:
        del manifest[gone]

    with open(manifest_path, 'w', encoding='utf-8') as fh:
        json.dump(manifest, fh, indent=1)

    if only:
        print(f'\nRegenerated {only} only. Run with --stale to see which others no longer match.')
    else:
        print(f'\n{len(groups)} bundles, {sum(m["lines"] for m in manifest.values()):,} lines.')

    report_gaps(groups)


if __name__ == '__main__':
    main()
