# Phase 5 — Theme System, Routing, Localisation Scaffold & Shared Widgets

> **Regenerated 2026-08-05 from the canonical tree.** Folds in the four post-6F fix rounds: the
> twenty-six-failure test pass, the insight-card host correction, and the two on-device UI passes — FAB
> action alignment, module-grid navigation, and the range-row split. Earlier revisions reintroduce defects
> listed in ARCH_6 §3 and the new shapes P15–P18 in `ARCH_AMENDMENTS_PRE_7A.md`.
>
> Files shared with other phase documents — `app_en.arb`, `routes.dart`, `app_router.dart`,
> `layout_overflow_test.dart`, and the Phase 6A editor files amended by 6B, 6C and 6D — carry
> **identical** content in every copy, so they may be applied in any order.


**Complete. 42 files, 5,059 lines.** This supersedes both earlier partial deliveries — apply this
file and discard `PHASE_05_SHELL.md` (part 1) and `PHASE_05_SHELL_PART2.md`. Every DELIVER item is
present, verified mechanically at 42/42.

---

## Before you apply this: three setup steps

### 1. Dependencies — the task's list is incomplete

```bash
flutter pub add flutter_riverpod go_router
flutter pub add flutter_localizations --sdk=flutter
flutter pub add intl
```

The task specified only the first line. The other two are not optional: `app.dart` uses
`GlobalMaterialLocalizations.delegate` from `flutter_localizations`, and the file `flutter gen-l10n`
produces imports `intl`. Per the standing rule I list only what this phase's code actually imports —
and it imports these.

### 2. One pubspec flag, or nothing compiles

Add to the existing `flutter:` section of `pubspec.yaml`:

```yaml
flutter:
  generate: true
```

**Without it `flutter gen-l10n` fails outright** with *"Attempted to generate localizations code
without having the flutter: generate flag turned on"*. This became mandatory in Flutter 3.32 and still
holds on the pinned 3.44 — it is flutter#169209. Every widget below reads its strings from the
generated class, so nothing compiles until this is set.

This is a `flutter:` build flag, not a dependency version, so it does not touch the version-pinning
rule (ARCH_1 §7.4). It also is not a second codegen package — `gen-l10n` is a first-party command, not
a `build_runner` package, so §7.3's one-codegen rule is intact.

### 3. Run codegen in this order

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build
dart analyze
flutter test --update-goldens test/shared/golden
flutter test
```

`gen-l10n` writes `lib/app/l10n/generated/app_localizations.dart`. **That file is deliberately not in
this delivery** — the generator owns it, and shipping a hand-written copy would conflict with the real
output. I generated one locally so the import audit could resolve, then excluded it.

---

## The NOTE's question, answered: Phase 5 owns the provider graph

Delivered as three files under `lib/app/providers/`.

`bootstrap` has to construct the database regardless, so the infrastructure layer is unavoidable here.
Above that, every repository provider is a one-line call to a constructor that already exists — there
is nothing to design, only somewhere to put it. And the failure mode of deferring is specific rather
than theoretical: 6A, 6B and 6C all need `itemRepositoryProvider`, and whichever ships first defines it
wherever its author happened to be working.

`ItemCategoryResolver` settles it. It is a **caching** resolver, so constructing it twice halves the hit
rate for no benefit. One provider, three consumers.

Providers are typed as the **contract**, never the implementation, which keeps the layering rule
enforceable by signature rather than by review.

### Three services deliberately have no provider

| Service | Blocked on | Owner |
|---|---|---|
| `AnalyticsService` | `AnalyticsPort` has no `data/` adapter | 7B |
| `AnalyticsCacheService` | `AnalyticsCacheRepository` has no implementation | 7B |
| `CalendarAggregator` | `CalendarRepository` has no implementation | 7A |

The NOTE flagged the first. Wiring found the other two: **Phase 3A declared seventeen repository
contracts and Phases 3B–3D implemented fifteen.** The two outstanding are exactly the two these
services need. That is by design — the calendar and analytics read models are 7A and 7B's work — but it
was not recorded anywhere, and it means three of the twelve engines cannot be wired yet.

Stubbing any of them would be worse than omitting them. A port returning empty rows makes an unfinished
analytics screen indistinguishable from a working one that found no data. An absent provider is a
compile error at the first use site, which names the problem where someone can act on it.

### Two missing mappers, found by wiring

`CurrencyRateService` takes four function ports. Two had no adapter:

- `CurrencyRateRow → UsdRate` existed **only as a private method** inside `CurrencyRepositoryImpl`.
- `UsdRate → CurrencyRatesCompanion` **did not exist at all** — so `saveSnapshot` could never have been
  satisfied against the DAO, meaning `syncDailyRates` could not actually have run in production.

Both now live in `data/repositories/mappers/rate_mappers.dart`, and `CurrencyRepositoryImpl` delegates
to it. Writing the row map a second time in the provider would have been the fourth instance of the
duplication Phases 4A and 4B each had to undo. `currency_repository_impl.dart` is re-delivered for
that reason.

Two further mismatches the provider surfaced: `CurrencyDao.upsertRates` takes
`List<CurrencyRatesCompanion>` and not `List<UsdRate>`, and `newestRateDate` requires a `baseCode`
argument — supplied as `RateTable.pivotCode`, since a snapshot is USD-pivoted by definition.

---

## Design direction

The subject is one household's money and pantry, opened for twenty seconds at a time, often at a till.
That grounds every choice: there is no hero, and legibility beats expression.

**Typography carries the personality, because no custom font can.** Bundling a display face needs
either a font package or assets declared under `android/`, and this phase may do neither. That suits the
brief. **The one real typographic risk is `FontFeature.tabularFigures()` on every money and quantity
style.** By default most fonts set `1` narrower than `8`, so a column of amounts jitters as values
change; tabular figures force one advance width and a ledger column aligns on the decimal without a
monospace face. It matters more here than usual because `MoneyFormatter` produces Indian grouping
(`2,50,000`), whose group widths differ from Western grouping and give the eye fewer landmarks.

**Four palettes, none of them the generated-interface default.** A warm cream ground with a serif and a
terracotta accent has become the house style of AI-produced UI; picking it would say nothing about this
app. The default is **Indigo Khata** — indigo ink on bone paper with brass for anything you touch, drawn
from the bound household ledger this app replaces. **Slate Sage** is the quiet option where nothing has
chroma except numbers that mean something. **Midnight Brass** is designed dark-first on a blue-black
rather than `#000000`, because pure black collapses the surface tiers that replace shadow in dark mode.
**Monsoon Teal** is the deliberate counter-proposal: cool and high-contrast, for a phone held in
daylight.

**Depth is four surface tiers, not shadows.** `surfaceSunken` sits *below* the base rather than above it,
so an input reads as a hole you type into rather than a card you might tap.

### Accessibility, verified rather than asserted

The palettes make a specific claim: **income is lighter than expense in every set**, so the pair stays
distinguishable with hue removed. I computed WCAG relative luminance for all eight colour sets:

| | income L | expense L | body text vs base |
|---|---|---|---|
| Indigo Khata light | 0.160 | 0.091 | 14.8:1 |
| Indigo Khata dark | 0.486 | 0.366 | 15.4:1 |
| Slate Sage light | 0.152 | 0.093 | 14.4:1 |
| Slate Sage dark | 0.470 | 0.377 | 14.9:1 |
| Midnight Brass light | 0.135 | 0.088 | 15.0:1 |
| Midnight Brass dark | 0.484 | 0.352 | 16.1:1 |
| Monsoon Teal light | 0.122 | 0.073 | 15.2:1 |
| Monsoon Teal dark | 0.465 | 0.360 | 15.8:1 |

The claim holds in all eight. Body text clears AA everywhere by a wide margin and no amount colour falls
below 4.6:1. **The gap is real but modest** — in light mode income is 1.5–1.8× the luminance of expense —
so it helps rather than solves the problem, which is why `AmountText` also renders an explicit sign and
does not rely on colour alone.

---

## `AmountField`: what "never rejects intermediate states" required

Typing `1`, `1.`, `1.2` produces three inputs of which only two parse. The field rewrites the controller
in **none** of them — parsing drives `onChanged` and the error text only.

That is not cosmetic. Deleting a digit to fix a typo momentarily produces something unparseable, and a
field that reformats at that instant moves the cursor and eats the next keystroke. So a trailing decimal
point is `ParseFailure.malformed` and stays **silent**, because it is what everyone types on the way to
entering paise. Only failures that cannot become valid by typing more — invalid character, too many
decimals, too large — surface a message.

`onChanged` receives null while the input is incomplete, which is distinct from a valid zero. A Save
button disables on the former; rejecting the latter is the caller's business rule.

---

## Rule compliance, measured

| Rule | Result |
|---|---|
| No hex colour in a widget | **0** across 18 widgets, the shell and the Theme Lab |
| No raw `EdgeInsets` number | **0** — every value via `AlayaSpacing` |
| No raw `Duration` | **0** — every value via `AlayaDurations` |
| Red/green rule in exactly one place | **1** site: `AlayaSemanticColors.forAmount` |
| Every user-visible string from the ARB | 114 keys; two argued exceptions below |
| `AmountField` uses `MoneyParser`, never rejects intermediates | as above |
| One constant switches the look | `AlayaPresets.activePreset` |
| No `@riverpod` / `go_router_builder` | **0** uses |
| `drift_dev` remains the only codegen package | OK |
| No encryption anywhere | **0** hits for `PRAGMA key`, `sqlcipher`, `AesGcm` |
| `Qty.toString()` never reaches the UI | **0** — `QtyText` is the only path |

**One documented token-layer exception.** `alaya_elevation.dart` contains translucent blacks. A shadow
is occlusion, not a palette colour — always neutral black, only its opacity varying. Deriving it from
the palette would tint it, which is a coloured glow and a different effect. The file says so.

**Two deliberate literal-string exceptions.** `SectionHeader` upper-cases in Dart rather than storing
shouty text in the ARB, because casing is presentation — a translator writes a sentence, and a screen
reader that spells out capitals needs the original, which is why it passes `semanticsLabel`. And the
goldens use literals so they do not depend on `gen-l10n` having run; their job is layout.

## Audit

| Check | Result |
|---|---|
| Brace balance | 202 files, 0 |
| Missing imports — exhaustive | 0 |
| Unused imports | 0 |
| L12 — `domain/` importing flutter, drift or `data/` | 0 |
| Route strings outside `routes.dart` | 0 |
| DELIVER items present | 42/42 |

---

## Findings

**A malformed colour that would not have failed to compile.** `Color(0xFF04202333)` — ten hex digits.
Dart accepts the literal and truncates to 32 bits, so it would have rendered a silently wrong colour in
Monsoon Teal's dark set. Caught by asserting every literal is exactly eight digits.

**Four API mismatches caught while writing, not after.** `DateKey` has no `toDateTime()` — it is
`toUtcMidnight()`. `ParseFailure` has six members and the switch had to cover all of them.
`openAlayaDatabase()` takes only defaults. `Unit` keys on `code`, not `id`.

**I caught myself over-engineering `ShakeOnError`.** The first version hand-rolled a Taylor-series sine
to avoid importing `dart:math`, with a comment justifying it. Bad reasoning — the import is free and
hand-rolled trigonometry is a correctness risk for nothing. It uses `math.sin`.

**And an off-grid spacing.** `AlayaDrawer` had `AlayaSpacing.xxs / 2`, which yields 2 and is not on the
4-point scale. Dividing a token to reach an off-scale value defeats having the scale.

**`AlayaDatabase` declares no `daos:` list**, so there are no generated DAO getters. Each of the
twenty-one DAOs is `AccountDao(db)` with its own provider.

**`databaseProvider` throws when un-overridden** rather than opening a connection. A provider that
quietly opened a second one would break L10's single-open-path rule, and the symptom would be a locked
database rather than an error naming the cause.

**`ShakeOnError` keys on an incrementing int, not a bool.** Two consecutive wrong PINs must shake twice,
and a bool already `true` produces no change and therefore no second shake — which reads as the app
having ignored the attempt. It honours `MediaQuery.disableAnimations` by skipping entirely rather than
shortening.

**`ConfirmSheet.show` returns `false` on dismissal, never null**, so a caller cannot treat "they swiped
it away" as consent by forgetting a null check.

**`AmountText` always renders a sign**, an accessibility decision rather than a stylistic one. It also
never ellipsises — a truncated number reads as a smaller number, so it clips and the caller gives it
room.

**`AmountText` defaults `symbol` to the currency code, not `₹`.** `INR 1,234.00` is less pretty and never
wrong; a hardcoded symbol would be wrong for every other currency. The real symbol lives on the
`currencies` row, and 6A should pass it.

**`UnitPicker` filters by category rather than trusting its caller.** A `Qty` is a bare integer plus a
category, so offering litres for a weight stores a number that is reinterpreted on read — Law L8 broken
silently.

**`AlayaDrawer` resolves the *root* of a nested location.** `/expenses/abc123` selects Expenses;
matching the full location would leave nothing selected the moment a detail screen opened. `titleFor` is
static so the app bar titles itself from the same mapping rather than each screen repeating its name.

**A drawer, and `ShellRoute` rather than `StatefulShellRoute`.** Nine destinations is past what a bottom
bar holds without truncating labels or shrinking targets below the tap-target floor. A drawer carries no
expectation of per-tab scroll restoration, so the stateful variant would keep nine navigators alive for
nothing.

**The router takes a `LockGate` callback** rather than importing `PinService`, so Phase 6F supplies the
real gate without editing the router. It defaults to never-locked, which is provisional on purpose and
visible in the signature rather than buried in a comment.

**The goldens render on `AlayaPresets.activePreset`, so changing the palette fails them deliberately** —
that is how a palette change gets reviewed. `textScaler` is pinned to `TextScaler.noScaling`, because a
golden that moved with the host's accessibility settings would pass on one machine and fail on another,
which is worse than no golden.

**The Theme Lab enumerates from `AlayaTypography.all` and `semantic.byName`** rather than a hand-written
list, so a token added later appears without anyone remembering. In release it renders one line instead
of the lab, keeping it out of the shipped UI without a conditional route that could be got wrong.

## Standing caveat

Every audit above is a custom Python scanner, not `dart analyze`. They have agreed with the compiler on
every error reported so far, but `dart analyze` remains the real gate — and each round has shown the
next error lives in a category not yet scanned for. Two known scanner limitations surfaced this phase:
it strips string contents, so a symbol used only inside an interpolation reads as unused; and it checks
`nullable` per line, so a multi-line column declaration reads as required.



---

### `lib/shared/widgets/alaya_bottom_sheet.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_spacing.dart';

/// The app's one bottom-sheet scaffold (ARCH_3 §8.3).
///
/// **Every sheet goes through here.** It composes the keyboard inset padding, [SafeArea] and a
/// [SingleChildScrollView] in that order, exactly once — the combination each sheet otherwise gets
/// wrong in the same way. A `MainAxisSize.min` Column inside a `Padding` keyed to
/// `viewInsets.bottom` is correct in each half and broken together: the padding shrinks the
/// available height and the Column has no way to give up the room it already took, so it overflows
/// the instant a keyboard opens and never otherwise. Putting the scroll view *inside* the padding
/// turns that overflow into scroll extent instead.
///
/// Sheets therefore return content only — no `SafeArea`, no `viewInsets` padding and no scroll view
/// of their own. A sheet that adds one is reintroducing the bug.
class AlayaBottomSheet extends StatelessWidget {
  /// Wraps [child] in the sheet scaffold. Prefer [show].
  const AlayaBottomSheet({required this.child, this.padding = defaultPadding, super.key});

  /// The sheet's content, laid out as though the viewport were tall enough for it.
  final Widget child;

  /// Padding around [child]. Inside the scroll view, so it scrolls with the content rather than
  /// eating viewport height a keyboard has already taken.
  final EdgeInsetsGeometry padding;

  /// The default content padding: screen-edge horizontally, tighter at the top where the drag
  /// handle already provides separation.
  static const EdgeInsets defaultPadding = EdgeInsets.fromLTRB(
    AlayaSpacing.screenEdge,
    AlayaSpacing.xs,
    AlayaSpacing.screenEdge,
    AlayaSpacing.md,
  );

  /// Shows [builder]'s widget as a modal sheet and resolves to whatever it pops.
  ///
  /// `isScrollControlled` is not optional: without it the sheet is capped near half the screen and
  /// cannot grow when a keyboard pushes its content up. `useSafeArea` keeps the sheet clear of the
  /// status bar while deliberately leaving the bottom edge to this widget's own [SafeArea] — so the
  /// sheet's background still runs behind the navigation bar and only its content is inset.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    EdgeInsetsGeometry padding = defaultPadding,
    bool isDismissible = true,
    bool enableDrag = true,
  }) =>
      showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: isDismissible,
        enableDrag: enableDrag,
        builder: (context) => AlayaBottomSheet(padding: padding, child: builder(context)),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: padding,
            child: child,
          ),
        ),
      );
}
```


### `lib/app/theme/tokens/alaya_spacing.dart`

```dart
/// The spacing scale (ARCH_3 §8) — the only source of padding and gap values in the app.
///
/// Eight steps on a 4-point grid. A widget writing `EdgeInsets.all(13)` is a bug, not a preference:
/// once one exists, nothing keeps the next screen's rhythm consistent with this one.
///
/// The names are sizes rather than roles (`md`, not `cardPadding`) because a role-named scale
/// invites a ninth value the moment a role appears that does not fit — and then the grid is gone.
abstract final class AlayaSpacing {
  /// 4 — hairline separation, icon-to-label.
  static const double xxs = 4;

  /// 8 — inside a chip, between stacked labels.
  static const double xs = 8;

  /// 12 — between related rows.
  static const double sm = 12;

  /// 16 — the default. Card padding, screen margin.
  static const double md = 16;

  /// 20 — a slightly generous card.
  static const double lg = 20;

  /// 24 — between sections.
  static const double xl = 24;

  /// 32 — around a section header.
  static const double xxl = 32;

  /// 48 — empty-state breathing room, above a primary action.
  static const double xxxl = 48;

  /// The screen edge margin, named because it must not drift between screens.
  static const double screenEdge = md;

  /// The minimum tap target, per Material's accessibility floor.
  ///
  /// Not a spacing value so much as a constraint, but it belongs on the scale because every
  /// icon-button-sized widget in the app needs to reach it and there must be one number to reach.
  static const double minTapTarget = 48;
}
```

### `lib/app/theme/tokens/alaya_radii.dart`

```dart
import 'package:flutter/widgets.dart';

/// The corner-radius scale (ARCH_3 §8).
///
/// Four steps, deliberately shallow. A finance app is read in columns, and a heavily rounded card
/// fights the vertical alignment that makes a column of amounts scannable — so the radius is enough
/// to soften a surface and not enough to make it feel like a separate object floating away.
abstract final class AlayaRadii {
  /// 4 — chips, tags, small inline surfaces.
  static const double xs = 4;

  /// 8 — inputs, buttons.
  static const double sm = 8;

  /// 12 — cards, sheets' inner surfaces. The default.
  static const double md = 12;

  /// 20 — bottom sheets and dialogs, where the corner is a large visible arc.
  static const double lg = 20;

  /// A fully round shape, for avatars and the expandable FAB's collapsed state.
  static const double full = 999;

  /// [xs] as a [BorderRadius].
  static const BorderRadius borderXs = BorderRadius.all(Radius.circular(xs));

  /// [sm] as a [BorderRadius].
  static const BorderRadius borderSm = BorderRadius.all(Radius.circular(sm));

  /// [md] as a [BorderRadius].
  static const BorderRadius borderMd = BorderRadius.all(Radius.circular(md));

  /// [lg] as a [BorderRadius].
  static const BorderRadius borderLg = BorderRadius.all(Radius.circular(lg));

  /// A sheet's top-only radius, since its bottom edge meets the screen.
  static const BorderRadius sheetTop = BorderRadius.only(
    topLeft: Radius.circular(lg),
    topRight: Radius.circular(lg),
  );
}
```

### `lib/app/theme/tokens/alaya_durations.dart`

```dart
/// The animation duration scale (ARCH_3 §8).
///
/// Four values, and no widget writes its own. The figures are the ones ARCH_3 §8 specifies, and the
/// reason they are short is that this app is used in twenty-second bursts — logging a purchase at a
/// till. An animation the user waits through is a cost, not polish.
abstract final class AlayaDurations {
  /// 120 ms — a colour change, a check mark, a ripple settling.
  static const Duration fast = Duration(milliseconds: 120);

  /// 220 ms — the default. An expanding card, a chip toggling, a sheet's content settling.
  static const Duration base = Duration(milliseconds: 220);

  /// 380 ms — the expandable FAB unfolding, a large surface reflowing.
  static const Duration slow = Duration(milliseconds: 380);

  /// 300 ms — a route transition. Between [base] and [slow] on purpose: a page change needs to read
  /// as a change of place, which [base] is too brisk to convey, without making navigation feel slow.
  static const Duration page = Duration(milliseconds: 300);

  /// 90 ms — one leg of the error shake, which is four legs plus a settle.
  static const Duration shakeLeg = Duration(milliseconds: 90);

  /// 2.5 s — how long a snack bar stays.
  static const Duration snack = Duration(milliseconds: 2500);

  /// 300 ms — how long a search field waits after the last keystroke before querying.
  ///
  /// An interaction delay rather than an animation, and it sits here because Law U6 says every
  /// duration in a widget comes from a token — so the token file has to hold every duration a widget
  /// needs. It is deliberately longer than [base]: a debounce tuned to an animation scale fires
  /// mid-word and makes typing feel like it is fighting the field.
  ///
  /// A **network** timeout still does not belong here. That scale is seconds and lives with the
  /// client that owns the call (see `infrastructure_providers.dart`).
  static const Duration debounce = Duration(milliseconds: 300);
}
```

### `lib/app/theme/tokens/alaya_typography.dart`

```dart
import 'dart:ui' show FontFeature;

import 'package:flutter/widgets.dart';

/// The type scale (ARCH_3 §8) — one scale, semantic names, no colours.
///
/// Every style here is colourless on purpose. Colour arrives from the palette through
/// `AlayaTheme`, so a widget that needs a warning-coloured label composes
/// `AlayaTypography.label.copyWith(color: semantic.warning)` rather than reaching for a second
/// style that happens to be the right colour. One axis per token.
///
/// **The scale carries this app's personality, because no custom font can.** Bundling a display
/// face needs either a font package or assets declared under `android/`, and this phase may do
/// neither — so the character comes from weight, size and figure treatment instead. That turns out
/// to suit the subject: a household ledger is read in columns, and what makes a column legible is
/// that the digits line up, not that the headings are expressive.
abstract final class AlayaTypography {
  /// Amounts and any figure that appears in a column.
  ///
  /// **Tabular figures are the one deliberate typographic risk in this design.** By default most
  /// fonts render proportional digits, so `1` is narrower than `8` and a column of amounts jitters
  /// left and right as the values change. `FontFeature.tabularFigures()` forces every digit to the
  /// same advance width, so a ledger column aligns on the decimal without a monospace font — and
  /// with Indian grouping (`2,50,000`) that matters more than usual, because the group widths differ
  /// from Western grouping and the eye has fewer landmarks.
  static const List<FontFeature> figures = [FontFeature.tabularFigures()];

  /// Slashed zero, where a zero could be misread as an O — account numbers, recovery codes.
  static const List<FontFeature> slashedZero = [
    FontFeature.tabularFigures(),
    FontFeature.slashedZero(),
  ];

  /// The dashboard's headline figure. One per screen, at most.
  static const TextStyle displayAmount = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w300,
    height: 1.1,
    // Negative tracking at display size: default tracking is set for body text and looks loose
    // once the glyphs are this large.
    letterSpacing: -1.2,
    fontFeatures: figures,
  );

  /// A card's primary amount.
  static const TextStyle amountLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: -0.4,
    fontFeatures: figures,
  );

  /// A ledger row's amount. The most-rendered style in the app.
  static const TextStyle amountMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
    letterSpacing: -0.1,
    fontFeatures: figures,
  );

  /// A secondary or converted amount, shown beneath the original.
  static const TextStyle amountSmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
    fontFeatures: figures,
  );

  /// A quantity, which is a figure and so shares the tabular treatment.
  static const TextStyle quantity = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.3,
    fontFeatures: figures,
  );

  /// An app-bar or screen title.
  static const TextStyle screenTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: -0.2,
  );

  /// A section header inside a scrolling screen.
  static const TextStyle sectionHeader = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    // Positive tracking and upper case in the widget: at this size a header needs to read as a
    // label rather than as small body text, and tracking does that without another weight.
    letterSpacing: 0.8,
  );

  /// A card's title.
  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Default running text.
  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// Running text that needs emphasis without becoming a heading.
  static const TextStyle bodyEmphasis = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );

  /// A form field's label.
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  /// Metadata — a date, an account name beneath a title, a unit suffix.
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  /// A small eyebrow above a section, and a chip's text.
  static const TextStyle overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.6,
  );

  /// A button's label.
  static const TextStyle button = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.1,
  );

  /// Every style, for the Theme Lab to enumerate without a hand-maintained list going stale.
  static const Map<String, TextStyle> all = {
    'displayAmount': displayAmount,
    'amountLarge': amountLarge,
    'amountMedium': amountMedium,
    'amountSmall': amountSmall,
    'quantity': quantity,
    'screenTitle': screenTitle,
    'sectionHeader': sectionHeader,
    'cardTitle': cardTitle,
    'body': body,
    'bodyEmphasis': bodyEmphasis,
    'label': label,
    'caption': caption,
    'overline': overline,
    'button': button,
  };
}
```

### `lib/app/theme/tokens/alaya_elevation.dart`

```dart
import 'package:flutter/widgets.dart';

/// The elevation scale (ARCH_3 §8).
///
/// Expressed as shadow lists rather than Material `elevation` doubles, because the same numeric
/// elevation reads very differently against a light and a dark surface — and in dark mode a
/// shadow is nearly invisible, so depth has to come from surface tiers instead. `AlayaTheme`
/// selects between [light] and [dark] accordingly, which is why both live here.
///
/// **The hex literals below are the one intentional exception to "no hex colours outside the
/// palette", and they are not palette colours.** A shadow is occlusion — light that a raised
/// surface blocked — so it is always neutral black and only its opacity changes. Deriving it from
/// the palette would tint the shadow, which is a different visual effect (a coloured glow) and one
/// no preset here asks for. The values are alpha steps, and the palette has no say in them.
abstract final class AlayaElevation {
  /// Flat. A surface that sits directly on its parent.
  static const List<BoxShadow> none = [];

  /// A card at rest, on a light background.
  static const List<BoxShadow> lightRaised = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 3)),
  ];

  /// A pressed or dragged card, a menu, on a light background.
  static const List<BoxShadow> lightFloating = [
    BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 8)),
  ];

  /// A sheet or dialog, on a light background.
  static const List<BoxShadow> lightOverlay = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, -4)),
  ];

  /// A card at rest, on a dark background.
  ///
  /// Darker and tighter than its light counterpart. A soft black shadow on a near-black surface is
  /// invisible, so the shadow's job in dark mode is only to separate an edge, and the sense of
  /// height comes from the palette's surface tiers.
  static const List<BoxShadow> darkRaised = [
    BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// A pressed or dragged card, on a dark background.
  static const List<BoxShadow> darkFloating = [
    BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3)),
  ];

  /// A sheet or dialog, on a dark background.
  static const List<BoxShadow> darkOverlay = [
    BoxShadow(color: Color(0x59000000), blurRadius: 20, offset: Offset(0, -2)),
  ];

  /// The raised shadow for [isDark].
  static List<BoxShadow> raised({required bool isDark}) => isDark ? darkRaised : lightRaised;

  /// The floating shadow for [isDark].
  static List<BoxShadow> floating({required bool isDark}) => isDark ? darkFloating : lightFloating;

  /// The overlay shadow for [isDark].
  static List<BoxShadow> overlay({required bool isDark}) => isDark ? darkOverlay : lightOverlay;
}
```

### `lib/app/theme/palettes/palette.dart`

```dart
import 'package:flutter/widgets.dart';

/// A complete palette as **data**, which is the whole point of ARCH_3 §8.
///
/// Every colour the app can render is a field here. Nothing is computed from a seed and nothing is
/// derived at use time, because both make "change the palette later, easily" false: a seeded scheme
/// means you cannot adjust one colour without moving others, and a derived colour means the value
/// you see on screen exists in no file you can edit.
///
/// A preset supplies light **and** dark in one object rather than two, so a half-migrated palette —
/// light updated, dark forgotten — cannot compile.
@immutable
class AlayaPalette {
  /// Creates a palette.
  const AlayaPalette({
    required this.name,
    required this.description,
    required this.light,
    required this.dark,
  });

  /// The identifier shown in Settings and the Theme Lab.
  final String name;

  /// One line on what this palette is for — read by a human choosing between them.
  final String description;

  /// The light-mode colours.
  final AlayaColorSet light;

  /// The dark-mode colours.
  final AlayaColorSet dark;

  /// The set for [isDark].
  AlayaColorSet forMode({required bool isDark}) => isDark ? dark : light;
}

/// One mode's complete colour set.
///
/// The four surface tiers are the structural idea. Rather than one background colour plus shadows,
/// depth is expressed by stepping through tiers — which is what makes dark mode legible, since a
/// shadow on a near-black surface conveys nothing.
@immutable
class AlayaColorSet {
  /// Creates a colour set.
  const AlayaColorSet({
    required this.surfaceBase,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.surfaceSunken,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.divider,
    required this.income,
    required this.expense,
    required this.transfer,
    required this.warning,
    required this.danger,
    required this.success,
    required this.onStatus,
  });

  /// Tier 0 — the screen behind everything.
  final Color surfaceBase;

  /// Tier 1 — a card sitting on the base.
  final Color surfaceRaised;

  /// Tier 2 — a sheet, dialog or menu above a card.
  final Color surfaceOverlay;

  /// Tier -1 — an inset well: a text field's fill, a disabled row, a chart's plot area.
  ///
  /// Below the base rather than above it, which is why it is not simply "tier 3". An input needs to
  /// read as a hole you type into, not a card you might tap.
  final Color surfaceSunken;

  /// The brand colour. App bar accents, selected states, the primary button.
  final Color primary;

  /// Text and icons on [primary].
  final Color onPrimary;

  /// The interactive accent, used sparingly — the FAB, a focused field's border.
  ///
  /// Separate from [primary] so that "the brand" and "the thing you tap" can differ. When they are
  /// the same colour, every branded surface looks tappable.
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;

  /// Primary reading colour.
  final Color textPrimary;

  /// Supporting text — an account name beneath a payee.
  final Color textSecondary;

  /// De-emphasised text — a timestamp, a disabled label, placeholder text.
  final Color textMuted;

  /// Hairlines and borders.
  final Color divider;

  /// Money arriving.
  final Color income;

  /// Money leaving.
  final Color expense;

  /// Money moving between the user's own accounts — neither a gain nor a loss.
  final Color transfer;

  /// Something needs attention soon.
  final Color warning;

  /// Something is wrong or overdue.
  final Color danger;

  /// Something completed.
  final Color success;

  /// Text and icons on any of [warning], [danger] or [success] used as a fill.
  final Color onStatus;
}
```

### `lib/app/theme/palettes/presets.dart`

```dart
import 'package:flutter/widgets.dart';

import 'package:alaya/app/theme/palettes/palette.dart';

/// The palettes that ship, and the one constant that switches the app's entire look (ARCH_3 §8).
///
/// **Deliberate constraint on income and expense: they differ in lightness as well as hue.** Roughly
/// eight percent of men have some red-green deficiency, and a finance app that encodes gain and loss
/// in hue alone is unreadable for them. In every preset below, income is the lighter of the pair —
/// so even with hue removed the two remain distinguishable, and `AmountText` additionally renders an
/// explicit sign rather than relying on colour at all.
abstract final class AlayaPresets {
  /// The palette the app boots with.
  ///
  /// **Changing this one constant changes the entire app's look**, which is the requirement ARCH_3 §8
  /// exists to satisfy. Nothing else needs editing.
  static const AlayaPalette activePreset = indigoKhata;

  /// Every preset, for Settings and the Theme Lab.
  static const List<AlayaPalette> all = [
    indigoKhata,
    slateSage,
    midnightBrass,
    monsoonTeal,
  ];

