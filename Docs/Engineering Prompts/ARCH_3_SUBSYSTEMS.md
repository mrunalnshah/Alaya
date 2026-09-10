# Alaya · ARCH 3 — Subsystems

Eight subsystems that cut across features. Attach with ARCH_1 for phases 4x, 6F, 7x, 8x.

**§8 is now the theme *architecture* only.** Every rule about how a screen looks, behaves and is
tested moved to **ARCH_5_UIUX.md**, which is attached to every prompt from 6A. This file keeps the
file layout and the palette-as-data decision because those are structural; it no longer states
usage rules, because two documents stating them is how they drift.

---

## 1. Currency

### 1.1 Data source ladder

Verified live, July 2026. The `cdn.jsdelivr.net/gh/fawazahmed0/currency-api@1/...` URLs that
most tutorials still show are **dead** — the project moved to `fawazahmed0/exchange-api` on npm.

| Order | URL |
|---|---|
| 1 | `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json` |
| 2 | `https://latest.currency-api.pages.dev/v1/currencies/usd.min.json` |
| 3 | `https://api.frankfurter.dev/v2/rates?base=USD&quotes=INR,EUR,JPY,CNY` |

Historical rates: swap `@latest` for `@YYYY-MM-DD`, or use
`https://{YYYY-MM-DD}.currency-api.pages.dev/v1/currencies/usd.min.json`. Frankfurter's
equivalent is `?date=YYYY-MM-DD`.

Both are keyless and free. Frankfurter is ECB-backed, open source and self-hostable, which is
why it is the fallback rather than another community CDN.

### 1.2 Pivot design — one HTTP request per day, total

The fawazahmed0 endpoint for a base currency returns **every** quote in one file. So:

- Pivot on **USD**. One daily fetch of `usd.min.json` yields USD→INR, USD→EUR, USD→JPY and
  USD→CNY in a single response.
- All other pairs are **cross-rated locally**: `INR→JPY = (USD→JPY) / (USD→INR)`.
- `currency_rates` therefore only ever stores rows with `baseCode = 'USD'`.

One request per day for the entire app, forever. Frankfurter's response shape differs, so
`CurrencyApiClient` normalises both into the same `RateSnapshot` before caching — the cache
never knows which source it came from, only `source` for debugging.

### 1.3 Rules

1. **Fetch policy.** Once daily, opportunistically, on app foreground *if* a network already
   exists. Never on a blocking path, never before first frame.
2. **Failure policy.** A failed fetch is a no-op. Saving a transaction never awaits a rate (L11).
3. **Lookup rule.** For a transaction on `dateKey = D`, use the row with the **greatest
   `rateDateKey <= D`**. If none exists, use the earliest available row and mark the result
   `RateQuality.approximate`. Never interpolate, never extrapolate silently. This rule exists
   because Frankfurter has no weekend rows — an exact-date match would fail every Saturday.
4. **Missing rate.** The transaction is excluded from the converted headline total and
   contributes to an `unconvertedCount`, surfaced as a small chip: `+3 unconverted`.
5. **Home currency.** One setting, default from device locale, **display only**. Changing it
   rewrites nothing (L9).
6. **Explicit freeze.** The per-transaction "show me what ₹100 was in USD that day" writes
   `convertedAmountMinor`, `conversionRate`, `conversionRateRaw`, `conversionDateKey`. A
   separate, frozen artefact that is never recomputed.
7. `conversionRateRaw` stores the API's exact string. A `REAL` rate is fine for display, but
   the raw string means you can always reproduce a number a user questions.

### 1.4 Network allowlist

Enforced by one `NetworkPolicy` class that every HTTP call goes through. Three entries, total:

| Purpose | Host |
|---|---|
| Currency rates | `cdn.jsdelivr.net`, `*.currency-api.pages.dev`, `api.frankfurter.dev` |
| Rewarded ads | Google AdMob (Phase 8B) |
| Tip purchase | Google Play Billing (Phase 8B) |

