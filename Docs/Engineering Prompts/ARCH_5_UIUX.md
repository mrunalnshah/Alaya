# Alaya · ARCH 5 — UI/UX

**Attach this file to every prompt from 6A onwards.** With ARCH_1 it is the complete statement of
what a screen must be.

| | |
|---|---|
| Doc version | 1.0 |
| Date | 2026-08-01 |
| Binds | phases 6A–9 |
| Supersedes | ARCH_3 §8.1 and §8.3, which now point here |

---

## 0. Why this file exists

Three failure modes, all of which had already happened once by the end of Phase 5:

| Failure | What it looks like | Prevented by |
|---|---|---|
| **Overflow** | A `RenderFlex` stripe that appears only with a keyboard up, only in landscape, or only at a raised text scale — invisible to `dart analyze`, to a scanner, and to looking at the screen | §1 U2, §3's skeletons, §9's gate |
| **A screen that is nearly a screen** | Ships with a populated state and no empty, loading or error state; or a control that is 21px tall; or a number the user cannot act on | §1 U4, §5, §9 |
| **A stranded column** | `disposalReason`, `snoozeUntilDateKey`, `paidAmountMinor` exist in the schema, are written by an engine, and no screen ever shows them | §7's coverage matrix |

The third is the expensive one. A missing screen gets noticed. A column that no screen surfaces
looks like a working feature from every angle except the user's.

**How to use it.** §1 is law and citable by number. §3 tells you which skeleton to start from. §7
tells you what your phase owes. §9 is the gate — a phase is not done until both checklists pass.

---

## 1. The UI Laws

Non-negotiable from 6A. Numbered so a review can cite them the way it cites ARCH_1's L-series. If
generated code violates one, reject the file rather than patching it.

| ID | Law |
|---|---|
| **U1** | Every screen is one of the six archetypes in §3. A seventh needs a decision recorded in ARCH_4 §5.1 first. |
| **U2** | **Nothing overflows.** Every sheet goes through `AlayaBottomSheet`. Every centred full-height state goes through `ScrollSafeCenter`. Every form is inside a scroll view. Every new sheet and full-height state is added to `test/shared/layout_overflow_test.dart` **in the phase that creates it**. |
| **U3** | Every interactive target is at least `AlayaSpacing.minTapTarget` (48dp) in both axes. A visually smaller control gets a larger hit area, not an exemption. |
| **U4** | **Every asynchronous surface implements four states: loading, empty, error, populated.** `AsyncValue` is consumed with all three branches handled; `.value!`, `.requireValue` and `??  []` on a repository stream are review rejects. |
| **U5** | No user-visible string literal anywhere under `features/` or `shared/`. ARB only. A developer-facing placeholder marker is the sole exception and must carry `// PLACEHOLDER: PHASE_XX`. |
| **U6** | No raw colour, spacing, radius, duration, icon size or text style. `AlayaPalette`, `AlayaSpacing`, `AlayaRadii`, `AlayaDurations`, `AlayaIconSize`, `AlayaTypography` only. |
| **U7** | `Money` renders only through `AmountText`. `Qty` only through `QtyText`. `DateKey` only through `DateText`. `toString()` on any of the three is a bug. |
| **U8** | A destructive action confirms through `ConfirmSheet`, states what will happen rather than asking "are you sure", and is undoable wherever the data model allows it (ARCH_3 §4). Irreversible actions require typed confirmation. |
| **U9** | **Every write reports its outcome, and a failure reports the repository's own `Failure.message`.** Success is a snack bar carrying Undo where undo exists. Failure is an inline message on the field, or a snack naming what failed — `errorBodyGeneric` is the last resort for an error with no message, never the default, and the same holds for an `ErrorState` body. A write that appears to do nothing is the worst outcome available; a write that fails identically for every cause is the second worst. **A generic error message is a bug you cannot find.** |
| **U10** | A form never loses input. Dismissing an editor with unsaved changes prompts; a rejected save leaves every field populated. |
| **U11** | **Optional-first.** Every capture path has exactly one required field. Everything else has a defensible default, and the record is marked `needsReview` rather than blocking the user. |
| **U12** | Nothing in the UI awaits the network (ARCH_1 L11). A rate, an ad and a purchase are the only network calls, and none of them gates a save. |
| **U13** | Every list is virtualised — `ListView.builder`, `SliverList` or equivalent. Mapping a repository stream into a `Column` is a review reject regardless of the expected row count. |
| **U14** | **Primary actions live in the bottom third.** A full-screen editor commits from a sticky footer, never from an app-bar action. The app bar carries navigation and overflow only. |
| **U15** | Every screen survives 320dp width and `textScaler` 2.0 simultaneously. Both are asserted, not assumed. |
| **U16** | Every screen is reachable from the drawer, or from a screen that is. An orphan route is a feature nobody will find. |
| **U17** | Colour is never the only signal. An amount carries a sign, a status carries a label or glyph, an error carries text. |
| **U18** | A detail or editor route lives **outside** the drawer shell, so it gets a back arrow rather than a hamburger (`AppBar` resolves `hasDrawer` before `canPop`). |
| **U19** | No screen reads a repository directly. A screen watches a view-model provider in its own `features/*/providers/`, which watches the shared providers in `app/providers/`. Redeclaring a repository or engine provider is a review reject (ARCH_1 §7.3). |
| **U20** | Every column assigned to your phase in §7 is reachable by a user before the phase is done, or is recorded in §7.3 as a deliberate deferral with the phase that will take it. |
| **U21** | **A `Row` pairing a flexible label with a value that grows under text scale must stack above 1.5×.** `Row([icon, Expanded(label), value])` gives `value` unbounded width; at 2× it takes its natural size, `Expanded` gets nothing, and the label wraps to dozens of lines. `Flexible` on the value is the wrong fix — against a tight `Expanded` the two split evenly and the *label* truncates at scale 1. Use `MediaQuery.textScalerOf(context).scale(1) >= 1.5` and stack, or use a `Wrap`. Never clip a `Money` or `Qty` to fit: `AmountText` and `QtyText` clip rather than ellipsise, so a clipped figure is a wrong figure. The overflow is reported against the ancestor `Column`, not the offending grandchild — measure each child with `tester.getSize`, do not reason from the stack trace. |
| **U22** | **One user action has one write path.** Where a repository method owns a write end-to-end — `payOccurrence` writing a transaction *and* settling its occurrence, `RecurringRepository.materialiseUpTo` creating occurrences — exactly one surface may reach it, and any form that also writes must route through the same method rather than alongside it. Two reachable paths for one action produce two records, and the user sees no reason why. |
| **U23** | **Resolve a required value before asking for it.** A field the repository requires is still friction if the answer is already stored: check the owning entity's default, then the app-wide setting, then a sole candidate. Ask only on genuine ambiguity, say that the answer will be remembered, and remember it. Never make a column nullable to avoid the question — an unattributed withdrawal makes every balance quietly wrong. |
| **U24** | **A value derived from a text field is recomputed on every change, never seeded once.** A field fires per keystroke, so `x ?? derive(input)` locks in the answer for the first character — typing `30` set three days and kept it. Recompute on every change, and record an explicit flag when the user overrides the derived value so the recomputation stops trampling a deliberate choice. |
| **U25** | **A rejection shown in the form clears on the next edit.** A refused save deserves longer than a snack, so the repository's message is also rendered in place — but a message that survives the edit which fixes it is a stale error the user must dismiss by hand. Clear it on any change; keep it only across the save itself. |