  /// Indigo ink on bone paper, with brass for anything you touch.
  ///
  /// The default. Drawn from the bound household ledger this app replaces — indigo dye and the brass
  /// of a ledger clasp — rather than from a generic finance blue. The background is bone rather than
  /// cream: cream with a serif and a terracotta accent has become the default look of generated
  /// interfaces, and picking it would say nothing about this app.
  static const AlayaPalette indigoKhata = AlayaPalette(
    name: 'Indigo Khata',
    description: 'Indigo ink on bone paper, brass for anything you touch.',
    light: AlayaColorSet(
      surfaceBase: Color(0xFFF6F5F1),
      surfaceRaised: Color(0xFFFFFFFF),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFECEAE3),
      primary: Color(0xFF2A3A6B),
      onPrimary: Color(0xFFFFFFFF),
      accent: Color(0xFF9A6A1E),
      onAccent: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF1B2033),
      textSecondary: Color(0xFF515873),
      textMuted: Color(0xFF868CA3),
      divider: Color(0xFFDDDAD1),
      income: Color(0xFF2E7D5B),
      expense: Color(0xFF9E2A2B),
      transfer: Color(0xFF4A5578),
      warning: Color(0xFF9A6A1E),
      danger: Color(0xFF9E2A2B),
      success: Color(0xFF2E7D5B),
      onStatus: Color(0xFFFFFFFF),
    ),
    dark: AlayaColorSet(
      surfaceBase: Color(0xFF14161F),
      surfaceRaised: Color(0xFF1D202C),
      surfaceOverlay: Color(0xFF262A38),
      surfaceSunken: Color(0xFF0E1017),
      primary: Color(0xFF98AEE8),
      onPrimary: Color(0xFF121727),
      accent: Color(0xFFD9A650),
      onAccent: Color(0xFF231803),
      textPrimary: Color(0xFFECEDF2),
      textSecondary: Color(0xFFA8AEC4),
      textMuted: Color(0xFF767D93),
      divider: Color(0xFF2E3342),
      income: Color(0xFF6FCB9F),
      expense: Color(0xFFE58A87),
      transfer: Color(0xFF98A4C8),
      warning: Color(0xFFD9A650),
      danger: Color(0xFFE58A87),
      success: Color(0xFF6FCB9F),
      onStatus: Color(0xFF121727),
    ),
  );

  /// Cool grey with sage, for when the app should disappear.
  ///
  /// The quiet option. Almost no saturation outside the semantic colours, so the only thing with any
  /// chroma on screen is a number that means something.
  static const AlayaPalette slateSage = AlayaPalette(
    name: 'Slate Sage',
    description: 'Cool grey with sage. Nothing has colour except the numbers that matter.',
    light: AlayaColorSet(
      surfaceBase: Color(0xFFF4F5F5),
      surfaceRaised: Color(0xFFFFFFFF),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFE9EBEB),
      primary: Color(0xFF3D4A47),
      onPrimary: Color(0xFFFFFFFF),
      accent: Color(0xFF5E8B72),
      onAccent: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF1E2422),
      textSecondary: Color(0xFF56605D),
      textMuted: Color(0xFF8B9491),
      divider: Color(0xFFD9DDDC),
      income: Color(0xFF2F7A57),
      expense: Color(0xFF98342F),
      transfer: Color(0xFF4F5F5B),
      warning: Color(0xFF8A6516),
      danger: Color(0xFF98342F),
      success: Color(0xFF2F7A57),
      onStatus: Color(0xFFFFFFFF),
    ),
    dark: AlayaColorSet(
      surfaceBase: Color(0xFF161918),
      surfaceRaised: Color(0xFF1F2322),
      surfaceOverlay: Color(0xFF282D2B),
      surfaceSunken: Color(0xFF101312),
      primary: Color(0xFFA7BCB4),
      onPrimary: Color(0xFF15201C),
      accent: Color(0xFF86B79A),
      onAccent: Color(0xFF102016),
      textPrimary: Color(0xFFE9ECEB),
      textSecondary: Color(0xFFA6AFAC),
      textMuted: Color(0xFF757E7B),
      divider: Color(0xFF2F3533),
      income: Color(0xFF74C79C),
      expense: Color(0xFFE0908B),
      transfer: Color(0xFF9DA9A5),
      warning: Color(0xFFD3AC5F),
      danger: Color(0xFFE0908B),
      success: Color(0xFF74C79C),
      onStatus: Color(0xFF15201C),
    ),
  );

  /// Brass and copper on blue-black. Dark-first.
  ///
  /// Designed dark and then given a light mode, rather than the reverse. The base is a blue-black
  /// rather than pure black: on OLED, `#000000` makes the surface tiers collapse into one another,
  /// so the sense of depth that replaces shadow in dark mode disappears exactly where it is needed.
  static const AlayaPalette midnightBrass = AlayaPalette(
    name: 'Midnight Brass',
    description: 'Brass and copper on blue-black. Built dark first.',
    light: AlayaColorSet(
      surfaceBase: Color(0xFFF2F1EE),
      surfaceRaised: Color(0xFFFCFBF9),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFE6E4DF),
      primary: Color(0xFF2B2E3A),
      onPrimary: Color(0xFFF7F3EA),
      accent: Color(0xFF8A6220),
      onAccent: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF1A1C24),
      textSecondary: Color(0xFF4F5361),
      textMuted: Color(0xFF848897),
      divider: Color(0xFFD8D5CE),
      income: Color(0xFF2C7355),
      expense: Color(0xFF973027),
      transfer: Color(0xFF4A4E5E),
      warning: Color(0xFF8A6220),
      danger: Color(0xFF973027),
      success: Color(0xFF2C7355),
      onStatus: Color(0xFFFFFFFF),
    ),
    dark: AlayaColorSet(
      surfaceBase: Color(0xFF0F1118),
      surfaceRaised: Color(0xFF181B25),
      surfaceOverlay: Color(0xFF212530),
      surfaceSunken: Color(0xFF090A0F),
      primary: Color(0xFFE2C79A),
      onPrimary: Color(0xFF1B1607),
      accent: Color(0xFFC98B4B),
      onAccent: Color(0xFF1D1104),
      textPrimary: Color(0xFFF0EDE6),
      textSecondary: Color(0xFFB0ACA1),
      textMuted: Color(0xFF7B776D),
      divider: Color(0xFF2A2E3A),
      income: Color(0xFF79C9A2),
      expense: Color(0xFFE0897E),
      transfer: Color(0xFFA9A79E),
      warning: Color(0xFFDFB264),
      danger: Color(0xFFE0897E),
      success: Color(0xFF79C9A2),
      onStatus: Color(0xFF1B1607),
    ),
  );

  /// Cool teal on pale grey-blue, for high ambient light.
  ///
  /// The deliberate counter-proposal to a warm off-white. A phone used at a market stall in
  /// daylight needs the highest text contrast of any preset here, and a cool background holds
  /// contrast better than a warm one under a bright sky.
  static const AlayaPalette monsoonTeal = AlayaPalette(
    name: 'Monsoon Teal',
    description: 'Cool teal on pale grey-blue. The highest contrast, for bright daylight.',
    light: AlayaColorSet(
      surfaceBase: Color(0xFFEFF3F4),
      surfaceRaised: Color(0xFFFFFFFF),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFE1E8EA),
      primary: Color(0xFF11555F),
      onPrimary: Color(0xFFFFFFFF),
      accent: Color(0xFF0D7A85),
      onAccent: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF0C1F23),
      textSecondary: Color(0xFF3E5A60),
      textMuted: Color(0xFF74898E),
      divider: Color(0xFFCFDADC),
      income: Color(0xFF1F6F4A),
      expense: Color(0xFF8E2622),
      transfer: Color(0xFF3B5B62),
      warning: Color(0xFF8A5B0F),
      danger: Color(0xFF8E2622),
      success: Color(0xFF1F6F4A),
      onStatus: Color(0xFFFFFFFF),
    ),
    dark: AlayaColorSet(
      surfaceBase: Color(0xFF0D1518),
      surfaceRaised: Color(0xFF152125),
      surfaceOverlay: Color(0xFF1D2C31),
      surfaceSunken: Color(0xFF080E10),
      primary: Color(0xFF7FC8D2),
      onPrimary: Color(0xFF062226),
      accent: Color(0xFF4FB3BF),
      onAccent: Color(0xFF042023),
      textPrimary: Color(0xFFE7EFF0),
      textSecondary: Color(0xFF9FB6BA),
      textMuted: Color(0xFF6D8388),
      divider: Color(0xFF25373C),
      income: Color(0xFF6DC79B),
      expense: Color(0xFFE28A83),
      transfer: Color(0xFF93AFB5),
      warning: Color(0xFFD9AE63),
      danger: Color(0xFFE28A83),
      success: Color(0xFF6DC79B),
      onStatus: Color(0xFF062226),
    ),
  );
}
```

### `lib/app/theme/semantic_colors.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';

/// The app's semantic colours, reachable from any `BuildContext` (ARCH_3 §8).
///
/// A `ThemeExtension` rather than a set of top-level constants, because the palette can change at
/// runtime and a widget holding a `const` colour would not rebuild. Reached through
/// [AlayaSemanticColorsContext.semantic] on the context.
@immutable
class AlayaSemanticColors extends ThemeExtension<AlayaSemanticColors> {
  /// Creates the extension.
  const AlayaSemanticColors({
    required this.income,
    required this.expense,
    required this.transfer,
    required this.warning,
    required this.danger,
    required this.success,
    required this.muted,
    required this.onStatus,
    required this.surfaceBase,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.surfaceSunken,
  });

  /// Builds the extension from one mode of a palette.
  factory AlayaSemanticColors.fromColorSet(AlayaColorSet colors) => AlayaSemanticColors(
        income: colors.income,
        expense: colors.expense,
        transfer: colors.transfer,
        warning: colors.warning,
        danger: colors.danger,
        success: colors.success,
        muted: colors.textMuted,
        onStatus: colors.onStatus,
        surfaceBase: colors.surfaceBase,
        surfaceRaised: colors.surfaceRaised,
        surfaceOverlay: colors.surfaceOverlay,
        surfaceSunken: colors.surfaceSunken,
      );

  /// Money arriving.
  final Color income;

  /// Money leaving.
  final Color expense;

  /// Money moving between the user's own accounts.
  final Color transfer;

  /// Something needs attention soon.
  final Color warning;

  /// Something is wrong or overdue.
  final Color danger;

  /// Something completed.
  final Color success;

  /// De-emphasised — and the colour a zero amount takes.
  final Color muted;

  /// Text and icons on a [warning], [danger] or [success] fill.
  final Color onStatus;

  /// Tier 0 — the screen.
  final Color surfaceBase;

  /// Tier 1 — a card.
  final Color surfaceRaised;

  /// Tier 2 — a sheet or dialog.
  final Color surfaceOverlay;

  /// Tier -1 — an inset well, such as a text field's fill.
  final Color surfaceSunken;

  /// **The red/green rule, implemented exactly once (ARCH_3 §8.1).**
  ///
  /// Every amount in the app takes its colour from this method and no other. That is what makes the
  /// convention uniform by construction rather than by 200 widgets each remembering it — and it is
  /// what makes the convention changeable, since inverting it for a user who reads red as auspicious
  /// is one edit here.
  ///
  /// Zero is [muted], not [income]. A zero amount has no direction, and colouring it green would
  /// assert something the number does not say.
  Color forAmount(Money amount) {
    if (amount.isZero) return muted;
    return amount.isNegative ? expense : income;
  }

  /// The colour for an amount belonging to a transaction of [kind].
  ///
  /// Delegates to [forAmount] for everything except a transfer, which is the one case the amount's
  /// sign cannot express: moving ₹5,000 between your own accounts is neither a gain nor a loss, but
  /// its leg is signed like any other. Colouring it green on the way in and red on the way out would
  /// make one movement of money look like income and expense at once.
  Color forTransactionKind(TransactionKind kind, Money amount) =>
      kind == TransactionKind.transfer ? transfer : forAmount(amount);

  /// The surface colour for [tier] 0 to 2, or -1 for a sunken well.
  Color surfaceForTier(int tier) => switch (tier) {
        -1 => surfaceSunken,
        0 => surfaceBase,
        1 => surfaceRaised,
        _ => surfaceOverlay,
      };

  /// Every semantic colour by name, so the Theme Lab enumerates them without a list to maintain.
  Map<String, Color> get byName => {
        'income': income,
        'expense': expense,
        'transfer': transfer,
        'warning': warning,
        'danger': danger,
        'success': success,
        'muted': muted,
        'surfaceBase': surfaceBase,
        'surfaceRaised': surfaceRaised,
        'surfaceOverlay': surfaceOverlay,
        'surfaceSunken': surfaceSunken,
      };

  @override
  AlayaSemanticColors copyWith({
    Color? income,
    Color? expense,
    Color? transfer,
    Color? warning,
    Color? danger,
    Color? success,
    Color? muted,
    Color? onStatus,
    Color? surfaceBase,
    Color? surfaceRaised,
    Color? surfaceOverlay,
    Color? surfaceSunken,
  }) =>
      AlayaSemanticColors(
        income: income ?? this.income,
        expense: expense ?? this.expense,
        transfer: transfer ?? this.transfer,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        success: success ?? this.success,
        muted: muted ?? this.muted,
        onStatus: onStatus ?? this.onStatus,
        surfaceBase: surfaceBase ?? this.surfaceBase,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
        surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      );

  @override
  AlayaSemanticColors lerp(AlayaSemanticColors? other, double t) {
    if (other == null) return this;
    return AlayaSemanticColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      onStatus: Color.lerp(onStatus, other.onStatus, t)!,
      surfaceBase: Color.lerp(surfaceBase, other.surfaceBase, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
    );
  }
}

/// Reaches [AlayaSemanticColors] from a `BuildContext`.
extension AlayaSemanticColorsContext on BuildContext {
  /// This context's semantic colours.
  ///
  /// Throws if the extension is absent, which can only happen inside a `MaterialApp` that is not
  /// `AlayaTheme`'s — a programming error worth failing loudly rather than silently falling back to
  /// Material defaults and shipping a screen whose amounts are the wrong colour.
  AlayaSemanticColors get semantic {
    final extension = Theme.of(this).extension<AlayaSemanticColors>();
    assert(
      extension != null,
      'AlayaSemanticColors is missing. Wrap this subtree in AlayaTheme.light or AlayaTheme.dark.',
    );
    return extension ?? AlayaSemanticColors.fromColorSet(_fallback);
  }
}

const AlayaColorSet _fallback = AlayaColorSet(
  surfaceBase: Color(0xFFF6F5F1),
  surfaceRaised: Color(0xFFFFFFFF),
  surfaceOverlay: Color(0xFFFFFFFF),
  surfaceSunken: Color(0xFFECEAE3),
  primary: Color(0xFF2A3A6B),
  onPrimary: Color(0xFFFFFFFF),
  accent: Color(0xFF9A6A1E),
  onAccent: Color(0xFFFFFFFF),
  textPrimary: Color(0xFF1B2033),
  textSecondary: Color(0xFF515873),
  textMuted: Color(0xFF868CA3),
  divider: Color(0xFFDDDAD1),
  income: Color(0xFF2E7D5B),
  expense: Color(0xFF9E2A2B),
  transfer: Color(0xFF4A5578),
  warning: Color(0xFF9A6A1E),
  danger: Color(0xFF9E2A2B),
  success: Color(0xFF2E7D5B),
  onStatus: Color(0xFFFFFFFF),
);
```

### `lib/app/theme/alaya_theme.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// Turns a palette plus the tokens into light and dark `ThemeData` (ARCH_3 §8).
///
/// Every component theme is configured here rather than left to Material's defaults, because a
/// default is a colour and a radius chosen by someone who had not seen this palette. Leaving them
/// unset is how an app ends up with a purple ripple on an indigo button.
abstract final class AlayaTheme {
  /// The light theme for [palette], defaulting to the active preset.
  static ThemeData light([AlayaPalette palette = AlayaPresets.activePreset]) =>
      _build(palette: palette, isDark: false);

  /// The dark theme for [palette], defaulting to the active preset.
  static ThemeData dark([AlayaPalette palette = AlayaPresets.activePreset]) =>
      _build(palette: palette, isDark: true);

  static ThemeData _build({required AlayaPalette palette, required bool isDark}) {
    final colors = palette.forMode(isDark: isDark);
    final scheme = _scheme(colors, isDark: isDark);
    final text = _textTheme(colors);

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.surfaceBase,
      canvasColor: colors.surfaceBase,
      dividerColor: colors.divider,
      textTheme: text,
      // Splash and highlight derive from the accent rather than Material's default ink, so a tap
      // never flashes a colour that is not in the palette.
      splashColor: colors.accent.withValues(alpha: 0.10),
      highlightColor: colors.accent.withValues(alpha: 0.06),
      extensions: [AlayaSemanticColors.fromColorSet(colors)],
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surfaceBase,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AlayaTypography.screenTitle.copyWith(color: colors.textPrimary),
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderMd),
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AlayaSpacing.sm,
          vertical: AlayaSpacing.sm,
        ),
        border: const OutlineInputBorder(
          borderRadius: AlayaRadii.borderSm,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AlayaRadii.borderSm,
          borderSide: BorderSide(color: colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AlayaRadii.borderSm,
          borderSide: BorderSide(color: colors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AlayaRadii.borderSm,
          borderSide: BorderSide(color: colors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AlayaRadii.borderSm,
          borderSide: BorderSide(color: colors.danger, width: 2),
        ),
        labelStyle: AlayaTypography.label.copyWith(color: colors.textSecondary),
        floatingLabelStyle: AlayaTypography.label.copyWith(color: colors.accent),
        hintStyle: AlayaTypography.body.copyWith(color: colors.textMuted),
        errorStyle: AlayaTypography.caption.copyWith(color: colors.danger),
        prefixIconColor: colors.textSecondary,
        suffixIconColor: colors.textSecondary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: colors.surfaceSunken,
          disabledForegroundColor: colors.textMuted,
          minimumSize: const Size(0, AlayaSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.lg),
          textStyle: AlayaTypography.button,
          shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderSm),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          side: BorderSide(color: colors.divider),
          minimumSize: const Size(0, AlayaSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.lg),
          textStyle: AlayaTypography.button,
          shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderSm),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          minimumSize: const Size(0, AlayaSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.sm),
          textStyle: AlayaTypography.button,
          shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderSm),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderMd),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceSunken,
        selectedColor: colors.primary,
        disabledColor: colors.surfaceSunken,
        labelStyle: AlayaTypography.overline.copyWith(color: colors.textSecondary),
        secondaryLabelStyle: AlayaTypography.overline.copyWith(color: colors.onPrimary),
        side: BorderSide(color: colors.divider),
        padding: const EdgeInsets.symmetric(
          horizontal: AlayaSpacing.xs,
          vertical: AlayaSpacing.xxs,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderXs),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.sheetTop),
        showDragHandle: true,
        dragHandleColor: colors.divider,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderLg),
        titleTextStyle: AlayaTypography.cardTitle.copyWith(color: colors.textPrimary),
        contentTextStyle: AlayaTypography.body.copyWith(color: colors.textSecondary),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(AlayaRadii.lg),
            bottomRight: Radius.circular(AlayaRadii.lg),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.textSecondary,
        textColor: colors.textPrimary,
        titleTextStyle: AlayaTypography.body.copyWith(color: colors.textPrimary),
        subtitleTextStyle: AlayaTypography.caption.copyWith(color: colors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.md),
        minVerticalPadding: AlayaSpacing.xs,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderSm),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceOverlay,
        contentTextStyle: AlayaTypography.body.copyWith(color: colors.textPrimary),
        actionTextColor: colors.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderSm),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.surfaceSunken,
        circularTrackColor: colors.surfaceSunken,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.onAccent : colors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.accent : colors.surfaceSunken,
        ),
        trackOutlineColor: WidgetStateProperty.all(colors.divider),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? colors.accent : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(colors.onAccent),
        side: BorderSide(color: colors.divider, width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderXs),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.textPrimary,
        unselectedLabelColor: colors.textMuted,
        labelStyle: AlayaTypography.bodyEmphasis,
        unselectedLabelStyle: AlayaTypography.body,
        indicatorColor: colors.accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: colors.divider,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.accent.withValues(alpha: 0.14),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.all(
          AlayaTypography.overline.copyWith(color: colors.textSecondary),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? colors.accent : colors.textMuted,
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.surfaceOverlay,
          borderRadius: AlayaRadii.borderXs,
          border: Border.all(color: colors.divider),
        ),
        textStyle: AlayaTypography.caption.copyWith(color: colors.textPrimary),
        waitDuration: AlayaDurations.slow,
      ),
      iconTheme: IconThemeData(color: colors.textSecondary, size: 22),
    );
  }

  static ColorScheme _scheme(AlayaColorSet colors, {required bool isDark}) => ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        secondary: colors.accent,
        onSecondary: colors.onAccent,
        error: colors.danger,
        onError: colors.onStatus,
        surface: colors.surfaceBase,
        onSurface: colors.textPrimary,
        surfaceContainerLowest: colors.surfaceSunken,
        surfaceContainerLow: colors.surfaceBase,
        surfaceContainer: colors.surfaceRaised,
        surfaceContainerHigh: colors.surfaceRaised,
        surfaceContainerHighest: colors.surfaceOverlay,
        onSurfaceVariant: colors.textSecondary,
        outline: colors.divider,
        outlineVariant: colors.divider,
      );

  /// The Material `TextTheme`, mapped from the app's semantic scale.
  ///
  /// Material's slots exist because framework widgets read them; the app's own widgets use
  /// `AlayaTypography` directly. Mapping both ways round would give two names for one style, so the
  /// rule is: framework widgets get this, Alaya widgets get the token.
  static TextTheme _textTheme(AlayaColorSet colors) {
    final primary = colors.textPrimary;
    final secondary = colors.textSecondary;
    return TextTheme(
      displayLarge: AlayaTypography.displayAmount.copyWith(color: primary),
      displayMedium: AlayaTypography.amountLarge.copyWith(color: primary),
      headlineSmall: AlayaTypography.screenTitle.copyWith(color: primary),
      titleLarge: AlayaTypography.screenTitle.copyWith(color: primary),
      titleMedium: AlayaTypography.cardTitle.copyWith(color: primary),
      titleSmall: AlayaTypography.label.copyWith(color: secondary),
      bodyLarge: AlayaTypography.body.copyWith(color: primary),
      bodyMedium: AlayaTypography.body.copyWith(color: primary),
      bodySmall: AlayaTypography.caption.copyWith(color: secondary),
      labelLarge: AlayaTypography.button.copyWith(color: primary),
      labelMedium: AlayaTypography.label.copyWith(color: secondary),
      labelSmall: AlayaTypography.overline.copyWith(color: secondary),
    );
  }
}
```

### `l10n.yaml`

```yaml
arb-dir: lib/app/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AlayaStrings
output-dir: lib/app/l10n/generated
nullable-getter: false
required-resource-attributes: false

