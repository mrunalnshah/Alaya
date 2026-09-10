# Alaya

**Your home, remembered.**

A record of a household — its money, its things, its food and its upkeep. Android, Flutter, entirely
offline, no account, no backend.

> Most money apps track what you spent. Alaya knows what you have.

---

## What it is

Expenses, inventory with expiry batches, recipes that read your kitchen and tell you what you can cook,
shopping lists, recurring bills, appliance warranties and service schedules, analytics, and a calendar over
all of it. Every feature works with no internet connection, and nothing leaves the device.

Full description: [`FEATURES.md`](FEATURES.md)

## How it is built

| | |
|---|---|
| **Flutter / Dart** | Android only, by choice |
| **drift over SQLite** | 30 tables, schema v3, forward-only step migrations from committed snapshots |
| **Riverpod** | Hand-written providers, no code generation |
| **go_router** | Declarative routes, one shell |
| **No backend** | There is no server component. There is nothing to run |

**Money is integer minor units. Quantity is integer milli-units.** No floating-point arithmetic exists
anywhere near a balance or a stock level.

**Layering is enforced by a lint**: `tool/check_layering.dart` fails the build if `features/` imports
`data/`. A plugin gets a port in `domain/services/` first.

~1,100 tests, four golden suites, and a layout gate that renders every screen at 320dp with double text
scale.

## The architecture documents

These are the source of truth, not the code:

| File | |
|---|---|
| `ARCH_1_FOUNDATION.md` | Laws, layering, the dependency table |
| `ARCH_2_DATABASE.md` | Schema, migrations, the snapshot discipline |
| `ARCH_3_SUBSYSTEMS.md` | Backup, lock, notifications, trash |
| `ARCH_4_DECISIONS.md` | Every decision, with the reason it was taken |
| `ARCH_5_UIUX.md` | Screen archetypes, the UI laws, motion |
| **`ARCH_M_MAINTENANCE.md`** | **How to change this app.** Read this first |

## Making a change

The codebase is ~85,000 lines across 19 bundles. `ARCH_M` routes a change to the three or four bundles it
needs, so no session ever loads the whole thing.

```bash
python3 tool/make_bundles.py        # regenerate after any change
```

Prompt templates for each kind of change: `PROMPTS.md`

## Building

```bash
flutter pub get
dart run build_runner build
flutter test
flutter run
```

Release builds, signing and the Play checklist: `PUBLISHING_FROM_SCRATCH.md` and
`PLAY_LISTING_CHECKLIST.md`.

## Licence

**All rights reserved.** See [`LICENSE`](LICENSE). This is proprietary source, not open source.

Third-party notices are surfaced in-app via `showLicensePage`.

---

© 2026 WildeWulf