---

## 2. Visual language

### 2.1 The two modes

Every screen serves one of two jobs, and it must be obvious which:

| Mode | Where | Design consequence |
|---|---|---|
| **Capture** | quick-add, consume sheet, pay sheet, line editor | One required field. Keyboard up on open. Commit button above the keyboard. Nothing that requires reading. Target: under 8 seconds, one hand, at a till. |
| **Review** | lists, detail, dashboard, analytics | Dense, scannable, informative. Two-handed and unhurried. Nothing hidden behind a tap that could have been shown. |

A screen that tries to be both becomes a form nobody wants to fill in at a checkout. When in doubt,
split it: capture the amount, then offer *Add details*.

### 2.2 Layout grid

- **Screen margin** — `AlayaSpacing.screenEdge` (16). Nothing touches the edge except a divider,
  an image and a full-bleed sheet handle.
- **Between related rows** — `sm` (12). **Between sections** — `xl` (24). **Above a section
  header** — `xl`, below it `xs`.
- **Card padding** — `md` (16), `lg` (20) for a card that carries a headline number.
- **Vertical rhythm inside a row** — `xxs` (4) between a title and its subtitle.
- Dividing lines are `1px` at `dividerColor`, used **only** between rows of the same kind. Sections
  separate by space, not by rules.

### 2.3 Typography, by role

The scale exists; the discipline is using the right member. One style per role, no `copyWith` on
`fontSize` anywhere.

| Role | Token | Where |
|---|---|---|
| The one number on the dashboard | `displayAmount` (40) | Total available funds. Once per screen, at most. |
| A card's headline figure | `amountLarge` (24) | Detail screen hero, quick-add field |
| A ledger row's amount | `amountMedium` (16) | Every list row |
| A converted or secondary figure | `amountSmall` (13) | "≈ USD 14.20" under the original |
| Quantity | `quantity` (15) | Item rows, batch chips |
| Screen title | `screenTitle` (20) | App bar only |
| Card / list-row title | `cardTitle` (16) | Payee name, item name, asset name |
| Body copy | `body` (15) | Empty-state bodies, notes, descriptions |
| Emphasised body | `bodyEmphasis` (15) | The one line in a sheet that carries the consequence |
| Field label | `label` (13) | Input labels, key in a key/value row |
| Metadata | `caption` (12) | Date, account name, "3 items", helper text |
| Section header | `sectionHeader` (13) | Upper-cased by `SectionHeader`, never in the ARB |
| Chip / eyebrow | `overline` (11) | Tags, status chips |
| Button | `button` (15) | Every button label |

**Tabular figures are on every numeric style already.** Do not override a numeric style with a body
style to "make it match" — a column of amounts that jitters as values change is the thing tabular
figures exist to prevent.

### 2.4 Colour

- Semantic only, via `context.semantic`. A widget that names a hue has a bug.
- **The red/green rule lives in `AlayaSemanticColors.forAmount` and nowhere else.** Never re-derive
  it from a sign, a kind or a subtype at a call site.
- A transfer is `transfer`, not red-then-green. Pass `kind` to `AmountText` whenever you have it.
- Zero is `muted`. A zero balance is not income.
- `warning` / `danger` / `success` are for **state**, never for emphasis. A section header is not
  warning-coloured because it is important.
- A user-chosen `tag.colorArgb` is data, not palette. It may tint a 8dp dot and nothing else — there
  is no way to guarantee a readable foreground over an arbitrary background.
- Every status colour is paired with a word (U17). `expiringSoonLabel` next to an amber dot, not an
  amber dot alone.

### 2.5 Surface and depth

Four tiers, and depth is a palette step rather than a shadow — which is what keeps a card legible in
dark mode, where a soft black shadow on a near-black ground says nothing.

| Tier | Use |
|---|---|
| `-1` sunken | An input's fill, a well the user types into |
| `0` base | The screen |
| `1` raised | A card. The default. |
| `2` overlay | A sheet, a dialog, the selected row in a picker |

Never nest a tier-1 card inside a tier-1 card. If content needs grouping inside a card, use space
and a `SectionHeader`.

### 2.6 Motion

Four things animate. Nothing else.

| What | Token | Note |
|---|---|---|
| Route transition | handled by `pageTransitionsTheme` | Do not wrap a screen in your own transition. |
| Sheet in/out | framework | `AlayaBottomSheet` only. |
| FAB unfold | `AlayaDurations.slow` | The one expressive moment in the app. |
| A value changing in place | `AlayaDurations.base` | `AnimatedSwitcher` on a total that recalculates, so the user sees *that* it changed. |