```

### `lib/app/l10n/app_en.arb`

```json
{
  "@@locale": "en",
  "appName": "Alaya",
  "@appName": {
    "description": "The app's name, shown in the drawer header."
  },
  "navDashboard": "Dashboard",
  "navExpenses": "Expenses",
  "navInventory": "Inventory",
  "navShopping": "Shopping",
  "navRecurring": "Recurring",
  "navServices": "Services",
  "navCalendar": "Calendar",
  "navInsights": "Insights",
  "navSettings": "Settings",
  "navThemeLab": "Theme Lab",
  "actionSave": "Save",
  "@actionSave": {
    "description": "Commits an edit. Active voice, and the same word appears in the resulting confirmation."
  },
  "actionSaved": "Saved",
  "actionCancel": "Cancel",
  "actionDelete": "Delete",
  "actionDeleted": "Deleted",
  "actionUndo": "Undo",
  "actionRetry": "Try again",
  "actionAdd": "Add",
  "actionEdit": "Edit",
  "actionDone": "Done",
  "actionClose": "Close",
  "actionSelect": "Select",
  "actionClear": "Clear",
  "actionClearAll": "Clear all",
  "actionSearch": "Search",
  "actionConfirm": "Confirm",
  "actionDiscard": "Discard",
  "actionKeepEditing": "Keep editing",
  "actionRemoveTag": "Remove tag",
  "@actionRemoveTag": {
    "description": "Accessibility label for the dismiss affordance on a removable tag chip."
  },
  "actionClearSearch": "Clear search",
  "@actionClearSearch": {
    "description": "Accessibility label for the clear button inside AlayaSearchField."
  },
  "addExpense": "Add expense",
  "addIncome": "Add income",
  "addTransfer": "Add transfer",
  "addItem": "Add item",
  "addToShoppingList": "Add to shopping list",
  "dateToday": "Today",
  "@dateToday": {
    "description": "DateText.relative, when the date is the clock's today. Sentence case; it can begin a row."
  },
  "dateYesterday": "Yesterday",
  "dateTomorrow": "Tomorrow",
  "emptyTitleNoTransactions": "No transactions yet",
  "emptyBodyNoTransactions": "Add your first expense and it will appear here.",
  "@emptyBodyNoTransactions": {
    "description": "An empty screen is an invitation to act, so this names the action rather than describing the emptiness."
  },
  "emptyTitleNoItems": "Nothing in your inventory",
  "emptyBodyNoItems": "Add an item to start tracking what you have at home.",
  "emptyTitleNoShopping": "Your list is empty",
  "emptyBodyNoShopping": "Add something, or let Alaya suggest items you are low on.",
  "emptyTitleNoRecurring": "No recurring bills",
  "emptyBodyNoRecurring": "Set up a bill or subscription and Alaya will remind you when it is due.",
  "emptyTitleNoResults": "No matches",
  "emptyBodyNoResults": "Try a shorter search, or check the spelling.",
  "loadingLabel": "Loading",
  "loadingTransactions": "Loading transactions",
  "errorTitleGeneric": "That did not work",
  "@errorTitleGeneric": {
    "description": "Errors do not apologise and are never vague. This pairs with a specific body message."
  },
  "errorBodyGeneric": "Something went wrong on our side. Try again.",
  "errorTitleNotFound": "Not found",
  "errorBodyNotFound": "This item may have been deleted.",
  "errorBodyNoConnection": "You are offline. Alaya works offline, but rates will not refresh.",
  "errorFieldRequired": "This is required",
  "errorAmountInvalid": "Enter an amount",
  "errorAmountZero": "Enter an amount greater than zero",
  "errorAmountInvalidCharacter": "Digits only",
  "errorAmountNegativeNotAllowed": "Enter a positive amount",
  "errorAmountTooManyDecimals": "Too many decimal places",
  "errorAmountTooLarge": "That amount is too large",
  "errorQuantityTooLarge": "That quantity is too large",
  "errorQuantityInvalid": "Enter a quantity",
  "errorQuantityInvalidCharacter": "Digits only",
  "errorQuantityNegativeNotAllowed": "Enter a positive quantity",
  "errorQuantityTooPrecise": "Too precise for this unit",
  "@errorQuantityTooPrecise": {
    "description": "The typed quantity is finer than the chosen unit can express exactly. Shown rather than rounded, because rounding a quantity silently changes what the user recorded."
  },
  "errorDateInvalid": "Choose a date",
  "confirmDeleteTitle": "Delete this?",
  "confirmDeleteBody": "You can undo this for the next few seconds.",
  "confirmDiscardTitle": "Discard your changes?",
  "confirmDiscardBody": "What you have typed will not be saved.",
  "labelAmount": "Amount",
  "labelQuantity": "Quantity",
  "labelUnit": "Unit",
  "labelDate": "Date",
  "labelAccount": "Account",
  "labelPaymentMethod": "Payment method",
  "labelPayee": "Payee",
  "labelCategory": "Category",
  "labelTags": "Tags",
  "labelNote": "Note",
  "labelFrom": "From",
  "labelTo": "To",
  "labelItem": "Item",
  "labelExpiry": "Expiry",
  "labelTotal": "Total",
  "hintSelectAccount": "Choose an account",
  "hintSelectUnit": "Choose a unit",
  "hintSelectTags": "Choose tags",
  "hintSelectDate": "Choose a date",
  "hintSearchItems": "Search items",
  "hintNote": "Add a note",
  "amountUnconverted": "{count, plural, =1{1 amount not converted} other{{count} amounts not converted}}",
  "@amountUnconverted": {
    "description": "The chip beside a total when some amounts had no exchange rate. Surfaced rather than hidden, because a total missing a row is otherwise indistinguishable from a complete one.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "amountApproximate": "Approximate rate",
  "@amountApproximate": {
    "description": "Shown when a conversion used the nearest earlier rate rather than the exact date's."
  },
  "tagCountMore": "+{count}",
  "@tagCountMore": {
    "description": "Overflow indicator when a row cannot show every tag.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "statusNeedsReview": "Needs details",
  "@statusNeedsReview": {
    "description": "StatusChip on a transaction saved by quick-add. Names what is missing, not that a flag is set."
  },
  "statusUnallocated": "Unallocated",
  "@statusUnallocated": {
    "description": "StatusChip label when a transaction's lines do not sum to its amount. The figure is a separate AmountText (U7); never auto-balanced (anomaly A11)."
  },
  "statusDetached": "Receipt deleted",
  "@statusDetached": {
    "description": "StatusChip on a batch whose source transaction was deleted. The food did not un-exist."
  },
  "statusApproximate": "Approximate",
  "lowStockLabel": "Low",
  "expiringSoonLabel": "Expiring soon",
  "expiredLabel": "Expired",
  "overdueLabel": "Overdue",
  "dueTodayLabel": "Due today",
  "paidLabel": "Paid",
  "skippedLabel": "Skipped",
  "kindDeposit": "Money in",
  "kindWithdrawal": "Money out",
  "kindTransfer": "Transfer",
  "kindAdjustmentIncrease": "Correction up",
  "kindAdjustmentDecrease": "Correction down",
  "subtypeGrocery": "Groceries",
  "subtypeHousehold": "Household",
  "subtypeElectronics": "Electronics",
  "subtypeBill": "Bill",
  "subtypeTransferSelf": "Between my accounts",
  "subtypeTransferOut": "Sent to someone",
  "subtypeSalaryIn": "Salary",
  "subtypeOtherIn": "Other income",
  "subtypeOtherOut": "Other spending",
  "needsReviewBanner": "{count, plural, =1{1 transaction needs details} other{{count} transactions need details}}",
  "@needsReviewBanner": {
    "description": "Surfaces transactions.needsReview. Quick-add saves an amount and nothing else by design; without this row that deliberate shortcut becomes silent data rot.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "needsReviewAction": "Review",
  "filterTitle": "Filter",
  "filterDateRange": "Date range",
  "filterKind": "Type",
  "filterSubtype": "Category",
  "filterApply": "Show results",
  "filterReset": "Reset",
  "filterChipAccount": "Account: {name}",
  "@filterChipAccount": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipPayee": "Payee: {name}",
  "@filterChipPayee": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipRange": "{label}",
  "@filterChipRange": {
    "placeholders": {
      "label": {
        "type": "String"
      }
    }
  },
  "rangeToday": "Today",
  "rangeLast7Days": "Last 7 days",
  "rangeLast30Days": "Last 30 days",
  "rangeThisMonth": "This month",
  "rangeLastMonth": "Last month",
  "rangeThisYear": "This year",
  "rangeAllTime": "All time",
  "rangeCustom": "Custom",
  "searchTransactionsHint": "Search notes",
  "transactionDeleted": "Transaction deleted",
  "quickAddTitle": "Quick add",
  "quickAddMoneyIn": "Money in",
  "quickAddMoneyOut": "Money out",
  "quickAddSave": "Save",
  "actionAddDetails": "Add details",
  "editorTitleNew": "New transaction",
  "editorTitleEdit": "Edit transaction",
  "sectionWhatAndHowMuch": "What and how much",
  "sectionWhereItCameFrom": "Where it came from",
  "sectionWhereItWent": "Where it went",
  "sectionWhatYouBought": "What you bought",
  "sectionWarranty": "Warranty",
  "sectionSchedule": "Schedule",
  "transferOwnAccount": "To my own account",
  "transferSomeoneElse": "To someone else",
  "transferOwnAccountHelp": "Moves money between your accounts. Your total does not change.",
  "transferSomeoneElseHelp": "Money leaves your accounts. This is a withdrawal.",
  "alsoAddToInventory": "Also add to inventory",
  "destinationNone": "Just an expense",
  "destinationInventory": "Save to Inventory",
  "destinationAsset": "Save to Services",
  "destinationRecurring": "Save to Recurring",
  "lineAdd": "Add item",
  "lineDescription": "Item",
  "lineUnitPrice": "Unit price",
  "lineAmount": "Line total",
  "lineCreatedLink": "Created: {name}",
  "@lineCreatedLink": {
    "description": "Surfaces transaction_lines.created*Id — the artefact this line produced, tappable through to it.",
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "payeeCreate": "New payee “{name}”",
  "@payeeCreate": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "saveExpense": "Save expense",
  "saveIncome": "Save income",
  "saveTransfer": "Save transfer",
  "detailSectionLines": "Items",
  "detailSectionDetails": "Details",
  "actionFreezeConversion": "Show in another currency",
  "frozenConversionNote": "Frozen on {date} at {rate}",
  "@frozenConversionNote": {
    "description": "Surfaces transactions.converted*/conversionRateRaw. A separate artefact that is never recomputed (Law L9).",
    "placeholders": {
      "date": {
        "type": "String"
      },
      "rate": {
        "type": "String"
      }
    }
  },
  "deleteReasonHint": "Why? (optional)",
  "actionDeleteTransaction": "Delete transaction",
  "labelSubtype": "Category",
  "labelKind": "Type",
  "themeLabTitle": "Theme Lab",
  "themeLabSubtitle": "Every token, component and semantic colour, light and dark.",
  "themeLabSectionSpacing": "Spacing",
  "themeLabSectionRadii": "Radii",
  "themeLabSectionTypography": "Typography",
  "themeLabSectionElevation": "Elevation",
  "themeLabSectionSemantic": "Semantic colours",
  "themeLabSectionSurfaces": "Surface tiers",
  "themeLabSectionComponents": "Components",
  "themeLabSectionPalettes": "Palettes",
  "themeLabLight": "Light",
  "themeLabDark": "Dark",
  "semanticIncome": "Income",
  "semanticExpense": "Expense",
  "semanticTransfer": "Transfer",
  "semanticWarning": "Warning",
  "semanticDanger": "Danger",
  "semanticSuccess": "Success",
  "semanticMuted": "Muted",
  "drawerSectionMoney": "Money",
  "drawerSectionHome": "Home",
  "drawerSectionMore": "More",
  "inventoryGroupFavourites": "Favourites",
  "@inventoryGroupFavourites": {
    "description": "Phase 6B — inventory."
  },
  "inventoryGroupUntagged": "Everything else",
  "@inventoryGroupUntagged": {
    "description": "Phase 6B — inventory."
  },
  "itemKindGeneric": "General",
  "@itemKindGeneric": {
    "description": "Phase 6B — inventory."
  },
  "itemKindFood": "Food",
  "@itemKindFood": {
    "description": "Phase 6B — inventory."
  },
  "itemKindMedicine": "Medicine",
  "@itemKindMedicine": {
    "description": "Phase 6B — inventory."
  },
  "itemKindBeauty": "Beauty",
  "@itemKindBeauty": {
    "description": "Phase 6B — inventory."
  },
  "itemKindHousehold": "Household",
  "@itemKindHousehold": {
    "description": "Phase 6B — inventory."
  },
  "itemKindOther": "Other",
  "@itemKindOther": {
    "description": "Phase 6B — inventory."
  },
  "filterFavouritesOnly": "Favourites only",
  "@filterFavouritesOnly": {
    "description": "Phase 6B — inventory."
  },
  "actionFavourite": "Add to favourites",
  "@actionFavourite": {
    "description": "Phase 6B — inventory."
  },
  "actionUnfavourite": "Remove from favourites",
  "@actionUnfavourite": {
    "description": "Phase 6B — inventory."
  },
  "outOfStockLabel": "Out of stock",
  "@outOfStockLabel": {
    "description": "Phase 6B — inventory."
  },
  "itemBatchCount": "{count, plural, =1{1 batch} other{{count} batches}}",
  "@itemBatchCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "loadingInventory": "Loading inventory",
  "@loadingInventory": {
    "description": "Phase 6B — inventory."
  },
  "detailSectionBatches": "Batches",
  "@detailSectionBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginPurchase": "From a purchase",
  "@batchOriginPurchase": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginManual": "Added by hand",
  "@batchOriginManual": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginImported": "Imported",
  "@batchOriginImported": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginAdjustment": "From an adjustment",
  "@batchOriginAdjustment": {
    "description": "Phase 6B — inventory."
  },
  "labelPurchased": "Purchased",
  "@labelPurchased": {
    "description": "Phase 6B — inventory."
  },
  "labelStorageLocation": "Stored in",
  "@labelStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "labelUnitCost": "Unit cost",
  "@labelUnitCost": {
    "description": "Phase 6B — inventory."
  },
  "labelInitial": "Bought",
  "@labelInitial": {
    "description": "Phase 6B — inventory."
  },
  "labelNearestExpiry": "Nearest expiry",
  "@labelNearestExpiry": {
    "description": "Phase 6B — inventory."
  },
  "labelDisplayUnit": "Shown in",
  "@labelDisplayUnit": {
    "description": "Phase 6B — inventory."
  },
  "labelItemKind": "Kind",
  "@labelItemKind": {
    "description": "Phase 6B — inventory."
  },
  "labelLowStockThreshold": "Low-stock level",
  "@labelLowStockThreshold": {
    "description": "Phase 6B — inventory."
  },
  "labelExpiryNotifyDays": "Warn before expiry",
  "@labelExpiryNotifyDays": {
    "description": "Phase 6B — inventory."
  },
  "actionConsume": "Use some",
  "@actionConsume": {
    "description": "Phase 6B — inventory."
  },
  "actionAddBatch": "Add a batch",
  "@actionAddBatch": {
    "description": "Phase 6B — inventory."
  },
  "actionViewHistory": "Movement history",
  "@actionViewHistory": {
    "description": "Phase 6B — inventory."
  },
  "actionDeleteItem": "Delete item",
  "@actionDeleteItem": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemTitle": "Delete this item?",
  "@confirmDeleteItemTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemBody": "Its {count, plural, =1{1 batch} other{{count} batches}} go with it. The movement history stays, so what you already used is still recorded.",
  "@confirmDeleteItemBody": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "itemDeleted": "Item deleted",
  "@itemDeleted": {
    "description": "Phase 6B — inventory."
  },
  "expiresInDays": "{days, plural, =0{Expires today} =1{Expires tomorrow} other{Expires in {days} days}}",
  "@expiresInDays": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "expiredDaysAgo": "{days, plural, =1{Expired yesterday} other{Expired {days} days ago}}",
  "@expiredDaysAgo": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "sectionWhatItIs": "What it is",
  "@sectionWhatItIs": {
    "description": "Phase 6B — inventory."
  },
  "sectionStockRules": "Stock rules",
  "@sectionStockRules": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryWeight": "Weight",
  "@unitCategoryWeight": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryVolume": "Volume",
  "@unitCategoryVolume": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryCount": "Count",
  "@unitCategoryCount": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryLocked": "Measured in {category}",
  "@unitCategoryLocked": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "category": {}
    }
  },
  "unitCategoryLockedHelp": "This cannot change. Every batch and movement already recorded is stored in this measure, and there is no conversion between weight, volume and count.",
  "@unitCategoryLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "expiryNotifyDaysHelp": "Days of warning before a batch expires.",
  "@expiryNotifyDaysHelp": {
    "description": "Phase 6B — inventory."
  },
  "labelFavourite": "Favourite",
  "@labelFavourite": {
    "description": "Phase 6B — inventory."
  },
  "saveItem": "Save item",
  "@saveItem": {
    "description": "Phase 6B — inventory."
  },
  "sectionHowMuch": "How much",
  "@sectionHowMuch": {
    "description": "Phase 6B — inventory."
  },
  "sectionBatchDetails": "Batch details",
  "@sectionBatchDetails": {
    "description": "Phase 6B — inventory."
  },
  "saveBatch": "Save batch",
  "@saveBatch": {
    "description": "Phase 6B — inventory."
  },
  "batchSaved": "Batch saved",
  "@batchSaved": {
    "description": "Phase 6B — inventory."
  },
  "hintStorageLocation": "Freezer, pantry, bathroom shelf…",
  "@hintStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "consumeTitle": "Use stock",
  "@consumeTitle": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindConsume": "Used",
  "@consumeKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindWaste": "Thrown away",
  "@consumeKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindExpired": "Expired",
  "@consumeKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "consumeRecorded": "Recorded",
  "@consumeRecorded": {
    "description": "Phase 6B — inventory."
  },
  "consumeFromLabel": "Taking from",
  "@consumeFromLabel": {
    "description": "Phase 6B — inventory."
  },
  "consumeFefoNote": "Oldest expiry first.",
  "@consumeFefoNote": {
    "description": "Phase 6B — inventory."
  },
  "consumeSpansBatches": "{count, plural, =1{Takes all of 1 batch} other{Spans {count} batches, writing {count} movements}}",
  "@consumeSpansBatches": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "consumeOverAvailable": "More than you have on hand",
  "@consumeOverAvailable": {
    "description": "Phase 6B — inventory."
  },
  "historyTitle": "Movement history",
  "@historyTitle": {
    "description": "Phase 6B — inventory."
  },
  "movementKindOpeningIn": "Opening stock",
  "@movementKindOpeningIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindPurchaseIn": "Bought",
  "@movementKindPurchaseIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindManualIn": "Added by hand",
  "@movementKindManualIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindConsume": "Used",
  "@movementKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "movementKindWaste": "Thrown away",
  "@movementKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "movementKindExpired": "Expired",
  "@movementKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustIn": "Adjusted up",
  "@movementKindAdjustIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustOut": "Adjusted down",
  "@movementKindAdjustOut": {
    "description": "Phase 6B — inventory."
  },
  "movementReversed": "Reversed",
  "@movementReversed": {
    "description": "Phase 6B — inventory."
  },
  "movementIsReversal": "Reverses an earlier movement",
  "@movementIsReversal": {
    "description": "Phase 6B — inventory."
  },
  "actionReverse": "Reverse",
  "@actionReverse": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseTitle": "Reverse this movement?",
  "@confirmReverseTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseBody": "An opposite movement is appended. Nothing is erased — both entries stay in the history.",
  "@confirmReverseBody": {
    "description": "Phase 6B — inventory."
  },
  "movementReversedSnack": "Movement reversed",
  "@movementReversedSnack": {
    "description": "Phase 6B — inventory."
  },
  "emptyTitleNoMovements": "Nothing recorded yet",
  "@emptyTitleNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoMovements": "Using, wasting or adjusting this batch will show up here.",
  "@emptyBodyNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoBatches": "Add a batch and it will appear here with its expiry.",
  "@emptyBodyNoBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchQuantityLockedHelp": "How much is left is worked out from the movement history. Use, waste or adjust the batch to change it.",
  "@batchQuantityLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "daysCount": "{days, plural, =1{1 day} other{{days} days}}",
  "@daysCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "groupByFavourites": "Group favourites first",
  "@groupByFavourites": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitUsed": "Record as used",
  "@consumeCommitUsed": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitWaste": "Record as thrown away",
  "@consumeCommitWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitExpired": "Record as expired",
  "@consumeCommitExpired": {
    "description": "Phase 6B — inventory."
  },
  "lowStockWithCount": "Low · {count}",
  "@lowStockWithCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "actionDeleteBatch": "Delete batch",
  "@actionDeleteBatch": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchTitle": "Delete this batch?",
  "@confirmDeleteBatchTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchBody": "The stock it still holds disappears from your on-hand total. What you already used stays in the movement history.",
  "@confirmDeleteBatchBody": {
    "description": "Phase 6B — inventory."
  },
  "batchDeleted": "Batch deleted",
  "@batchDeleted": {
    "description": "Phase 6B — inventory."
  },
  "itemCreate": "New item",
  "@itemCreate": {
    "description": "Creates a catalogued item inline while itemising a receipt."
  },
  "itemCreateHint": "No items yet — create one so this line becomes stock.",
  "@itemCreateHint": {
    "description": "Shown in the line editor when the item catalogue is empty."
  },
  "itemCreateCategoryPrompt": "How is it measured? This cannot change later.",
  "@itemCreateCategoryPrompt": {
    "description": "Prompt for unitCategory on inline creation; immutable after create (Law L8)."
  },
  "itemDuplicateBody": "You already have this item, measured the same way. Open the one you have instead of adding a second.",
  "@itemDuplicateBody": {
    "description": "Shown when an item with the same normalized name and unit category exists."
  },
  "itemUnitsMissingBody": "No units are set up for this measure yet. Pick a different measure, or add units in Settings first.",
  "@itemUnitsMissingBody": {
    "description": "Shown when the chosen UnitCategory has no rows in units."
  },
  "itemSimilarNote": "You also have this name under a different measure. That is fine — weight, volume and count never convert into each other.",
  "@itemSimilarNote": {
    "description": "Informational note, never a block: Law L8 makes same-name/different-category distinct items."
  },
  "actionOpenExisting": "Open the one I have",
  "@actionOpenExisting": {
    "description": "Opens the existing item a duplicate collides with."
  },
  "shoppingEstimate": "Estimated",
  "@shoppingEstimate": {
    "description": "Running total of estimated prices on a shopping list."
  },
  "shoppingSwitchList": "Switch list",
  "@shoppingSwitchList": {
    "description": "Opens the list manager from the app bar."
  },
  "shoppingCheckedCount": "{checked} of {total} ticked",
  "@shoppingCheckedCount": {
    "description": "Progress line above a shopping list.",
    "placeholders": {
      "checked": {},
      "total": {}
    }
  },
  "emptyTitleNoEntries": "Nothing on this list yet",
  "@emptyTitleNoEntries": {
    "description": "Shopping list empty state."
  },
  "emptyBodyNoEntries": "Add what you need, or pull in suggestions from what is running low.",
  "@emptyBodyNoEntries": {
    "description": "Shopping list empty state body."
  },
  "addEntry": "Add",
  "@addEntry": {
    "description": "Adds one entry to a shopping list."
  },
  "shoppingGroupUntagged": "Everything else",
  "@shoppingGroupUntagged": {
    "description": "Header for entries with no tag."
  },
  "actionUncheckAll": "Untick everything",
  "@actionUncheckAll": {
    "description": "Clears every tick on a shopping list."
  },
  "entryEditorTitle": "What do you need?",
  "@entryEditorTitle": {
    "description": "Entry editor sheet title."
  },
  "entryFreeTextLabel": "Name it",
  "@entryFreeTextLabel": {
    "description": "Free-text label for a shopping entry."
  },
  "entryFreeTextHint": "Television, birthday card, light bulbs…",
  "@entryFreeTextHint": {
    "description": "Hint showing that an entry need not be an inventory item."
  },
  "entryLinkItem": "Link to an item",
  "@entryLinkItem": {
    "description": "Optional link from a shopping entry to a catalogued item."
  },
  "entryNoItem": "Not in my inventory",
  "@entryNoItem": {
    "description": "Dropdown option leaving itemId null."
  },
  "labelEstimatedPrice": "Estimated price",
  "@labelEstimatedPrice": {
    "description": "Optional per-entry price estimate."
  },
  "entryNeedsSomething": "Give it a name, or link it to an item",
  "@entryNeedsSomething": {
    "description": "Rejection when neither freeText nor itemId is set."
  },
  "originAutoLowStock": "Suggested",
  "@originAutoLowStock": {
    "description": "Chip marking an auto-generated low-stock entry."
  },
  "originPromoted": "Yours now",
  "@originPromoted": {
    "description": "Chip shown once an auto entry has been edited into a manual one."
  },
  "actionSnooze": "Snooze a week",
  "@actionSnooze": {
    "description": "Hides an auto suggestion until a later date."
  },
  "actionDismiss": "Not now",
  "@actionDismiss": {
    "description": "Dismisses an auto suggestion until stock recovers and drops again."
  },
  "snoozedUntilLabel": "Snoozed until",
  "@snoozedUntilLabel": {
    "description": "Precedes a DateText on a snoozed entry."
  },
  "generateTitle": "Running low",
  "@generateTitle": {
    "description": "Low-stock suggestion sheet title."
  },
  "generateBody": "These are below the level you set. Add the ones you want.",
  "@generateBody": {
    "description": "Low-stock suggestion sheet body."
  },
  "generateShortBy": "Short by",
  "@generateShortBy": {
    "description": "Precedes a QtyText giving threshold minus stock on hand."
  },
  "generateRefresh": "Check again",
  "@generateRefresh": {
    "description": "Re-runs low-stock generation."
  },
  "generateEmptyTitle": "Nothing is running low",
  "@generateEmptyTitle": {
    "description": "Generate sheet empty state."
  },
  "generateEmptyBody": "Set a low-stock level on an item and it will show up here when it drops.",
  "@generateEmptyBody": {
    "description": "Generate sheet empty state body."
  },
  "generateAdded": "{count, plural, =1{1 suggestion added} other{{count} suggestions added}}",
  "@generateAdded": {
    "description": "Result snack after regeneration.",
    "placeholders": {
      "count": {}
    }
  },
  "convertTitle": "Turn into a purchase",
  "@convertTitle": {
    "description": "Convert-to-purchase screen title."
  },
  "convertBody": "Each ticked entry becomes one line, marked for inventory. You confirm the amount and account next.",
  "@convertBody": {
    "description": "Explains the handoff to the expense editor."
  },
  "convertConfirm": "Open the expense",
  "@convertConfirm": {
    "description": "Primary action; hands off to the 6A editor."
  },
  "convertNothingTitle": "Nothing is ticked",
  "@convertNothingTitle": {
    "description": "Convert screen empty state."
  },
  "convertNothingBody": "Tick what you actually bought, then come back.",
  "@convertNothingBody": {
    "description": "Convert screen empty state body."
  },
  "convertLineCount": "{count, plural, =1{1 line} other{{count} lines}}",
  "@convertLineCount": {
    "description": "How many lines the draft will carry.",
    "placeholders": {
      "count": {}
    }
  },
  "listManagerTitle": "Your lists",
  "@listManagerTitle": {
    "description": "List manager sheet title."
  },
  "listNameLabel": "List name",
  "@listNameLabel": {
    "description": "Field label when creating or renaming a list."
  },
  "listCreate": "New list",
  "@listCreate": {
    "description": "Creates a shopping list."
  },
  "listRename": "Rename",
  "@listRename": {
    "description": "Renames a shopping list."
  },
  "listSetDefault": "Make default",
  "@listSetDefault": {
    "description": "Marks a list as the one that opens by default."
  },
  "listDefaultBadge": "Default",
  "@listDefaultBadge": {
    "description": "Chip on the default list."
  },
  "listArchive": "Archive",
  "@listArchive": {
    "description": "Archives a shopping list."
  },
  "listUnarchive": "Restore",
  "@listUnarchive": {
    "description": "Un-archives a shopping list."
  },
  "listArchivedBadge": "Archived",
  "@listArchivedBadge": {
    "description": "Chip on an archived list."
  },
  "listArchivedSection": "Archived",
  "@listArchivedSection": {
    "description": "Section header for archived lists."
  },
  "emptyTitleNoLists": "No lists yet",
  "@emptyTitleNoLists": {
    "description": "List manager empty state."
  },
  "emptyBodyNoLists": "Create one and it becomes your default.",
  "@emptyBodyNoLists": {
    "description": "List manager empty state body."
  },
  "loadingShopping": "Loading your list",
  "@loadingShopping": {
    "description": "Skeleton label for shopping surfaces."
  },
  "actionAddToList": "Add to my list",
  "@actionAddToList": {
    "description": "Accepts a low-stock suggestion, promoting it to origin=manual so regeneration leaves it alone."
  },
  "suggestionDismissed": "Turned down",
  "@suggestionDismissed": {
    "description": "Chip on a dismissed suggestion; it stays listed so it can be accepted later."
  },
  "lineItemsTitle": "What you bought",
  "@lineItemsTitle": {
    "description": "Title of the dedicated line-items page."
  },
  "lineItemsManage": "Add or edit items",
  "@lineItemsManage": {
    "description": "Opens the line-items page from the transaction editor."
  },
  "lineItemsAdd": "Add an item",
  "@lineItemsAdd": {
    "description": "Adds one line from the line-items page."
  },
  "lineItemsSaveAndAnother": "Save & add another",
  "@lineItemsSaveAndAnother": {
    "description": "Commits the line and reopens the editor blank, so a receipt is entered without leaving the sheet."
  },
  "lineItemsCount": "{count, plural, =0{No items yet} =1{1 item} other{{count} items}}",
  "@lineItemsCount": {
    "description": "Running count on the line-items page.",
    "placeholders": {
      "count": {}
    }
  },
  "emptyTitleNoLineItems": "Nothing itemised yet",
  "@emptyTitleNoLineItems": {
    "description": "Line-items page empty state."
  },
  "emptyBodyNoLineItems": "Add what was on the receipt. Anything you leave out still counts toward the total.",
  "@emptyBodyNoLineItems": {
    "description": "Line-items page empty state body."
  },
  "actionRemove": "Remove",
  "@actionRemove": {
    "description": "Removes one line from a transaction."
  },
  "lineRemoved": "Item removed",
  "@lineRemoved": {
    "description": "Snack after removing a line."
  },
  "lineItemsAllocated": "Itemised",
  "@lineItemsAllocated": {
    "description": "Precedes the summed line total on the line-items page."
  },
  "recurringOutflow": "Going out",
  "@recurringOutflow": {
    "description": "Group header for outflow templates."
  },
  "recurringInflow": "Coming in",
  "@recurringInflow": {
    "description": "Group header for inflow templates — salary reads as income, not a negative bill."
  },
  "recurringNextDue": "Next",
  "@recurringNextDue": {
    "description": "Precedes a DateText giving the next due date."
  },
  "recurringOverdue": "Overdue",
  "@recurringOverdue": {
    "description": "Chip on an occurrence past its due date. Derived from the clock, never stored."
  },
  "recurringPaused": "Paused",
  "@recurringPaused": {
    "description": "Chip on a paused template."
  },
  "recurringDueToday": "Due today",
  "@recurringDueToday": {
    "description": "Chip when the next occurrence falls today."
  },
  "emptyTitleNoTemplates": "Nothing recurring yet",
  "@emptyTitleNoTemplates": {
    "description": "Template list empty state."
  },
  "emptyBodyNoTemplates": "Add a bill, a subscription or a salary and it will appear here when it is next due.",
  "@emptyBodyNoTemplates": {
    "description": "Template list empty state body."
  },
  "addTemplate": "Add",
  "@addTemplate": {
    "description": "Adds a recurring template."
  },
  "actionPause": "Pause",
  "@actionPause": {
    "description": "Pauses a template."
  },
  "actionResume": "Resume",
  "@actionResume": {
    "description": "Resumes a paused template."
  },
  "loadingRecurring": "Loading your schedule",
  "@loadingRecurring": {
    "description": "Skeleton label for recurring surfaces."
  },
  "builderSectionWhat": "What it is",
  "@builderSectionWhat": {
    "description": "First section of the template builder."
  },
  "builderSectionWhen": "How often",
  "@builderSectionWhen": {
    "description": "Frequency section of the template builder."
  },
  "builderSectionDefaults": "Defaults",
  "@builderSectionDefaults": {
    "description": "Amount and account section of the template builder."
  },
  "labelTemplateName": "Name",
  "@labelTemplateName": {
    "description": "Template name field."
  },
  "labelRecurringKind": "Kind",
  "@labelRecurringKind": {
    "description": "Bill, subscription, rent or salary."
  },
  "labelDirection": "Direction",
  "@labelDirection": {
    "description": "Whether money goes out or comes in."
  },
  "directionOutflow": "Money out",
  "@directionOutflow": {
    "description": "RecurringDirection.outflow."
  },
  "directionInflow": "Money in",
  "@directionInflow": {
    "description": "RecurringDirection.inflow."
  },
  "kindBill": "Bill",
  "@kindBill": {
    "description": "RecurringKind.bill."
  },
  "kindSubscription": "Subscription",
  "@kindSubscription": {
    "description": "RecurringKind.subscription."
  },
  "kindRent": "Rent",
  "@kindRent": {
    "description": "RecurringKind.rent."
  },
  "kindSalary": "Salary",
  "@kindSalary": {
    "description": "RecurringKind.salary."
  },
  "labelEvery": "Every",
  "@labelEvery": {
    "description": "Precedes the interval count and unit."
  },
  "unitDay": "{count, plural, =1{day} other{days}}",
  "@unitDay": {
    "description": "RecurringIntervalUnit.day.",
    "placeholders": {
      "count": {}
    }
  },
  "unitWeek": "{count, plural, =1{week} other{weeks}}",
  "@unitWeek": {
    "description": "RecurringIntervalUnit.week.",
    "placeholders": {
      "count": {}
    }
  },
  "unitMonth": "{count, plural, =1{month} other{months}}",
  "@unitMonth": {
    "description": "RecurringIntervalUnit.month.",
    "placeholders": {
      "count": {}
    }
  },
  "unitYear": "{count, plural, =1{year} other{years}}",
  "@unitYear": {
    "description": "RecurringIntervalUnit.year.",
    "placeholders": {
      "count": {}
    }
  },
  "labelAnchorDay": "On day of the month",
  "@labelAnchorDay": {
    "description": "anchorDayOfMonth. Stored once, clamped at render (anomaly A13)."
  },
  "anchorDayHelp": "Kept as you set it. Anchored on the 31st, a short month falls on its last day and the next long month returns to the 31st.",
  "@anchorDayHelp": {
    "description": "Explains that the anchor never walks backwards."
  },
  "labelStartDate": "Starts",
  "@labelStartDate": {
    "description": "startDateKey."
  },
  "labelEndDate": "Ends",
  "@labelEndDate": {
    "description": "endDateKey, optional."
  },
  "labelDefaultAmount": "Usual amount",
  "@labelDefaultAmount": {
    "description": "defaultAmount — a default, not a fixed figure."
  },
  "labelRemindBefore": "Remind me",
  "@labelRemindBefore": {
    "description": "remindDaysBefore."
  },
  "saveTemplate": "Save",
  "@saveTemplate": {
    "description": "Commits the template."
  },
  "previewTitle": "Next three",
  "@previewTitle": {
    "description": "Header of the frequency preview."
  },
  "previewEmpty": "Set a start date to see when this lands.",
  "@previewEmpty": {
    "description": "Frequency preview with nothing to show."
  },
  "previewClamped": "Shortened to fit the month",
  "@previewClamped": {
    "description": "Marks a previewed date the anchor could not reach."
  },
  "payTitle": "Record this payment",
  "@payTitle": {
    "description": "Pay sheet title."
  },
  "payTitleInflow": "Record this receipt",
  "@payTitleInflow": {
    "description": "Pay sheet title for an inflow."
  },
  "labelActualAmount": "Amount actually paid",
  "@labelActualAmount": {
    "description": "The real figure, which may differ from the default."
  },
  "labelActualAmountInflow": "Amount actually received",
  "@labelActualAmountInflow": {
    "description": "Inflow wording for the same field."
  },
  "payUsualWas": "Usually",
  "@payUsualWas": {
    "description": "Precedes the default amount when the actual differs from it."
  },
  "labelPaidOn": "Paid on",
  "@labelPaidOn": {
    "description": "paidDateKey."
  },
  "payCommit": "Record it",
  "@payCommit": {
    "description": "Commits the payment and creates the transaction."
  },
  "payRecorded": "Recorded",
  "@payRecorded": {
    "description": "Result snack after paying."
  },
  "payNeedsAccount": "Choose which account it came from",
  "@payNeedsAccount": {
    "description": "Rejection when no account is selected."
  },
  "payUndoTitle": "Undo this payment?",
  "@payUndoTitle": {
    "description": "Confirmation before undoing."
  },
  "payUndoBody": "The obligation goes back to due and the transaction it created is deleted. Anything that transaction produced — stock, an asset — goes with it.",
  "@payUndoBody": {
    "description": "Says exactly what undo reverses, in the order it happens (ARCH_5 §5.4)."
  },
  "payUndone": "Payment undone",
  "@payUndone": {
    "description": "Result snack after undoing."
  },
  "actionSkip": "Skip this one",
  "@actionSkip": {
    "description": "Marks an occurrence deliberately skipped."
  },
  "occurrenceSkipped": "Skipped",
  "@occurrenceSkipped": {
    "description": "Chip on a skipped occurrence, and the snack after skipping."
  },
  "historyRecurringTitle": "Payment history",
  "@historyRecurringTitle": {
    "description": "Occurrence history screen title."
  },
  "historyDefaultVsActual": "Differed from the usual amount",
  "@historyDefaultVsActual": {
    "description": "Badge when paidAmount != defaultAmount."
  },
  "emptyTitleNoOccurrences": "Nothing due yet",
  "@emptyTitleNoOccurrences": {
    "description": "Occurrence history empty state."
  },
  "emptyBodyNoOccurrences": "Occurrences appear as their due dates arrive. Nothing is ever paid for you.",
  "@emptyBodyNoOccurrences": {
    "description": "Empty state body, stating anomaly A14 plainly."
  },
  "statusDue": "Due",
  "@statusDue": {
    "description": "RecurringOccurrenceStatus.due."
  },
  "statusPaid": "Paid",
  "@statusPaid": {
    "description": "RecurringOccurrenceStatus.paid."
  },
  "statusDismissed": "Dismissed",
  "@statusDismissed": {
    "description": "RecurringOccurrenceStatus.dismissed."
  },
  "kindServiceFee": "Service fee",
  "@kindServiceFee": {
    "description": "RecurringKind.serviceFee — a recurring charge tied to an asset."
  },
  "kindOther": "Something else",
  "@kindOther": {
    "description": "RecurringKind.other — anything the named kinds do not cover."
  },
  "billDueSection": "Due now",
  "@billDueSection": {
    "description": "Header above the recurring bills a payment can settle."
  },
  "billSetUpAction": "Set up a recurring bill",
  "@billSetUpAction": {
    "description": "Opens the template builder from the bill form."
  },
  "billNothingDue": "Nothing is due right now.",
  "@billNothingDue": {
    "description": "Shown in the bill form when no occurrence is outstanding."
  },
  "recurringScheduleNext": "Saved. Now set how often it repeats.",
  "@recurringScheduleNext": {
    "description": "Snack after a line asked to become recurring."
  },
  "recurringNotYetDue": "Not due yet",
  "@recurringNotYetDue": {
    "description": "Chip when the next occurrence has not materialised."
  },
  "billSettlesLabel": "Settling",
  "@billSettlesLabel": {
    "description": "Precedes the recurring bill this payment will settle."
  },
  "billSettleNone": "Not a recurring bill",
  "@billSettleNone": {
    "description": "Option that leaves the payment unlinked to any template."
  },
  "billSettleHelp": "Pick one and the amount below becomes what you actually paid. Saving records it once.",
  "@billSettleHelp": {
    "description": "Explains that the editor is the single write path for a bill payment."
  },
  "billAmountBecomesPaid": "This amount is what gets recorded",
  "@billAmountBecomesPaid": {
    "description": "Helper under the amount when a bill is selected."
  },
  "billAccountAuto": "Paid from",
  "@billAccountAuto": {
    "description": "Precedes the account resolved automatically for a bill payment."
  },
  "billAccountAskOnce": "Which account does this come from? Alaya remembers it on the bill.",
  "@billAccountAskOnce": {
    "description": "Shown only when no template default, no app default and more than one account exist."
  },
  "assetGroupAppliance": "Appliances",
  "@assetGroupAppliance": {
    "description": "AssetType.appliance group header."
  },
  "assetGroupElectronics": "Electronics",
  "@assetGroupElectronics": {
    "description": "AssetType.electronics."
  },
  "assetGroupVehicle": "Vehicles",
  "@assetGroupVehicle": {
    "description": "AssetType.vehicle."
  },
  "assetGroupFurniture": "Furniture",
  "@assetGroupFurniture": {
    "description": "AssetType.furniture."
  },
  "assetGroupProperty": "Property",
  "@assetGroupProperty": {
    "description": "AssetType.property."
  },
  "assetGroupServiceProvider": "People",
  "@assetGroupServiceProvider": {
    "description": "AssetType.serviceProvider — a maid or gardener lives here, not in a second system."
  },
  "assetGroupSubscription": "Subscriptions",
  "@assetGroupSubscription": {
    "description": "AssetType.subscription."
  },
  "assetGroupOther": "Other",
  "@assetGroupOther": {
    "description": "AssetType.other."
  },
  "assetUnderWarranty": "In warranty",
  "@assetUnderWarranty": {
    "description": "Chip when warrantyEndDateKey is still ahead."
  },
  "assetWarrantyEnding": "Warranty ending",
  "@assetWarrantyEnding": {
    "description": "Chip when the warranty ends soon."
  },
  "assetWarrantyExpired": "Out of warranty",
  "@assetWarrantyExpired": {
    "description": "Chip when the warranty has passed."
  },
  "assetServiceDue": "Service due",
  "@assetServiceDue": {
    "description": "Chip when nextServiceDueDateKey has passed."
  },
  "assetServiceSoon": "Service soon",
  "@assetServiceSoon": {
    "description": "Chip when a service is close."
  },
  "assetDisposedChip": "Disposed",
  "@assetDisposedChip": {
    "description": "Chip on a disposed asset."
  },
  "assetUnderRepair": "Being repaired",
  "@assetUnderRepair": {
    "description": "AssetStatus.underRepair."
  },
  "filterShowDisposed": "Include disposed",
  "@filterShowDisposed": {
    "description": "Filter that brings disposed assets back into the list."
  },
  "emptyTitleNoAssets": "Nothing tracked yet",
  "@emptyTitleNoAssets": {
    "description": "Asset list empty state."
  },
  "emptyBodyNoAssets": "Add an appliance, a vehicle, or the person who helps around the house — they all live here.",
  "@emptyBodyNoAssets": {
    "description": "Asset list empty state body, stating the serviceProvider case plainly."
  },
  "addAsset": "Add",
  "@addAsset": {
    "description": "Adds an asset."
  },
  "loadingAssets": "Loading your things",
  "@loadingAssets": {
    "description": "Skeleton label for service surfaces."
  },
  "assetSectionIdentity": "Details",
  "@assetSectionIdentity": {
    "description": "Identity section on the detail screen."
  },
  "assetSectionWarranty": "Warranty",
  "@assetSectionWarranty": {
    "description": "Warranty section."
  },
  "assetSectionContact": "Contact",
  "@assetSectionContact": {
    "description": "Contact block."
  },
  "assetSectionService": "Service history",
  "@assetSectionService": {
    "description": "Service records section."
  },
  "assetSectionSalary": "Salary history",
  "@assetSectionSalary": {
    "description": "Service records section for a serviceProvider."
  },
  "assetLifetimeCost": "Spent on service so far",
  "@assetLifetimeCost": {
    "description": "Sum of every service record cost."
  },
  "assetLifetimeSalary": "Paid so far",
  "@assetLifetimeSalary": {
    "description": "The same figure for a serviceProvider."
  },
  "labelBrand": "Brand",
  "@labelBrand": {
    "description": "assets.brand."
  },
  "labelModelNo": "Model",
  "@labelModelNo": {
    "description": "assets.modelNo."
  },
  "labelSerialNo": "Serial",
  "@labelSerialNo": {
    "description": "assets.serialNo."
  },
  "labelPurchasePrice": "Bought for",
  "@labelPurchasePrice": {
    "description": "assets.purchasePrice."
  },
  "labelWarrantyStart": "Warranty from",
  "@labelWarrantyStart": {
    "description": "assets.warrantyStartDateKey."
  },
  "labelWarrantyEnd": "Warranty until",
  "@labelWarrantyEnd": {
    "description": "assets.warrantyEndDateKey."
  },
  "labelWarrantyProvider": "Covered by",
  "@labelWarrantyProvider": {
    "description": "assets.warrantyProvider."
  },
  "labelServiceInterval": "Service every",
  "@labelServiceInterval": {
    "description": "assets.serviceIntervalDays."
  },
  "labelNextService": "Next service",
  "@labelNextService": {
    "description": "assets.nextServiceDueDateKey."
  },
  "labelContactName": "Name",
  "@labelContactName": {
    "description": "assets.primaryContactName."
  },
  "labelContactPhone": "Phone",
  "@labelContactPhone": {
    "description": "assets.primaryContactPhone."
  },
  "labelLocation": "Kept in",
  "@labelLocation": {
    "description": "assets.location."
  },
  "actionCall": "Call",
  "@actionCall": {
    "description": "Dials primaryContactPhone."
  },
  "callFailed": "No app on this phone can place that call.",
  "@callFailed": {
    "description": "Shown when the tel: intent finds no handler."
  },
  "actionAddService": "Record a service",
  "@actionAddService": {
    "description": "Adds a service record."
  },
  "actionAddSalary": "Record a payment",
  "@actionAddSalary": {
    "description": "The same action for a serviceProvider."
  },
  "actionDispose": "Dispose of it",
  "@actionDispose": {
    "description": "Opens the dispose sheet."
  },
  "actionUndispose": "Bring it back",
  "@actionUndispose": {
    "description": "Reverses a disposal."
  },
  "assetLinkedRecurring": "Paid on a schedule",
  "@assetLinkedRecurring": {
    "description": "Chip when linkedRecurringTemplateId is set."
  },
  "emptyBodyNoServices": "Nothing recorded against this yet.",
  "@emptyBodyNoServices": {
    "description": "Empty service history."
  },
  "labelAssetName": "What is it?",
  "@labelAssetName": {
    "description": "assets.name."
  },
  "labelAssetType": "Kind",
  "@labelAssetType": {
    "description": "assets.type."
  },
  "assetTypeHelpPerson": "A person you pay regularly belongs here too — their payments become service records.",
  "@assetTypeHelpPerson": {
    "description": "Explains AssetType.serviceProvider when it is chosen."
  },
  "saveAsset": "Save",
  "@saveAsset": {
    "description": "Commits an asset."
  },
  "serviceIntervalHelp": "Days between services. The next due date moves on each time you record one.",
  "@serviceIntervalHelp": {
    "description": "Explains serviceIntervalDays."
  },
  "labelServiceType": "What happened",
  "@labelServiceType": {
    "description": "service_records.type."
  },
  "serviceTypeService": "Serviced",
  "@serviceTypeService": {
    "description": "ServiceRecordType.service."
  },
  "serviceTypeRepair": "Repaired",
  "@serviceTypeRepair": {
    "description": "ServiceRecordType.repair."
  },
  "serviceTypeMaintenance": "Maintenance",
  "@serviceTypeMaintenance": {
    "description": "ServiceRecordType.maintenance."
  },
  "serviceTypeInspection": "Inspection",
  "@serviceTypeInspection": {
    "description": "ServiceRecordType.inspection."
  },
  "serviceTypeSalaryPaid": "Salary paid",
  "@serviceTypeSalaryPaid": {
    "description": "ServiceRecordType.salaryPaid — the maid case."
  },
  "serviceTypeOther": "Something else",
  "@serviceTypeOther": {
    "description": "ServiceRecordType.other."
  },
  "labelProviderName": "Who did it",
  "@labelProviderName": {
    "description": "service_records.providerName."
  },
  "labelProviderPhone": "Their number",
  "@labelProviderPhone": {
    "description": "service_records.providerPhone."
  },
  "labelServiceDate": "When",
  "@labelServiceDate": {
    "description": "service_records.serviceDateKey."
  },
  "labelServiceCost": "Cost",
  "@labelServiceCost": {
    "description": "service_records.cost."
  },
  "labelNextDue": "Next one due",
  "@labelNextDue": {
    "description": "service_records.nextDueDateKey."
  },
  "alsoRecordAsExpense": "Also record it as an expense",
  "@alsoRecordAsExpense": {
    "description": "The alsoRecordAsExpense toggle."
  },
  "alsoRecordHelp": "Writes a withdrawal for the cost as well, so it shows in your ledger.",
  "@alsoRecordHelp": {
    "description": "Explains what the toggle writes."
  },
  "alsoRecordNeedsAccount": "Choose which account it comes from",
  "@alsoRecordNeedsAccount": {
    "description": "Rejection when the toggle is on with no account."
  },
  "alsoRecordNeedsCost": "Add a cost first",
  "@alsoRecordNeedsCost": {
    "description": "Rejection when the toggle is on with no cost."
  },
  "saveService": "Save",
  "@saveService": {
    "description": "Commits a service record."
  },
  "disposeTitle": "What happened to it?",
  "@disposeTitle": {
    "description": "Dispose sheet title."
  },
  "disposeBody": "It stays in your records either way — what you spent on it still counts. This just stops it appearing as something you own.",
  "@disposeBody": {
    "description": "States anomaly A30 plainly: an asset is never deleted."
  },
  "disposeReasonSold": "Sold it",
  "@disposeReasonSold": {
    "description": "AssetDisposalReason.sold."
  },
  "disposeReasonExpired": "Wore out",
  "@disposeReasonExpired": {
    "description": "AssetDisposalReason.expired."
  },
  "disposeReasonDamaged": "Broke",
  "@disposeReasonDamaged": {
    "description": "AssetDisposalReason.damaged."
  },
  "disposeReasonGifted": "Gave it away",
  "@disposeReasonGifted": {
    "description": "AssetDisposalReason.gifted."
  },
  "disposeReasonLost": "Lost it",
  "@disposeReasonLost": {
    "description": "AssetDisposalReason.lost."
  },
  "disposeReasonReplaced": "Replaced it",
  "@disposeReasonReplaced": {
    "description": "AssetDisposalReason.replaced."
  },
  "disposeReasonOther": "Something else",
  "@disposeReasonOther": {
    "description": "AssetDisposalReason.other."
  },
  "labelDisposalAmount": "Got back",
  "@labelDisposalAmount": {
    "description": "assets.disposalAmount — what the disposal recovered."
  },
  "labelDisposalDate": "When",
  "@labelDisposalDate": {
    "description": "assets.disposedAtDateKey."
  },
  "disposeCommit": "Record it",
  "@disposeCommit": {
    "description": "Commits the disposal."
  },
  "disposeDone": "Recorded",
  "@disposeDone": {
    "description": "Snack after disposing."
  },
  "undisposeDone": "Back in your list",
  "@undisposeDone": {
    "description": "Snack after un-disposing."
  },
  "disposeNeedsReason": "Pick what happened",
  "@disposeNeedsReason": {
    "description": "Rejection when no reason is chosen."
  },
  "hintSearchAssets": "Search your things and people",
  "@hintSearchAssets": {
    "description": "Search hint on the asset list."
  },
  "errorWarrantyBackwards": "The warranty cannot end before it starts",
  "@errorWarrantyBackwards": {
    "description": "Field error when warrantyEndDateKey precedes warrantyStartDateKey."
  },
  "sectionMoney": "Money",
  "@sectionMoney": {
    "description": "Header above the cost and expense controls on the service editor."
  },
  "assetCreatedFromPurchase": "Saved. Now say what it is and how long it is covered.",
  "@assetCreatedFromPurchase": {
    "description": "Snack after a purchase line created an asset."
  },
  "destinationHelpNone": "Recorded as spending and nothing else.",
  "@destinationHelpNone": {
    "description": "Explains destination none."
  },
  "destinationHelpInventory": "Groceries, refills, anything measured and consumed. Needs an item and a quantity, and creates stock you can run down.",
  "@destinationHelpInventory": {
    "description": "Explains destination inventory."
  },
  "destinationHelpAsset": "A phone, a fridge, a chair. Creates something you own, with its own warranty and service history.",
  "@destinationHelpAsset": {
    "description": "Explains destination asset."
  },
  "destinationHelpRecurring": "Sets up a schedule so this comes back every month.",
  "@destinationHelpRecurring": {
    "description": "Explains destination recurring."
  },
  "assetSameNameNote": "You already have one called this. That is fine — this will be a separate one, with its own warranty and service history.",
  "@assetSameNameNote": {
    "description": "Informational note when an asset name repeats. Never a block: five iPhones are five assets."
  },
  "@destinationNone": {
    "description": "No artefact. Recorded as spending and nothing else."
  },
  "@destinationInventory": {
    "description": "Creates stock. Names the Inventory module, matching navInventory."
  },
  "@destinationAsset": {
    "description": "Creates an asset. Names the Services module, matching navServices."
  },
  "@destinationRecurring": {
    "description": "Hands off to the template builder. Matches navRecurring."
  },
  "actionSetWarranty": "Set the warranty",
  "@actionSetWarranty": {
    "description": "Snack action opening the asset a purchase line created."
  },
  "labelPaymentMethodOptional": "How you paid (optional)",
  "@labelPaymentMethodOptional": {
    "description": "Optional payment method on the service editor. Travels to the expense, never onto the record."
  },
  "dashboardTitle": "Home",
  "@dashboardTitle": {
    "description": "Dashboard screen title."
  },
  "fundsAvailable": "Total available funds",
  "@fundsAvailable": {
    "description": "Label above the one headline figure on the dashboard."
  },
  "fundsUnconverted": "{count, plural, =1{1 balance not converted} other{{count} balances not converted}}",
  "@fundsUnconverted": {
    "description": "Chip when BalanceService could not convert some accounts. Excluded from the headline, never summed (anomaly A34).",
    "placeholders": {
      "count": {}
    }
  },
  "fundsApproximate": "Rate is older than today",
  "@fundsApproximate": {
    "description": "Chip when the conversion used the most recent rate on or before today."
  },
  "fundsWhyExcluded": "Balances Alaya has no rate for are left out rather than guessed at.",
  "@fundsWhyExcluded": {
    "description": "Explains why the headline may be lower than the sum of every account."
  },
  "rangeLast30": "Last 30 days",
  "@rangeLast30": {
    "description": "Range label. Always stated, never implied (anomaly A33)."
  },
  "rangeMoneyIn": "In",
  "@rangeMoneyIn": {
    "description": "Deposits over the labelled range."
  },
  "rangeMoneyOut": "Out",
  "@rangeMoneyOut": {
    "description": "Withdrawals over the labelled range."
  },
  "rangeNothingYet": "Nothing yet",
  "@rangeNothingYet": {
    "description": "Shown in place of a figure when a range holds no transactions."
  },
  "rangeExcluded": "{count, plural, =1{1 left out} other{{count} left out}}",
  "@rangeExcluded": {
    "description": "Chip when transactions in a foreign currency could not be converted into the range total.",
    "placeholders": {
      "count": {}
    }
  },
  "insightUpcoming": "Coming up",
  "@insightUpcoming": {
    "description": "The calendar side of the switchable insight card."
  },
  "insightSpending": "Where it went",
  "@insightSpending": {
    "description": "The analytics side of the switchable insight card."
  },
  "insightSwitchLabel": "Show",
  "@insightSwitchLabel": {
    "description": "Semantics label for the insight card switch."
  },
  "insightNothingUpcoming": "Nothing needs attention in the next fortnight.",
  "@insightNothingUpcoming": {
    "description": "Empty state for the upcoming side."
  },
  "insightAnalyticsPending": "Spending breakdowns arrive with the analytics module.",
  "@insightAnalyticsPending": {
    "description": "Honest empty state: AnalyticsService has no data adapter until Phase 7B (ARCH_4 §5.1 item 15)."
  },
  "insightBillDue": "Bill due",
  "@insightBillDue": {
    "description": "Upcoming row for a recurring occurrence."
  },
  "insightServiceDue": "Service due",
  "@insightServiceDue": {
    "description": "Upcoming row for an asset needing service."
  },
  "insightWarrantyEnding": "Warranty ending",
  "@insightWarrantyEnding": {
    "description": "Upcoming row for an expiring warranty."
  },
  "insightBatchExpiring": "Expiring",
  "@insightBatchExpiring": {
    "description": "Upcoming row for a batch past or near its expiry."
  },
  "moduleGridTitle": "Where to next",
  "@moduleGridTitle": {
    "description": "Header above the navigation tiles."
  },
  "moduleExpenses": "{count, plural, =0{none this month} =1{1 this month} other{{count} this month}}",
  "@moduleExpenses": {
    "description": "Live number on the Expenses tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleInventory": "{count, plural, =0{nothing tracked} =1{1 running low} other{{count} running low}}",
  "@moduleInventory": {
    "description": "Live number on the Inventory tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleShopping": "{count, plural, =0{list is clear} =1{1 to buy} other{{count} to buy}}",
  "@moduleShopping": {
    "description": "Live number on the Shopping tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleRecurring": "{count, plural, =0{all settled} =1{1 due} other{{count} due}}",
  "@moduleRecurring": {
    "description": "Live number on the Recurring tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleServices": "{count, plural, =0{nothing needs doing} =1{1 needs attention} other{{count} need attention}}",
  "@moduleServices": {
    "description": "Live number on the Services tile.",
    "placeholders": {
      "count": {}
    }
  },
  "fabAddIncome": "Money in",
  "@fabAddIncome": {
    "description": "FAB action opening the editor as a deposit."
  },
  "fabAddItem": "New item",
  "@fabAddItem": {
    "description": "FAB action opening the item editor."
  },
  "loadingDashboard": "Adding it up",
  "@loadingDashboard": {
    "description": "Skeleton label for the dashboard."
  },
  "fabOpenLabel": "Add something",
  "@fabOpenLabel": {
    "description": "Semantics label for the closed expandable FAB."
  },
  "fabCloseLabel": "Close",
  "@fabCloseLabel": {
    "description": "Semantics label for the open expandable FAB."
  },
  "eventTypeTransaction": "Transaction",
  "eventTypeRecurringDue": "Recurring bill",
  "eventTypeBatchExpiry": "Expiring",
  "eventTypeWarrantyEnd": "Warranty ending",
  "eventTypeServiceDue": "Service due",
  "eventTypeShoppingTarget": "Shopping target",
  "calendarSeverityWarning": "Needs attention",
  "calendarSeverityDanger": "Past its date",
  "calendarLoadingDay": "Loading this day…",
  "calendarDayErrorTitle": "Could not load this day",
  "calendarDayEmptyTitle": "Nothing on this day",
  "calendarDayEmptyBody": "No transactions, bills, expiries or services fall here.",
  "calendarRetry": "Try again",
  "calendarLoadingMonth": "Loading this month…",
  "calendarErrorTitle": "Could not load the calendar",
  "calendarPreviousMonth": "Previous month",
  "calendarNextMonth": "Next month",
  "calendarOnDay": "On this day",
  "calendarRangeOn": "Select a range",
  "calendarRangeOff": "Stop selecting a range",
  "calendarRangePickEnd": "From {start} — tap another day to finish.",
  "calendarInRange": "{count, plural, =1{1 day} other{{count} days}}",
  "calendarRangeEmptyTitle": "Nothing in these days",
  "calendarRangeEmptyBody": "No transactions, bills, expiries or services fall inside the range.",
  "@calendarRangePickEnd": {
    "description": "Prompt after the range start is chosen.",
    "placeholders": {
      "start": {
        "type": "String"
      }
    }
  },
  "@calendarInRange": {
    "description": "How many days the chosen range spans.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "calendarBackToToday": "Back to this month",
  "calendarTotalOut": "Spent",
  "calendarTotalIn": "Received",
  "dashboardOpenCalendar": "Open calendar",
  "dashboardCalendarSemantics": "{month} at a glance. Opens the calendar.",
  "@dashboardCalendarSemantics": {
    "description": "Screen-reader label for the dashboard month card where days are too narrow to tap.",
    "placeholders": {
      "month": {
        "type": "String"
      }
    }
  },
  "navBackToDashboard": "Back to dashboard"
}
```

> **Reconciled 2026-08-05.** This is Phase 6F's `app_en.arb` — a strict superset of the pre-6F file (876 keys plus 60 dashboard keys, nothing dropped, no value changed). The six pre-6F documents carried the smaller version, so applying any of them after 6F silently removed every dashboard string. ARCH_6 §2's cross-document diff should have caught this and did not; it is the second live instance of the drift §2 declares closed.


### `lib/app/router/routes.dart`

```dart
/// Every route path in the app, in one place.
///
/// Hand-written: `go_router_builder` cannot resolve alongside `drift_dev` (ARCH_1 §7.1). A literal
/// path anywhere else is a route that drifts silently when this file changes.
abstract final class Routes {
  /// Where the app opens.
  static const String initial = dashboard;

  // ── top level, inside the drawer shell ──

  /// The dashboard.
  static const String dashboard = '/';

  /// The transaction ledger.
  static const String expenses = '/expenses';

  /// The inventory catalogue.
  static const String inventory = '/inventory';

  /// The shopping lists.
  static const String shopping = '/shopping';

  /// The recurring templates.
  static const String recurring = '/recurring';

  /// The assets and service records.
  static const String services = '/services';

  /// The calendar.
  static const String calendar = '/calendar';

  /// The insights.
  static const String insights = '/insights';

  /// The settings.
  static const String settings = '/settings';

  // ── outside the shell: full-screen editors and the lock ──

  /// The PIN gate.
  static const String lock = '/lock';

  /// The palette workbench.
  static const String themeLab = '/settings/theme-lab';

  /// A new transaction.
  static const String transactionNew = '/expenses/new';

  /// The line items of a new transaction.
  static const String transactionLinesNew = '/expenses/new/lines';

  /// A new item.
  static const String itemNew = '/inventory/new';

  /// A new recurring template.
  static const String recurringNew = '/recurring/new';

  /// A new asset.
  static const String assetNew = '/services/new';

  // ── parameterised ──

  /// Path pattern for one transaction.
  static const String transactionDetailPattern = '/expenses/:transactionId';

  /// Path pattern for editing one transaction.
  static const String transactionEditPattern = '/expenses/:transactionId/edit';

  /// Path pattern for the line items of one transaction.
  static const String transactionLinesPattern = '/expenses/:transactionId/lines';

  /// Path pattern for one item.
  static const String itemDetailPattern = '/inventory/:itemId';

  /// Path pattern for editing one item.
  static const String itemEditPattern = '/inventory/:itemId/edit';

  /// Path pattern for adding a batch to one item.
  static const String batchNewPattern = '/inventory/:itemId/batch/new';

  /// Path pattern for editing one batch.
  static const String batchEditPattern = '/inventory/:itemId/batch/:batchId';

  /// Path pattern for one batch's movement history.
  static const String batchHistoryPattern = '/inventory/:itemId/batch/:batchId/history';

  /// Path pattern for one shopping list.
  static const String shoppingListPattern = '/shopping/:listId';

  /// Path pattern for turning a shopping list's ticked entries into a purchase.
  static const String shoppingConvertPattern = '/shopping/:listId/convert';

  /// Path pattern for editing one recurring template.
  static const String recurringEditPattern = '/recurring/:templateId/edit';

  /// Path pattern for one template's occurrence history.
  static const String recurringHistoryPattern = '/recurring/:templateId/history';

  /// Path pattern for one recurring template.
  static const String recurringDetailPattern = '/recurring/:templateId';

  /// Path pattern for editing one asset.
  static const String assetEditPattern = '/services/:assetId/edit';

  /// Path pattern for a new service record against one asset.
  static const String serviceNewPattern = '/services/:assetId/service/new';

  /// Path pattern for editing one service record.
  static const String serviceEditPattern = '/services/:assetId/service/:recordId';

  /// Path pattern for one asset.
  static const String assetDetailPattern = '/services/:assetId';

  /// Path pattern for one calendar day.
  static const String calendarDayPattern = '/calendar/:dateKey';

  // ── param names, so a builder reading them cannot misspell one ──

  /// The transaction id parameter.
  static const String pTransactionId = 'transactionId';

  /// The item id parameter.
  static const String pItemId = 'itemId';

  /// The batch id parameter.
  static const String pBatchId = 'batchId';

  /// The shopping list id parameter.
  static const String pListId = 'listId';

  /// The recurring template id parameter.
  static const String pTemplateId = 'templateId';

  /// The asset id parameter.
  static const String pAssetId = 'assetId';

  /// The service record id parameter.
  static const String pRecordId = 'recordId';

  /// The calendar date parameter.
  static const String pDateKey = 'dateKey';

  // ── builders ──

  /// The location for transaction [id].
  static String transactionDetail(String id) => '$expenses/$id';

  /// The location for editing transaction [id].
  static String transactionEdit(String id) => '$expenses/$id/edit';

  /// The location for the line items of transaction [id], or of a new one when null.
  static String transactionLines(String? id) =>
      id == null ? transactionLinesNew : '$expenses/$id/lines';

  /// The location for item [id].
  static String itemDetail(String id) => '$inventory/$id';

  /// The location for editing item [id].
  static String itemEdit(String id) => '$inventory/$id/edit';

  /// The location for adding a batch to item [itemId].
  static String batchNew(String itemId) => '$inventory/$itemId/batch/new';

  /// The location for editing batch [batchId] of item [itemId].
  static String batchEdit(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId';

  /// The location for batch [batchId]'s movement history.
  static String batchHistory(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId/history';

  /// The location for shopping list [id].
  static String shoppingList(String id) => '$shopping/$id';

  /// The location for converting shopping list [id] into a purchase.
  static String shoppingConvert(String id) => '$shopping/$id/convert';

  /// The location for recurring template [id].
  static String recurringDetail(String id) => '$recurring/$id';

  /// The location for editing recurring template [id], or for a new one when null.
  static String recurringEdit(String? id) =>
      id == null ? recurringNew : '$recurring/$id/edit';

  /// The location for template [id]'s occurrence history.
  static String recurringHistory(String id) => '$recurring/$id/history';

  /// The location for asset [id].
  static String assetDetail(String id) => '$services/$id';

  /// The location for editing asset [id], or for a new one when null.
  static String assetEdit(String? id) => id == null ? assetNew : '$services/$id/edit';

  /// The location for a new service record against asset [assetId].
  static String serviceNew(String assetId) => '$services/$assetId/service/new';

  /// The location for editing service record [recordId] of asset [assetId].
  static String serviceEdit(String assetId, String recordId) =>
      '$services/$assetId/service/$recordId';

  /// The location for the calendar on [dateKey].
  static String calendarDay(int dateKey) => '$calendar/$dateKey';

  /// The nine drawer destinations, in drawer order.
  ///
  /// Named for the drawer rather than the shell because `AlayaDrawer` reads it by this name — a route
  /// cannot exist in the router and be missing from the drawer without this list disagreeing.
  static const List<String> drawerDestinations = [
    dashboard,
    expenses,
    inventory,
    shopping,
    recurring,
    services,
    calendar,
    insights,
    settings,
  ];
}
```

### `lib/app/router/app_router.dart`

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/placeholder_screen.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_detail_screen.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_editor_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_editor_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_history_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_detail_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_editor_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/occurrence_history_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_builder_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_editor_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/service_editor_screen.dart';
import 'package:alaya/features/settings/presentation/theme_lab_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/convert_to_purchase_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/shopping_list_screen.dart';
import 'package:alaya/shared/widgets/alaya_drawer.dart';

/// Whether the app is currently locked, consulted on every navigation.
typedef LockGate = bool Function();

/// The app's `go_router` configuration — hand-written, per ARCH_1 §7.3.
///
/// **The nine drawer destinations sit inside the shell; every detail and editor route sits outside
/// it** (U18). `AppBar` resolves its leading slot by checking `hasDrawer` *before* `canPop`, so a
/// detail screen rendered inside the drawer shell gets a hamburger where a back arrow belongs.
///
/// Literal-path segments are declared before their parameterised siblings, because go_router walks
/// its route list in order and `:itemId` would otherwise swallow the word `new`.
abstract final class AppRouter {
  /// Builds the router.
  static GoRouter build({
    LockGate? isLocked,
    String initialLocation = Routes.initial,
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    final locked = isLocked ?? () => false;
    return GoRouter(
      initialLocation: initialLocation,
      navigatorKey: navigatorKey,
      debugLogDiagnostics: false,
      redirect: (context, state) {
        final atLock = state.matchedLocation == Routes.lock;
        if (locked() && !atLock) return Routes.lock;
        if (!locked() && atLock) return Routes.dashboard;
        return null;
      },
      routes: [
        GoRoute(
          path: Routes.lock,
          builder: (context, state) =>
              const PlaceholderScreen(owningPhase: 'Phase 8A'),
        ),
        ShellRoute(
          // No `location` passed: `_ShellScaffold` reads it from the router, because the state handed to a
          // pathless `ShellRoute`'s builder reports `/` for every screen inside it.
          builder: (context, state, child) => _ShellScaffold(child: child),
          routes: [
            GoRoute(
              path: Routes.dashboard,
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(
              path: Routes.expenses,
              builder: (context, state) => const TransactionListScreen(),
            ),
            GoRoute(
              path: Routes.inventory,
              builder: (context, state) => const InventoryListScreen(),
            ),
            GoRoute(
              path: Routes.shopping,
              builder: (context, state) => const ShoppingListScreen(),
            ),
            GoRoute(
              path: Routes.recurring,
              builder: (context, state) => const TemplateListScreen(),
            ),
            GoRoute(
              path: Routes.services,
              builder: (context, state) => const AssetListScreen(),
            ),
            GoRoute(
              path: Routes.calendar,
              builder: (context, state) => const CalendarScreen(),
              routes: [
                // A sub-route rather than a sibling detail route: a day is a view of the month, so it
                // keeps the drawer shell and the month stays behind it (Law U27).
                GoRoute(
                  path: ':${Routes.pDateKey}',
                  builder: (context, state) => CalendarScreen(
                    initialDay: _dateKeyParam(
                      state.pathParameters[Routes.pDateKey],
                    ),
                  ),
                ),
              ],
            ),
            _destination(Routes.insights, 'Phase 7B'),
            _destination(Routes.settings, 'Phase 8A'),
          ],
        ),
        GoRoute(
          path: Routes.transactionNew,
          builder: (context, state) => const TransactionEditorScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesNew,
          builder: (context, state) => const LineItemsScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesPattern,
          builder: (context, state) => LineItemsScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionEditPattern,
          builder: (context, state) => TransactionEditorScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionDetailPattern,
          builder: (context, state) => TransactionDetailScreen(
            transactionId: state.pathParameters[Routes.pTransactionId]!,
          ),
        ),
        GoRoute(
          path: Routes.itemNew,
          builder: (context, state) => const ItemEditorScreen(),
        ),
        GoRoute(
          path: Routes.batchNewPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchHistoryPattern,
          builder: (context, state) => BatchHistoryScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchEditPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId],
          ),
        ),
        GoRoute(
          path: Routes.itemEditPattern,
          builder: (context, state) => ItemEditorScreen(
            itemId: state.pathParameters[Routes.pItemId],
          ),
        ),
        GoRoute(
          path: Routes.itemDetailPattern,
          builder: (context, state) => ItemDetailScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingConvertPattern,
          builder: (context, state) => ConvertToPurchaseScreen(
            listId: state.pathParameters[Routes.pListId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingListPattern,
          builder: (context, state) => ShoppingListScreen(
            listId: state.pathParameters[Routes.pListId],
          ),
        ),
        GoRoute(
          path: Routes.recurringNew,
          builder: (context, state) => const TemplateBuilderScreen(),
        ),
        GoRoute(
          path: Routes.recurringHistoryPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.recurringEditPattern,
          builder: (context, state) => TemplateBuilderScreen(
            templateId: state.pathParameters[Routes.pTemplateId],
          ),
        ),
        GoRoute(
          path: Routes.recurringDetailPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.assetNew,
          builder: (context, state) => const AssetEditorScreen(),
        ),
        GoRoute(
          path: Routes.serviceNewPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.serviceEditPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
            recordId: state.pathParameters[Routes.pRecordId],
          ),
        ),
        GoRoute(
          path: Routes.assetEditPattern,
          builder: (context, state) => AssetEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId],
          ),
        ),
        GoRoute(
          path: Routes.assetDetailPattern,
          builder: (context, state) => AssetDetailScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.themeLab,
          builder: (context, state) => _DetailScaffold(
            title: AlayaStrings.of(context).navThemeLab,
            child: const ThemeLabScreen(),
          ),
        ),
      ],
    );
  }

  /// A top-level drawer destination, rendered inside the shell.
  static GoRoute _destination(String path, String owningPhase) => GoRoute(
    path: path,
    builder: (context, state) => PlaceholderScreen(owningPhase: owningPhase),
  );

  /// A detail route, rendered outside the shell so it gets a back arrow rather than a hamburger.
  static GoRoute _detail(String pattern, String owningPhase) => GoRoute(
    path: pattern,
    builder: (context, state) => _DetailScaffold(
      title: AlayaDrawer.titleFor(context, state.uri.path),
      child: PlaceholderScreen(owningPhase: owningPhase),
    ),
  );
}

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // `AppBar` resolves its implied leading by checking `hasDrawer` **before** `canPop`, so a shell that
    // owns a drawer can never show a back arrow no matter how it was reached. That is fine for a drawer
    // destination switched into as a peer, and wrong for one pushed as a drill-down — and both happen
    // here: the drawer `go`es, the dashboard's module grid `push`es.
    //
    // So the slot is stated rather than implied. Pushed: a back arrow that pops the shell's own navigator
    // (`context.pop`, not `Navigator.maybePop`, which from above the shell navigator would target the root
    // one and do nothing). Switched into: null, which lets the hamburger be implied as before.
    //
    // The drawer stays attached either way, so the edge swipe still opens it on a pushed screen.
    final strings = AlayaStrings.of(context);

    // **Read from the router, not from the builder's `state`.** `ShellRoute` declares no `path`, so the
    // `GoRouterState` handed to its builder describes the *shell's* match rather than the leaf's — and a
    // pathless route's `matchedLocation` is its parent's, which here is `/`. Every screen inside the shell
    // therefore looked like the dashboard: `atDashboard` was permanently true so the home action never
    // rendered, `AlayaDrawer` highlighted Dashboard wherever you were, and `titleFor` named it too.
    //
    // `currentConfiguration` is the delegate's live `RouteMatchList`, so its `uri` is the leaf location no
    // matter which builder asks.
    final here = GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;

    // **`context.canPop()` cannot answer this question from here.** This widget is the `ShellRoute`
    // builder, so its context sits *above* the shell's own `Navigator`; `canPop` resolves against the
    // root navigator, which only ever holds the shell itself. It therefore returns false however the
    // screen was reached, `leading` was always null, and the back arrow this once tried to show could
    // never appear. The drawer's hamburger was the only leading widget users ever saw, and from a module
    // the sole way home was the system back gesture.
    //
    // So the way home is stated outright instead of inferred from a stack this context cannot see: every
    // shell screen except the dashboard carries a home action. It pops when there is something to pop and
    // navigates otherwise, so arriving by the module grid's `push` and by the drawer's `go` both end up
    // in the same place — and the hamburger keeps its slot, because the drawer is still how you move
    // between peers (Law U27).
    return Scaffold(
      drawer: AlayaDrawer(currentLocation: here),
      appBar: AppBar(
        title: Text(AlayaDrawer.titleFor(context, here)),
        // **Unconditional, deliberately.** This was `if (!atDashboard)` and never appeared, and rather
        // than reason about why a condition is false I would rather the button exist and be seen. It
        // shows on the dashboard too, where it is merely redundant — a redundant button is a far smaller
        // fault than a missing one, and its presence there is also the proof that this file is live.
        //
        // Once it is confirmed visible, `if (!atDashboard)` can come back.
        actions: [
          IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(Routes.dashboard),
            tooltip: strings.navBackToDashboard,
            icon: const Icon(Icons.home_outlined, size: AlayaIconSize.md),
          ),
        ],
      ),
      body: child,
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}

/// Parses a `:dateKey` path parameter, or null when it is absent or not a date key.
///
/// A malformed deep link opens the calendar on today rather than throwing — the route is reachable
/// from outside the app.
DateKey? _dateKeyParam(String? raw) {
  final value = int.tryParse(raw ?? '');
  if (value == null) return null;

  final year = value ~/ 10000;
  final month = (value ~/ 100) % 100;
  final day = value % 100;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  // Round-trip through `fromYmd`, which normalises overflow through `DateTime.utc`: 20260230 comes
  // back as 20260302 and fails this check, where a digit-range test alone would accept it.
  final probe = DateKey.fromYmd(year, month, day);
  return probe.value == value ? probe : null;
}
```

### `lib/app/router/placeholder_screen.dart`

```dart
// PLACEHOLDER: PHASE_06
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// Stands in for a feature screen until the phase that owns it lands.
///
/// One parameterised placeholder rather than nine near-identical stub files: nine stubs would each
/// need deleting, and a stub left behind is indistinguishable from a real screen that does nothing.
///
/// It carries no destination name of its own. The surrounding scaffold titles itself from
/// `AlayaDrawer.titleFor`, so every visible name is localised in one place instead of appearing here
/// as a dozen English literals that no translator would ever see.
class PlaceholderScreen extends StatelessWidget {
  /// Creates a placeholder owned by [owningPhase], e.g. `Phase 6A`.
  const PlaceholderScreen({required this.owningPhase, super.key});

  /// The phase that will replace this. Developer text, deliberately not localised.
  final String owningPhase;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AlayaSpacing.xxl),
        child: Text(
          owningPhase,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
```

### `lib/app/providers/infrastructure_providers.dart`

```dart
/// The bottom of the dependency graph: the database, the DAOs, and the ambient singletons.
///
/// **Hand-written, because `@riverpod` needs `riverpod_generator` and `drift_dev` is the only
/// codegen package this project may have (ARCH_1 §7.3).** A second one makes the whole project
/// unresolvable, so the annotation is not available at any price.
///
/// Providers rather than a service locator so that a widget test can override exactly one
/// dependency — `databaseProvider` with an in-memory database, `clockProvider` with a `FixedClock` —
/// without constructing the other forty.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/text/normalizer.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/account_dao.dart';
import 'package:alaya/data/daos/analytics_cache_dao.dart';
import 'package:alaya/data/daos/calendar_dao.dart';
import 'package:alaya/data/daos/asset_dao.dart';
import 'package:alaya/data/daos/backup_history_dao.dart';
import 'package:alaya/data/daos/batch_dao.dart';
import 'package:alaya/data/daos/currency_dao.dart';
import 'package:alaya/data/daos/item_dao.dart';
import 'package:alaya/data/daos/notification_schedule_dao.dart';
import 'package:alaya/data/daos/payee_dao.dart';
import 'package:alaya/data/daos/payment_method_dao.dart';
import 'package:alaya/data/daos/recurring_occurrence_dao.dart';
import 'package:alaya/data/daos/recurring_template_dao.dart';
import 'package:alaya/data/daos/service_record_dao.dart';
import 'package:alaya/data/daos/settings_dao.dart';
import 'package:alaya/data/daos/shopping_entry_dao.dart';
import 'package:alaya/data/daos/shopping_list_dao.dart';
import 'package:alaya/data/daos/stock_movement_dao.dart';
import 'package:alaya/data/daos/tag_dao.dart';
import 'package:alaya/data/daos/transaction_dao.dart';
import 'package:alaya/data/daos/transaction_line_dao.dart';
import 'package:alaya/data/daos/unit_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/security/secure_key_value_store.dart';


/// The open database.
///
/// **Overridden in `bootstrap` with the real connection** and in tests with
/// `AlayaDatabase(NativeDatabase.memory())`. It throws if read un-overridden, which is deliberate:
/// a provider that silently opened a second connection would violate L10's single-open-path rule and
/// the symptom would be a locked database rather than an error naming the cause.
final databaseProvider = Provider<AlayaDatabase>((ref) {
  throw StateError(
    'databaseProvider was not overridden. bootstrap() must supply the connection — see '
    'data/db/connection/open_database.dart, the only permitted open path (ARCH_1 L10).',
  );
});

/// The wall clock.
///
/// Every timestamp and every "today" in the app comes from here, which is what makes a date-sensitive
/// test reproducible instead of dependent on when it ran.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// The UUID v7 generator.
final uidGeneratorProvider = Provider<UidGenerator>((ref) => const Uuid7Generator());

/// The logger.
final loggerProvider = Provider<Logger>((ref) => const DeveloperLogger());

/// The text normaliser used for duplicate detection and search.
final normalizerProvider = Provider<Normalizer>((ref) => const Normalizer());

/// The HTTP client, configured for one job: a fire-and-forget rate fetch.
///
/// The timeouts are literal `Duration`s and not `AlayaDurations` values, deliberately. That scale is a
/// UI animation scale measured in tens of milliseconds; a network timeout is seconds, and borrowing an
/// animation token for one would be a category error rather than reuse.
///
/// They are short because `syncDailyRates` must never block a write (Law L11). A rate that arrives
/// late is worth nothing — the cached rate is already in use — so the call gives up quickly rather
/// than holding a connection open on a bad network.
final dioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
    ),
  ),
);

/// Secure key-value storage, for the app lock only.
///
/// Never the database (ARCH_3 §2.1) — that separation is what stops a restore from replacing the
/// user's PIN with the one from the backup.
final secureKeyValueStoreProvider =
    Provider<SecureKeyValueStore>((ref) => const FlutterSecureKeyValueStore());

// ── DAOs ────────────────────────────────────────────────────────────────────────────────
//
// One per aggregate, each a thin `DatabaseAccessor` over the single connection. They are separate
// providers rather than getters on the database because `@DriftDatabase` here declares no `daos:`
// list, so there are no generated accessors to reach for.

/// The accounts DAO.
final accountDaoProvider = Provider<AccountDao>((ref) => AccountDao(ref.watch(databaseProvider)));

/// The transactions DAO.
final transactionDaoProvider =
    Provider<TransactionDao>((ref) => TransactionDao(ref.watch(databaseProvider)));

/// The transaction-lines DAO.
final transactionLineDaoProvider =
    Provider<TransactionLineDao>((ref) => TransactionLineDao(ref.watch(databaseProvider)));

/// The payment-methods DAO.
final paymentMethodDaoProvider =
    Provider<PaymentMethodDao>((ref) => PaymentMethodDao(ref.watch(databaseProvider)));

/// The payees DAO.
final payeeDaoProvider = Provider<PayeeDao>((ref) => PayeeDao(ref.watch(databaseProvider)));

/// The tags DAO.
final tagDaoProvider = Provider<TagDao>((ref) => TagDao(ref.watch(databaseProvider)));

/// The currencies and rates DAO.
final currencyDaoProvider = Provider<CurrencyDao>((ref) => CurrencyDao(ref.watch(databaseProvider)));

/// The units DAO.
final unitDaoProvider = Provider<UnitDao>((ref) => UnitDao(ref.watch(databaseProvider)));

/// The settings DAO.
final settingsDaoProvider = Provider<SettingsDao>((ref) => SettingsDao(ref.watch(databaseProvider)));

/// The items DAO.
final itemDaoProvider = Provider<ItemDao>((ref) => ItemDao(ref.watch(databaseProvider)));

/// The inventory-batches DAO.
final batchDaoProvider = Provider<BatchDao>((ref) => BatchDao(ref.watch(databaseProvider)));

/// The stock-movements DAO.
final stockMovementDaoProvider =
    Provider<StockMovementDao>((ref) => StockMovementDao(ref.watch(databaseProvider)));

/// The shopping-lists DAO.
final shoppingListDaoProvider =
    Provider<ShoppingListDao>((ref) => ShoppingListDao(ref.watch(databaseProvider)));

/// The shopping-entries DAO.
final shoppingEntryDaoProvider =
    Provider<ShoppingEntryDao>((ref) => ShoppingEntryDao(ref.watch(databaseProvider)));

/// The recurring-templates DAO.
final recurringTemplateDaoProvider =
    Provider<RecurringTemplateDao>((ref) => RecurringTemplateDao(ref.watch(databaseProvider)));

/// The recurring-occurrences DAO.
final recurringOccurrenceDaoProvider =
    Provider<RecurringOccurrenceDao>((ref) => RecurringOccurrenceDao(ref.watch(databaseProvider)));

/// The assets DAO.
final assetDaoProvider = Provider<AssetDao>((ref) => AssetDao(ref.watch(databaseProvider)));

/// The service-records DAO.
final serviceRecordDaoProvider =
    Provider<ServiceRecordDao>((ref) => ServiceRecordDao(ref.watch(databaseProvider)));

/// The notification-schedule DAO.
final notificationScheduleDaoProvider =
    Provider<NotificationScheduleDao>((ref) => NotificationScheduleDao(ref.watch(databaseProvider)));

/// The backup-history DAO.
final backupHistoryDaoProvider =
    Provider<BackupHistoryDao>((ref) => BackupHistoryDao(ref.watch(databaseProvider)));

/// The analytics-cache DAO.
final analyticsCacheDaoProvider =
    Provider<AnalyticsCacheDao>((ref) => AnalyticsCacheDao(ref.watch(databaseProvider)));

/// The calendar DAO, over `v_calendar_events`.
final calendarDaoProvider =
    Provider<CalendarDao>((ref) => CalendarDao(ref.watch(databaseProvider)));
```

### `lib/app/providers/repository_providers.dart`

```dart
/// One provider per repository contract, typed as the **contract** and never the implementation.
///
/// Typing them as the interface is what makes the layering rule enforceable: a feature that declares
/// `ref.watch(accountRepositoryProvider)` receives an `AccountRepository` and cannot reach into
/// `AccountRepositoryImpl` for a method the contract does not expose.
///
/// **Two of Phase 3A's seventeen contracts have no implementation yet** — `CalendarRepository` and
/// `AnalyticsCacheRepository` — so they have no provider here. See `service_providers.dart` for what
/// that blocks and why stubbing them would be worse.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/data/repositories/calendar_repository_impl.dart';
import 'package:alaya/data/repositories/account_repository_impl.dart';
import 'package:alaya/data/repositories/asset_repository_impl.dart';
import 'package:alaya/data/repositories/batch_repository_impl.dart';
import 'package:alaya/data/repositories/currency_repository_impl.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/item_repository_impl.dart';
import 'package:alaya/data/repositories/payee_repository_impl.dart';
import 'package:alaya/data/repositories/payment_method_repository_impl.dart';
import 'package:alaya/data/repositories/recurring_repository_impl.dart';
import 'package:alaya/data/repositories/service_record_repository_impl.dart';
import 'package:alaya/data/repositories/settings_repository_impl.dart';
import 'package:alaya/data/repositories/shopping_repository_impl.dart';
import 'package:alaya/data/repositories/stock_repository_impl.dart';
import 'package:alaya/data/repositories/tag_repository_impl.dart';
import 'package:alaya/data/repositories/transaction_repository_impl.dart';
import 'package:alaya/data/repositories/unit_repository_impl.dart';
import 'package:alaya/domain/repositories/calendar_repository.dart';
import 'package:alaya/domain/repositories/account_repository.dart';
import 'package:alaya/domain/repositories/asset_repository.dart';
import 'package:alaya/domain/repositories/batch_repository.dart';
import 'package:alaya/domain/repositories/currency_repository.dart';
import 'package:alaya/domain/repositories/item_repository.dart';
import 'package:alaya/domain/repositories/payee_repository.dart';
import 'package:alaya/domain/repositories/payment_method_repository.dart';
import 'package:alaya/domain/repositories/recurring_repository.dart';
import 'package:alaya/domain/repositories/service_record_repository.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/repositories/shopping_repository.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';
import 'package:alaya/domain/repositories/tag_repository.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';
import 'package:alaya/domain/repositories/unit_repository.dart';


/// Resolves an item's unit category, with a per-instance cache.
///
/// A single provider rather than one per consumer, because three repositories need it and its whole
/// value is the cache: constructing it twice halves the hit rate for no reason.
final itemCategoryResolverProvider =
    Provider<ItemCategoryResolver>((ref) => ItemCategoryResolver(ref.watch(itemDaoProvider)));

/// Key-value app settings.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepositoryImpl(ref.watch(settingsDaoProvider), ref.watch(clockProvider)),
);

/// Currencies, rates and conversion.
///
/// Takes `CurrencyRateService` so `syncDailyRates` has one implementation. Phase 3B's
/// `DailyRateFetch` typedef is gone — the repository delegates rather than reimplementing the
/// once-daily check, which the earlier version omitted entirely.
final currencyRepositoryProvider = Provider<CurrencyRepository>(
  (ref) => CurrencyRepositoryImpl(
    ref.watch(currencyDaoProvider),
    ref.watch(clockProvider),
    ref.watch(settingsRepositoryProvider),
    rateService: ref.watch(currencyRateServiceProvider),
  ),
);

/// Units and conversion factors.
final unitRepositoryProvider = Provider<UnitRepository>(
  (ref) => UnitRepositoryImpl(ref.watch(unitDaoProvider), ref.watch(clockProvider)),
);

/// Accounts and balances.
final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepositoryImpl(
    ref.watch(accountDaoProvider),
    ref.watch(transactionDaoProvider),
    ref.watch(currencyRepositoryProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// Payment methods.
final paymentMethodRepositoryProvider = Provider<PaymentMethodRepository>(
  (ref) => PaymentMethodRepositoryImpl(
    ref.watch(paymentMethodDaoProvider),
    ref.watch(clockProvider),
  ),
);

/// Payees.
final payeeRepositoryProvider = Provider<PayeeRepository>(
  (ref) => PayeeRepositoryImpl(ref.watch(payeeDaoProvider), ref.watch(clockProvider)),
);

/// Tags.
final tagRepositoryProvider = Provider<TagRepository>(
  (ref) => TagRepositoryImpl(ref.watch(tagDaoProvider), ref.watch(clockProvider)),
);

/// Transactions, with their lines and stock side effects.
final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepositoryImpl(
    ref.watch(transactionDaoProvider),
    ref.watch(transactionLineDaoProvider),
    ref.watch(accountDaoProvider),
    ref.watch(unitDaoProvider),
    ref.watch(batchDaoProvider),
    ref.watch(stockMovementDaoProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(currencyRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// The item catalogue.
final itemRepositoryProvider = Provider<ItemRepository>(
  (ref) => ItemRepositoryImpl(ref.watch(itemDaoProvider), ref.watch(clockProvider)),
);

/// Inventory batches.
final batchRepositoryProvider = Provider<BatchRepository>(
  (ref) => BatchRepositoryImpl(
    ref.watch(batchDaoProvider),
    ref.watch(itemCategoryResolverProvider),
    ref.watch(clockProvider),
  ),
);

/// Stock levels and movements.
final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => StockRepositoryImpl(
    ref.watch(batchDaoProvider),
    ref.watch(stockMovementDaoProvider),
    ref.watch(itemCategoryResolverProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// Shopping lists and entries.
final shoppingRepositoryProvider = Provider<ShoppingRepository>(
  (ref) => ShoppingRepositoryImpl(
    ref.watch(shoppingListDaoProvider),
    ref.watch(shoppingEntryDaoProvider),
    ref.watch(itemDaoProvider),
    ref.watch(transactionLineDaoProvider),
    ref.watch(itemCategoryResolverProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// Recurring templates and occurrences.
final recurringRepositoryProvider = Provider<RecurringRepository>(
  (ref) => RecurringRepositoryImpl(
    ref.watch(recurringTemplateDaoProvider),
    ref.watch(recurringOccurrenceDaoProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// Assets.
final assetRepositoryProvider = Provider<AssetRepository>(
  (ref) => AssetRepositoryImpl(ref.watch(assetDaoProvider), ref.watch(clockProvider)),
);

/// Service records.
final serviceRecordRepositoryProvider = Provider<ServiceRecordRepository>(
  (ref) => ServiceRecordRepositoryImpl(
    ref.watch(serviceRecordDaoProvider),
    ref.watch(assetDaoProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// The calendar feed. Phase 3A declared the contract and no phase implemented it until 7A
/// (ARCH_4 §5.1 item 15), which is why `calendarAggregatorProvider` could not exist.
final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => CalendarRepositoryImpl(ref.watch(calendarDaoProvider)),
);
```

### `lib/app/providers/service_providers.dart`

```dart
/// One provider per engine.
///
/// The stateless engines are `const` and could in principle be constructed at each use site. They get
/// providers anyway so that every dependency in the app arrives the same way — a codebase where some
/// collaborators are injected and others are constructed inline is one where you cannot tell, from a
/// widget, what it actually depends on.
///
/// ## Three services have no provider, deliberately
///
/// | Service | Blocked on | Owner |
/// |---|---|---|
/// | `AnalyticsService` | `AnalyticsPort` is declared in `domain/` with no `data/` adapter | Phase 7B |
/// | `AnalyticsCacheService` | `AnalyticsCacheRepository` (Phase 3A) has no implementation | Phase 7B |
/// | `CalendarAggregator` | `CalendarRepository` (Phase 3A) has no implementation | Phase 7A |
///
/// Phase 3A declared seventeen repository contracts and Phases 3B–3D implemented fifteen. The two
/// outstanding are precisely the two these services need, which is not an oversight — the calendar
/// and analytics read models are 7A and 7B's work.
///
/// **Stubbing any of them would be worse than omitting them.** A port returning empty rows makes an
/// unfinished analytics screen look like a working one that found no data, and there is no way to
/// tell those apart from the UI. An absent provider is a compile error at the first use site, which
/// names the problem exactly where someone can act on it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/data/backup/backup_service.dart';
import 'package:alaya/data/backup/restore_service.dart';
import 'package:alaya/data/remote/currency_api_client.dart';
import 'package:alaya/data/repositories/mappers/rate_mappers.dart';
import 'package:alaya/data/security/app_lock_store.dart';
import 'package:alaya/data/security/pin_service.dart';
import 'package:alaya/data/security/recovery_code.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';
import 'package:alaya/domain/services/date_range_service.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/services/low_stock_suggestion_engine.dart';
import 'package:alaya/domain/services/purchase_fan_out_service.dart';
import 'package:alaya/domain/services/recurring_engine.dart';
import 'package:alaya/domain/services/stock_reconciler.dart';
import 'package:alaya/domain/services/unit_engine.dart';


// ── stateless engines ───────────────────────────────────────────────────────────────────

/// Unit conversion within a category.
final unitEngineProvider = Provider<UnitEngine>((ref) => const UnitEngine());

/// Date-range presets for filters and analytics.
final dateRangeServiceProvider = Provider<DateRangeService>((ref) => const DateRangeService());

/// Net worth and per-account balances.
final balanceServiceProvider = Provider<BalanceService>((ref) => const BalanceService());

/// FEFO consumption planning.
final inventoryConsumptionServiceProvider =
    Provider<InventoryConsumptionService>((ref) => const InventoryConsumptionService());

/// Cache-versus-ledger reconciliation and repair.
final stockReconcilerProvider = Provider<StockReconciler>((ref) => const StockReconciler());

/// Idempotent low-stock suggestion decisions.
final lowStockSuggestionEngineProvider =
    Provider<LowStockSuggestionEngine>((ref) => const LowStockSuggestionEngine());

/// Recurring schedule arithmetic — next due, materialisation, settlement.
final recurringEngineProvider = Provider<RecurringEngine>((ref) => const RecurringEngine());

// ── engines with dependencies ───────────────────────────────────────────────────────────

/// Turns a purchase line into a batch, an asset or a template.
final purchaseFanOutServiceProvider = Provider<PurchaseFanOutService>(
  (ref) => PurchaseFanOutService(normalizer: ref.watch(normalizerProvider)),
);

/// The exchange-rate HTTP client.
final currencyApiClientProvider = Provider<CurrencyApiClient>(
  (ref) => CurrencyApiClient(
    dio: ref.watch(dioProvider),
    logger: ref.watch(loggerProvider),
  ),
);

/// Rate lookup, cross-rate pivoting and the once-daily fetch.
///
/// Its four collaborators are closures over the DAO rather than the repository, which is what keeps
/// this out of a cycle: `CurrencyRepository` depends on this service, so a service depending on the
/// repository would not resolve.
final currencyRateServiceProvider = Provider<CurrencyRateService>((ref) {
  final dao = ref.watch(currencyDaoProvider);
  final client = ref.watch(currencyApiClientProvider);
  final clock = ref.watch(clockProvider);
  final uids = ref.watch(uidGeneratorProvider);
  return CurrencyRateService(
    loadTable: () async => RateMappers.tableFrom(
      rows: await dao.allRates(),
      decimalDigitsByCode: await dao.decimalDigitsByCode(),
    ),
    saveSnapshot: (snapshot) => dao.upsertRates(
      RateMappers.companionsFrom(snapshot: snapshot, uids: uids, clock: clock),
    ),
    fetchSnapshot: client.fetchLatest,
    // `newestRateDate` takes the base code; a snapshot is always USD-pivoted (ARCH_3 §1.2).
    newestCachedDate: () => dao.newestRateDate(RateTable.pivotCode),
    clock: clock,
  );
});

// ── security ────────────────────────────────────────────────────────────────────────────

/// Recovery-code generation and normalisation.
final recoveryCodeProvider = Provider<RecoveryCode>((ref) => RecoveryCode());

/// The app-lock secret store.
///
/// Reads and writes secure storage only, never the database — which is what makes a restore unable
/// to change the lock (ARCH_3 §2.1).
final appLockStoreProvider = Provider<AppLockStore>(
  (ref) => AppLockStore(storage: ref.watch(secureKeyValueStoreProvider)),
);

/// PIN verification, change, enable, disable and the failure throttle.
final pinServiceProvider = Provider<PinService>(
  (ref) => PinService(
    store: ref.watch(appLockStoreProvider),
    clock: ref.watch(clockProvider),
    recoveryCode: ref.watch(recoveryCodeProvider),
  ),
);

// ── backup ──────────────────────────────────────────────────────────────────────────────

/// Database export via `VACUUM INTO`.
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    database: ref.watch(databaseProvider),
    historyDao: ref.watch(backupHistoryDaoProvider),
    clock: ref.watch(clockProvider),
    uids: ref.watch(uidGeneratorProvider),
  ),
);

/// Merge and Replace restore.
final restoreServiceProvider = Provider<RestoreService>(
  (ref) => RestoreService(database: ref.watch(databaseProvider)),
);

/// The calendar aggregator, which applies ARCH_3 §6's per-type severity thresholds.
///
/// Stateless and `const`-constructible, but it takes a repository, so it gets a provider like every
/// other engine — no widget constructs it.
final calendarAggregatorProvider = Provider<CalendarAggregator>(
  (ref) => CalendarAggregator(ref.watch(calendarRepositoryProvider)),
);
```

### `lib/data/repositories/mappers/rate_mappers.dart`

```dart
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// Maps between `currency_rates` rows and the rate types `CurrencyRateService` works in.
///
/// Extracted in Phase 5, when wiring the provider graph revealed that **one direction existed only
/// as a private method inside `CurrencyRepositoryImpl` and the other did not exist at all.**
/// `CurrencyRateService` takes a `RateSnapshotSaver`, and until now nothing in the codebase could
/// satisfy it against the DAO — the port had no adapter, so `syncDailyRates` could not actually have
/// been called in production.
///
/// Both directions live here so the mapping has one definition. Writing the row-to-`UsdRate` map a
/// second time in the provider would have been the fourth instance of the duplication that Phase 4A
/// and 4B each had to undo.
abstract final class RateMappers {
  /// Builds an in-memory [RateTable] from cached rows.
  ///
  /// [decimalDigitsByCode] comes from `currencies`, not from the rate rows: minor-unit precision is a
  /// property of the currency, and reading it from a rate row would make a JPY amount's precision
  /// depend on whether a rate happened to be cached for it.
  static RateTable tableFrom({
    required Iterable<CurrencyRateRow> rows,
    required Map<String, int> decimalDigitsByCode,
  }) =>
      RateTable(
        rates: rows.map(usdRateFrom),
        decimalDigitsByCode: decimalDigitsByCode,
      );

  /// Maps one cached row to a [UsdRate].
  static UsdRate usdRateFrom(CurrencyRateRow row) => UsdRate(
        quoteCode: row.quoteCode,
        on: row.rateDateKey,
        rate: row.rate,
        rateRaw: row.rateRaw,
      );

  /// Maps a fetched snapshot to insertable rows.
  ///
  /// [uids] supplies a primary key per row even though `idx_rates_point` is what actually prevents
  /// duplicates — the table's own key is a UUID (ARCH_1 §4.4), and the upsert targets the index
  /// rather than the id, so a fresh id on a row that already exists is discarded by the conflict
  /// clause rather than inserted twice.
  ///
  /// `baseCode` is [RateTable.pivotCode] for every row, because a snapshot is USD-pivoted by
  /// definition (ARCH_3 §1.2) — storing each pair separately is exactly what the pivot avoids.
  static List<CurrencyRatesCompanion> companionsFrom({
    required RateSnapshot snapshot,
    required UidGenerator uids,
    required Clock clock,
  }) {
    final now = clock.nowUtcMillis();
    return snapshot.rates
        .map(
          (rate) => CurrencyRatesCompanion.insert(
            id: uids.generate(),
            baseCode: RateTable.pivotCode,
            quoteCode: rate.quoteCode,
            rateDateKey: rate.on,
            rate: rate.rate,
            // The provider's exact string, kept verbatim. ARCH_3 §1.3.7 wants the raw response value
            // so a rounding question later can be answered against what the provider actually sent.
            rateRaw: rate.rateRaw,
            source: snapshot.source,
            fetchedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        )
        .toList();
  }
}
```

### `lib/data/repositories/currency_repository_impl.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/currency_dao.dart';
import 'package:alaya/data/repositories/mappers/currency_mapper.dart';
import 'package:alaya/data/repositories/mappers/rate_mappers.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/repositories/currency_repository.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// `CurrencyRepository` backed by `CurrencyDao`.
///
/// A thin adapter over two owners. [convert] and [convertToHome] build a `RateTable` from the cached
/// rows and let it apply ARCH_3 §1.2's pivot and §1.3's lookup rule — no network access, and no
/// second copy of that arithmetic living here. [syncDailyRates] delegates to `CurrencyRateService`,
/// which owns the once-daily skip and the fetch ladder.
///
/// Phase 3B implemented both inline, because neither service existed yet. Phase 4A moved them, so
/// there is exactly one definition of each rule — the same reason `v_batch_stock_check` exists to
/// catch a second definition of a stock total.
final class CurrencyRepositoryImpl implements CurrencyRepository {
  /// Creates the repository over [dao], resolving the home currency through [settings].
  ///
  /// [rateService] is null until Phase 5 wires one; a null service makes [syncDailyRates] a
  /// documented no-op rather than a runtime error.
  const CurrencyRepositoryImpl(
    this._dao,
    this._clock,
    this._settings, {
    CurrencyRateService? rateService,
  }) : _rateService = rateService;

  final CurrencyDao _dao;
  final Clock _clock;
  final SettingsRepository _settings;
  final CurrencyRateService? _rateService;

  /// Used only if the seeded `homeCurrencyCode` setting is somehow absent — Phase 1C's seed data
  /// always writes it, so this is a defensive fallback, never the expected path.
  static const String _fallbackHomeCurrencyCode = 'INR';

  @override
  Stream<List<Currency>> watchEnabled() =>
      _dao.watchEnabled().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Currency>> watchAll() =>
      _dao.watchAll().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Currency?> byCode(String code) async => (await _dao.byCode(code))?.toEntity();

  @override
  Future<Map<String, int>> decimalDigitsByCode() => _dao.decimalDigitsByCode();

  @override
  Future<Result<void, Failure>> setEnabled({
    required String code,
    required bool isEnabled,
  }) async {
    await _dao.setEnabled(
      code: code,
      isEnabled: isEnabled,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<ConvertedMoney> convert({
    required Money amount,
    required String toCurrencyCode,
    required DateKey on,
  }) async {
    final table = await _rateTable();
    return table.convert(amount: amount, toCurrencyCode: toCurrencyCode, on: on);
  }

  @override
  Future<ConvertedMoney> convertToHome({
    required Money amount,
    required DateKey on,
  }) async {
    final homeCode = await _settings.readHomeCurrencyCode() ?? _fallbackHomeCurrencyCode;
    return convert(amount: amount, toCurrencyCode: homeCode, on: on);
  }

  @override
  Stream<int> watchUnconvertedCount() {
    // A real implementation needs to re-evaluate every active transaction's convertibility
    // whenever the rate cache changes, which is exactly the aggregation Phase 4A's
    // currency_rate_service is designed to own (it sits above both this repository and
    // TransactionRepository). Returning a constant stream here rather than guessing at a query
    // keeps this phase honest about what it does and does not implement.
    return Stream.value(0);
  }

  @override
  /// Delegates to `CurrencyRateService.syncDailyRates`, which is the only implementation.
  ///
  /// This method used to fetch directly. It was replaced because the service adds the two things
  /// that make ARCH_3 §1.2's "one request per day for the entire app, forever" true rather than
  /// aspirational — it skips the fetch when the cache already holds today's date, and refuses to
  /// overwrite a working cache with an empty snapshot. A caller wiring the old version to a
  /// foreground hook would have re-fetched on every resume.
  ///
  /// Still never throws: the service swallows every failure path (Law L11).
  Future<void> syncDailyRates() async {
    await _rateService?.syncDailyRates();
  }

  /// Builds the in-memory rate table `RateTable` needs, from the cached USD rows.
  ///
  /// The pivot and lookup rules live in `CurrencyRateService`'s `RateTable` (ARCH_3 §1.2, §1.3) —
  /// this method only supplies the data. Phase 3B originally hand-rolled the same cross-rating here;
  /// Phase 4A moved it, because two implementations of one rule drift apart and the schema's own
  /// reconciliation view is a standing reminder of what that costs.
  Future<RateTable> _rateTable() async {
    final rows = await _dao.allRates();
    // Delegates to RateMappers so this mapping has one definition — Phase 5 needed the same map in
    // the provider graph, and a second copy is how the two drift apart.
    return RateMappers.tableFrom(
      rows: rows,
      decimalDigitsByCode: await _dao.decimalDigitsByCode(),
    );
  }
}
```

### `lib/app/app.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/app_router.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/app/theme/palettes/presets.dart';

/// The active palette.
///
/// A provider rather than a bare constant so Settings and the Theme Lab can switch palettes at
/// runtime and the whole tree rebuilds. `AlayaPresets.activePreset` remains the compile-time default,
/// so the "one constant change" requirement (ARCH_3 §8.1) still holds for anyone who wants to change
/// the shipped look rather than offer a choice.
final activePaletteProvider = StateProvider<AlayaPalette>((ref) => AlayaPresets.activePreset);

/// The theme mode, following the system by default.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// The router, held in a provider so its lifetime matches the app's.
///
/// `GoRouter` owns navigation state, so rebuilding it would reset the stack. Constructing it inside
/// `build` is the standard way to lose a user's place on every theme change.
final routerProvider = Provider<GoRouter>((ref) => AppRouter.build());

/// The root widget.
class AlayaApp extends ConsumerWidget {
  /// Creates the app.
  const AlayaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(activePaletteProvider);
    final mode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      // Not a literal: the app's own name comes from the ARB like every other visible string.
      onGenerateTitle: (context) => AlayaStrings.of(context).appName,
      theme: AlayaTheme.light(palette),
      darkTheme: AlayaTheme.dark(palette),
      themeMode: mode,
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: const [
        AlayaStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AlayaStrings.supportedLocales,
      debugShowCheckedModeBanner: false,
    );
  }
}
```

### `lib/app/bootstrap.dart`

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/app.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/connection/open_database.dart';

/// Opens the database, builds the provider graph and runs the app.
///
/// The database is opened **here and only here**, through `openAlayaDatabase` — the single permitted
/// open path (Law L10). `databaseProvider` throws when un-overridden precisely so that a second open
/// site cannot appear quietly; the symptom of one would be a locked file rather than an error naming
/// the cause.
///
/// The database is plaintext (ARCH_1 §2.1). There is no key to derive, no passphrase to prompt for and
/// no unlock step before the connection opens.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = openAlayaDatabase();

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const AlayaApp(),
    ),
  );
}

/// Builds a `ProviderScope` over [database] for tests and the Theme Lab.
///
/// Exposed so a widget test can supply `AlayaDatabase(NativeDatabase.memory())` without reaching for
/// `bootstrap`, which would open a real file.
ProviderScope scopeFor({
  required AlayaDatabase database,
  required Widget child,
  List<Override> extraOverrides = const [],
}) =>
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database), ...extraOverrides],
      child: child,
    );
```

### `lib/main.dart`

```dart
import 'package:alaya/app/bootstrap.dart';

/// The Android entry point.
///
/// Deliberately empty of logic. Everything that could fail — opening the database, building the
/// provider graph — lives in `bootstrap` where it can be exercised by a test without a platform
/// binding hard-coded into `main`.
///
/// Returns the future rather than dropping it: a discarded future's error goes nowhere, so a failure
/// to open the database would present as a blank screen with nothing in the log naming the cause.
Future<void> main() => bootstrap();
```

### `lib/shared/widgets/scroll_safe_center.dart`

```dart
import 'package:flutter/material.dart';

/// Centres [child] in the available space, and scrolls instead of overflowing when there is not
/// enough of it (ARCH_3 §8.3).
///
/// The shape the full-height state widgets share, in one place. A bare `Center` hands its child
/// loose constraints and then lets it exceed them, which is why a state widget that looks right on a
/// phone in portrait paints an overflow stripe in a short list area, in landscape, or at a large
/// accessibility text scale. The `minHeight` is what keeps the content vertically centred when the
/// space *is* sufficient, so the common case is indistinguishable from a plain `Center`.
///
/// Falls back to a bare `Center` when the incoming height is unbounded, because a vertical
/// `SingleChildScrollView` given infinite height asserts rather than degrading.
class ScrollSafeCenter extends StatelessWidget {
  /// Centres and, when necessary, scrolls [child].
  const ScrollSafeCenter({required this.child, this.padding = EdgeInsets.zero, super.key});

  /// The content to centre.
  final Widget child;

  /// Padding around [child], inside the scrollable area so it scrolls with the content.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final content = Padding(padding: padding, child: Center(child: child));
          if (!constraints.hasBoundedHeight) return content;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: content,
            ),
          );
        },
      );
}
```


### `lib/shared/widgets/amount_text.dart`

```dart
import 'package:flutter/widgets.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/money_formatter.dart';

/// How large an amount renders.
enum AmountSize {
  /// The dashboard headline. One per screen.
  display,

  /// A card's primary figure.
  large,

  /// A ledger row. The default.
  medium,

  /// A converted or secondary figure.
  small,
}

/// Renders a [Money] with the app's colour convention and tabular figures.
///
/// **This is the widget the design is built around.** Three things happen here that make a column of
/// amounts readable:
///
/// 1. Tabular figures, from `AlayaTypography`. Digits share one advance width, so values align on the
///    decimal as they change instead of jittering.
/// 2. Colour from [AlayaSemanticColors.forAmount] and nowhere else, so the red/green rule has one
///    definition (ARCH_3 §8.1).
/// 3. **An explicit sign, always.** Colour alone would exclude the roughly eight percent of men with
///    a red-green deficiency; the palettes additionally keep income lighter than expense, but a glyph
///    is the only signal that survives both colour blindness and a greyscale screenshot.
class AmountText extends StatelessWidget {
  /// Creates an amount.
  const AmountText(
    this.amount, {
    this.size = AmountSize.medium,
    this.decimalDigits = 2,
    this.symbol,
    this.kind,
    this.showSign = true,
    this.muted = false,
    this.textAlign,
    super.key,
  });

  /// The amount.
  final Money amount;

  /// How large to render it.
  final AmountSize size;

  /// The currency's minor-unit precision.
  ///
  /// Defaults to 2. The real value lives on the `currencies` row, and a feature screen that has the
  /// currency to hand should pass it — JPY has 0 and rendering `¥1,200.00` is wrong.
  final int decimalDigits;

  /// The currency symbol.
  ///
  /// Defaults to the currency code, which is never wrong even when it is less pretty than `₹`. A
  /// hardcoded symbol would be wrong for every other currency the app supports.
  final String? symbol;

  /// The transaction kind, when known.
  ///
  /// Supplied only to colour a transfer neutrally: a transfer's leg is signed like any other, so
  /// without this it would render as income on the way in and expense on the way out — one movement
  /// of money looking like two different things.
  final TransactionKind? kind;

  /// Whether to render the sign.
  ///
  /// Defaults to true. Set false only where the direction is already unambiguous in the layout — a
  /// column headed "Spent", for instance.
  final bool showSign;

  /// Renders in the muted colour instead of the semantic one, for a disabled or historical row.
  final bool muted;

  /// How to align the text. Amounts in a column should be [TextAlign.right].
  final TextAlign? textAlign;

  static const MoneyFormatter _formatter = MoneyFormatter();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final color = muted
        ? semantic.muted
        : kind == null
            ? semantic.forAmount(amount)
            : semantic.forTransactionKind(kind!, amount);

    return Text(
      _formatter.format(
        amount,
        decimalDigits: decimalDigits,
        symbol: symbol ?? amount.currencyCode,
        showPlusSign: showSign && amount.isPositive,
      ),
      style: _styleFor(size).copyWith(color: color),
      textAlign: textAlign,
      maxLines: 1,
      // An amount is never truncated with an ellipsis: a partly shown number reads as a smaller
      // number. Scaling down is wrong for the same reason, so it clips and the caller gives it room.
      overflow: TextOverflow.clip,
      softWrap: false,
    );
  }

  TextStyle _styleFor(AmountSize size) => switch (size) {
        AmountSize.display => AlayaTypography.displayAmount,
        AmountSize.large => AlayaTypography.amountLarge,
        AmountSize.medium => AlayaTypography.amountMedium,
        AmountSize.small => AlayaTypography.amountSmall,
      };
}
```

### `lib/shared/widgets/qty_text.dart`

```dart
import 'package:flutter/widgets.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';

/// Renders a [Qty] through [QtyFormatter].
///
/// **Never `Qty.toString()`.** That is a debug representation — it prints milli-base units and the
/// category name, which would put `2000000 milli weight` in front of a user instead of `2 kg`. The
/// formatter is the only path to a displayable quantity.
class QtyText extends StatelessWidget {
  /// Creates a quantity.
  const QtyText(
    this.quantity, {
    this.style = UnitStyle.mixed,
    this.muted = false,
    this.textStyle,
    this.textAlign,
    super.key,
  });

  /// The quantity.
  final Qty quantity;

  /// Which unit presentation to use — [UnitStyle.mixed] decomposes `4 kg 450 g`.
  final UnitStyle style;

  /// Renders in the muted colour, for a depleted batch or a disabled row.
  final bool muted;

  /// Overrides the default [AlayaTypography.quantity].
  final TextStyle? textStyle;

  /// How to align the text.
  final TextAlign? textAlign;

  static const QtyFormatter _formatter = QtyFormatter();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Text(
      _formatter.format(quantity, style: style),
      style: (textStyle ?? AlayaTypography.quantity).copyWith(
        // Not `forAmount`: a quantity has no financial direction, so a negative one is a correction
        // rather than an expense and colouring it red would assert something false.
        color: muted ? semantic.muted : null,
      ),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
    );
  }
}
```

### `lib/shared/widgets/alaya_card.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_elevation.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';

/// The app's one card surface.
///
/// Takes a surface **tier** rather than an elevation number, because depth here is a palette step and
/// not a shadow — which is what keeps a card legible in dark mode, where a soft black shadow on a
/// near-black ground conveys nothing (see `AlayaElevation`).
class AlayaCard extends StatelessWidget {
  /// Creates a card.
  const AlayaCard({
    required this.child,
    this.tier = 1,
    this.padding = const EdgeInsets.all(AlayaSpacing.md),
    this.onTap,
    this.onLongPress,
    this.border = false,
    this.semanticsLabel,
    super.key,
  });

  /// The card's content.
  final Widget child;

  /// The surface tier: -1 sunken, 0 base, 1 raised (the default), 2 overlay.
  final int tier;

  /// Inner padding. Always a token value.
  final EdgeInsetsGeometry padding;

  /// Tap handler. When null the card is not interactive and takes no ink.
  final VoidCallback? onTap;

  /// Long-press handler, usually a context menu.
  final VoidCallback? onLongPress;

  /// Draws a hairline border, for a card on a same-coloured surface.
  final bool border;

  /// An accessibility label describing the card as a whole.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final isDark = theme.brightness == Brightness.dark;
    final interactive = onTap != null || onLongPress != null;
    final shape = RoundedRectangleBorder(
      borderRadius: AlayaRadii.borderMd,
      side: border ? BorderSide(color: theme.dividerColor) : BorderSide.none,
    );
    final content = Padding(padding: padding, child: child);

    // The surface colour and the border belong to the Material, not to a DecoratedBox wrapped
    // around it. A Material paints its ink splashes *beneath* its child, so an opaque decoration
    // between the two hides every ripple — the card looked correct and simply never responded to a
    // press. The DecoratedBox here carries the shadow and nothing else.
    final surface = Material(
      color: semantic.surfaceForTier(tier),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: interactive
          ? InkWell(onTap: onTap, onLongPress: onLongPress, child: content)
          : content,
    );

    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AlayaRadii.borderMd,
        // No shadow on a sunken tier: a well does not cast one.
        boxShadow: tier <= 0 ? AlayaElevation.none : AlayaElevation.raised(isDark: isDark),
      ),
      child: surface,
    );

    return semanticsLabel == null
        ? card
        : Semantics(label: semanticsLabel, container: true, child: card);
  }
}
```

### `lib/shared/widgets/tag_chip.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/tag.dart';

/// Renders one [Tag].
///
/// A tag may carry its own `colorArgb`, which is user data rather than a palette value — so it is
/// used for a small leading dot and never for the label or the fill. A user-chosen colour behind text
/// would break contrast unpredictably, and there is no way to guarantee a readable foreground for an
/// arbitrary background.
///
/// **A tappable chip reaches the 48px tap-target floor; a display-only one stays compact.** The chip
/// is the densest interactive element in the app and it is how tags get selected, so the hit area
/// cannot be the 21px the label alone implies. The coloured pill is also the ink surface rather than
/// sitting on top of one, because a Material paints its splashes beneath its child and an opaque fill
/// in between makes a press produce no feedback at all.
class TagChip extends StatelessWidget {
  /// Creates a chip for [tag].
  const TagChip({
    required this.tag,
    this.selected = false,
    this.onTap,
    this.onRemove,
    this.removeLabel,
    super.key,
  });

  /// The tag.
  final Tag tag;

  /// Whether the tag is currently applied.
  final bool selected;

  /// Tap handler, usually a toggle.
  final VoidCallback? onTap;

  /// Remove handler. When set, a trailing dismiss affordance appears.
  final VoidCallback? onRemove;

  /// Accessibility label for the dismiss affordance, already localised.
  ///
  /// Passed in rather than read from the ARB here, so this widget needs no `Localizations` ancestor
  /// and its goldens stay independent of `flutter gen-l10n` having run.
  final String? removeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final dotColor = tag.colorArgb == null ? null : Color(tag.colorArgb!);
    final background = selected ? theme.colorScheme.primary : semantic.surfaceSunken;
    final foreground = selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant;
    final shape = RoundedRectangleBorder(
      borderRadius: AlayaRadii.borderXs,
      side: selected ? BorderSide.none : BorderSide(color: theme.dividerColor),
    );

    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.xs,
        vertical: AlayaSpacing.xxs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            _Dot(color: dotColor),
            const SizedBox(width: AlayaSpacing.xxs),
          ],
          Flexible(
            child: Text(
              tag.name,
              style: AlayaTypography.overline.copyWith(color: foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: AlayaSpacing.xxs),
            Semantics(
              button: true,
              label: removeLabel,
              child: InkResponse(
                onTap: onRemove,
                radius: AlayaSpacing.md,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(AlayaSpacing.xxs),
                  child: Icon(Icons.close, size: AlayaIconSize.sm, color: foreground),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return Material(color: background, shape: shape, clipBehavior: Clip.antiAlias, child: body);
    }

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: background,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
            child: Center(widthFactor: 1, child: body),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: AlayaSpacing.xs,
        height: AlayaSpacing.xs,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
```

### `lib/shared/widgets/section_header.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// A header separating sections inside a scrolling screen.
///
/// Upper-cases its label. The transformation lives here rather than in the ARB, because the ARB holds
/// the sentence a translator writes and casing is presentation — a locale where upper case is wrong,
/// or a screen reader that spells out capitals, both need the original string intact.
class SectionHeader extends StatelessWidget {
  /// Creates a header.
  const SectionHeader({
    required this.label,
    this.trailing,
    this.padding = const EdgeInsets.only(
      left: AlayaSpacing.screenEdge,
      right: AlayaSpacing.screenEdge,
      top: AlayaSpacing.xl,
      bottom: AlayaSpacing.xs,
    ),
    super.key,
  });

  /// The label, already localised.
  final String label;

  /// An optional action on the right — "See all", a count, a filter.
  final Widget? trailing;

  /// Surrounding padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: AlayaTypography.sectionHeader.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              // The original casing is what assistive technology reads.
              semanticsLabel: label,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
```

### `lib/shared/widgets/empty_state.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/scroll_safe_center.dart';

/// What a screen shows when it has nothing to show.
///
/// **An empty screen is an invitation to act, not a report that there is no data.** So [body] names
/// the next step and [actionLabel] performs it — "Add your first expense and it will appear here",
/// not "No data available". The copy lives in the ARB; this widget only lays it out.
///
/// Scrolls rather than overflowing when the viewport is short, through [ScrollSafeCenter]. The
/// vertical margin is `xl` rather than `xxxl` because it is a *minimum*: the content is centred in
/// whatever space there is, so a larger figure buys nothing on a tall screen and costs 48px of
/// headroom on a short one.
class EmptyState extends StatelessWidget {
  /// Creates an empty state.
  const EmptyState({
    required this.title,
    required this.body,
    this.icon,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// A short line naming what is absent.
  final String title;

  /// One or two lines naming what to do about it.
  final String body;

  /// An optional icon above the title.
  final IconData? icon;

  /// The action's label. Ignored when [onAction] is null.
  final String? actionLabel;

  /// The action.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    return ScrollSafeCenter(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.xxl,
        vertical: AlayaSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AlayaIconSize.xl, color: semantic.muted),
            const SizedBox(height: AlayaSpacing.md),
          ],
          Text(
            title,
            style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            body,
            style: AlayaTypography.body.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: AlayaSpacing.xl),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
```

### `lib/shared/widgets/loading_state.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// A centred loading indicator with a label.
///
/// The label is not decoration: a bare spinner tells a screen reader nothing, and
/// `CircularProgressIndicator` has no implicit semantics of its own.
class LoadingState extends StatelessWidget {
  /// Creates a loading state.
  const LoadingState({required this.label, this.compact = false, super.key});

  /// What is loading, already localised.
  final String label;

  /// Renders inline rather than filling the viewport — for a list footer.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indicator = SizedBox(
      width: AlayaSpacing.xl,
      height: AlayaSpacing.xl,
      child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: label),
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(AlayaSpacing.md),
        child: Center(child: indicator),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          const SizedBox(height: AlayaSpacing.md),
          Text(
            label,
            style: AlayaTypography.caption.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
```



### `lib/shared/widgets/error_state.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/scroll_safe_center.dart';

/// What a screen shows when a read failed.
///
/// **Errors do not apologise and are never vague about what happened.** [title] names the failure and
/// [body] says what to do; neither says "sorry". A retry appears only when retrying could plausibly
/// work — offering it for a deleted record trains the user to ignore the button.
///
/// Scrolls rather than overflowing when the viewport is short, through [ScrollSafeCenter]. This one
/// is the tallest of the three states — icon, two text blocks and a 48px button — so it is the one
/// most likely to meet a viewport that cannot hold it.
class ErrorState extends StatelessWidget {
  /// Creates an error state.
  const ErrorState({
    required this.title,
    required this.body,
    this.retryLabel,
    this.onRetry,
    super.key,
  });

  /// What went wrong.
  final String title;

  /// What to do about it.
  final String body;

  /// The retry action's label. Ignored when [onRetry] is null.
  final String? retryLabel;

  /// The retry action.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    return ScrollSafeCenter(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.xxl,
        vertical: AlayaSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: AlayaIconSize.xl, color: semantic.danger),
          const SizedBox(height: AlayaSpacing.md),
          Text(
            title,
            style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            body,
            style: AlayaTypography.body.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null && retryLabel != null) ...[
            const SizedBox(height: AlayaSpacing.xl),
            OutlinedButton(onPressed: onRetry, child: Text(retryLabel!)),
          ],
        ],
      ),
    );
  }
}
```


### `lib/shared/widgets/confirm_sheet.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// A bottom sheet asking the user to confirm something.
///
/// A sheet rather than a dialog: it appears near the thumb, and on a one-handed phone a centred
/// dialog puts the destructive button where a stretch is needed.
///
/// Returns `true` only on explicit confirmation. Dismissing by tapping outside or swiping down
/// returns `false` rather than null, so a caller cannot treat "they walked away" as consent by
/// forgetting a null check.
class ConfirmSheet extends StatelessWidget {
  /// Creates a confirmation sheet. Prefer [show].
  const ConfirmSheet({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    this.destructive = false,
    super.key,
  });

  /// The question, phrased so that confirming is the obvious reading.
  final String title;

  /// What confirming will do, including anything reversible about it.
  final String body;

  /// The confirm button's label. Names the action — "Delete", not "OK".
  final String confirmLabel;

  /// The cancel button's label.
  final String cancelLabel;

  /// Renders the confirm button in the danger colour.
  final bool destructive;

  /// Shows the sheet and resolves to whether the user confirmed.
  ///
  /// Through [AlayaBottomSheet.show], so the content scrolls. There is no keyboard here, but a user
  /// at a large accessibility text scale can still make a title, a body and two buttons taller than
  /// the sheet — the same overflow with a different cause.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required String cancelLabel,
    bool destructive = false,
  }) async {
    final result = await AlayaBottomSheet.show<bool>(
      context: context,
      builder: (context) => ConfirmSheet(
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    // AlayaBottomSheet owns the safe area, the padding and the scroll view.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          body,
          style: AlayaTypography.body.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: semantic.danger,
                  foregroundColor: semantic.onStatus,
                )
              : null,
          child: Text(confirmLabel),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
      ],
    );
  }
}
```

### `lib/shared/widgets/shake_on_error.dart`

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_durations.dart';

/// Shakes its child horizontally when [trigger] changes.
///
/// Used on the PIN pad and on a rejected form. A shake communicates rejection without moving focus or
/// stealing the keyboard, which a snack bar or dialog both do — and on a PIN pad, keeping focus is the
/// difference between retrying immediately and re-tapping the field.
///
/// Keyed on an incrementing [trigger] rather than a bool, so two consecutive failures shake twice. A
/// bool that is already `true` produces no change and therefore no second shake, which reads as the
/// app having ignored the attempt.
///
/// Respects `MediaQuery.disableAnimations`: when a user has asked the platform to reduce motion, the
/// shake is skipped entirely rather than shortened.
class ShakeOnError extends StatefulWidget {
  /// Creates a shake wrapper.
  const ShakeOnError({
    required this.trigger,
    required this.child,
    this.distance = 10,
    super.key,
  });

  /// Increment this to shake.
  final int trigger;

  /// The widget to shake.
  final Widget child;

  /// Peak horizontal displacement in logical pixels.
  final double distance;

  @override
  State<ShakeOnError> createState() => _ShakeOnErrorState();
}

class _ShakeOnErrorState extends State<ShakeOnError> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    // Four legs plus a settle, each one shakeLeg long.
    duration: AlayaDurations.shakeLeg * 5,
    vsync: this,
  );

  @override
  void didUpdateWidget(ShakeOnError oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.trigger > 0) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // A decaying sine: four crossings, each smaller than the last, settling at zero.
          final t = _controller.value;
          final decay = 1 - t;
          final offset = widget.distance * decay * math.sin(t * 4 * math.pi);
          return Transform.translate(offset: Offset(offset, 0), child: child);
        },
        child: widget.child,
      );
}
```

### `lib/shared/widgets/alaya_expandable_fab.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One action inside an [AlayaExpandableFab].
class FabAction {
  /// Creates an action.
  const FabAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  /// The label, already localised. Always shown — an icon alone is a guess.
  final String label;

  /// The leading icon.
  final IconData icon;

  /// What tapping it does.
  final VoidCallback onPressed;
}

/// A FAB that unfolds into labelled actions.
///
/// Every action carries a visible label rather than an icon alone. A row of unlabelled icons is a
/// memory test, and the actions here — expense, income, item — are not distinguishable by any icon a
/// user has seen before.
///
/// Collapses on any action, on a tap anywhere outside itself, and on back.
///
/// ## Why the actions used to unfold on the wrong side of the screen
///
/// Two separate causes, and the first one is the one you see.
///
/// **`SizeTransition` left-aligns.** For a vertical axis it builds
/// `ClipRect(Align(alignment: AlignmentDirectional(-1.0, axisAlignment), heightFactor: t))` — and `-1.0`
/// on the horizontal axis means *left*. An `Align` given a `heightFactor` but no `widthFactor` also
/// **expands to fill the width it is offered**. So each min-width action row was being left-aligned inside
/// a box as wide as the whole FAB slot, while the button — not wrapped in a `SizeTransition` — obeyed
/// `CrossAxisAlignment.end` and stayed in the corner. Button right, actions hard left, which is exactly
/// what shipped. The rows fill the slot and right-align their own content now, so the framework's
/// alignment no longer has anything to decide.
///
/// **The slot's width also moved the anchor.** `FloatingActionButtonLocation.endFloat` answers
/// `x = screenWidth - slotWidth - margin` — it anchors by the slot's *own* width. Sizing to content made
/// that width 56 closed and full-screen open (the `Align` above), so `x` went to `-16` and the whole menu,
/// button included, shifted off the left edge. A slot of `screenWidth - 2 * md` makes it constant: `x = md`
/// open or closed, and off-screen becomes unreachable rather than unlikely.
///
/// The bound also gives the labels something to ellipsise against. `Flexible` was always there for that,
/// but under a full-screen loose constraint it had nothing to push back on and the row simply grew.
///
/// **Still no scrim (ARCH_3 §8.3).** A full-screen dim drawn from inside the FAB slot is either clipped
/// to the slot — invisible, and unable to receive the tap it exists for — or forces the slot wider and
/// reintroduces the anchor drift above. `TapRegion` supplies the dismissal without either failure, and
/// the rows carry opaque surfaces of their own so they stay legible over content.
class AlayaExpandableFab extends StatefulWidget {
  /// Creates an expandable FAB.
  const AlayaExpandableFab({
    required this.actions,
    required this.openLabel,
    required this.closeLabel,
    super.key,
  });

  /// The actions, in the order they unfold upward.
  final List<FabAction> actions;

  /// Accessibility label for the collapsed button.
  final String openLabel;

  /// Accessibility label for the expanded button.
  final String closeLabel;

  @override
  State<AlayaExpandableFab> createState() => _AlayaExpandableFabState();
}

class _AlayaExpandableFabState extends State<AlayaExpandableFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: AlayaDurations.slow,
    vsync: this,
  );
  bool _expanded = false;

  void _toggle() => _expanded ? _collapse() : _expand();

  void _expand() {
    setState(() => _expanded = true);
    _controller.forward();
  }

  void _collapse() {
    if (!_expanded) return;
    setState(() => _expanded = false);
    _controller.reverse();
  }

  void _run(FabAction action) {
    _collapse();
    action.onPressed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The margin `endFloat` will subtract, on both sides, so the anchor lands at exactly `md`.
    //
    // **Clamped, because Android's first frame reports a zero-width viewport.** The engine logs it twice
    // before the tree builds — `D/FlutterRenderer: Width is zero. 0,0` — and `0 - 32` is `-32`, which is
    // not a width: `SizedBox` asserted `BoxConstraints has a negative minimum width` and the app opened
    // to a red screen on every launch. The fixed extent is still what keeps the anchor still (Law U28);
    // it simply cannot go below nothing. The next frame carries the real width and the slot corrects
    // itself, which is why the fault never survived to a screenshot and never showed up in tests — the
    // widget harness always sets a real viewport before pumping.
    final slotWidth =
        (MediaQuery.sizeOf(context).width - AlayaSpacing.md * 2).clamp(0.0, double.infinity);

    return PopScope<Object?>(
      canPop: !_expanded,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _collapse();
      },
      child: TapRegion(
        onTapOutside: (_) => _collapse(),
        // Rebuilt per frame so the action rows leave the tree at the end of the reverse rather than the
        // start of it: a SizeTransition zeroes its child's height but not its width, and rows left
        // mounted while collapsed would keep taking hit tests over the content behind them.
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => SizedBox(
            width: slotWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!_controller.isDismissed)
                  for (final action in widget.actions)
                    SizeTransition(
                      sizeFactor: _controller,
                      axisAlignment: 1,
                      child: FadeTransition(
                        opacity: _controller,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            bottom: AlayaSpacing.sm,
                          ),
                          child: _ActionRow(
                            action: action,
                            onTap: () => _run(action),
                          ),
                        ),
                      ),
                    ),
                FloatingActionButton(
                  onPressed: _toggle,
                  tooltip: _expanded ? widget.closeLabel : widget.openLabel,
                  child: AnimatedRotation(
                    turns: _expanded ? 0.125 : 0,
                    duration: AlayaDurations.base,
                    child: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.onTap});

  final FabAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Fills the slot and right-aligns its content, rather than being a min-width row left-aligned by
    // `SizeTransition`. See the class doc: this is the line that puts the actions under the button.
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Flexible against the slot's bounded width: the label ellipsises at the screen edge instead of
        // widening the row past it.
        Flexible(
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            shape: const RoundedRectangleBorder(
              borderRadius: AlayaRadii.borderSm,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AlayaSpacing.minTapTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AlayaSpacing.sm,
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      action.label,
                      style: AlayaTypography.button.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AlayaSpacing.sm),
        SizedBox(
          width: AlayaSpacing.minTapTarget,
          height: AlayaSpacing.minTapTarget,
          child: Material(
            color: theme.colorScheme.secondary,
            shape: const RoundedRectangleBorder(
              borderRadius: AlayaRadii.borderSm,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Icon(
                action.icon,
                color: theme.colorScheme.onSecondary,
                size: AlayaIconSize.md,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

### `lib/shared/widgets/alaya_drawer.dart`

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// The app's navigation drawer.
///
/// Its destination list is `Routes.drawerDestinations`, so a route cannot exist in the router and be
/// missing from the drawer — the two read the same constant.
///
/// A drawer rather than a bottom bar because there are nine destinations. A bottom bar holds four
/// comfortably and five at a squeeze; beyond that the labels truncate and the targets shrink below the
/// tap-target floor.
class AlayaDrawer extends StatelessWidget {
  /// Creates the drawer.
  const AlayaDrawer({required this.currentLocation, super.key});

  /// The location currently shown, used to mark the selected row.
  final String currentLocation;

  /// The localised title for [location].
  ///
  /// Static so the app bar can title itself from the same mapping the drawer uses, rather than each
  /// screen repeating its own name and the two drifting apart.
  static String titleFor(BuildContext context, String location) {
    final strings = AlayaStrings.of(context);
    return switch (_rootOf(location)) {
      Routes.dashboard => strings.navDashboard,
      Routes.expenses => strings.navExpenses,
      Routes.inventory => strings.navInventory,
      Routes.shopping => strings.navShopping,
      Routes.recurring => strings.navRecurring,
      Routes.services => strings.navServices,
      Routes.calendar => strings.navCalendar,
      Routes.insights => strings.navInsights,
      Routes.settings => strings.navSettings,
      _ => strings.appName,
    };
  }

  /// The icon for [location].
  static IconData iconFor(String location) => switch (_rootOf(location)) {
        Routes.dashboard => Icons.dashboard_outlined,
        Routes.expenses => Icons.receipt_long_outlined,
        Routes.inventory => Icons.inventory_2_outlined,
        Routes.shopping => Icons.shopping_cart_outlined,
        Routes.recurring => Icons.autorenew_outlined,
        Routes.services => Icons.build_outlined,
        Routes.calendar => Icons.calendar_month_outlined,
        Routes.insights => Icons.insights_outlined,
        Routes.settings => Icons.settings_outlined,
        _ => Icons.circle_outlined,
      };

  /// The top-level route a possibly-nested [location] belongs to.
  ///
  /// `/expenses/abc123` selects Expenses. Matching the full location would leave nothing selected as
  /// soon as the user opened a detail screen.
  static String _rootOf(String location) {
    if (location == Routes.dashboard) return Routes.dashboard;
    for (final destination in Routes.drawerDestinations) {
      if (destination == Routes.dashboard) continue;
      if (location == destination || location.startsWith('$destination/')) return destination;
    }
    return location;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AlayaStrings.of(context);
    final selected = _rootOf(currentLocation);

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.md),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AlayaSpacing.md,
                AlayaSpacing.xs,
                AlayaSpacing.md,
                AlayaSpacing.lg,
              ),
              child: Text(
                strings.appName,
                style: AlayaTypography.screenTitle.copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
            for (final destination in Routes.drawerDestinations)
              _DrawerRow(
                destination: destination,
                selected: destination == selected,
                onTap: () {
                  Navigator.of(context).pop();
                  if (destination != selected) context.go(destination);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final String destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.xs,
        vertical: AlayaSpacing.xxs,
      ),
      child: ListTile(
        selected: selected,
        selectedColor: theme.colorScheme.secondary,
        selectedTileColor: theme.colorScheme.secondary.withValues(alpha: 0.10),
        leading: Icon(AlayaDrawer.iconFor(destination)),
        title: Text(AlayaDrawer.titleFor(context, destination)),
        onTap: onTap,
      ),
    );
  }
}
```

### `lib/shared/widgets/date_picker_field.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/core/time/date_key.dart';

/// Picks a civil date, working in [DateKey] throughout.
///
/// Converts to `DateTime` only to hand Material's picker something it understands, and converts
/// straight back. Holding a `DateTime` in the field's state would reintroduce the time-of-day and
/// timezone that `DateKey` exists to eliminate — and a date that shifts by a day near midnight is the
/// exact bug the type prevents.
class DatePickerField extends StatelessWidget {
  /// Creates a date field.
  const DatePickerField({
    required this.value,
    required this.onChanged,
    required this.formatted,
    this.label,
    this.hint,
    this.errorText,
    this.firstDate,
    this.lastDate,
    this.enabled = true,
    super.key,
  });

  /// The selected date, or null when unset.
  final DateKey? value;

  /// Called with the newly chosen date.
  final ValueChanged<DateKey> onChanged;

  /// Renders [value] for display.
  ///
  /// Injected because date formatting is locale-dependent and belongs with the caller's formatter,
  /// not duplicated inside a field widget.
  final String Function(DateKey) formatted;

  /// The field's label.
  final String? label;

  /// Placeholder shown when [value] is null.
  final String? hint;

  /// An error from the caller.
  final String? errorText;

  /// Earliest selectable date. Defaults to ten years back.
  final DateKey? firstDate;

  /// Latest selectable date. Defaults to five years forward.
  final DateKey? lastDate;

  /// Whether the field accepts input.
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = value?.toUtcMidnight() ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate?.toUtcMidnight() ?? DateTime(now.year - 10),
      lastDate: lastDate?.toUtcMidnight() ?? DateTime(now.year + 5),
    );
    if (picked != null) onChanged(DateKey.fromDateTime(picked));
  }

  @override
  Widget build(BuildContext context) {
    final current = value;
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      child: InputDecorator(
        // **The hint belongs to the decoration, not to the child.** With `isEmpty: true` the label sits
        // inside the field rather than floating, and a child `Text(hint)` then renders in exactly the
        // same place — so an unset date showed its label and its hint on top of each other. Handing the
        // hint to `InputDecoration` lets the decorator own that collision, which is the only thing that
        // knows where the label currently is.
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: errorText,
          suffixIcon: Icon(
            Icons.calendar_today_outlined,
            size: AlayaIconSize.md,
          ),
          enabled: enabled,
        ),
        isEmpty: current == null,
        child: current == null ? const SizedBox.shrink() : Text(formatted(current)),
      ),
    );
  }
}
```


### `lib/shared/widgets/amount_field.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/money_parser.dart';
import 'package:alaya/core/result/failure.dart';

/// A money input backed by [MoneyParser].
///
/// **It never rejects an intermediate typing state.** Typing `1`, then `1.`, then `1.2` passes through
/// three inputs of which only two parse — and the field rewrites the text in none of them. A field
/// that "corrects" as you type is unusable: deleting a digit to fix a typo momentarily produces
/// something unparseable, and a field that reformats at that instant moves the cursor and eats the
/// next keystroke.
///
/// So parsing drives [onChanged] and the error text only, never the controller's value.
/// [onChanged] receives null while the input is not yet a valid amount, which is the signal a Save
/// button should disable on — distinct from a zero amount, which is valid input the caller may still
/// choose to reject.
class AmountField extends StatefulWidget {
  /// Creates an amount field.
  const AmountField({
    required this.currencyCode,
    required this.onChanged,
    this.decimalDigits = 2,
    this.initialValue,
    this.label,
    this.hint,
    this.errorText,
    this.allowNegative = false,
    this.autofocus = false,
    this.controller,
    super.key,
  });

  /// The currency the typed number is denominated in.
  final String currencyCode;

  /// Called on every keystroke with the parsed amount, or null while it does not parse.
  final ValueChanged<Money?> onChanged;

  /// The currency's minor-unit precision. JPY is 0.
  final int decimalDigits;

  /// A starting amount, rendered as plain digits so it is immediately editable.
  final Money? initialValue;

  /// The field's label, already localised.
  final String? label;

  /// Placeholder text, already localised.
  final String? hint;

  /// An error from the caller — a business rule, not a parse failure.
  ///
  /// Takes precedence over the internal parse message, because "you have insufficient balance" is more
  /// useful than "enter an amount" when both are true.
  final String? errorText;

  /// Whether a leading minus is accepted.
  final bool allowNegative;

  /// Whether to focus on mount.
  final bool autofocus;

  /// An external controller, when the caller needs to clear or preset the text.
  final TextEditingController? controller;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  static const MoneyParser _parser = MoneyParser();

  late final TextEditingController _controller =
      widget.controller ?? TextEditingController(text: _initialText());
  ParseFailure? _failure;

  String _initialText() {
    final initial = widget.initialValue;
    if (initial == null || initial.isZero) return '';
    // Plain digits with a decimal point, not a formatted string: grouping separators in an editable
    // field fight the cursor, and the parser accepts either so there is nothing to gain.
    //
    // Split into a sign and a magnitude rather than dividing the signed minor value: `~/` truncates
    // toward zero, so -50 minor over a divisor of 100 gives a whole part of 0 and the minus sign
    // disappears — a -0.50 opening balance would load as 0.50.
    final divisor = _pow10(widget.decimalDigits);
    final sign = initial.isNegative ? '-' : '';
    final magnitude = initial.minor.abs();
    final whole = magnitude ~/ divisor;
    if (widget.decimalDigits == 0) return '$sign$whole';
    final fraction = (magnitude % divisor).toString().padLeft(widget.decimalDigits, '0');
    return '$sign$whole.$fraction';
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  void _handleChanged(String raw) {
    if (raw.trim().isEmpty) {
      setState(() => _failure = null);
      widget.onChanged(null);
      return;
    }
    final result = _parser.parse(
      raw,
      currencyCode: widget.currencyCode,
      decimalDigits: widget.decimalDigits,
      allowNegative: widget.allowNegative,
    );
    setState(() => _failure = result.failureOrNull);
    widget.onChanged(result.valueOrNull);
  }

  /// The parse failures worth showing mid-typing.
  ///
  /// A trailing decimal point is [ParseFailure.malformed] but is also what every user types on the way
  /// to entering paise — so it stays silent. Only failures that cannot become valid by typing more are
  /// surfaced.
  String? _parseMessage(BuildContext context) {
    final failure = _failure;
    if (failure == null) return null;
    final strings = AlayaStrings.of(context);
    return switch (failure) {
      ParseFailure.invalidCharacter => strings.errorAmountInvalidCharacter,
      ParseFailure.negativeNotAllowed => strings.errorAmountNegativeNotAllowed,
      ParseFailure.tooManyDecimalDigits => strings.errorAmountTooManyDecimals,
      ParseFailure.tooLarge => strings.errorAmountTooLarge,
      ParseFailure.empty || ParseFailure.malformed => null,
    };
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.right,
        style: AlayaTypography.amountLarge,
        inputFormatters: [
          // Filters at the keystroke rather than validating after: a letter in a numeric field is
          // never intentional, and blocking it is not the same as rejecting an incomplete number.
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-\u0020]')),
          LengthLimitingTextInputFormatter(24),
        ],
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: widget.errorText ?? _parseMessage(context),
          prefixText: widget.currencyCode,
        ),
        onChanged: _handleChanged,
      );
}
```


### `lib/core/quantity/qty_parser.dart`

```dart
import 'package:intl/intl.dart';

import '../result/failure.dart';
import '../result/result.dart';
import 'qty.dart';
import 'unit_category.dart';

/// Parses user-typed quantity text into [Qty] — Law L2's counterpart to `MoneyParser`.
///
/// **No `double` is involved at any point.** The typed decimal is converted to milli-base units by
/// exact integer arithmetic, which is what L2 requires and what makes the precision rule honest: a
/// value finer than the chosen unit can represent is **rejected**, never silently rounded. That is
/// the whole difference from a `double.parse` followed by `.round()`, which turned `0.501` of a
/// factor-1 unit into a whole one and reported success.
///
/// Never throws. Every outcome, including a string the user is still halfway through typing, comes
/// back as a [Result] so the field can decide what to surface.
final class QtyParser {
  /// Creates a parser. Stateless — safe to use as a `const` singleton.
  const QtyParser();

  static const int _maxInputLength = 18;

  /// The largest quantity this parser will produce, in milli-base units.
  ///
  /// 1e15 milli-base is a thousand tonnes of a weight item. The cap exists to keep
  /// `magnitude × factorToBaseMilli` inside a 64-bit int rather than to express a domain rule, and
  /// it is checked *before* the multiplication for exactly that reason.
  static const int maxMilliBase = 1000000000000000;

  /// Parses [input] as a quantity in the unit whose factor is [factorToBaseMilli].
  ///
  /// [factorToBaseMilli] comes from the `units` row, so `kg` is 1000000, `g` is 1000 and `pc` is
  /// 1000. [localeTag] decides which characters are the decimal point and the grouping separator.
  /// Negative input is rejected unless [allowNegative]: a movement is a positive quantity plus a
  /// `kind`, so a negative quantity is a bug at almost every call site.
  ///
  /// A fractional value is accepted whenever the unit can express it exactly — `0.5` of a `pc`
  /// is 500 milli-base, which ARCH_1 §4.2 requires — and returns
  /// [ParseFailure.tooManyDecimalDigits] when it cannot.
  Result<Qty, ParseFailure> parse(
    String input, {
    required UnitCategory category,
    required int factorToBaseMilli,
    String localeTag = 'en',
    bool allowNegative = false,
  }) {
    if (factorToBaseMilli <= 0) return const Result.failure(ParseFailure.malformed);

    var text = input.trim();
    if (text.isEmpty) return const Result.failure(ParseFailure.empty);
    if (text.length > _maxInputLength) return const Result.failure(ParseFailure.tooLarge);

    var sign = 1;
    if (text.startsWith('-')) {
      if (!allowNegative) return const Result.failure(ParseFailure.negativeNotAllowed);
      sign = -1;
      text = text.substring(1);
    } else if (text.startsWith('+')) {
      text = text.substring(1);
    }
    if (text.isEmpty) return const Result.failure(ParseFailure.malformed);

    final symbols = NumberFormat.decimalPattern(localeTag).symbols;
    final groupSeparator = symbols.GROUP_SEP;
    final decimalSeparator = symbols.DECIMAL_SEP;

    if (groupSeparator.isNotEmpty) {
      text = text.replaceAll(groupSeparator, '');
    }
    if (text.isEmpty) return const Result.failure(ParseFailure.malformed);

    final parts = decimalSeparator.isEmpty ? [text] : text.split(decimalSeparator);
    if (parts.length > 2) return const Result.failure(ParseFailure.malformed);

    final wholePart = parts[0];
    final fractionPart = parts.length == 2 ? parts[1] : '';

    if (wholePart.isEmpty && fractionPart.isEmpty) {
      return const Result.failure(ParseFailure.malformed);
    }
    if (!_isDigitsOnly(wholePart) || !_isDigitsOnly(fractionPart)) {
      return const Result.failure(ParseFailure.invalidCharacter);
    }

    final digits = '${wholePart.isEmpty ? '0' : wholePart}$fractionPart';
    if (digits.length > _maxInputLength) return const Result.failure(ParseFailure.tooLarge);

    final magnitude = int.parse(digits);
    if (magnitude > maxMilliBase ~/ factorToBaseMilli) {
      return const Result.failure(ParseFailure.tooLarge);
    }

    final scaled = magnitude * factorToBaseMilli;
    final divisor = _pow10(fractionPart.length);
    if (scaled % divisor != 0) {
      return const Result.failure(ParseFailure.tooManyDecimalDigits);
    }

    return Result.ok(Qty(sign * (scaled ~/ divisor), category));
  }

  /// Renders [qty] as plain editable digits in the unit whose factor is [factorToBaseMilli].
  ///
  /// The inverse of [parse] for a text field's initial value: plain digits with a decimal point and
  /// no grouping separators, because separators in an editable field fight the cursor.
  ///
  /// Integer arithmetic throughout, and it **truncates** at [maxFractionDigits] rather than
  /// rounding. Truncation matters because this text is what the user then edits: rounding up would
  /// let a save commit a larger quantity than the one stored, which nobody typed. A unit whose
  /// factor is not a power of ten (`dozen` is 12000) can hold values with no terminating decimal, so
  /// a bound is unavoidable.
  String format(Qty qty, {required int factorToBaseMilli, int maxFractionDigits = 6}) {
    if (factorToBaseMilli <= 0) return '';
    final negative = qty.isNegative;
    final magnitude = negative ? -qty.milliBase : qty.milliBase;
    final sign = negative ? '-' : '';
    final whole = magnitude ~/ factorToBaseMilli;
    final remainder = magnitude % factorToBaseMilli;
    if (remainder == 0) return '$sign$whole';

    final scaled = remainder * _pow10(maxFractionDigits) ~/ factorToBaseMilli;
    var fraction = scaled.toString().padLeft(maxFractionDigits, '0');
    while (fraction.endsWith('0')) {
      fraction = fraction.substring(0, fraction.length - 1);
    }
    return fraction.isEmpty ? '$sign$whole' : '$sign$whole.$fraction';
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  static bool _isDigitsOnly(String value) {
    for (final codeUnit in value.codeUnits) {
      if (codeUnit < 0x30 || codeUnit > 0x39) return false;
    }
    return true;
  }
}
```

### `lib/shared/widgets/qty_field.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_parser.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/shared/widgets/unit_picker.dart';

/// A quantity input paired with its unit.
///
/// The number and the unit are one control because a quantity without a unit is meaningless — `2` is
/// not a quantity until you know whether it is kilograms or pieces. Splitting them into two fields
/// lets a user submit a number with the wrong unit still selected.
///
/// Parses through [QtyParser], so no `double` touches a quantity (Law L2) and a value finer than the
/// selected unit can express is reported rather than rounded away.
///
/// Like `AmountField`, it never rewrites what is being typed: [onChanged] receives null while the
/// input is incomplete, and the text is left alone.
class QtyField extends StatefulWidget {
  /// Creates a quantity field.
  const QtyField({
    required this.category,
    required this.units,
    required this.selectedUnit,
    required this.onChanged,
    required this.onUnitChanged,
    this.initialValue,
    this.label,
    this.hint,
    this.errorText,
    this.unitLabel,
    super.key,
  });

  /// The category being measured. Constrains which units are offered (Law L8).
  final UnitCategory category;

  /// The units available in [category].
  final List<Unit> units;

  /// The unit currently chosen.
  final Unit? selectedUnit;

  /// Called with the parsed quantity, or null while the input is not yet a valid one.
  final ValueChanged<Qty?> onChanged;

  /// Called when the user picks a different unit.
  final ValueChanged<Unit> onUnitChanged;

  /// A starting quantity.
  final Qty? initialValue;

  /// The field's label.
  final String? label;

  /// Placeholder text.
  final String? hint;

  /// An error from the caller — a business rule, not a parse failure.
  final String? errorText;

  /// The unit picker's label.
  final String? unitLabel;

  @override
  State<QtyField> createState() => _QtyFieldState();
}

class _QtyFieldState extends State<QtyField> {
  static const QtyParser _parser = QtyParser();

  late final TextEditingController _controller = TextEditingController(text: _initialText());
  ParseFailure? _failure;

  String _initialText() {
    final initial = widget.initialValue;
    final unit = widget.selectedUnit;
    if (initial == null || initial.isZero || unit == null) return '';
    return _parser.format(initial, factorToBaseMilli: unit.factorToBaseMilli);
  }

  /// Re-derives the quantity from [raw].
  ///
  /// [unit] overrides `widget.selectedUnit`, and the unit picker must supply it. The parent has not
  /// rebuilt yet when the picker fires, so `widget.selectedUnit` still holds the *previous* unit —
  /// re-parsing against it stored `10 g` for a field displaying `10 kg`.
  void _handleChanged(String raw, {Unit? unit}) {
    unit ??= widget.selectedUnit;
    if (unit == null || raw.trim().isEmpty) {
      setState(() => _failure = null);
      widget.onChanged(null);
      return;
    }
    final result = _parser.parse(
      raw,
      category: widget.category,
      factorToBaseMilli: unit.factorToBaseMilli,
    );
    setState(() => _failure = result.failureOrNull);
    widget.onChanged(result.valueOrNull);
  }

  /// The parse failures worth showing mid-typing.
  ///
  /// A trailing decimal point is [ParseFailure.malformed] and is also what everyone types on the way
  /// to entering a fraction, so it stays silent — only failures that cannot become valid by typing
  /// more are surfaced. `tooManyDecimalDigits` is one of those and matters most: it is the case the
  /// old `double` path resolved by silently rounding.
  String? _parseMessage(BuildContext context) {
    final failure = _failure;
    if (failure == null) return null;
    final strings = AlayaStrings.of(context);
    return switch (failure) {
      ParseFailure.invalidCharacter => strings.errorQuantityInvalidCharacter,
      ParseFailure.negativeNotAllowed => strings.errorQuantityNegativeNotAllowed,
      ParseFailure.tooManyDecimalDigits => strings.errorQuantityTooPrecise,
      ParseFailure.tooLarge => strings.errorQuantityTooLarge,
      ParseFailure.empty || ParseFailure.malformed => null,
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              style: AlayaTypography.quantity,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(12),
              ],
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
                errorText: widget.errorText ?? _parseMessage(context),
              ),
              onChanged: _handleChanged,
            ),
          ),
          const SizedBox(width: AlayaSpacing.xs),
          Expanded(
            flex: 2,
            child: UnitPicker(
              category: widget.category,
              units: widget.units,
              selected: widget.selectedUnit,
              label: widget.unitLabel,
              onChanged: (unit) {
                widget.onUnitChanged(unit);
                // Re-derive with the new factor: the typed number means something different now,
                // and it may no longer be expressible — 0.5 is half a piece but not half a
                // milligram. The unit is passed explicitly because `widget.selectedUnit` is still the
                // old one until the parent rebuilds.
                _handleChanged(_controller.text, unit: unit);
              },
            ),
          ),
        ],
      );
}
```

### `lib/shared/widgets/unit_picker.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Picks a unit from within one category.
///
/// **Only units in [category] are offered, and that is a correctness constraint rather than a
/// convenience.** A `Qty` is a bare integer plus a category, so offering litres for a weight would
/// store a number that is reinterpreted on read — Law L8's cross-category prohibition, broken
/// silently rather than loudly.
class UnitPicker extends StatelessWidget {
  /// Creates a unit picker.
  const UnitPicker({
    required this.category,
    required this.units,
    required this.selected,
    required this.onChanged,
    this.label,
    this.enabled = true,
    super.key,
  });

