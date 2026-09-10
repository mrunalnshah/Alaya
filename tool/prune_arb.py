#!/usr/bin/env python3
"""Removes the ARB keys my UI changes orphaned.

Seven keys, all superseded during the recipe and UI rounds: a label replaced by a better question, a hint
that stopped applying when the field changed, a suffix for a unit no longer shown. `flutter gen-l10n` does
not mind an unreferenced key, so none of this is urgent — but a string table that describes screens which no
longer exist is the same class of fault as a stale bundle.

Verifies each key is genuinely unreferenced in lib/ before deleting it, so a key I mis-listed survives.
"""

import json
import re
import collections
from pathlib import Path

ORPHANED = [
    'labelDensity',
    'densityHelp',
    'suffixGramsPerMl',
    'recipeAmountHint',
    'recipeSpoonsNeedWeight',
    'recipeQuantityHint',
    'recipeAmountHintVessel',
]

arb_path = Path('lib/app/l10n/app_en.arb')
arb = json.loads(arb_path.read_text(), object_pairs_hook=collections.OrderedDict)

referenced = set()
for dart in Path('lib').rglob('*.dart'):
    referenced |= set(re.findall(r'strings\.(\w+)', dart.read_text()))

removed, kept = [], []
for key in ORPHANED:
    if key in referenced:
        kept.append(key)
        continue
    arb.pop(key, None)
    arb.pop('@' + key, None)
    removed.append(key)

arb_path.write_text(json.dumps(arb, indent=2, ensure_ascii=False) + '\n')

print(f'removed {len(removed)} keys: {", ".join(removed) or "none"}')
if kept:
    print(f'KEPT {len(kept)} — still referenced, so my list was wrong: {", ".join(kept)}')
print(f'{len([k for k in arb if not k.startswith("@")])} keys remain')