Error feedback uses `ShakeOnError`, keyed on an incrementing int so two consecutive failures shake
twice. Everything respects `MediaQuery.disableAnimationsOf` by **skipping**, not shortening.

No decorative animation, no parallax, no staggered list entry. The app is opened for twenty seconds.

### 2.7 Iconography

- **Material Symbols outlined, one weight, no mixing with filled.** A filled icon means "selected"
  and nothing else.
- Sizes come from `AlayaIconSize` (new in 6A — see §4): `sm` 16, `md` 20, `lg` 24, `xl` 40.
- An icon alone is never an action unless it is one of the six universally-understood glyphs: back,
  close, search, add, more, delete. Everything else carries a label or a tooltip **and** a
  `Semantics` label.
- Never an icon-only row in a list. Icons identify; words explain.

### 2.8 Copy

Written in the ARB, reviewed as product surface, not as strings.

- Second person, active voice, present tense. "Add your first expense", not "No data available".
- **Never apologise.** No "Sorry", no "Oops", no "!". State what happened and what to do.
- A confirmation names the consequence: *"Delete this transaction? The 2 kg of potatoes it added
  will stay in your inventory."* Not *"Are you sure?"*
- Numbers always carry their unit or currency. Never a bare `4450`.
- Empty states name the next action and offer it as a button.
- Sentence case everywhere. `SectionHeader` upper-cases in Dart so the ARB keeps the sentence a
  translator writes and a screen reader gets the original.

---

## 3. The six screen archetypes

Start from the matching skeleton. Deviating is allowed; inventing a seventh is not (U1).

### A — Capture sheet

*Quick-add, consume, pay, snooze, line item.* Mode: capture.

```
AlayaBottomSheet
  Column(min)
    [title — cardTitle]
    [the ONE required field, autofocus: true]
    [2–4 chip rows of optional context: account, tag, date — never a dropdown]
    [SizedBox xl]
    [FilledButton — full width, the commit]
    [TextButton — the escape, only if dismiss is ambiguous]
```

- Opens with the keyboard up and focus in the required field.
- Optional context is **chips, not pickers**. A chip row shows the current choice and the two most
  likely alternatives; "More…" opens a picker. A dropdown in a capture sheet costs two taps and a
  read.
- Commit is enabled the moment the required field parses. Everything else has a default.
- Dismissing with only the required field touched discards silently. Dismissing after any optional
  edit prompts (U10).
- Never more than one screen-height of content. If it needs scrolling to reach the commit button, it
  is an Editor, not a Capture sheet.

### B — Editor screen

*Transaction editor, item editor, asset editor, template builder.* Mode: capture-then-review.
Route: **outside the shell** (U18).

```
Scaffold
  appBar: AppBar(leading: CloseButton, title, actions: [overflow only])
  body: AlayaFormScaffold
          SingleChildScrollView
            SectionHeader + fields
            SectionHeader + fields
            ...
  footer (sticky, above the keyboard): [Secondary] [Primary — commit]
```

- **`CloseButton`, not a back arrow** — an editor is a task, and ✕ says "abandon" where ← says "go
  up". Both route through the unsaved-changes guard.
- Sections group by *decision*, not by table. "What and how much", "Where it came from", "What you
  bought" — never "transactions" and "transaction_lines".
- The commit is in the sticky footer (U14) and states the action: "Save expense", not "Save".
- Validation is on submit, not on blur. An error appears inline under its field, focus moves to the
  first invalid field, and `ShakeOnError` fires once.
- A subtype/kind switch changes the visible sections and **preserves every field the new shape still
  has**. Changing grocery → household must not clear the amount.

### C — Ledger list

*Transactions, stock movements, occurrences, service records.* Mode: review. Append-only truths.

```
Scaffold (inside the shell)
  appBar: AppBar(title, actions: [search, filter])
  body: [FilterChipBar — visible only when a filter is active]
        CustomScrollView
          SliverPersistentHeader (sticky date header)
          SliverList.builder (rows)
          ...
  floatingActionButton: capture
```

- **Grouped by day, with sticky date headers.** A finance ledger without date grouping is unreadable
  past twenty rows.
- A row is at most three lines: primary (title + amount), secondary (metadata), tertiary (chips,
  only when non-empty). Amount right-aligned and tabular; everything else left.
- Active filters are always visible as removable chips. A filter you cannot see is a bug report
  waiting to happen ("my transactions disappeared").
- **No pull-to-refresh.** The data is local and streamed; a refresh gesture that cannot do anything
  teaches the user the app is slow.
- Swipe actions are permitted only with a long-press menu offering the same actions — swipe is
  invisible to anyone who has not been told.
- Loading is a **skeleton**, not a spinner (§5.2).

### D — Catalogue list

*Items, assets, shopping entries, recurring templates, accounts.* Mode: review. Things, not events.

```
Scaffold (inside the shell)
  appBar: AppBar(title, actions: [overflow])
  body: [AlayaSearchField — pinned, not in the app bar]
        [segment / group chips]
        CustomScrollView
          SliverList.builder of group sections
  floatingActionButton: add
```

- Search is a visible field, not a magnifying glass. Catalogues are searched constantly.
- Grouped by the user's own axis — tag for items, type for assets, list for shopping.
- A row carries: leading identity (icon or colour dot), title, the one number that matters
  (stock on hand, next due, price), and a status chip when abnormal.
- Tapping a row opens Detail. Long-press opens the same actions as the detail screen's overflow.

### E — Detail screen

*One transaction, item, asset, template.* Mode: review. Route: **outside the shell** (U18).

```
Scaffold
  appBar: AppBar(back, title, actions: [edit, overflow])
  body: SingleChildScrollView
          [Hero card — the headline figure + status chips]
          [SectionHeader + KeyValueRows]
          [SectionHeader + related list, e.g. lines / batches / history]
          [SizedBox xxl]
          [Destructive actions — last, quiet, never a filled button]
```