  /// The category whose units may be chosen.
  final UnitCategory category;

  /// The available units. Any not in [category] are filtered out rather than trusted.
  final List<Unit> units;

  /// The current selection.
  final Unit? selected;

  /// Called with the newly chosen unit.
  final ValueChanged<Unit> onChanged;

  /// The field's label.
  final String? label;

  /// Whether the picker accepts input.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Filtered here rather than assumed of the caller: a picker that trusts its input to already be
    // category-correct is one bad call site away from breaking L8.
    final eligible = units.where((unit) => unit.category == category).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // Resolved to the instance in `eligible` that shares the selected code, not passed through. A
    // dropdown matches its value against its items by `==`, and `Unit`'s equality covers every
    // field — so a caller holding an instance read before the row was edited would match nothing
    // and the field would render blank with no error.
    Unit? current;
    for (final unit in eligible) {
      if (unit.code == selected?.code) {
        current = unit;
        break;
      }
    }

    return DropdownButtonFormField<Unit>(
      // Keyed on the selection so a change from the caller rebuilds the form field rather than
      // being absorbed: a FormField keeps its own copy of the value it was created with.
      key: ValueKey(current?.code),
      initialValue: current,
      // Without this the button lays its items out at their natural width against unbounded
      // constraints and then overflows the narrow column a QtyField gives it.
      isExpanded: true,
      decoration: InputDecoration(labelText: label, enabled: enabled),
      items: [
        for (final unit in eligible)
          DropdownMenuItem(
            value: unit,
            child: Text(unit.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: enabled ? (unit) => unit == null ? null : onChanged(unit) : null,
    );
  }
}
```

### `lib/shared/widgets/tag_picker.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Selects zero or more tags, filtered to those valid for a [scope].
///
/// A wrap of chips rather than a dropdown or a dialog. Tags are chosen several at a time and the
/// current selection needs to stay visible while choosing — a dropdown hides it at exactly the moment
/// the user is deciding whether they have enough.
///
/// Filters by [scope] because `Tag.allowedScopes` exists: a tag scoped to items should not be offerable
/// on a transaction, and letting it through would put a link row in a table whose scope forbids it.
class TagPicker extends StatelessWidget {
  /// Creates a tag picker.
  const TagPicker({
    required this.available,
    required this.selectedIds,
    required this.scope,
    required this.onToggle,
    this.label,
    this.emptyLabel,
    super.key,
  });

  /// Every tag the user has.
  final List<Tag> available;

  /// The ids currently applied.
  final Set<String> selectedIds;

  /// The scope being tagged.
  final TagScope scope;

  /// Called with a tag's id when the user toggles it.
  final ValueChanged<String> onToggle;

  /// The control's label.
  final String? label;

  /// Shown when no tag is valid for [scope].
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eligible = available
        .where((tag) => !tag.isDeleted && tag.allowedScopes.contains(scope))
        .toList()
      ..sort((a, b) {
        // Selected first, then the user's own order. Keeping selection at the top means a long tag
        // list never hides what is already applied.
        final aSelected = selectedIds.contains(a.id);
        final bSelected = selectedIds.contains(b.id);
        if (aSelected != bSelected) return aSelected ? -1 : 1;
        return a.sortOrder.compareTo(b.sortOrder);
      });

    if (eligible.isEmpty && emptyLabel != null) {
      return Text(
        emptyLabel!,
        style: AlayaTypography.caption.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AlayaTypography.label.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AlayaSpacing.xs),
        ],
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final tag in eligible)
              TagChip(
                tag: tag,
                selected: selectedIds.contains(tag.id),
                onTap: () => onToggle(tag.id),
              ),
          ],
        ),
      ],
    );
  }
}
```

### `lib/shared/widgets/account_picker.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/account.dart';