Nothing else. No crash reporter, no analytics SDK, no font CDN, no image loader. If a package
wants a network call outside this list, it does not go in the app.

### 1.5 Service contract

The sketch this section originally carried was three-quarters right; Phase 4A implemented it and the
differences are worth recording, because two of them were the spec telling us something.

```dart
// domain/services/currency_rate_service.dart
Future<RateTable>       table();            // load once, convert many
Future<ConvertedMoney>  toHome({required Money amount, required DateKey on,
                                required String homeCurrencyCode});
Future<CrossRate?>      rateOn({required String from, required String to,
                                required DateKey on});
Future<void>            syncDailyRates();   // never throws, never blocks

// The pure part — no I/O, so the whole lookup rule is testable from literals.
class RateTable {
  RateLeg?       legFor({required String code, required DateKey on});   // §1.3 rule 3
  CrossRate?     crossRate({required String from, required String to, required DateKey on});
  ConvertedMoney convert({required Money amount, required String toCurrencyCode,
                          required DateKey on});                        // synchronous
}
```

**`toHome` was specified as synchronous, and that was a design instruction, not a slip.** A
synchronous conversion is only possible with the rates already in hand — so the rates live in an
in-memory `RateTable` loaded once, and `RateTable.convert` is the synchronous call. Converting a
month of transactions through a per-amount async path would have meant two cache round trips *per
amount*. The service's `Future<ConvertedMoney> toHome` is the single-amount convenience over it.

**`rateOn` returns `CrossRate?`, not `Money?`.** A rate between two currencies is a ratio; there is
no amount for a `Money` to hold. `CrossRate` carries the rate, the date actually used, and the
`RateQuality`, all of which the freeze action writes.

**`unconvertedCount()` is not on this service, and only half of it exists.** The count is inherently
a property of *whatever is being totalled*, not of the rate subsystem:

| Total | Where the count lives | Status |
|---|---|---|
| Net worth, over account balances | `BalanceService.NetWorth.unconvertedCount` | **implemented, Phase 4A** |
| Spend or income, over transactions | belongs with whatever aggregates transactions | **not implemented** — Phase 7B |

`CurrencyRepository.watchUnconvertedCount()` is a stub returning `Stream.value(0)` and is
deliberately still one: a real implementation must re-evaluate every active transaction's
convertibility whenever the rate cache changes, which is analytics work. Phase 7B should build it
over the same `RateTable` rather than inventing a second lookup path, and may then delete the stub.

---

## 2. App lock

**The database is plaintext (ARCH_1 §2.1).** The PIN is a UI gate. That makes this subsystem
dramatically simpler than a key-derivation design — and it changes what the setup copy is
allowed to claim.

### 2.1 Design

```
PIN            4 digits (6 optional in settings)
Stored         PBKDF2-HMAC-SHA256(pin, salt, 310_000) -> pinHash
               + salt, both in flutter_secure_storage
Recovery       a single 10-character code, base32 alphabet (no 0/O/1/I),
               hashed the same way, stored alongside
Never          the PIN, its hash, or the recovery code touch the database
```

**Why not in the database.** Not for secrecy — the DB is readable anyway — but because
restoring a backup must not change your lock. If the hash lived in the DB, importing a
friend's backup would silently replace your PIN with theirs. Secure storage keeps the lock
tied to the *install*, not the *data*. That is the correct boundary.

### 2.2 Flows

| Action | Behaviour |
|---|---|
| Enable lock | PIN entered twice → recovery code generated and shown → one confirm checkbox → lock active → **immediately prompt "Make a backup now?"** |
| Unlock | Hash and compare. Correct → open app. Wrong → increment counter. |
| Change PIN | Verify old PIN, store new hash. Recovery code unchanged. |
| Disable lock | Verify PIN, delete hash + salt + recovery hash. |
| Forgot PIN | Enter recovery code → set a new PIN. Data untouched. |
| Forgot both | Explicit last resort: "Erase all data and start over", requires typing `ERASE`. Offers to export a backup first — which is possible because the DB is plaintext and the lock is not a decryption key. |
| Biometric | `local_auth` gates the same screen. No key material involved, so this is genuinely just a shortcut. |
| Auto-lock | On background after a configurable delay (default 60 s). Lock state only; the database stays open. |

