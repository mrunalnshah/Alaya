# Alaya · ARCH 1 — Foundation

**Attach this file to every prompt.** It is the smallest complete statement of the rules.

|                |                                            |
| -------------- | ------------------------------------------ |
| Project        | Alaya — Finance & Home Management          |
| Platform       | Android only                               |
| Flutter / Dart | 3.44.x / 3.12.x                            |
| Doc version    | 2.2 (UI/UX architecture split into ARCH_5) |
| Date           | 2026-08-01                                 |

---

## 1. The document set

Six files. Attach only what a phase needs — that is the whole point of the split.

| File | Contents | Attach to |
|---|---|---|
| **ARCH_1_FOUNDATION.md** | laws, vocabulary, core primitives, units, tech stack, folder structure | **every prompt** |
| **ARCH_2_DATABASE.md** | 31 tables, constraints, indexes, 11 views, ERDs | 1B, 1C, 2x, 3x, 7B |
| **ARCH_3_SUBSYSTEMS.md** | currency, app lock, backup, lifecycle, analytics, calendar, notifications, theme architecture | 4x, 6F, 7x, 8x |
| **ARCH_5_UIUX.md** | UI laws, visual language, screen archetypes, component contracts, interaction, accessibility, the data-surface coverage matrix, the two gates | **every prompt from 6A** |
| **ARCH_4_DECISIONS.md** | anomaly register, traceability, risks, open decisions | reference — rarely attached to code prompts |
| **PROMPTS.md** | phase plan, all ready-to-paste prompts, DoD, release checklist | your working file, never attached |

**From 6A onwards, ARCH_1 + ARCH_5 is the minimum attachment.** ARCH_1 governs the data and the
layering; ARCH_5 governs everything the user sees. Neither is sufficient alone, and a UI phase given
only ARCH_1 will invent its own design system in the first file it writes.

Every phase emits one markdown file: `PHASE_01A_CORE.md`, `PHASE_01B_DATABASE.md`, and so on.
Inside it, each source file appears as a path heading followed by one fenced block containing
the complete file.

---

## 2. The Laws

Non-negotiable. If generated code violates one of these, reject the file — do not patch it.

| ID | Law |
|---|---|
| **L1** | Money is `int` minor units + a currency code. `double` never **stores** money and never crosses a repository or DAO boundary. The single sanctioned contact is `Money.convert`, which takes a `double` FX rate and returns `int` minor units through `MoneyRounding`. |
| **L2** | Quantity is `int` milli-base-units + a unit category. `double` never touches quantity. |
| **L3** | No total is ever stored. Balances and stock levels are derived from ledgers. Sole exception: `inventory_batches.remainingQuantityMilli`, an explicitly-labelled cache with a `recompute()` repair path. |
| **L4** | Instants are `INTEGER` epoch millis **UTC**. Civil dates are `INTEGER` `yyyymmdd` (`DateKey`). Drift's `DateTime` column type is never used. |
| **L5** | Primary keys are `TEXT` UUIDv7, generated in Dart. No autoincrement anywhere. |
| **L6** | Nothing is hard-deleted except by the purge job. Every user-facing table has `deletedAt`. Sole exception: `stock_movements`, which is append-only and corrects by reversal. |
| **L7** | Repositories read from **views**, never base tables, so `deletedAt IS NULL` cannot be forgotten. |
| **L8** | An Item's `unitCategory` is immutable after creation. Cross-category conversion does not exist. |
| **L9** | `originalAmountMinor` + `originalCurrencyCode` are immutable once saved. Conversion is display-layer or an explicit frozen snapshot — never a rewrite. |
| **L10** | Exactly one function opens the database (`open_database.dart`). No conditional open logic, no second path. |
| **L11** | A failed network call never blocks a write. The app is fully functional offline, forever. |
| **L12** | `domain/` imports nothing from `data/`, `drift/`, or `flutter/`. Direction is `features → domain → core` and `data → domain → core`. |
| **L13** | Enum *names* are a schema contract. Renaming a Dart enum value is a breaking migration. All DB enums are `TEXT` via a fallback-safe converter. |
| **L14** | Every write touching two tables happens inside one drift `transaction {}`. |

**From Phase 6A there is a second numbered series.** ARCH_5 §1 declares UI Laws **U1–U20**, binding
on every phase from 6A and citable the same way. They do not overlap with L1–L14: the L-series
governs what is stored and how the layers depend on each other, the U-series governs what reaches
the screen. Where they touch — L11's "a failed network call never blocks a write" and U12's "nothing
in the UI awaits the network" — they say the same thing from either side of the boundary, which is
deliberate.

### 2.1 On storage security

**The database is plaintext.** No SQLCipher, no SQLite3MultipleCiphers, no `PRAGMA key`.
The PIN is an **app lock** — a UI gate, not a cryptographic boundary. Two consequences that
must be honoured in code:

1. **`android:allowBackup="false"` is mandatory.** Android's default auto-backup would
   otherwise upload the plaintext financial database to the user's Google Drive. This is the
   single most important line in the manifest. See ARCH_3 §2.4.