/// Picks an account.
///
/// Shows each account's currency code alongside its name, because a transfer between accounts in
/// different currencies is a different operation from one within a currency — and the user needs to
/// see that before choosing, not after the form changes shape.
///
/// Archived accounts are excluded unless one is already selected, in which case it stays visible so
/// an old transaction can still be edited without silently losing its account.
class AccountPicker extends StatelessWidget {
  /// Creates an account picker.
  const AccountPicker({
    required this.accounts,
    required this.selected,
    required this.onChanged,
    this.label,
    this.hint,
    this.errorText,
    this.excludeId,
    this.enabled = true,
    super.key,
  });

  /// The accounts to offer.
  final List<Account> accounts;

  /// The current selection.
  final Account? selected;

  /// Called with the newly chosen account.
  final ValueChanged<Account> onChanged;

  /// The field's label.
  final String? label;

  /// Placeholder when nothing is selected.
  final String? hint;

  /// An error from the caller.
  final String? errorText;

  /// An account to hide — the other side of a transfer, so it cannot be both source and
  /// destination.
  final String? excludeId;

  /// Whether the picker accepts input.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eligible = accounts
        .where((account) => account.id != excludeId)
        .where((account) => !account.isArchived || account.id == selected?.id)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // Resolved by id to the instance actually in the item list. `Account`'s equality compares every
    // field, including the balance-affecting ones, so passing the caller's possibly-staler instance
    // would match no item and blank the field.
    Account? current;
    for (final account in eligible) {
      if (account.id == selected?.id) {
        current = account;
        break;
      }
    }

