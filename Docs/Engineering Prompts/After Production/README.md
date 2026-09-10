# Alaya — maintenance bundles

Alaya is 478 files and 84,764 lines across 19 bundles. **You never upload all of it.**

## Start here

Send **`ARCH_M_MAINTENANCE.md` alone** with what you want to do. It routes the change and tells you which
bundles to upload. The prompt to open with is in ARCH_M §9.

```
ARCH_M_MAINTENANCE.md   ->  "upload B3_DOMAIN, F_EXPENSE, ARB"  ->  you upload those three
```

## What is here

| File | |
|---|---|
| `ARCH_M_MAINTENANCE.md` | **The routing layer.** Read alone, first |
| `PROMPTS.md` | **Copy-paste prompts** for every kind of change. Start here in practice |
| `B*.md`, `F*.md`, `ARB.md` | The bundles. Upload only what ARCH_M names |
| `make_bundles.py` | Regenerates bundles from the repo. Copy to `tool/` |
| `_manifest.json` | Every bundle's file list, for mechanical regeneration |

## The bundles

| Bundle | Files | Lines |
|---|---|---|
| `B1_CORE` | 31 | 2,707 |
| `B2_SCHEMA` | 46 | 8,470 |
| `B3_DOMAIN` | 64 | 10,296 |
| `B4_DATA` | 47 | 8,672 |
| `B5_APP` | 19 | 3,173 |
| `B6_SHARED` | 32 | 3,860 |
| `B7_TESTKIT` | 17 | 4,712 |
| `B8_ANDROID` | 2 | 205 |
| `F_EXPENSE` | 38 | 6,466 |
| `F_INVENTORY` | 24 | 4,042 |
| `F_SHOPPING` | 17 | 2,925 |
| `F_RECURRING` | 19 | 3,246 |
| `F_SERVICE` | 20 | 4,187 |
| `F_DASHBOARD` | 16 | 2,132 |
| `F_CALENDAR` | 9 | 1,863 |
| `F_ANALYTICS` | 24 | 4,723 |
| `F_SETTINGS` | 38 | 7,325 |
| `F_OPS` | 14 | 2,517 |
| `ARB` | 1 | 3,243 |

## After you apply a change

```bash
cp make_bundles.py tool/
python3 tool/make_bundles.py F_EXPENSE     # just the bundles you touched
```

**A stale bundle is worse than no bundle**, because it looks authoritative while describing code that no longer
exists — the same failure as writing against a remembered API, one level up.

## Also keep alongside these

`ARCH_1_FOUNDATION.md` · `ARCH_2_DATABASE.md` · `ARCH_3_SUBSYSTEMS.md` · `ARCH_4_DECISIONS.md` ·
`ARCH_5_UIUX.md` — the binding architecture. ARCH_M tells you which of them a given change needs; usually one
or two, rarely all five.

The phase documents (`PHASE_*.md`) are **history, not reference**. They record why a decision was made. If a
change needs the reasoning behind something, they have it — but the bundles are what the code actually is.