- The hero card answers the question the user opened the screen with, in one glance.
- Everything else is `KeyValueRow`. A null value **hides its row** rather than rendering "—" — a
  screen full of dashes reads as broken data.
- Related records are a real list with their own tap targets, not a summary string.
- Destructive actions sit at the bottom in `danger` text on a plain surface. Never a red filled
  button at the top, which is a mis-tap waiting to happen.

### F — Overview

*Dashboard, analytics home.* Mode: review.

```
Scaffold (inside the shell)
  body: CustomScrollView
          [Funds header — the one displayAmount + unconverted chip]
          [Range row — labelled, always]
          [Insight card — switchable]
          [Module grid]
  floatingActionButton: AlayaExpandableFab
```

- **One `displayAmount` per screen.** Two headline numbers is no headline number.
- Every range is labelled with what it means (ARCH_4 A33). Never an unlabelled "last month".
- A card that cannot compute shows its own error or empty state inline. One failing card never
  blanks the dashboard.
- The module grid is navigation, not decoration — every tile carries a live number.

---

## 4. Component contracts

### 4.1 Already delivered (Phase 5 + fix pack)

| Widget | Contract | Never |
|---|---|---|
| `AmountText` | The only path from `Money` to pixels. Signed, tabular, semantic colour. | Ellipsise. Clip is deliberate — give it room. |
| `QtyText` | The only path from `Qty` to pixels. | Colour by sign; a quantity has no direction. |
| `AlayaCard` | Tier-based surface, visible ink when tappable. | Nest inside another tier-1 card. |
| `TagChip` | Tappable chips reach 48dp; display-only stay compact. | Fill with `tag.colorArgb`. |
| `SectionHeader` | Upper-cases in Dart, passes the original to semantics. | Receive an already-upper-cased ARB string. |
| `EmptyState` / `ErrorState` / `LoadingState` | Scroll-safe via `ScrollSafeCenter`. | Be given a fixed-height box smaller than their content. |
| `ConfirmSheet` | Returns `false` on dismissal, never null. | Ask "are you sure". |
| `ShakeOnError` | Keyed on an incrementing int. | Be keyed on a bool. |
| `AlayaExpandableFab` | Sizes to content; `TapRegion` + `PopScope` dismissal. | Contain a `Stack` that expands, or a `Positioned.fill`. |
| `AlayaDrawer` | Resolves a nested location to its section. | Be the navigation for a detail route. |
| `AmountField` | `MoneyParser`; never rewrites mid-typing. | Reject a trailing decimal point out loud. |
| `QtyField` | `QtyParser`; integer-only (L2). | Round a value the unit cannot express. |
| `UnitPicker` / `AccountPicker` | Category- and archive-filtered, `isExpanded`. | Trust the caller's filtering. |
| `DatePickerField` | Works in `DateKey` throughout. | Hold a `DateTime` in state. |
| `AlayaBottomSheet` | The only sheet scaffold. | Be bypassed by `showModalBottomSheet`. |
| `ScrollSafeCenter` | Centre, scroll only when it must. | Be given unbounded height. |

### 4.2 Required before 6A's screens

Created in 6A, in `lib/shared/` and `lib/app/theme/tokens/`. Later phases reuse and never re-create.

| File | What |
|---|---|
| `app/theme/tokens/alaya_icon_size.dart` | `sm` 16, `md` 20, `lg` 24, `xl` 40. Closes the last raw-number gap (U6). |
| `shared/widgets/date_text.dart` | The only path from `DateKey` to pixels (U7). Styles: `full`, `medium`, `dayMonth`, `relative` ("Today", "Yesterday", then the date). Locale-aware via `intl`, takes the `Clock` for `relative`. |
| `shared/widgets/key_value_row.dart` | Label/value row for detail screens. **Renders nothing when the value is null.** |
| `shared/widgets/status_chip.dart` | Semantic status pill: label + optional glyph + semantic colour. The single home for `needsReview`, `unallocated`, `detached`, `overdue`, `expiring`, `low`, `approximate`. |
| `shared/widgets/alaya_form_scaffold.dart` | Scroll body + sticky footer above the keyboard + unsaved-changes guard (`PopScope`) + submit-in-progress state. Every Editor uses it (U10, U14). |
| `shared/widgets/alaya_list_skeleton.dart` | Shimmerless placeholder rows for list loading (§5.2). |
| `shared/widgets/alaya_search_field.dart` | Debounced, clearable, with a `Semantics` label. Used by 6B/6C/6E. |
| `shared/feedback/undo_snack.dart` | `showUndoSnack(context, message, onUndo)` — the single implementation of U9's success path, using `AlayaDurations.snack`. |
| `shared/widgets/filter_chip_bar.dart` | Renders active filters as removable chips; hidden when empty (archetype C). |

Nine files, all thin. Every one exists because otherwise five feature phases each write their own.

---

## 5. Interaction and feedback

### 5.1 The four states, concretely

| State | Ledger / catalogue list | Detail | Editor |
|---|---|---|---|
| Loading | `AlayaListSkeleton` (5 rows) | Skeleton hero + 3 key/value rows | Disabled fields, footer spinner |
| Empty | `EmptyState` with the creating action | n/a (a detail always has data) | n/a |
| Error | `ErrorState` with retry | `ErrorState` with retry | Inline under the field + snack for the write |
| Populated | rows | content | fields |

An `AsyncValue` is consumed as `when(data:, loading:, error:)`. There is no fourth branch and no
`.value!`.

### 5.2 Loading, precisely

- **Under ~300 ms** — show nothing. A flash of spinner is worse than a pause.
- **A list** — `AlayaListSkeleton`. The shape of what is coming beats a spinner every time.
- **An in-place action (save, pay, consume)** — the button enters a progress state and the form
  disables. Never a full-screen barrier.
- **Never** a `CircularProgressIndicator` centred in a screen that is about to be a list.

### 5.3 Feedback for writes (U9)