    return DropdownButtonFormField<Account>(
      // See UnitPicker: a FormField does not reliably follow later changes to the value it was
      // created with, and a transfer form must be able to clear one side when the other changes.
      key: ValueKey(current?.id),
      initialValue: current,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        enabled: enabled,
      ),
      isExpanded: true,
      items: [
        for (final account in eligible)
          DropdownMenuItem(
            value: account,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  account.currencyCode,
                  style: AlayaTypography.caption.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: enabled ? (account) => account == null ? null : onChanged(account) : null,
    );
  }
}
```

### `lib/features/settings/presentation/theme_lab_screen.dart`

```dart
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/app.dart';
import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_elevation.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/loading_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Every token, component and semantic colour on one page, light and dark side by side (ARCH_3 §8.2).
///
/// **This is how palettes actually get chosen.** The alternative is navigating the real app hunting for
/// a screen that happens to use `warning`, discovering it only renders in one state, and guessing about
/// the rest. Everything enumerates from the token maps rather than a hand-written list, so a token
/// added later appears here without anyone remembering to add it.
///
/// Debug-only. In a release build it renders a single line saying so rather than the lab, which keeps
/// it out of the shipped UI without a conditional route that could be got wrong.
class ThemeLabScreen extends ConsumerWidget {
  /// Creates the lab.
  const ThemeLabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    if (!kDebugMode) {
      return Center(child: Text(strings.themeLabTitle));
    }