2. Setup copy must not overstate protection. The lock deters someone picking up an unlocked
   phone. It does not protect against a rooted device or physical extraction. Android's own
   device encryption still protects the file while the phone is locked.

---

## 3. Canonical vocabulary

Every prompt, table, class and UI label uses these words and only these words. Loose
vocabulary is how data models rot.

### 3.1 Money side

| Concept | Means | Does **not** mean |
|---|---|---|
| **Account** | A container holding money, with a balance. `Cash in hand`, `HDFC Savings`, `Paytm Wallet`. Exactly one currency. | A payment app, a category |
| **PaymentMethod** | The rail money travelled on: `Cash`, `UPI`, `Card`, `Bank Transfer`, `Cheque`. Metadata only, no balance. | A place money lives |
| **Payee** | The counterparty. Used for both `From` (deposits) and `To` (withdrawals). | A category |
| **Transaction** | One movement of money. | A purchased thing |
| **TransactionLine** | One purchased thing inside a transaction. | A transaction |
| **Tag** | A free user-defined label, scoped by which modules may use it. | A structural type |
| **Subtype** | The closed structural flow type that decides which form appears and which analytics bucket it lands in. | A tag |

`TransactionKind` — `deposit`, `withdrawal`, `transfer`, `adjustmentIncrease`, `adjustmentDecrease`

`TransactionSubtype` — `grocery`, `household`, `electronics`, `bill`, `transferSelf`,
`transferOut`, `salaryIn`, `otherIn`, `otherOut`

> **Why both `subtype` and `tags`.** `subtype` is a closed enum because it *changes the UI
> form* and must be stable for analytics. `tags` are open because you cannot enumerate what
> a user in Ahmedabad, Osaka and Lisbon will call things. They are not redundant.

### 3.2 Stuff side

| Concept | Means | Example |
|---|---|---|
| **Item** | The *kind* of consumable thing. Identity = `(normalizedName, unitCategory)`. Holds threshold + display preference. | `Potato (weight)` |
| **Batch** | One acquisition of an Item: quantity, expiry, cost, source. | `2 kg bought 12 Jul, exp 20 Jul, ₹60` |
| **StockMovement** | An immutable event changing a Batch's remaining quantity. | `consume 100 g` |
| **Asset** | A durable, serviceable, non-consumable thing **or person**. Warranty, service history, disposal. | `LG TV`, `Maid — Kamla` |
| **ServiceRecord** | One service / repair / payment event against an Asset. | `AC gas refill ₹1,800` |
| **RecurringTemplate** | A repeating obligation or income, either direction. | `Netflix ₹649/mo`, `Salary ₹65,000/mo` |
| **RecurringOccurrence** | One dated instance: `due` / `paid` / `skipped` / `dismissed`. | `Netflix — 05 Aug — paid` |
| **ShoppingEntry** | An intent to buy. May or may not link to an Item. | `Shampoo 2 pc ☐` |

### 3.3 The three ledgers

Alaya has exactly three append-only truths. Everything else is a projection.

```
1. transactions + transaction_lines   ->  all money
2. stock_movements                    ->  all physical stock
3. recurring_occurrences              ->  all obligations
```

If a number on screen is not derivable from one of these three, it is a bug.

---

## 4. Core primitives

Four value objects. Phase 1A exists as its own phase because every later file inherits these.

### 4.1 `Money`

```dart
final class Money {
  final int minor;            // paise / cents. Never a double. (L1)
  final String currencyCode;  // 'INR'
}
```

- Arithmetic between different currencies **throws**. No implicit conversion, ever.
- `decimalDigits` comes from the `currencies` table, cached at startup. JPY = 0,
  INR/USD/EUR/CNY = 2. **Never hardcode `100`.**
- API: `Money.zero(code)`, `+`, `-`, `*int`, unary `-`, `abs`, `isNegative`, `compareTo`.
- Rounding exists in exactly one place: `Money.convert(rate, to, rounding)`, default
  `MoneyRounding.halfUp`. Nowhere else in the app rounds money.
- User input goes through `MoneyParser` (locale-aware separators — `1.234,56` in EU locales,
  `1,234.56` in `en_IN`), returning `Result<Money, ParseFailure>`. It never throws while
  someone is typing.

### 4.2 `Qty`

```dart
final class Qty {
  final int milliBase;          // base unit x 1000  (g / ml / pc)
  final UnitCategory category;  // weight | volume | count
}
```

- `2 kg` → `2_000_000`. `250 g` → `250_000`. `0.5 pc` → `500`.
- Arithmetic across categories **throws** (L8). There is no gram↔ml.
- Conversion within a category uses `units.factorToBaseMilli`, an integer. Integer in,
  integer out. No float appears at any point.

**Why ×1000.** Plain grams would satisfy every example in the spec, then fail the first time
someone records half a pumpkin or 0.5 g of saffron — at which point it is a migration
touching every quantity in the database. The factor costs nothing today.

