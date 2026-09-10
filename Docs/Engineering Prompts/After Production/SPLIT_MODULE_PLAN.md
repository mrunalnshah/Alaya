# Split + Data Export — build plan (final)

**What this is.** Two tracks. **Track A** builds the Split module — a personal ledger of shared
expenses. **Track B** builds app-wide CSV/spreadsheet export, plus Splitwise import. Fifteen
sessions total, and they are independent apart from one ordering constraint noted at Track B.
Upload it alongside `ARCH_M_MAINTENANCE.md` at the start of every session in §6.

**Read §0 and §1 before writing anything.** §0 records what this module is not; §1 records what the
apps people actually use get wrong, and which of those failures the schema forecloses.

---

## 0. Scope, and the decisions that are now closed

### It is a single-user ledger

One person uses the app. Nobody logs in, nobody else is notified, nobody confirms a payment, no other
device agrees with yours. **Groups and people are reference labels** — who owes, which group, what
occasion, where — not accounts belonging to anybody.

### Three ARCH_4 §2.3 non-goals

| Non-goal | Status |
|---|---|
| *no cloud sync* | **Unchanged.** Law L11 — fully functional offline, forever. This module adds no network call |
| *no multi-user or shared household accounts* | **Unchanged.** Nobody logs in. A `payees` row with `kind = person` is a label, exactly as a merchant is |
| *no lending/investment tracking (…keeps you outside Play's Financial Services policy)* | **Narrowed deliberately.** This tracks shared *expenses*, not credit at interest. Record it as a doc amendment so it is not re-litigated. The remaining work is the Play declaration, which is a form, not code |

Also unchanged and worth naming, because it is a real gap against paid competitors: **no OCR receipt
scanning.** Itemisation here is manual — but unlimited and free, where Splitwise paywalls it. And
attachments already exist (Phase 8B), so a receipt *photo* can hang off the expense today.

### Decision 1 — owed money is not spendable until it arrives

**Locked.** A receivable never counts toward the dashboard's *total available funds*. It has its own
card, labelled so the distinction is unmissable.

When somebody pays you, the settlement writes a real **deposit** into a chosen account, and from that
instant the money is ordinary spendable balance like any other deposit. No separate "split wallet", no
second concept to reconcile.

This is the whole of requirement 1 and requirement 8, and it is why §2's Case A records the full
outflow. It also means the module cannot inflate your net worth with money you have not received —
the failure mode of every app that treats a balance as an asset.

### Decision 2 — simplification is advisory, and §3 says why that is not a preference

**Locked.** True pairwise debts are never rewritten. A minimum-transfer plan is computed, shown, and
acted on; the underlying history stays exactly as recorded.

### The four design commitments

Break one and this becomes an ordinary clone.

**1. No balance is ever stored (Law L3).** *"Ravi owes you ₹1,850"* is a view over shares and
settlements. Splitwise stores balances and reconciles them; Alaya structurally cannot drift.

**2. A settlement is a real transaction, not a flag.** When Ravi pays you, a `transactions` deposit is
written with a `paymentMethodId`. Your account ledger and your split ledger cannot diverge — the
failure class ARCH_M §7 documents at length.

**3. Shares attach to lines, not just totals.** `transaction_lines` already exists. Each person's
total is a **sum over lines**.

**4. Money is exact, and the screen admits when it is not.** ₹1,000 ÷ 3 assigns the stray paise
deterministically and the shares sum to the total. Where they cannot, the "unallocated ₹20" pattern
`transaction_lines` already uses is surfaced rather than rounded away.

---

## 1. Verification against the apps people actually use

Checked in August 2026 against Splitwise, Tricount, Settle Up, Splid, Kittysplit and the current crop
of alternatives (SplitMyExpenses, GoodShare, Splital, ExpenDiv, SplitterUp). Sources are review
round-ups and Splitwise's own help centre and feedback forum.

### What the market's leader charges for, and Alaya gets structurally

| Splitwise, since its 2024 free-tier change | Alaya |
|---|---|
| **Item-level splits — Pro only**, roughly $40–60/year | Free and native. `transaction_lines` already exists for the grocery-into-inventory flow |
| **Recurring shared expenses — Pro only** | `F_RECURRING` already exists |
| **Receipt OCR — Pro only** | Not offered. Manual itemisation, unlimited; receipt photos via attachments |
| **~3 expenses per day on free tier, plus ads** | No limit. Alaya's own ads are unrelated to this module |
| Balances stored and reconciled | Derived (L3). Cannot drift |

**Item-level splitting behind a paywall is the single most useful finding in this research.** It is
requirement "someone orders extra" verbatim, it is the most-praised Pro feature, and here it falls out
of a table that already exists.

### The friction every review names, and how this module stands

> *"You're at dinner with six people. To split the bill properly, you need all six to download the
> app, create accounts, and join your group. In practice, at least two of them never will."*

That is the #1 structural complaint about Splitwise across every comparison read. The apps gaining
ground — ExpenDiv, Splid, Tricount, Kittysplit — all attack it by letting participants avoid accounts.

**Alaya is already on the right side of this: nobody else needs anything.** The gap is *outbound* —
we cannot send them a summary or a payment link the way ExpenDiv emails one.

**So the shareable summary is a first-class feature, not an afterthought** (session 7), and for an
Indian user it carries a **UPI intent link** — `upi://pay?pa=…&am=…&tn=…` — so "Ravi owes you ₹1,850"
becomes a message he taps to pay. That is ExpenDiv's payment link, on the payment rail this user's
country actually uses, with no backend. It is a deep link, not payment processing.

### Where newer entrants differentiate, and Alaya already has it

GoodShare and EconoGlance are winning switchers on **analytics and budgets bolted onto splitting.**
Alaya has a 24-surface analytics module with a cache, a calendar, a notification digest, recurring
templates, an inventory ledger and multi-currency conversion **already built**. This module is the
last missing dimension of a personal finance app rather than a splitting app growing an analytics tab.

### Honest remaining gaps

| Gap | Assessment |
|---|---|
| No OCR | Real. Splitwise Pro and EconoGlance have it. Manual entry with a receipt photo attached is the answer here |
| Others cannot log expenses | Inherent to no-sync, and the market is split on whether that is a cost |
| No Splitwise import | **Closable.** Splitwise exports CSV and every serious alternative advertises an importer. Session 10 |

---

## 2. The two cases the data model must hold

**Case A — you paid (requirement 1).** You pay ₹1,000 for four. Cash left your account, so a
`transactions` withdrawal of **₹1,000** is written — the full amount, because a ledger that says
otherwise is lying. Your share is ₹250; the other ₹750 is owed to you and arrives as settlements, each
a real deposit into an account you choose.

**Case B — somebody else paid (requirement 2).** Ravi pays ₹1,000; you owe ₹250. **No transaction
exists on your account at all** until you settle, at which point a ₹250 withdrawal is written.

Case B is why `split_expenses.transactionId` is nullable and `paidByPayeeId` is not. Most
implementations model only Case A and bolt B on afterwards.

**Two analytics lenses (requirement 4), and only Alaya can offer both:** *what left my account*
(₹1,000) and *what I actually consumed* (₹250). Splitwise knows the second and nothing about your
bank; your bank app knows the first and nothing about the split.

---

## 3. Simplify debts — the researched design

### What Splitwise does, and what it costs them

Splitwise rewrites the group's debt graph in place and re-simplifies automatically on every new
expense or payment. Three consequences, all documented by Splitwise itself:

1. **Its own help centre advises users to stop trusting the individual balances**, recommending they
   look at the total instead because pairwise figures may have been reshuffled. An app that has to say
   that has broken its own record.
2. **Turning it off does not cleanly reverse.** Splitwise's help centre states that payments made
   under simplified paths may no longer line up with the restored debts, so people may need to resend
   funds. Nobody overpays, but the history stops making sense.
3. **The recurring complaint, verbatim across a decade of their feedback forum:** *"Why do I owe ₹100
   to person A? She never lent me money."*

And the top-voted request — a **temporary preview toggle**, so you can see the simplified plan without
committing to it — was acknowledged by Splitwise staff in 2014 as a good idea and has never shipped.

**That request is the feature. Decision 2 builds it as the default behaviour.**

### The algorithm

Per currency — netting INR against USD without a rate would violate L9's spirit and produce a figure
nobody can reproduce.

**Step 1 — net.** Reduce shares minus settlements to one signed balance per person. Anyone at zero
drops out.

**Step 2 — partition into zero-sum subsets.** A subset whose balances sum to zero settles internally
in `k−1` transfers. Maximising the number of such subsets minimises the total, and that is the true
optimum. Finding it is NP-hard in general and **trivial at group scale** — bitmask dynamic programming
over ≤ 20 members, which covers every real group. Above that, fall back to step 3 alone.

**Step 3 — greedy within each subset.** Match the largest creditor to the largest debtor, repeat. This
alone guarantees ≤ `n−1` transfers, which is what Splitwise achieves; step 2 is what beats it.

**Step 4 — the tie-break nobody else does.** Among plans with the same number of transfers, prefer the
one with the most transfers **along debt edges that actually exist** — between people who really
transacted. This is a direct answer to *"she never lent me money"*, and it is free: it only ranks
plans that were already equal on count.

### The presentation

- **Suggested, never applied.** The pairwise ledger is untouched, so no "unravelling" is possible.
- **Preview by default**, with the true and simplified views side by side. The decade-old request.
- Accepting the plan records **ordinary settlements** — the same rows a manual settle-up writes. There
  is no "simplified" state to get stuck in and no toggle to lock.
- Every suggested transfer explains itself: *"pay Ravi ₹450 — this clears what you owe Priya, who owes
  Ravi."* The sentence Splitwise's users have to work out for themselves.

---

## 4. Schema — v4

Schema is at **v3** (`v1`, `v2`, `v3` snapshots; `from1To2`, `from2To3`). This takes it to **v4** and
needs `from3To4`, a v4 snapshot, and — for any seeded row — **both** the seed and the migration step.
ARCH_M §7 records shipping one without the other.

Every table gets `id TEXT` UUIDv7 (L5), `createdAt`, `updatedAt`, `deletedAt` (L6), and is read through
a view (L7).

### `split_groups`
```
name, normalizedName, note, colorArgb, iconKey,
defaultSplitMethod TEXT,           -- SplitMethod, fallback-safe converter (L13)
isArchived INTEGER, sortOrder INTEGER
```
Occasion and place live on the expense, not the group — one group has many occasions.

### `split_members`
```
groupId -> split_groups, payeeId -> payees,
defaultWeightBasisPoints INTEGER,  -- 40/30/30 entered once, never re-entered
sortOrder INTEGER
```
**People are `payees`**, which already has `kind ∈ {person, merchant, employer, utility, other}` with
`phone` and `note`. A new `people` table would be a second vocabulary for one concept. **Who you are**
is one `app_settings` key, `split.selfPayeeId` — not a flag on a shared table.

### `split_expenses`
```
groupId -> split_groups          NULL   -- a one-off split with one person needs no group
transactionId -> transactions    NULL   -- NULL in Case B
paidByPayeeId -> payees          NOT NULL
totalAmountMinor INTEGER         NOT NULL CHECK (> 0)
currencyCode -> currencies       NOT NULL
dateKey, monthKey INTEGER        NOT NULL  -- monthKey denormalised, as transactions does
title, place, occasion, note     TEXT
splitMethod TEXT                 NOT NULL
settleByDateKey INTEGER          NULL   -- feeds calendar + notifications
convertedAmountMinor, convertedCurrencyCode, conversionRate,
conversionRateRaw, conversionDateKey    -- frozen snapshot only (L9), for travel
```
**No `myShareMinor` column.** Derived (L3). Storing it is the most tempting mistake in this schema and
it drifts the first time a share is edited.

### `split_shares`
```
splitExpenseId -> split_expenses NOT NULL
payeeId -> payees                NOT NULL
transactionLineNo INTEGER        NULL   -- commitment 3: the share is against one line
shareAmountMinor INTEGER         NOT NULL  -- the resolved, exact figure
inputKind TEXT                   NOT NULL  -- equal | exact | percent | shares
inputValue INTEGER               NULL   -- basis points, weight, or minor units
```
Both the **input** and the **resolved amount** are stored, deliberately: re-deriving on every read
would re-run allocation and could assign the stray paise differently from what the user agreed to. The
input is kept so the editor can show *how* it was split.

`transactionLineNo` is usable only when `transactionId IS NOT NULL` — itemising needs the receipt,
which means you paid. Table CHECK, and stated in the entity doc.

### `split_settlements`
```
groupId -> split_groups          NULL
fromPayeeId, toPayeeId -> payees NOT NULL
amountMinor INTEGER              NOT NULL CHECK (> 0)
currencyCode -> currencies       NOT NULL
dateKey INTEGER                  NOT NULL
transactionId -> transactions    NULL   -- NOT NULL whenever you are a party
paymentMethodId -> payment_methods NULL
simplifiedFromPlanId TEXT        NULL   -- provenance when it came from an accepted plan
note TEXT
```
**Many settlements per debt.** Requirement 1's *"keep adding as the individual keeps paying"* is
partial settlement, and the remainder is a view — never a decremented column.

### Views

| View | Answers |
|---|---|
| `v_split_expenses` | soft-delete filtered, with derived `my_share_minor` |
| `v_split_balances` | per payee: owed to me, I owe, net — **the L3 centrepiece** |
| `v_split_group_balances` | the same, per group |
| `v_split_activity` | expenses and settlements interleaved, newest first |
| `v_calendar_events` | **a new arm**, not a new table |

### Enums (L13 — names are a schema contract)
```dart
enum SplitMethod { equal, exactAmounts, percent, shares, perLine }
enum ShareInputKind { equal, exact, percent, shares }
```
Plus two values added to existing enums, each breaking compilation in known places — see session 8.

---

## 5. Session 1 upload

```
SPLIT_MODULE_PLAN.md   ARCH_M_MAINTENANCE.md   ARCH_1_FOUNDATION.md   B1_CORE.md   B3_DOMAIN.md
```

with:

> Session 1 of the Split plan. Write the change.
>
> - Complete files, never fragments, never a patch carrying a source-file extension.
> - Only files that changed.
> - Say which of §6's rules you had to work around, and how.
> - If something conflicts with a rule, stop and tell me.
> - Before shipping a test, recompute its expected values independently.

---

## 6. The sessions

Nine, and Track B adds six. Split by layer, build between each. Session 1 touches no screen and no
table.

> ARCH_M §4: *put the pure arithmetic in its own session, first — it changes no screen, so it cannot
> break anything, and it settles the questions the UI will otherwise re-open three times.* That was
> the only round of four in the measure rework that needed no correction.
>
> And: *budget for the UI to need more rounds than the data.* Sessions 5–9 are the UI.

### 1 — the arithmetic
**Upload:** `ARCH_1`, `ARCH_M`, `B1_CORE`, `B3_DOMAIN` — ~16,000 lines

- `Money.allocate` in `core/money/` beside `convert` and `MoneyRounding`. **Nothing like it exists** —
  verified before proposing it. Largest-remainder: parts sum to the total exactly, stray minor units go
  to the largest remainders, ties break deterministically.
- `SplitResolver` in `domain/services/split/` — equal, exact, percent (basis points), weights,
  per-line — resolving to exact shares. Reports an unallocated remainder rather than absorbing it.
- `DebtSimplifier` — §3's four steps, returning a **suggested plan** with a per-transfer explanation.

**Must not** touch the schema, a screen, or the ARB. Pure Dart, no Flutter import.

**Test:** ₹1,000 ÷ 3; ₹0.01 ÷ 2; percent inputs that miss 10,000 basis points; a weight of zero; one
participant; a group where greedy gives `n−1` but zero-sum partitioning beats it; the existing-edge
tie-break; and 20 members for the DP ceiling. **Recompute every expected figure in a throwaway script
before asserting it** — ARCH_M §7 records why.

### 2 — schema v4
**Upload:** `ARCH_2`, `ARCH_M`, session 1's files, **all of `B2_SCHEMA`** (38,390 lines)

All of `B2_SCHEMA` because `alaya_database.dart` and `migration_strategy.dart` are existing files
being modified; ARCH_M §4 is explicit that a DAO cannot be written without reading one.

Produces the five tables, four views, `from3To4`, the v4 snapshot, seed rows, and the
`v_calendar_events` arm.

**Must not** add a `myShareMinor` or `balanceMinor` column anywhere (L3). If a screen later seems to
need one, the answer is a view.

### 3 — entities, DAOs, repositories
**Upload:** `ARCH_M`, `B2_SCHEMA`, `B3_DOMAIN`, `B4_DATA`

Every multi-table write inside one drift `transaction {}` (L14) — a split expense writes the
transaction, its lines, and its shares. Repositories read views, never base tables (L7).

### 4 — domain services
**Upload:** `ARCH_3`, `ARCH_M`, `B3_DOMAIN`, `B4_DATA`

- `SplitBalanceService` — who owes what, from shares and settlements. No stored total.
- `SettlementService` — records the settlement **and** its transaction, atomically. Both or neither.
- `SplitExpenseService` — the Case A / Case B bridge into the expense module.

**Watch:** `transactions.originalAmountMinor` is immutable (L9). Editing shares must never rewrite it.
When shares stop summing to the total, that is an unallocated remainder the screen shows.

### 5 — the split editor inside the expense flow
**Upload:** `ARCH_5`, `ARCH_M`, `F_EXPENSE`, `B5_APP`, `B6_SHARED`, `ARB`

The hardest screen, and where requirement 8 lives: splitting is a step *inside* adding an expense, not
a second place to enter the same thing.

Group or people, a method, per-line attribution when lines exist, live per-person amounts, and the
unallocated remainder shown honestly.

**Watch:** Law U4's four states; U5/U6 no literals; U7 money through `AmountText`; U14's sticky footer;
and 320dp × textScaler 2.0 — a per-person amount row is exactly the `Row` of fixed-size children
ARCH_M §7 warns about.

### 6 — groups and people
**Upload:** `ARCH_5`, `ARCH_M`, `F_SPLIT`, `B6_SHARED`, `ARB`

Group list, group detail with balances and activity, creation with default weights, person management
over `payees`.

**Watch:** a new route needs a widget that navigates to it (ARCH_5 §9.2), and detail/editor routes sit
**outside** the `ShellRoute` or they get a hamburger where a back arrow belongs (U18, anomaly A49).

### 7 — settling up, and the summary that replaces sync
**Upload:** `ARCH_M`, `F_SPLIT`, `F_EXPENSE`, `B6_SHARED`, `ARB`

- Settle up, full or partial, with a real payment method, writing the deposit or withdrawal per
  decision 1.
- The simplification **preview**, side by side with true balances, and accepting it.
- **The shareable summary**, first class per §1 — plain text plus a **UPI intent link** per debtor.
  The existing SAF and share paths carry it.

**Watch:** a settlement that writes its transaction but not its row, or the reverse, is the divergence
this module exists to prevent. One transaction, both writes.

### 8 — calendar and notifications
**Upload:** `ARCH_M`, `F_SPLIT`, `F_CALENDAR`, `F_OPS`, `B1_CORE`, `B3_DOMAIN`, `B4_DATA`, `ARB`

Two enum additions, both breaking compilation in places named here. That is the good failure mode:
ARCH_M records that an exhaustive switch is a contract, and adding a value is how you find its
implementers.

**`CalendarEventType.splitSettleBy`** — existing values `transaction`, `recurringDue`, `batchExpiry`,
`warrantyEnd`, `serviceDue`, `shoppingTarget`. Breaks:

| Site | Needs |
|---|---|
| `CalendarAggregator.resolveSeverity` | a severity band for an unsettled debt |
| `LocalNotificationScheduler._kindForEvent` | the event → `NotificationKind` mapping |
| `F_CALENDAR` day sheet | icon, tone, tap target |
| `F_DASHBOARD` calendar widget | the same |

**`NotificationKind.settlementDue`** — existing values `expiry`, `serviceDue`, `recurringDue`,
`lowStock`, `warrantyEnd`. Breaks:

| Site | Needs |
|---|---|
| `LocalNotificationScheduler._digestBody` | a sentence — *"₹1,850 owed to you"* |
| `RemindersScreen._kindLabel` / `_kindHelp` | two ARB keys |
| `reminderKinds` in `reminder_port.dart` | **adding it here makes the toggle appear on the reminders screen automatically** — the screen iterates that list |
| `notification_schedule.kind` converter | fallback-safe already (L13); existing rows unaffected |

**Two notification designs, and the second is the one no competitor has.** `settleByDateKey` gives a
due-date reminder, which is what ExpenDiv sells. The one nobody does is an **ageing nudge** — *"Ravi
has owed you ₹1,850 for three weeks"* — which needs no due date, falls out of the balance view for
free, and is what people actually want. Build both; the threshold is one `app_settings` key.

**Watch:** the digest is one message a day (ARCH_3 §7) and inexact by design — no per-debt ping. And
the digest body is assembled in a `workmanager` isolate with no `BuildContext`, which is why ARCH_M
records that copy as the sanctioned exception to Law U5.

### 9 — analytics, dashboard, tests
**Upload:** `ARCH_M`, `F_SPLIT`, `F_ANALYTICS`, `F_DASHBOARD`, `B7_TESTKIT`, `ARB`

- Analytics with §2's **two lenses**: outflow versus own share, on every existing surface.
- Balances by person and group over time; who you split with most; **occasion and place as analytics
  dimensions** — they are on `split_expenses` for exactly this, and no competitor offers it.
- A dashboard card: net owed, oldest unsettled debt, and — per decision 1 — visibly **outside** total
  available funds.

**Watch:** the module grid needs a tile, a count provider, **and two numbers** in
`module_grid_test.dart` — the tile count and the name list. A tile with a blank label passes the count
check alone (ARCH_M §4b). `analytics_cache` invalidates on writes to contributing tables.

---

# Track B — Data export (CSV / spreadsheet) and Splitwise import

**Runs independently of Track A.** The only ordering constraint is that Split's datasets (B6) need
Split's tables, so Track A sessions 1–4 must land first if you want split data in the export. Track B
sessions 1–5 can happen before Track A entirely.

## B0. Why this does not touch every file

The obvious design puts a `toCsv()` on every repository and a switch in one export service that knows
about all twenty modules. That design touches every bundle, breaks whenever any module changes, and
makes "add a column to the export" a change to the export engine.

**Invert it.** One contract, declared in `domain/`:

```
ExportDataset
  name           -- "transactions", "inventory_batches", "split_expenses"
  columns        -- ordered, typed, each with a header
  rows(range)    -- a Stream of already-formatted string lists
```

Each module supplies **one file** that describes its own datasets. The export engine iterates a
registry and never learns what a transaction is. Consequences:

- Adding a module's export is one new file in that module's bundle. It is not a change to the engine.
- Adding a column is one line, in the module that owns the data.
- **Each dataset session uploads one or two feature bundles plus ~3,000 lines of contract**, instead of
  the whole app.

**Nothing here needs a schema change.** You never restore from a CSV, so there is no export history to
store — `backup_history` exists because a backup is restorable and a CSV is not. Export presets live in
`app_settings` keys. Schema stays at **v4** (Track A's version) throughout.

**Nothing here needs a new dependency.** `package:archive` is already a dependency with a working
`ZipEncoder` in the backup path, and the SAF `createDocument` channel already writes to a user-chosen
location. A zip of CSVs is assembled from parts that exist.

## B0.1 The decision that makes this useful or useless

**Analysis-ready by default, raw on request.**

A dump of `transactions` is technically an export and practically worthless: `019fffaf-66c8-…` in the
account column, `125000` in the amount column, `20260814` in the date column. Nobody opens that in
Sheets and learns anything.

| Field | Raw | Analysis-ready (**default**) |
|---|---|---|
| Amount | `125000` | `1250.00` **plus** `currency` **plus** `amount_minor` for exactness |
| Date | `20260814` | `2026-08-14` — which Sheets and Excel parse as a date; the integer does not |
| Account, payee, item, tag | UUID | the name, with the UUID in a trailing `id` column for joins |
| Enum | `withdrawal` | `withdrawal` — unchanged. Law L13 makes enum names a schema contract, so they are already stable identifiers |
| Converted amount | omitted | `converted_amount` + `converted_currency` + `rate`, from the L9 frozen snapshot |

Law L1 is not at risk: a decimal *string* in a text file is display formatting, the same as
`AmountText`. No `double` stores or crosses a boundary.

**Raw mode** keeps UUIDs and minor units for anyone who wants to reassemble the relational model. One
toggle, both modes from the same descriptor.

## B0.2 Two entry points, because the request named both

1. **Settings › Export data** — pick datasets, a date range, a mode, get one zip of CSVs. Sits beside
   Backup in `F_OPS`, which already owns that surface.
2. **Every analytics surface gets "export this data"** — the chart you are looking at, as the CSV
   behind it. This is the one competitors charge for: Settle Up puts Excel export in Premium.

## B0.3 The safety rule this inherits

ARCH_3 §3.4's backup warning is verbatim on every export, every time. **A CSV deserves it more than a
backup does** — a `.db` file needs a tool to read, a CSV opens in anything, and this one leaves the app
containing every amount you have ever recorded. Same words, same placement, no exceptions.

---

### B1 — the CSV writer and the dataset contract
**Upload:** `SPLIT_MODULE_PLAN.md`, `ARCH_M`, `ARCH_1`, `B1_CORE`, `B3_DOMAIN` — ~16,000 lines

- `CsvWriter` in `core/export/` — RFC 4180 quoting. The cases that break naive writers, all tested:
  a comma in a payee name, a double quote in a note, a newline in a multi-line note, a leading `=`
  or `+` (which Excel executes as a formula — **a real injection vector in a finance export**), a UTF-8
  BOM so Excel opens Devanagari and ₹ correctly, and an empty cell versus a null.
- `ExportDataset`, `ExportColumn`, `ExportMode { analysisReady, raw }` in `domain/services/export/`.
- `ExportRegistry` — the list a module registers into.
- Value formatters: `Money` → decimal string + currency; `DateKey` → ISO; `Qty` → decimal + unit.

**Must not** touch the schema, a screen, the ARB, or any feature bundle. Pure Dart.

**Test:** every quoting case above; that a formula-injection prefix is neutralised; that ISO dates
round-trip; that the analysis-ready and raw modes agree on `amount_minor`.

---

### B2 — the export service and the file adapter
**Upload:** `ARCH_3`, `ARCH_M`, B1's files, `B3_DOMAIN`, `B4_DATA`, `B8_ANDROID` — ~22,000 lines

- `ExportPort` in domain; `CsvExportAdapter` in data.
- Writes through the **existing** SAF `createDocument` channel and zips through the **existing**
  `ZipEncoder` — the backup path in `data_transfer_adapter.dart` is the pattern to copy, including its
  "VACUUM INTO cannot write into an archive" workaround, which is the reason it stages beside the
  destination first.
- Share as well as save, matching `exportAndShare`.
- **Streamed, not accumulated.** Five years of transactions must not become one string in memory. The
  `rows()` contract is a `Stream` for this reason and the adapter must honour it.

**Watch:** a failed export must leave no partial file at the destination. The backup path already
solves this; do not solve it differently.

---

### B3 — the export screen
**Upload:** `ARCH_5`, `ARCH_M`, B1's files, `F_OPS`, `F_SETTINGS`, `B6_SHARED`, `ARB` — ~15,000 lines

Dataset selection with counts, a `DateRangePreset` (A33 — it exists), the mode toggle, the §3.4
warning, progress, and the result. Four states per screen (U4), no literals (U5/U6).

**Watch:** ARCH_5 U18 — this is a detail route and belongs **outside** the `ShellRoute`, or it gets a
hamburger where a back arrow should be (anomaly A49).

---

### B4 — datasets: Expense and Analytics
**Upload:** `ARCH_M`, B1's files, `F_EXPENSE`, `F_ANALYTICS`, `ARB` — ~14,000 lines

The two people ask for first. `transactions`, `transaction_lines`, `accounts`, `payees`, `tags`,
`payment_methods`, plus a CSV behind each analytics surface and the "export this data" affordance.

**Watch:** `MoneyByCurrency` groups by currency rather than summing across (anomaly A34). An export that
flattens two currencies into one column would undo that deliberately.

---

### B5 — datasets: Inventory, Shopping, Recipe, Service, Recurring, Calendar
**Upload:** `ARCH_M`, B1's files, `F_INVENTORY`, `F_SHOPPING`, `F_RECIPE`, `F_SERVICE`, `F_RECURRING`,
`F_CALENDAR` — ~21,000 lines

`items`, `inventory_batches`, `stock_movements`, `shopping_entries`, recipes with ingredients and the
cook log, `assets`, `service_records`, recurring templates and occurrences, and `v_calendar_events` as
one flat dated feed — which is the single most useful sheet in the whole export.

Split across two sessions if it runs long; the descriptors are independent by construction, which is
the point of B0.

**Watch:** `Qty` is milli-base + category (L2). Export the decimal **and** the unit, or a column of
`4450` means nothing.

---

### B6 — datasets: Split, plus Splitwise import
**Upload:** `ARCH_M`, B1's files, `F_SPLIT`, `F_OPS`, `B4_DATA`, `B7_TESTKIT`, `ARB` — ~18,000 lines

**Requires Track A sessions 1–4.**

- Split datasets: expenses, shares, settlements, and a per-person balance sheet.
- **Splitwise CSV import** — the counterpart, sharing B1's parsing and B2's file path. Splitwise exports
  CSV per group and every serious alternative advertises an importer, because it is how switchers move.
  Map to `split_expenses` and `split_shares`, create missing `payees`, and **report what could not be
  mapped rather than guessing.**
- The test suite for the whole track.

**Watch:** ARCH_1 §7.4 — **never add `file_picker`.** `DataTransferPort.pickBackupFile` is the read
path and the pattern to copy.

---

## Track B at a glance

| | Uploads | Roughly |
|---|---|---|
| B1 | `ARCH_1`, `B1_CORE`, `B3_DOMAIN` | 16k |
| B2 | `ARCH_3`, `B3_DOMAIN`, `B4_DATA`, `B8_ANDROID` | 22k |
| B3 | `ARCH_5`, `F_OPS`, `F_SETTINGS`, `B6_SHARED`, `ARB` | 15k |
| B4 | `F_EXPENSE`, `F_ANALYTICS`, `ARB` | 14k |
| B5 | six feature bundles | 21k |
| B6 | `F_SPLIT`, `F_OPS`, `B4_DATA`, `B7_TESTKIT`, `ARB` | 18k |

**`B2_SCHEMA` appears nowhere.** No table, no view, no migration, no v5 — which is what B0 buys.

---

## 7. After every session — both tracks

```bash
flutter gen-l10n && python3 tool/check_arb_keys.py && flutter analyze && flutter test
python3 tool/reachability.py            # a service with no caller is the recurring fault
python3 tool/make_bundles.py            # regenerate what this session touched
```

`check_arb_keys.py --unused` at least once per UI session — ARCH_M §5 records two ARB strings that
promised a capability nobody wired.

**Before declaring the module done**, ask the question `reachability.py` cannot: **does each new screen
and service appear in any test file?** Seven capabilities in the previous cycle existed and were either
unreachable or untested, and three of those were whole screens.