The "forgot both" path is the one that only exists because we dropped encryption, and it is a
real improvement: nobody permanently loses their financial history to a forgotten 4-digit PIN.

### 2.3 Throttling

Counter in secure storage, not the DB (the DB is not the thing being protected):

| Failures | Delay |
|---|---|
| 1–4 | none |
| 5 | 30 s |
| 6 | 1 min |
| 7 | 5 min |
| 8+ | 15 min, doubling to a 1 h cap |

Optional "erase all data after 10 failed attempts", **default off**, behind a scary confirm.

### 2.4 `android:allowBackup="false"` — mandatory

This is the single most important consequence of a plaintext database.

Android's auto-backup is **on by default**. Left on, it silently uploads the app's private
data directory — the complete financial database — to the user's Google Drive, outside the
app's control and outside what the Play data-safety form would declare.

```xml
<application
    android:allowBackup="false"
    android:dataExtractionRules="@xml/data_extraction_rules">
```

`allowBackup="false"` disables backup on API 30 and below; `dataExtractionRules` covers API
31+, where cloud-backup and device-transfer are gated separately. A third attribute,
`fullBackupContent="false"`, is redundant once `allowBackup` is false and is omitted to keep
the manifest minimal.

**Ships in Phase 1A**, not Phase 8B — the database arrives in Phase 1B, so this cannot wait.

`res/xml/data_extraction_rules.xml`:

```xml
<data-extraction-rules>
    <cloud-backup><exclude domain="root" path="." /></cloud-backup>
    <device-transfer><exclude domain="root" path="." /></device-transfer>
</data-extraction-rules>
```

Side benefit: it also blocks `adb backup` extraction. The user's own explicit export (§3)
becomes the only way data leaves the device, which is exactly the intent.

### 2.5 Honest copy

The lock setup screen says, in plain language: this PIN stops someone who picks up your
unlocked phone. It does not encrypt your data. Your phone's own lock screen is what protects
the file when the device is locked.

No "bank-grade", no "military-grade", no padlock iconography implying encryption. Overclaiming
here is both dishonest and a Play listing risk.

---

## 3. Backup & restore

Dropping encryption collapses this from a three-layer subsystem into roughly one screen and
two SQL statements. This is the biggest simplification of the redesign.

### 3.1 Export — `VACUUM INTO`

```sql
VACUUM INTO '/path/chosen/by/user/alaya-backup-20260728-1432.db';
```

One statement. It produces a consistent, compacted, standalone SQLite file even while the app
is running — no manual file copy, no WAL/journal race, no serialisation layer. This is exactly
the "SQL file directly" you asked for, and with a plaintext database it is finally trivial.

- Filename: `alaya-backup-<yyyyMMdd-HHmm>.db`
- If any attachments exist, wrap into `alaya-backup-<stamp>.zip` containing `data.db` +
  `attachments/`. Otherwise ship the bare `.db` — fewer moving parts.