### 4.3 `DateKey`

```dart
extension type const DateKey(int value)   // yyyymmdd, local civil date
```

- `20260728`. `monthKey` = `value ~/ 100` = `202607`.
- Every user-meaningful *date* (due, expiry, purchase) is a `DateKey`.
- Every *instant* (`createdAt`, `occurredAt`) is epoch millis UTC.
- **Sorting:** `DateKey` cannot declare `implements Comparable<DateKey>` — an extension type may
  only implement supertypes of its representation type, and `int` implements `Comparable<num>`.
  So `compareTo` is a plain method and the zero-argument `List.sort()` is unavailable. Sort with
  the static comparator: `dates.sort(DateKey.compare)`. Every phase that orders dates in Dart
  must use it (SQL `ORDER BY date_key` is unaffected, and is the preferred path anyway per L7).
- **SQL comparisons:** for the same reason — `DateKey` is not an `int` — it cannot be passed to
  drift's `isBetweenValues`, `isSmallerOrEqualValue` or the other range helpers, which take a
  column's *SQL* type even when a type converter is attached. Use the
  `DateKeyColumnFilters` extension from `lib/data/db/date_key_filters.dart`:
  `isInDateRange(from, to)`, `isDateOnOrBefore(d)`, `isDateOnOrAfter(d)`, `isDateBefore(d)`,
  `isDateAfter(d)`, `isOnDate(d)`. It crosses the `DateKey` → `int` boundary once, rather than
  leaving a `.value` unwrap at every date filter in 2B, 2C, 4C and 7B. `month_key` is `yyyymm`,
  has no wrapper type, and is compared with plain ints.

  Both of these are the design working, not friction to route around. The reason `DateKey` refuses
  to be an `int` is that `dateKey + 1` must not compile — `20260731 + 1` is not a date.

**Why both.** A bill "due on the 5th" is a civil date — it is the 5th regardless of timezone.
Store it as an instant and a user flying Ahmedabad → London sees rent due on the 4th. Store
an audit timestamp as a civil date and you cannot order events. Conflating the two is the
most common date bug in finance apps, and it is why L4 bans drift's `DateTime` column type
outright (drift maintains an entire migration guide about that fallout).

### 4.4 `Uid`

UUIDv7 (`uuid` package), `TEXT` primary keys, generated in Dart.

**Why not autoincrement.** Backup, restore and merge. The moment a user restores onto a
second device or merges an older backup, integer IDs collide and silently reattach rows to
the wrong parents. UUIDs are what make **Merge restore** possible at all (ARCH_3 §3).

### 4.5 Enum storage

All DB enums stored as `TEXT` via a shared `SafeEnumConverter<T>` that maps unknown strings
to a declared fallback member instead of throwing. Two reasons: the backup file stays
human-readable (`"grocery"` beats `3`), and a bundle from a newer app version degrades
gracefully. Per L13, **never rename an enum value.**

---

## 5. Units & formatting

### 5.1 Categories — three, fixed forever

| Category | Base | Display rule | Example |
|---|---|---|---|
| `weight` | gram | `kg + g` when ≥ 1000 g | `4450 g → "4 kg 450 g"` |
| `volume` | millilitre | `L + ml` when ≥ 1000 ml | `1200 ml → "1 L 200 ml"` |
| `count` | piece | never broken down | `3 pc` |

### 5.2 Formatter contract

`QtyFormatter.format(Qty, {UnitStyle style, Locale locale})`:

- `mixed` → `4 kg 450 g` — item rows, batch chips. **Default.**
- `compact` → `4.45 kg` — dense chart axes and narrow chips only.
- `base` → `4450 g` — debug and export.

Zero-part suppression: `2000 g` → `2 kg`, never `2 kg 0 g`. Sub-base: `500` milliBase in
`count` → `0.5 pc`. Negatives never occur — movements are positive quantities with a `kind`.

### 5.3 User-defined units

A user unit is `(code, category, factorToBaseMilli, displayName)`. `dozen = 12 pc` →
`factorToBaseMilli = 12_000`. If the user cannot state a factor — "1 packet of noodles" —
the correct action is a **new Item**, and the UI says exactly that. Three categories exist
and no fourth will be added; that constraint is what keeps `Qty` arithmetic total and L8
enforceable.

### 5.4 Item display vs batch display

The spec contradicts itself here (see ARCH_4 A21). The resolution satisfies both statements:

- **Item row** shows the summed mixed-unit total: `4 kg 450 g`.
- **Expanding the item** shows the individual batches with their expiries: `2 kg · exp 20 Jul`,
  `250 g · exp 02 Aug`.

Every operation acts on batches. Display sums. Note the spec's own example arithmetic is
wrong — `250 + 2000 + 1500 + 700 = 4450 g` displays as **4 kg 450 g**, not 2 kg 450 g. That
is precisely why the formatter must be pure-computed and is a required test case in Phase 1A.

---

## 6. Layering & folder structure