| Outcome | Surface |
|---|---|
| Created / updated, undoable | Snack bar: what happened + **Undo**. `AlayaDurations.snack`. |
| Created / updated, not undoable | Snack bar: what happened. No action. |
| Deleted (soft) | Snack bar + Undo. Always. Soft delete exists precisely so this is possible. |
| Failed on a field | Inline error under the field + `ShakeOnError` + focus moves there. |
| Failed on the write | Snack bar naming the operation, with **Retry** where retrying is safe. |

One snack bar at a time. A second replaces the first rather than queueing.

### 5.4 Undo, per entity

Follows ARCH_3 §4.1 rather than inventing a second policy.

| Action | Undo |
|---|---|
| Transaction delete | Clear `deletedAt`. **Also restores the fan-out link**, never re-creates a batch. |
| Stock consume | Writes a **reversing movement** (`reversesMovementId`), never deletes the original. |
| Shopping entry check | Toggle back. |
| Low-stock suggestion dismiss | Toggle `autoState`. |
| Recurring occurrence pay | Undo the occurrence **and** the transaction it created, in that order, and say so in the confirmation. |
| Asset dispose | Status change back to `active`. Never a delete. |
| Item delete | Restores the item and its cascade-deleted batches. |

### 5.5 Destructive actions (U8)

Three tiers:

| Tier | Example | Treatment |
|---|---|---|
| Reversible | delete a transaction | Do it, snack with Undo. **No confirmation.** A confirm dialog on an undoable action is friction with no safety value. |
| Consequential | delete an item with live batches, dispose an asset | `ConfirmSheet` naming the consequence, then Undo. |
| Irreversible | erase all data, replace-restore, empty trash | `ConfirmSheet` **plus** typed confirmation (`ERASE`, `REPLACE`), and an offer to export a backup first. |

Blocked actions are blocked, not warned: deleting an account with live transactions shows a dialog
offering **Archive** and no delete button at all (ARCH_3 §4.1).

### 5.6 Keyboard

- A screen with a text input has a scroll ancestor. No exceptions (U2).
- `textInputAction` chains fields: `next` through the form, `done` on the last, which submits.
- Numeric fields use `TextInputType.numberWithOptions(decimal: true)` and filter at the keystroke.
- The commit button is never under the keyboard. `AlayaFormScaffold` and `AlayaBottomSheet` both
  guarantee this; a screen doing its own thing does not.
- Dismissing the keyboard never dismisses the sheet.

### 5.7 Navigation

- Shell destinations: drawer, hamburger, `titleFor` from the drawer mapping.
- Detail and editor: outside the shell, back arrow or ✕ (U18).
- A tap that will lose work asks first. A tap that will not, never asks.
- Deep state (a filter, a selected range) lives in the view-model, not the route. The URL is the
  record's identity and nothing else.

---

## 6. Accessibility

Not a phase-9 pass. Each item is checkable while the screen is being written.

| Requirement | How it is met |
|---|---|
| Every target ≥ 48dp | U3. Asserted with `meetsGuideline(androidTapTargetGuideline)` in each screen's widget test. |
| Contrast ≥ 4.5:1 for text | The four palettes are pre-verified (Phase 5). Do not introduce a colour outside them. |
| Colour is never alone | U17. Amounts sign, statuses label. |
| Icon-only controls named | `Semantics(label:)` or `tooltip:` on every one. Asserted with `meetsGuideline(labeledTapTargetGuideline)`. |
| Text scale to 200% | U15. One widget test per screen at `TextScaler.linear(2)`. |
| Screen reader order | Wrap a composite row in `Semantics(container: true, label:)` so a ledger row reads as one thing, not five fragments. |
| Reduced motion | `MediaQuery.disableAnimationsOf` skips animation entirely. |
| No timed-out information | The only timed surface is the snack bar, and nothing is available *only* there. |

---

## 7. Data-surface coverage matrix

**The rule (U20): a phase is not done until every row assigned to it is reachable by a user.**

Every table in ARCH_2 appears here. If you add a table, add a row. If a column is deliberately not
surfaced, it goes in §7.3 with the phase that will take it — never nowhere.

### 7.1 By table

| Table | Create | Read | Edit | Retire | Owning phase |
|---|---|---|---|---|---|
| `app_settings` | onboarding | Settings | Settings | — | 8A |
| `currencies` | seed | Settings › Currencies | enable/disable, home currency | — | 8A |
| `currency_rates` | engine | Settings shows "rates as of …"; `approximate` chip on converted figures | — | — | 4A/8A · chip 6F |
| `units` | Settings › Units | `UnitPicker` | Settings | Settings | 8A · used 6B |
| `tags` | inline from any picker | `TagPicker`, row chips | Settings › Tags | Settings (soft) | 8A · used 6A/6B/6C |
| `attachments` | Attach sheet | thumbnail row on detail | — | delete | **8B** |
| `accounts` | onboarding + Settings | Dashboard funds, `AccountPicker` | Settings | Archive | 8A · used 6A/6F |
| `payment_methods` | Settings | chip row in editor | Settings | Settings | 8A · used 6A |
| `payees` | **inline from the transaction editor** | detail, filter, top-payees | Settings | Settings | 6A create · 8A manage |
| `transactions` | quick-add + editor | list, detail, calendar, analytics | editor | delete + undo | **6A** |
| `transaction_lines` | line editor | detail lines section | line editor | remove | **6A** |
| `transaction_tags` | `TagPicker` in editor | row chips, filter | editor | — | **6A** |
| `items` | item editor + purchase fan-out | inventory list, detail | editor | delete (cascades batches) | **6B** |
| `inventory_batches` | batch form + fan-out | item detail batch list | batch form | delete | **6B** |
| `stock_movements` | consume / waste / adjust sheets | batch detail history timeline | — (append-only) | reversal | **6B** |
| `item_tags` | item editor | item row chips, group-by | editor | — | **6B** |
| `shopping_lists` | list manager | list switcher | rename | archive | **6C** |
| `shopping_entries` | add row + auto low-stock | grouped list | inline edit | check / dismiss / snooze | **6C** |
| `recurring_templates` | template builder | template list, dashboard due | builder | pause / delete | **6D** |
| `recurring_occurrences` | engine (lazy) | template history, calendar, dashboard | pay / skip sheet | dismiss | **6D** |
| `assets` | asset editor + fan-out | asset list, detail | editor | **dispose with reason** | **6E** |
| `service_records` | service editor | asset detail history | editor | delete | **6E** |
| `asset_tags` | asset editor | asset row chips | editor | — | **6E** |
| `notification_schedule` | engine | Settings › Reminders shows what is scheduled | per-type toggles | cancel | **8B** |
| `backup_history` | backup service | Settings › Backup list | — | delete entry | **8B** |
| `analytics_cache` | engine | — (invisible by design) | — | "clear cache" in Settings | **7B** |