- Log to `backup_history`.
- Schema version travels inside the file itself (drift's `user_version`), so there is no
  manifest to keep in sync.

### 3.2 Restore — `ATTACH`

Because primary keys are UUIDs (ARCH_1 §4.4), merge is a per-table upsert with no ID
remapping:

```sql
ATTACH DATABASE '/tmp/incoming.db' AS backup;
-- gate first. NOTE the qualified pragma: `pragma_user_version('backup')` does NOT work —
-- SQLite rejects it with "too many arguments on pragma_user_version() - max 0", because the
-- table-valued form takes no argument and so cannot be aimed at an attached schema. Verified
-- in Phase 4C: the form below returned the attached file's 7 while main was 1.
PRAGMA backup.user_version;                    -- refuse if > current schemaVersion

-- then, per table:
INSERT INTO items SELECT * FROM backup.items WHERE true
  ON CONFLICT(id) DO UPDATE SET
     name = excluded.name, ...            -- all columns
   WHERE excluded.updated_at > items.updated_at;   -- last-write-wins

DETACH DATABASE backup;
```

| Mode | Behaviour |
|---|---|
| **Replace** | Close DB → move current file to `rollback.db` → copy backup into place → reopen. Requires typing `REPLACE`. Auto-restores the rollback if reopening throws. |
| **Merge** | `ATTACH` + per-table upsert by UUID, last-write-wins on `updatedAt`. Rows absent from the backup are kept. |

Guards, in order: verify the file opens as SQLite → `user_version <= app schemaVersion` → run
inside one transaction → snapshot a rollback copy first → `DETACH` in a `finally`.

**The lock is not restored.** PIN and recovery hashes live in secure storage (§2.1), so
importing a backup never changes who can open the app.

### 3.3 Android storage reality

> **8B implementation note.** SAF is provided by `lib/data/platform/saf_channel.dart` over
> `android/app/src/main/kotlin/com/alaya/saf/SafPlugin.kt` — **not** by `file_picker`, which cannot be used in
> this project (ARCH_1 §7). Two methods: `openDocument` (`ACTION_OPEN_DOCUMENT`, **copies into the app cache and
> returns that path**, because `ATTACH DATABASE` needs a filesystem path and SQLite cannot open `content://` —
> and the read grant expires with the activity result) and `createDocument` (`ACTION_CREATE_DOCUMENT`, writes a
> given file into the chosen URI in one round trip, so Dart never holds a URI it cannot use).
>
> **The manifest declares zero `<uses-permission>` entries.** Attachment files live inside the app's own
> directory; everything outward goes through a system sheet.


You cannot write to arbitrary paths on Android 11+.

- Export → Storage Access Framework *create-document* intent; the user picks the location.
- Share → `share_plus` with a `FileProvider` content URI (WhatsApp, Gmail, Drive all work).
- Import → *open-document* intent, copy to app cache, then `ATTACH` from there.
- **No** `WRITE_EXTERNAL_STORAGE`, **no** `MANAGE_EXTERNAL_STORAGE`. The latter requires a
  Play declaration form and is routinely rejected.

### 3.4 The warning

On the export confirmation sheet, every single time — not in settings, not a tooltip:

> **This backup is not encrypted.** Anyone who opens this file can read every transaction,
> balance and account name. Only share it somewhere you trust.

> **8B enforcement note.** The ARB key is `backupNotEncryptedWarning`, and it now carries the text above
> **verbatim including the third sentence** — 8A shipped a paraphrase that dropped *"Only share it somewhere you
> trust"*, the only actionable clause, and nothing caught it until §3.4 was read directly. Both export paths in
> `BackupScreen` route through one `_confirmExport`, so neither can reach the filesystem without it.
> `ops_screens_test.dart` asserts the third clause **by phrase** and asserts that cancelling leaves
> `exports == 0`. **Do not reword this string.**

The database itself is plaintext too, so this is a consistent, honest threat model rather than
the contradiction it would have been alongside an encrypted DB.

---

## 4. Soft delete & lifecycle

| State | Meaning | Counted in totals? | Visible in pickers? |
|---|---|---|---|
| active | normal | yes | yes |
| `isArchived` | retired but historical (an old bank account) | **yes** | no |
| `deletedAt` set | user deleted it | **no** | no |
| purged | past retention, gone | n/a | n/a |

Archive and delete get conflated constantly. **Archive keeps money in your net worth; delete
removes it.** A closed bank account with ₹0 should be archived. A duplicate transaction should
be deleted.

### 4.1 Cascade rules

| Deleting | Effect |
|---|---|
| Item | cascade soft-delete its Batches. Movements untouched (append-only). |
| Transaction | **never** cascades to Batches or Assets. Nulls `sourceTransactionLineId`, flips batch `origin` to `detached`. Offers "also remove the 4 items this added" **only** if the batch is untouched (`remaining == initial`, zero consumption movements). |
| Account with any live transaction | **blocked.** Hard stop with a dialog offering Archive. Not a warning — a block. |
| Tag | soft only; links survive so history stays readable. Renders greyed with `(deleted)`. `isSystem` tags cannot be deleted at all. |
| RecurringTemplate | soft; `paid` occurrences and their transactions survive. |
| Asset | never deleted — `status = disposed` + `disposalReason`. |

The transaction rule is the one that matters most: you deleted a receipt, not the groceries.

### 4.2 Trash

> **8B implementation note.** `TrashPort` / `TrashAdapter`, and **`_hardDelete` is the only hard delete in the
> codebase.** All three purge paths — one row, everything, only the expired — arrive there; `_deleteRow` beneath
> it is a `switch` over seven tables with no logic and no other caller. **Later phases must not write a second
> `DELETE FROM`:** a row that can vanish without appearing in the trash breaks the retention promise.
>
> It runs under `PRAGMA defer_foreign_keys`, because **`foreign_keys = OFF` is silently ignored inside a
> transaction** — the same trap `EraseService` documents. Seven user-facing tables are listed, not the
> twenty-two that carry `deletedAt`: a trash showing `currency_rates` and `analytics_cache` would bury the
> transaction somebody is looking for.
>
> Retention is enforced by `lib/data/reminders/daily_job.dart`, registered once from `bootstrap()`. Before that
> call existed, every screen worked and the trash never emptied.


Phase 8B: a trash screen with 30-day retention, per-item restore, and "empty now". Purge is
**the only hard delete in the codebase** and lives in exactly one function.

---

## 5. Analytics

Written last (Phase 7B), designed now. Analytics designed last against a schema built without
it is how you end up unable to answer "which vegetable did I buy most" and needing a migration.

### 5.1 Query catalogue — the schema acceptance test

Every query must be answerable from ARCH_2 with **no schema change**. If a table review breaks
one of these, the table is wrong.

| # | Question | Needs |
|---|---|---|
| 1 | Spend by subtype, per month | `v_monthly_totals`, `subtype` |
| 2 | Spend by tag, per month | `transaction_tags` |
| 3 | Spend by payment method | `paymentMethodId` |
| 4 | Top 10 payees by spend | `payeeId` |
| 5 | Income vs expense, 12-month trend | `kind`, `monthKey` |
| 6 | Net cash flow per month | `v_account_ledger` |
| 7 | Balance trend per account | `v_account_ledger` + `dateKey` |
| 8 | Grocery share of total spend | `subtype` |
| 9 | **Top items by spend** | `transaction_lines.itemId`, `lineAmountMinor` |
| 10 | **Top items by quantity bought** | `quantityMilli` |
| 11 | **Most expensive single purchase of an item** | `unitPriceMinor` |
| 12 | **Unit-price trend for one item** (personal inflation) | `unitPriceMinor` + `dateKey` |
| 13 | Inventory value on hand | `remainingQuantityMilli × unitCostMinor` |
| 14 | **Food waste — quantity and money** | `stock_movements.kind = 'waste'` + batch cost |
| 15 | Items expiring in N days | `expiryDateKey` |
| 16 | Low-stock count over time | `v_low_stock` |
| 17 | Fixed monthly commitment total | `recurring_templates` |
| 18 | Recurring vs discretionary split | `recurringTemplateId IS NULL` |
| 19 | Lifetime service cost per asset | `service_records.costMinor` |
| 20 | Warranty coverage timeline | `warrantyStart/EndDateKey` |
| 21 | Day-of-week / day-of-month spend heatmap | `dateKey` |
| 22 | Category concentration (top-3 share) | `subtype` + `tags` |
| 23 | Average grocery basket size | `transactions` ⋈ `count(lines)` |
| 24 | **Price per base unit, same item across purchases** | `lineAmountMinor ÷ (quantityMilli / 1000)` |

The bolded ones are the differentiators. 12, 14 and 24 are things no mainstream expense app
tells you, and they fall out of this schema for free. Query 12 — *"your potatoes cost 34% more
than in January"* — is the kind of insight that gets an app screenshotted and shared.

### 5.2 Implementation rules

- Queries live in `domain/services/analytics/` as named, individually-testable functions
  returning plain records. **No chart library types in the domain layer.**
- SQL aggregation over indexed columns. Nothing is loaded into Dart to be summed.
- Multi-currency series convert **per data point** using §1.3's lookup rule, and every series
  returns an `approximate` / `unconverted` count alongside the data.
- `analytics_cache` for anything over ~200 ms, keyed by `(queryName, paramsHash)`, invalidated
  on any write to a contributing table.

---

## 6. Calendar

`v_calendar_events` is a `UNION ALL` view. No physical events table, therefore no
synchronisation code, therefore no synchronisation bugs.

```
date_key | event_type | ref_type | ref_id | title | amount_minor | currency_code | severity
```

| `event_type` | Source | Severity |
|---|---|---|
| `transaction` | `transactions.dateKey` | info |
| `recurringDue` | `recurring_occurrences` where `status = 'due'` | warning if `dueDateKey < today` |
| `batchExpiry` | `inventory_batches.expiryDateKey` where remaining > 0 | warning ≤ 7 d, danger if past |
| `warrantyEnd` | `assets.warrantyEndDateKey` | warning ≤ 30 d |
| `serviceDue` | `assets.nextServiceDueDateKey` + `service_records.nextDueDateKey` | warning ≤ 7 d |
| `shoppingTarget` | `shopping_lists.targetDateKey` | info |

"Medicine expiry" needs no special handling — it is `batchExpiry` on an Item with
`itemKind = medicine`, which is exactly why `itemKind` exists.

Always queried with a bounded range (`date_key BETWEEN ? AND ?`) so it hits the per-source
indexes and never scans.

---

## 7. Notifications

> **8B implementation note.** `ReminderPort` / `LocalNotificationScheduler`. Four constraints are structural
> rather than commented: the contract cannot express a per-item ping or an exact time;
> `AndroidScheduleMode.inexactAllowWhileIdle` is the only mode used; an empty count **cancels** rather than
> delivering *"0 items expire this week"*; and the digest's Android id is a constant so the daily job cannot
> stack duplicates.
>
> `POST_NOTIFICATIONS` is requested on the **first switch-on** and nowhere else. `ReminderPermission`
> distinguishes `notRequested` from `denied`, which is what lets the screen avoid nagging somebody who refused.
> A refusal leaves the switch off.
>
> **`NotificationKind.lowStock` is deliberately absent from `reminderKinds`.** It is a *state*, not a date —
> everything a digest mentions falls on a day, and "you are low on rice" would fire every morning until somebody
> shopped.
>
> **Recorded deviation from Law U5:** the digest's text is assembled in Dart, not the ARB. A `workmanager`
> isolate has no `BuildContext` and no `AlayaStrings`, and passing pre-localised text into a job that may run
> days later in a locale since changed would be worse than plain English. Confined to
> `LocalNotificationScheduler._digestBody`.


Not in the original spec, but expiry dates, service dues and recurring dues are worthless
without them — a reminder you must open the app to see is not a reminder.

- `flutter_local_notifications` + `timezone`, **inexact scheduling only**. No
  `SCHEDULE_EXACT_ALARM` — Android 14 restricts it and Play will ask why you need it.
- `POST_NOTIFICATIONS` requested **contextually**, when the user first enables a reminder.
  Never on first launch.
- **One daily digest** at a user-chosen time — *"3 items expire this week, 1 bill due
  tomorrow"* — rather than a stream of individual pings. Fewer, better notifications.
- A `workmanager` daily job recomputes upcoming events and reschedules.
- `notification_schedule` guarantees idempotency and gives every notification a stable Android
  ID, so it can be cancelled when the underlying record changes.
- All reminders default **off**. The user opts in.

---

## 8. Theme

The requirement is: change the palette later, easily. That means the palette must be **data**,
not code sprinkled across 200 widgets.

​```
lib/app/theme/
  tokens/
    alaya_spacing.dart      // 4 / 8 / 12 / 16 / 20 / 24 / 32 / 48, + minTapTarget 48
    alaya_radii.dart        // 4 / 8 / 12 / 20 / full, + sheetTop
    alaya_durations.dart    // fast 120ms, base 220ms, slow 380ms, page 300ms
    alaya_typography.dart   // one type scale, semantic names, tabular figures on numerics
    alaya_elevation.dart    // shadow sets, light and dark
    alaya_icon_size.dart    // 16 / 20 / 24 / 40 — added in 6A, closes the last raw-number class
  palettes/
    palette.dart            // the AlayaPalette data class
    presets.dart            // 4 complete palettes as const data
  semantic_colors.dart      // ThemeExtension<AlayaSemanticColors>
  alaya_theme.dart          // palette + tokens -> ThemeData (light & dark)
​```

### 8.1 The three structural guarantees

Everything else about the theme is a usage rule and lives in ARCH_5.

1. **A palette is `const` data, not code.** Switching the entire app's look is one constant change
   in `presets.dart` (`AlayaPresets.activePreset`). Four presets ship: Indigo Khata (default),
   Slate Sage, Midnight Brass, Monsoon Teal.
2. **Semantic colours reach a widget through a `ThemeExtension`**, not through top-level constants,
   because the palette can change at runtime and a widget holding a `const` colour would not
   rebuild. Reached as `context.semantic`.
3. **The red/green rule is implemented exactly once**, in `AlayaSemanticColors.forAmount(Money)`.
   That is what makes it uniform by construction rather than by 200 widgets each remembering it,
   and changeable — inverting it for a user who reads red as auspicious is one edit.

### 8.2 Theme Lab

A debug-only screen (Phase 5) rendering every token, every component and every semantic colour
on one scrollable page, in light and dark side by side. This is how palettes actually get
chosen — not by navigating the real app hunting for a screen that uses `warning`.

It is a **route outside the drawer shell** (ARCH_5 U18), reached from Settings, and it renders
nothing but a title line in a release build.

### 8.3 Where the rest went

| Was | Now |
|---|---|
| §8.1 usage rules (no hex in a widget, semantic names, one red/green site) | ARCH_5 §1 U6, §2.4 |
| §8.3 layout rules no static check can enforce | ARCH_5 §1 U2, §10, and `test/shared/layout_overflow_test.dart` |
| Accessibility expectations | ARCH_5 §6 |

---

## Phase 7A amendment — CalendarAggregator now has two consumers

`CalendarAggregator` was specified for the calendar screen. It also backs the dashboard's upcoming
shortlist, so its severity thresholds (§6) are the single definition of "needs attention" across both
screens rather than one of two.

**Its occurrence rows are created by `RecurringRepository.materialiseUpTo`, not by the aggregator.** The
`recurringDue` arm of `v_calendar_events` reads `recurring_occurrences` where `status = 'due'`, so a
recurring template contributes nothing until a row exists. `recurringHorizonProvider` performs that
materialisation once per session, two years ahead, and **both** the month feed and the dashboard card await
it before subscribing. Any future consumer of the aggregator must await it too, or it will read a feed
that is complete in six of its seven arms.