Direction, enforced by lint (L12):

```
features/  ->  domain/  ->  core/
data/      ->  domain/  ->  core/
```

`domain/` has **zero** imports of `flutter/`, `drift/` or `data/`. It is pure Dart, so every
business rule is unit-testable without a device or an emulator.

**`features/` has zero imports of `data/` either, and 8A/8B made that structural.** Any service that is a
`final class` or reaches a plugin now sits behind a contract in `domain/services/`, with the provider in
`app/providers/` typed as the contract. Seven exist: `lock/app_lock.dart`, `lock/biometric_gate.dart`,
`backup/data_transfer_port.dart`, `attachments/attachment_port.dart`, `reminders/reminder_port.dart`,
`trash/trash_port.dart`, `support/support_port.dart`.

The reason is not tidiness. `PinService`, `BackupService` and `RestoreService` are declared `final class`, so
in Dart 3 they can be neither extended nor implemented outside their own library — **a test fake is
impossible**. Add platform channels for seven plugins and ARCH_5 §9.1's four-states-per-screen gate was
unreachable by any route.

**Rule for later phases: a new plugin gets a port before it gets a caller.** If a screen needs to name a type
from `data/`, move the type to `domain/` and put the implementation behind a contract. `UnlockOutcome`,
`UnlockRefusal`, `BackupArtefact` and `RestoreMode` moved for exactly that reason.

```
lib/
  main.dart
  app/
    app.dart, bootstrap.dart
    providers/       infrastructure_providers.dart  <- database, DAOs, clock, uid, logger
                     repository_providers.dart      <- one per domain contract
                     service_providers.dart         <- the engines
    router/          app_router.dart, routes.dart, placeholder_screen.dart
                     shell destinations inside ShellRoute; every detail and editor
                     route OUTSIDE it, so it gets a back arrow (ARCH_5 U18)
    theme/           tokens/          alaya_spacing, alaya_radii, alaya_durations,
                                      alaya_typography, alaya_elevation, alaya_icon_size
                     palettes/, semantic_colors.dart, alaya_theme.dart
    l10n/            app_en.arb, l10n.yaml at the project root
                     generated/  <- `flutter gen-l10n` output; never hand-edited
  core/
    ids/             uid.dart
    time/            date_key.dart, clock.dart
    money/           money.dart, money_parser.dart, money_formatter.dart, rounding.dart
    quantity/        qty.dart, unit_category.dart, unit_converter.dart, qty_formatter.dart,
                     qty_parser.dart
    text/            normalizer.dart
    result/          result.dart, failure.dart
    enums/           all shared enums + safe_enum_converter.dart
    logging/         logger.dart
  data/
    db/
      alaya_database.dart
      tables/        meta, tags, money, inventory, shopping, recurring, service, ops
      views/         *.drift
      indexes.drift
      fts.drift
      converters/
      migrations/    migration_strategy.dart, schema/
      seed/          seed_data.dart
      connection/    open_database.dart          <- the ONLY open path (L10)
    daos/            one per aggregate
    repositories/    concrete impls of domain contracts
    security/        app_lock_store.dart, pin_service.dart, recovery_code.dart,
                     secure_key_value_store.dart
    remote/          currency_api_client.dart, network_policy.dart
    backup/          backup_service.dart, restore_service.dart
  domain/
    entities/        pure models
    repositories/    abstract contracts
    services/        unit, currency, recurring, stock, suggestion, calendar,
                     balance, analytics/
  features/
    dashboard/ expense/ inventory/ shopping/ recurring/ service/
    analytics/ calendar/ settings/ security/ support/ onboarding/
      presentation/  screens/, widgets/   <- feature-local widgets only
      providers/     view-model and screen-state providers ONLY (ARCH_5 U19).
                     Never a repository or engine provider — those live in app/providers/.
      state/         immutable screen-state classes
  shared/
    widgets/         AlayaCard, AmountText, QtyText, DateText, EmptyState, ErrorState,
                     LoadingState, TagChip, StatusChip, KeyValueRow, SectionHeader,
                     ConfirmSheet, ShakeOnError, AlayaBottomSheet, ScrollSafeCenter,
                     AlayaFormScaffold, AlayaListSkeleton, AlayaSearchField,
                     FilterChipBar, AlayaExpandableFab, AlayaDrawer,
                     DatePickerField, AmountField, QtyField, UnitPicker, TagPicker,
                     AccountPicker
    feedback/        undo_snack.dart
```

A widget in `shared/` is used by two or more features. One used by a single feature belongs in that
feature's `presentation/widgets/`. ARCH_5 §8 lists what each phase is permitted to add to `shared/`;
anything beyond that is recorded in ARCH_4 §5.1 before it is written.

---

## 7. Tech stack

**Add each package in the phase that first imports it — not up front.** Every plugin in
`pubspec.yaml` is configured by Gradle on *every* build whether any Dart code imports it or
not, so front-loading all 23 phases' plugins means ~20 chances to fail the build before one
line of early-phase code runs. The "Added in" column is binding; §7.4 explains how to add.