### 7.2 Columns most likely to be stranded

These exist, are written, and have no obvious home. Each is assigned. **Tick them explicitly.**

| Column | Must appear as | Phase |
|---|---|---|
| `transactions.needsReview` | The *"3 transactions need details"* banner, and a `StatusChip` on the row | 6A |
| `transactions.converted*` + `conversionRateRaw` | A **Freeze conversion** action on detail, then a secondary `amountSmall` line | 6A |
| `transactions.deleteReason` | Optional reason on the delete sheet | 6A |
| `transaction_lines.destination` | Destination chooser in the line editor | 6A |
| `transaction_lines.created*Id` | A tappable *"Created: LG TV"* link on the line row | 6A |
| `v_transaction_allocation.unallocatedMinor` | The *"₹20 unallocated"* chip. Never auto-balanced | 6A |
| `items.expiryNotifyDays` | Item editor field; consumed by 8B | 6B |
| `items.isFavorite` | Star on the item row + a favourites filter | 6B |
| `items.lowStockThresholdMilli` | Item editor + the `low` chip | 6B |
| `inventory_batches.origin = detached` | A `StatusChip` explaining the receipt was deleted | 6B |
| `inventory_batches.storageLocation` | Batch form field + batch row metadata | 6B |
| `stock_movements.reversesMovementId` | A *"reversed"* marker in the history timeline | 6B |
| `stock_movements.kind = waste \| expired` | Distinct entries in the consume sheet, feeding 7B's waste insight | 6B |
| `shopping_entries.autoState` + `snoozeUntilDateKey` | Snooze / dismiss actions on an auto-generated row | 6C |
| `shopping_entries.estimatedPriceMinor` | Inline field + a running list estimate | 6C |
| `shopping_entries.origin = autoLowStock` | A chip distinguishing suggested from manual | 6C |
| `recurring_templates.anchorDayOfMonth/Month/Weekday` | The frequency builder, previewing the next three dates | 6D |
| `recurring_templates.direction = inflow` | Salary appears as income, not a negative bill | 6D |
| `recurring_occurrences.paidAmountMinor` | Pay sheet pre-fills the default and records the actual; history shows both when they differ | 6D |
| `assets.type = serviceProvider` | The maid case — a person in the asset list, with salary history | 6E |
| `assets.disposal*` + `status = disposed` | Dispose flow with a reason picker; disposed assets stay visible behind a filter | 6E |
| `assets.serviceIntervalDays` / `nextServiceDueDateKey` | Editor field + the `serviceDue` chip and calendar event | 6E |
| `assets.primaryContactPhone` | A **call** action on asset detail | 6E |
| `service_records.type = salaryPaid` | Its own entry type in the service editor | 6E |
| `accounts.includeInNetWorth` | Settings toggle, explained | 8A |
| `accounts.openingBalance*` | Onboarding capture — without it a new user's real cash is invisible (A03) | 8A |
| `tags.parentTagId` | One level of nesting in Settings › Tags, and drill-down in analytics | 8A / 7B |
| `tags.allowedIn*` | The scoping matrix editor; "Kitchen" must not appear in the deposit picker | 8A |

### 7.3 Deliberately deferred

| Column / feature | Reason | Taken by |
|---|---|---|
| `attachments.*` | Table exists from 1B to avoid a migration; camera and file flow are a phase of their own | 8B |
| `analytics_cache.*` | Invisible by design; only "clear cache" ever surfaces | 7B |
| `currency_rates` per-row | No user value in a rate table; the freeze artefact and the "as of" line are enough | — |
| `CurrencyRepository.watchUnconvertedCount` | Stub today; needs the analytics read model | 7B |

---

## 8. Per-phase UI scope

Each phase lists its screens with archetypes, the coverage rows it closes, and any shared widget it
is permitted to add. **A phase adds no shared widget not listed here without recording it.**

| Phase | Screens (archetype) | Closes | May add to `shared/` |
|---|---|---|---|
| **6A** | QuickAddSheet (A) · TransactionEditor + 7 subtype forms (B) · LineItemEditor (A) · TransactionList (C) · FilterSheet (A) · TransactionDetail (E) | `transactions`, `transaction_lines`, `transaction_tags`, `payees` (create), §7.2 rows 1–6 | the nine in §4.2 |
| **6B** | InventoryList (D) · ItemDetail (E) · ItemEditor (B) · BatchEditor (B) · ConsumeSheet (A) · BatchHistory (C) | `items`, `inventory_batches`, `stock_movements`, `item_tags`, §7.2 rows 7–13 | `AlayaTimeline` |
| **6C** | ShoppingList (D) · EntryEditor (A) · GenerateSheet (A) · ConvertToPurchase (B) | `shopping_lists`, `shopping_entries`, §7.2 rows 14–16 | — |
| **6D** | TemplateList (D) · TemplateBuilder (B) · PaySheet (A) · OccurrenceHistory (C) | `recurring_templates`, `recurring_occurrences`, §7.2 rows 17–19 | `FrequencyPreview` |
| **6E** | AssetList (D) · AssetDetail (E) · AssetEditor (B) · ServiceEditor (B) · DisposeSheet (A) | `assets`, `service_records`, `asset_tags`, §7.2 rows 20–24 | — |
| **6F** | Dashboard (F) | funds header, range rows, module grid, `approximate`/`unconverted` chips | `ModuleTile` |
| **7A** | CalendarMonth (F) · DaySheet (A) | `v_calendar_events` surfaces; **implements `CalendarRepository`** | — |
| **7B** | AnalyticsHome (F) · 24 query surfaces · DrillDown (C) | `analytics_cache`, unconverted count; **implements `AnalyticsCacheRepository` + `AnalyticsPort` adapter** | `ChartCard` |
| **8A** ✅ | Onboarding (B) · Settings tree (D) · PIN setup (B) · Lock (A) — **plus 12 branches and 3 editors the row did not name but the coverage required**: payment methods, payees, currencies, security, data, about, and account/tag/unit editors | `app_settings`, `accounts`, `payment_methods`, `payees`, `units`, `currencies`, `tags` management, §7.2 rows 25–28 | — |
| **8B** ✅ | Backup (D) · Restore (B) · Trash (C) · Support Us (F) · Reminders (D) · attach sheet (A) + thumbnail strip | `attachments`, `notification_schedule`, `backup_history` | — |
| **9** | none — polish, perf, a11y sweep | — | — |