    final palette = ref.watch(activePaletteProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AlayaSpacing.screenEdge,
            AlayaSpacing.md,
            AlayaSpacing.screenEdge,
            0,
          ),
          child: Text(
            strings.themeLabSubtitle,
            style: AlayaTypography.body.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SectionHeader(label: strings.themeLabSectionPalettes),
        _PalettePicker(
          current: palette,
          onSelected: (next) => ref.read(activePaletteProvider.notifier).state = next,
        ),
        SectionHeader(label: strings.themeLabSectionSemantic),
        _SideBySide(palette: palette, builder: (context) => const _SemanticSwatches()),
        SectionHeader(label: strings.themeLabSectionSurfaces),
        _SideBySide(palette: palette, builder: (context) => const _SurfaceTiers()),
        SectionHeader(label: strings.themeLabSectionTypography),
        const _TypeScale(),
        SectionHeader(label: strings.themeLabSectionSpacing),
        const _SpacingScale(),
        SectionHeader(label: strings.themeLabSectionRadii),
        const _RadiiScale(),
        SectionHeader(label: strings.themeLabSectionElevation),
        _SideBySide(palette: palette, builder: (context) => const _ElevationScale()),
        SectionHeader(label: strings.themeLabSectionComponents),
        _SideBySide(palette: palette, builder: (context) => const _Components()),
      ],
    );
  }
}

/// Renders [builder] twice, in light and dark, so a palette is judged as a pair.
class _SideBySide extends StatelessWidget {
  const _SideBySide({required this.palette, required this.builder});

  final AlayaPalette palette;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Pane(
              label: strings.themeLabLight,
              theme: AlayaTheme.light(palette),
              child: builder(context),
            ),
          ),
          const SizedBox(width: AlayaSpacing.sm),
          Expanded(
            child: _Pane(
              label: strings.themeLabDark,
              theme: AlayaTheme.dark(palette),
              child: builder(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.label, required this.theme, required this.child});

  final String label;
  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AlayaTypography.overline),
          const SizedBox(height: AlayaSpacing.xxs),
          Theme(
            data: theme,
            child: Builder(
              builder: (context) => DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: AlayaRadii.borderSm,
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Padding(padding: const EdgeInsets.all(AlayaSpacing.sm), child: child),
              ),
            ),
          ),
        ],
      );
}

class _PalettePicker extends StatelessWidget {
  const _PalettePicker({required this.current, required this.onSelected});

  final AlayaPalette current;
  final ValueChanged<AlayaPalette> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final preset in AlayaPresets.all)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
                child: AlayaCard(
                  tier: preset.name == current.name ? 2 : 1,
                  border: preset.name == current.name,
                  onTap: () => onSelected(preset),
                  child: Row(
                    children: [
                      for (final swatch in [
                        preset.light.primary,
                        preset.light.accent,
                        preset.dark.surfaceBase,
                        preset.light.income,
                        preset.light.expense,
                      ]) ...[
                        _Swatch(color: swatch),
                        const SizedBox(width: AlayaSpacing.xxs),
                      ],
                      const SizedBox(width: AlayaSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(preset.name, style: AlayaTypography.cardTitle),
                            Text(preset.description, style: AlayaTypography.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: AlayaSpacing.lg,
        height: AlayaSpacing.lg,
        decoration: BoxDecoration(color: color, borderRadius: AlayaRadii.borderXs),
      );
}

class _SemanticSwatches extends StatelessWidget {
  const _SemanticSwatches();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in semantic.byName.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
            child: Row(
              children: [
                _Swatch(color: entry.value),
                const SizedBox(width: AlayaSpacing.xs),
                Expanded(child: Text(entry.key, style: AlayaTypography.caption)),
              ],
            ),
          ),
      ],
    );
  }
}

class _SurfaceTiers extends StatelessWidget {
  const _SurfaceTiers();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final tier in [-1, 0, 1, 2])
            Padding(
              padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
              child: AlayaCard(
                tier: tier,
                border: true,
                padding: const EdgeInsets.all(AlayaSpacing.xs),
                child: Text('tier $tier', style: AlayaTypography.caption),
              ),
            ),
        ],
      );
}

class _TypeScale extends StatelessWidget {
  const _TypeScale();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in AlayaTypography.all.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.key, style: AlayaTypography.overline),
                    // 1,234,567.89 rather than lorem: the figures are what the tabular treatment is
                    // for, and a pangram would hide the thing being judged.
                    Text('1,234,567.89 Alaya', style: entry.value),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _SpacingScale extends StatelessWidget {
  const _SpacingScale();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    const steps = {
      'xxs 4': AlayaSpacing.xxs,
      'xs 8': AlayaSpacing.xs,
      'sm 12': AlayaSpacing.sm,
      'md 16': AlayaSpacing.md,
      'lg 20': AlayaSpacing.lg,
      'xl 24': AlayaSpacing.xl,
      'xxl 32': AlayaSpacing.xxl,
      'xxxl 48': AlayaSpacing.xxxl,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in steps.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(entry.key, style: AlayaTypography.caption),
                  ),
                  Container(
                    width: entry.value,
                    height: AlayaSpacing.sm,
                    color: semantic.transfer,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RadiiScale extends StatelessWidget {
  const _RadiiScale();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    const steps = {
      'xs 4': AlayaRadii.xs,
      'sm 8': AlayaRadii.sm,
      'md 12': AlayaRadii.md,
      'lg 20': AlayaRadii.lg,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Row(
        children: [
          for (final entry in steps.entries)
            Padding(
              padding: const EdgeInsets.only(right: AlayaSpacing.xs),
              child: Column(
                children: [
                  Container(
                    width: AlayaSpacing.xxl,
                    height: AlayaSpacing.xxl,
                    decoration: BoxDecoration(
                      color: semantic.transfer,
                      borderRadius: BorderRadius.circular(entry.value),
                    ),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  Text(entry.key, style: AlayaTypography.overline),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ElevationScale extends StatelessWidget {
  const _ElevationScale();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadows = {
      'raised': AlayaElevation.raised(isDark: isDark),
      'floating': AlayaElevation.floating(isDark: isDark),
      'overlay': AlayaElevation.overlay(isDark: isDark),
    };
    return Column(
      children: [
        for (final entry in shadows.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.sm),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.semantic.surfaceRaised,
                borderRadius: AlayaRadii.borderMd,
                boxShadow: entry.value,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AlayaSpacing.xs),
                child: Text(entry.key, style: AlayaTypography.caption),
              ),
            ),
          ),
      ],
    );
  }
}

class _Components extends StatelessWidget {
  const _Components();

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final tag = Tag(
      id: 'demo',
      name: 'groceries',
      normalizedName: 'groceries',
      allowedScopes: const {TagScope.withdrawal},
      isSystem: false,
      sortOrder: 0,
      isDeleted: false,
      colorArgb: 0xFF2E7D5B,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AmountText(Money(-125050, 'INR'), size: AmountSize.large),
        const AmountText(Money(250000, 'INR')),
        const AmountText(
          Money(500000, 'INR'),
          kind: TransactionKind.transfer,
          size: AmountSize.small,
        ),
        const SizedBox(height: AlayaSpacing.xs),
        const QtyText(Qty(4450000, UnitCategory.weight)),
        const QtyText(Qty(3000, UnitCategory.count)),
        const SizedBox(height: AlayaSpacing.xs),
        Wrap(
          spacing: AlayaSpacing.xxs,
          children: [
            TagChip(tag: tag, onTap: () {}),
            TagChip(tag: tag, selected: true, onTap: () {}),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xs),
        FilledButton(onPressed: () {}, child: Text(strings.actionSave)),
        const SizedBox(height: AlayaSpacing.xxs),
        OutlinedButton(onPressed: () {}, child: Text(strings.actionCancel)),
        const SizedBox(height: AlayaSpacing.xxs),
        TextButton(onPressed: () {}, child: Text(strings.actionUndo)),
        const SizedBox(height: AlayaSpacing.xs),
        TextField(decoration: InputDecoration(labelText: strings.labelAmount)),
        const SizedBox(height: AlayaSpacing.xs),
        SizedBox(
          height: 150,
          child: EmptyState(
            title: strings.emptyTitleNoResults,
            body: strings.emptyBodyNoResults,
            icon: Icons.search_off_outlined,
          ),
        ),
        SizedBox(height: 120, child: LoadingState(label: strings.loadingLabel)),
        SizedBox(
          height: 170,
          child: ErrorState(
            title: strings.errorTitleGeneric,
            body: strings.errorBodyGeneric,
            retryLabel: strings.actionRetry,
            onRetry: () {},
          ),
        ),
        Text(
          '${AlayaDurations.fast.inMilliseconds} / ${AlayaDurations.base.inMilliseconds} / '
          '${AlayaDurations.slow.inMilliseconds} / ${AlayaDurations.page.inMilliseconds} ms',
          style: AlayaTypography.caption,
        ),
      ],
    );
  }
}
```

### `test/shared/golden/widget_golden_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Goldens for the five display widgets, in light and dark.
///
/// Each renders on the **active preset** rather than a fixture palette, so changing
/// `AlayaPresets.activePreset` fails these deliberately. That is the point: the goldens are how a
/// palette change is reviewed, and one that slipped through unnoticed would defeat having them.
///
/// None of these widgets reads a localised string — every label is a parameter — so the harness needs
/// no `Localizations` and the goldens stay independent of `flutter gen-l10n` having run.
void main() {
  /// Wraps [child] in the app's theme at a fixed size.
  ///
  /// `textScaler` is pinned to 1.0 through `MaterialApp.builder` rather than a `MediaQuery` above the
  /// app: `WidgetsApp` re-establishes `MediaQuery` from the view, so an outer one never reaches the
  /// widget and the pin would be decorative — a golden that silently moved with the host's
  /// accessibility settings would fail on one machine and pass on another.
  ///
  /// The canvas sizes are per-widget rather than shared. `EmptyState` is designed to fill a viewport,
  /// so it gets a taller one; it no longer overflows a short canvas either, but a golden that shows
  /// it mid-scroll is a golden of nothing useful.
  Widget harness(Widget child, {required bool dark, Size size = const Size(320, 140)}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark
          ? AlayaTheme.dark(AlayaPresets.activePreset)
          : AlayaTheme.light(AlayaPresets.activePreset),
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: inner!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Padding(
              padding: const EdgeInsets.all(AlayaSpacing.md),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> expectGolden(
    WidgetTester tester,
    Widget child,
    String name, {
    required bool dark,
    Size size = const Size(320, 140),
  }) async {
    await tester.pumpWidget(harness(child, dark: dark, size: size));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.${dark ? "dark" : "light"}.png'),
    );
  }

  final demoTag = Tag(
    id: 'tag-groceries',
    name: 'groceries',
    normalizedName: 'groceries',
    allowedScopes: const {TagScope.withdrawal},
    isSystem: false,
    sortOrder: 0,
    isDeleted: false,
    colorArgb: 0xFF2E7D5B,
  );

  group('AmountText', () {
    // One widget showing all four directions at once, so the colour convention is reviewable as a
    // set. Reviewing them in separate files makes an inverted income/expense pair easy to miss.
    final sample = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        AmountText(Money(250000, 'INR'), size: AmountSize.large),
        AmountText(Money(-125050, 'INR')),
        AmountText(Money(500000, 'INR'), kind: TransactionKind.transfer),
        AmountText(Money(0, 'INR'), size: AmountSize.small),
      ],
    );

    testWidgets('light', (tester) => expectGolden(tester, sample, 'amount_text', dark: false));
    testWidgets('dark', (tester) => expectGolden(tester, sample, 'amount_text', dark: true));
  });

  group('QtyText', () {
    const sample = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        QtyText(Qty(4450000, UnitCategory.weight)),
        QtyText(Qty(1500000, UnitCategory.volume)),
        QtyText(Qty(3000, UnitCategory.count)),
        QtyText(Qty(250000, UnitCategory.weight), muted: true),
      ],
    );

    testWidgets('light', (tester) => expectGolden(tester, sample, 'qty_text', dark: false));
    testWidgets('dark', (tester) => expectGolden(tester, sample, 'qty_text', dark: true));
  });

  group('TagChip', () {
    // A tappable chip is taller than a display-only one: it has to reach the 48px tap-target floor,
    // and the pair being visibly different is the point rather than an inconsistency.
    Widget sample() => Center(
          child: Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              TagChip(tag: demoTag),
              TagChip(tag: demoTag, selected: true, onTap: () {}),
              TagChip(tag: demoTag, onTap: () {}, onRemove: () {}, removeLabel: 'Remove tag'),
            ],
          ),
        );

    testWidgets(
      'light',
      (tester) => expectGolden(
        tester,
        sample(),
        'tag_chip',
        dark: false,
        size: const Size(320, 180),
      ),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(
        tester,
        sample(),
        'tag_chip',
        dark: true,
        size: const Size(320, 180),
      ),
    );
  });

  group('AlayaCard', () {
    Widget sample() => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AlayaCard(child: Text('tier 1 raised')),
            const SizedBox(height: AlayaSpacing.xs),
            const AlayaCard(tier: -1, child: Text('tier -1 sunken')),
            const SizedBox(height: AlayaSpacing.xs),
            AlayaCard(border: true, onTap: () {}, child: const Text('bordered, tappable')),
          ],
        );

    testWidgets(
      'light',
      (tester) => expectGolden(
        tester,
        sample(),
        'alaya_card',
        dark: false,
        size: const Size(320, 260),
      ),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(
        tester,
        sample(),
        'alaya_card',
        dark: true,
        size: const Size(320, 260),
      ),
    );
  });

  group('EmptyState', () {
    // Literal strings here rather than ARB lookups: the golden's job is the layout, and pulling in
    // Localizations would make it depend on gen-l10n having run.
    Widget sample() => EmptyState(
          title: 'No transactions yet',
          body: 'Add your first expense and it will appear here.',
          icon: Icons.receipt_long_outlined,
          actionLabel: 'Add expense',
          onAction: () {},
        );

    testWidgets(
      'light',
      (tester) => expectGolden(
        tester,
        sample(),
        'empty_state',
        dark: false,
        size: const Size(320, 400),
      ),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(
        tester,
        sample(),
        'empty_state',
        dark: true,
        size: const Size(320, 400),
      ),
    );
  });
}
```

### `test/core/qty_parser_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_parser.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';