| Concern | Package | Version | Added in |
|---|---|---|---|
| Format | `intl` | resolver | **1A** |
| IDs | `uuid` | resolver, 4.x+ for `v7()` | **1A** |
| Lints | `very_good_analysis` | resolver | **1A** (dev) |
| DB | `drift` | resolver, must land ≥ 2.34.2 | **1B** |
| DB codegen | `drift_dev`, `build_runner` | resolver | **1B** (dev) |
| DB helper | `drift_flutter` | resolver | **1C** |
| SQLite | `sqlite3` | resolver, 3.x bundles SQLite via build hooks | **1C** |
| HTTP | `dio` | resolver | **4A** |
| Lock storage | `flutter_secure_storage` | resolver | **4C** |
| PIN hashing | `cryptography` | resolver, PBKDF2-HMAC-SHA256 | **4C** |
| Zip | `archive` | resolver | **4C** |
| Files | `path_provider`, `share_plus` | resolver | **8A** |
| Files — SAF | **NO PACKAGE.** `lib/data/platform/saf_channel.dart` over `android/.../com/alaya/saf/SafPlugin.kt` | in-project | **8B** |
| Notifications | `flutter_local_notifications`, `timezone`, `workmanager` | resolver | **8B** |
| Monetisation | `google_mobile_ads` (resolver + UMP consent), `in_app_purchase` | resolver | **8B** |
| Localisation | `flutter_localizations` | `sdk: flutter` | **5** |
| State | `flutter_riverpod` | **^3.4.1** (pinned) | **5** |
| Routing | `go_router` | resolver | **5** |
| Calendar UI | `table_calendar` | resolver | **7A** |
| Charts | `fl_chart` | resolver | **7B** |
| Biometric | `local_auth` | resolver | **8A** |
| Notify | `flutter_local_notifications`, `timezone`, `workmanager` | resolver | **8B** |
| Ads | `google_mobile_ads` | resolver + UMP consent | **8B** |
| Billing | `in_app_purchase` | resolver, one-time tip | **8B** |
| Anim | `flutter_animate` | resolver, optional | **9** |

"resolver" means **do not write a version by hand** — run `flutter pub add <pkg>` and let it
write the current constraint. Providers and routes are hand-written; there is no Riverpod or
go_router codegen (§7.3).

`drift` is listed as "resolver, must land ≥ 2.34.2" rather than pinned: `flutter pub add drift`
writes `^current`, and since 2.34.2 shipped in July 2026 anything current already clears that
floor. Verify once with `flutter pub deps | grep drift` rather than typing a constraint.

**Why `drift_flutter` and `sqlite3` are 1C, not 1B.** Phase 1B's 14 files import exactly one
third-party package, `drift` — the table DSL. `driftDatabase()` and the bundled SQLite binary are
only touched by `open_database.dart`, which is Phase 1C. Deferring them means Phase 1B is
verifiable entirely through `build_runner` and `dart test`, with **no Android build involved at
all**: a schema mistake surfaces in codegen in seconds instead of behind a four-minute Gradle
failure. That is the single most useful consequence of §7.4's rule 2.

**`file_picker` MUST NEVER BE ADDED. Confirmed in 8B, not hypothetical.** `flutter pub add file_picker`
resolves to **3.0.4 (2020)** under §7.3's analyzer cap; its `android/build.gradle` calls `jcenter()`, shut
down in 2021. `pub get` succeeds, `dart analyze` is clean, `flutter test` passes, and `assembleDebug` fails.
8B replaced it with the SAF platform channel this section itself recommended — `ACTION_OPEN_DOCUMENT` and
`ACTION_CREATE_DOCUMENT`, no permission and no pub dependency. Removing it also dropped `dbus`, `ffi`,
`win32`, `web` and `flutter_web_plugins`.

**`image_picker` is pinned nowhere, so camera capture does not exist.** Attachments choose an existing image
through the SAF channel. Adding capture needs a row in §7's table first. Open decision as of Phase 9.

**Gradle coordinates are outside §7.4's scope.** §7.4 governs `pub`, which has `flutter pub add`; Gradle has
no equivalent. Exactly one is hand-written, in `android/app/build.gradle.kts`:
`com.android.tools:desugar_jdk_libs:2.1.4` — required because `flutter_local_notifications` uses `java.time`
and the AAR metadata check refuses the build without desugaring enabled. **Do not add `play-services-ads`**;
`google_mobile_ads` brings the version it is tested against, and a second hand-pinned one produces a runtime
`NoSuchMethodError` rather than a build error.

Original 4C note, retained: `file_picker`'s dependency set includes `dbus`, `ffi`, `win32`, `web` and
`flutter_web_plugins` — desktop and web surface this Android-only app never uses. Evaluate at
4C whether a small SAF platform channel is preferable to the whole plugin.

### 7.1 Packages that must NOT appear