**7A and 7B carry a debt from Phase 5.** Three engines have no provider because two repository
contracts and one port adapter are unimplemented (ARCH_4 §5.1 item 15). Those are the first task of
their phase, not the last.

**8A and 8B carried the same shape of debt, and it is worth generalising.** 8A had to build `EraseService`
before any screen (nothing could erase, and two mandated flows needed it); 8B had to build an attachment
store, a trash adapter, a notification scheduler and a SAF channel, because the tables existed and nothing
read them. **Assume a UI phase owes a data-layer capability until you have checked, and check first.**

**Both phases also added seven `domain/services/` ports** — see ARCH_1 §6. A screen that needs to name a
type from `data/` is the signal.

**8A's archetype deviations, each recorded rather than requested:** the lock screen takes A's *shape* in a
`Scaffold` rather than a sheet, and uses a keypad rather than A's "keyboard up"; onboarding has no
`CloseButton` because nothing sits behind it; the settings tree has no FAB; Support Us has no
`displayAmount` because there is no honest headline number.

---

## 9. The gates

### 9.1 Screen Definition of Done

Every screen, every phase. A screen that fails one of these is not finished.

- [ ] Archetype from §3 declared in the file's doc comment
- [ ] **All four states** implemented and each has a widget test (U4)
- [ ] Added to `test/shared/layout_overflow_test.dart` if it is a sheet or a full-height state (U2)
- [ ] Renders at **320 × 640 with `textScaler` 2.0** with no exception — one test (U15)
- [ ] `meetsGuideline(androidTapTargetGuideline)` and `meetsGuideline(labeledTapTargetGuideline)` pass (U3, §6)
- [ ] Zero string literals; every label resolves from the ARB (U5)
- [ ] Zero raw colours, spacings, radii, durations, icon sizes, text styles (U6)
- [ ] Every `Money` through `AmountText`, `Qty` through `QtyText`, `DateKey` through `DateText` (U7)
- [ ] Every write produces a snack bar or an inline error (U9)
- [ ] Unsaved-changes guard on every editor (U10)
- [ ] Destructive actions follow §5.5's tier
- [ ] Watches a view-model provider; declares no repository or engine provider (U19)
- [ ] Every list virtualised (U13)
- [ ] Reachable from the drawer or from something that is (U16)
- [ ] Detail and editor routes are outside the shell (U18)

### 9.2 Phase UI Definition of Done

- [ ] Every §7 row assigned to this phase is reachable by a user, or moved to §7.3 with an owner (U20)
- [ ] **For each route added this phase, some widget navigates to it** — assert `context.push(R)` / `context.go(R)`, or an `_Entry.route` in the settings tree

  > **Added after 8B, which failed the U20 line above without noticing.** Four of five screens were built,
  > routed and tested, and no user could reach any of them: `settingsBackup`, `settingsTrash`,
  > `settingsReminders` and `support` were each referenced exactly once — by their own entry in the router.
  > Every coverage row was honestly earned. Two checks passed and neither asks the right question:
  > *every screen the router names exists*, and *every route constant is declared*. **Reaching a feature is
  > not the same as building it.** The assertion above finds all of them in one pass.
- [ ] Every `Row` pairing a flexible label with an `AmountText` or `QtyText` stacks above 1.5× (U21)
- [ ] Every failure path shows the repository's own message, not `errorBodyGeneric` (U9)
- [ ] Exactly one surface reaches each repository write this phase touches (U22)
- [ ] Every required field tries the defaults it could resolve before asking (U23)
- [ ] Every value derived from a text field recomputes per keystroke, with an override flag (U24)
- [ ] Every in-form rejection clears on the next edit (U25)
- [ ] Every §7.2 column assigned to this phase renders somewhere a user can see it
- [ ] Every screen passes §9.1
- [ ] `test/shared/layout_overflow_test.dart` grew by this phase's sheets and full-height states
- [ ] No new shared widget beyond §8's allowance, or the addition is recorded in ARCH_4 §5.1
- [ ] Goldens for any new shared widget, light and dark
- [ ] One pass on a real device in **dark mode** — dark is where surface-tier mistakes show
- [ ] One pass in **airplane mode** — nothing spins forever (U12)

---

## 10. Anti-patterns

Every one of these has shipped in this project or was one review away from shipping.