void main() {
  const parser = QtyParser();

  // The seeded factors from ARCH_2 §14, so the cases are the ones the app actually meets.
  const kg = 1000000;
  const g = 1000;
  const mg = 1;
  const pc = 1000;
  const dozen = 12000;

  Qty? parsed(
    String input, {
    required int factor,
    UnitCategory category = UnitCategory.weight,
    bool allowNegative = false,
  }) =>
      parser
          .parse(
            input,
            category: category,
            factorToBaseMilli: factor,
            allowNegative: allowNegative,
          )
          .valueOrNull;

  ParseFailure? failed(
    String input, {
    required int factor,
    UnitCategory category = UnitCategory.weight,
    bool allowNegative = false,
  }) =>
      parser
          .parse(
            input,
            category: category,
            factorToBaseMilli: factor,
            allowNegative: allowNegative,
          )
          .failureOrNull;

  group('exact conversion', () {
    test('whole units scale by the factor', () {
      expect(parsed('2', factor: kg), const Qty(2000000, UnitCategory.weight));
      expect(parsed('250', factor: g), const Qty(250000, UnitCategory.weight));
      expect(parsed('5', factor: mg), const Qty(5, UnitCategory.weight));
    });

    test('fractions the unit can express are exact', () {
      expect(parsed('0.25', factor: kg), const Qty(250000, UnitCategory.weight));
      expect(parsed('1.5', factor: kg), const Qty(1500000, UnitCategory.weight));
      expect(parsed('0.5', factor: g), const Qty(500, UnitCategory.weight));
    });

    test('half a piece is legal — ARCH_1 §4.2 requires it', () {
      expect(
        parsed('0.5', factor: pc, category: UnitCategory.count),
        const Qty(500, UnitCategory.count),
      );
    });

    test('a factor that is not a power of ten still converts exactly', () {
      expect(
        parsed('0.5', factor: dozen, category: UnitCategory.count),
        const Qty(6000, UnitCategory.count),
      );
      expect(
        parsed('1', factor: dozen, category: UnitCategory.count),
        const Qty(12000, UnitCategory.count),
      );
    });

    test('the category is carried through, not inferred', () {
      expect(
        parsed('1', factor: g, category: UnitCategory.volume),
        const Qty(1000, UnitCategory.volume),
      );
    });
  });

  group('precision is refused, never rounded', () {
    // ARCH_4 R20: the double-backed field turned this into one whole unit and reported success.
    test('a value finer than the unit fails rather than rounding', () {
      expect(failed('0.501', factor: mg), ParseFailure.tooManyDecimalDigits);
      expect(failed('0.0001', factor: g), ParseFailure.tooManyDecimalDigits);
    });

    test('the boundary case is accepted', () {
      expect(parsed('0.001', factor: g), const Qty(1, UnitCategory.weight));
    });
  });

  group('rejections', () {
    test('empty and still-being-typed input', () {
      expect(failed('', factor: g), ParseFailure.empty);
      expect(failed('   ', factor: g), ParseFailure.empty);
      expect(failed('.', factor: g), ParseFailure.malformed);
      expect(failed('1.2.3', factor: g), ParseFailure.malformed);
    });

    test('non-digits', () {
      expect(failed('abc', factor: g), ParseFailure.invalidCharacter);
      expect(failed('1kg', factor: g), ParseFailure.invalidCharacter);
    });

    test('negatives need opting in', () {
      expect(failed('-1', factor: g), ParseFailure.negativeNotAllowed);
      expect(
        parsed('-1', factor: g, allowNegative: true),
        const Qty(-1000, UnitCategory.weight),
      );
    });

    test('a quantity too large to hold is caught before the multiplication', () {
      expect(failed('99999999999999', factor: kg), ParseFailure.tooLarge);
    });

    test('a nonsensical factor fails rather than dividing by zero', () {
      expect(failed('1', factor: 0), ParseFailure.malformed);
    });
  });

  test('grouping separators are stripped', () {
    expect(parsed('1,250', factor: g), const Qty(1250000, UnitCategory.weight));
  });

  group('format', () {
    test('renders in the unit with no trailing zeros', () {
      expect(
        parser.format(const Qty(4450000, UnitCategory.weight), factorToBaseMilli: kg),
        '4.45',
      );
      expect(
        parser.format(const Qty(4450000, UnitCategory.weight), factorToBaseMilli: g),
        '4450',
      );
      expect(
        parser.format(const Qty(500, UnitCategory.count), factorToBaseMilli: pc),
        '0.5',
      );
      expect(
        parser.format(const Qty(2000000, UnitCategory.weight), factorToBaseMilli: kg),
        '2',
      );
    });

    test('round trips through parse', () {
      const original = Qty(1234500, UnitCategory.weight);
      final text = parser.format(original, factorToBaseMilli: kg);
      expect(parsed(text, factor: kg), original);
    });

    test('negatives keep their sign', () {
      expect(
        parser.format(const Qty(-500, UnitCategory.weight), factorToBaseMilli: g),
        '-0.5',
      );
    });
  });
}
```


### `test/shared/layout_overflow_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/expense/presentation/sheets/delete_transaction_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/freeze_conversion_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_filter_sheet.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/shopping/presentation/sheets/entry_editor_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/generate_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/list_manager_sheet.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_expandable_fab.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/loading_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/service/presentation/sheets/dispose_sheet.dart';
import 'package:alaya/features/service/presentation/widgets/contact_action.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/shared/widgets/module_tile.dart';

import '../support/expense_harness.dart';
import '../support/fake_settings_repository.dart';
// Prefixed: `kToday` and `kNarrowPhone` are declared by every harness in this project, and this is
// the only file that imports two of them.
import '../support/calendar_harness.dart' as cal;

/// The only thing in this project that catches a layout overflow (ARCH_3 §8.3, ARCH_5 U2).
///
/// **Every sheet and every full-height state belongs here.** These defects are invisible to
/// `dart analyze`, to a file-by-file scan and to looking at the screen, because the missing
/// affordance is always an *ancestor*: the widget under review is locally correct and the parent
/// that should have given it room, or a way to scroll, is the one at fault.
///
/// They are also invisible to an ordinary widget test. A `RenderFlex` overflow reports through
/// `FlutterError.onError` rather than throwing at the site, so a test only fails on one if something
/// asks — which is exactly how an overflow hides in a suite that otherwise looks green. Every case
/// below asks, via `tester.takeException()`.
void main() {
  /// Roughly what a software keyboard takes from a phone in portrait.
  const double keyboardInset = 320;

  /// Roughly the room a list area has left on a small phone with a keyboard up.
  const Size squeezed = Size(320, 140);

  Widget host(
    Widget child, {
    double bottomInset = 0,
    double textScale = 1,
    List<Override> overrides = const [],
  }) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AlayaTheme.light(AlayaPresets.activePreset),
          // Every expense sheet reads `AlayaStrings.of(context)`, which unwraps a null without a
          // delegate installed. The Phase 5 groups pass literal strings, so this file went without
          // one until real screens arrived — and then failed as a null-check rather than as a
          // missing translation, which is why it read like five separate defects.
          localizationsDelegates: const [
            AlayaStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AlayaStrings.supportedLocales,
          // Inside the app rather than above it. `WidgetsApp` re-establishes `MediaQuery` from the
          // view, so an outer one is discarded before anything under test can read it — and a test
          // that believes it has simulated a keyboard when it has not is worse than no test.
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: EdgeInsets.only(bottom: bottomInset),
              textScaler: TextScaler.linear(textScale),
            ),
            child: inner!,
          ),
          home: Scaffold(body: child),
        ),
      );

  /// Content taller than the room a keyboard leaves, so the assertions are about the scaffold rather
  /// than about how long a particular string happens to be.
  Widget tallContent() => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [SizedBox(width: 200, height: 400)],
      );

  group('AlayaBottomSheet', () {
    testWidgets('scrolls rather than overflowing with a keyboard up', (tester) async {
      await tester.pumpWidget(
        host(AlayaBottomSheet(child: tallContent()), bottomInset: keyboardInset),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('still fits when there is no keyboard', (tester) async {
      await tester.pumpWidget(host(AlayaBottomSheet(child: tallContent())));
      expect(tester.takeException(), isNull);
    });

    // The bug, reproduced deliberately. `Padding(bottom: viewInsets)` around a `MainAxisSize.min`
    // Column is correct in each half and broken together: the padding shrinks the space and the
    // Column has no way to give up the room it already took. **If this ever stops overflowing, the
    // guard above has stopped testing anything** — and the reason AlayaBottomSheet exists has
    // quietly gone away.
    testWidgets('the un-scaffolded shape it replaces still overflows', (tester) async {
      await tester.pumpWidget(
        host(
          Padding(
            padding: const EdgeInsets.only(bottom: keyboardInset),
            child: tallContent(),
          ),
        ),
      );
      expect(tester.takeException(), isA<FlutterError>());
    });
  });

  group('ConfirmSheet', () {
    testWidgets('survives a keyboard and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => ConfirmSheet.show(
                context,
                title: 'Delete this transaction?',
                body: 'You can undo this for the next few seconds.',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                destructive: true,
              ),
              child: const Text('open'),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('AlayaFormScaffold', () {
    Widget form({bool submitting = false}) => AlayaFormScaffold(
          primaryLabel: 'Save expense',
          onPrimary: () {},
          secondaryLabel: 'Cancel',
          onSecondary: () {},
          isDirty: true,
          isSubmitting: submitting,
          discardTitle: 'Discard your changes?',
          discardBody: 'What you have typed will not be saved.',
          discardConfirmLabel: 'Discard',
          discardCancelLabel: 'Keep editing',
          child: const Column(
            children: [SizedBox(height: 300), TextField(), SizedBox(height: 300)],
          ),
        );

    testWidgets('body scrolls and the footer stays above the keyboard', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset));
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a doubled text scale with a keyboard up', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset, textScale: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the submitting footer does not grow the row past its box', (tester) async {
      await tester.pumpWidget(host(form(submitting: true), textScale: 2));
      expect(tester.takeException(), isNull);
    });
  });

  // Every sheet Phase 6A adds, at a keyboard inset and a doubled text scale — the two conditions
  // under which each of them is first used and least likely to have been looked at.
  group('expense sheets', () {
    final expenseOverrides = <Override>[
      homeCurrencyCodeProvider.overrideWith((ref) => 'INR'),
      homeDecimalDigitsProvider.overrideWith((ref) => 2),
      selectableAccountsProvider.overrideWith((ref) => Stream.value(const [kAccount])),
      quickAddTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      accountsByIdProvider
          .overrideWith((ref) => Stream.value(<String, Account>{kAccount.id: kAccount})),
      lineEditorItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      enabledCurrenciesProvider.overrideWith(
        (ref) => Stream.value(const [
          Currency(
            code: 'USD',
            name: 'US Dollar',
            symbol: r'$',
            decimalDigits: 2,
            isEnabled: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: expenseOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets('QuickAddSheet', (tester) => pumpSheet(tester, const QuickAddSheet()));

    testWidgets(
      'TransactionFilterSheet',
      (tester) => pumpSheet(tester, const TransactionFilterSheet()),
    );

    testWidgets(
      'LineItemEditor',
      (tester) => pumpSheet(
        tester,
        const LineItemEditor(
          currencyCode: 'INR',
          decimalDigits: 2,
          defaultDestination: TransactionLineDestination.inventory,
        ),
      ),
    );

    testWidgets(
      'DeleteTransactionSheet',
      (tester) => pumpSheet(tester, const DeleteTransactionSheet()),
    );

    testWidgets(
      'FreezeConversionSheet',
      (tester) => pumpSheet(tester, const FreezeConversionSheet(excludeCode: 'INR')),
    );
  });

  // Phase 6B's sheet, at a keyboard inset and a doubled text scale — the two conditions under
  // which it is first used and least likely to have been looked at (U2).
  group('inventory sheets', () {
    final inventoryOverrides = <Override>[
      consumeFefoProvider('item-1').overrideWith((ref) => Stream.value(const <Batch>[])),
      unitsInCategoryProvider(UnitCategory.weight).overrideWith(
        (ref) => Stream.value(const [
          Unit(
            code: 'kg',
            category: UnitCategory.weight,
            factorToBaseMilli: 1000000,
            displayName: 'kilogram',
            isSystem: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    testWidgets('ConsumeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: ConsumeSheet(
              itemId: 'item-1',
              unitCode: 'kg',
              category: UnitCategory.weight,
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: inventoryOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6C's three sheets, at a keyboard inset and a doubled text scale — the two conditions under
  // which each is first used and least likely to have been looked at (U2).
  group('shopping sheets', () {
    final shoppingOverrides = <Override>[
      entryItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      entryTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      entryCurrencyProvider.overrideWith((ref) async => 'INR'),
      entryDecimalDigitsProvider.overrideWith((ref) async => 2),
      entriesProvider('list-1').overrideWith((ref) => Stream.value(const <ShoppingEntry>[])),
      shoppingItemsByIdProvider.overrideWith((ref) => Stream.value(const <String, Item>{})),
      allListsProvider.overrideWith((ref) => Stream.value(const <ShoppingList>[])),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: shoppingOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets(
      'EntryEditorSheet',
      (tester) => pumpSheet(tester, const EntryEditorSheet(listId: 'list-1')),
    );

    testWidgets(
      'GenerateSheet',
      (tester) => pumpSheet(tester, const GenerateSheet(listId: 'list-1')),
    );

    testWidgets(
      'ListManagerSheet',
      (tester) => pumpSheet(tester, const ListManagerSheet()),
    );
  });

  // Phase 6D's pay sheet, at a keyboard inset and a doubled text scale — an amount field, a date
  // field, an account dropdown and a two-line note, all growing at once.
  group('recurring sheets', () {
    final recurringOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      payAccountsProvider.overrideWith((ref) => Stream.value(const <Account>[])),
      payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
    ];

    testWidgets('PaySheet', (tester) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(
            child: PaySheet(
              occurrenceId: 'occ-1',
              template: RecurringTemplate(
                id: 'tpl-1',
                name: 'A rent template with a name long enough to wrap at a doubled scale',
                normalizedName: 'rent',
                kind: RecurringKind.rent,
                direction: RecurringDirection.outflow,
                defaultAmount: const Money(120000, 'INR'),
                intervalUnit: RecurringIntervalUnit.month,
                intervalCount: 1,
                startDateKey: const DateKey(20260131),
                nextDueDateKey: const DateKey(20260831),
                isPaused: false,
                autoRemind: true,
                remindDaysBefore: 3,
                anchorDayOfMonth: 31,
              ),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: recurringOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6D adds, with a clamp note on every row.
  group('FrequencyPreview at a doubled text scale', () {
    testWidgets('three dates, two of them clamped', (tester) async {
      await tester.pumpWidget(
        host(
          const FrequencyPreview(
            dates: [
              PreviewedDate(dateKey: DateKey(20260131)),
              PreviewedDate(dateKey: DateKey(20260228), clamped: true),
              PreviewedDate(dateKey: DateKey(20260331)),
            ],
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6E's dispose sheet: seven choice chips, a date field, an optional amount and a note, all
  // growing at once under a keyboard inset.
  group('service sheets', () {
    final serviceOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('DisposeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: DisposeSheet(assetId: 'asset-1', currencyCode: 'INR'),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: serviceOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The contact block: a name, a number and a call button, none of them flexible.
  group('ContactAction at a doubled text scale', () {
    testWidgets('a long name beside a long number', (tester) async {
      await tester.pumpWidget(
        host(
          const ContactAction(
            phone: '+91 98765 43210',
            name: 'A service centre with a name long enough to wrap',
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6F's dashboard sections. Each is a card whose figures, chips and labels all grow at once, and
  // the funds header carries the only display-sized amount in the app.
  group('dashboard sections', () {
    final dashOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      // InsightCard's notifier restores its side from `app_settings` on the first frame, which
      // resolves `databaseProvider` unless this is here — the failure reads as a database bug in a
      // test that never mentions one (ARCH_6 P6).
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      dashboardCurrencyProvider.overrideWith((ref) async => 'INR'),
      dashboardDigitsProvider.overrideWith((ref) async => 2),
      totalFundsProvider.overrideWith(
        (ref) async => const NetWorth(
          total: Money(98765432, 'INR'),
          unconvertedCount: 3,
          isApproximate: true,
        ),
      ),
      upcomingProvider.overrideWith((ref) async => const <UpcomingEntry>[]),
    ];

    testWidgets('FundsHeader with both chips at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const FundsHeader(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('InsightCard with its switch at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const InsightCard(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6F adds. Two lines of text and a glyph inside a fixed aspect ratio is
  // exactly the shape that overflows when the text doubles and the box does not.
  group('ModuleTile at a doubled text scale', () {
    testWidgets('a long label beside a long count', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 160,
            height: 108,
            child: ModuleTile(
              label: 'Recurring commitments',
              icon: Icons.event_repeat,
              detail: '17 need attention before the end of the month',
              onTap: () {},
            ),
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 7A. Both shapes here are the ones that have already cost this project rounds: a sheet whose
  // content outgrows the viewport, and a grid of text cells whose row height does not move with the text.
  // Zero width, which is not a hypothetical: Android reports it on the first frame of every launch
  // ("D/FlutterRenderer: Width is zero. 0,0") and the FAB's slot subtracted padding from it, producing a
  // negative width and a red screen on startup. Every widget harness sets a real viewport before pumping,
  // which is exactly why nothing here caught it — so the degenerate viewport is now stated outright.
  group('degenerate viewports', () {
    testWidgets('the expandable FAB survives a zero-width first frame', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size.zero),
            child: Scaffold(
              floatingActionButton: AlayaExpandableFab(
                openLabel: 'Add',
                closeLabel: 'Close',
                actions: [
                  FabAction(label: 'One', icon: Icons.add, onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('calendar', () {
    List<Override> calOverrides({List<CalendarEvent> events = const []}) =>
        cal.calendarOverrides(cal.FakeCalendarRepository(events: events));

    final busyDay = <CalendarEvent>[
      cal.event(title: 'A payee with a name long enough to wrap at a doubled scale', amountMinor: 98765432),
      cal.event(
        type: CalendarEventType.serviceDue,
        refType: 'asset',
        refId: 'as-1',
        title: 'The boiler in the upstairs cupboard',
        baseSeverity: CalendarSeverity.warning,
      ),
      cal.event(
        type: CalendarEventType.batchExpiry,
        refType: 'inventoryBatch',
        refId: 'ba-1',
        title: 'Yoghurt, the large tub',
        baseSeverity: CalendarSeverity.warning,
      ),
    ];

    testWidgets('DaySheet with three grouped entries at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('DaySheet with a keyboard up as well', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // U26: `TableCalendar` takes a fixed `rowHeight`, so the grid computes one from the text scaler. If
    // that computation is ever replaced by a constant, this is the test that says so.
    testWidgets('the month grid at a doubled scale on the narrowest phone', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the month grid at a tripled scale, which is past what U15 asks for',
        (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 3, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // The range header prints two formatted dates and a dash, which is the longest single string this
    // screen can produce — and it appears only in a mode the other cases never enter.
    testWidgets('the range header at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('22'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // The screen's own composition, which the shared full-height group cannot reach: six measured rows
    // plus a header are taller than a squeezed list area on their own, so the grid and the state beneath
    // it have to share a scroll rather than compete for a fixed box.
    for (final scale in [1.0, 2.0]) {
      testWidgets('the whole screen in a squeezed viewport at ${scale}x', (tester) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: scale,
            overrides: calOverrides(events: busyDay),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // Each of the three states in turn, in the same squeezed box. Loading and error sit in the sliver
    // that fills the remainder, and that remainder is negative here.
    testWidgets('loading, empty and error all survive the squeezed box', (tester) async {
      for (final repo in [
        cal.FakeCalendarRepository(pending: true),
        cal.FakeCalendarRepository(),
        cal.FakeCalendarRepository(error: 'view unavailable'),
      ]) {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: 2,
            overrides: cal.calendarOverrides(repo),
          ),
        );
        // `pump`, not `pumpAndSettle`: the loading case holds a `CircularProgressIndicator`, which
        // animates forever, so `pumpAndSettle` times out rather than settling. Two frames is enough to
        // resolve the completed futures in the other two cases.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('full-height states in a squeezed viewport', () {
    Widget inSqueezedBox(Widget child) => host(
          Center(
            child: SizedBox(width: squeezed.width, height: squeezed.height, child: child),
          ),
        );

    testWidgets('EmptyState with an icon, body and action', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          EmptyState(
            title: 'No transactions yet',
            body: 'Add your first expense and it will appear here.',
            icon: Icons.receipt_long_outlined,
            actionLabel: 'Add expense',
            onAction: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ErrorState with a retry — the tallest of the three', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          ErrorState(
            title: 'That did not work',
            body: 'Something went wrong on our side. Try again.',
            retryLabel: 'Try again',
            onRetry: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoadingState', (tester) async {
      await tester.pumpWidget(inSqueezedBox(const LoadingState(label: 'Loading')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('AlayaListSkeleton clips rather than overflowing', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(const AlayaListSkeleton(label: 'Loading transactions')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmptyState at a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: EmptyState(
                title: 'No transactions yet',
                body: 'Add your first expense and it will appear here.',
                icon: Icons.receipt_long_outlined,
                actionLabel: 'Add expense',
                onAction: () {},
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    // The states are also the shape the Theme Lab renders inside a half-width pane, which is where
    // the 150px `SizedBox` around an EmptyState used to overflow by roughly 58px.
    testWidgets('EmptyState in a half-width pane', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          const SizedBox(
            width: 134,
            child: EmptyState(title: 'No matches', body: 'Try a shorter search.'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6A's line-items page: a full-height screen whose summary row, list rows and footer all
  // grow under text scale at once. Squeezed and doubled, which is the pair U21 exists for.
  group('the line items page', () {
    final editorOverrides = <Override>[
      transactionEditorProvider.overrideWith(
        () => _FixedEditor(
          AsyncValue.data(
            TransactionEditorState(
              currencyCode: 'INR',
              dateKey: const DateKey(20260801),
              amount: const Money(20000, 'INR'),
              lines: [
                TransactionLine(
                  id: 'l1',
                  transactionId: '',
                  lineNo: 1,
                  description: 'A description long enough to need two lines at a doubled scale',
                  destination: TransactionLineDestination.inventory,
                  quantity: const Qty(500000, UnitCategory.weight),
                  lineAmount: const Money(4000, 'INR'),
                ),
              ],
            ),
          ),
        ),
      ),
      homeDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('populated at 320dp and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(const LineItemsScreen(), textScale: 2, overrides: editorOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('kit rows at a doubled text scale', () {
    testWidgets('KeyValueRow wraps a long value instead of overflowing', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            child: KeyValueRow(
              label: 'Payment method',
              value: 'Bank transfer from HDFC Savings ending 4417',
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('FilterChipBar wraps rather than clipping a row of chips', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: FilterChipBar(
              clearAllLabel: 'Clear all',
              onClearAll: () {},
              filters: [
                ActiveFilter(label: 'Account: HDFC Savings', onRemove: () {}),
                ActiveFilter(label: 'Tag: Groceries', onRemove: () {}),
                ActiveFilter(label: 'Jan 2026 – Aug 2026', onRemove: () {}),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('StatusChip ellipsises a long label in a narrow box', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 96,
            child: StatusChip(label: 'Needs details', tone: StatusTone.info),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// A transaction editor reporting a fixed state, so a layout can be pumped without a database.
class _FixedEditor extends TransactionEditorNotifier {
  _FixedEditor(this._value);

  final AsyncValue<TransactionEditorState> _value;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _value;
}
```

### `test/shared/golden/widget_golden_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Goldens for the five display widgets, in light and dark.
///
/// Each renders on the **active preset** rather than a fixture palette, so changing
/// `AlayaPresets.activePreset` fails these deliberately. That is the point: the goldens are how a
/// palette change is reviewed, and one that slipped through unnoticed would defeat having them.
///
/// None of these widgets reads a localised string — every label is a parameter — so the harness needs
/// no `Localizations` and the goldens stay independent of `flutter gen-l10n` having run.
void main() {
  /// Wraps [child] in the app's theme at a fixed size.
  ///
  /// `textScaler` is pinned to 1.0 through `MaterialApp.builder` rather than a `MediaQuery` above the
  /// app: `WidgetsApp` re-establishes `MediaQuery` from the view, so an outer one never reaches the
  /// widget and the pin would be decorative — a golden that silently moved with the host's
  /// accessibility settings would fail on one machine and pass on another.
  ///
  /// The canvas sizes are per-widget rather than shared. `EmptyState` is designed to fill a viewport,
  /// so it gets a taller one; it no longer overflows a short canvas either, but a golden that shows
  /// it mid-scroll is a golden of nothing useful.
  Widget harness(Widget child, {required bool dark, Size size = const Size(320, 140)}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark
          ? AlayaTheme.dark(AlayaPresets.activePreset)
          : AlayaTheme.light(AlayaPresets.activePreset),
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: inner!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Padding(
              padding: const EdgeInsets.all(AlayaSpacing.md),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> expectGolden(
    WidgetTester tester,
    Widget child,
    String name, {
    required bool dark,
    Size size = const Size(320, 140),
  }) async {
    await tester.pumpWidget(harness(child, dark: dark, size: size));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.${dark ? "dark" : "light"}.png'),
    );
  }

  final demoTag = Tag(
    id: 'tag-groceries',
    name: 'groceries',
    normalizedName: 'groceries',
    allowedScopes: const {TagScope.withdrawal},
    isSystem: false,
    sortOrder: 0,
    isDeleted: false,
    colorArgb: 0xFF2E7D5B,
  );

  group('AmountText', () {
    // One widget showing all four directions at once, so the colour convention is reviewable as a
    // set. Reviewing them in separate files makes an inverted income/expense pair easy to miss.
    final sample = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        AmountText(Money(250000, 'INR'), size: AmountSize.large),
        AmountText(Money(-125050, 'INR')),
        AmountText(Money(500000, 'INR'), kind: TransactionKind.transfer),
        AmountText(Money(0, 'INR'), size: AmountSize.small),
      ],
    );

    testWidgets('light', (tester) => expectGolden(tester, sample, 'amount_text', dark: false));
    testWidgets('dark', (tester) => expectGolden(tester, sample, 'amount_text', dark: true));
  });

  group('QtyText', () {
    const sample = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        QtyText(Qty(4450000, UnitCategory.weight)),
        QtyText(Qty(1500000, UnitCategory.volume)),
        QtyText(Qty(3000, UnitCategory.count)),
        QtyText(Qty(250000, UnitCategory.weight), muted: true),
      ],
    );

    testWidgets('light', (tester) => expectGolden(tester, sample, 'qty_text', dark: false));
    testWidgets('dark', (tester) => expectGolden(tester, sample, 'qty_text', dark: true));
  });

  group('TagChip', () {
    // A tappable chip is taller than a display-only one: it has to reach the 48px tap-target floor,
    // and the pair being visibly different is the point rather than an inconsistency.
    Widget sample() => Center(
          child: Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              TagChip(tag: demoTag),
              TagChip(tag: demoTag, selected: true, onTap: () {}),
              TagChip(tag: demoTag, onTap: () {}, onRemove: () {}, removeLabel: 'Remove tag'),
            ],
          ),
        );

    testWidgets(
      'light',
      (tester) => expectGolden(
        tester,
        sample(),
        'tag_chip',
        dark: false,
        size: const Size(320, 180),
      ),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(
        tester,
        sample(),
        'tag_chip',
        dark: true,
        size: const Size(320, 180),
      ),
    );
  });

  group('AlayaCard', () {
    Widget sample() => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AlayaCard(child: Text('tier 1 raised')),
            const SizedBox(height: AlayaSpacing.xs),
            const AlayaCard(tier: -1, child: Text('tier -1 sunken')),
            const SizedBox(height: AlayaSpacing.xs),
            AlayaCard(border: true, onTap: () {}, child: const Text('bordered, tappable')),
          ],
        );

    testWidgets(
      'light',
      (tester) => expectGolden(
        tester,
        sample(),
        'alaya_card',
        dark: false,
        size: const Size(320, 260),
      ),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(
        tester,
        sample(),
        'alaya_card',
        dark: true,
        size: const Size(320, 260),
      ),
    );
  });

  group('EmptyState', () {
    // Literal strings here rather than ARB lookups: the golden's job is the layout, and pulling in
    // Localizations would make it depend on gen-l10n having run.
    Widget sample() => EmptyState(
          title: 'No transactions yet',
          body: 'Add your first expense and it will appear here.',
          icon: Icons.receipt_long_outlined,
          actionLabel: 'Add expense',
          onAction: () {},
        );

    testWidgets(
      'light',
      (tester) => expectGolden(
        tester,
        sample(),
        'empty_state',
        dark: false,
        size: const Size(320, 400),
      ),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(
        tester,
        sample(),
        'empty_state',
        dark: true,
        size: const Size(320, 400),
      ),
    );
  });
}
```
