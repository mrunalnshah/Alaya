# ARCH_6 — CODE INDEX & DEFECT LEDGER

**Version 3.0 · regenerated after Phase 6E · binding from Phase 6F**

## 1. What this document is for

The project is **342 files and roughly 52,000 lines** of Dart across twenty phase documents. A phase
that needs to know whether `AssetRepository` has a `watchDueForService` should not read any of them.
**§6 is the generated signature index for every public API — 208 files, complete parameter lists, no
bodies.** Read it instead of the phase documents.

Three rules make it trustworthy:

1. **It is generated, not written.** Regenerate at the end of every phase from the working tree. A
   hand-maintained index drifts within one phase and is then worse than nothing.
2. **Signatures only.** For *how* something behaves, read that one file. For *whether it exists and
   what it takes*, this is enough.
3. **§3 is the defect ledger.** It records the shape of each mistake, not the incident, because eight
   of the ten patterns below recurred at least twice.

**One caveat that matters.** This index is generated from the tree reconstructed out of the phase
documents plus every fix through 6D. It has never been compiled. If `flutter analyze` disagrees with
anything here, the analyser is right — that is ARCH_4 R22, and this document is not an exception to it.

## 2. Doc/code drift — the problem, and how it was closed

Version 1.0 of this document recorded a live hazard: **fix packs had been applied to the working tree
but never folded back into the phase documents.** Regenerating from a document would have reintroduced
a layout crash. Two further regressions came from the same cause — a router constant renamed during
transcription, and an entire feature (Phase 6C's draft channel) silently reverted by patching from a
stale local copy.

That is now closed, and the closure has a mechanism rather than a promise:

- **One canonical tree.** Every fix is applied to it; every phase document is *regenerated from* it.
  No document is hand-edited.
- **Shared files are byte-identical.** Sixteen files appear in more than one document — `app_en.arb`,
  `routes.dart`, `app_router.dart`, `layout_overflow_test.dart`, and the Phase 6A editor files amended
  by 6B, 6C and 6D. A cross-document diff is part of every regeneration and currently reports zero
  mismatches.
- **The check is mechanical.** §5 gives it. A promise to remember would not have survived one phase.

**Standing rule:** a fix is not delivered until the owning phase document is regenerated from the tree
that contains it (PROMPTS §5).

## 3. Defect ledger — the shapes, not the incidents

Every entry recurred. The count is the point: writing a rule down did not stop the pattern; a
mechanical sweep did. ARCH_4 §4 R30–R38 carry these as risk rows with the full narrative — this table
is the working index.

| # | Shape | Times | Detection that works |
|---|---|---|---|
| **P1** | A non-flexible trailing element starves its `Expanded` sibling. Worst case: a nudge banner **1,084px tall** with the ledger beneath it measuring `Size(320.0, 0.0)` — completely invisible | **9** | The overflow is reported against the ancestor `Column`, never the grandchild. `tester.getSize` on each child found it in one run after the stack trace failed three times. Now ARCH_5 **U21** |
| **P2** | `NeverScrollableScrollPhysics` without `shrinkWrap` — a viewport inside a scrollable gets unbounded height and throws on the first frame | 1 | The two travel together; one without the other is the defect |
| **P3** | A getter reading `this` cannot validate a change not yet applied. `setKind` asked the *old* kind for valid subtypes → red screen | 1 | Validation across a transition takes the new value as a parameter |
| **P4** | U13 admits no row-count exemption. A repository stream mapped into a `Column`; and `AlayaTimeline` taking an eagerly-built `List` where rendering was virtualised but construction was not | 2 | `SliverList.builder`, and a widget that takes `itemBuilder` rather than a list |
| **P5** | Riverpod shapes: a fused `Notifier` that does not compile; `overrideWith` on a `NotifierProvider` *instance* (works on `FutureProvider`/`StreamProvider` instances); two `pumpWidget` calls in one test **silently false-passing**; a varying override count throwing outright | 4 | One scope per state, fixed-length override lists, and a grep for `pumpX` count per test |
| **P6** | Harness gaps that read as product bugs — no `localizationsDelegates`, so five sheets failed with a null check; assertions on widgets below a lazy fold | 2 | Any harness pumping a `features/` widget installs the four delegates and scrolls first |
| **P7** | Reinventing a contract that exists. `ItemRepository.setFavorite`, `watchDue()`, `findByIdentity`, `RecurringEngine` — the last of which I nearly duplicated as a new domain service | 4 | Grep §6 before writing a repository or engine call. This is the concrete reason this document exists |
| **P8** | A generic error message is a bug you cannot find. Six rounds recovering text the code already had in `Failure.message`. **Worse second-order failure:** two attempts to surface it produced nothing, because the state field holding it was not preserved in `copyWith` | 2 | ARCH_5 **U9**; and any nullable state field takes `?? this.x` plus a named clear flag |
| **P9** | Two reachable write paths for one action produce two records. `payOccurrence` owns a write end-to-end; the bill form reached it *and* left the editor's `create` reachable — ₹600 and ₹700 both saved | 1 | ARCH_5 **U22**: exactly one surface per repository write |
| **P11** | A presence check run against raw source matches its own documentation. Twice it failed loudly and was corrected; the third time a consolidation audit reported *"all 24 markers present"* because the marker appeared in a **doc comment** while the line had been dropped — certifying the regression as fixed | **3** | Strip comments and string literals before asserting that code exists (ARCH_4 R39) |
| **P12** | Overlapping fix folders give several candidate bases for one file, and a rebuild from the phase document silently reverts fixes. Two in Phase 6E: one caught by the compiler, one by nothing | **2** | One fix folder per phase, consolidated after every round (R43) |
| **P13** | A callback that outlives its screen must not touch that context. `context.push` inside a `SnackBarAction` after a pop throws *"Looking up a deactivated widget's ancestor is unsafe"* | 1 | Capture the router before the pop; the instance survives it (R40) |
| **P14** | A value derived from a text field seeded with `?? ` locks in the first keystroke's answer — typing `30` set three days | 1 | Recompute per keystroke with an override flag (R41, ARCH_5 U24) |
| **P10** | A truncated `grep -A n` window silently shortens an enum, and the switch compiles until it does not. `RecurringKind` read as four values, then five; it has six | **2** | `sed -n '/^enum X/,/^}/p'` and assert the case count equals the value count |

### 3.1 What actually reduced the rate

Not the rules. Every one of P1, P5, P7 and P10 recurred *after* being written down. What worked, in
order of value:

1. **A sweep for siblings after every fix.** Four rounds of the 6C pass were spent fixing one
   occurrence at a time of a pattern already in this ledger.
2. **Reading a declaration whole rather than through a grep window.**
3. **Asserting on presence, not on counts.** Several of my own verification scripts failed on
   arithmetic (`copyWith` mentions a field three times on one line) while the code was correct.
4. **Verifying a diagnostic renders, not merely compiles.** P8's second-order failure is the case.

## 4. Law and UI-Law audit — all 321 files

Mechanically checked, not sampled. Re-run at every phase boundary; §5 has the script.

| Law | Result |
|---|---|
| L1 money is int minor | Clean, under the amended wording — `Money.convert` is the one sanctioned `double` boundary and returns `int` |
| L2 quantity is int milli | Clean — `QtyParser` is the only parse path |
| L3 no stored totals | Clean — `inventory_batches.remainingQuantityMilli` is the labelled exception, and 6B renders it read-only in the batch editor for exactly that reason |
| L4 epoch millis / DateKey | Clean — no `DateTimeColumn` in `lib/data` |
| L5 UUIDv7 keys | Clean — zero `autoIncrement` |
| L6 soft delete, append-only movements | Clean — reversal is the only correction path; `replaceLines` soft-deletes, which is why a reused line id collided |
| L7 repositories read views | Clean |
| L8 unitCategory immutable | Clean — read-only on edit, and the notifier refuses the change as well as hiding the control |
| L9 original currency immutable | Clean — freezing writes a separate snapshot, never a rewrite |
| L10 one database open | Clean — `open_database.dart` alone |
| L12 domain imports nothing downward | Clean — zero `drift`, `flutter` or `data/` imports under `lib/domain` |
| L13 enum names are schema | Clean |
| L14 two-table writes in one transaction | Clean at the repository layer. The purchase fan-out remains the documented deviation (ARCH_4 §5.1 items 17 and 21), now with the caller's retry obligation satisfied |
| U4 no AsyncValue escape hatches | Clean — zero `.requireValue`, zero `.value!` |
| U5 no string literals | **One accepted exception**, below |
| U6 no raw colours, sizes or text styles | Clean — zero `Color(0x…)`, zero `fontSize:`, zero `textTheme.` in a feature |
| U7 value types through their widgets | Clean |
| U13 every list virtualised | Clean |
| U21 rows stack above 1.5× | Six files guard it explicitly; nine occurrences fixed |
| U22 one write path per action | Clean |
| Forbidden packages | Clean |

### 4.1 The one accepted U5 exception

`lib/features/settings/presentation/theme_lab_screen.dart` contains two literals — `'tier $tier'` and
a specimen number string. **Accepted, not overlooked.** The theme lab is a palette workbench for
developing the design system; its labels name internal concepts (surface tiers, type specimens) that
have no user-facing meaning and no translation. Localising them would add ARB keys nobody reads.

If the theme lab is ever promoted to a user-facing appearance screen, this exception lapses and the
strings move to the ARB with it.

## 5. Regenerating this document, and the checks that go with it

`tools/audit.sh` — run at every phase boundary, before the phase is called done.

```bash
#!/usr/bin/env bash
# Alaya phase audit. Run from the repo root.
set -u
note() { printf '  %-34s %s\n' "$1" "$2"; }
viol() { note "$1" "VIOLATED"; shift; "$@" | head -3 | sed 's/^/       /'; }

echo "── contract integrity ──"
comm -23 <(grep -rhoP 'Routes\.\K\w+' lib test | sort -u) \
         <(grep -oP 'static (?:const )?(?:String|List<String>) \K\w+' lib/app/router/routes.dart | sort -u) \
  | sed 's/^/  MISSING Routes./'
comm -23 <(grep -rhoP 'strings\.\K\w+' lib | sort -u) \
         <(python3 -c "import json;print('\n'.join(k for k in json.load(open('lib/app/l10n/app_en.arb')) if not k.startswith('@')))" | sort -u) \
  | sed 's/^/  MISSING ARB key: /'

echo "── the Laws ──"
grep -rlq "package:drift\|package:flutter/\|alaya/data/" lib/domain/ && note "L12 domain isolation" VIOLATED || note "L12 domain isolation" ok
grep -riq autoincrement lib/ && note "L5 no autoincrement" VIOLATED || note "L5 no autoincrement" ok
grep -rq "dateTime()\|DateTimeColumn" lib/data && note "L4 no DateTime column" VIOLATED || note "L4 no DateTime column" ok
[ "$(grep -rl 'driftDatabase(\|NativeDatabase(' lib/ | wc -l)" = 1 ] && note "L10 one open path" ok || note "L10 one open path" CHECK

echo "── the UI Laws ──"
grep -rnP "Text\(\s*'[^\$'][^']{2,}'" lib/features lib/shared | grep -v theme_lab_screen && note "U5 no literals" VIOLATED || note "U5 no literals" ok
grep -rq "Color(0x\|fontSize: [0-9]\|textTheme\." lib/features lib/shared && note "U6 no raw values" VIOLATED || note "U6 no raw values" ok
grep -rq "\.requireValue\|\.value!" lib/features lib/shared && note "U4 no escape hatch" VIOLATED || note "U4 no escape hatch" ok
grep -rlqP 'Column\(\s*children: \[\s*for \(final \w+ in (rows|items|movements)\)' lib/features && note "U13 no Column-over-stream" VIOLATED || note "U13 no Column-over-stream" ok

echo "── P1/U21: rows that must stack at 2x ──"
grep -rln "AmountText(\|QtyText(" lib/features lib/shared | while read -r f; do
  grep -q "Expanded(" "$f" && ! grep -q "textScalerOf" "$f" && echo "  review: $f"
done

echo "── P10: every switched enum is exhaustive ──"
python3 tools/check_enums.py

echo "── P5: one pump per widget test ──"
for f in $(grep -rl "testWidgets(" test/); do
  python3 - "$f" <<'EOF'
import re,sys
s=open(sys.argv[1]).read()
for m in re.finditer(r"testWidgets\('([^']+)'.*?\n  \}\);", s, re.S):
    n=len(re.findall(r'await pump\w+\(\s*tester', m.group(0)))
    if n>1: print(f'  {sys.argv[1]}: "{m.group(1)}" pumps {n} times')
EOF
done

echo "── P6: harnesses without localisations ──"
for f in $(grep -rl "MaterialApp(" test/); do
  grep -q "AlayaStrings.delegate" "$f" || echo "  $f"
done

echo "── §9.1 per screen ──"
python3 tools/check_screens.py

echo "── doc/code drift ──"
python3 tools/regen_phase_docs.py --check
```

`tools/gen_code_index.py` regenerates §6 — signatures only: type and enum headers, constructors,
public fields, getters and methods, with complete parameter lists and no bodies.

**Four traps that cost real time when that generator was written, recorded so it is not rewritten
badly:** a length cap silently drops the longest signatures, which are the ones that matter most; a
`{`-stripper meant for class bodies destroys inline record typedefs unless anchored to end-of-line;
`abstract interface class` does not match a pattern written for `abstract final class`; and a parameter
list spanning lines must be joined on paren balance *before* the body is cut, or every named-parameter
method loses its parameters. All four produced a silently wrong index that looked fine.

## 6. The signature index

Generated from the canonical tree. **208 files, zero truncated signatures**, including the whole of
`features/service`, which version 2.0 omitted because the generator's section list had never been
extended for it — a reminder that a generated document is only as complete as its section table.

Grep this section rather than the phase documents.


### Core — money, quantity, time, ids, text

**`lib/core/ids/uid.dart`**

```dart
abstract interface class UidGenerator
String generate()
final class Uuid7Generator implements UidGenerator
const Uuid7Generator()
final class SequentialUidGenerator implements UidGenerator
SequentialUidGenerator({this.prefix = 'test'})
final String prefix
```

**`lib/core/money/money.dart`**

```dart
final class Money implements Comparable<Money>
const Money(this.minor, this.currencyCode)
const Money.zero(String currencyCode)
final int minor
final String currencyCode
bool get isNegative
bool get isPositive
bool get isZero
Money abs()
int compareTo(Money other)
Money convert({ required double rate, required String toCurrencyCode, required int fromDecimalDigits, required int toDecimalDigits, MoneyRounding rounding = MoneyRounding.halfUp, })
final scale = math.pow(10, toDecimalDigits - fromDecimalDigits).toDouble()
final rawValue = minor * rate * scale
bool operator ==(Object other)
int get hashCode => Object.hash(minor, currencyCode)
String toString()
final class CurrencyMismatchError extends Error
CurrencyMismatchError(this.first, this.second)
final String first
final String second
```

**`lib/core/money/money_formatter.dart`**

```dart
final class MoneyFormatter
const MoneyFormatter()
String format( Money money, { required int decimalDigits, required String symbol, String localeTag = 'en_IN', bool showPlusSign = false, })
final magnitude = money.minor.abs()
final divisor = _pow10(decimalDigits)
final whole = magnitude ~/ divisor
final frac = magnitude % divisor
final symbols = NumberFormat.decimalPattern(localeTag).symbols
final groupedWhole = _groupDigits( whole.toString(), groupSeparator: symbols.GROUP_SEP, useIndianGrouping: _isIndianLocale(localeTag), )
final fracStr = decimalDigits == 0
final sign = money.isNegative ? '-' : (showPlusSign && money.isPositive ? '+' : '')
var result = 1
final region = localeTag.split(RegExp('[_-]')).last.toUpperCase()
final secondaryGroupSize = useIndianGrouping ? 2 : 3
final primaryGroup = digits.substring(digits.length - 3)
var rest = digits.substring(0, digits.length - 3)
final groups = <String>[]
while (rest.length > secondaryGroupSize)
rest = rest.substring(0, rest.length - secondaryGroupSize)
```

**`lib/core/money/money_parser.dart`**

```dart
final class MoneyParser
const MoneyParser()
Result<Money, ParseFailure> parse( String input, { required String currencyCode, required int decimalDigits, String localeTag = 'en', bool allowNegative = false, })
var text = input.trim()
var sign = 1
sign = -1
text = text.substring(1)
final symbols = NumberFormat.decimalPattern(localeTag).symbols
final groupSep = symbols.GROUP_SEP
final decimalSep = symbols.DECIMAL_SEP
text = text.replaceAll(groupSep, '')
final decimalParts = decimalSep.isEmpty ? [text] : text.split(decimalSep)
final wholePart = decimalParts[0]
final fracPart = decimalParts.length == 2 ? decimalParts[1] : ''
final paddedFrac = fracPart.padRight(decimalDigits, '0')
final digitString = '$
final magnitude = int.parse(digitString)
```

**`lib/core/money/rounding.dart`**

```dart
enum MoneyRounding
int apply(double value)
final flooredValue = magnitude.floor()
final fraction = magnitude - flooredValue
final flooredValue = value.floor()
final fraction = value - flooredValue
```

**`lib/core/quantity/qty.dart`**

```dart
final class Qty implements Comparable<Qty>
const Qty(this.milliBase, this.category)
const Qty.zero(UnitCategory category)
final int milliBase
final UnitCategory category
bool get isNegative
bool get isPositive
bool get isZero
int compareTo(Qty other)
bool operator ==(Object other)
int get hashCode => Object.hash(milliBase, category)
String toString()
final class UnitCategoryMismatchError extends Error
UnitCategoryMismatchError(this.first, this.second)
final UnitCategory first
final UnitCategory second
```

**`lib/core/quantity/qty_formatter.dart`**

```dart
enum UnitStyle
final class QtyFormatter
const QtyFormatter()
String format(Qty qty, {UnitStyle style = UnitStyle.mixed, String localeTag = 'en'})
final isNegative = qty.isNegative
final magnitude = isNegative ? -qty.milliBase : qty.milliBase
final sign = isNegative ? '-' : ''
final body = switch (style)
final bigWhole = magnitude ~/ _milliPerBigUnit
final remainderMilli = magnitude % _milliPerBigUnit
final bigUnit = category == UnitCategory.weight ? 'kg' : 'L'
final hundredths = (magnitude * 100 + _milliPerBigUnit ~/ 2) ~/ _milliPerBigUnit
final whole = hundredths ~/ 100
final frac = hundredths % 100
final fracStr = frac.toString().padLeft(2, '0')
final unit = category.baseUnitCode
final whole = valueMilli ~/ _milliPerBaseUnit
final frac = valueMilli % _milliPerBaseUnit
var fracStr = frac.toString().padLeft(3, '0')
while (fracStr.endsWith('0'))
fracStr = fracStr.substring(0, fracStr.length - 1)
```

**`lib/core/quantity/qty_parser.dart`**

```dart
final class QtyParser
const QtyParser()
static const int maxMilliBase = 1000000000000000
Result<Qty, ParseFailure> parse( String input, { required UnitCategory category, required int factorToBaseMilli, String localeTag = 'en', bool allowNegative = false, })
var text = input.trim()
var sign = 1
sign = -1
text = text.substring(1)
final symbols = NumberFormat.decimalPattern(localeTag).symbols
final groupSeparator = symbols.GROUP_SEP
final decimalSeparator = symbols.DECIMAL_SEP
text = text.replaceAll(groupSeparator, '')
final parts = decimalSeparator.isEmpty ? [text] : text.split(decimalSeparator)
final wholePart = parts[0]
final fractionPart = parts.length == 2 ? parts[1] : ''
final digits = '$
final magnitude = int.parse(digits)
final scaled = magnitude * factorToBaseMilli
final divisor = _pow10(fractionPart.length)
String format(Qty qty, {required int factorToBaseMilli, int maxFractionDigits = 6})
final negative = qty.isNegative
final magnitude = negative ? -qty.milliBase : qty.milliBase
final sign = negative ? '-' : ''
final whole = magnitude ~/ factorToBaseMilli
final remainder = magnitude % factorToBaseMilli
final scaled = remainder * _pow10(maxFractionDigits) ~/ factorToBaseMilli
var fraction = scaled.toString().padLeft(maxFractionDigits, '0')
while (fraction.endsWith('0'))
fraction = fraction.substring(0, fraction.length - 1)
var result = 1
```

**`lib/core/quantity/unit_category.dart`**

```dart
enum UnitCategory
String get baseUnitCode => switch (this)
```

**`lib/core/quantity/unit_converter.dart`**

```dart
final class UnitConverter
const UnitConverter()
Result<int, ParseFailure> parseToMilliBase( String input, { required int unitFactorMilliBase, String localeTag = 'en', bool allowNegative = false, })
var text = input.trim()
var sign = 1
sign = -1
text = text.substring(1)
final symbols = NumberFormat.decimalPattern(localeTag).symbols
final groupSep = symbols.GROUP_SEP
final decimalSep = symbols.DECIMAL_SEP
text = text.replaceAll(groupSep, '')
final parts = decimalSep.isEmpty ? [text] : text.split(decimalSep)
final wholePart = parts[0]
final fracPart = parts.length == 2 ? parts[1] : ''
final numerator = int.parse('${wholePart.isEmpty ? '0' : wholePart}$fracPart')
final denominator = _pow10(fracPart.length)
final product = numerator * unitFactorMilliBase
final milliBase = (product + denominator ~/ 2) ~/ denominator
var result = 1
```

**`lib/core/text/normalizer.dart`**

```dart
final class Normalizer
const Normalizer()
String normalize(String input)
final caseFolded = input.toLowerCase()
final withoutDiacritics = _stripDiacritics(caseFolded)
final withoutPunctuation = withoutDiacritics.replaceAll(_nonLetterDigitOrMark, ' ')
final buffer = StringBuffer()
final replacement = _diacriticMap[rune]
```

**`lib/core/time/clock.dart`**

```dart
abstract interface class Clock
DateTime now()
extension ClockDerived on Clock
int nowUtcMillis()
DateKey today()
final class SystemClock implements Clock
const SystemClock()
final class FixedClock implements Clock
FixedClock(DateTime initial) : _current = initial
void advance(Duration duration)
void setTo(DateTime dateTime)
```

**`lib/core/time/date_key.dart`**

```dart
extension type const DateKey(int value)
factory DateKey.fromYmd(int year, int month, int day)
final rolled = DateTime.utc(year, month, day)
factory DateKey.fromDateTime(DateTime dateTime)
int get year
int get month => (value ~/ 100) % 100
int get day
int get monthKey
int get weekday => toUtcMidnight().weekday
DateTime toUtcMidnight()
DateKey addDays(int days)
int diffDays(DateKey other)
bool isBefore(DateKey other)
bool isAfter(DateKey other)
bool isWithin(DateKey start, DateKey end)
int compareTo(DateKey other)
static int compare(DateKey a, DateKey b)
String toIso()
```


### Core — enums (renaming a value is a breaking migration, L13)

**`lib/core/enums/date_range_preset.dart`**

```dart
enum DateRangePreset
```

**`lib/core/enums/inventory_enums.dart`**

```dart
enum ItemKind
enum BatchOrigin
enum StockMovementKind
```

**`lib/core/enums/money_enums.dart`**

```dart
enum TransactionKind
enum TransactionSubtype
enum AccountKind
enum PaymentMethodKind
enum PayeeKind
enum TransactionLineDestination
```

**`lib/core/enums/ops_enums.dart`**

```dart
enum NotificationKind
enum NotificationStatus
enum BackupKind
```

**`lib/core/enums/recurring_enums.dart`**

```dart
enum RecurringKind
enum RecurringDirection
enum RecurringIntervalUnit
enum RecurringOccurrenceStatus
```

**`lib/core/enums/safe_enum_converter.dart`**

```dart
final class SafeEnumConverter<T extends Enum>
const SafeEnumConverter(this.values, this.fallback)
final List<T> values
final T fallback
String toSql(T value)
T fromSql(String raw)
```

**`lib/core/enums/service_enums.dart`**

```dart
enum AssetType
enum AssetStatus
enum AssetDisposalReason
enum ServiceRecordType
```

**`lib/core/enums/shopping_enums.dart`**

```dart
enum ShoppingEntryOrigin
enum ShoppingEntryAutoState
```

**`lib/core/enums/tag_scope.dart`**

```dart
enum TagScope
```


### Core — result, failures, logging

**`lib/core/logging/logger.dart`**

```dart
enum LogLevel
abstract interface class Logger
void log( String message, { LogLevel level = LogLevel.info, String? tag, Object? error, StackTrace? stackTrace, })
final class DeveloperLogger implements Logger
const DeveloperLogger()
final class NoopLogger implements Logger
const NoopLogger()
```

**`lib/core/result/failure.dart`**

```dart
const Failure(this.message)
final String message
String toString()
final class NotFoundFailure extends Failure
const NotFoundFailure(super.message, {required this.id})
final String id
final class ConflictFailure extends Failure
const ConflictFailure(super.message)
final class BusinessRuleFailure extends Failure
const BusinessRuleFailure(super.message, {required this.rule})
final String rule
final class ValidationFailure extends Failure
const ValidationFailure(super.message, {this.field})
final String? field
final class UnexpectedFailure extends Failure
const UnexpectedFailure(super.message, {this.cause})
final Object? cause
enum ParseFailure
```

**`lib/core/result/result.dart`**

```dart
const Result()
bool get isOk
bool get isFailure
T? get valueOrNull => switch (this)
F? get failureOrNull => switch (this)
final class Ok<T, F> extends Result<T, F>
const Ok(this.value)
final T value
bool operator ==(Object other)
int get hashCode => Object.hash(Ok, value)
String toString()
final class Err<T, F> extends Result<T, F>
const Err(this.failure)
final F failure
int get hashCode => Object.hash(Err, failure)
```


### Domain — entities

**`lib/domain/entities/account.dart`**

```dart
class Account
const Account({ required this.id, required this.name, required this.normalizedName, required this.kind, required this.currencyCode, required this.openingBalance, required this.openingBalanceDateKey, required this.isArchived, required this.includeInNetWorth, required this.sortOrder, this.colorArgb, this.iconKey, })
final String id
final String name
final String normalizedName
final AccountKind kind
final String currencyCode
final Money openingBalance
final DateKey openingBalanceDateKey
final bool isArchived
final bool includeInNetWorth
final int sortOrder
final int? colorArgb
final String? iconKey
bool get isSelectable
Account copyWith({ String? id, String? name, String? normalizedName, AccountKind? kind, String? currencyCode, Money? openingBalance, DateKey? openingBalanceDateKey, bool? isArchived, bool? includeInNetWorth, int? sortOrder, int? colorArgb, String? iconKey, })
bool operator ==(Object other)
int get hashCode => Object.hashAll([ id, name, normalizedName, kind, currencyCode, openingBalance, openingBalanceDateKey, isArchived, includeInNetWorth, sortOrder, colorArgb, iconKey, ])
String toString()
```

**`lib/domain/entities/account_balance.dart`**

```dart
class AccountBalance
const AccountBalance({ required this.accountId, required this.balance, })
final String accountId
final Money balance
bool get isNegative
bool operator ==(Object other)
int get hashCode => Object.hash(accountId, balance)
String toString()
```

**`lib/domain/entities/asset.dart`**

```dart
class Asset
final String id
final String name
final String normalizedName
final AssetType type
final AssetStatus status
final String? brand
final String? modelNo
final String? serialNo
final DateKey? purchaseDateKey
final Money? purchasePrice
final String? sourceTransactionLineId
final DateKey? warrantyStartDateKey
final DateKey? warrantyEndDateKey
final String? warrantyProvider
final String? warrantyNote
final int? serviceIntervalDays
final DateKey? nextServiceDueDateKey
final String? primaryContactName
final String? primaryContactPhone
final String? location
final String? linkedRecurringTemplateId
final DateKey? disposedAtDateKey
final AssetDisposalReason? disposalReason
final String? disposalNote
final Money? disposalAmount
final String? notes
bool get isDisposed
bool get isInUse
bool get hasContactPhone
bool get isServiceProvider
int? warrantyDaysLeftFrom(DateKey today)
bool isUnderWarranty(DateKey today)
final end = warrantyEndDateKey
final start = warrantyStartDateKey
bool isWarrantyEndingWithin(DateKey today, int days)
final left = warrantyDaysLeftFrom(today)
int? serviceDaysLeftFrom(DateKey today)
bool isServiceOverdue(DateKey today)
final due = nextServiceDueDateKey
Money? get netCost
final paid = purchasePrice
final recovered = disposalAmount
bool operator ==(Object other)
String toString()
```

**`lib/domain/entities/batch.dart`**

```dart
class Batch
const Batch({ required this.id, required this.itemId, required this.initialQuantity, required this.remainingQuantity, required this.unitCodeAtPurchase, required this.purchasedDateKey, required this.origin, this.expiryDateKey, this.unitCost, this.sourceTransactionLineId, this.storageLocation, this.note, })
final String id
final String itemId
final Qty initialQuantity
final Qty remainingQuantity
final String unitCodeAtPurchase
final DateKey purchasedDateKey
final BatchOrigin origin
final DateKey? expiryDateKey
final Money? unitCost
final String? sourceTransactionLineId
final String? storageLocation
final String? note
bool get isExhausted
bool get hasStock
Qty get consumedQuantity
bool isExpired(DateKey today)
final expiry = expiryDateKey
bool isExpiringWithin(DateKey today, int days)
int? daysUntilExpiry(DateKey today)
Money? get remainingValue
final cost = unitCost
Batch copyWith({ String? id, String? itemId, Qty? initialQuantity, Qty? remainingQuantity, String? unitCodeAtPurchase, DateKey? purchasedDateKey, BatchOrigin? origin, DateKey? expiryDateKey, Money? unitCost, String? sourceTransactionLineId, String? storageLocation, String? note, })
bool operator ==(Object other)
int get hashCode => Object.hashAll([ id, itemId, initialQuantity, remainingQuantity, unitCodeAtPurchase, purchasedDateKey, origin, expiryDateKey, unitCost, sourceTransactionLineId, storageLocation, note, ])
String toString()
```

**`lib/domain/entities/calendar_event.dart`**

```dart
enum CalendarEventType
enum CalendarSeverity
class CalendarEvent
const CalendarEvent({ required this.dateKey, required this.type, required this.refType, required this.refId, required this.title, required this.baseSeverity, this.amount, })
final DateKey dateKey
final CalendarEventType type
final String refType
final String refId
final String title
final CalendarSeverity baseSeverity
final Money? amount
CalendarSeverity severityAsOf(DateKey today)
final daysAway = dateKey.diffDays(today)
int daysAwayFrom(DateKey today)
bool isPast(DateKey today)
bool operator ==(Object other)
int get hashCode
String toString()
```

**`lib/domain/entities/converted_money.dart`**

```dart
enum RateQuality
class ConvertedMoney
const ConvertedMoney({ required this.original, required this.quality, this.converted, this.rate, this.rateDateKey, })
const ConvertedMoney.unconverted(this.original)
converted = null
rate = null
rateDateKey = null
final Money original
final RateQuality quality
final Money? converted
final double? rate
final DateKey? rateDateKey
bool get hasConversion
bool get isExcludedFromTotals
Money get display
bool operator ==(Object other)
int get hashCode => Object.hashAll([original, quality, converted, rate, rateDateKey])
String toString()
```

**`lib/domain/entities/currency.dart`**

```dart
class Currency
const Currency({ required this.code, required this.name, required this.symbol, required this.decimalDigits, required this.isEnabled, required this.sortOrder, })
final String code
final String name
final String symbol
final int decimalDigits
final bool isEnabled
final int sortOrder
Money get zero => Money.zero(code)
Currency copyWith({ String? code, String? name, String? symbol, int? decimalDigits, bool? isEnabled, int? sortOrder, })
bool operator ==(Object other)
int get hashCode
String toString()
```

**`lib/domain/entities/item.dart`**

```dart
class Item
const Item({ required this.id, required this.name, required this.normalizedName, required this.unitCategory, required this.defaultDisplayUnitCode, required this.itemKind, required this.isFavorite, this.lowStockThreshold, this.expiryNotifyDays, this.notes, })
final String id
final String name
final String normalizedName
final UnitCategory unitCategory
final String defaultDisplayUnitCode
final ItemKind itemKind
final bool isFavorite
final Qty? lowStockThreshold
final int? expiryNotifyDays
final String? notes
bool get hasThreshold
Item copyWith({ String? id, String? name, String? normalizedName, UnitCategory? unitCategory, String? defaultDisplayUnitCode, ItemKind? itemKind, bool? isFavorite, Qty? lowStockThreshold, int? expiryNotifyDays, String? notes, })
bool operator ==(Object other)
int get hashCode => Object.hashAll([ id, name, normalizedName, unitCategory, defaultDisplayUnitCode, itemKind, isFavorite, lowStockThreshold, expiryNotifyDays, notes, ])
String toString()
```

**`lib/domain/entities/item_stock.dart`**

```dart
class ItemStock
const ItemStock({ required this.itemId, required this.totalRemaining, required this.batchCount, required this.isLowStock, this.nearestExpiry, this.lowStockThreshold, })
final String itemId
final Qty totalRemaining
final int batchCount
final bool isLowStock
final DateKey? nearestExpiry
final Qty? lowStockThreshold
bool get isOutOfStock
Qty? get shortfall
final threshold = lowStockThreshold
bool hasExpiredStock(DateKey today)
final expiry = nearestExpiry
int? daysUntilNearestExpiry(DateKey today)
bool operator ==(Object other)
int get hashCode => Object.hashAll( [itemId, totalRemaining, batchCount, isLowStock, nearestExpiry, lowStockThreshold])
String toString()
```

**`lib/domain/entities/payee.dart`**

```dart
class Payee
const Payee({ required this.id, required this.name, required this.normalizedName, required this.kind, this.phone, this.note, })
final String id
final String name
final String normalizedName
final PayeeKind kind
final String? phone
final String? note
bool get hasPhone
Payee copyWith({ String? id, String? name, String? normalizedName, PayeeKind? kind, String? phone, String? note, })
bool operator ==(Object other)
int get hashCode => Object.hashAll([id, name, normalizedName, kind, phone, note])
String toString()
```

**`lib/domain/entities/payment_method.dart`**

```dart
class PaymentMethod
const PaymentMethod({ required this.id, required this.name, required this.kind, required this.isSystem, required this.sortOrder, })
final String id
final String name
final PaymentMethodKind kind
final bool isSystem
final int sortOrder
bool get isDeletable
PaymentMethod copyWith({ String? id, String? name, PaymentMethodKind? kind, bool? isSystem, int? sortOrder, })
bool operator ==(Object other)
int get hashCode => Object.hashAll([id, name, kind, isSystem, sortOrder])
String toString()
```

**`lib/domain/entities/recurring_occurrence.dart`**

```dart
class RecurringOccurrence
const RecurringOccurrence({ required this.id, required this.templateId, required this.dueDateKey, required this.status, this.paidTransactionId, this.paidAmount, this.paidDateKey, this.note, })
final String id
final String templateId
final DateKey dueDateKey
final RecurringOccurrenceStatus status
final String? paidTransactionId
final Money? paidAmount
final DateKey? paidDateKey
final String? note
bool get isOutstanding
bool get isPaid
bool isOverdue(DateKey today)
int daysUntilDue(DateKey today)
bool isDueWithin(DateKey today, int days)
RecurringOccurrence copyWith({ String? id, String? templateId, DateKey? dueDateKey, RecurringOccurrenceStatus? status, String? paidTransactionId, Money? paidAmount, DateKey? paidDateKey, String? note, })
bool operator ==(Object other)
int get hashCode => Object.hashAll([ id, templateId, dueDateKey, status, paidTransactionId, paidAmount, paidDateKey, note, ])
String toString()
```

**`lib/domain/entities/recurring_template.dart`**

```dart
class RecurringTemplate
final String id
final String name
final String normalizedName
final RecurringKind kind
final RecurringDirection direction
final Money defaultAmount
final RecurringIntervalUnit intervalUnit
final int intervalCount
final DateKey startDateKey
final DateKey nextDueDateKey
final bool isPaused
final bool autoRemind
final int remindDaysBefore
final String? payeeId
final String? defaultAccountId
final String? defaultPaymentMethodId
final String? tagId
final int? anchorDayOfMonth
final int? anchorMonth
final int? anchorWeekday
final DateKey? endDateKey
final String? linkedAssetId
final String? note
bool get isOutflow
bool hasEnded(DateKey today)
final end = endDateKey
bool isActiveAsOf(DateKey today)
int? clampedDayFor({required int year, required int month})
final anchor = anchorDayOfMonth
final lastDayOfMonth = DateTime.utc(year, month + 1, 0).day
bool operator ==(Object other)
int get hashCode => Object.hashAll([ id, name, normalizedName, kind, direction, defaultAmount, intervalUnit, intervalCount, startDateKey, nextDueDateKey, isPaused, autoRemind, remindDaysBefore, payeeId, defaultAccountId, defaultPaymentMethodId, tagId, anchorDayOfMonth, anchorMonth, anchorWeekday, endDateKey, linkedAssetId, note, ])
String toString()
```

**`lib/domain/entities/service_record.dart`**

```dart
class ServiceRecord
const ServiceRecord({ required this.id, required this.assetId, required this.serviceDateKey, required this.type, this.providerName, this.providerPhone, this.cost, this.linkedTransactionId, this.nextDueDateKey, this.notes, })
final String id
final String assetId
final DateKey serviceDateKey
final ServiceRecordType type
final String? providerName
final String? providerPhone
final Money? cost
final String? linkedTransactionId
final DateKey? nextDueDateKey
final String? notes
bool get hasCost
bool get isBookedAsExpense
bool get hasProviderPhone
bool get isSalaryPayment
int? daysUntilNextDue(DateKey today)
ServiceRecord copyWith({ String? id, String? assetId, DateKey? serviceDateKey, ServiceRecordType? type, String? providerName, String? providerPhone, Money? cost, String? linkedTransactionId, DateKey? nextDueDateKey, String? notes, })
bool operator ==(Object other)
int get hashCode => Object.hashAll([ id, assetId, serviceDateKey, type, providerName, providerPhone, cost, linkedTransactionId, nextDueDateKey, notes, ])
String toString()
```

**`lib/domain/entities/shopping_entry.dart`**

```dart
class ShoppingEntry
const ShoppingEntry({ required this.id, required this.listId, required this.origin, required this.autoState, required this.isChecked, required this.sortOrder, this.itemId, this.freeText, this.quantity, this.unitCode, this.tagId, this.estimatedPrice, this.checkedAtUtc, this.snoozeUntilDateKey, this.stockAtGeneration, this.purchasedTransactionLineId, })
final String id
final String listId
final ShoppingEntryOrigin origin
final ShoppingEntryAutoState autoState
final bool isChecked
final int sortOrder
final String? itemId
final String? freeText
final Qty? quantity
final String? unitCode
final String? tagId
final Money? estimatedPrice
final DateTime? checkedAtUtc
final DateKey? snoozeUntilDateKey
final Qty? stockAtGeneration
final String? purchasedTransactionLineId
String? get displayLabel
bool get isAutoGenerated
bool get isPurchased
bool isVisibleAsOf(DateKey today)
bool isOutstandingAsOf(DateKey today)
ShoppingEntry copyWith({ String? id, String? listId, ShoppingEntryOrigin? origin, ShoppingEntryAutoState? autoState, bool? isChecked, int? sortOrder, String? itemId, String? freeText, Qty? quantity, String? unitCode, String? tagId, Money? estimatedPrice, DateTime? checkedAtUtc, DateKey? snoozeUntilDateKey, Qty? stockAtGeneration, String? purchasedTransactionLineId, })
bool operator ==(Object other)
int get hashCode => Object.hashAll([ id, listId, origin, autoState, isChecked, sortOrder, itemId, freeText, quantity, unitCode, tagId, estimatedPrice, checkedAtUtc, snoozeUntilDateKey, stockAtGeneration, purchasedTransactionLineId, ])
String toString()
```

**`lib/domain/entities/shopping_list.dart`**

```dart
class ShoppingList
const ShoppingList({ required this.id, required this.name, required this.isDefault, required this.isArchived, this.targetDateKey, })
final String id
final String name
final bool isDefault
final bool isArchived
final DateKey? targetDateKey
bool get isSelectable
int? daysUntilTarget(DateKey today)
ShoppingList copyWith({ String? id, String? name, bool? isDefault, bool? isArchived, DateKey? targetDateKey, })
bool operator ==(Object other)
int get hashCode => Object.hashAll([id, name, isDefault, isArchived, targetDateKey])
String toString()
```

**`lib/domain/entities/stock_movement.dart`**

```dart
class StockMovement
const StockMovement({ required this.id, required this.batchId, required this.itemId, required this.kind, required this.quantity, required this.occurredAtUtc, required this.dateKey, this.reason, this.note, this.linkedTransactionId, this.reversesMovementId, })
final String id
final String batchId
final String itemId
final StockMovementKind kind
final Qty quantity
final DateTime occurredAtUtc
final DateKey dateKey
final String? reason
final String? note
final String? linkedTransactionId
final String? reversesMovementId
bool get isIncoming => switch (kind)
Qty get signedQuantity
bool get isWaste
kind == StockMovementKind.waste || kind == StockMovementKind.expired
bool get isReversal
bool operator ==(Object other)
int get hashCode => Object.hashAll([ id, batchId, itemId, kind, quantity, occurredAtUtc, dateKey, reason, note, linkedTransactionId, reversesMovementId, ])
String toString()
```

**`lib/domain/entities/tag.dart`**

```dart
class Tag
const Tag({ required this.id, required this.name, required this.normalizedName, required this.allowedScopes, required this.isSystem, required this.sortOrder, required this.isDeleted, this.colorArgb, this.iconKey, this.parentTagId, })
final String id
final String name
final String normalizedName
final Set<TagScope> allowedScopes
final bool isSystem
final int sortOrder
final bool isDeleted
final int? colorArgb
final String? iconKey
final String? parentTagId
bool isAllowedIn(TagScope scope)
bool get isChild
bool get isDeletable
Tag copyWith({ String? id, String? name, String? normalizedName, Set<TagScope>? allowedScopes, bool? isSystem, int? sortOrder, bool? isDeleted, int? colorArgb, String? iconKey, String? parentTagId, })
bool operator ==(Object other)
int get hashCode => Object.hashAll([ id, name, normalizedName, // Order-independent, so two equal sets built in different orders hash alike. Object.hashAllUnordered(allowedScopes), isSystem, sortOrder, isDeleted, colorArgb, iconKey, parentTagId, ])
String toString()
```

**`lib/domain/entities/transaction.dart`**

```dart
class Transaction
final String id
final TransactionKind kind
final TransactionSubtype subtype
final DateTime occurredAtUtc
final DateKey dateKey
final Money originalAmount
final bool needsReview
final String? fromAccountId
final String? toAccountId
final String? paymentMethodId
final String? payeeId
final String? note
final String? recurringTemplateId
final String? recurringOccurrenceId
final Money? frozenConversion
final double? frozenConversionRate
final String? frozenConversionRateRaw
final DateKey? frozenConversionDateKey
int get monthKey
Money get signedAmount => switch (kind)
Money signedAmountFor(String accountId)
final zero = Money.zero(originalAmount.currencyCode)
bool get isTransfer
bool get isInflow
kind == TransactionKind.deposit || kind == TransactionKind.adjustmentIncrease
bool get isOutflow
kind == TransactionKind.withdrawal || kind == TransactionKind.adjustmentDecrease
bool get isAdjustment
kind == TransactionKind.adjustmentIncrease || kind == TransactionKind.adjustmentDecrease
bool get isRecurring
bool get hasFrozenConversion
bool operator ==(Object other)
int get hashCode => Object.hashAll([ id, kind, subtype, occurredAtUtc, dateKey, originalAmount, needsReview, fromAccountId, toAccountId, paymentMethodId, payeeId, note, recurringTemplateId, recurringOccurrenceId, frozenConversion, frozenConversionRate, frozenConversionRateRaw, frozenConversionDateKey, ])
String toString()
```

**`lib/domain/entities/transaction_line.dart`**

```dart
class TransactionLine
const TransactionLine({ required this.id, required this.transactionId, required this.lineNo, required this.description, required this.destination, this.itemId, this.quantity, this.unitCode, this.unitPrice, this.lineAmount, this.createdBatchId, this.createdAssetId, this.createdRecurringTemplateId, this.note, })
final String id
final String transactionId
final int lineNo
final String description
final TransactionLineDestination destination
final String? itemId
final Qty? quantity
final String? unitCode
final Money? unitPrice
final Money? lineAmount
final String? createdBatchId
final String? createdAssetId
final String? createdRecurringTemplateId
final String? note
bool get hasArtefact
String? get createdArtefactId
createdBatchId ?? createdAssetId ?? createdRecurringTemplateId
bool get isCatalogued
double? get pricePerBaseUnit
final amount = lineAmount
final qty = quantity
TransactionLine copyWith({ String? id, String? transactionId, int? lineNo, String? description, TransactionLineDestination? destination, String? itemId, Qty? quantity, String? unitCode, Money? unitPrice, Money? lineAmount, String? createdBatchId, String? createdAssetId, String? createdRecurringTemplateId, String? note, })
bool operator ==(Object other)
int get hashCode => Object.hashAll([ id, transactionId, lineNo, description, destination, itemId, quantity, unitCode, unitPrice, lineAmount, createdBatchId, createdAssetId, createdRecurringTemplateId, note, ])
String toString()
```

**`lib/domain/entities/unit.dart`**

```dart
class Unit
const Unit({ required this.code, required this.category, required this.factorToBaseMilli, required this.displayName, required this.isSystem, required this.sortOrder, })
final String code
final UnitCategory category
final int factorToBaseMilli
final String displayName
final bool isSystem
final int sortOrder
bool get isBaseUnit
Unit copyWith({ String? code, UnitCategory? category, int? factorToBaseMilli, String? displayName, bool? isSystem, int? sortOrder, })
bool operator ==(Object other)
int get hashCode => Object.hashAll( [code, category, factorToBaseMilli, displayName, isSystem, sortOrder])
String toString()
```


### Domain — repository contracts

**`lib/domain/repositories/account_repository.dart`**

```dart
abstract interface class AccountRepository
Stream<List<Account>> watchSelectable()
Stream<List<Account>> watchAllIncludingArchived()
Future<Account?> byId(String id)
Stream<List<AccountBalance>> watchBalances()
Stream<AccountBalance?> watchBalanceOf(String accountId)
Stream<List<Transaction>> watchLedgerFor(String accountId)
Future<Result<Account, Failure>> save(Account account)
Future<Result<void, Failure>> setArchived({ required String id, required bool isArchived, })
Future<Result<void, Failure>> delete(String id)
```

**`lib/domain/repositories/analytics_cache_repository.dart`**

```dart
abstract interface class AnalyticsCacheRepository
Future<String?> read({ required String cacheKey, required String paramsHash, })
Future<void> write({ required String cacheKey, required String paramsHash, required String payloadJson, required Duration ttl, })
Future<void> invalidate(String cacheKey)
Future<void> invalidateAll()
```

**`lib/domain/repositories/asset_repository.dart`**

```dart
abstract interface class AssetRepository
Stream<List<Asset>> watchInUse()
Stream<List<Asset>> watchByType(AssetType type)
Stream<List<Asset>> watchDisposed()
Future<Asset?> byId(String id)
Stream<List<Asset>> watchWarrantyEndingInRange({ required DateKey from, required DateKey to, })
Stream<List<Asset>> watchServiceDueInRange({ required DateKey from, required DateKey to, })
Future<Result<Asset, Failure>> save(Asset asset)
Future<Result<void, Failure>> setStatus({ required String id, required AssetStatus status, })
Future<Result<void, Failure>> dispose({ required String assetId, required AssetDisposalReason reason, required DateKey dateKey, int? amountMinor, String? note, })
Future<Result<void, Failure>> undispose(String id)
Future<Result<void, Failure>> detachFromDeletedTransaction(String id)
```

**`lib/domain/repositories/batch_repository.dart`**

```dart
class BatchReconciliation
const BatchReconciliation({ required this.batchId, required this.cached, required this.fromLedger, required this.discrepancy, })
final String batchId
final Qty cached
final Qty fromLedger
final Qty discrepancy
bool get isConsistent
abstract interface class BatchRepository
Stream<List<Batch>> watchByItemFefo(String itemId)
Future<List<Batch>> byItemFefo(String itemId)
Stream<List<Batch>> watchByItem(String itemId)
Stream<List<Batch>> watchExpiringInRange({ required DateKey from, required DateKey to, })
Future<Batch?> byId(String id)
Future<Result<Batch, Failure>> create(Batch batch)
Future<Result<Batch, Failure>> updateMetadata(Batch batch)
Future<Result<void, Failure>> detachFromDeletedTransaction(String batchId)
Future<Result<void, Failure>> delete(String id)
Stream<List<BatchReconciliation>> watchReconciliation()
Future<List<BatchReconciliation>> findDiscrepancies()
Future<Result<void, Failure>> recompute(String batchId)
Future<Result<int, Failure>> recomputeAll()
```

**`lib/domain/repositories/calendar_repository.dart`**

```dart
abstract interface class CalendarRepository
Stream<List<CalendarEvent>> watchRange({ required DateKey from, required DateKey to, })
Future<List<CalendarEvent>> forDay(DateKey dateKey)
Future<Map<DateKey, int>> countsByDate({ required DateKey from, required DateKey to, })
```

**`lib/domain/repositories/currency_repository.dart`**

```dart
abstract interface class CurrencyRepository
Stream<List<Currency>> watchEnabled()
Stream<List<Currency>> watchAll()
Future<Currency?> byCode(String code)
Future<Map<String, int>> decimalDigitsByCode()
Future<Result<void, Failure>> setEnabled({ required String code, required bool isEnabled, })
Future<ConvertedMoney> convert({ required Money amount, required String toCurrencyCode, required DateKey on, })
Future<ConvertedMoney> convertToHome({ required Money amount, required DateKey on, })
Stream<int> watchUnconvertedCount()
Future<void> syncDailyRates()
```

**`lib/domain/repositories/item_repository.dart`**

```dart
abstract interface class ItemRepository
Stream<List<Item>> watchAll()
Stream<List<Item>> watchByCategory(UnitCategory category)
Stream<List<Item>> watchFavorites()
Stream<List<Item>> watchMatching(String term)
Future<Item?> byId(String id)
Future<Item?> findByIdentity({ required String normalizedName, required UnitCategory unitCategory, })
Future<List<Item>> findSimilar({ required String name, required UnitCategory unitCategory, })
Stream<List<ItemStock>> watchAllStock()
Stream<ItemStock?> watchStockOf(String itemId)
Stream<List<ItemStock>> watchLowStock()
Future<Result<Item, Failure>> save(Item item)
Future<Result<void, Failure>> setFavorite({ required String id, required bool isFavorite, })
Future<Result<void, Failure>> delete(String id)
```

**`lib/domain/repositories/payee_repository.dart`**

```dart
abstract interface class PayeeRepository
Stream<List<Payee>> watchAll()
Stream<List<Payee>> watchMatching(String term)
Future<Payee?> byId(String id)
Future<Payee?> byNormalizedName(String normalizedName)
Future<Result<Payee, Failure>> save(Payee payee)
Future<Result<void, Failure>> delete(String id)
```

**`lib/domain/repositories/payment_method_repository.dart`**

```dart
abstract interface class PaymentMethodRepository
Stream<List<PaymentMethod>> watchAll()
Future<PaymentMethod?> byId(String id)
Future<Result<PaymentMethod, Failure>> save(PaymentMethod method)
Future<Result<void, Failure>> delete(String id)
```

**`lib/domain/repositories/recurring_repository.dart`**

```dart
class RecurringDue
const RecurringDue({required this.template, this.occurrence})
final RecurringTemplate template
final RecurringOccurrence? occurrence
bool isOverdue(DateKey today)
abstract interface class RecurringRepository
Stream<List<RecurringTemplate>> watchAllTemplates()
Stream<List<RecurringTemplate>> watchTemplatesByDirection(RecurringDirection direction)
Stream<List<RecurringDue>> watchDue()
Future<RecurringTemplate?> templateById(String id)
Stream<List<RecurringTemplate>> watchTemplatesForAsset(String assetId)
Future<Result<RecurringTemplate, Failure>> saveTemplate(RecurringTemplate template)
Future<Result<void, Failure>> setTemplatePaused({ required String id, required bool isPaused, })
Future<Result<void, Failure>> deleteTemplate(String id)
Stream<List<RecurringOccurrence>> watchOccurrences(String templateId)
Stream<List<RecurringOccurrence>> watchOccurrencesInRange({ required DateKey from, required DateKey to, })
Future<Result<int, Failure>> materialiseUpTo(DateKey asOf)
Future<Result<Transaction, Failure>> payOccurrence({ required String occurrenceId, required Money amount, required DateKey paidOn, required String accountId, String? paymentMethodId, })
Future<Result<void, Failure>> skipOccurrence({ required String occurrenceId, String? note, })
Future<Result<void, Failure>> unsettleOccurrence(String occurrenceId)
```

**`lib/domain/repositories/service_record_repository.dart`**

```dart
abstract interface class ServiceRecordRepository
Stream<List<ServiceRecord>> watchForAsset(String assetId)
Stream<List<ServiceRecord>> watchForAssetByType({ required String assetId, required ServiceRecordType type, })
Stream<List<ServiceRecord>> watchWithNextDueInRange({ required DateKey from, required DateKey to, })
Future<ServiceRecord?> byId(String id)
Future<ServiceRecord?> mostRecentForAsset(String assetId)
Future<Map<String, Money>> lifetimeCostByCurrency(String assetId)
Future<Result<ServiceRecord, Failure>> save( ServiceRecord record, { bool alsoRecordAsExpense, String? accountId, String? paymentMethodId, })
Future<Result<void, Failure>> unlinkDeletedTransaction(String id)
Future<Result<void, Failure>> delete(String id)
```

**`lib/domain/repositories/settings_repository.dart`**

```dart
abstract interface class SettingsRepository
Stream<String?> watchValue(String key)
Future<String?> readValue(String key)
Stream<Map<String, String>> watchAll()
Future<Result<void, Failure>> writeValue({ required String key, required String value, required String valueType, })
Future<Result<void, Failure>> remove(String key)
Future<String?> readHomeCurrencyCode()
Future<String?> readDefaultAccountId()
```

**`lib/domain/repositories/shopping_repository.dart`**

```dart
abstract interface class ShoppingRepository
Stream<List<ShoppingList>> watchSelectableLists()
Stream<List<ShoppingList>> watchAllLists()
Stream<ShoppingList?> watchDefaultList()
Future<ShoppingList?> listById(String id)
Future<Result<ShoppingList, Failure>> saveList(ShoppingList list)
Future<Result<void, Failure>> setDefaultList(String id)
Future<Result<void, Failure>> setListArchived({ required String id, required bool isArchived, })
Future<Result<void, Failure>> deleteList(String id)
Stream<List<ShoppingEntry>> watchEntries(String listId)
Stream<List<ShoppingEntry>> watchUncheckedEntries(String listId)
Future<Result<ShoppingEntry, Failure>> saveEntry(ShoppingEntry entry)
Future<Result<void, Failure>> setEntryChecked({ required String id, required bool isChecked, })
Future<Result<void, Failure>> snoozeEntry({ required String id, required DateKey until, })
Future<Result<void, Failure>> dismissEntry(String id)
Future<Result<void, Failure>> reorderEntries(List<String> orderedIds)
Future<Result<void, Failure>> deleteEntry(String id)
Future<Result<int, Failure>> regenerateLowStockSuggestions(String listId)
Future<Result<List<TransactionLine>, Failure>> buildPurchaseDraft(String listId)
Future<Result<void, Failure>> markPurchased({ required List<String> entryIds, required String transactionId, })
```

**`lib/domain/repositories/stock_repository.dart`**

```dart
class ConsumptionDraw
const ConsumptionDraw({required this.batchId, required this.quantity})
final String batchId
final Qty quantity
class WasteTotal
const WasteTotal({ required this.itemId, required this.quantity, required this.costByCurrency, })
final String itemId
final Map<String, Money> costByCurrency
abstract interface class StockRepository
Future<Result<List<ConsumptionDraw>, Failure>> consume({ required String itemId, required Qty quantity, required StockMovementKind kind, String? reason, String? note, })
Future<Result<void, Failure>> consumeFromBatch({ required String batchId, required Qty quantity, required StockMovementKind kind, String? reason, String? note, })
Future<Result<void, Failure>> addStock({ required String batchId, required Qty quantity, required StockMovementKind kind, String? note, })
Future<Result<void, Failure>> reverse({ required String movementId, String? reason, })
Stream<List<StockMovement>> watchForBatch(String batchId)
Stream<List<StockMovement>> watchForItemInRange({ required String itemId, required DateKey from, required DateKey to, })
Future<List<WasteTotal>> wasteTotals({ required DateKey from, required DateKey to, })
```

**`lib/domain/repositories/tag_repository.dart`**

```dart
abstract interface class TagRepository
Stream<List<Tag>> watchAll()
Stream<List<Tag>> watchByScope(TagScope scope)
Stream<List<Tag>> watchRoots()
Stream<List<Tag>> watchChildren(String parentTagId)
Future<Tag?> byId(String id)
Future<Result<Tag, Failure>> save(Tag tag)
Future<Result<void, Failure>> delete(String id)
Stream<List<Tag>> watchForTransaction(String transactionId)
Future<Result<void, Failure>> setForTransaction({ required String transactionId, required List<String> tagIds, })
Stream<List<Tag>> watchForItem(String itemId)
Future<Result<void, Failure>> setForItem({ required String itemId, required List<String> tagIds, })
Stream<List<Tag>> watchForAsset(String assetId)
Future<Result<void, Failure>> setForAsset({ required String assetId, required List<String> tagIds, })
```

**`lib/domain/repositories/transaction_repository.dart`**

```dart
class TransactionAllocation
const TransactionAllocation({ required this.transactionId, required this.amount, required this.allocated, required this.unallocated, required this.lineCount, })
final String transactionId
final Money amount
final Money allocated
final Money unallocated
final int lineCount
bool get hasMismatch
class DetachedArtefacts
const DetachedArtefacts({ required this.batchIds, required this.assetIds, required this.recurringTemplateIds, required this.untouchedBatchIds, })
final List<String> batchIds
final List<String> assetIds
final List<String> recurringTemplateIds
final List<String> untouchedBatchIds
bool get isEmpty
abstract interface class TransactionRepository
Future<Transaction?> byId(String id)
Stream<List<Transaction>> watchByDateRange({ required DateKey from, required DateKey to, })
Stream<List<Transaction>> watchByAccount(String accountId)
Stream<List<Transaction>> watchBySubtype( TransactionSubtype subtype, { int? fromMonthKey, int? toMonthKey, })
Stream<List<Transaction>> watchNeedingReview()
Stream<int> watchNeedsReviewCount()
Future<List<Transaction>> search(String query, {int limit})
Stream<List<TransactionLine>> watchLines(String transactionId)
Stream<TransactionAllocation?> watchAllocation(String transactionId)
Stream<List<TransactionLine>> watchLinesForItem(String itemId)
Future<Result<Transaction, Failure>> create({ required Transaction transaction, List<TransactionLine> lines, List<String> tagIds, })
Future<Result<Transaction, Failure>> update(Transaction transaction)
Future<Result<void, Failure>> recordCreatedArtefact({ required String lineId, String? createdBatchId, String? createdAssetId, String? createdRecurringTemplateId, })
Future<Result<void, Failure>> replaceLines({ required String transactionId, required List<TransactionLine> lines, })
Future<Result<void, Failure>> markReviewed(String id)
Future<Result<void, Failure>> freezeConversion({ required String id, required DateKey on, required String toCurrencyCode, })
Future<Result<DetachedArtefacts, Failure>> delete({ required String id, String? reason, })
```

**`lib/domain/repositories/unit_repository.dart`**

```dart
abstract interface class UnitRepository
Stream<List<Unit>> watchAll()
Stream<List<Unit>> watchByCategory(UnitCategory category)
Future<Unit?> byCode(String code)
Future<Map<String, int>> factorsByCode()
Future<Map<String, UnitCategory>> categoriesByCode()
Future<Result<Unit, Failure>> save(Unit unit)
Future<Result<void, Failure>> delete(String code)
```


### Domain — services and engines

**`lib/domain/services/analytics/analytics_cache_service.dart`**

```dart
final class AnalyticsCacheService
const AnalyticsCacheService(this._repository)
static const Duration defaultTtl = Duration(hours: 6)
static const Duration cacheThreshold = Duration(milliseconds: 200)
bool shouldCache(Duration estimatedCost)
String keyFor(String queryName, Map<String, Object?> params)
String hashParams(Map<String, Object?> params)
final sorted = params.keys.toList()..sort()
final canonical = {for (final key in sorted) key: _stringify(params[key])}
final encoded = jsonEncode(canonical)
var hash = 0
hash = (hash * 31 + unit) & 0x7FFFFFFF
Map<String, Object?> windowParams(AnalyticsWindow window)
Future<String?> read({ required String queryName, required Map<String, Object?> params, })
final key = keyFor(queryName, params)
Future<void> write({ required String queryName, required Map<String, Object?> params, required String payload, Duration ttl = defaultTtl, })
Future<String> readOrCompute({ required String queryName, required Map<String, Object?> params, required Future<String> Function() compute, Duration ttl = defaultTtl, }) async
final cached = await read(queryName: queryName, params: params)
final fresh = await compute()
Future<void> invalidateOnWrite()
Future<void> invalidate({ required String queryName, required Map<String, Object?> params, })
final bool v => v.toString()
final num v => v.toString()
final String v
final Iterable<Object?> v => v.map(_stringify).join(',')
```

**`lib/domain/services/analytics/analytics_port.dart`**

```dart
typedef RawMoneyRow = ({String key, String label, int amountMinor, String currencyCode, int count})
typedef RawQuantityRow = ({String key, String label, int milliBase, String category, int count})
typedef RawMonthRow = ({int monthKey, int amountMinor, String currencyCode, int count})
typedef RawDateRow = ({int dateKey, int amountMinor, String currencyCode, int count})
typedef RawBucketRow = ({int bucket, int amountMinor, String currencyCode, int count})
abstract interface class AnalyticsPort
Future<List<RawMoneyRow>> spendBySubtype(AnalyticsWindow window)
Future<List<RawMoneyRow>> spendByTag(AnalyticsWindow window)
Future<List<RawMoneyRow>> spendByPaymentMethod(AnalyticsWindow window)
Future<List<RawMoneyRow>> spendByPayee(AnalyticsWindow window, {int limit})
Future<List<RawMonthRow>> totalsByMonthAndKind(AnalyticsWindow window, TransactionKind kind)
Future<List<RawMonthRow>> netFlowByMonth(AnalyticsWindow window)
Future<List<RawDateRow>> ledgerLegsForAccount(String accountId, AnalyticsWindow window)
Future<List<RawMoneyRow>> totalSpend(AnalyticsWindow window)
Future<List<RawMoneyRow>> spendByItem(AnalyticsWindow window, {int limit})
Future<List<RawQuantityRow>> quantityByItem(AnalyticsWindow window, {int limit})
dearestPurchase(String itemId, AnalyticsWindow window)
itemPurchaseHistory(String itemId, AnalyticsWindow window)
valuedBatches()
Future<int> batchesWithoutCost()
wasteMovements(AnalyticsWindow window)
expiringBatches(AnalyticsWindow window)
Future<int> lowStockCount()
activeCommitments()
Future<List<RawMoneyRow>> spendByRecurringFlag(AnalyticsWindow window)
serviceCostByAsset(AnalyticsWindow window)
warrantyWindows()
Future<List<RawBucketRow>> spendByBucket(AnalyticsWindow window, {required bool byWeekday})
DateKey today()
```

**`lib/domain/services/analytics/analytics_service.dart`**

```dart
final class AnalyticsService
const AnalyticsService({ required AnalyticsPort port, required RateTable rates, required String homeCurrencyCode, }) : _port = port
Future<MoneySeries> spendBySubtype(AnalyticsWindow window) async
Future<MoneySeries> spendByTag(AnalyticsWindow window) async
Future<MoneySeries> spendByPaymentMethod(AnalyticsWindow window) async
Future<MoneySeries> topPayeesBySpend(AnalyticsWindow window, {int limit = 10}) async
final series = _toSeries(await _port.spendByPayee(window, limit: limit), window.to)
final sorted = series.slices.toList()
Future<IncomeVsExpense> incomeVsExpense(AnalyticsWindow window) async
final income = await _port.totalsByMonthAndKind(window, TransactionKind.deposit)
final expense = await _port.totalsByMonthAndKind(window, TransactionKind.withdrawal)
final byMonth = <int, ({int income, int expense})>
var approximate = 0
var unconverted = 0
void fold(List<RawMonthRow> rows, {required bool isIncome})
final converted = _convert(row.amountMinor, row.currencyCode, _monthEnd(row.monthKey))
final current = byMonth[row.monthKey] ?? (income: 0, expense: 0)
fold(income, isIncome: true)
fold(expense, isIncome: false)
final points = byMonth.entries
Future<NetCashFlow> netCashFlowByMonth(AnalyticsWindow window) async
Future<BalanceTrend> balanceTrend(String accountId, AnalyticsWindow window) async
final opening = await _port.openingBalance(accountId)
final legs = await _port.ledgerLegsForAccount(accountId, window)
var running = opening.minor
final points = <BalancePoint>[]
Future<ShareOfTotal?> groceryShareOfSpend(AnalyticsWindow window) async
final series = await spendBySubtype(window)
Future<SpendHeatmap> spendHeatmap(AnalyticsWindow window, {bool byWeekday = true}) async
final rows = await _port.spendByBucket(window, byWeekday: byWeekday)
final byBucket = <int, ({int minor, int count})>
final converted = _convert(row.amountMinor, row.currencyCode, window.to)
final current = byBucket[row.bucket] ?? (minor: 0, count: 0)
final cells = byBucket.entries
Future<Concentration> categoryConcentration( AnalyticsWindow window, { int topCount = 3, }) async
final total = series.slices.fold<int>(0, (sum, s) => sum + s.amount.minor)
final top = sorted.take(topCount).map((slice)
Future<BasketStats> averageGroceryBasket(AnalyticsWindow window) async
final baskets = await _port.groceryBaskets(window)
var totalMinor = 0
var totalLines = 0
var counted = 0
final converted = _convert(basket.amountMinor, basket.currencyCode, window.to)
Future<List<ItemSpend>> topItemsBySpend(AnalyticsWindow window, {int limit = 10}) async
final rows = await _port.spendByItem(window, limit: limit)
final out = <ItemSpend>[]
Future<List<ItemQuantity>> topItemsByQuantity(AnalyticsWindow window, {int limit = 10}) async
final rows = await _port.quantityByItem(window, limit: limit)
Future<DearestPurchase?> dearestPurchaseOfItem( String itemId, String itemName, AnalyticsWindow window, ) async
final row = await _port.dearestPurchase(itemId, window)
Future<UnitPriceTrend> unitPriceTrend( String itemId, String itemName, AnalyticsWindow window, ) async
final points = await pricePerBaseUnitHistory(itemId, window)
double? change
final first = points.first.pricePerBaseUnit
final last = points.last.pricePerBaseUnit
Future<List<UnitPricePoint>> pricePerBaseUnitHistory( String itemId, AnalyticsWindow window, ) async
final rows = await _port.itemPurchaseHistory(itemId, window)
final points = <UnitPricePoint>[]
final baseUnits = row.milliBase / 1000
Future<InventoryValue> inventoryValueOnHand() async
final batches = await _port.valuedBatches()
final byCode = <String, int>
final value =
Future<List<ItemWasteTotal>> wasteTotals(AnalyticsWindow window) async
final movements = await _port.wasteMovements(window)
final byItem = <String, ({String name, int milli, String category, Map<String, int> cost})>
final current = byItem[m.itemId] ??
final cost = current.cost
final unitCost = m.unitCostMinor
final code = m.currencyCode
final factor = m.unitFactorToBaseMilli
final value = (unitCost * m.milliBase / factor).truncate()
Future<List<ExpiringBatch>> itemsExpiringWithin(int days) async
final today = _port.today()
final rows = await _port.expiringBatches((from: today, to: today.addDays(days)))
Future<LowStockPoint> lowStockCountToday() async
Future<MonthlyCommitment> monthlyCommitmentTotal() async
final templates = await _port.activeCommitments()
var total = 0
final monthly = _toMonthlyMinor( amountMinor: t.defaultAmountMinor, intervalUnit: t.intervalUnit, intervalCount: t.intervalCount, )
final converted = _convert(monthly, t.currencyCode, today)
Future<RecurringSplit> recurringVsDiscretionary(AnalyticsWindow window) async
final rows = await _port.spendByRecurringFlag(window)
var recurring = 0
var discretionary = 0
final total = recurring + discretionary
Future<List<AssetServiceCost>> lifetimeServiceCostByAsset(AnalyticsWindow window) async
final rows = await _port.serviceCostByAsset(window)
final byAsset = <String, ({String name, Map<String, int> cost, int count})>
final current = byAsset[row.assetId] ?? (name: row.assetName, cost: <String, int>{}, count: 0)
Future<List<WarrantyCoverage>> warrantyCoverage() async
final rows = await _port.warrantyWindows()
final end = row.endDateKey == null ? null : DateKey(row.endDateKey!)
final start = row.startDateKey == null ? null : DateKey(row.startDateKey!)
final daysLeft = end?.diffDays(today)
final result = _rates.convert( amount: Money(minor, currencyCode), toCurrencyCode: _home, on: on, )
final byKey = <String, ({String label, int minor})>
final converted = _convert(row.amountMinor, row.currencyCode, on)
final current = byKey[row.key] ?? (label: row.label, minor: 0)
final slices = byKey.entries
final byMonth = <int, int>
final year = monthKey ~/ 100
final month = monthKey % 100
final perInterval = intervalCount <= 0 ? 1 : intervalCount
switch (intervalUnit)
```

**`lib/domain/services/analytics/analytics_types.dart`**

```dart
typedef AnalyticsWindow = ({DateKey from, DateKey to})
typedef ConversionQuality = ({int approximateCount, int unconvertedCount})
typedef MoneySlice = ({String label, String key, Money amount})
typedef QuantitySlice = ({String label, String key, Qty quantity})
typedef MoneySeries = ({List<MoneySlice> slices, ConversionQuality quality})
typedef MonthPoint = ({int monthKey, Money amount})
typedef MonthSeries = ({List<MonthPoint> points, ConversionQuality quality})
typedef DayPoint = ({DateKey date, Money amount})
typedef SubtypeSpend = ({int monthKey, MoneySeries series})
typedef IncomeVsExpensePoint = ({int monthKey, Money income, Money expense})
typedef IncomeVsExpense = ({List<IncomeVsExpensePoint> points, ConversionQuality quality})
typedef NetCashFlow = ({List<MonthPoint> points, ConversionQuality quality})
typedef BalancePoint = ({DateKey date, Money balance})
typedef BalanceTrend = ({String accountId, List<BalancePoint> points})
typedef ShareOfTotal = ({String key, String label, Money amount, double share})
typedef Concentration = ({ List<ShareOfTotal> top, double topShare, Money total, ConversionQuality quality, })
typedef ItemSpend = ({String itemId, String itemName, Money amount, int purchaseCount})
typedef ItemQuantity = ({String itemId, String itemName, Qty quantity, int purchaseCount})
typedef DearestPurchase = ({ String itemId, String itemName, Money unitPrice, DateKey on, String transactionId, })
typedef UnitPricePoint = ({ DateKey on, Money lineAmount, Qty quantity, double pricePerBaseUnit, })
typedef UnitPriceTrend = ({ String itemId, String itemName, List<UnitPricePoint> points, double? percentChange, })
typedef InventoryValue = ({Map<String, Money> byCurrency, int batchesValued, int batchesNoCost})
typedef ItemWasteTotal = ({ String itemId, String itemName, Qty quantity, Map<String, Money> costByCurrency, })
typedef ExpiringBatch = ({ String batchId, String itemId, String itemName, Qty remaining, DateKey expiry, int daysLeft, })
typedef LowStockPoint = ({DateKey date, int itemCount})
typedef MonthlyCommitment = ({ Money total, int templateCount, ConversionQuality quality, })
typedef RecurringSplit = ({ Money recurring, Money discretionary, double recurringShare, ConversionQuality quality, })
typedef AssetServiceCost = ({ String assetId, String assetName, Map<String, Money> byCurrency, int serviceCount, })
typedef WarrantyCoverage = ({ String assetId, String assetName, DateKey? start, DateKey? end, int? daysLeft, bool isCovered, })
typedef HeatmapCell = ({int bucket, Money amount, int transactionCount})
typedef SpendHeatmap = ({List<HeatmapCell> cells, ConversionQuality quality})
typedef BasketStats = ({ Money averageValue, double averageLineCount, int basketCount, ConversionQuality quality, })
```

**`lib/domain/services/balance_service.dart`**

```dart
class AccountBalanceInput
const AccountBalanceInput({ required this.accountId, required this.balance, required this.includeInNetWorth, })
final String accountId
final Money balance
final bool includeInNetWorth
class NetWorth
const NetWorth({ required this.total, required this.unconvertedCount, required this.isApproximate, })
final Money total
final int unconvertedCount
final bool isApproximate
bool get isComplete
final class BalanceService
const BalanceService()
NetWorth totalFrom({ required Iterable<AccountBalanceInput> balances, required RateTable table, required String homeCurrencyCode, required DateKey asOf, })
var total = Money.zero(homeCurrencyCode)
var unconverted = 0
var approximate = false
final converted = table.convert( amount: input.balance, toCurrencyCode: homeCurrencyCode, on: asOf, )
total = total + converted.converted!
Future<NetWorth> totalInHome({ required Iterable<AccountBalanceInput> balances, required CurrencyRateService rates, required String homeCurrencyCode, required DateKey asOf, }) async
final table = await rates.table()
ConvertedMoney convertOne({ required Money balance, required RateTable table, required String homeCurrencyCode, required DateKey asOf, })
Map<String, Money> totalsByCurrency(Iterable<AccountBalanceInput> balances)
final byCode = <String, int>
```

**`lib/domain/services/calendar_aggregator.dart`**

```dart
typedef CalendarDay = ({ DateKey date, List<CalendarEvent> events, CalendarSeverity severity, })
final class CalendarAggregator
const CalendarAggregator(this._repository)
static const int batchExpiryWarningDays = 7
static const int serviceDueWarningDays = 7
static const int warrantyEndWarningDays = 30
Stream<List<CalendarEvent>> watchRange({ required DateKey from, required DateKey to, required DateKey today, })
Stream<List<CalendarDay>> watchDays({ required DateKey from, required DateKey to, required DateKey today, })
Future<List<CalendarEvent>> forDay({ required DateKey dateKey, required DateKey today, }) async
final events = await _repository.forDay(dateKey)
Future<Map<DateKey, int>> countsByDate({ required DateKey from, required DateKey to, })
List<CalendarDay> groupByDay(List<CalendarEvent> events)
final byDate = <int, List<CalendarEvent>>
final days = byDate.entries.map((entry) { final dayEvents = entry.value; return ( date: DateKey(entry.key), events: dayEvents, severity: worstSeverity(dayEvents), ); }).toList()
CalendarSeverity worstSeverity(Iterable<CalendarEvent> events)
var worst = CalendarSeverity.info
CalendarEvent resolveSeverity({ required CalendarEvent event, required DateKey today, })
final resolved = severityFor(event: event, today: today)
CalendarSeverity severityFor({ required CalendarEvent event, required DateKey today, })
final daysAway = event.dateKey.diffDays(today)
final isPast = daysAway < 0
switch (event.type)
```

**`lib/domain/services/currency_rate_service.dart`**

```dart
class UsdRate
const UsdRate({ required this.quoteCode, required this.on, required this.rate, required this.rateRaw, })
final String quoteCode
final DateKey on
final double rate
final String rateRaw
class RateSnapshot
const RateSnapshot({ required this.on, required this.rates, required this.source, })
final List<UsdRate> rates
final String source
bool get isEmpty
class RateTable
RateTable({ required Iterable<UsdRate> rates, required Map<String, int> decimalDigitsByCode, }) : _decimalDigits = Map.unmodifiable(decimalDigitsByCode)
final code = rate.quoteCode.toUpperCase()
RateTable.empty() : _decimalDigits = const
static const String pivotCode = 'USD'
Iterable<String> get quoteCodes
RateLeg? legFor({required String code, required DateKey on})
final upper = code.toUpperCase()
final rates = _byQuote[upper]
UsdRate? onOrBefore
onOrBefore = rate
final earliest = rates.first
CrossRate? crossRate({ required String from, required String to, required DateKey on, })
final fromLeg = legFor(code: from, on: on)
final toLeg = legFor(code: to, on: on)
ConvertedMoney convert({ required Money amount, required String toCurrencyCode, required DateKey on, })
final cross = crossRate(from: amount.currencyCode, to: toCurrencyCode, on: on)
final fromDigits = _decimalDigits[amount.currencyCode]
final toDigits = _decimalDigits[toCurrencyCode]
final fromApprox = fromLeg.quality == RateQuality.approximate
final toApprox = toLeg.quality == RateQuality.approximate
class RateLeg
const RateLeg({ required this.rate, required this.quotedOn, required this.quality, required this.rateRaw, })
final DateKey quotedOn
final RateQuality quality
class CrossRate
const CrossRate({ required this.rate, required this.quotedOn, required this.quality, })
typedef RateTableLoader = Future<RateTable> Function()
typedef RateSnapshotSaver = Future<void> Function(RateSnapshot snapshot)
typedef RateSnapshotFetcher = Future<RateSnapshot?> Function()
typedef NewestRateDateReader = Future<DateKey?> Function()
final class CurrencyRateService
const CurrencyRateService({ required RateTableLoader loadTable, required RateSnapshotSaver saveSnapshot, required RateSnapshotFetcher fetchSnapshot, required NewestRateDateReader newestCachedDate, required Clock clock, }) : _loadTable = loadTable
Future<RateTable> table()
Future<ConvertedMoney> toHome({ required Money amount, required DateKey on, required String homeCurrencyCode, }) async
final rates = await _loadTable()
Future<CrossRate?> rateOn({ required String from, required String to, required DateKey on, }) async
Future<void> syncDailyRates() async
final today = _clock.today()
final newest = await _newestCachedDate()
final snapshot = await _fetchSnapshot()
```

**`lib/domain/services/date_range_service.dart`**

```dart
typedef DateRange = ({DateKey from, DateKey to})
final class DateRangeService
const DateRangeService()
static final DateKey earliest = DateKey.fromYmd(1900, 1, 1)
DateRange? resolve(DateRangePreset preset, DateKey today)
switch (preset)
final year = today.month == 1 ? today.year - 1 : today.year
final month = today.month == 1 ? 12 : today.month - 1
DateRange wholeMonthOf(DateKey anyDayInMonth)
final year = anyDayInMonth.year
final month = anyDayInMonth.month
DateRange previousWholeMonth(DateKey anyDayInMonth)
final year = anyDayInMonth.month == 1 ? anyDayInMonth.year - 1 : anyDayInMonth.year
final month = anyDayInMonth.month == 1 ? 12 : anyDayInMonth.month - 1
DateRange precedingWindowOf(DateRange range)
final lengthDays = range.to.diffDays(range.from)
final end = range.from.addDays(-1)
bool contains(DateRange range, DateKey date)
int lengthInDays(DateRange range)
```

**`lib/domain/services/inventory_consumption_service.dart`**

```dart
class ConsumableBatch
const ConsumableBatch({ required this.batchId, required this.remaining, required this.purchasedDateKey, this.expiryDateKey, })
factory ConsumableBatch.fromBatch(Batch batch)
final String batchId
final Qty remaining
final DateKey purchasedDateKey
final DateKey? expiryDateKey
class ConsumptionPlan
const ConsumptionPlan({required this.draws, required this.totalAvailable})
final List<ConsumptionDraw> draws
final Qty totalAvailable
int get movementCount
Iterable<String> get touchedBatchIds => draws.map((d) => d.batchId)
final class InventoryConsumptionService
const InventoryConsumptionService()
List<ConsumableBatch> orderFefo(Iterable<ConsumableBatch> batches)
final ordered = batches.where((b) => b.remaining.isPositive).toList()
final aUndated = a.expiryDateKey == null
final bUndated = b.expiryDateKey == null
final byExpiry = DateKey.compare(a.expiryDateKey!, b.expiryDateKey!)
Result<ConsumptionPlan, Failure> plan({ required Iterable<ConsumableBatch> batches, required Qty needed, })
ValidationFailure('The quantity to consume must be greater than zero.', field: 'needed')
final ordered = orderFefo(batches)
ValidationFailure( 'Batch ${batch.batchId} is measured in ${batch.remaining.category.name}, not ' '${needed.category.name}.', field: 'needed', )
final availableMilli =
final available = Qty(availableMilli, needed.category)
BusinessRuleFailure( 'Not enough stock on hand to consume this quantity.', rule: 'insufficientStock', )
final draws = <ConsumptionDraw>[]
var remaining = needed.milliBase
final take = remaining < batch.remaining.milliBase ? remaining : batch.remaining.milliBase
ConsumptionDraw(batchId: batch.batchId, quantity: Qty(take, needed.category))
Result<ConsumptionPlan, Failure> planAll({ required Iterable<ConsumableBatch> batches, required Qty zeroOfCategory, })
final total = ordered.fold<int>(0, (sum, b) => sum + b.remaining.milliBase)
BusinessRuleFailure('There is nothing on hand to consume.', rule: 'insufficientStock')
```

**`lib/domain/services/low_stock_suggestion_engine.dart`**

```dart
enum SuggestionAction
class SuggestionDecision
const SuggestionDecision({ required this.itemId, required this.action, required this.reason, this.existingEntryId, this.suggestedQuantity, this.stockAtDecision, })
final String itemId
final SuggestionAction action
final String reason
final String? existingEntryId
final Qty? suggestedQuantity
final Qty? stockAtDecision
bool get requiresWrite
final class LowStockSuggestionEngine
const LowStockSuggestionEngine()
List<SuggestionDecision> decide({ required Iterable<ItemStock> lowStock, required Iterable<ShoppingEntry> existingAutoEntries, required DateKey today, })
final byItem = <String, ShoppingEntry>
final itemId = entry.itemId
final decisions = <SuggestionDecision>[]
final shortfall = stock.shortfall
final until = existing.snoozeUntilDateKey
final atDecision = existing.stockAtGeneration
final recovered = stock.totalRemaining.milliBase > atDecision.milliBase
```

**`lib/domain/services/purchase_fan_out_service.dart`**

```dart
enum FanOutTarget
class FanOutPlan
const FanOutPlan({ required this.lineId, required this.target, this.batch, this.asset, this.recurringTemplateName, })
const FanOutPlan.none(this.lineId)
batch = null
asset = null
recurringTemplateName = null
final String lineId
final FanOutTarget target
final Batch? batch
final Asset? asset
final String? recurringTemplateName
bool get createsArtefact
bool get isWellFormed
final count = [batch != null, asset != null, recurringTemplateName != null]
final class PurchaseFanOutService
const PurchaseFanOutService({Normalizer normalizer = const Normalizer()})
Result<FanOutPlan, Failure> plan({ required TransactionLine line, required Transaction transaction, required String newArtefactId, })
switch (line.destination)
FanOutPlan( lineId: line.id, target: FanOutTarget.recurringTemplate, recurringTemplateName: line.description, )
Result<List<FanOutPlan>, Failure> planAll({ required List<TransactionLine> lines, required Transaction transaction, required List<String> newArtefactIds, })
ValidationFailure( 'One artefact id is needed per line.', field: 'newArtefactIds', )
final plans = <FanOutPlan>[]
final line = lines[i]
final planned = plan( line: line, transaction: transaction, newArtefactId: newArtefactIds[i], )
final value = planned.valueOrNull!
final unitCode = line.unitCode
ValidationFailure( 'This line is marked for inventory but has no unit, so the stock it would create could ' 'not be measured.', field: 'unitCode', )
final itemId = line.itemId
ValidationFailure( 'An inventory line needs a catalogued item for its batch to belong to.', field: 'itemId', )
final quantity = line.quantity
ValidationFailure( 'An inventory line needs a quantity greater than zero.', field: 'quantity', )
final name = line.description.trim()
ValidationFailure('An asset line needs a description to name the asset.', field: 'description')
Qty? batchQuantityFor(TransactionLine line)
Money? assetPriceFor(TransactionLine line)
DateKey artefactDateFor(Transaction transaction)
```

**`lib/domain/services/recurring_engine.dart`**

```dart
class PlannedOccurrence
const PlannedOccurrence({required this.templateId, required this.dueDateKey})
final String templateId
final DateKey dueDateKey
class MaterialisationPlan
const MaterialisationPlan({ required this.templateId, required this.occurrences, required this.nextDueDateKey, required this.stoppedAtSafetyBound, })
final List<PlannedOccurrence> occurrences
final DateKey nextDueDateKey
final bool stoppedAtSafetyBound
bool get isEmpty
class SettlementIntent
const SettlementIntent({ required this.kind, required this.subtype, required this.amount, required this.dateKey, required this.fromAccountId, required this.toAccountId, required this.templateId, required this.occurrenceId, this.payeeId, this.tagId, this.note, })
final TransactionKind kind
final TransactionSubtype subtype
final Money amount
final DateKey dateKey
final String? fromAccountId
final String? toAccountId
final String occurrenceId
final String? payeeId
final String? tagId
final String? note
final class RecurringEngine
const RecurringEngine()
static const int maxOccurrencesPerPass = 240
DateKey nextDue({required DateKey from, required RecurringTemplate template})
final count = template.intervalCount
switch (template.intervalUnit)
final total = from.year * 12 + (from.month - 1) + count
final year = total ~/ 12
final month = total % 12 + 1
clampDayOfMonth(template.anchorDayOfMonth ?? from.day, year, month)
final year = from.year + count
clampDayOfMonth(template.anchorDayOfMonth ?? from.day, year, from.month)
int clampDayOfMonth(int day, int year, int month)
final lastDay = DateTime.utc(year, month + 1, 0).day
MaterialisationPlan planMaterialisation({ required RecurringTemplate template, required DateKey asOf, Iterable<DateKey> alreadyMaterialised = const [], })
final existing = alreadyMaterialised.map((d) => d.value).toSet()
final planned = <PlannedOccurrence>[]
var cursor = template.nextDueDateKey
var guard = 0
var hitBound = false
while (!cursor.isAfter(asOf))
hitBound = true
final end = template.endDateKey
cursor = nextDue(from: cursor, template: template)
bool isActive({required RecurringTemplate template, required DateKey asOf})
Result<SettlementIntent, Failure> planSettlement({ required RecurringTemplate template, required RecurringOccurrence occurrence, required Money amount, required DateKey paidOn, required String accountId, })
ValidationFailure('The amount paid must be greater than zero.', field: 'amount')
BusinessRuleFailure( 'This occurrence is already ${occurrence.status.name}.', rule: 'occurrenceNotDue', )
ValidationFailure( 'That occurrence belongs to a different template.', field: 'occurrence', )
ValidationFailure( 'This template is in ${template.defaultAmount.currencyCode}, so the payment cannot be ' 'in ${amount.currencyCode}.', field: 'amount', )
final isOutflow = template.direction == RecurringDirection.outflow
Result<void, Failure> planSkip(RecurringOccurrence occurrence)
BusinessRuleFailure( 'A settled occurrence cannot be skipped — unsettle it first.', rule: 'cannotSkipPaid', )
bool isOverdue({required RecurringOccurrence occurrence, required DateKey today})
```

**`lib/domain/services/stock_reconciler.dart`**

```dart
final class StockReconciler
const StockReconciler()
bool isIncoming(StockMovementKind kind)
int remainingFromLedgerMilli(Iterable<StockMovement> movements)
var total = 0
BatchReconciliation reconcile({ required String batchId, required Qty cached, required Iterable<StockMovement> movements, })
final fromLedgerMilli = remainingFromLedgerMilli(movements)
final category = cached.category
List<BatchReconciliation> discrepancies(Iterable<BatchReconciliation> reconciliations)
ReconciliationSummary summarise(Iterable<BatchReconciliation> reconciliations)
final all = reconciliations.toList()
final broken = discrepancies(all)
Qty zeroIn(UnitCategory category)
class ReconciliationSummary
const ReconciliationSummary({ required this.batchesChecked, required this.batchesNeedingRepair, this.largestDiscrepancy, })
final int batchesChecked
final int batchesNeedingRepair
final Qty? largestDiscrepancy
bool get isHealthy
```

**`lib/domain/services/unit_engine.dart`**

```dart
final class UnitEngine
const UnitEngine()
static const int milliPerBaseUnit = 1000
static const int maxFactorToBaseMilli = 1000000000
Result<int, Failure> amountInUnitMilli({ required Qty quantity, required Unit unit, })
BusinessRuleFailure( 'A ${quantity.category.name} quantity cannot be expressed in ${unit.code}, which ' 'measures ${unit.category.name}. There is no conversion between categories.', rule: 'crossCategoryConversion', )
ValidationFailure( 'Unit ${unit.code} has a non-positive factor and cannot be converted to.', field: 'factorToBaseMilli', )
final scaled = quantity.milliBase * milliPerBaseUnit
ValidationFailure( 'This quantity cannot be expressed exactly in ${unit.code}.', field: 'unit', )
int? amountInUnitMilliTruncating({ required Qty quantity, required Unit unit, })
Result<Qty, Failure> quantityFromUnit({ required int amountMilli, required Unit unit, })
ValidationFailure( 'Unit ${unit.code} has a non-positive factor.', field: 'factorToBaseMilli', )
final milliBase = amountMilli * unit.factorToBaseMilli ~/ milliPerBaseUnit
Result<int, Failure> convert({ required int amountMilli, required Unit from, required Unit to, })
BusinessRuleFailure( 'There is no conversion between ${from.category.name} and ${to.category.name}.', rule: 'crossCategoryConversion', )
final quantity = quantityFromUnit(amountMilli: amountMilli, unit: from)
Result<void, Failure> validateUserUnit({ required Unit unit, required Iterable<Unit> existingUnits, })
final code = unit.code.trim()
ValidationFailure('A unit code must be 12 characters or fewer.', field: 'code')
ValidationFailure('A unit needs a display name.', field: 'displayName')
ValidationFailure( 'A unit needs a positive factor to its category\'s base unit. If you cannot state one ' 'exactly, create a separate Item instead.', field: 'factorToBaseMilli', )
ValidationFailure( 'That factor is too large to convert safely.', field: 'factorToBaseMilli', )
final folded = code.toLowerCase()
ConflictFailure('A unit with the code "${existing.code}" already exists.')
```


### App — providers (the ONLY place a repository or engine is declared, U19)

**`lib/app/providers/infrastructure_providers.dart`**

```dart
BaseOptions( connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 10), sendTimeout: const Duration(seconds: 10), )
```

**`lib/app/providers/service_providers.dart`**

```dart
final dao = ref.watch(currencyDaoProvider)
final client = ref.watch(currencyApiClientProvider)
final clock = ref.watch(clockProvider)
final uids = ref.watch(uidGeneratorProvider)
```


### App — theme tokens and semantic colours

**`lib/app/theme/alaya_theme.dart`**

```dart
abstract final class AlayaTheme
static ThemeData light([AlayaPalette palette = AlayaPresets.activePreset])
static ThemeData dark([AlayaPalette palette = AlayaPresets.activePreset])
final colors = palette.forMode(isDark: isDark)
final scheme = _scheme(colors, isDark: isDark)
final text = _textTheme(colors)
final primary = colors.textPrimary
final secondary = colors.textSecondary
```

**`lib/app/theme/palettes/palette.dart`**

```dart
class AlayaPalette
const AlayaPalette({ required this.name, required this.description, required this.light, required this.dark, })
final String name
final String description
final AlayaColorSet light
final AlayaColorSet dark
AlayaColorSet forMode({required bool isDark})
class AlayaColorSet
final Color surfaceBase
final Color surfaceRaised
final Color surfaceOverlay
final Color surfaceSunken
final Color primary
final Color onPrimary
final Color accent
final Color onAccent
final Color textPrimary
final Color textSecondary
final Color textMuted
final Color divider
final Color income
final Color expense
final Color transfer
final Color warning
final Color danger
final Color success
final Color onStatus
```

**`lib/app/theme/palettes/presets.dart`**

```dart
abstract final class AlayaPresets
static const AlayaPalette activePreset = indigoKhata
static const List<AlayaPalette> all = [
```

**`lib/app/theme/semantic_colors.dart`**

```dart
class AlayaSemanticColors extends ThemeExtension<AlayaSemanticColors>
const AlayaSemanticColors({ required this.income, required this.expense, required this.transfer, required this.warning, required this.danger, required this.success, required this.muted, required this.onStatus, required this.surfaceBase, required this.surfaceRaised, required this.surfaceOverlay, required this.surfaceSunken, })
factory AlayaSemanticColors.fromColorSet(AlayaColorSet colors)
final Color income
final Color expense
final Color transfer
final Color warning
final Color danger
final Color success
final Color muted
final Color onStatus
final Color surfaceBase
final Color surfaceRaised
final Color surfaceOverlay
final Color surfaceSunken
Color forAmount(Money amount)
Color forTransactionKind(TransactionKind kind, Money amount)
kind == TransactionKind.transfer ? transfer : forAmount(amount)
Color surfaceForTier(int tier)
Map<String, Color> get byName
AlayaSemanticColors copyWith({ Color? income, Color? expense, Color? transfer, Color? warning, Color? danger, Color? success, Color? muted, Color? onStatus, Color? surfaceBase, Color? surfaceRaised, Color? surfaceOverlay, Color? surfaceSunken, })
AlayaSemanticColors lerp(AlayaSemanticColors? other, double t)
extension AlayaSemanticColorsContext on BuildContext
AlayaSemanticColors get semantic
final extension = Theme.of(this).extension<AlayaSemanticColors>()
```

**`lib/app/theme/tokens/alaya_durations.dart`**

```dart
abstract final class AlayaDurations
static const Duration fast = Duration(milliseconds: 120)
static const Duration base = Duration(milliseconds: 220)
static const Duration slow = Duration(milliseconds: 380)
static const Duration page = Duration(milliseconds: 300)
static const Duration shakeLeg = Duration(milliseconds: 90)
static const Duration snack = Duration(milliseconds: 2500)
static const Duration debounce = Duration(milliseconds: 300)
```

**`lib/app/theme/tokens/alaya_elevation.dart`**

```dart
abstract final class AlayaElevation
static const List<BoxShadow> none = []
static const List<BoxShadow> lightRaised = [
BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1))
BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 3))
static const List<BoxShadow> lightFloating = [
BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))
BoxShadow(color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 8))
static const List<BoxShadow> lightOverlay = [
BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, -4))
static const List<BoxShadow> darkRaised = [
BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1))
static const List<BoxShadow> darkFloating = [
BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3))
static const List<BoxShadow> darkOverlay = [
BoxShadow(color: Color(0x59000000), blurRadius: 20, offset: Offset(0, -2))
static List<BoxShadow> raised({required bool isDark})
static List<BoxShadow> floating({required bool isDark})
static List<BoxShadow> overlay({required bool isDark})
```

**`lib/app/theme/tokens/alaya_icon_size.dart`**

```dart
abstract final class AlayaIconSize
static const double sm = 16
static const double md = 20
static const double lg = 24
static const double xl = 40
```

**`lib/app/theme/tokens/alaya_radii.dart`**

```dart
abstract final class AlayaRadii
static const double xs = 4
static const double sm = 8
static const double md = 12
static const double lg = 20
static const double full = 999
static const BorderRadius borderXs = BorderRadius.all(Radius.circular(xs))
static const BorderRadius borderSm = BorderRadius.all(Radius.circular(sm))
static const BorderRadius borderMd = BorderRadius.all(Radius.circular(md))
static const BorderRadius borderLg = BorderRadius.all(Radius.circular(lg))
static const BorderRadius sheetTop = BorderRadius.only( topLeft: Radius.circular(lg), topRight: Radius.circular(lg), )
```

**`lib/app/theme/tokens/alaya_spacing.dart`**

```dart
abstract final class AlayaSpacing
static const double xxs = 4
static const double xs = 8
static const double sm = 12
static const double md = 16
static const double lg = 20
static const double xl = 24
static const double xxl = 32
static const double xxxl = 48
static const double screenEdge = md
static const double minTapTarget = 48
```

**`lib/app/theme/tokens/alaya_typography.dart`**

```dart
abstract final class AlayaTypography
static const List<FontFeature> figures = [FontFeature.tabularFigures()]
static const List<FontFeature> slashedZero = [
static const TextStyle displayAmount = TextStyle( fontSize: 40, fontWeight: FontWeight.w300, height: 1.1, // Negative tracking at display size: default tracking is set for body text and looks loose // once the glyphs are this large. letterSpacing: -1.2, fontFeatures: figures, )
static const TextStyle amountLarge = TextStyle( fontSize: 24, fontWeight: FontWeight.w500, height: 1.2, letterSpacing: -0.4, fontFeatures: figures, )
static const TextStyle amountMedium = TextStyle( fontSize: 16, fontWeight: FontWeight.w500, height: 1.25, letterSpacing: -0.1, fontFeatures: figures, )
static const TextStyle amountSmall = TextStyle( fontSize: 13, fontWeight: FontWeight.w400, height: 1.3, fontFeatures: figures, )
static const TextStyle quantity = TextStyle( fontSize: 15, fontWeight: FontWeight.w400, height: 1.3, fontFeatures: figures, )
static const TextStyle screenTitle = TextStyle( fontSize: 20, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: -0.2, )
static const TextStyle sectionHeader = TextStyle( fontSize: 13, fontWeight: FontWeight.w600, height: 1.2, // Positive tracking and upper case in the widget: at this size a header needs to read as a // label rather than as small body text, and tracking does that without another weight. letterSpacing: 0.8, )
static const TextStyle cardTitle = TextStyle( fontSize: 16, fontWeight: FontWeight.w600, height: 1.3, )
static const TextStyle body = TextStyle( fontSize: 15, fontWeight: FontWeight.w400, height: 1.45, )
static const TextStyle bodyEmphasis = TextStyle( fontSize: 15, fontWeight: FontWeight.w600, height: 1.45, )
static const TextStyle label = TextStyle( fontSize: 13, fontWeight: FontWeight.w500, height: 1.3, )
static const TextStyle caption = TextStyle( fontSize: 12, fontWeight: FontWeight.w400, height: 1.35, )
static const TextStyle overline = TextStyle( fontSize: 11, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: 0.6, )
static const TextStyle button = TextStyle( fontSize: 15, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: 0.1, )
static const Map<String, TextStyle> all =
```


### App — router

**`lib/app/router/app_router.dart`**

```dart
typedef LockGate = bool Function()
abstract final class AppRouter
static GoRouter build({ LockGate? isLocked, String initialLocation = Routes.initial, GlobalKey<NavigatorState>? navigatorKey, })
final locked = isLocked ?? ()
class _ShellScaffold extends StatelessWidget
final String location
final Widget child
Widget build(BuildContext context)
class _DetailScaffold extends StatelessWidget
final String title
```

**`lib/app/router/placeholder_screen.dart`**

```dart
class PlaceholderScreen extends StatelessWidget
const PlaceholderScreen({required this.owningPhase, super.key})
final String owningPhase
Widget build(BuildContext context)
final semantic = context.semantic
```

**`lib/app/router/routes.dart`**

```dart
abstract final class Routes
static const String initial = dashboard
static const String dashboard = '/'
static const String expenses = '/expenses'
static const String inventory = '/inventory'
static const String shopping = '/shopping'
static const String recurring = '/recurring'
static const String services = '/services'
static const String calendar = '/calendar'
static const String insights = '/insights'
static const String settings = '/settings'
static const String lock = '/lock'
static const String themeLab = '/settings/theme-lab'
static const String transactionNew = '/expenses/new'
static const String transactionLinesNew = '/expenses/new/lines'
static const String itemNew = '/inventory/new'
static const String recurringNew = '/recurring/new'
static const String assetNew = '/services/new'
static const String transactionDetailPattern = '/expenses/:transactionId'
static const String transactionEditPattern = '/expenses/:transactionId/edit'
static const String transactionLinesPattern = '/expenses/:transactionId/lines'
static const String itemDetailPattern = '/inventory/:itemId'
static const String itemEditPattern = '/inventory/:itemId/edit'
static const String batchNewPattern = '/inventory/:itemId/batch/new'
static const String batchEditPattern = '/inventory/:itemId/batch/:batchId'
static const String batchHistoryPattern = '/inventory/:itemId/batch/:batchId/history'
static const String shoppingListPattern = '/shopping/:listId'
static const String shoppingConvertPattern = '/shopping/:listId/convert'
static const String recurringEditPattern = '/recurring/:templateId/edit'
static const String recurringHistoryPattern = '/recurring/:templateId/history'
static const String recurringDetailPattern = '/recurring/:templateId'
static const String assetEditPattern = '/services/:assetId/edit'
static const String serviceNewPattern = '/services/:assetId/service/new'
static const String serviceEditPattern = '/services/:assetId/service/:recordId'
static const String assetDetailPattern = '/services/:assetId'
static const String calendarDayPattern = '/calendar/:dateKey'
static const String pTransactionId = 'transactionId'
static const String pItemId = 'itemId'
static const String pBatchId = 'batchId'
static const String pListId = 'listId'
static const String pTemplateId = 'templateId'
static const String pAssetId = 'assetId'
static const String pRecordId = 'recordId'
static const String pDateKey = 'dateKey'
static String transactionDetail(String id)
static String transactionEdit(String id)
static String transactionLines(String? id)
id == null ? transactionLinesNew : '$expenses/$id/lines'
static String itemDetail(String id)
static String itemEdit(String id)
static String batchNew(String itemId)
static String batchEdit(String itemId, String batchId)
static String batchHistory(String itemId, String batchId)
static String shoppingList(String id)
static String shoppingConvert(String id)
static String recurringDetail(String id)
static String recurringEdit(String? id)
id == null ? recurringNew : '$recurring/$id/edit'
static String recurringHistory(String id)
static String assetDetail(String id)
static String assetEdit(String? id)
static String serviceNew(String assetId)
static String serviceEdit(String assetId, String recordId)
static String calendarDay(int dateKey)
static const List<String> drawerDestinations = [
```


### Shared widgets and feedback

**`lib/shared/feedback/undo_snack.dart`**

```dart
ScaffoldMessenger.of(context)
SnackBar( content: Text(message), duration: AlayaDurations.snack, action: SnackBarAction(label: undoLabel, onPressed: onUndo), )
final semantic = context.semantic
SnackBar( content: Text(message, style: TextStyle(color: semantic.onStatus)), backgroundColor: semantic.danger, duration: AlayaDurations.snack, action: retryLabel == null || onRetry == null ? null : SnackBarAction( label: retryLabel, textColor: semantic.onStatus, onPressed: onRetry, ), )
```

**`lib/shared/widgets/account_picker.dart`**

```dart
class AccountPicker extends StatelessWidget
const AccountPicker({ required this.accounts, required this.selected, required this.onChanged, this.label, this.hint, this.errorText, this.excludeId, this.enabled = true, super.key, })
final List<Account> accounts
final Account? selected
final ValueChanged<Account> onChanged
final String? label
final String? hint
final String? errorText
final String? excludeId
final bool enabled
Widget build(BuildContext context)
final theme = Theme.of(context)
final eligible = accounts
Account? current
current = account
DropdownMenuItem( value: account, child: Row( children: [ Expanded( child: Text( account.name, maxLines: 1, overflow: TextOverflow.ellipsis, ), ), Text( account.currencyCode, style: AlayaTypography.caption.copyWith( color: theme.colorScheme.onSurfaceVariant, ), ), ], ), )
```

**`lib/shared/widgets/alaya_bottom_sheet.dart`**

```dart
class AlayaBottomSheet extends StatelessWidget
const AlayaBottomSheet({required this.child, this.padding = defaultPadding, super.key})
final Widget child
final EdgeInsetsGeometry padding
static const EdgeInsets defaultPadding = EdgeInsets.fromLTRB( AlayaSpacing.screenEdge, AlayaSpacing.xs, AlayaSpacing.screenEdge, AlayaSpacing.md, )
EdgeInsetsGeometry padding = defaultPadding
bool isDismissible = true
bool enableDrag = true
Widget build(BuildContext context)
```

**`lib/shared/widgets/alaya_card.dart`**

```dart
class AlayaCard extends StatelessWidget
const AlayaCard({ required this.child, this.tier = 1, this.padding = const EdgeInsets.all(AlayaSpacing.md), this.onTap, this.onLongPress, this.border = false, this.semanticsLabel, super.key, })
final Widget child
final int tier
final EdgeInsetsGeometry padding
final VoidCallback? onTap
final VoidCallback? onLongPress
final bool border
final String? semanticsLabel
Widget build(BuildContext context)
final theme = Theme.of(context)
final semantic = context.semantic
final isDark = theme.brightness == Brightness.dark
final interactive = onTap != null || onLongPress != null
final shape = RoundedRectangleBorder( borderRadius: AlayaRadii.borderMd, side: border ? BorderSide(color: theme.dividerColor) : BorderSide.none, )
final content = Padding(padding: padding, child: child)
final surface = Material( color: semantic.surfaceForTier(tier), shape: shape, clipBehavior: Clip.antiAlias, child: interactive ? InkWell(onTap: onTap, onLongPress: onLongPress, child: content) : content, )
final card = DecoratedBox( decoration: BoxDecoration( borderRadius: AlayaRadii.borderMd, // No shadow on a sunken tier: a well does not cast one. boxShadow: tier <= 0 ? AlayaElevation.none : AlayaElevation.raised(isDark: isDark), ), child: surface, )
```

**`lib/shared/widgets/alaya_drawer.dart`**

```dart
class AlayaDrawer extends StatelessWidget
const AlayaDrawer({required this.currentLocation, super.key})
final String currentLocation
static String titleFor(BuildContext context, String location)
final strings = AlayaStrings.of(context)
static IconData iconFor(String location)
Widget build(BuildContext context)
final theme = Theme.of(context)
final selected = _rootOf(currentLocation)
class _DrawerRow extends StatelessWidget
final String destination
final bool selected
final VoidCallback onTap
```

**`lib/shared/widgets/alaya_expandable_fab.dart`**

```dart
class FabAction
const FabAction({required this.label, required this.icon, required this.onPressed})
final String label
final IconData icon
final VoidCallback onPressed
class AlayaExpandableFab extends StatefulWidget
const AlayaExpandableFab({ required this.actions, required this.openLabel, required this.closeLabel, super.key, })
final List<FabAction> actions
final String openLabel
final String closeLabel
State<AlayaExpandableFab> createState()
class _AlayaExpandableFabState extends State<AlayaExpandableFab> with SingleTickerProviderStateMixin
AnimationController(duration: AlayaDurations.slow, vsync: this)
setState(() => _expanded = true)
setState(() => _expanded = false)
void dispose()
Widget build(BuildContext context)
class _ActionRow extends StatelessWidget
final FabAction action
final VoidCallback onTap
final theme = Theme.of(context)
```

**`lib/shared/widgets/alaya_form_scaffold.dart`**

```dart
class AlayaFormScaffold extends StatelessWidget
final Widget child
final String primaryLabel
final VoidCallback? onPrimary
final String discardTitle
final String discardBody
final String discardConfirmLabel
final String discardCancelLabel
final String? secondaryLabel
final VoidCallback? onSecondary
final bool isDirty
final bool isSubmitting
final EdgeInsetsGeometry padding
final navigator = Navigator.of(context)
final discard = await ConfirmSheet.show( context, title: discardTitle, body: discardBody, confirmLabel: discardConfirmLabel, cancelLabel: discardCancelLabel, destructive: true, )
Widget build(BuildContext context)
final blocked = isDirty || isSubmitting
unawaited(_confirmDiscard(context))
Expanded( child: SingleChildScrollView( padding: padding, child: child, ), )
class _FormFooter extends StatelessWidget
final theme = Theme.of(context)
final secondary = secondaryLabel
final primary = FilledButton( onPressed: onPrimary, child: isSubmitting ? SizedBox( width: AlayaSpacing.lg, height: AlayaSpacing.lg, child: CircularProgressIndicator( strokeWidth: 2, color: theme.colorScheme.onPrimary, ), ) : Text(primaryLabel), )
```

**`lib/shared/widgets/alaya_list_skeleton.dart`**

```dart
class AlayaListSkeleton extends StatelessWidget
const AlayaListSkeleton({ required this.label, this.rows = 5, this.hasLeading = true, this.hasTrailing = true, super.key, })
final String label
final int rows
final bool hasLeading
final bool hasTrailing
Widget build(BuildContext context)
class _SkeletonRow extends StatelessWidget
final double titleFactor
class _Block extends StatelessWidget
final double height
final double? width
final bool rounded
```

**`lib/shared/widgets/alaya_search_field.dart`**

```dart
class AlayaSearchField extends StatefulWidget
const AlayaSearchField({ required this.onChanged, required this.clearLabel, this.hintText, this.initialValue, this.autofocus = false, super.key, })
final ValueChanged<String> onChanged
final String clearLabel
final String? hintText
final String? initialValue
final bool autofocus
State<AlayaSearchField> createState()
class _AlayaSearchFieldState extends State<AlayaSearchField>
TextEditingController(text: widget.initialValue ?? '')
void initState()
final nowHasText = raw.isNotEmpty
setState(() => _hasText = false)
void dispose()
Widget build(BuildContext context)
```

**`lib/shared/widgets/alaya_timeline.dart`**

```dart
enum TimelineTone
class AlayaTimelineEntry
const AlayaTimelineEntry({ required this.title, required this.trailing, this.subtitle, this.meta, this.icon, this.tone = TimelineTone.neutral, this.badge, this.onTap, })
final String title
final Widget trailing
final Widget? subtitle
final String? meta
final IconData? icon
final TimelineTone tone
final String? badge
final VoidCallback? onTap
class AlayaTimeline extends StatelessWidget
const AlayaTimeline({ required this.itemCount, required this.itemBuilder, super.key, })
final int itemCount
final AlayaTimelineEntry Function(BuildContext context, int index) itemBuilder
Widget build(BuildContext context)
class _Entry extends StatelessWidget
final AlayaTimelineEntry entry
final bool isFirst
final bool isLast
final theme = Theme.of(context)
final semantic = context.semantic
final colour = _toneColour(semantic)
final superseded = entry.tone == TimelineTone.superseded
final onTap = entry.onTap
class _Rail extends StatelessWidget
final Color colour
class _Line extends StatelessWidget
final bool visible
final double? height
class _Badge extends StatelessWidget
final String label
```

**`lib/shared/widgets/amount_field.dart`**

```dart
class AmountField extends StatefulWidget
const AmountField({ required this.currencyCode, required this.onChanged, this.decimalDigits = 2, this.initialValue, this.label, this.hint, this.errorText, this.allowNegative = false, this.autofocus = false, this.controller, super.key, })
final String currencyCode
final ValueChanged<Money?> onChanged
final int decimalDigits
final Money? initialValue
final String? label
final String? hint
final String? errorText
final bool allowNegative
final bool autofocus
final TextEditingController? controller
State<AmountField> createState()
class _AmountFieldState extends State<AmountField>
widget.controller ?? TextEditingController(text: _initialText())
final initial = widget.initialValue
final divisor = _pow10(widget.decimalDigits)
final sign = initial.isNegative ? '-' : ''
final magnitude = initial.minor.abs()
final whole = magnitude ~/ divisor
final fraction = (magnitude % divisor).toString().padLeft(widget.decimalDigits, '0')
var result = 1
setState(() => _failure = null)
final result = _parser.parse( raw, currencyCode: widget.currencyCode, decimalDigits: widget.decimalDigits, allowNegative: widget.allowNegative, )
setState(() => _failure = result.failureOrNull)
final failure = _failure
final strings = AlayaStrings.of(context)
void dispose()
Widget build(BuildContext context)
```

**`lib/shared/widgets/amount_text.dart`**

```dart
enum AmountSize
class AmountText extends StatelessWidget
const AmountText( this.amount, { this.size = AmountSize.medium, this.decimalDigits = 2, this.symbol, this.kind, this.showSign = true, this.muted = false, this.textAlign, super.key, })
final Money amount
final AmountSize size
final int decimalDigits
final String? symbol
final TransactionKind? kind
final bool showSign
final bool muted
final TextAlign? textAlign
Widget build(BuildContext context)
final semantic = context.semantic
final color = muted
```

**`lib/shared/widgets/confirm_sheet.dart`**

```dart
class ConfirmSheet extends StatelessWidget
const ConfirmSheet({ required this.title, required this.body, required this.confirmLabel, required this.cancelLabel, this.destructive = false, super.key, })
final String title
final String body
final String confirmLabel
final String cancelLabel
final bool destructive
static Future<bool> show( BuildContext context, { required String title, required String body, required String confirmLabel, required String cancelLabel, bool destructive = false, }) async
final result = await AlayaBottomSheet.show<bool>( context: context, builder: (context) => ConfirmSheet( title: title, body: body, confirmLabel: confirmLabel, cancelLabel: cancelLabel, destructive: destructive, ), )
Widget build(BuildContext context)
final theme = Theme.of(context)
final semantic = context.semantic
```

**`lib/shared/widgets/date_picker_field.dart`**

```dart
class DatePickerField extends StatelessWidget
const DatePickerField({ required this.value, required this.onChanged, required this.formatted, this.label, this.hint, this.errorText, this.firstDate, this.lastDate, this.enabled = true, super.key, })
final DateKey? value
final ValueChanged<DateKey> onChanged
final String Function(DateKey) formatted
final String? label
final String? hint
final String? errorText
final DateKey? firstDate
final DateKey? lastDate
final bool enabled
final now = DateTime.now()
final initial = value?.toUtcMidnight() ?? now
final picked = await showDatePicker( context: context, initialDate: initial, firstDate: firstDate?.toUtcMidnight() ?? DateTime(now.year - 10), lastDate: lastDate?.toUtcMidnight() ?? DateTime(now.year + 5), )
Widget build(BuildContext context)
final current = value
```

**`lib/shared/widgets/date_text.dart`**

```dart
enum DateTextStyle
class DateText extends StatelessWidget
const DateText( this.date, { this.style = DateTextStyle.medium, this.textStyle, this.muted = false, this.textAlign, super.key, }) : _clock = null
const DateText.relative( this.date, { required Clock clock, this.textStyle, this.muted = false, this.textAlign, super.key, }) : style = DateTextStyle.relative
final DateKey date
final DateTextStyle style
final TextStyle? textStyle
final bool muted
final TextAlign? textAlign
Widget build(BuildContext context)
final semantic = context.semantic
final localeTag = Localizations.localeOf(context).toString()
final moment = date.toUtcMidnight()
final clock = _clock
final strings = AlayaStrings.of(context)
switch (date.diffDays(clock.today()))
```

**`lib/shared/widgets/empty_state.dart`**

```dart
class EmptyState extends StatelessWidget
const EmptyState({ required this.title, required this.body, this.icon, this.actionLabel, this.onAction, super.key, })
final String title
final String body
final IconData? icon
final String? actionLabel
final VoidCallback? onAction
Widget build(BuildContext context)
final theme = Theme.of(context)
final semantic = context.semantic
```

**`lib/shared/widgets/error_state.dart`**

```dart
class ErrorState extends StatelessWidget
const ErrorState({ required this.title, required this.body, this.retryLabel, this.onRetry, super.key, })
final String title
final String body
final String? retryLabel
final VoidCallback? onRetry
Widget build(BuildContext context)
final theme = Theme.of(context)
final semantic = context.semantic
```

**`lib/shared/widgets/filter_chip_bar.dart`**

```dart
class ActiveFilter
const ActiveFilter({required this.label, required this.onRemove})
final String label
final VoidCallback onRemove
class FilterChipBar extends StatelessWidget
const FilterChipBar({ required this.filters, this.onClearAll, this.clearAllLabel, super.key, })
final List<ActiveFilter> filters
final VoidCallback? onClearAll
final String? clearAllLabel
Widget build(BuildContext context)
final showClearAll = onClearAll != null && clearAllLabel != null && filters.length > 1
class _FilterChip extends StatelessWidget
final ActiveFilter filter
final theme = Theme.of(context)
```

**`lib/shared/widgets/frequency_preview.dart`**

```dart
class PreviewedDate
const PreviewedDate({required this.dateKey, this.clamped = false})
final DateKey dateKey
final bool clamped
class FrequencyPreview extends StatelessWidget
const FrequencyPreview({required this.dates, super.key})
final List<PreviewedDate> dates
Widget build(BuildContext context)
final strings = AlayaStrings.of(context)
final semantic = context.semantic
```

**`lib/shared/widgets/key_value_row.dart`**

```dart
class KeyValueRow extends StatelessWidget
const KeyValueRow({ required this.label, this.value, this.valueWidget, this.onTap, this.icon, super.key, })
final String label
final String? value
final Widget? valueWidget
final VoidCallback? onTap
final IconData? icon
Widget build(BuildContext context)
final rendered = valueWidget
final theme = Theme.of(context)
final semantic = context.semantic
```

**`lib/shared/widgets/loading_state.dart`**

```dart
class LoadingState extends StatelessWidget
const LoadingState({required this.label, this.compact = false, super.key})
final String label
final bool compact
Widget build(BuildContext context)
final theme = Theme.of(context)
final indicator = SizedBox( width: AlayaSpacing.xl, height: AlayaSpacing.xl, child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: label), )
```

**`lib/shared/widgets/qty_field.dart`**

```dart
class QtyField extends StatefulWidget
const QtyField({ required this.category, required this.units, required this.selectedUnit, required this.onChanged, required this.onUnitChanged, this.initialValue, this.label, this.hint, this.errorText, this.unitLabel, super.key, })
final UnitCategory category
final List<Unit> units
final Unit? selectedUnit
final ValueChanged<Qty?> onChanged
final ValueChanged<Unit> onUnitChanged
final Qty? initialValue
final String? label
final String? hint
final String? errorText
final String? unitLabel
State<QtyField> createState()
class _QtyFieldState extends State<QtyField>
final initial = widget.initialValue
final unit = widget.selectedUnit
setState(() => _failure = null)
final result = _parser.parse( raw, category: widget.category, factorToBaseMilli: unit.factorToBaseMilli, )
setState(() => _failure = result.failureOrNull)
final failure = _failure
final strings = AlayaStrings.of(context)
void dispose()
Widget build(BuildContext context)
```

**`lib/shared/widgets/qty_text.dart`**

```dart
class QtyText extends StatelessWidget
const QtyText( this.quantity, { this.style = UnitStyle.mixed, this.muted = false, this.textStyle, this.textAlign, super.key, })
final Qty quantity
final UnitStyle style
final bool muted
final TextStyle? textStyle
final TextAlign? textAlign
Widget build(BuildContext context)
final semantic = context.semantic
```

**`lib/shared/widgets/scroll_safe_center.dart`**

```dart
class ScrollSafeCenter extends StatelessWidget
const ScrollSafeCenter({required this.child, this.padding = EdgeInsets.zero, super.key})
final Widget child
final EdgeInsetsGeometry padding
Widget build(BuildContext context)
```

**`lib/shared/widgets/section_header.dart`**

```dart
class SectionHeader extends StatelessWidget
const SectionHeader({ required this.label, this.trailing, this.padding = const EdgeInsets.only( left: AlayaSpacing.screenEdge, right: AlayaSpacing.screenEdge, top: AlayaSpacing.xl, bottom: AlayaSpacing.xs, ), super.key, })
final String label
final Widget? trailing
final EdgeInsetsGeometry padding
Widget build(BuildContext context)
final theme = Theme.of(context)
```

**`lib/shared/widgets/shake_on_error.dart`**

```dart
class ShakeOnError extends StatefulWidget
const ShakeOnError({ required this.trigger, required this.child, this.distance = 10, super.key, })
final int trigger
final Widget child
final double distance
State<ShakeOnError> createState()
class _ShakeOnErrorState extends State<ShakeOnError> with SingleTickerProviderStateMixin
void didUpdateWidget(ShakeOnError oldWidget)
void dispose()
Widget build(BuildContext context)
```

**`lib/shared/widgets/status_chip.dart`**

```dart
enum StatusTone
class StatusChip extends StatelessWidget
const StatusChip({ required this.label, this.tone = StatusTone.neutral, this.icon, this.trailing, this.onTap, super.key, })
final String label
final StatusTone tone
final IconData? icon
final Widget? trailing
final VoidCallback? onTap
Widget build(BuildContext context)
final semantic = context.semantic
final foreground = switch (tone)
final shape = RoundedRectangleBorder( borderRadius: AlayaRadii.borderXs, side: BorderSide(color: foreground.withValues(alpha: 0.28)), )
final background = foreground.withValues(alpha: 0.12)
```

**`lib/shared/widgets/tag_chip.dart`**

```dart
class TagChip extends StatelessWidget
const TagChip({ required this.tag, this.selected = false, this.onTap, this.onRemove, this.removeLabel, super.key, })
final Tag tag
final bool selected
final VoidCallback? onTap
final VoidCallback? onRemove
final String? removeLabel
Widget build(BuildContext context)
final theme = Theme.of(context)
final semantic = context.semantic
final dotColor = tag.colorArgb == null ? null : Color(tag.colorArgb!)
final background = selected ? theme.colorScheme.primary : semantic.surfaceSunken
final foreground = selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant
final shape = RoundedRectangleBorder( borderRadius: AlayaRadii.borderXs, side: selected ? BorderSide.none : BorderSide(color: theme.dividerColor), )
class _Dot extends StatelessWidget
final Color color
```

**`lib/shared/widgets/tag_picker.dart`**

```dart
class TagPicker extends StatelessWidget
const TagPicker({ required this.available, required this.selectedIds, required this.scope, required this.onToggle, this.label, this.emptyLabel, super.key, })
final List<Tag> available
final Set<String> selectedIds
final TagScope scope
final ValueChanged<String> onToggle
final String? label
final String? emptyLabel
Widget build(BuildContext context)
final theme = Theme.of(context)
final eligible = available
final aSelected = selectedIds.contains(a.id)
final bSelected = selectedIds.contains(b.id)
```

**`lib/shared/widgets/unit_picker.dart`**

```dart
class UnitPicker extends StatelessWidget
const UnitPicker({ required this.category, required this.units, required this.selected, required this.onChanged, this.label, this.enabled = true, super.key, })
final UnitCategory category
final List<Unit> units
final Unit? selected
final ValueChanged<Unit> onChanged
final String? label
final bool enabled
Widget build(BuildContext context)
final eligible = units.where((unit) => unit.category == category).toList()
Unit? current
current = unit
DropdownMenuItem( value: unit, child: Text(unit.displayName, maxLines: 1, overflow: TextOverflow.ellipsis), )
```


### Feature — expense (6A)

**`lib/features/expense/presentation/screens/line_items_screen.dart`**

```dart
class LineItemsScreen extends ConsumerWidget
const LineItemsScreen({this.transactionId, super.key})
final String? transactionId
final notifier = ref.read(transactionEditorProvider(transactionId).notifier)
var another = true
while (another && context.mounted)
final draft = await LineItemEditor.show( context, currencyCode: state.currencyCode, decimalDigits: digits, defaultDestination: TransactionLineDestination.none, )
another = draft.addAnother
final draft = await LineItemEditor.show( context, currencyCode: state.currencyCode, decimalDigits: digits, defaultDestination: line.destination, line: line, )
final strings = AlayaStrings.of(context)
showResultSnack(context, message: strings.lineRemoved)
Widget build(BuildContext context, WidgetRef ref)
final async = ref.watch(transactionEditorProvider(transactionId))
final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2
class _Summary extends StatelessWidget
final TransactionEditorState state
final int decimalDigits
Widget build(BuildContext context)
final semantic = context.semantic
final unallocated = state.unallocated
final allocated = state.lineTotal
class _LineTile extends StatelessWidget
final TransactionLine line
final VoidCallback onTap
final VoidCallback onRemove
final amount = line.lineAmount
final quantity = line.quantity
```

**`lib/features/expense/presentation/screens/transaction_detail_screen.dart`**

```dart
class TransactionDetailScreen extends ConsumerWidget
const TransactionDetailScreen({required this.transactionId, super.key})
final String transactionId
final strings = AlayaStrings.of(context)
final reason = await DeleteTransactionSheet.show(context)
final detached =
showFailureSnack(context, message: strings.errorBodyGeneric)
showResultSnack(context, message: strings.transactionDeleted)
final code = await FreezeConversionSheet.show( context, excludeCode: transaction.originalAmount.currencyCode, )
final ok = await ref.read(transactionActionsProvider).freezeConversion( transaction: transaction, toCurrencyCode: code, )
? showResultSnack(context, message: strings.actionSaved)
Widget build(BuildContext context, WidgetRef ref)
final async = ref.watch(transactionByIdProvider(transactionId))
class _Body extends ConsumerWidget
final Transaction transaction
final VoidCallback onDelete
final VoidCallback onFreeze
final semantic = context.semantic
final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2
final accounts = ref.watch(accountsByIdProvider).valueOrNull ?? const <String, Account>
final payees = ref.watch(payeesByIdProvider).valueOrNull ?? const <String, Payee>
final methods =
final tags = ref.watch(transactionTagsProvider(transaction.id)).valueOrNull ?? const []
final allocation = ref.watch(transactionAllocationProvider(transaction.id)).valueOrNull
final lines = ref.watch(transactionLinesProvider(transaction.id))
final clock = ref.watch(clockProvider)
final from = transaction.fromAccountId
final to = transaction.toAccountId
final payeeId = transaction.payeeId
final methodId = transaction.paymentMethodId
final frozen = transaction.frozenConversion
class _LineRow extends StatelessWidget
final TransactionLine line
final int decimalDigits
final itemId = line.itemId
final assetId = line.createdAssetId
final templateId = line.createdRecurringTemplateId
Widget build(BuildContext context)
final theme = Theme.of(context)
final route = _artefactRoute()
final quantity = line.quantity
final amount = line.lineAmount
```

**`lib/features/expense/presentation/screens/transaction_editor_screen.dart`**

```dart
class TransactionEditorScreen extends ConsumerWidget
const TransactionEditorScreen({this.transactionId, super.key})
final String? transactionId
final strings = AlayaStrings.of(context)
final saved = await ref.read(transactionEditorProvider(transactionId).notifier).save()
final why = ref.read(transactionEditorProvider(transactionId)).valueOrNull?.saveError
showFailureSnack(context, message: why ?? strings.errorBodyGeneric)
final after = ref.read(transactionEditorProvider(transactionId)).valueOrNull
final fanOutError = after?.fanOutError
final createdAsset = after?.createdAssetId
final router = GoRouter.of(context)
final target = Routes.assetEdit(createdAsset)
showResultSnack( context, message: strings.assetCreatedFromPurchase, actionLabel: strings.actionSetWarranty, onAction: () => router.push(target), )
showResultSnack(context, message: strings.recurringScheduleNext)
? showFailureSnack(context, message: fanOutError)
Widget build(BuildContext context, WidgetRef ref)
final async = ref.watch(transactionEditorProvider(transactionId))
class _Form extends ConsumerWidget
final String? editorId
final TransactionEditorState state
final notifier = ref.read(transactionEditorProvider(editorId).notifier)
final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2
final accounts = ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[]
final methods = ref.watch(editorPaymentMethodsProvider).valueOrNull ?? const <PaymentMethod>[]
final tags = ref.watch(editorTagsProvider(state.kind)).valueOrNull ?? const <Tag>[]
final localeTag = Localizations.localeOf(context).toString()
Account? accountFor(String? id)
class _SubtypeForm extends StatelessWidget
final int decimalDigits
Widget build(BuildContext context)
DepositForm(editorId: editorId, state: state)
TransferForm(editorId: editorId, state: state)
```

**`lib/features/expense/presentation/screens/transaction_list_screen.dart`**

```dart
class TransactionListScreen extends ConsumerWidget
const TransactionListScreen({super.key})
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final searching = ref.watch(isSearchingProvider)
class _Toolbar extends ConsumerWidget
final narrowed = ref.watch(transactionFilterProvider).isNarrowed
final semantic = context.semantic
class _NeedsReviewRow extends ConsumerWidget
final filter = ref.watch(transactionFilterProvider)
final count = ref.watch(needsReviewCountProvider).valueOrNull ?? 0
class _ActiveFilters extends ConsumerWidget
final notifier = ref.read(transactionFilterProvider.notifier)
final accounts = ref.watch(accountsByIdProvider).valueOrNull ?? const <String, Account>
final payees = ref.watch(payeesByIdProvider).valueOrNull ?? const <String, Payee>
class _GroupedList extends ConsumerWidget
final days = ref.watch(transactionDaysProvider)
final clock = ref.watch(clockProvider)
final background = Theme.of(context).scaffoldBackgroundColor
class _SearchResults extends ConsumerWidget
final results = ref.watch(transactionSearchResultsProvider)
? EmptyState( title: strings.emptyTitleNoResults, body: strings.emptyBodyNoResults, icon: Icons.search_off_outlined, )
class _Row extends ConsumerWidget
final Transaction transaction
final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2
final from = transaction.fromAccountId
final to = transaction.toAccountId
final payeeId = transaction.payeeId
class _DayHeader extends SliverPersistentHeaderDelegate
final DateKey date
final Clock clock
final Color background
double get minExtent
double get maxExtent
Widget build(BuildContext context, double shrinkOffset, bool overlapsContent)
bool shouldRebuild(_DayHeader oldDelegate)
```

**`lib/features/expense/presentation/sheets/delete_transaction_sheet.dart`**

```dart
class DeleteTransactionSheet extends StatefulWidget
const DeleteTransactionSheet({super.key})
static Future<String?> show(BuildContext context)
State<DeleteTransactionSheet> createState()
class _DeleteTransactionSheetState extends State<DeleteTransactionSheet>
void dispose()
Widget build(BuildContext context)
final strings = AlayaStrings.of(context)
final theme = Theme.of(context)
```

**`lib/features/expense/presentation/sheets/freeze_conversion_sheet.dart`**

```dart
class FreezeConversionSheet extends ConsumerWidget
const FreezeConversionSheet({required this.excludeCode, super.key})
final String excludeCode
static Future<String?> show(BuildContext context, {required String excludeCode})
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final theme = Theme.of(context)
final currencies = ref.watch(enabledCurrenciesProvider)
```

**`lib/features/expense/presentation/sheets/line_item_editor.dart`**

```dart
class LineItemDraft
const LineItemDraft({required this.line, this.addAnother = false})
final TransactionLine line
final bool addAnother
class LineItemEditor extends ConsumerStatefulWidget
const LineItemEditor({ required this.currencyCode, required this.decimalDigits, required this.defaultDestination, this.line, super.key, })
final String currencyCode
final int decimalDigits
final TransactionLineDestination defaultDestination
final TransactionLine? line
static Future<LineItemDraft?> show( BuildContext context, { required String currencyCode, required int decimalDigits, required TransactionLineDestination defaultDestination, TransactionLine? line, })
ConsumerState<LineItemEditor> createState()
class _LineItemEditorState extends ConsumerState<LineItemEditor>
TextEditingController(text: widget.line?.description ?? '')
final name = _description.text.trim()
setState(() => _descriptionMissing = true)
final item = Item( id: ref.read(uidGeneratorProvider).generate(), name: name, normalizedName: ref.read(normalizerProvider).normalize(name), unitCategory: _newItemCategory, defaultDisplayUnitCode: _newItemCategory.baseUnitCode, itemKind: ItemKind.generic, isFavorite: false, )
final saved = await ref.read(itemRepositoryProvider).save(item)
final value = saved.valueOrNull
setState(() { _createFailed = value == null; if (value == null) return; _itemId = value.id; _creatingItem = false; _unitCode = value.defaultDisplayUnitCode; _quantity = null; })
void dispose()
final description = _description.text.trim()
final existing = widget.line
Widget build(BuildContext context)
final strings = AlayaStrings.of(context)
final theme = Theme.of(context)
final items = ref.watch(lineEditorItemsProvider).valueOrNull ?? const <Item>[]
Item? selectedItem
selectedItem = item
final units =
Unit? selectedUnit
switch (category)
switch (destination)
class _NewItemRow extends StatelessWidget
final UnitCategory category
final ValueChanged<UnitCategory> onCategoryChanged
final VoidCallback onCreate
final VoidCallback onCancel
```

**`lib/features/expense/presentation/sheets/quick_add_sheet.dart`**

```dart
class QuickAddSheet extends ConsumerWidget
const QuickAddSheet({super.key})
static Future<void> show(BuildContext context)
final strings = AlayaStrings.of(context)
final navigator = Navigator.of(context)
final messengerContext = context
final created = await ref.read(quickAddProvider.notifier).submit()
showUndoSnack( messengerContext, message: strings.actionSaved, undoLabel: strings.actionUndo, onUndo: () => ref.read(quickAddProvider.notifier).undo(created.id), )
Widget build(BuildContext context, WidgetRef ref)
final theme = Theme.of(context)
final state = ref.watch(quickAddProvider)
final notifier = ref.read(quickAddProvider.notifier)
final currency = ref.watch(homeCurrencyCodeProvider).valueOrNull ?? 'INR'
final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2
final accounts = ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[]
final tags = ref.watch(quickAddTagsProvider).valueOrNull ?? const <Tag>[]
class _ChipRow extends StatelessWidget
final String label
final List<Widget> children
Widget build(BuildContext context)
class _Choice extends StatelessWidget
final bool selected
final VoidCallback onTap
```

**`lib/features/expense/presentation/widgets/line_items_section.dart`**

```dart
class LineItemsSection extends ConsumerWidget
const LineItemsSection({ required this.editorId, required this.state, required this.decimalDigits, this.defaultDestination = TransactionLineDestination.inventory, super.key, })
final String? editorId
final TransactionEditorState state
final int decimalDigits
final TransactionLineDestination defaultDestination
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final semantic = context.semantic
final notifier = ref.read(transactionEditorProvider(editorId).notifier)
final unallocated = state.unallocated
```

**`lib/features/expense/presentation/widgets/needs_review_banner.dart`**

```dart
class NeedsReviewBanner extends StatelessWidget
const NeedsReviewBanner({ required this.count, required this.onTap, super.key, })
final int count
final VoidCallback onTap
Widget build(BuildContext context)
final theme = Theme.of(context)
final semantic = context.semantic
final strings = AlayaStrings.of(context)
final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5
final message = Text( strings.needsReviewBanner(count), style: AlayaTypography.body.copyWith(color: theme.colorScheme.onSurface), )
final action = Text( strings.needsReviewAction, style: AlayaTypography.button.copyWith(color: semantic.transfer), )
final leading = Icon( Icons.edit_note, size: AlayaIconSize.md, color: semantic.transfer, )
```

**`lib/features/expense/presentation/widgets/payee_field.dart`**

```dart
class PayeeField extends ConsumerStatefulWidget
const PayeeField({required this.editorId, required this.selectedId, super.key})
final String? editorId
final String? selectedId
ConsumerState<PayeeField> createState()
class _PayeeFieldState extends ConsumerState<PayeeField>
void dispose()
final name = _newName.text.trim()
final strings = AlayaStrings.of(context)
final created =
showFailureSnack(context, message: strings.errorBodyGeneric)
setState(() => _creating = false)
Widget build(BuildContext context)
final payees = ref.watch(editorPayeesProvider).valueOrNull ?? const <Payee>[]
final notifier = ref.read(transactionEditorProvider(widget.editorId).notifier)
Payee? current
current = payee
```

**`lib/features/expense/presentation/widgets/subtype_forms/bill_form.dart`**

```dart
class BillForm extends ConsumerWidget
const BillForm({required this.editorId, required this.state, super.key})
final String? editorId
final TransactionEditorState state
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final semantic = context.semantic
final notifier = ref.read(transactionEditorProvider(editorId).notifier)
final due = ref.watch(dueBillsProvider)
final today = ref.watch(clockProvider).today()
final digits = ref.watch(builderDecimalDigitsProvider).valueOrNull ?? 2
```

**`lib/features/expense/presentation/widgets/subtype_forms/deposit_form.dart`**

```dart
class DepositForm extends ConsumerWidget
const DepositForm({required this.editorId, required this.state, super.key})
final String? editorId
final TransactionEditorState state
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final notifier = ref.read(transactionEditorProvider(editorId).notifier)
final accounts = ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[]
Account? selected
selected = account
```

**`lib/features/expense/presentation/widgets/subtype_forms/electronics_form.dart`**

```dart
class ElectronicsForm extends ConsumerWidget
const ElectronicsForm({ required this.editorId, required this.state, required this.decimalDigits, super.key, })
final String? editorId
final TransactionEditorState state
final int decimalDigits
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final notifier = ref.read(transactionEditorProvider(editorId).notifier)
final localeTag = Localizations.localeOf(context).toString()
String format(DateKey date)
```

**`lib/features/expense/presentation/widgets/subtype_forms/grocery_form.dart`**

```dart
class GroceryForm extends ConsumerWidget
const GroceryForm({ required this.editorId, required this.state, required this.decimalDigits, super.key, })
final String? editorId
final TransactionEditorState state
final int decimalDigits
Widget build(BuildContext context, WidgetRef ref)
```

**`lib/features/expense/presentation/widgets/subtype_forms/household_form.dart`**

```dart
class HouseholdForm extends ConsumerWidget
const HouseholdForm({ required this.editorId, required this.state, required this.decimalDigits, super.key, })
final String? editorId
final TransactionEditorState state
final int decimalDigits
Widget build(BuildContext context, WidgetRef ref)
```

**`lib/features/expense/presentation/widgets/subtype_forms/other_form.dart`**

```dart
class OtherForm extends ConsumerWidget
const OtherForm({ required this.editorId, required this.state, required this.decimalDigits, super.key, })
final String? editorId
final TransactionEditorState state
final int decimalDigits
Widget build(BuildContext context, WidgetRef ref)
```

**`lib/features/expense/presentation/widgets/subtype_forms/transfer_form.dart`**

```dart
class TransferForm extends ConsumerWidget
const TransferForm({required this.editorId, required this.state, super.key})
final String? editorId
final TransactionEditorState state
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final semantic = context.semantic
final notifier = ref.read(transactionEditorProvider(editorId).notifier)
final accounts = ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[]
Account? accountFor(String? id)
```

**`lib/features/expense/presentation/widgets/transaction_filter_sheet.dart`**

```dart
class TransactionFilterSheet extends ConsumerWidget
const TransactionFilterSheet({super.key})
static Future<void> show(BuildContext context)
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final theme = Theme.of(context)
final filter = ref.watch(transactionFilterProvider)
final notifier = ref.read(transactionFilterProvider.notifier)
final accounts = ref.watch(accountsByIdProvider).valueOrNull ?? const <String, Account>
static String rangeLabel(AlayaStrings strings, DateRangePreset preset)
class _Choice extends StatelessWidget
final String label
final bool selected
final VoidCallback onTap
Widget build(BuildContext context)
```

**`lib/features/expense/presentation/widgets/transaction_row.dart`**

```dart
class TransactionRow extends StatelessWidget
const TransactionRow({ required this.transaction, required this.decimalDigits, required this.onTap, this.payee, this.fromAccount, this.toAccount, super.key, })
final Transaction transaction
final int decimalDigits
final VoidCallback onTap
final Payee? payee
final Account? fromAccount
final Account? toAccount
Widget build(BuildContext context)
final theme = Theme.of(context)
final semantic = context.semantic
final strings = AlayaStrings.of(context)
final title = payee?.name ?? _subtypeLabel(strings, transaction.subtype)
final metadata = _metadata(strings)
final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5
final amount = AmountText( transaction.signedAmount, kind: transaction.kind, decimalDigits: decimalDigits, textAlign: stacked ? TextAlign.start : TextAlign.end, )
final parts = <String>[]
final from = fromAccount?.name
final to = toAccount?.name
final account = (fromAccount ?? toAccount)?.name
static String subtypeLabel(AlayaStrings strings, TransactionSubtype subtype)
switch (subtype)
static String kindLabel(AlayaStrings strings, TransactionKind kind)
```

**`lib/features/expense/providers/quick_add_providers.dart`**

```dart
class QuickAddState
const QuickAddState({ this.kind = TransactionKind.withdrawal, this.amount, this.accountId, this.tagId, this.submitting = false, this.amountMissing = false, this.shakeTrigger = 0, })
final TransactionKind kind
final Money? amount
final String? accountId
final String? tagId
final bool submitting
final bool amountMissing
final int shakeTrigger
bool get isDirty
QuickAddState copyWith({ TransactionKind? kind, Money? amount, bool clearAmount = false, String? accountId, String? tagId, bool clearTag = false, bool? submitting, bool? amountMissing, int? shakeTrigger, })
QuickAddState( kind: kind ?? this.kind, amount: clearAmount ? null : (amount ?? this.amount), accountId: accountId ?? this.accountId, tagId: clearTag ? null : (tagId ?? this.tagId), submitting: submitting ?? this.submitting, amountMissing: amountMissing ?? this.amountMissing, shakeTrigger: shakeTrigger ?? this.shakeTrigger, )
class QuickAddNotifier extends AutoDisposeNotifier<QuickAddState>
QuickAddState build()
void setKind(TransactionKind kind)
void setAmount(Money? amount)
void setAccount(String accountId)
void toggleTag(String tagId)
Future<Transaction?> submit() async
final amount = state.amount
state = state.copyWith( amountMissing: true, shakeTrigger: state.shakeTrigger + 1, )
state = state.copyWith(submitting: true)
final clock = ref.read(clockProvider)
final isDeposit = state.kind == TransactionKind.deposit
final transaction = Transaction( id: ref.read(uidGeneratorProvider).generate(), kind: state.kind, subtype: isDeposit ? TransactionSubtype.otherIn : TransactionSubtype.otherOut, occurredAtUtc: clock.now().toUtc(), dateKey: clock.today(), originalAmount: amount, needsReview: true, fromAccountId: isDeposit ? null : state.accountId, toAccountId: isDeposit ? state.accountId : null, )
final tagId = state.tagId
final result = await ref.read(transactionRepositoryProvider).create( transaction: transaction, tagIds: [if (tagId != null) tagId], )
state = state.copyWith(submitting: false)
Future<void> undo(String id) async
final kind = ref.watch(quickAddProvider.select((s) => s.kind))
final scope = kind == TransactionKind.deposit ? TagScope.deposit : TagScope.withdrawal
```

**`lib/features/expense/providers/transaction_detail_providers.dart`**

```dart
class TransactionActions
const TransactionActions(this._ref)
Future<DetachedArtefacts?> delete(String id, {String? reason}) async
final result =
Future<bool> freezeConversion({ required Transaction transaction, required String toCurrencyCode, }) async
final result = await _ref.read(transactionRepositoryProvider).freezeConversion( id: transaction.id, on: transaction.dateKey, toCurrencyCode: toCurrencyCode, )
```

**`lib/features/expense/providers/transaction_draft_provider.dart`**

```dart
class TransactionDraftNotifier extends Notifier<TransactionDraft?>
TransactionDraft? build()
void offer(TransactionDraft draft)
TransactionDraft? take()
final draft = state
state = null
```

**`lib/features/expense/providers/transaction_editor_providers.dart`**

```dart
class TransactionNotFound implements Exception
const TransactionNotFound(this.id)
final String id
String toString()
class TransactionEditorNotifier extends AutoDisposeFamilyNotifier<AsyncValue<TransactionEditorState>, String?>
AsyncValue<TransactionEditorState> build(String? arg)
unawaited(_load(arg))
final settings = ref.read(settingsRepositoryProvider)
final code = await settings.readHomeCurrencyCode() ?? 'INR'
final draft = ref.read(transactionDraftProvider.notifier).take()
state = AsyncValue.data( TransactionEditorState( currencyCode: code, dateKey: ref.read(clockProvider).today(), kind: draft?.kind ?? TransactionKind.withdrawal, subtype: draft?.subtype ?? TransactionSubtype.otherOut, lines: draft?.lines ?? const [], note: draft?.note, sourceEntryIds: draft?.sourceEntryIds ?? const [], ), )
final repository = ref.read(transactionRepositoryProvider)
final transaction = await repository.byId(id)
state = AsyncValue.error(TransactionNotFound(id), StackTrace.current)
final lines = await _firstOrEmpty(repository.watchLines(id))
final tags = await _firstOrEmpty(ref.read(tagRepositoryProvider).watchForTransaction(id))
state = AsyncValue.data( TransactionEditorState.fromTransaction( transaction, lines: lines, tagIds: {for (final tag in tags) tag.id}, ), )
state = AsyncValue.error(error, stack)
final current = state.valueOrNull
state = AsyncValue.data(change(current))
void setKind(TransactionKind kind)
void setSubtype(TransactionSubtype subtype)
void setAmount(Money? amount)
void setDate(DateKey date)
void setFromAccount(String? id)
void setToAccount(String? id)
void setPaymentMethod(String? id)
void setPayee(String? id)
void setNote(String note)
void setRecurringOccurrence({ String? occurrenceId, Money? defaultAmount, String? accountId, })
void toggleTag(String tagId)
void setTransferTarget({required bool toOwnAccount})
void setWarranty({DateKey? start, DateKey? end})
void setAlsoAddToInventory({required bool value})
void upsertLine(TransactionLine line)
void removeLine(String lineId)
Future<bool> createPayee(String name) async
final normalizer = ref.read(normalizerProvider)
final payee = Payee( id: ref.read(uidGeneratorProvider).generate(), name: name, normalizedName: normalizer.normalize(name), kind: PayeeKind.merchant, )
final saved = await ref.read(payeeRepositoryProvider).save(payee)
final value = saved.valueOrNull
setPayee(value.id)
Future<String?> save() async
final uids = ref.read(uidGeneratorProvider)
final clock = ref.read(clockProvider)
final amount = current.amount!
final id = current.id ?? uids.generate()
final lines = [
final transaction =
final settling = current.recurringOccurrenceId
final account = current.fromAccountId ??
final paid = await ref.read(recurringRepositoryProvider).payOccurrence( occurrenceId: settling, amount: amount, paidOn: current.dateKey, accountId: account, paymentMethodId: current.paymentMethodId, )
final failure = paid.failureOrNull
final written = current.isEditing
final replaced = await repository.replaceLines(transactionId: id, lines: lines)
final fanned = await _fanOut(transaction: transaction, lines: lines, state: current)
final planned = ref.read(purchaseFanOutServiceProvider).planAll( lines: lines, transaction: transaction, newArtefactIds: [for (var i = 0; i < lines.length; i++) uids.generate()], )
final plans = planned.valueOrNull
final wanted = lines.any( (line) => line.destination != TransactionLineDestination.none, )
String? refused
var requestedTemplate = false
String? createdAsset
final updated = [...lines]
final index = updated.indexWhere((line) => line.id == plan.lineId)
switch (plan.target)
final batch = plan.batch
final saved = await ref.read(batchRepositoryProvider).create(batch)
refused = saved.failureOrNull?.message
final asset = plan.asset
final saved = await ref.read(assetRepositoryProvider).save( asset.copyWith( warrantyStartDateKey: state.warrantyStart, warrantyEndDateKey: state.warrantyEnd, ), )
TemplateDraft( name: plan.recurringTemplateName ?? updated[index].description, amount: updated[index].lineAmount ?? state.amount, )
requestedTemplate = true
kind == TransactionKind.deposit ? TagScope.deposit : TagScope.withdrawal
```

**`lib/features/expense/providers/transaction_list_providers.dart`**

```dart
class TransactionFilterNotifier extends Notifier<TransactionFilter>
TransactionFilter build()
void setPreset(DateRangePreset preset)
state = state.copyWith(preset: preset, clearCustomRange: true)
void setCustomRange(DateRange range)
state = state.copyWith(preset: DateRangePreset.custom, customRange: range)
void toggleKind(TransactionKind kind)
final next =
state = state.copyWith(kinds: next)
void toggleSubtype(TransactionSubtype subtype)
state = state.copyWith(subtypes: next)
void setAccount(String? accountId)
void setPayee(String? payeeId)
void showNeedsReviewOnly()
void clearNeedsReviewOnly()
void clear()
final filter = ref.watch(transactionFilterProvider)
final service = ref.watch(dateRangeServiceProvider)
final today = ref.watch(clockProvider).today()
final range = ref.watch(transactionRangeProvider)
class TransactionDayGroup
const TransactionDayGroup({required this.date, required this.transactions})
final DateKey date
final List<Transaction> transactions
final groups = <int, List<Transaction>>
final dates = groups.keys.toList()..sort((a, b)
TransactionDayGroup(date: DateKey(date), transactions: groups[date]!)
final code = await ref.watch(homeCurrencyCodeProvider.future)
final currency = await ref.watch(currencyRepositoryProvider).byCode(code)
```

**`lib/features/expense/providers/transaction_search_providers.dart`**

```dart
class TransactionSearchQueryNotifier extends Notifier<String>
String build()
void set(String query)
void clear()
final query = ref.watch(transactionSearchQueryProvider)
```

**`lib/features/expense/state/transaction_draft.dart`**

```dart
class TransactionDraft
const TransactionDraft({ required this.lines, required this.kind, required this.subtype, this.note, this.sourceEntryIds = const <String>[], this.sourceListId, })
final List<TransactionLine> lines
final TransactionKind kind
final TransactionSubtype subtype
final String? note
final List<String> sourceEntryIds
final String? sourceListId
```

**`lib/features/expense/state/transaction_editor_state.dart`**

```dart
class TransactionEditorState
final String? id
final TransactionKind kind
final TransactionSubtype subtype
final Money? amount
final String currencyCode
final DateKey dateKey
final String? fromAccountId
final String? toAccountId
final String? paymentMethodId
final String? payeeId
final String? note
final Set<String> tagIds
final List<TransactionLine> lines
final DateKey? warrantyStart
final DateKey? warrantyEnd
final bool alsoAddToInventory
final bool toOwnAccount
final bool needsReview
final bool submitting
final bool amountMissing
final int shakeTrigger
final bool dirty
final String? fanOutError
final String? saveError
final bool wantsTemplate
final String? recurringOccurrenceId
final String? createdAssetId
final bool accountMissing
final List<String> sourceEntryIds
bool get isEditing
List<TransactionSubtype> get availableSubtypes => subtypesFor(kind)
static List<TransactionSubtype> subtypesFor(TransactionKind kind)
Money? get lineTotal
var total = Money.zero(currencyCode)
final lineAmount = line.lineAmount
Money? get unallocated
final total = lineTotal
final value = amount
final difference = value - total
Transaction toTransaction({required String newId, required DateTime occurredAtUtc})
Transaction( id: id ?? newId, kind: kind, subtype: subtype, occurredAtUtc: occurredAtUtc, dateKey: dateKey, originalAmount: amount ?? Money.zero(currencyCode), needsReview: needsReview, fromAccountId: fromAccountId, toAccountId: toAccountId, paymentMethodId: paymentMethodId, payeeId: payeeId, note: note, )
static TransactionEditorState fromTransaction( Transaction transaction, { required List<TransactionLine> lines, required Set<String> tagIds, })
```

**`lib/features/expense/state/transaction_filter.dart`**

```dart
class TransactionFilter
const TransactionFilter({ this.preset = DateRangePreset.last30Days, this.customRange, this.kinds = const <TransactionKind>{}, this.subtypes = const <TransactionSubtype>{}, this.accountId, this.payeeId, this.needsReviewOnly = false, })
final DateRangePreset preset
final DateRange? customRange
final Set<TransactionKind> kinds
final Set<TransactionSubtype> subtypes
final String? accountId
final String? payeeId
final bool needsReviewOnly
bool get isNarrowed
bool admits({ required TransactionKind kind, required TransactionSubtype subtype, required String? fromAccountId, required String? toAccountId, required String? transactionPayeeId, required bool needsReview, })
TransactionFilter copyWith({ DateRangePreset? preset, DateRange? customRange, bool clearCustomRange = false, Set<TransactionKind>? kinds, Set<TransactionSubtype>? subtypes, String? accountId, bool clearAccount = false, String? payeeId, bool clearPayee = false, bool? needsReviewOnly, })
TransactionFilter( preset: preset ?? this.preset, customRange: clearCustomRange ? null : (customRange ?? this.customRange), kinds: kinds ?? this.kinds, subtypes: subtypes ?? this.subtypes, accountId: clearAccount ? null : (accountId ?? this.accountId), payeeId: clearPayee ? null : (payeeId ?? this.payeeId), needsReviewOnly: needsReviewOnly ?? this.needsReviewOnly, )
bool operator ==(Object other)
int get hashCode => Object.hash( preset, customRange, Object.hashAllUnordered(kinds), Object.hashAllUnordered(subtypes), accountId, payeeId, needsReviewOnly, )
```


### Feature — inventory (6B)

**`lib/features/inventory/presentation/screens/batch_editor_screen.dart`**

```dart
class BatchEditorScreen extends ConsumerWidget
const BatchEditorScreen({required this.itemId, this.batchId, super.key})
final String itemId
final String? batchId
final strings = AlayaStrings.of(context)
final confirmed = await ConfirmSheet.show( context, title: strings.confirmDeleteBatchTitle, body: strings.confirmDeleteBatchBody, confirmLabel: strings.actionDeleteBatch, cancelLabel: strings.actionCancel, destructive: true, )
final ok = await ref.read(itemActionsProvider).deleteBatch(id)
showFailureSnack(context, message: strings.errorBodyGeneric)
showResultSnack(context, message: strings.batchDeleted)
final saved = await ref.read(batchEditorProvider(_args).notifier).save()
showResultSnack(context, message: strings.batchSaved)
Widget build(BuildContext context, WidgetRef ref)
final async = ref.watch(batchEditorProvider(_args))
class _Form extends ConsumerWidget
final BatchEditorArgs args
final BatchEditorState state
final semantic = context.semantic
final notifier = ref.read(batchEditorProvider(args).notifier)
final item = ref.watch(batchOwnerProvider(state.itemId)).valueOrNull
final currency = ref.watch(batchCurrencyProvider).valueOrNull
final digits = ref.watch(batchDecimalDigitsProvider).valueOrNull ?? 2
final units = item == null
final localeTag = Localizations.localeOf(context).toString()
String format(DateKey date)
Unit? selected
final quantity = state.quantity
```

**`lib/features/inventory/presentation/screens/batch_history_screen.dart`**

```dart
class BatchHistoryScreen extends ConsumerWidget
const BatchHistoryScreen({required this.itemId, required this.batchId, super.key})
final String itemId
final String batchId
final strings = AlayaStrings.of(context)
final confirmed = await ConfirmSheet.show( context, title: strings.confirmReverseTitle, body: strings.confirmReverseBody, confirmLabel: strings.actionReverse, cancelLabel: strings.actionCancel, )
final ok = await ref.read(movementActionsProvider).reverse(movementId)
? showResultSnack(context, message: strings.movementReversedSnack)
Widget build(BuildContext context, WidgetRef ref)
final movements = ref.watch(batchMovementsProvider(batchId))
final reversed = ref.watch(reversedMovementIdsProvider(batchId))
final isReversal = movement.reversesMovementId != null
final tone = isReversed
```

**`lib/features/inventory/presentation/screens/inventory_list_screen.dart`**

```dart
class InventoryListScreen extends ConsumerWidget
const InventoryListScreen({super.key})
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final groups = ref.watch(inventoryGroupsProvider)
final filter = ref.watch(inventoryFilterProvider)
class _Toolbar extends ConsumerWidget
final notifier = ref.read(inventoryFilterProvider.notifier)
final lowCount = ref.watch(lowStockCountProvider)
class _ActiveFilters extends ConsumerWidget
class _Empty extends StatelessWidget
final bool isSearching
Widget build(BuildContext context)
class _Sections extends ConsumerWidget
final List<InventoryGroup> sections
final stocks = ref.watch(itemStocksProvider).valueOrNull ?? const
final today = ref.watch(clockProvider).today()
class _GroupHeader extends StatelessWidget
final String label
final semantic = context.semantic
abstract final class ItemKindLabel
static String of(AlayaStrings strings, ItemKind kind)
```

**`lib/features/inventory/presentation/screens/item_detail_screen.dart`**

```dart
class ItemDetailScreen extends ConsumerWidget
const ItemDetailScreen({required this.itemId, super.key})
final String itemId
final strings = AlayaStrings.of(context)
final confirmed = await ConfirmSheet.show( context, title: strings.confirmDeleteItemTitle, body: strings.confirmDeleteItemBody(batchCount), confirmLabel: strings.actionDeleteItem, cancelLabel: strings.actionCancel, destructive: true, )
final ok = await ref.read(itemActionsProvider).delete(itemId)
showFailureSnack(context, message: strings.errorBodyGeneric)
showResultSnack(context, message: strings.itemDeleted)
Widget build(BuildContext context, WidgetRef ref)
final async = ref.watch(itemByIdProvider(itemId))
class _Body extends ConsumerWidget
final Item item
final ValueChanged<int> onDelete
final semantic = context.semantic
final today = ref.watch(clockProvider).today()
final stock = ref.watch(itemStockProvider(item.id)).valueOrNull
final batches = ref.watch(itemBatchesProvider(item.id))
final units = ref.watch(detailUnitsByCodeProvider).valueOrNull ?? const
final threshold = item.lowStockThreshold
final notifyDays = item.expiryNotifyDays
```

**`lib/features/inventory/presentation/screens/item_editor_screen.dart`**

```dart
class ItemEditorScreen extends ConsumerWidget
const ItemEditorScreen({this.itemId, super.key})
final String? itemId
final strings = AlayaStrings.of(context)
final saved = await ref.read(itemEditorProvider(itemId).notifier).save()
showFailureSnack(context, message: strings.errorBodyGeneric)
showResultSnack(context, message: strings.actionSaved)
Widget build(BuildContext context, WidgetRef ref)
final async = ref.watch(itemEditorProvider(itemId))
class _Form extends ConsumerWidget
final String? editorId
final ItemEditorState state
switch (category)
final semantic = context.semantic
final notifier = ref.read(itemEditorProvider(editorId).notifier)
final units =
Unit? selected
Unit? thresholdUnit
class _IssueBanner extends ConsumerWidget
final conflictId = state.conflictItemId
final message = switch (state.issue)
```

**`lib/features/inventory/presentation/sheets/consume_sheet.dart`**

```dart
class ConsumeSheet extends ConsumerWidget
const ConsumeSheet({ required this.itemId, required this.unitCode, required this.category, super.key, })
final String itemId
final String unitCode
final UnitCategory category
static Future<void> show( BuildContext context, { required String itemId, required String unitCode, required UnitCategory category, })
final strings = AlayaStrings.of(context)
final written = await ref.read(consumeProvider(args).notifier).commit()
showFailureSnack(context, message: strings.errorBodyGeneric)
showResultSnack(context, message: strings.consumeRecorded)
Widget build(BuildContext context, WidgetRef ref)
final theme = Theme.of(context)
final semantic = context.semantic
final args = (itemId: itemId, unitCode: unitCode)
final state = ref.watch(consumeProvider(args))
final notifier = ref.read(consumeProvider(args).notifier)
final fefo = ref.watch(consumeFefoProvider(itemId))
final units = ref.watch(unitsInCategoryProvider(category)).valueOrNull ?? const <Unit>[]
Unit? selected
final batches = fefo.valueOrNull ?? const <Batch>[]
final plan = state.planAgainst(batches)
final shortfall = state.shortfallAgainst(batches)
class _BatchChips extends StatelessWidget
final List<Batch> batches
final ConsumeState state
final List<ConsumePlanLeg> plan
final ValueChanged<String?> onPick
Widget build(BuildContext context)
final fefoId = plan.isEmpty ? batches.first.id : plan.first.batch.id
class _BatchChipLabel extends StatelessWidget
final Batch batch
final expiry = batch.expiryDateKey
```

**`lib/features/inventory/presentation/widgets/batch_card.dart`**

```dart
class BatchCard extends StatelessWidget
const BatchCard({ required this.batch, required this.today, required this.onTap, this.onHistory, super.key, })
final Batch batch
final DateKey today
final VoidCallback onTap
final VoidCallback? onHistory
Widget build(BuildContext context)
final strings = AlayaStrings.of(context)
final semantic = context.semantic
final days = batch.daysUntilExpiry(today)
final location = batch.storageLocation
```

**`lib/features/inventory/presentation/widgets/item_row.dart`**

```dart
class ItemRow extends StatelessWidget
const ItemRow({ required this.item, required this.stock, required this.today, required this.onTap, this.onToggleFavourite, super.key, })
final Item item
final ItemStock? stock
final DateKey today
final VoidCallback onTap
final VoidCallback? onToggleFavourite
final current = stock
final chips = <Widget>[]
final days = current.daysUntilNearestExpiry(today)
Widget build(BuildContext context)
final strings = AlayaStrings.of(context)
final theme = Theme.of(context)
final semantic = context.semantic
final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5
final chips = _chips(context, strings)
final quantity = current == null
```

**`lib/features/inventory/providers/batch_editor_providers.dart`**

```dart
typedef BatchEditorArgs = ({String itemId, String? batchId})
final code = await ref.watch(batchCurrencyProvider.future)
final currency = await ref.watch(currencyRepositoryProvider).byCode(code)
class BatchEditorNotifier extends AutoDisposeFamilyNotifier<AsyncValue<BatchEditorState>, BatchEditorArgs>
AsyncValue<BatchEditorState> build(BatchEditorArgs arg)
unawaited(_load(arg))
final batchId = arg.batchId
final batch = await ref.read(batchRepositoryProvider).byId(batchId)
state = AsyncValue.error( StateError('Batch $batchId not found.'), StackTrace.current, )
state = AsyncValue.data(BatchEditorState.fromBatch(batch))
final item = await ref.read(itemRepositoryProvider).byId(arg.itemId)
state = AsyncValue.error( StateError('Item ${arg.itemId} not found.'), StackTrace.current, )
state = AsyncValue.data( BatchEditorState( itemId: arg.itemId, unitCode: item.defaultDisplayUnitCode, purchasedDateKey: ref.read(clockProvider).today(), ), )
state = AsyncValue.error(error, stack)
final current = state.valueOrNull
state = AsyncValue.data(change(current))
void setQuantity(Qty? quantity)
void setUnitCode(String code)
void setPurchased(DateKey date)
void setExpiry(DateKey? date)
void setUnitCost(Money? cost)
void setStorageLocation(String location)
void setNote(String note)
Future<String?> save() async
final quantity = current.quantity
final repository = ref.read(batchRepositoryProvider)
final id = current.id ?? ref.read(uidGeneratorProvider).generate()
final existing = await repository.byId(id)
final updated = await repository.updateMetadata( current.toBatch( newId: id, resolvedQuantity: existing.initialQuantity, remaining: existing.remainingQuantity, ), )
final created =
```

**`lib/features/inventory/providers/batch_history_providers.dart`**

```dart
final movements = ref.watch(batchMovementsProvider(batchId)).valueOrNull
class MovementActions
MovementActions(this._ref)
Future<bool> reverse(String movementId, {String? reason}) async
final result =
```

**`lib/features/inventory/providers/consume_providers.dart`**

```dart
typedef ConsumeArgs = ({String itemId, String unitCode})
class ConsumeNotifier extends AutoDisposeFamilyNotifier<ConsumeState, ConsumeArgs>
ConsumeState build(ConsumeArgs arg)
ConsumeState(itemId: arg.itemId, unitCode: arg.unitCode)
void setQuantity(Qty? quantity)
void setUnitCode(String code)
void setKind(StockMovementKind kind)
void setBatch(String? batchId)
void setReason(String reason)
Future<int?> commit() async
final quantity = state.quantity
state = state.copyWith(quantityMissing: true, shakeTrigger: state.shakeTrigger + 1)
state = state.copyWith(submitting: true)
final repository = ref.read(stockRepositoryProvider)
final override = state.overrideBatchId
final result = await repository.consumeFromBatch( batchId: override, quantity: quantity, kind: state.kind, reason: state.reason, )
state = state.copyWith(submitting: false)
final result = await repository.consume( itemId: state.itemId, quantity: quantity, kind: state.kind, reason: state.reason, )
```

**`lib/features/inventory/providers/inventory_list_providers.dart`**

```dart
class InventoryGroup
const InventoryGroup({required this.items, this.kind, this.isFavourites = false})
final List<Item> items
final ItemKind? kind
final bool isFavourites
class InventoryFilterNotifier extends Notifier<InventoryFilter>
InventoryFilter build()
void setQuery(String query)
void setGroupBy(InventoryGroupBy groupBy)
void toggleFavouritesOnly()
state = state.copyWith(favouritesOnly: !state.favouritesOnly)
void toggleLowStockOnly()
void toggleKind(ItemKind kind)
final next =
state = state.copyWith(kinds: next)
void clear()
final items = ref.watch(itemsProvider)
final stocks = ref.watch(itemStocksProvider)
final filter = ref.watch(inventoryFilterProvider)
final all = items.valueOrNull
final byId = stocks.valueOrNull
final term = filter.query.toLowerCase()
final visible = [
final starred = [for (final item in visible) if (item.isFavorite) item]
final rest = [for (final item in visible) if (!item.isFavorite) item]
final buckets = <ItemKind, List<Item>>
final stocks = ref.watch(itemStocksProvider).valueOrNull
```

**`lib/features/inventory/providers/item_detail_providers.dart`**

```dart
class ItemActions
ItemActions(this._ref)
Future<bool> delete(String id) async
final result = await _ref.read(itemRepositoryProvider).delete(id)
Future<bool> toggleFavourite(Item item) async
final result = await _ref.read(itemRepositoryProvider).setFavorite( id: item.id, isFavorite: !item.isFavorite, )
Future<bool> deleteBatch(String batchId) async
final result = await _ref.read(batchRepositoryProvider).delete(batchId)
```

**`lib/features/inventory/providers/item_editor_providers.dart`**

```dart
class ItemEditorNotifier extends AutoDisposeFamilyNotifier<AsyncValue<ItemEditorState>, String?>
AsyncValue<ItemEditorState> build(String? arg)
ItemEditorState(unitCategory: UnitCategory.count, displayUnitCode: 'pc')
unawaited(_load(arg))
final item = await ref.read(itemRepositoryProvider).byId(id)
state = AsyncValue.error(StateError('Item $id not found.'), StackTrace.current)
state = AsyncValue.data(ItemEditorState.fromItem(item))
state = AsyncValue.error(error, stack)
final current = state.valueOrNull
state = AsyncValue.data(change(current))
void setName(String name)
void setCategory(UnitCategory category, String baseUnitCode)
void setDisplayUnit(Unit unit)
void setThresholdUnit(Unit unit)
void setKind(ItemKind kind)
void toggleFavourite()
void setThreshold(Qty? threshold)
void setExpiryNotifyDays(int? days)
void setNotes(String notes)
Future<String?> save() async
final repository = ref.read(itemRepositoryProvider)
final normalized = ref.read(normalizerProvider).normalize(current.name.trim())
final clash = await repository.findByIdentity( normalizedName: normalized, unitCategory: current.unitCategory, )
final units =
final displayUnit = units.any((unit) => unit.code == current.displayUnitCode)
final id = current.id ?? ref.read(uidGeneratorProvider).generate()
final saved = await repository.save( current.copyWith(displayUnitCode: displayUnit).toItem( newId: id, normalizedName: normalized, ), )
Future<void> refreshSimilar() async
final similar = await ref.read(itemRepositoryProvider).findSimilar( name: current.name.trim(), unitCategory: current.unitCategory, )
```

**`lib/features/inventory/state/batch_editor_state.dart`**

```dart
class BatchEditorState
const BatchEditorState({ required this.itemId, required this.unitCode, required this.purchasedDateKey, this.id, this.quantity, this.expiryDateKey, this.unitCost, this.storageLocation, this.note, this.origin = BatchOrigin.manual, this.submitting = false, this.quantityMissing = false, this.shakeTrigger = 0, this.dirty = false, })
final String? id
final String itemId
final Qty? quantity
final String unitCode
final DateKey purchasedDateKey
final DateKey? expiryDateKey
final Money? unitCost
final String? storageLocation
final String? note
final BatchOrigin origin
final bool submitting
final bool quantityMissing
final int shakeTrigger
final bool dirty
bool get isEditing
bool get quantityEditable
BatchEditorState copyWith({ String? id, Qty? quantity, bool clearQuantity = false, String? unitCode, DateKey? purchasedDateKey, DateKey? expiryDateKey, bool clearExpiry = false, Money? unitCost, bool clearUnitCost = false, String? storageLocation, String? note, BatchOrigin? origin, bool? submitting, bool? quantityMissing, int? shakeTrigger, bool? dirty, })
Batch toBatch({required String newId, required Qty resolvedQuantity, Qty? remaining})
static BatchEditorState fromBatch(Batch batch)
```

**`lib/features/inventory/state/consume_state.dart`**

```dart
class ConsumePlanLeg
const ConsumePlanLeg({required this.batch, required this.quantity})
final Batch batch
final Qty quantity
class ConsumeState
const ConsumeState({ required this.itemId, required this.unitCode, this.quantity, this.kind = StockMovementKind.consume, this.overrideBatchId, this.reason, this.submitting = false, this.quantityMissing = false, this.shakeTrigger = 0, this.dirty = false, })
final String itemId
final String unitCode
final Qty? quantity
final StockMovementKind kind
final String? overrideBatchId
final String? reason
final bool submitting
final bool quantityMissing
final int shakeTrigger
final bool dirty
bool get isOverridden
ConsumeState copyWith({ Qty? quantity, bool clearQuantity = false, String? unitCode, StockMovementKind? kind, String? overrideBatchId, bool clearOverride = false, String? reason, bool? submitting, bool? quantityMissing, int? shakeTrigger, bool? dirty, })
List<ConsumePlanLeg> planAgainst(List<Batch> fefo)
final wanted = quantity
final override = overrideBatchId
final take = wanted <= batch.remainingQuantity ? wanted : batch.remainingQuantity
final legs = <ConsumePlanLeg>[]
var outstanding = wanted
final take =
Qty? shortfallAgainst(List<Batch> fefo)
var covered = Qty(0, wanted.category)
final missing = wanted - covered
```

**`lib/features/inventory/state/inventory_filter.dart`**

```dart
enum InventoryGroupBy
class InventoryFilter
const InventoryFilter({ this.groupBy = InventoryGroupBy.kind, this.favouritesOnly = false, this.lowStockOnly = false, this.kinds = const <ItemKind>{}, this.query = '', })
final InventoryGroupBy groupBy
final bool favouritesOnly
final bool lowStockOnly
final Set<ItemKind> kinds
final String query
bool get isNarrowed
bool get isSearching
InventoryFilter copyWith({ InventoryGroupBy? groupBy, bool? favouritesOnly, bool? lowStockOnly, Set<ItemKind>? kinds, String? query, })
InventoryFilter( groupBy: groupBy ?? this.groupBy, favouritesOnly: favouritesOnly ?? this.favouritesOnly, lowStockOnly: lowStockOnly ?? this.lowStockOnly, kinds: kinds ?? this.kinds, query: query ?? this.query, )
```

**`lib/features/inventory/state/item_editor_state.dart`**

```dart
enum ItemSaveIssue
class ItemEditorState
final String? id
final String name
final UnitCategory unitCategory
final String displayUnitCode
final String? thresholdUnitCode
final ItemKind itemKind
final bool isFavorite
final Qty? lowStockThreshold
final int? expiryNotifyDays
final String? notes
final bool submitting
final bool nameMissing
final int shakeTrigger
final bool dirty
final ItemSaveIssue? issue
final String? conflictItemId
final List<Item> similarInOtherMeasures
bool get isEditing
Item toItem({required String newId, required String normalizedName})
static ItemEditorState fromItem(Item item)
```


### Feature — shopping (6C)

**`lib/features/shopping/presentation/screens/convert_to_purchase_screen.dart`**

```dart
class ConvertToPurchaseScreen extends ConsumerWidget
const ConvertToPurchaseScreen({required this.listId, super.key})
final String listId
final offered =
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final draft = ref.watch(purchaseDraftProvider(listId))
class _Preview extends StatelessWidget
final List<TransactionLine> lines
Widget build(BuildContext context)
final semantic = context.semantic
```

**`lib/features/shopping/presentation/screens/shopping_list_screen.dart`**

```dart
class ShoppingListScreen extends ConsumerWidget
const ShoppingListScreen({this.listId, super.key})
final String? listId
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final active = ref.watch(activeListProvider)
class _NoLists extends StatelessWidget
final VoidCallback onCreate
Widget build(BuildContext context)
class _Body extends ConsumerWidget
final ShoppingList list
final groups = ref.watch(shoppingGroupsProvider(list.id))
final summary = ref.watch(shoppingSummaryProvider(list.id))
class _Header extends ConsumerWidget
final ShoppingSummary summary
final semantic = context.semantic
final digits = ref.watch(entryDecimalDigitsProvider).valueOrNull ?? 2
final estimate = summary.estimate
class _Sections extends ConsumerWidget
final List<ShoppingGroup> sections
final items = ref.watch(shoppingItemsByIdProvider).valueOrNull ?? const <String, Item>
final actions = ref.read(shoppingActionsProvider)
Future<void> guard(Future<String?> Function() run) async
final error = await run()
showFailureSnack(context, message: error)
```

**`lib/features/shopping/presentation/sheets/entry_editor_sheet.dart`**

```dart
class EntryEditorSheet extends ConsumerWidget
const EntryEditorSheet({required this.listId, this.entryId, super.key})
final String listId
final String? entryId
static Future<void> show( BuildContext context, { required String listId, String? entryId, })
final strings = AlayaStrings.of(context)
final saved = await ref.read(entryEditorProvider(args).notifier).save()
showFailureSnack(context, message: strings.errorBodyGeneric)
showResultSnack(context, message: strings.actionSaved)
Widget build(BuildContext context, WidgetRef ref)
final args = (listId: listId, entryId: entryId)
final async = ref.watch(entryEditorProvider(args))
class _Form extends ConsumerWidget
final EntryEditorArgs args
final EntryEditorState state
final VoidCallback onSave
final theme = Theme.of(context)
final semantic = context.semantic
final notifier = ref.read(entryEditorProvider(args).notifier)
final items = ref.watch(entryItemsProvider).valueOrNull ?? const <Item>[]
final tags = ref.watch(entryTagsProvider).valueOrNull ?? const <Tag>[]
final currency = ref.watch(entryCurrencyProvider).valueOrNull
final digits = ref.watch(entryDecimalDigitsProvider).valueOrNull ?? 2
Item? linked
final units =
Unit? selectedUnit
```

**`lib/features/shopping/presentation/sheets/generate_sheet.dart`**

```dart
class GenerateSheet extends ConsumerWidget
const GenerateSheet({required this.listId, super.key})
final String listId
static Future<void> show(BuildContext context, {required String listId})
final strings = AlayaStrings.of(context)
final outcome = await ref.read(generateActionsProvider).regenerate(listId)
final error = outcome.error
? showFailureSnack(context, message: error)
Widget build(BuildContext context, WidgetRef ref)
final theme = Theme.of(context)
final semantic = context.semantic
final suggestions = ref.watch(lowStockSuggestionsProvider(listId))
final actions = ref.read(shoppingActionsProvider)
Future<void> guard(Future<String?> Function() run) async
final failed = await run()
showFailureSnack(context, message: failed)
```

**`lib/features/shopping/presentation/sheets/list_manager_sheet.dart`**

```dart
class ListManagerSheet extends ConsumerStatefulWidget
const ListManagerSheet({super.key})
static Future<void> show(BuildContext context)
ConsumerState<ListManagerSheet> createState()
class _ListManagerSheetState extends ConsumerState<ListManagerSheet>
void dispose()
final error = await run()
showFailureSnack(context, message: error)
final name = _name.text.trim()
final actions = ref.read(listManagerActionsProvider)
final renaming = _renamingId
final created = await actions.create(name, isFirst: lists.isEmpty)
final error = created.error
setState(() => _renamingId = null)
Widget build(BuildContext context)
final strings = AlayaStrings.of(context)
final theme = Theme.of(context)
final semantic = context.semantic
final lists = ref.watch(allListsProvider)
class _Lists extends StatelessWidget
final List<ShoppingList> lists
final ValueChanged<String> onSelect
final ValueChanged<ShoppingList> onRename
final ValueChanged<String> onDefault
final ValueChanged<ShoppingList> onArchive
final live = [for (final list in lists) if (!list.isArchived) list]
final archived = [for (final list in lists) if (list.isArchived) list]
class _Tile extends StatelessWidget
final ShoppingList list
```

**`lib/features/shopping/presentation/widgets/entry_row.dart`**

```dart
class EntryRow extends StatelessWidget
const EntryRow({ required this.entry, required this.item, required this.decimalDigits, required this.onToggle, required this.onTap, this.onSnooze, this.onDismiss, super.key, })
final ShoppingEntry entry
final Item? item
final int decimalDigits
final ValueChanged<bool> onToggle
final VoidCallback onTap
final VoidCallback? onSnooze
final VoidCallback? onDismiss
Widget build(BuildContext context)
final strings = AlayaStrings.of(context)
final theme = Theme.of(context)
final semantic = context.semantic
final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5
final label = entry.freeText ?? item?.name ?? strings.labelItem
final price = entry.estimatedPrice
final quantity = entry.quantity
final snoozeUntil = entry.snoozeUntilDateKey
final estimate = price == null
```

**`lib/features/shopping/providers/convert_providers.dart`**

```dart
final result = await ref.watch(shoppingRepositoryProvider).buildPurchaseDraft(listId)
class ConvertActions
ConvertActions(this._ref)
bool offerDraft({required String listId, required List<TransactionLine> lines})
final entries = _ref.read(entriesProvider(listId)).valueOrNull ?? const []
TransactionDraft( lines: lines, kind: TransactionKind.withdrawal, subtype: TransactionSubtype.grocery, sourceListId: listId, sourceEntryIds: [ for (final entry in entries) if (entry.isChecked && !entry.isPurchased) entry.id, ], )
```

**`lib/features/shopping/providers/entry_editor_providers.dart`**

```dart
typedef EntryEditorArgs = ({String listId, String? entryId})
final code = await ref.watch(entryCurrencyProvider.future)
final currency = await ref.watch(currencyRepositoryProvider).byCode(code)
class EntryEditorNotifier extends AutoDisposeFamilyNotifier<AsyncValue<EntryEditorState>, EntryEditorArgs>
AsyncValue<EntryEditorState> build(EntryEditorArgs arg)
unawaited(_load(arg))
final entries =
state = AsyncValue.data(EntryEditorState.fromEntry(entry))
state = AsyncValue.error( StateError('Entry ${arg.entryId} not found.'), StackTrace.current, )
state = AsyncValue.error(error, stack)
final current = state.valueOrNull
state = AsyncValue.data(change(current))
void setFreeText(String text)
void setItem(Item? item)
void setQuantity(Qty? quantity)
void setUnitCode(String code)
void setTag(String? tagId)
void setEstimatedPrice(Money? price)
Future<String?> save() async
final id = current.id ?? ref.read(uidGeneratorProvider).generate()
final saved = await ref
```

**`lib/features/shopping/providers/generate_providers.dart`**

```dart
class LowStockSuggestion
const LowStockSuggestion({required this.entry, this.item, this.shortfall})
final ShoppingEntry entry
final Item? item
final Qty? shortfall
final entries = ref.watch(entriesProvider(listId))
final items = ref.watch(shoppingItemsByIdProvider)
final rows = entries.valueOrNull
final byId = items.valueOrNull ?? const <String, Item>
LowStockSuggestion( entry: entry, item: entry.itemId == null ? null : byId[entry.itemId], shortfall: _shortfall(entry, entry.itemId == null ? null : byId[entry.itemId]), )
final threshold = item?.lowStockThreshold
final atGeneration = entry.stockAtGeneration
final gap = threshold - atGeneration
class GenerateActions
GenerateActions(this._ref)
Future<String?> accept(ShoppingEntry entry) async
final saved = await _ref.read(shoppingRepositoryProvider).saveEntry( entry.copyWith( origin: ShoppingEntryOrigin.manual, autoState: ShoppingEntryAutoState.active, ), )
final result =
final failure = result.failureOrNull
```

**`lib/features/shopping/providers/list_manager_providers.dart`**

```dart
class ListManagerActions
ListManagerActions(this._ref)
final id = _ref.read(uidGeneratorProvider).generate()
final saved = await _ref.read(shoppingRepositoryProvider).saveList( ShoppingList(id: id, name: name.trim(), isDefault: isFirst, isArchived: false), )
final failure = saved.failureOrNull
Future<String?> rename(ShoppingList list, String name) async
final saved = await _ref
Future<String?> setDefault(String id) async
final result = await _ref.read(shoppingRepositoryProvider).setDefaultList(id)
Future<String?> setArchived({required String id, required bool isArchived}) async
final result = await _ref
```

**`lib/features/shopping/providers/shopping_list_providers.dart`**

```dart
class ShoppingGroup
const ShoppingGroup({required this.entries, this.tag})
final List<ShoppingEntry> entries
final Tag? tag
class SelectedListNotifier extends Notifier<String?>
String? build()
void select(String? listId)
final selected = ref.watch(selectedListIdProvider)
final lists = ref.watch(selectableListsProvider)
final fallback = ref.watch(defaultListProvider)
final entries = ref.watch(entriesProvider(listId))
final tags = ref.watch(shoppingTagsByIdProvider)
final rows = entries.valueOrNull
final byId = tags.valueOrNull ?? const <String, Tag>
final today = ref.watch(clockProvider).today()
final visible = [
final buckets = <String?, List<ShoppingEntry>>
final tagged = [
ShoppingGroup(entries: buckets[id]!, tag: byId[id])
class ShoppingSummary
const ShoppingSummary({ required this.estimate, required this.checked, required this.total, })
final Money? estimate
final int checked
final int total
bool get hasChecked
final groups = ref.watch(shoppingGroupsProvider(listId)).valueOrNull ?? const []
Money? estimate
var checked = 0
var total = 0
final price = entry.estimatedPrice
estimate = estimate == null ? price : estimate + price
class ShoppingActions
ShoppingActions(this._ref)
static const int snoozeDays = 7
Future<String?> setChecked({required String id, required bool isChecked}) async
final result = await _ref
Future<String?> snooze(String id) async
final until = _ref.read(clockProvider).today().addDays(snoozeDays)
final result =
Future<String?> dismiss(String id) async
final result = await _ref.read(shoppingRepositoryProvider).dismissEntry(id)
Future<String?> delete(String id) async
final result = await _ref.read(shoppingRepositoryProvider).deleteEntry(id)
Future<void> uncheckAll(List<ShoppingEntry> entries) async
final repository = _ref.read(shoppingRepositoryProvider)
```

**`lib/features/shopping/state/entry_editor_state.dart`**

```dart
class EntryEditorState
const EntryEditorState({ required this.listId, this.id, this.freeText = '', this.itemId, this.quantity, this.unitCode, this.tagId, this.estimatedPrice, this.origin = ShoppingEntryOrigin.manual, this.autoState = ShoppingEntryAutoState.active, this.sortOrder = 0, this.isChecked = false, this.submitting = false, this.identityMissing = false, this.shakeTrigger = 0, this.dirty = false, })
final String? id
final String listId
final String freeText
final String? itemId
final Qty? quantity
final String? unitCode
final String? tagId
final Money? estimatedPrice
final ShoppingEntryOrigin origin
final ShoppingEntryAutoState autoState
final int sortOrder
final bool isChecked
final bool submitting
final bool identityMissing
final int shakeTrigger
final bool dirty
bool get isEditing
bool get hasIdentity => freeText.trim().isNotEmpty || itemId != null
ShoppingEntry toEntry({required String newId})
final promoted = isEditing && origin == ShoppingEntryOrigin.autoLowStock
static EntryEditorState fromEntry(ShoppingEntry entry)
```


### Feature — recurring (6D)

**`lib/features/recurring/presentation/screens/occurrence_history_screen.dart`**

```dart
class OccurrenceHistoryScreen extends ConsumerWidget
const OccurrenceHistoryScreen({required this.templateId, super.key})
final String templateId
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final template = ref.watch(historyTemplateProvider(templateId))
class _Body extends ConsumerWidget
final RecurringTemplate template
final transactionId = occurrence.paidTransactionId
final confirmed = await ConfirmSheet.show( context, title: strings.payUndoTitle, body: strings.payUndoBody, confirmLabel: strings.actionUndo, cancelLabel: strings.actionCancel, destructive: true, )
final error = await ref.read(occurrenceActionsProvider).undoPayment( occurrenceId: occurrence.id, transactionId: transactionId, )
error == null
? showResultSnack(context, message: strings.payUndone)
final semantic = context.semantic
final async = ref.watch(occurrencesProvider(template.id))
final today = ref.watch(clockProvider).today()
final digits = ref.watch(builderDecimalDigitsProvider).valueOrNull ?? 2
final ordered = [...rows]
```

**`lib/features/recurring/presentation/screens/template_builder_screen.dart`**

```dart
class TemplateBuilderScreen extends ConsumerWidget
const TemplateBuilderScreen({this.templateId, super.key})
final String? templateId
final strings = AlayaStrings.of(context)
final saved = await ref.read(templateBuilderProvider(templateId).notifier).save()
final state = ref.read(templateBuilderProvider(templateId)).valueOrNull
showFailureSnack( context, message: state?.rejection ?? _issueMessage(strings, state?.issue), )
showResultSnack(context, message: strings.actionSaved)
switch (issue)
Widget build(BuildContext context, WidgetRef ref)
final async = ref.watch(templateBuilderProvider(templateId))
class _Form extends ConsumerWidget
final String? editorId
final TemplateBuilderState state
switch (unit)
final semantic = context.semantic
final notifier = ref.read(templateBuilderProvider(editorId).notifier)
final digits = ref.watch(builderDecimalDigitsProvider).valueOrNull ?? 2
final accounts = ref.watch(builderAccountsProvider).valueOrNull ?? const <Account>[]
final dates = ref.watch(previewProvider(editorId))
final localeTag = Localizations.localeOf(context).toString()
String format(DateKey date)
Account? selectedAccount
```

**`lib/features/recurring/presentation/screens/template_list_screen.dart`**

```dart
class TemplateListScreen extends ConsumerWidget
const TemplateListScreen({super.key})
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final groups = ref.watch(templateGroupsProvider)
final overdue = ref.watch(overdueCountProvider)
class _Sections extends ConsumerWidget
final List<TemplateGroup> sections
final semantic = context.semantic
final today = ref.watch(clockProvider).today()
final digits = ref.watch(builderDecimalDigitsProvider).valueOrNull ?? 2
final actions = ref.read(templateActionsProvider)
Future<void> guard(Future<String?> Function() run) async
final error = await run()
showFailureSnack(context, message: error)
```

**`lib/features/recurring/presentation/sheets/pay_sheet.dart`**

```dart
class PaySheet extends ConsumerWidget
const PaySheet({required this.occurrenceId, required this.template, super.key})
final String occurrenceId
final RecurringTemplate template
static Future<void> show( BuildContext context, { required String occurrenceId, required RecurringTemplate template, })
final strings = AlayaStrings.of(context)
final created = await ref.read(payProvider(_args).notifier).commit()
final state = ref.read(payProvider(_args))
showFailureSnack( context, message: state.rejection ?? switch (state.issue) { PayIssue.amountMissing => strings.errorAmountInvalid, PayIssue.accountMissing => strings.payNeedsAccount, PayIssue.rejected || null => strings.errorBodyGeneric, }, )
showUndoSnack( context, message: strings.payRecorded, undoLabel: strings.actionUndo, onUndo: () async { final error = await ref.read(occurrenceActionsProvider).undoPayment( occurrenceId: occurrenceId, transactionId: created, ); if (!context.mounted) return; error == null ? showResultSnack(context, message: strings.payUndone) : showFailureSnack(context, message: error); }, )
Widget build(BuildContext context, WidgetRef ref)
final theme = Theme.of(context)
final semantic = context.semantic
final state = ref.watch(payProvider(_args))
final notifier = ref.read(payProvider(_args).notifier)
final currency = template.defaultAmount.currencyCode
final digits = ref.watch(payDecimalDigitsProvider(currency)).valueOrNull ?? 2
final accounts = ref.watch(payAccountsProvider).valueOrNull ?? const <Account>[]
final inflow = template.direction == RecurringDirection.inflow
final localeTag = Localizations.localeOf(context).toString()
String format(DateKey date)
Account? selectedAccount
```

**`lib/features/recurring/presentation/widgets/template_row.dart`**

```dart
class TemplateRowTile extends StatelessWidget
const TemplateRowTile({ required this.template, required this.next, required this.today, required this.decimalDigits, required this.onTap, this.onPay, this.onTogglePause, super.key, })
final RecurringTemplate template
final RecurringOccurrence? next
final DateKey today
final int decimalDigits
final VoidCallback onTap
final VoidCallback? onPay
final VoidCallback? onTogglePause
Widget build(BuildContext context)
final strings = AlayaStrings.of(context)
final theme = Theme.of(context)
final semantic = context.semantic
final occurrence = next
final overdue = occurrence != null && occurrence.isOverdue(today)
final dueToday = occurrence != null && occurrence.dueDateKey == today
final chips = <Widget>[
StatusChip(label: strings.recurringOverdue, tone: StatusTone.danger)
else if (dueToday)
StatusChip(label: strings.recurringDueToday, tone: StatusTone.warning)
StatusChip(label: strings.recurringNotYetDue)
```

**`lib/features/recurring/providers/bill_account_providers.dart`**

```dart
final appDefault = ref.watch(defaultAccountIdProvider).valueOrNull
final accounts = ref.watch(billAccountsProvider).valueOrNull ?? const <Account>[]
```

**`lib/features/recurring/providers/pay_providers.dart`**

```dart
typedef PayArgs = ({String occurrenceId, int defaultMinor, String currencyCode, String? accountId})
class PayNotifier extends AutoDisposeFamilyNotifier<PayState, PayArgs>
PayState build(PayArgs arg)
final defaultAmount = Money(arg.defaultMinor, arg.currencyCode)
void setAmount(Money? amount)
state = state.copyWith(amount: amount, clearIssue: true, dirty: true)
void setAccount(String? accountId)
state = state.copyWith(accountId: accountId, clearIssue: true, dirty: true)
void setPaidOn(DateKey date)
void setNote(String note)
Future<String?> commit() async
final amount = state.amount
state = state.copyWith( issue: PayIssue.amountMissing, shakeTrigger: state.shakeTrigger + 1, )
final accountId = state.accountId
state = state.copyWith(issue: PayIssue.accountMissing)
state = state.copyWith(submitting: true, clearIssue: true)
final result = await ref.read(recurringRepositoryProvider).payOccurrence( occurrenceId: state.occurrenceId, amount: amount, paidOn: state.paidOn, accountId: accountId, paymentMethodId: state.paymentMethodId, )
final failure = result.failureOrNull
state = state.copyWith(issue: PayIssue.rejected, rejection: failure.message)
state = state.copyWith(issue: PayIssue.rejected, rejection: error.toString())
state = state.copyWith(submitting: false)
class OccurrenceActions
OccurrenceActions(this._ref)
Future<String?> skip({required String occurrenceId, String? note}) async
final result = await _ref
Future<String?> undoPayment({ required String occurrenceId, required String transactionId, }) async
final unsettled =
final unsettleFailure = unsettled.failureOrNull
final deleted =
```

**`lib/features/recurring/providers/template_builder_providers.dart`**

```dart
final code = await ref.watch(builderCurrencyProvider.future)
final currency = await ref.watch(currencyRepositoryProvider).byCode(code)
final state = ref.watch(templateBuilderProvider(editorId)).valueOrNull
final engine = ref.watch(recurringEngineProvider)
final template = state.toTemplate( newId: 'preview', normalizedName: 'preview', nextDue: state.startDateKey, )
final dates = <PreviewedDate>[]
var cursor = state.startDateKey
final end = state.endDateKey
final anchor = state.anchorDayOfMonth
while (dates.length < 3)
PreviewedDate( dateKey: cursor, // A clamp is visible exactly when the anchor could not be reached this month. Only a monthly // or yearly interval anchors to a day, so a weekly template never reports one. clamped: anchor != null && state.needsDayAnchor && cursor.day != anchor, )
cursor = engine.nextDue(from: cursor, template: template)
class TemplateBuilderNotifier extends AutoDisposeFamilyNotifier<AsyncValue<TemplateBuilderState>, String?>
AsyncValue<TemplateBuilderState> build(String? arg)
unawaited(_load(arg))
final code =
final today = ref.read(clockProvider).today()
final draft = ref.read(templateDraftProvider.notifier).take()
state = AsyncValue.data( TemplateBuilderState( currencyCode: code, startDateKey: today, anchorDayOfMonth: today.day, name: draft?.name ?? '', amount: draft?.amount, ), )
final template = await ref.read(recurringRepositoryProvider).templateById(id)
state = AsyncValue.error( StateError('Recurring template $id not found.'), StackTrace.current, )
state = AsyncValue.data(TemplateBuilderState.fromTemplate(template))
state = AsyncValue.error(error, stack)
final current = state.valueOrNull
state = AsyncValue.data(change(current))
void setName(String name)
void setKind(RecurringKind kind)
void setDirection(RecurringDirection direction)
void setAmount(Money? amount)
void setIntervalUnit(RecurringIntervalUnit unit)
void setIntervalCount(int count)
void setAnchorDay(int? day)
void setStartDate(DateKey date)
void setEndDate(DateKey? date)
void setAccount(String? accountId)
void setRemindDaysBefore(int days)
void toggleRemind()
void setNote(String note)
Future<String?> save() async
final id = current.id ?? ref.read(uidGeneratorProvider).generate()
final failure = saved.failureOrNull
```

**`lib/features/recurring/providers/template_draft_provider.dart`**

```dart
class TemplateDraft
const TemplateDraft({required this.name, this.amount})
final String name
final Money? amount
class TemplateDraftNotifier extends Notifier<TemplateDraft?>
TemplateDraft? build()
void offer(TemplateDraft draft)
TemplateDraft? take()
final draft = state
state = null
```

**`lib/features/recurring/providers/template_list_providers.dart`**

```dart
class TemplateRow
const TemplateRow({required this.template, this.next})
final RecurringTemplate template
final RecurringOccurrence? next
class TemplateGroup
const TemplateGroup({required this.direction, required this.rows})
final RecurringDirection direction
final List<TemplateRow> rows
final result = await ref
final templates = ref.watch(templatesProvider)
final all = templates.valueOrNull
List<TemplateRow> rowsFor(RecurringDirection direction)
TemplateRow( template: template, next: _soonestOutstanding( ref.watch(occurrencesProvider(template.id)).valueOrNull, ), )
final outflow = rowsFor(RecurringDirection.outflow)
final inflow = rowsFor(RecurringDirection.inflow)
TemplateGroup(direction: RecurringDirection.outflow, rows: outflow)
TemplateGroup(direction: RecurringDirection.inflow, rows: inflow)
RecurringOccurrence? soonest
soonest = occurrence
final groups = ref.watch(templateGroupsProvider).valueOrNull ?? const []
final engine = ref.watch(recurringEngineProvider)
final today = ref.watch(clockProvider).today()
var count = 0
final next = row.next
class TemplateActions
TemplateActions(this._ref)
Future<String?> setPaused({required String id, required bool isPaused}) async
final result = await _ref
Future<String?> delete(String id) async
final result = await _ref.read(recurringRepositoryProvider).deleteTemplate(id)
```

**`lib/features/recurring/state/pay_state.dart`**

```dart
enum PayIssue
class PayState
const PayState({ required this.occurrenceId, required this.defaultAmount, required this.paidOn, this.amount, this.accountId, this.paymentMethodId, this.note, this.submitting = false, this.issue, this.rejection, this.shakeTrigger = 0, this.dirty = false, })
final String occurrenceId
final Money defaultAmount
final Money? amount
final DateKey paidOn
final String? accountId
final String? paymentMethodId
final String? note
final bool submitting
final PayIssue? issue
final String? rejection
final int shakeTrigger
final bool dirty
bool get differsFromDefault
final actual = amount
PayState copyWith({ Money? amount, DateKey? paidOn, String? accountId, String? paymentMethodId, String? note, bool? submitting, PayIssue? issue, String? rejection, bool clearIssue = false, int? shakeTrigger, bool? dirty, })
```

**`lib/features/recurring/state/template_builder_state.dart`**

```dart
enum TemplateSaveIssue
class TemplateBuilderState
final String? id
final String name
final RecurringKind kind
final RecurringDirection direction
final String currencyCode
final Money? amount
final RecurringIntervalUnit intervalUnit
final int intervalCount
final int? anchorDayOfMonth
final DateKey startDateKey
final DateKey? endDateKey
final String? payeeId
final String? accountId
final String? tagId
final int remindDaysBefore
final bool autoRemind
final bool isPaused
final String? note
final bool submitting
final TemplateSaveIssue? issue
final String? rejection
final int shakeTrigger
final bool dirty
bool get isEditing
bool get needsDayAnchor
intervalUnit == RecurringIntervalUnit.month ||
intervalUnit == RecurringIntervalUnit.year
bool get isComplete
RecurringTemplate toTemplate({ required String newId, required String normalizedName, required DateKey nextDue, })
static TemplateBuilderState fromTemplate(RecurringTemplate template)
```


### Feature — service (6E)

**`lib/features/service/presentation/screens/asset_detail_screen.dart`**

```dart
class AssetDetailScreen extends ConsumerWidget
const AssetDetailScreen({required this.assetId, super.key})
final String assetId
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final async = ref.watch(assetByIdProvider(assetId))
class _Body extends ConsumerWidget
final Asset asset
final error = await DisposeSheet.show( context, assetId: asset.id, currencyCode: currencyCode, )
? showResultSnack(context, message: strings.disposeDone)
final error = await ref.read(assetActionsProvider).undispose(asset.id)
error == null
? showResultSnack(context, message: strings.undisposeDone)
final semantic = context.semantic
final today = ref.watch(clockProvider).today()
final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2
final currency = ref.watch(serviceCurrencyProvider).valueOrNull ?? 'INR'
final localeTag = Localizations.localeOf(context).toString()
String format(DateKey date)
final person = asset.isServiceProvider
class _Hero extends StatelessWidget
final DateKey today
final int decimalDigits
Widget build(BuildContext context)
final theme = Theme.of(context)
final price = asset.purchasePrice
class _Lifetime extends ConsumerWidget
final async = ref.watch(lifetimeServiceCostProvider(asset.id))
final totals = async.valueOrNull
class ServiceTypeLabels
const ServiceTypeLabels._()
static String of(AlayaStrings strings, ServiceRecordType type)
class _History extends ConsumerWidget
final String Function(DateKey) format
final async = ref.watch(serviceRecordsProvider(asset.id))
final ordered = [...records]
```

**`lib/features/service/presentation/screens/asset_editor_screen.dart`**

```dart
class AssetEditorScreen extends ConsumerWidget
const AssetEditorScreen({this.assetId, super.key})
final String? assetId
final strings = AlayaStrings.of(context)
final saved = await ref.read(assetEditorProvider(assetId).notifier).save()
final state = ref.read(assetEditorProvider(assetId)).valueOrNull
showFailureSnack( context, message: state?.rejection ?? switch (state?.issue) { AssetSaveIssue.nameMissing => strings.errorFieldRequired, AssetSaveIssue.warrantyBackwards => strings.errorWarrantyBackwards, AssetSaveIssue.rejected || null => strings.errorBodyGeneric, }, )
showResultSnack(context, message: strings.actionSaved)
Widget build(BuildContext context, WidgetRef ref)
final async = ref.watch(assetEditorProvider(assetId))
class _Form extends ConsumerWidget
final String? editorId
final AssetEditorState state
final semantic = context.semantic
final notifier = ref.read(assetEditorProvider(editorId).notifier)
final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2
final localeTag = Localizations.localeOf(context).toString()
String format(DateKey date)
```

**`lib/features/service/presentation/screens/asset_list_screen.dart`**

```dart
class AssetListScreen extends ConsumerWidget
const AssetListScreen({super.key})
static String typeLabel(AlayaStrings strings, AssetType type)
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final groups = ref.watch(assetGroupsProvider)
final filter = ref.watch(assetFilterProvider)
class _Toolbar extends ConsumerWidget
final semantic = context.semantic
final notifier = ref.read(assetFilterProvider.notifier)
final dueCount = ref.watch(serviceDueCountProvider)
class _ActiveFilters extends ConsumerWidget
class _Empty extends StatelessWidget
final bool isNarrowed
Widget build(BuildContext context)
class _Sections extends ConsumerWidget
final List<AssetGroup> sections
final today = ref.watch(clockProvider).today()
final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2
```

**`lib/features/service/presentation/screens/service_editor_screen.dart`**

```dart
class ServiceEditorScreen extends ConsumerWidget
const ServiceEditorScreen({required this.assetId, this.recordId, super.key})
final String assetId
final String? recordId
final strings = AlayaStrings.of(context)
final saved = await ref.read(serviceEditorProvider(_args).notifier).save()
final state = ref.read(serviceEditorProvider(_args)).valueOrNull
showFailureSnack( context, message: state?.rejection ?? switch (state?.issue) { ServiceSaveIssue.costMissingForExpense => strings.alsoRecordNeedsCost, ServiceSaveIssue.accountMissingForExpense => strings.alsoRecordNeedsAccount, ServiceSaveIssue.rejected || null => strings.errorBodyGeneric, }, )
showResultSnack(context, message: strings.actionSaved)
Widget build(BuildContext context, WidgetRef ref)
final async = ref.watch(serviceEditorProvider(_args))
class _Form extends ConsumerWidget
final ServiceEditorArgs args
final ServiceEditorState state
final semantic = context.semantic
final notifier = ref.read(serviceEditorProvider(args).notifier)
final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2
final accounts = ref.watch(serviceAccountsProvider).valueOrNull ?? const <Account>[]
final localeTag = Localizations.localeOf(context).toString()
String format(DateKey date)
Account? selectedAccount
final methods =
PaymentMethod? selectedMethod
```

**`lib/features/service/presentation/sheets/dispose_sheet.dart`**

```dart
class DisposeSheet extends ConsumerWidget
const DisposeSheet({required this.assetId, required this.currencyCode, super.key})
final String assetId
final String currencyCode
static Future<String?> show( BuildContext context, { required String assetId, required String currencyCode, })
DisposeSheet(assetId: assetId, currencyCode: currencyCode)
static String reasonLabel(AlayaStrings strings, AssetDisposalReason reason)
switch (reason)
final error = await ref.read(disposeProvider(_args).notifier).commit()
Widget build(BuildContext context, WidgetRef ref)
final strings = AlayaStrings.of(context)
final theme = Theme.of(context)
final semantic = context.semantic
final state = ref.watch(disposeProvider(_args))
final notifier = ref.read(disposeProvider(_args).notifier)
final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2
final localeTag = Localizations.localeOf(context).toString()
String format(DateKey date)
```

**`lib/features/service/presentation/widgets/asset_row.dart`**

```dart
class AssetRowTile extends StatelessWidget
const AssetRowTile({ required this.asset, required this.today, required this.decimalDigits, required this.onTap, super.key, })
final Asset asset
final DateKey today
final int decimalDigits
final VoidCallback onTap
static const int soonDays = 30
static IconData glyphFor(AssetType type)
Widget build(BuildContext context)
final strings = AlayaStrings.of(context)
final theme = Theme.of(context)
final semantic = context.semantic
final price = asset.purchasePrice
final chips = <Widget>[
StatusChip(label: strings.assetDisposedChip)
else if (asset.status == AssetStatus.underRepair)
StatusChip(label: strings.assetUnderRepair, tone: StatusTone.warning)
StatusChip(label: strings.assetServiceDue, tone: StatusTone.danger)
else if (asset.nextServiceDueDateKey != null && (asset.serviceDaysLeftFrom(today) ?? soonDays + 1) <= soonDays)
StatusChip(label: strings.assetServiceSoon, tone: StatusTone.warning)
StatusChip(label: strings.assetWarrantyExpired)
else if (asset.isWarrantyEndingWithin(today, soonDays))
StatusChip(label: strings.assetWarrantyEnding, tone: StatusTone.warning)
StatusChip(label: strings.assetUnderWarranty, tone: StatusTone.success)
StatusChip(label: strings.assetLinkedRecurring, tone: StatusTone.info)
```

**`lib/features/service/presentation/widgets/contact_action.dart`**

```dart
class ContactAction extends StatelessWidget
const ContactAction({required this.phone, this.name, super.key})
final String phone
final String? name
final strings = AlayaStrings.of(context)
final launched = await launchUrl(Uri(scheme: 'tel', path: phone))
showFailureSnack(context, message: strings.callFailed)
Widget build(BuildContext context)
final semantic = context.semantic
final who = name
```

**`lib/features/service/providers/asset_detail_providers.dart`**

```dart
final inUse = ref.watch(assetsInUseProvider)
final disposed = ref.watch(disposedAssetsProvider)
final active = inUse.valueOrNull
final retired = disposed.valueOrNull
class AssetActions
AssetActions(this._ref)
Future<String?> undispose(String id) async
final result = await _ref.read(assetRepositoryProvider).undispose(id)
Future<String?> setStatus({required String id, required AssetStatus status}) async
final result =
Future<String?> deleteRecord(String recordId) async
final result = await _ref.read(serviceRecordRepositoryProvider).delete(recordId)
```

**`lib/features/service/providers/asset_editor_providers.dart`**

```dart
final code = await ref.watch(serviceCurrencyProvider.future)
final currency = await ref.watch(currencyRepositoryProvider).byCode(code)
final trimmed = arg.name.trim()
final normalized = ref.watch(normalizerProvider).normalize(trimmed)
final inUse = ref.watch(assetsInUseProvider).valueOrNull ?? const <Asset>[]
final disposed = ref.watch(disposedAssetsProvider).valueOrNull ?? const <Asset>[]
class AssetEditorNotifier extends AutoDisposeFamilyNotifier<AsyncValue<AssetEditorState>, String?>
AsyncValue<AssetEditorState> build(String? arg)
unawaited(_load(arg))
final code =
state = AsyncValue.data(AssetEditorState(currencyCode: code))
final asset = await ref.read(assetRepositoryProvider).byId(id)
state = AsyncValue.error(StateError('Asset $id not found.'), StackTrace.current)
state = AsyncValue.data(AssetEditorState.fromAsset(asset, code))
state = AsyncValue.error(error, stack)
AssetEditorState Function(AssetEditorState) change
bool keepIssue = false
final current = state.valueOrNull
final next = change(current)
state = AsyncValue.data(keepIssue ? next : next.copyWith(clearIssue: true))
void setName(String name)
void setType(AssetType type)
void setBrand(String value)
void setModelNo(String value)
void setSerialNo(String value)
void setPurchaseDate(DateKey? date)
void setPurchasePrice(Money? price)
void setWarrantyStart(DateKey? date)
void setWarrantyEnd(DateKey? date)
void setWarrantyProvider(String value)
void setServiceIntervalDays(int? days)
void setNextServiceDue(DateKey? date)
void setContactName(String value)
void setContactPhone(String value)
void setLocation(String value)
void setNotes(String value)
Future<String?> save() async
final start = current.warrantyStartDateKey
final end = current.warrantyEndDateKey
final repository = ref.read(assetRepositoryProvider)
final id = current.id ?? ref.read(uidGeneratorProvider).generate()
final existing = current.isEditing ? await repository.byId(id) : null
final saved = await repository.save( current.toAsset( newId: id, normalizedName: ref.read(normalizerProvider).normalize(current.name.trim()), existing: existing, ), )
final failure = saved.failureOrNull
```

**`lib/features/service/providers/asset_list_providers.dart`**

```dart
class AssetFilter
const AssetFilter({this.includeDisposed = false, this.types = const <AssetType>{}, this.query = ''})
final bool includeDisposed
final Set<AssetType> types
final String query
bool get isNarrowed
bool get isSearching
AssetFilter copyWith({bool? includeDisposed, Set<AssetType>? types, String? query})
AssetFilter( includeDisposed: includeDisposed ?? this.includeDisposed, types: types ?? this.types, query: query ?? this.query, )
class AssetGroup
const AssetGroup({required this.type, required this.assets})
final AssetType type
final List<Asset> assets
class AssetFilterNotifier extends Notifier<AssetFilter>
AssetFilter build()
void setQuery(String query)
void toggleDisposed()
void toggleType(AssetType type)
final next =
state = state.copyWith(types: next)
void clear()
final inUse = ref.watch(assetsInUseProvider)
final filter = ref.watch(assetFilterProvider)
final active = inUse.valueOrNull
var all = [...active]
final disposed = ref.watch(disposedAssetsProvider)
final retired = disposed.valueOrNull
all = [...all, ...retired]
final term = filter.query.toLowerCase()
final visible = [
final buckets = <AssetType, List<Asset>>
final active = ref.watch(assetsInUseProvider).valueOrNull ?? const <Asset>[]
final today = ref.watch(clockProvider).today()
```

**`lib/features/service/providers/dispose_providers.dart`**

```dart
typedef DisposeArgs = ({String assetId, String currencyCode})
class DisposeNotifier extends AutoDisposeFamilyNotifier<DisposeState, DisposeArgs>
DisposeState build(DisposeArgs arg)
void setReason(AssetDisposalReason reason)
state = state.copyWith(reason: reason, reasonMissing: false, dirty: true)
void setDate(DateKey date)
void setAmount(Money? amount)
void setNote(String note)
Future<String?> commit() async
final reason = state.reason
state = state.copyWith( reasonMissing: true, shakeTrigger: state.shakeTrigger + 1, )
state = state.copyWith(submitting: true, clearRejection: true)
final result = await ref.read(assetRepositoryProvider).dispose( assetId: state.assetId, reason: reason, dateKey: state.dateKey, amountMinor: state.amount?.minor, note: state.note, )
final failure = result.failureOrNull
state = state.copyWith(rejection: failure.message)
state = state.copyWith(rejection: error.toString())
state = state.copyWith(submitting: false)
```

**`lib/features/service/providers/service_editor_providers.dart`**

```dart
typedef ServiceEditorArgs = ({String assetId, String? recordId})
class ServiceEditorNotifier extends AutoDisposeFamilyNotifier<AsyncValue<ServiceEditorState>, ServiceEditorArgs>
AsyncValue<ServiceEditorState> build(ServiceEditorArgs arg)
unawaited(_load(arg))
final code =
final recordId = arg.recordId
final record = await ref.read(serviceRecordRepositoryProvider).byId(recordId)
state = AsyncValue.error( StateError('Service record $recordId not found.'), StackTrace.current, )
state = AsyncValue.data(ServiceEditorState.fromRecord(record, code))
final asset = await ref.read(assetRepositoryProvider).byId(arg.assetId)
state = AsyncValue.error( StateError('Asset ${arg.assetId} not found.'), StackTrace.current, )
state = AsyncValue.error(error, stack)
final stored = await ref.read(settingsRepositoryProvider).readDefaultAccountId()
final accounts = await ref.read(accountRepositoryProvider).watchSelectable().first
ServiceEditorState Function(ServiceEditorState) change
bool keepIssue = false
final current = state.valueOrNull
final next = change(current)
state = AsyncValue.data(keepIssue ? next : next.copyWith(clearIssue: true))
void setType(ServiceRecordType type)
void setServiceDate(DateKey? date)
void setProviderName(String value)
void setProviderPhone(String value)
void setCost(Money? cost)
void setNextDue(DateKey? date)
void setNotes(String value)
void toggleExpense()
void setAccount(String? accountId)
void setPaymentMethod(String? methodId)
Future<String?> save() async
final repository = ref.read(serviceRecordRepositoryProvider)
final id = current.id ?? ref.read(uidGeneratorProvider).generate()
final existing = current.isEditing ? await repository.byId(id) : null
final saved = await repository.save( current.toRecord(newId: id, existing: existing), alsoRecordAsExpense: current.alsoRecordAsExpense, accountId: current.accountId, paymentMethodId: current.paymentMethodId, )
final failure = saved.failureOrNull
```

**`lib/features/service/state/asset_editor_state.dart`**

```dart
enum AssetSaveIssue
class AssetEditorState
final String? id
final String name
final AssetType type
final AssetStatus status
final String currencyCode
final String? brand
final String? modelNo
final String? serialNo
final DateKey? purchaseDateKey
final Money? purchasePrice
final DateKey? warrantyStartDateKey
final DateKey? warrantyEndDateKey
final String? warrantyProvider
final int? serviceIntervalDays
final DateKey? nextServiceDueDateKey
final String? contactName
final String? contactPhone
final String? location
final String? notes
final bool submitting
final AssetSaveIssue? issue
final String? rejection
final int shakeTrigger
final bool dirty
final bool nextServiceChosen
bool get isEditing
bool get isPerson
Asset toAsset({required String newId, required String normalizedName, Asset? existing})
static AssetEditorState fromAsset(Asset asset, String currencyCode)
```

**`lib/features/service/state/dispose_state.dart`**

```dart
class DisposeState
const DisposeState({ required this.assetId, required this.currencyCode, required this.dateKey, this.reason, this.amount, this.note, this.submitting = false, this.reasonMissing = false, this.rejection, this.shakeTrigger = 0, this.dirty = false, })
final String assetId
final String currencyCode
final AssetDisposalReason? reason
final DateKey dateKey
final Money? amount
final String? note
final bool submitting
final bool reasonMissing
final String? rejection
final int shakeTrigger
final bool dirty
DisposeState copyWith({ AssetDisposalReason? reason, DateKey? dateKey, Money? amount, bool clearAmount = false, String? note, bool? submitting, bool? reasonMissing, String? rejection, bool clearRejection = false, int? shakeTrigger, bool? dirty, })
```

**`lib/features/service/state/service_editor_state.dart`**

```dart
enum ServiceSaveIssue
class ServiceEditorState
final String? id
final String assetId
final String currencyCode
final ServiceRecordType type
final DateKey serviceDateKey
final String? providerName
final String? providerPhone
final Money? cost
final DateKey? nextDueDateKey
final String? notes
final bool alsoRecordAsExpense
final String? accountId
final String? paymentMethodId
final bool submitting
final ServiceSaveIssue? issue
final String? rejection
final int shakeTrigger
final bool dirty
bool get isEditing
bool get isSalary
bool get expenseIsSatisfiable
ServiceRecord toRecord({required String newId, ServiceRecord? existing})
static ServiceEditorState fromRecord(ServiceRecord record, String currencyCode)
```

---

## 7. Phase 7A defect shapes — P15–P24

**P15 — `SizeTransition` left-aligns and fills the width it is offered.** Its internal
`Align(AlignmentDirectional(-1.0, …))` has no `widthFactor`, so a min-width child is left-aligned inside a
full-width box. Give the row `MainAxisSize.max` and align its content explicitly.

**P16 — `CrossAxisAlignment.stretch` in an unbounded cross axis throws.** Wrap in `IntrinsicHeight`.

**P17 — A harness that omits a provider read during `build`.** Extends P6. **Hit three times in one
phase**, each time by adding a dependency to a provider without amending the harness in the same edit:
`settingsRepositoryProvider` (26 failures), `calendarRepositoryProvider`, then
`recurringHorizonProvider` (every screen test, rendering *nothing*). The symptom is uninformative — every
finder misses because the tree is in an error state. **Adding a dependency to a provider is a change to
every harness that mounts it.** Override at the nearest seam: a test does not care how occurrence rows
come to exist, so stub `recurringHorizonProvider`, not the repository beneath it.

**P18 — A deferral or a doc comment inherited without re-checking its premise.** The TagRepository
false-deferral, and `insight_providers.dart` claiming five reads including
`ServiceRecordRepository.watchWithNextDueInRange` while performing four and never calling it — so a
service due recorded against a service record never reached the dashboard, and the file asserted it did.

**P19 — A generated companion's required-field list is not the table's CHECK constraints.**
`AccountsCompanion.insert` names every `NOT NULL` column and says nothing about whether the *row* is
coherent. Eleven tests failed on one insert for want of `fromAccountId` on a withdrawal. Verifying against
generated code only counts for the questions actually asked of it — grep `CHECK`, not just `REFERENCES`.

**P20 — `DateKey.fromYmd` validates; it does not normalise.** `month + 1` on December is 13 and
`month - 1` on January is 0, and both throw. `DateTime.utc` *does* normalise, which is why
`DateTime.utc(y, m + 1, 0)` is a safe way to reach the last day of a month. Do month arithmetic in
absolute months:

```dart
final total = month.year * 12 + (month.month - 1) + months;
DateKey.fromYmd(total ~/ 12, total % 12 + 1, 1);
```

Also: *the same day two years on is not always a real date.* `fromYmd(2030, 2, 29)` throws, so a horizon
of "today plus two years" must use `addDays`, or the calendar and the dashboard both go blank on one day
every four years.

**P21 — `Semantics` without `container: true` creates no node**, and a package may exclude everything its
builders contribute. `table_calendar` labels each cell itself and drops descendant semantics, so a label
added in a `calendarBuilders` callback exists in the widget tree and in no semantics tree — invisible to
finders *and* to screen readers. **Dump the tree before adjusting the expectation:**
`debugDumpSemanticsTree()`. Five rounds were spent tuning an assertion against a node that could not
exist, because `find.bySemanticsLabel` reports "found 0" and cannot say what it saw.

**P22 — `addTearDown(handle.dispose)` is too late for a `SemanticsHandle`.**
`_verifySemanticsHandlesWereDisposed` runs inside `_runTestBody`, before tear-downs. Dispose inline.

**P23 — `find.byType` counts framework-inserted widgets.** Flutter wraps subtrees in its own
`IgnorePointer`s (`ignoring: false`); asserting `findsOneWidget` counted three at one width and two at
another. **Assert the property, not the type** — `widgetList<IgnorePointer>(…).any((w) => w.ignoring)`.

**P24 — An assertion on a downstream consequence fails for reasons unrelated to the behaviour.**
Testing "the days are inert" by tapping one threw `No GoRouter found in context`, because the tap
correctly fell through to the card's `InkWell`. The behaviour was right and the assertion was measuring
something else. Ask what property is meant before adjusting the finder — P21, P23 and P24 are one family.

### Harness helpers that set the viewport

`pumpCalendar` assigns `tester.view.physicalSize` **itself**, after any caller-side assignment. Pass
`size:` rather than setting `physicalSize` first, or the width under test is silently discarded and every
width-dependent assertion runs at the default.