| Package | Why |
|---|---|
| `sqlcipher_flutter_libs` | Obsolete — 0.7.0 is a deliberate no-op. Also irrelevant now: no encryption. |
| `sqlite3_flutter_libs` | Superseded by `sqlite3` 3.x build hooks. Adding it breaks the build. |
| `moor` / `moor_flutter` | Renamed to drift years ago. |
| `riverpod_generator` / `riverpod_annotation` | **Cannot resolve.** `riverpod_generator ^4.0.6` requires `analyzer ^13.0.0`, which no resolvable `test` version allows on this SDK — see §7.3. |
| `go_router_builder` | Same failure class: another `analyzer` constraint competing with `drift_dev`'s. Typed routes aren't worth the resolution risk. |
| Any crash/analytics SDK | Violates the network allowlist (ARCH_3 §1.4). |

Run `flutter pub deps | grep -i sqlite` after the first `pub get` and confirm neither libs
package is pulled in transitively. There is **no** `hooks:` block needed in `pubspec.yaml` —
that was only for encryption, which we no longer use.

### 7.2 Android

Verified against the real project, 2026-07-28: Kotlin 2.3.20, AGP 9.0.1, **Gradle 9.1.0**
(the wrapper's actual version — an earlier draft of this document said 9.6.1; 9.1.0 clears
AGP 9.0.1's Gradle 9.0 floor, so either works), JDK 17.
`android.builtInKotlin=false` and `android.newDsl=false` are both set and stay as-is.
**No feature prompt edits any Gradle file.**

`compileSdk`, `targetSdk`, `minSdk` and the version fields are delegated to `flutter.*` in
`app/build.gradle.kts` rather than hardcoded, which is correct and should stay that way. Note
this means `minSdk` follows Flutter's default rather than the **26** this document targets — if
26 is a hard requirement (adaptive icons, `java.time`), set `minSdk = 26` explicitly. Nothing
in phases 1A-9 needs more than Flutter's default, so this is a deliberate choice to make, not
a defect.

Two manifest requirements, both consequences of the plaintext database. **These ship in
Phase 1A, not Phase 8B** — the database arrives in Phase 1B, so the window where a debug build
could be auto-backed-up to Drive opens one phase from now:

```xml
<application
    android:allowBackup="false"
    android:dataExtractionRules="@xml/data_extraction_rules"
    android:fullBackupContent="false"
    ... >
```

`allowBackup="false"` is not optional. See ARCH_3 §2.4.

### 7.3 The one-codegen rule

**Exactly one `build_runner` codegen package may be in this project: `drift_dev`.** This is
not a style preference — a second one does not resolve. The chain, verified against a real
`pub get` failure:

```
flutter_test (SDK)  hard-pins  test_api = 0.7.11  and  matcher = 0.12.19
  -> the only `test` versions satisfying both are [1.29.0, 1.31.1)
  -> those require                                analyzer < 13.0.0
  -> flutter_riverpod -> riverpod -> test ^1.0.0  (a RUNTIME dep, so this cap is global)
  -> therefore NOTHING in the graph may require   analyzer ^13.0.0
```

`riverpod_generator ^4.0.6` requires exactly that, so it can never resolve here. When it is
present, pub exhausts every modern `test`, falls back to a pre-null-safety `test` needing
`io ^0.3.0`, and finally reports a confusing collision with `drift_dev`'s `io ^1.0.3` — which
makes `drift_dev` look like the problem when it is the victim.

`drift_dev` wins the single slot because the 31-table schema, all 11 views and every DAO are
generated; without it there is no data layer. The other two are sugar:

| Dropped | Replaced by | Cost |
|---|---|---|
| `riverpod_generator` + `riverpod_annotation` | Hand-written `Provider` / `NotifierProvider` / `StreamProvider` declarations | Slightly more verbose. `@riverpod` is never used anywhere in this codebase. |

**The hand-written Riverpod shapes this project actually resolves to — verified against the analyzer,
not against release notes.** `flutter_riverpod` is pinned at `^3.4.1` (§7's table), but the API present
in the resolved package is the **family-notifier** shape: `AutoDisposeFamilyNotifier`, with the family
argument arriving as a `build` parameter and a **zero-argument** factory.

```dart
final p = NotifierProvider.autoDispose.family<MyNotifier, MyState, String?>(MyNotifier.new);

class MyNotifier extends AutoDisposeFamilyNotifier<MyState, String?> {
  @override
  MyState build(String? arg) => ...;
}
```

Riverpod 3.0's published migration guide describes fusing `Notifier`, `FamilyNotifier`,
`AutoDisposeNotifier` and `AutoDisposeFamilyNotifier` into one `Notifier` and moving the argument to the
constructor. **Writing that shape here does not compile** — it fails with *"doesn't conform to the bound
'AutoDisposeFamilyNotifier'"* and *"'Function(String?)' can't be assigned to 'Function()'"*. Phase 6A
made exactly that mistake, from reading the changelog instead of checking the installed package.

**The rule this establishes: the bound the compiler reports is the authority on which API is present.**
Before changing a provider or notifier shape on the strength of a version note, write one and let
`dart analyze` say which it wants.
| `go_router_builder` | Hand-written `GoRoute`s + path constants and typed helper functions centralised in `routes.dart` | Route params lose compile-time checking. Mitigated by never writing a path literal outside `routes.dart`. |

Two side benefits worth naming: build times drop noticeably across 23 phases with only one
generator running, and dropping `@riverpod` **reduces** the Riverpod 4.0 migration risk that
motivated confining Riverpod to a bounded set of directories in the first place (L12). A 4.0
migration touches plain provider declarations in two known places, with no generated files to
regenerate and no annotation API that might change shape.

**Two places, decided in Phase 5.** The shared dependency graph — the database, the 21 DAOs, the
15 repositories and the engines — lives once in `app/providers/`. Feature-local providers, the
view-model and screen-state declarations, stay in `features/*/providers/`. Splitting it this way
*serves* the confinement goal rather than diluting it: the alternative is 6A, 6B and 6C each
declaring their own `itemRepositoryProvider`, which is how one repository ends up with three
providers and a caching resolver ends up constructed three times. Every provider in
`app/providers/` is typed as the **domain contract**, never the implementation, so a feature
cannot reach past the interface for a method the contract does not expose.

If a future phase seems to need a second generator (`freezed`, `json_serializable`, ...),
that is a schema-level decision — re-run the chain above first. The likely answer is to write
the boilerplate by hand.

### 7.3b Toolchain state — recorded because three 8B build failures came from here, and none from app code

| | |
|---|---|
| Flutter | 3.44.8 stable, Dart 3.12.2 |
| Gradle | **9.1.0** |
| AGP | **9.0.1** |
| `android.newDsl` | **`false`** in `gradle.properties`. Flutter's Gradle plugin is not AGP-9-new-DSL compatible |
| `android.builtInKotlin` | `false` |
| `repositoriesMode` | **`PREFER_SETTINGS`** — *not* `FAIL_ON_PROJECT_REPOS` |
| Flutter engine repo | Declared **at settings level**: `maven { url = uri("https://storage.googleapis.com/download.flutter.io") }` |

Flutter's Gradle plugin adds its engine artifact repository at **project** level. Under
`FAIL_ON_PROJECT_REPOS` the plugin cannot apply at all; under `PREFER_SETTINGS` it applies and its repository
is **silently ignored**, so `io.flutter:flutter_embedding_debug` becomes unresolvable. Declaring the engine
repo in `settings.gradle.kts` is what makes both work.

**Never re-add `allprojects { repositories { ... } }` to `android/build.gradle.kts`.** Under
`PREFER_SETTINGS` it silently shadows the settings-level declarations.

Android files now project-specific, beyond the manifest: `MainActivity.kt` (registers `SafPlugin` via the v2
embedding's `ActivityAware`; **base class deliberately unchanged**, since `local_auth` would want
`FlutterFragmentActivity` and that is a separate decision), `com/alaya/saf/SafPlugin.kt`,
`app/build.gradle.kts` (desugaring, per-build-type AdMob IDs, release signing), `build.gradle.kts`,
`settings.gradle.kts`, `gradle.properties`, and git-ignored `key.properties`.

Known non-blocking warning: `workmanager_android` applies the Kotlin Gradle Plugin, which future Flutter
versions will reject. **It is the only caller of `TrashPort.purgeExpired` and `ReminderPort.rescheduleAll`**,
so if an upgrade breaks it, thirty-day retention and the daily digest stop *silently*.

### 7.4 How to add a dependency

Two rules. Both were learned from real build failures, not from style preference.

**Rule 1 — never `any`, never a hand-typed version. Always `flutter pub add`.**

`any` has no floor. Pub prefers the newest version, but the moment a newer version creates
any friction it walks backwards — and pre-null-safety packages declare very loose bounds
(`sdk: '>=1.8.0 <3.0.0'`), so ancient releases are *easier* to satisfy than modern ones.
**This example stopped being illustrative in 8B — it happened, exactly as written.** See the prohibition in
§7 above.

`file_picker: any` silently resolved to **3.0.4, from 2020**, whose `android/build.gradle`
calls `jcenter()` — a repository shut down in 2021 and a method Gradle no longer has. `pub
get` reported success; the failure surfaced only at `assembleDebug`.

Hand-typing a version is the opposite failure: for a `0.x` package like `intl`, caret
semantics are tight (`^0.19.0` means `>=0.19.0 <0.20.0`), so a guess that is one minor
version stale fails to resolve outright.

```bash
flutter pub add intl uuid                 # writes ^<current> for each
flutter pub add --dev drift_dev build_runner
```

**Rule 2 — add it in the phase that first imports it (§7's "Added in" column).**

Gradle configures every plugin in `pubspec.yaml` on every build, imported or not. Phase 1A
imports exactly `intl` and `uuid`; it has no reason to make Gradle configure an ads SDK, a
notification scheduler and a file picker.

**Diagnosing a bad resolution.** `flutter pub deps` shows what actually resolved. If a plugin
fails to configure in Gradle, check its version first — a 4-year-old release is the signal,
and the fix is `flutter pub add <pkg>` to force a current floor, never a Gradle workaround.

### 7.5 Project bootstrap checks

These live in `android/` and are the project's own configuration, not something any phase
generates. Verify once, before Phase 1A builds:

`android/gradle.properties` — required by §7.2's AGP 9.0.1 / Kotlin 2.3.20 combination:

```properties
android.builtInKotlin=false
android.newDsl=false
```

Without `android.newDsl=false`, AGP 9 reads only the new DSL interface and fails when the
Flutter Gradle plugin is applied in `android/app/build.gradle.kts`. Both flags are flipped
deliberately in one dedicated pass later (risk R5), never by a feature phase.

**`pubspec.yaml` must contain `generate: true` under `flutter:`** — required from Phase 5, when the
ARB arrives:

```yaml
flutter:
  generate: true
```

Without it `flutter gen-l10n` fails outright with *"Attempted to generate localizations code without
having the flutter: generate flag turned on"*. This became mandatory in Flutter 3.32 and applies to
the pinned 3.44 (flutter#169209). It is a build flag rather than a dependency version, so §7.4's
no-hand-typed-versions rule does not cover it — and `gen-l10n` is a first-party command rather than a
`build_runner` package, so §7.3's one-codegen rule is intact.

`l10n.yaml` at the project root, and note what is **absent** from it:

```yaml
arb-dir: lib/app/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AlayaStrings
output-dir: lib/app/l10n/generated
nullable-getter: false
required-resource-attributes: false
```

`synthetic-package: false` is **deliberately not present**. That key is deprecated — Flutter is
withdrawing `package:flutter_gen` entirely, and an explicit `output-dir` is now the supported way to
generate into a real directory. Setting it produces a warning on 3.44 and will break on a later
release.

**Codegen order matters, and neither generator knows about the other:**

```bash
flutter pub get
flutter gen-l10n            # writes lib/app/l10n/generated/app_localizations.dart
dart run build_runner build # writes *.g.dart
dart analyze
```

`dart analyze` before `gen-l10n` reports every widget that reads a string as broken, exactly as it
reports every DAO as broken before `build_runner`. That is expected, not a defect — but it produced
twelve confusing errors in Phase 5 that looked like code faults.

### 7.6 Test-file import convention

**In a test file, import `package:drift/drift.dart` with an explicit `show` clause listing only
what that file uses.** Never import it bare alongside `flutter_test`.

Drift's query builder and `package:matcher` (re-exported by `flutter_test`) both declare top-level
names, and several collide outright:

| Name | drift | matcher |
|---|---|---|
| `isNull` | builds `IS NULL` in SQL | the null matcher |
| `isNotNull` | builds `IS NOT NULL` | the non-null matcher |

A bare import of both produces `ambiguous_import` on the *use site*, so the error points at
`expect(x, isNull)` and says nothing about the import that caused it — easy to misread as a
problem with the assertion.

```dart
// Correct — immune to any future collision, because nothing else is imported.
import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
```

A `show` clause beats `hide isNull, isNotNull` because it does not need updating when either
package adds a name. In practice a test needs very little from drift directly: `Value` for
nullable companion fields and `Variable` for `customSelect` parameters. Generated companions and
row classes come from the database file, not from drift, and `NativeDatabase` comes from
`drift/native.dart`, which does not re-export the query builder.

Check first whether the file needs drift at all — a test that only reads through generated
accessors and `NativeDatabase` needs no drift import whatsoever.


**Do not treat the AGP 9 "Flutter Fix" panel as a diagnosis.** `flutter run` prints it from a
generic heuristic whenever it sees AGP 9 together with *any* failed build — including builds
that failed for entirely unrelated reasons, and including projects that have already opted out
correctly. Confirm the flag's actual value in `gradle.properties` before acting on that panel.
It cost one wasted debugging round on this project.

---

## Phase 7A amendment

**§1 says "Six files"; there are seven.** `ARCH_6_CODE_INDEX.md` exists.

**§6 layering — a feature now imports another feature's providers.** `lib/features/dashboard` reads
`lib/features/calendar/providers/calendar_providers.dart` for `recurringHorizonProvider`,
`currentMonthProvider` and `calendarDayIndexProvider`, because one aggregator serves both screens and the
alternative is two code paths computing "what is coming" that will drift — which is exactly the defect 7A
retired. If this layering is disallowed, those three providers move to `lib/app/providers/`; the
feature-owned view-model providers stay where they are.

**Eight files are now shared across phase documents, not seven.** `lib/shared/widgets/alaya_expandable_fab.dart`
joins `app_router.dart`, `app_en.arb` and `layout_overflow_test.dart`. It is declared in PHASE_05 only, so
it has no cross-document duplication to keep in sync — but an edit to it is still an edit to a file every
phase depends on.