| Anti-pattern | Why it is wrong | Instead |
|---|---|---|
| `Material(color: transparent)` wrapping an opaque `DecoratedBox` | A `Material` paints ink **beneath** its child, so the ripple is invisible and the control feels dead | Put the colour on the `Material` |
| `Positioned.fill` scrim inside `Scaffold.floatingActionButton` | The slot clips it, so the scrim neither dims nor receives its tap — or the `Stack` expands and throws the button across the screen | `TapRegion` + `PopScope` |
| `Center` around a min-sized `Column` as a full-height state | Overflows the moment the viewport is short | `ScrollSafeCenter` |
| `Padding(bottom: viewInsets)` around a min-sized `Column` in a sheet | Each half is correct; together the padding shrinks the space and the Column cannot give up the room | `AlayaBottomSheet` |
| `DropdownButtonFormField` without `isExpanded: true` in a narrow box | Lays out at the widest item's natural width, then overflows | Always `isExpanded: true` |
| `MediaQuery` above `MaterialApp` in a test | `WidgetsApp` re-establishes it from the view; the override never arrives | `MaterialApp.builder` |
| A detail route inside the drawer shell | `AppBar` checks `hasDrawer` before `canPop`, so you get a hamburger where back belongs | Route outside the shell (U18) |
| Passing a stale entity to a `DropdownButtonFormField` | Value equality covers every field, so it matches no item and renders blank | Resolve to the instance in the item list, key on its id |
| `spinner` in the middle of a screen that will become a list | Reads as "slow" and shows nothing about what is coming | `AlayaListSkeleton` |
| Confirming an undoable delete | Friction with no safety value; trains the user to tap through confirmations | Do it, then Undo |
| "Are you sure?" | Says nothing about the consequence | Name what will happen |
| A `—` for every null field on a detail screen | Reads as broken data | Hide the row |
| Re-deriving red/green at a call site | Two definitions of the rule, one of which will drift | `SemanticColors.forAmount` |
| A raw `40` for an icon size | The last unguarded literal class | `AlayaIconSize` |
| `AsyncValue.value!` | Turns a loading frame into a crash | `when(data:, loading:, error:)` |
| Declaring `itemRepositoryProvider` in a feature | Three providers for one repository; `ItemCategoryResolver` caches, so its hit rate halves | Watch `app/providers/` (U19) |

---

## 11. Phase 7A amendments — laws U26–U31

Added while building the calendar and the dashboard month card. Each was found by a device or a test,
not by review, and each cost at least one round to diagnose. **U26–U28 were raised in the pre-7A
amendment note; U29–U31 are new.**

**U26 — A grid cell's main-axis extent is measured from the text scaler, never from an aspect ratio.**
`childAspectRatio` fixes a shape; text does not. Compute `mainAxisExtent` from
`MediaQuery.textScalerOf(context)` and export the widget's `maxLabelLines` so a caller can reason about
what it asked for.

**U27 — A drill-down pushes and shows a back affordance; a peer switch `go`es and does not.**
Amended twice by evidence:

* `AppBar` resolves its implied leading by checking `hasDrawer` **before** `canPop`, so a shell owning a
  drawer can never imply a back arrow. State the slot rather than relying on the implication.
* **A pathless `ShellRoute` cannot report the leaf location.** The `GoRouterState` handed to its builder
  describes the *shell's* match, and a pathless route's `matchedLocation` is its parent's — `/` for every
  screen inside the shell. Read `GoRouter.of(context).routerDelegate.currentConfiguration.uri.path`
  instead. Getting this wrong silently disables anything conditioned on location: the drawer highlighted
  Dashboard everywhere, `titleFor` named it everywhere, and a home action guarded by
  `location != dashboard` never rendered at all.

**U28 — A FAB slot has a constant width, and that width has a floor of zero.**
`endFloat` anchors by the slot's own width, so the width must not vary with content. But **Android
reports a zero-width viewport on the first frame of every launch** — the engine logs
`Width is zero. 0,0` — and `0 - 2 * md` is `-32`, which fails `BoxConstraints`' non-negative assert and
opens the app to a red screen. Any width derived by subtracting padding from a viewport dimension must
be clamped:

```dart
(MediaQuery.sizeOf(context).width - AlayaSpacing.md * 2).clamp(0.0, double.infinity)
```

No widget test caught this because **every harness sets a real viewport before pumping**. Degenerate
viewports must therefore be pumped deliberately — see `layout_overflow_test.dart`'s
`degenerate viewports` group.

**U29 — Every screen inside a drawer shell carries an explicit way home.**
The system back gesture is not an affordance. A module reached from the dashboard must offer a visible
return, and it belongs in `AppBar.actions` rather than the leading slot, so the drawer's hamburger keeps
its position — the drawer is still how peers are switched. The action pops when there is something to
pop and navigates otherwise, so arrival by `push` and by `go` both end in the same place:

```dart
onPressed: () => context.canPop() ? context.pop() : context.go(Routes.dashboard)
```

**Phase 9 and later: this action exists and must survive.** It is one `IconButton` in `_ShellScaffold`
in `app_router.dart` — a seven-way shared file — and it is the only way back to the dashboard other than
the system gesture. Any AppBar restyling, transition or shared-axis animation that rebuilds that bar must
preserve it.

**U30 — A seven-column date grid cannot meet the 48dp tap-target floor below 393dp, so the
interaction is measured rather than assumed.**
Seven cells at 48dp need 336dp. Inside a card with screen-edge and card padding the arithmetic is
`(width - 64) / 7`, giving 36.6dp at 320dp, 42.3dp at 360dp, 47.0dp at 393dp and 49.7dp at 412dp. The
same widget is therefore compliant on one phone and not another. Ask the constraints:

* **≥ 48dp per cell** — days accept taps.
* **below it** — `IgnorePointer` removes the gestures, `ExcludeSemantics` removes the undersized nodes,
  and a single card-sized target takes over.

Neither suppress the guideline nor drop the feature everywhere. A blanket exception would have covered
393dp, which is 1dp short.

**U31 — An amount takes its colour from its `TransactionKind`, never from a colour parameter.**
`AmountText` derives the hue itself. Passing a colour duplicates a mapping the widget owns and drifts
from it the first time the palette is retuned. Also amended into **U21**: at a doubled text scale an
amount does not sit *beside* text it competes with — the `EventCard` amount moved below the title because
as the Row's one inflexible child it starved the `Expanded` column to 64dp and a `StatusChip` that cannot
shrink overflowed by 124dp. A labelled `TextButton` beside a title behaves the same way, wanting 435dp of
256 available: give it its own row and let the label wrap.
