# Phase 1A — Core Value Objects

> **v1.4.** Your `android/` configuration was reviewed and is correct — `newDsl=false` and
> `builtInKotlin=false` were already set, `build.gradle.kts` has no `jcenter()`, and `:app`
> configures cleanly. The build failure is caused entirely by **`pubspec.yaml`**, which is
> replaced below.
>
> **What changed since the version you copied:**
> 1. `pubspec.yaml` — was declaring all 23 phases' packages with `any` constraints.
>    `file_picker: any` resolved to **3.0.4 (2020)**, whose `android/build.gradle` calls
>    `jcenter()`, removed from Gradle in 9.0. Now declares only what Phase 1A imports:
>    `intl`, `uuid`, and dev `very_good_analysis`, with bounded ranges. **This is the fix.**
> 2. **New:** `AndroidManifest.xml` + `res/xml/data_extraction_rules.xml` — your manifest has
>    no `android:allowBackup`, so it defaults to `true` and Android would upload the plaintext
>    financial database to Google Drive. Severity 1 (A42). Moved from Phase 8B to here because
>    the database arrives in Phase 1B. The manifest is otherwise byte-for-byte yours.
> 3. **New:** `lib/main.dart` — a `PHASE_05` placeholder smoke screen; every row should show a
>    green tick on the device.
> 4. Four compile fixes and one normalizer logic fix, carried over from v1.2. No Dart file has
>    changed since then.
>
> **Delete `pubspec.lock` before `flutter pub get`** — it still pins file_picker 3.0.4.
> The AGP 9 "Flutter Fix" panel in your log is a false positive; ignore it.

### `pubspec.yaml`

```yaml
name: alaya
description: Alaya — a finance and home management app.
publish_to: "none"
version: 0.1.0+1

environment:
  sdk: ^3.12.0
  flutter: ">=3.44.0"

# ─────────────────────────────────────────────────────────────────────────────────────────
# DEPENDENCY POLICY (ARCH_1 §7.4). Two rules, both learned the hard way.
#
# 1. NEVER `any`, and never a hand-typed version.
#    `any` has no floor. Pub prefers the newest version, but when a newer version creates
#    the slightest friction it walks backwards — and pre-null-safety packages declare very
#    loose bounds (sdk: '>=1.8.0 <3.0.0'), so ancient releases are EASIER to satisfy than
#    modern ones. `file_picker: any` silently resolved to 3.0.4 (from 2020), whose
#    android/build.gradle calls jcenter() — a method Gradle no longer has. Add packages with
#    `flutter pub add <pkg>`, which writes the current version as a caret floor.
#
# 2. Add a package in the PHASE THAT FIRST IMPORTS IT, not up front.
#    Every plugin listed here is configured by Gradle on every build, whether any Dart code
#    imports it or not. Front-loading all 23 phases' plugins means ~20 chances to fail the
#    build before one line of Phase 1A runs. See ARCH_1 §7 for the phase→package map.
#
# Phase 1A imports exactly two third-party packages: intl and uuid.
# The ranges below are deliberately wide with a post-null-safety floor: they cannot reach an
# ancient release, and they resolve to whatever is current. If either fails to resolve, run
# `flutter pub add intl uuid` and let pub write the exact constraint.
# ─────────────────────────────────────────────────────────────────────────────────────────

dependencies:
  flutter:
    sdk: flutter

  # Locale-aware separators for MoneyParser / MoneyFormatter / UnitConverter / QtyFormatter.
  intl: ">=0.18.0 <2.0.0"

  # UUIDv7 primary keys (Law L5). v7() requires uuid 4.x or newer.
  uuid: ">=4.0.0 <6.0.0"

dev_dependencies:
  flutter_test:
    sdk: flutter

  # Lint baseline included by analysis_options.yaml.
  very_good_analysis: ">=5.0.0 <20.0.0"

flutter:
  uses-material-design: true

```

### `analysis_options.yaml`

```yaml
# Alaya static analysis configuration. See ARCH_1_FOUNDATION.md §6 for the layering rule
# this file documents and `tool/check_layering.dart` enforces.
#
# LAYERING RULE (Law L12): features/ -> domain/ -> core/, and data/ -> domain/ -> core/.
#   - lib/domain/ must NEVER import package:flutter/*, package:drift/*, or anything under
#     lib/data/. It is pure Dart so every business rule is unit-testable without a device.
#   - lib/core/ must NEVER import package:flutter/* either, so that a future domain/ import
#     of a core/ file can never transitively drag Flutter into the domain layer.
#   The Dart analyzer has no built-in "banned import per path glob" lint, and adding a
#   third-party lint plugin isn't in ARCH_1 §7's pinned tech stack, so this rule is checked
#   by a small, dependency-free script instead: run `dart run tool/check_layering.dart`
#   (wire this into CI once CI exists). It exits non-zero and names the offending file and
#   import if the rule is violated.

include: package:very_good_analysis/analysis_options.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  exclude:
    - "**/*.g.dart"
    - "**/*.drift.dart"
    - "lib/data/db/migrations/schema/**"
  errors:
    # Doc comments are a project convention (one line per public API, more only when the
    # logic is genuinely non-obvious) rather than an analyzer-enforced rule.
    public_member_api_docs: ignore

linter:
  rules:
    prefer_relative_imports: false
    unnecessary_final: false

```

### `android/app/src/main/AndroidManifest.xml`

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- android:allowBackup="false" is MANDATORY (ARCH_3 §2.4, anomaly A42).
         The database is plaintext. Android's auto-backup defaults to ON, which would
         silently upload the complete financial database to the user's Google Drive —
         outside the app's control and outside anything the Play data-safety form declares.
         This also blocks `adb backup` extraction. Do not remove either attribute.

         allowBackup="false" disables backup on API 30 and below; dataExtractionRules
         covers API 31+, where cloud-backup and device-transfer are controlled separately. -->
    <application
        android:label="Alaya"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:allowBackup="false"
        android:dataExtractionRules="@xml/data_extraction_rules">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <!-- Specifies an Android theme to apply to this Activity as soon as
                 the Android process has started. This theme is visible to the user
                 while the Flutter UI initializes. After that, this theme continues
                 to determine the Window background behind the Flutter UI. -->
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <!-- Required to query activities that can process text, see:
         https://developer.android.com/training/package-visibility and
         https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.
         In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin. -->
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>

```

### `android/app/src/main/res/xml/data_extraction_rules.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- API 31+ backup controls. Excludes everything from both cloud backup and device-to-device
     transfer, because the app's database is plaintext (ARCH_1 §2.1) and must never leave the
     device except through the user's own explicit export (ARCH_3 §3). See anomaly A42. -->
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="root" path="." />
    </cloud-backup>
    <device-transfer>
        <exclude domain="root" path="." />
    </device-transfer>
</data-extraction-rules>

```

### `lib/main.dart`

```dart
// PLACEHOLDER: PHASE_05 — replaced by app/app.dart + app/bootstrap.dart with the real
// theme, router and drawer shell. Until then this renders Phase 1A's core value objects on
// the device so the build and the primitives can be verified without a test runner.
import 'package:flutter/material.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/money_formatter.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/text/normalizer.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';

void main() => runApp(const AlayaSmokeApp());

/// Temporary root widget for Phase 1A verification.
class AlayaSmokeApp extends StatelessWidget {
  /// Creates the Phase 1A smoke-test app.
  const AlayaSmokeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Alaya — Phase 1A',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B6E5C)),
          useMaterial3: true,
        ),
        home: const _SmokeScreen(),
      );
}

class _SmokeScreen extends StatelessWidget {
  const _SmokeScreen();

  @override
  Widget build(BuildContext context) {
    const qtyFormatter = QtyFormatter();
    const moneyFormatter = MoneyFormatter();
    const normalizer = Normalizer();
    const clock = SystemClock();

    final summed = const Qty(250000, UnitCategory.weight) +
        const Qty(2000000, UnitCategory.weight) +
        const Qty(1500000, UnitCategory.weight) +
        const Qty(700000, UnitCategory.weight);

    final rows = <(String, String, String)>[
      ('Qty sum → mixed', qtyFormatter.format(summed), '4 kg 450 g'),
      (
        'Qty zero-part suppression',
        qtyFormatter.format(const Qty(2000000, UnitCategory.weight)),
        '2 kg',
      ),
      (
        'Qty volume carry',
        qtyFormatter.format(const Qty(1200000, UnitCategory.volume)),
        '1 L 200 ml',
      ),
      (
        'Qty sub-base count',
        qtyFormatter.format(const Qty(500, UnitCategory.count)),
        '0.5 pc',
      ),
      (
        'Qty whole count',
        qtyFormatter.format(const Qty(3000, UnitCategory.count)),
        '3 pc',
      ),
      (
        'Qty compact style',
        qtyFormatter.format(summed, style: UnitStyle.compact),
        '4.45 kg',
      ),
      (
        'Money en_IN lakh grouping',
        moneyFormatter.format(
          const Money(123456700, 'INR'),
          decimalDigits: 2,
          symbol: '₹',
        ),
        '₹12,34,567.00',
      ),
      (
        'Money zero-decimal (JPY)',
        moneyFormatter.format(
          const Money(1234567, 'JPY'),
          decimalDigits: 0,
          symbol: '¥',
          localeTag: 'ja_JP',
        ),
        '¥1,234,567',
      ),
      ('Normalizer ligature', normalizer.normalize('CAFÉ-Au-Lait!!'), 'cafe au lait'),
      ('Normalizer œ ligature', normalizer.normalize('Œuf'), 'oeuf'),
      ('DateKey today', clock.today().toIso(), '(today, local)'),
      ('DateKey monthKey', '${clock.today().monthKey}', '(yyyymm)'),
      (
        'DateKey month-end + 1',
        DateKey.fromYmd(2026, 7, 31).addDays(1).toIso(),
        '2026-08-01',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Alaya — Phase 1A core')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final (label, actual, expected) = rows[i];
          final matches = expected.startsWith('(') || actual == expected;
          return ListTile(
            dense: true,
            leading: Icon(
              matches ? Icons.check_circle_outline : Icons.error_outline,
              color: matches ? Colors.green.shade700 : Colors.red.shade700,
            ),
            title: Text(label),
            subtitle: Text(
              matches ? actual : '$actual   (expected $expected)',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          );
        },
      ),
    );
  }
}

```

### `lib/core/ids/uid.dart`

```dart
import 'package:uuid/uuid.dart' as pkg_uuid;

/// Generates the identifiers used for every table's `TEXT` primary key (Law L5). Injected
/// wherever an id is created so tests can substitute a deterministic generator.
abstract interface class UidGenerator {
  /// A new, globally unique identifier.
  String generate();
}

/// The production [UidGenerator]: RFC 9562 UUIDv7, time-ordered so rows created later sort
/// after rows created earlier even without an extra `createdAt` index.
final class Uuid7Generator implements UidGenerator {
  /// Creates a generator backed by `package:uuid`.
  const Uuid7Generator();

  static const pkg_uuid.Uuid _uuid = pkg_uuid.Uuid();

  @override
  String generate() => _uuid.v7();
}

/// A deterministic [UidGenerator] for tests: returns `prefix-0`, `prefix-1`, ... in call
/// order, so fixtures and assertions can reference ids without reading generated values.
final class SequentialUidGenerator implements UidGenerator {
  /// Creates a generator whose ids are `'$prefix-$n'` for an incrementing counter `n`.
  SequentialUidGenerator({this.prefix = 'test'});

  /// The fixed prefix used for every generated id.
  final String prefix;

  int _next = 0;

  @override
  String generate() => '$prefix-${_next++}';
}

```

### `lib/core/time/date_key.dart`

```dart
/// A local civil date stored as an integer `yyyymmdd` (e.g. `20260728`), with zero runtime
/// overhead over the `int` it wraps. Deliberately has no timezone or time-of-day component
/// (Law L4): a bill "due on the 5th" is the 5th regardless of where the user is standing,
/// which is why this is never a `DateTime`/instant. `DateKey(rawValue)` does not validate —
/// it exists for cheap, trusted round-tripping of a value already known to be valid (e.g.
/// hydrating a database row). Build a validated instance from components with
/// [DateKey.fromYmd] or [DateKey.fromDateTime].
///
/// Note this cannot declare `implements Comparable<DateKey>`: an extension type may only
/// implement supertypes of its representation type, and `int` implements `Comparable<num>`,
/// not `Comparable<DateKey>`. [compareTo] is therefore a plain method, and sorting a
/// `List<DateKey>` uses the static [DateKey.compare] as an explicit comparator.
extension type const DateKey(int value) {
  /// Builds a validated [DateKey] from calendar components. Throws [ArgumentError] if the
  /// combination isn't a real calendar date (e.g. 30 February).
  factory DateKey.fromYmd(int year, int month, int day) {
    if (month < 1 || month > 12) {
      throw ArgumentError.value(month, 'month', 'must be between 1 and 12');
    }
    if (day < 1 || day > 31) {
      throw ArgumentError.value(day, 'day', 'must be between 1 and 31');
    }
    final rolled = DateTime.utc(year, month, day);
    if (rolled.year != year || rolled.month != month || rolled.day != day) {
      throw ArgumentError('$year-$month-$day is not a real calendar date');
    }
    return DateKey(year * 10000 + month * 100 + day);
  }

  /// Builds a [DateKey] from [dateTime]'s own year/month/day fields, taken exactly as they
  /// are on [dateTime] — this never calls `.toUtc()`, so passing a local `DateTime` yields
  /// the local civil date, which is almost always what "today" should mean.
  factory DateKey.fromDateTime(DateTime dateTime) =>
      DateKey.fromYmd(dateTime.year, dateTime.month, dateTime.day);

  /// The 4-digit year component.
  int get year => value ~/ 10000;

  /// The 1-based month component, `1`-`12`.
  int get month => (value ~/ 100) % 100;

  /// The 1-based day-of-month component.
  int get day => value % 100;

  /// The `yyyymm` month this date falls in, e.g. `20260728` → `202607`.
  int get monthKey => value ~/ 100;

  /// ISO weekday: `1` (Monday) through `7` (Sunday).
  int get weekday => toUtcMidnight().weekday;

  /// This date as a UTC-anchored midnight [DateTime]. This exists purely as a calculation
  /// vehicle for calendar arithmetic (UTC has no DST jumps, so day-arithmetic is exact) — it
  /// is never a real instant and must never be persisted as one.
  DateTime toUtcMidnight() => DateTime.utc(year, month, day);

  /// A new [DateKey] this many calendar days after this one. [days] may be negative.
  DateKey addDays(int days) => DateKey.fromDateTime(toUtcMidnight().add(Duration(days: days)));

  /// The number of calendar days from [other] to this date; positive when this date is
  /// later, negative when earlier.
  int diffDays(DateKey other) => toUtcMidnight().difference(other.toUtcMidnight()).inDays;

  /// True if this date is strictly before [other].
  bool isBefore(DateKey other) => value < other.value;

  /// True if this date is strictly after [other].
  bool isAfter(DateKey other) => value > other.value;

  /// True if this date is on or after [start] and on or before [end] (inclusive).
  bool isWithin(DateKey start, DateKey end) => value >= start.value && value <= end.value;

  /// Compares this date with [other]: negative if earlier, zero if equal, positive if later.
  int compareTo(DateKey other) => value.compareTo(other.value);

  /// A comparator for sorting, e.g. `dates.sort(DateKey.compare)`. Needed because an
  /// extension type cannot implement `Comparable<DateKey>` (see the class doc), so the
  /// zero-argument `List.sort()` is unavailable.
  static int compare(DateKey a, DateKey b) => a.value.compareTo(b.value);

  /// True if this date is strictly before [other].
  bool operator <(DateKey other) => value < other.value;

  /// True if this date is before or the same as [other].
  bool operator <=(DateKey other) => value <= other.value;

  /// True if this date is strictly after [other].
  bool operator >(DateKey other) => value > other.value;

  /// True if this date is after or the same as [other].
  bool operator >=(DateKey other) => value >= other.value;

  /// Renders as `yyyy-mm-dd` for logs and debugging only — never for UI display.
  String toIso() => '$year-${_twoDigits(month)}-${_twoDigits(day)}';

  static String _twoDigits(int n) => n < 10 ? '0$n' : '$n';
}

```

### `lib/core/time/clock.dart`

```dart
import 'date_key.dart';

/// Supplies the current time so it can be faked in tests; no code outside this file should
/// call `DateTime.now()` directly. Deliberately a single-method interface: the derived values
/// live in [ClockDerived] as extension methods, so an implementation only ever has to supply
/// [now] and the derived values can never drift out of sync with it.
abstract interface class Clock {
  /// The current local wall-clock date and time.
  DateTime now();
}

/// Values derived from [Clock.now]. Extension methods rather than interface members with
/// default bodies: `implements` inherits an interface but not its method bodies, so a default
/// body on the interface would force every implementer to redeclare it anyway.
extension ClockDerived on Clock {
  /// The current instant as epoch milliseconds UTC (Law L4's instant representation).
  int nowUtcMillis() => now().toUtc().millisecondsSinceEpoch;

  /// Today's date in the device's local timezone, as a civil [DateKey].
  DateKey today() => DateKey.fromDateTime(now());
}

/// The production [Clock], backed by the real system time.
final class SystemClock implements Clock {
  /// Creates a clock that reads the device's real wall-clock time.
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// A [Clock] fixed to one instant, for deterministic tests. Call [advance] to move it
/// forward within a test instead of constructing a new instance each time.
final class FixedClock implements Clock {
  /// Creates a clock fixed at [initial].
  FixedClock(DateTime initial) : _current = initial;

  DateTime _current;

  @override
  DateTime now() => _current;

  /// Moves this clock forward by [duration] (or backward, if negative).
  void advance(Duration duration) => _current = _current.add(duration);

  /// Sets this clock to exactly [dateTime].
  void setTo(DateTime dateTime) => _current = dateTime;
}

```

### `lib/core/money/money.dart`

```dart
import 'dart:math' as math;

import 'rounding.dart';

/// An exact monetary amount: integer minor units (e.g. paise, cents) plus a currency code.
/// Never backed by a `double` (Law L1). This type deliberately does not know how many
/// decimal digits its own currency uses — that comes from the `currencies` table at the
/// call site (never hardcode `100`; see ARCH_1 §4.1) — so every operation that needs to
/// interpret [minor] as a decimal amount takes `decimalDigits` as an explicit parameter.
final class Money implements Comparable<Money> {
  /// Creates a [Money] directly from already-computed minor units. Prefer [MoneyParser] to
  /// build one from user-typed text.
  const Money(this.minor, this.currencyCode);

  /// A zero amount in [currencyCode].
  const Money.zero(String currencyCode) : this(0, currencyCode);

  /// The amount in minor units (e.g. paise, cents). Always a whole number.
  final int minor;

  /// The currency code, e.g. `'INR'`. Matches a row in the `currencies` table.
  final String currencyCode;

  /// True if [minor] is less than zero.
  bool get isNegative => minor < 0;

  /// True if [minor] is greater than zero.
  bool get isPositive => minor > 0;

  /// True if [minor] is exactly zero.
  bool get isZero => minor == 0;

  /// Adds [other]. Throws [CurrencyMismatchError] if the currencies differ.
  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(minor + other.minor, currencyCode);
  }

  /// Subtracts [other]. Throws [CurrencyMismatchError] if the currencies differ.
  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(minor - other.minor, currencyCode);
  }

  /// Scales this amount by the integer [factor].
  Money operator *(int factor) => Money(minor * factor, currencyCode);

  /// The negation of this amount, in the same currency.
  Money operator -() => Money(-minor, currencyCode);

  /// The absolute value of this amount, in the same currency.
  Money abs() => isNegative ? -this : this;

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minor.compareTo(other.minor);
  }

  /// True if this amount is strictly less than [other]. Throws [CurrencyMismatchError] if
  /// the currencies differ.
  bool operator <(Money other) {
    _assertSameCurrency(other);
    return minor < other.minor;
  }

  /// True if this amount is less than or equal to [other]. Throws [CurrencyMismatchError]
  /// if the currencies differ.
  bool operator <=(Money other) {
    _assertSameCurrency(other);
    return minor <= other.minor;
  }

  /// True if this amount is strictly greater than [other]. Throws [CurrencyMismatchError]
  /// if the currencies differ.
  bool operator >(Money other) {
    _assertSameCurrency(other);
    return minor > other.minor;
  }

  /// True if this amount is greater than or equal to [other]. Throws [CurrencyMismatchError]
  /// if the currencies differ.
  bool operator >=(Money other) {
    _assertSameCurrency(other);
    return minor >= other.minor;
  }

  /// Converts this amount into [toCurrencyCode] using [rate] (units of [toCurrencyCode] per
  /// 1 unit of this currency), accounting for each currency's own decimal precision. This is
  /// the one sanctioned place in the app that rounds money; [rounding] defaults to
  /// [MoneyRounding.halfUp]. The result is a frozen, independent [Money] — this call never
  /// mutates `this` (Law L9: the original amount is immutable).
  Money convert({
    required double rate,
    required String toCurrencyCode,
    required int fromDecimalDigits,
    required int toDecimalDigits,
    MoneyRounding rounding = MoneyRounding.halfUp,
  }) {
    final scale = math.pow(10, toDecimalDigits - fromDecimalDigits).toDouble();
    final rawValue = minor * rate * scale;
    return Money(rounding.apply(rawValue), toCurrencyCode);
  }

  void _assertSameCurrency(Money other) {
    if (other.currencyCode != currencyCode) {
      throw CurrencyMismatchError(currencyCode, other.currencyCode);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(minor, currencyCode);

  /// A debug-only representation, e.g. `INR 12345mu`. Never use this for UI display — use
  /// [MoneyFormatter] instead.
  @override
  String toString() => '$currencyCode ${minor}mu';
}

/// Thrown when an operation combines two [Money] values in different currencies. There is
/// no implicit conversion anywhere in this type — indicates a programming error, not a
/// recoverable user-facing condition.
final class CurrencyMismatchError extends Error {
  /// Records the two currency codes that could not be combined.
  CurrencyMismatchError(this.first, this.second);

  /// The currency code of the left-hand operand.
  final String first;

  /// The currency code of the right-hand operand.
  final String second;

  @override
  String toString() => 'CurrencyMismatchError: cannot combine $first with $second directly '
      '— convert explicitly first.';
}

```

### `lib/core/money/rounding.dart`

```dart
/// Strategies for rounding a fractional minor-unit amount to an integer. Used only at the
/// single sanctioned rounding boundary in the app, [Money.convert] — nowhere else rounds
/// money (Law L1's spirit: the stored and returned amounts are always exact integers; only
/// a currency conversion, which multiplies by an inherently inexact market rate, ever needs
/// to round the result back down to one).
enum MoneyRounding {
  /// Rounds half away from zero (`2.5 → 3`, `-2.5 → -3`). The "school rounding" most people
  /// expect, and this app's default.
  halfUp,

  /// Rounds half toward zero (`2.5 → 2`, `-2.5 → -2`).
  halfDown,

  /// Rounds half to the nearest even integer (banker's rounding; `2.5 → 2`, `3.5 → 4`).
  halfEven,

  /// Always rounds toward positive infinity.
  ceiling,

  /// Always rounds toward negative infinity.
  floor;

  /// Rounds [value] to the nearest integer per this strategy.
  int apply(double value) => switch (this) {
        MoneyRounding.ceiling => value.ceil(),
        MoneyRounding.floor => value.floor(),
        MoneyRounding.halfUp =>
          value.isNegative ? -_halfUpMagnitude(-value) : _halfUpMagnitude(value),
        MoneyRounding.halfDown =>
          value.isNegative ? -_halfDownMagnitude(-value) : _halfDownMagnitude(value),
        MoneyRounding.halfEven => _halfEven(value),
      };

  static int _halfUpMagnitude(double magnitude) => (magnitude + 0.5).floor();

  static int _halfDownMagnitude(double magnitude) {
    final flooredValue = magnitude.floor();
    final fraction = magnitude - flooredValue;
    return fraction > 0.5 ? flooredValue + 1 : flooredValue;
  }

  static int _halfEven(double value) {
    final flooredValue = value.floor();
    final fraction = value - flooredValue;
    if (fraction < 0.5) return flooredValue;
    if (fraction > 0.5) return flooredValue + 1;
    return flooredValue.isEven ? flooredValue : flooredValue + 1;
  }
}

```

### `lib/core/money/money_parser.dart`

```dart
import 'package:intl/intl.dart';

import '../result/failure.dart';
import '../result/result.dart';
import 'money.dart';

/// Parses user-typed monetary text into [Money], honouring locale-specific decimal and
/// grouping separators. Never throws — every outcome, including a still-being-typed or
/// malformed string, comes back as a [Result] so the UI can decide how to react instead of
/// crashing. Converts the decimal text to minor units using exact string/integer
/// manipulation only; a `double` is never involved (Law L1), which also means this parser
/// never silently rounds a typed value — a currency's precision is enforced by rejecting
/// extra digits (see [ParseFailure.tooManyDecimalDigits]), not by discarding them.
final class MoneyParser {
  /// Creates a parser. Stateless — safe to use as a `const` singleton.
  const MoneyParser();

  static const int _maxInputLength = 24;

  /// Parses [input] as an amount in [currencyCode] with [decimalDigits] decimal places.
  /// [localeTag] (e.g. `'en_IN'`, `'de_DE'`) determines which characters are the decimal
  /// point and the grouping separator. Negative input is rejected unless [allowNegative].
  Result<Money, ParseFailure> parse(
    String input, {
    required String currencyCode,
    required int decimalDigits,
    String localeTag = 'en',
    bool allowNegative = false,
  }) {
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
    final groupSep = symbols.GROUP_SEP;
    final decimalSep = symbols.DECIMAL_SEP;

    if (groupSep.isNotEmpty) {
      text = text.replaceAll(groupSep, '');
    }
    if (text.isEmpty) return const Result.failure(ParseFailure.malformed);

    final decimalParts = decimalSep.isEmpty ? [text] : text.split(decimalSep);
    if (decimalParts.length > 2) return const Result.failure(ParseFailure.malformed);

    final wholePart = decimalParts[0];
    final fracPart = decimalParts.length == 2 ? decimalParts[1] : '';

    if (wholePart.isEmpty && fracPart.isEmpty) {
      return const Result.failure(ParseFailure.malformed);
    }
    if (!_isDigitsOnly(wholePart) || !_isDigitsOnly(fracPart)) {
      return const Result.failure(ParseFailure.invalidCharacter);
    }
    if (fracPart.length > decimalDigits) {
      return const Result.failure(ParseFailure.tooManyDecimalDigits);
    }

    final paddedFrac = fracPart.padRight(decimalDigits, '0');
    final digitString = '${wholePart.isEmpty ? '0' : wholePart}$paddedFrac';
    final magnitude = int.parse(digitString);

    return Result.ok(Money(sign * magnitude, currencyCode));
  }

  static bool _isDigitsOnly(String value) {
    for (final codeUnit in value.codeUnits) {
      if (codeUnit < 0x30 || codeUnit > 0x39) return false;
    }
    return true;
  }
}

```

### `lib/core/money/money_formatter.dart`

```dart
import 'package:intl/intl.dart';

import 'money.dart';

/// Renders [Money] as a locale-correct display string, including digit grouping. Deliberately
/// does not delegate grouping to `intl`'s `NumberFormat`: that class only supports a single,
/// uniform group size, so it cannot produce Indian lakh/crore grouping (2-2-3 digits) —
/// see dart-lang/i18n#349, an open feature request for exactly this. Instead, this formatter
/// uses `NumberFormat` only to look up which characters a locale uses as its decimal point
/// and group separator, and performs the actual digit grouping itself with exact integer and
/// string operations (never a `double`, consistent with Law L1). A purely display-layer
/// concern: it never mutates or rounds the underlying integer minor units.
final class MoneyFormatter {
  /// Creates a formatter. Stateless — safe to use as a `const` singleton.
  const MoneyFormatter();

  /// Formats [money] for display. [decimalDigits] and [symbol] must come from the
  /// `currencies` table (never hardcoded — see ARCH_1 §4.1); [localeTag] controls only
  /// digit grouping and the decimal separator character.
  String format(
    Money money, {
    required int decimalDigits,
    required String symbol,
    String localeTag = 'en_IN',
    bool showPlusSign = false,
  }) {
    final magnitude = money.minor.abs();
    final divisor = _pow10(decimalDigits);
    final whole = magnitude ~/ divisor;
    final frac = magnitude % divisor;

    final symbols = NumberFormat.decimalPattern(localeTag).symbols;
    final groupedWhole = _groupDigits(
      whole.toString(),
      groupSeparator: symbols.GROUP_SEP,
      useIndianGrouping: _isIndianLocale(localeTag),
    );

    final fracStr = decimalDigits == 0
        ? ''
        : '${symbols.DECIMAL_SEP}${frac.toString().padLeft(decimalDigits, '0')}';

    final sign = money.isNegative ? '-' : (showPlusSign && money.isPositive ? '+' : '');

    return '$sign$symbol$groupedWhole$fracStr';
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  /// True for locales whose region subtag is India, which use 2-2-3 grouping (lakh/crore)
  /// rather than the 3-3-3 grouping most other locales use.
  static bool _isIndianLocale(String localeTag) {
    final region = localeTag.split(RegExp('[_-]')).last.toUpperCase();
    return region == 'IN';
  }

  /// Groups [digits] (a plain non-negative integer string) into the target locale's scheme:
  /// a final group of 3 digits, then repeating groups of 2 (Indian) or 3 (Western) moving
  /// left, joined by [groupSeparator].
  static String _groupDigits(
    String digits, {
    required String groupSeparator,
    required bool useIndianGrouping,
  }) {
    if (groupSeparator.isEmpty || digits.length <= 3) return digits;

    final secondaryGroupSize = useIndianGrouping ? 2 : 3;
    final primaryGroup = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);

    final groups = <String>[];
    while (rest.length > secondaryGroupSize) {
      groups.insert(0, rest.substring(rest.length - secondaryGroupSize));
      rest = rest.substring(0, rest.length - secondaryGroupSize);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    groups.add(primaryGroup);

    return groups.join(groupSeparator);
  }
}

```

### `lib/core/quantity/unit_category.dart`

```dart
/// The three fixed physical quantity categories [Qty] can hold. No fourth category is ever
/// added (ARCH_1 §5.3): if an amount can't be expressed in one of these, the correct action
/// is a new Item, never a new category — this keeps cross-category conversion permanently
/// impossible to express (Law L8), rather than merely discouraged.
enum UnitCategory {
  /// Measured by mass. Base unit: gram.
  weight,

  /// Measured by capacity. Base unit: millilitre.
  volume,

  /// Measured by count. Base unit: piece. Never decomposed into a bigger/smaller unit pair.
  count;

  /// The canonical base unit code for this category: `'g'`, `'ml'`, or `'pc'`.
  String get baseUnitCode => switch (this) {
        UnitCategory.weight => 'g',
        UnitCategory.volume => 'ml',
        UnitCategory.count => 'pc',
      };
}

```

### `lib/core/quantity/qty.dart`

```dart
import 'unit_category.dart';

/// An exact physical quantity: integer milli-base-units (the category's base unit × 1000)
/// plus a [UnitCategory]. Never backed by a `double` (Law L2). The ×1000 scale exists so a
/// half-piece or a fraction-of-a-gram spice measurement is still an exact integer — plain
/// base units would satisfy every whole-number example and then fail the first time someone
/// records `0.5 pc` or `0.25 g`. Arithmetic across categories throws
/// [UnitCategoryMismatchError] (Law L8) — there is no gram↔millilitre conversion.
final class Qty implements Comparable<Qty> {
  /// Creates a [Qty] directly from already-computed milli-base-units.
  const Qty(this.milliBase, this.category);

  /// A zero quantity in [category].
  const Qty.zero(UnitCategory category) : this(0, category);

  /// The quantity in milli-base-units, e.g. milli-grams-of-the-base-gram for weight.
  final int milliBase;

  /// Which of the three fixed categories this quantity belongs to.
  final UnitCategory category;

  /// True if [milliBase] is less than zero.
  bool get isNegative => milliBase < 0;

  /// True if [milliBase] is greater than zero.
  bool get isPositive => milliBase > 0;

  /// True if [milliBase] is exactly zero.
  bool get isZero => milliBase == 0;

  /// Adds [other]. Throws [UnitCategoryMismatchError] if the categories differ.
  Qty operator +(Qty other) {
    _assertSameCategory(other);
    return Qty(milliBase + other.milliBase, category);
  }

  /// Subtracts [other]. Throws [UnitCategoryMismatchError] if the categories differ.
  Qty operator -(Qty other) {
    _assertSameCategory(other);
    return Qty(milliBase - other.milliBase, category);
  }

  /// Scales this quantity by the integer [factor].
  Qty operator *(int factor) => Qty(milliBase * factor, category);

  /// The negation of this quantity, in the same category.
  Qty operator -() => Qty(-milliBase, category);

  @override
  int compareTo(Qty other) {
    _assertSameCategory(other);
    return milliBase.compareTo(other.milliBase);
  }

  /// True if this quantity is strictly less than [other]. Throws [UnitCategoryMismatchError]
  /// if the categories differ.
  bool operator <(Qty other) {
    _assertSameCategory(other);
    return milliBase < other.milliBase;
  }

  /// True if this quantity is less than or equal to [other]. Throws
  /// [UnitCategoryMismatchError] if the categories differ.
  bool operator <=(Qty other) {
    _assertSameCategory(other);
    return milliBase <= other.milliBase;
  }

  /// True if this quantity is strictly greater than [other]. Throws
  /// [UnitCategoryMismatchError] if the categories differ.
  bool operator >(Qty other) {
    _assertSameCategory(other);
    return milliBase > other.milliBase;
  }

  /// True if this quantity is greater than or equal to [other]. Throws
  /// [UnitCategoryMismatchError] if the categories differ.
  bool operator >=(Qty other) {
    _assertSameCategory(other);
    return milliBase >= other.milliBase;
  }

  void _assertSameCategory(Qty other) {
    if (other.category != category) {
      throw UnitCategoryMismatchError(category, other.category);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Qty && other.milliBase == milliBase && other.category == category;

  @override
  int get hashCode => Object.hash(milliBase, category);

  /// A debug-only representation, e.g. `2500000m(weight)`. Never use this for UI display —
  /// use [QtyFormatter] instead.
  @override
  String toString() => '${milliBase}m(${category.name})';
}

/// Thrown when an operation combines two [Qty] values from different [UnitCategory]s. There
/// is no gram↔millilitre conversion anywhere in this type — indicates a programming error,
/// not a recoverable user-facing condition.
final class UnitCategoryMismatchError extends Error {
  /// Records the two categories that could not be combined.
  UnitCategoryMismatchError(this.first, this.second);

  /// The category of the left-hand operand.
  final UnitCategory first;

  /// The category of the right-hand operand.
  final UnitCategory second;

  @override
  String toString() =>
      'UnitCategoryMismatchError: cannot combine ${first.name} with ${second.name}.';
}

```

### `lib/core/quantity/unit_converter.dart`

```dart
import 'package:intl/intl.dart';

import '../result/failure.dart';
import '../result/result.dart';

/// Converts between a user-typed decimal quantity in some unit and the canonical integer
/// milliBase representation, using only integer arithmetic (Law L2). Unlike a currency's
/// exchange rate, a unit's `factorToBaseMilli` is always exact (e.g. `1 kg = 1_000_000`
/// milliBase, exactly), so this converter never needs the rate-multiplication tolerance
/// [Money.convert] does — the rare factor/precision combination that doesn't divide evenly
/// is resolved with half-up integer rounding, never a `double`.
final class UnitConverter {
  /// Creates a converter. Stateless — safe to use as a `const` singleton.
  const UnitConverter();

  static const int _maxInputLength = 24;

  /// Parses [input] — a decimal quantity in some unit — into milliBase, where one unit of
  /// the input equals [unitFactorMilliBase] milliBase units (e.g. `1_000_000` for `kg`).
  /// [localeTag] determines the decimal and grouping separator characters. Rounds half up
  /// on the rare factor/input combination that doesn't divide evenly.
  Result<int, ParseFailure> parseToMilliBase(
    String input, {
    required int unitFactorMilliBase,
    String localeTag = 'en',
    bool allowNegative = false,
  }) {
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
    final groupSep = symbols.GROUP_SEP;
    final decimalSep = symbols.DECIMAL_SEP;

    if (groupSep.isNotEmpty) {
      text = text.replaceAll(groupSep, '');
    }
    if (text.isEmpty) return const Result.failure(ParseFailure.malformed);

    final parts = decimalSep.isEmpty ? [text] : text.split(decimalSep);
    if (parts.length > 2) return const Result.failure(ParseFailure.malformed);

    final wholePart = parts[0];
    final fracPart = parts.length == 2 ? parts[1] : '';

    if (wholePart.isEmpty && fracPart.isEmpty) {
      return const Result.failure(ParseFailure.malformed);
    }
    if (!_isDigitsOnly(wholePart) || !_isDigitsOnly(fracPart)) {
      return const Result.failure(ParseFailure.invalidCharacter);
    }

    final numerator = int.parse('${wholePart.isEmpty ? '0' : wholePart}$fracPart');
    final denominator = _pow10(fracPart.length);
    final product = numerator * unitFactorMilliBase;
    final milliBase = (product + denominator ~/ 2) ~/ denominator;

    return Result.ok(sign * milliBase);
  }

  /// Splits [milliBase] into a whole count of units (each equal to [unitFactorMilliBase]
  /// milliBase) and the milliBase remainder. Intended for non-negative, already-stored
  /// quantities; see [Qty] for arithmetic on values that might be negative.
  ({int wholeUnits, int remainderMilliBase}) decompose(int milliBase, int unitFactorMilliBase) {
    return (
      wholeUnits: milliBase ~/ unitFactorMilliBase,
      remainderMilliBase: milliBase % unitFactorMilliBase,
    );
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

### `lib/core/quantity/qty_formatter.dart`

```dart
import 'package:intl/intl.dart';

import 'qty.dart';
import 'unit_category.dart';

/// Controls how [QtyFormatter] renders a quantity. See ARCH_1 §5.2.
enum UnitStyle {
  /// Decomposes weight/volume into their carry pair (`"4 kg 450 g"`) and leaves `count` as a
  /// single number (`"3 pc"`). The default; used for item rows and batch chips.
  mixed,

  /// A single decimal number in the bigger unit for weight/volume, rounded to 2 decimal
  /// places (`"4.45 kg"`); identical to [mixed] for `count`. Used for dense chart axes and
  /// narrow chips only.
  compact,

  /// The raw base unit with no decomposition (`"4450 g"`); identical to [mixed] for `count`.
  /// Used for debug output and export.
  base,
}

/// Renders a [Qty] as a human-readable string per ARCH_1 §5.2. Pure and stateless: the same
/// [Qty] and [UnitStyle] always produce the same string. The unit vocabulary (`kg`, `g`,
/// `L`, `ml`, `pc`) is always these English abbreviations regardless of locale; [localeTag]
/// controls only the decimal separator character used in [UnitStyle.compact].
final class QtyFormatter {
  /// Creates a formatter. Stateless — safe to use as a `const` singleton.
  const QtyFormatter();

  static const int _milliPerBaseUnit = 1000;
  static const int _milliPerBigUnit = _milliPerBaseUnit * 1000; // 1 kg or 1 L, in milliBase

  /// Formats [qty] according to [style].
  String format(Qty qty, {UnitStyle style = UnitStyle.mixed, String localeTag = 'en'}) {
    final isNegative = qty.isNegative;
    final magnitude = isNegative ? -qty.milliBase : qty.milliBase;
    final sign = isNegative ? '-' : '';
    final body = switch (style) {
      UnitStyle.mixed => _formatMixed(magnitude, qty.category),
      UnitStyle.compact => _formatCompact(magnitude, qty.category, localeTag),
      UnitStyle.base => _formatBase(magnitude, qty.category),
    };
    return '$sign$body';
  }

  String _formatMixed(int magnitude, UnitCategory category) {
    return switch (category) {
      UnitCategory.count => '${_formatThousandths(magnitude)} pc',
      UnitCategory.weight => _formatCarryPair(magnitude, smallUnit: 'g', bigUnit: 'kg'),
      UnitCategory.volume => _formatCarryPair(magnitude, smallUnit: 'ml', bigUnit: 'L'),
    };
  }

  String _formatCarryPair(int magnitude, {required String smallUnit, required String bigUnit}) {
    final bigWhole = magnitude ~/ _milliPerBigUnit;
    final remainderMilli = magnitude % _milliPerBigUnit;

    if (bigWhole == 0) {
      return '${_formatThousandths(remainderMilli)} $smallUnit';
    }
    if (remainderMilli == 0) {
      return '$bigWhole $bigUnit';
    }
    return '$bigWhole $bigUnit ${_formatThousandths(remainderMilli)} $smallUnit';
  }

  String _formatCompact(int magnitude, UnitCategory category, String localeTag) {
    if (category == UnitCategory.count) return '${_formatThousandths(magnitude)} pc';

    final bigUnit = category == UnitCategory.weight ? 'kg' : 'L';
    // Half-up rounding to 2 decimal places of the big-unit value, via pure integer math:
    // hundredths = round(magnitude * 100 / 1_000_000).
    final hundredths = (magnitude * 100 + _milliPerBigUnit ~/ 2) ~/ _milliPerBigUnit;
    final whole = hundredths ~/ 100;
    final frac = hundredths % 100;
    final fracStr = frac.toString().padLeft(2, '0');
    return '$whole${_decimalSeparator(localeTag)}$fracStr $bigUnit';
  }

  String _formatBase(int magnitude, UnitCategory category) {
    final unit = category.baseUnitCode;
    return '${_formatThousandths(magnitude)} $unit';
  }

  /// Formats [valueMilli] (a count of thousandths of some unit) as that unit's exact
  /// decimal value, e.g. `450_000` → `"450"`, `500` → `"0.5"`, `5` → `"0.005"`, `0` → `"0"`.
  static String _formatThousandths(int valueMilli) {
    final whole = valueMilli ~/ _milliPerBaseUnit;
    final frac = valueMilli % _milliPerBaseUnit;
    if (frac == 0) return '$whole';

    var fracStr = frac.toString().padLeft(3, '0');
    while (fracStr.endsWith('0')) {
      fracStr = fracStr.substring(0, fracStr.length - 1);
    }
    return '$whole.$fracStr';
  }

  /// The locale's decimal-point character. Looked up from `intl`'s locale data rather than
  /// guessed from the language subtag — that would get exceptions like `de_CH` wrong, which
  /// uses a period unlike the rest of German-speaking locales.
  static String _decimalSeparator(String localeTag) =>
      NumberFormat.decimalPattern(localeTag).symbols.DECIMAL_SEP;
}

```

### `lib/core/text/normalizer.dart`

```dart
/// Reduces a display name to a canonical form used only for identity matching (e.g. two
/// Items are the same Item only if their normalized names are identical) — the normalized
/// form is never shown to a user. Deliberately does no stemming or singularisation: "tomato"
/// and "tomatoes" normalize to two different strings, and stay two different Items, because
/// silent fuzzy merging can corrupt data in ways a user can't easily notice or undo.
final class Normalizer {
  /// Creates a normalizer. Stateless — safe to use as a `const` singleton.
  const Normalizer();

  // \p{M} (combining marks) must stay allowed alongside \p{L}\p{N} — Devanagari vowel
  // signs, Arabic tashkeel, and similar combining diacritics are category M, not L, and
  // stripping them as "punctuation" would corrupt those scripts' words, not just declutter
  // them the way it does for Latin punctuation.
  static final RegExp _nonLetterDigitOrMark = RegExp(r'[^\p{L}\p{N}\p{M}\s]', unicode: true);
  static final RegExp _whitespaceRun = RegExp(r'\s+');

  /// Produces the canonical identity form of [input]: case-folded, common precomposed Latin
  /// diacritics stripped to their base letter, all other punctuation removed (any script,
  /// via a Unicode-aware letter/number/mark test — not a hardcoded ASCII punctuation list),
  /// internal whitespace collapsed to single spaces, and the result trimmed. Limitation:
  /// this folds precomposed Latin accents (`'é'` as one code point, how Android text input
  /// normally produces them) but not an `'e'` followed by a separate combining-accent code
  /// point, which is rare in practice and is left attached rather than risking corruption
  /// of combining marks in other scripts.
  String normalize(String input) {
    final caseFolded = input.toLowerCase();
    final withoutDiacritics = _stripDiacritics(caseFolded);
    final withoutPunctuation = withoutDiacritics.replaceAll(_nonLetterDigitOrMark, ' ');
    return withoutPunctuation.replaceAll(_whitespaceRun, ' ').trim();
  }

  String _stripDiacritics(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final replacement = _diacriticMap[rune];
      if (replacement != null) {
        buffer.write(replacement);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// Maps lowercase Latin letters with diacritics/ligatures to their plain base form(s).
  /// Covers Latin-1 Supplement and the common Latin Extended-A range; scripts without this
  /// notion of "diacritics to strip" (Devanagari, Arabic, CJK, ...) pass through unchanged.
  /// Every rune of each key maps to the value, including the plain base letter that leads the
  /// multi-character groups — that self-mapping is a harmless no-op, and iterating all runes
  /// is what makes the single-character ligature entries (`æ`, `œ`, `ß`, `ð`, `þ`) work at all.
  static final Map<int, String> _diacriticMap = {
    for (final entry in const {
      'aàáâãäåāăą': 'a',
      'cçćĉċč': 'c',
      'dđď': 'd',
      'eèéêëēĕėęě': 'e',
      'gĝğġģ': 'g',
      'hĥħ': 'h',
      'iìíîïĩīĭįı': 'i',
      'jĵ': 'j',
      'kķ': 'k',
      'lĺļľł': 'l',
      'nñńņň': 'n',
      'oòóôõöøōŏő': 'o',
      'rŕŗř': 'r',
      'sśŝşš': 's',
      'tţťŧ': 't',
      'uùúûüũūŭůűų': 'u',
      'wŵ': 'w',
      'yýÿŷ': 'y',
      'zźżž': 'z',
      'æ': 'ae',
      'œ': 'oe',
      'ß': 'ss',
      'ð': 'd',
      'þ': 'th',
    }.entries)
      for (final variant in entry.key.runes) variant: entry.value,
  };
}

```

### `lib/core/result/result.dart`

```dart
/// A value that is either a success [T] or a failure [F], forcing callers to handle both
/// paths explicitly instead of relying on a thrown exception for an expected, recoverable
/// outcome (e.g. a malformed amount the user is still typing).
sealed class Result<T, F> {
  const Result();

  /// A successful result wrapping [value].
  const factory Result.ok(T value) = Ok<T, F>;

  /// A failed result wrapping [failure].
  const factory Result.failure(F failure) = Err<T, F>;

  /// True if this is a success.
  bool get isOk => this is Ok<T, F>;

  /// True if this is a failure.
  bool get isFailure => this is Err<T, F>;

  /// The success value, or `null` if this is a failure.
  T? get valueOrNull => switch (this) {
        Ok<T, F>(:final value) => value,
        Err<T, F>() => null,
      };

  /// The failure, or `null` if this is a success.
  F? get failureOrNull => switch (this) {
        Err<T, F>(:final failure) => failure,
        Ok<T, F>() => null,
      };

  /// Transforms a success value with [transform]; a failure passes through unchanged.
  Result<R, F> map<R>(R Function(T value) transform) => switch (this) {
        Ok<T, F>(:final value) => Result.ok(transform(value)),
        Err<T, F>(:final failure) => Result.failure(failure),
      };

  /// Transforms a failure with [transform]; a success passes through unchanged.
  Result<T, R> mapFailure<R>(R Function(F failure) transform) => switch (this) {
        Ok<T, F>(:final value) => Result.ok(value),
        Err<T, F>(:final failure) => Result.failure(transform(failure)),
      };

  /// Reduces both branches to a single value of type [R].
  R fold<R>(R Function(T value) onOk, R Function(F failure) onFailure) => switch (this) {
        Ok<T, F>(:final value) => onOk(value),
        Err<T, F>(:final failure) => onFailure(failure),
      };
}

/// The success branch of a [Result].
final class Ok<T, F> extends Result<T, F> {
  /// Wraps a successful [value].
  const Ok(this.value);

  /// The success payload.
  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T, F> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

/// The failure branch of a [Result].
final class Err<T, F> extends Result<T, F> {
  /// Wraps a [failure].
  const Err(this.failure);

  /// The failure payload.
  final F failure;

  @override
  bool operator ==(Object other) => other is Err<T, F> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err($failure)';
}

```

### `lib/core/result/failure.dart`

```dart
/// A recoverable, expected failure returned by a repository or service instead of a thrown
/// exception, so UI code can pattern-match on the concrete subtype to decide how to respond.
sealed class Failure {
  const Failure(this.message);

  /// A developer-facing description. Never shown to a user verbatim without localisation.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The requested record does not exist, or is soft-deleted and the caller required active.
final class NotFoundFailure extends Failure {
  /// Records that [id] could not be found.
  const NotFoundFailure(super.message, {required this.id});

  /// The identifier that was looked up.
  final String id;
}

/// The operation would violate a uniqueness or identity rule (e.g. a duplicate account name).
final class ConflictFailure extends Failure {
  /// Describes the conflicting rule in [message].
  const ConflictFailure(super.message);
}

/// The change is blocked by a business rule, e.g. deleting an account with live transactions.
final class BusinessRuleFailure extends Failure {
  /// [rule] is a short machine-readable rule id (e.g. `'accountInUse'`) for the UI to switch
  /// on; [message] is the human-readable explanation.
  const BusinessRuleFailure(super.message, {required this.rule});

  /// A short, stable identifier for the violated rule.
  final String rule;
}

/// Input failed validation before it reached storage.
final class ValidationFailure extends Failure {
  /// [field] names the offending input when the failure is field-specific.
  const ValidationFailure(super.message, {this.field});

  /// The offending field name, or `null` if the failure isn't tied to one field.
  final String? field;
}

/// An unexpected, non-recoverable error was caught and wrapped so it can't crash the app.
final class UnexpectedFailure extends Failure {
  /// Wraps the original [cause], if one is available.
  const UnexpectedFailure(super.message, {this.cause});

  /// The underlying exception or error that was caught, if any.
  final Object? cause;
}

/// Why a decimal-text-to-integer parse (an amount or a quantity) did not succeed. Shared by
/// [MoneyParser] and [UnitConverter] since both parse a locale-formatted decimal string into
/// an exact integer and can fail in exactly these ways.
enum ParseFailure {
  /// The input was empty (or became empty after trimming).
  empty,

  /// The input has no digits, or has structural problems a plain digit/separator scan
  /// can't resolve (e.g. two decimal points).
  malformed,

  /// The input contains a character that isn't a digit, sign, or a locale separator.
  invalidCharacter,

  /// The input starts with a minus sign but the caller disallowed negative values.
  negativeNotAllowed,

  /// The input has more fractional digits than the target precision supports (e.g. typing
  /// "100.5" for a currency with 0 decimal digits, or a unit finer than the stored factor
  /// allows) and this parser refuses to silently round away typed precision.
  tooManyDecimalDigits,

  /// The input is implausibly long and was rejected before attempting to parse it, as a
  /// guard against integer overflow on a pathological string.
  tooLarge,
}

```

### `lib/core/enums/money_enums.dart`

```dart
/// How a transaction moves money — which side gains, which side loses. See ARCH_1 §3.1.
/// Stored as `TEXT` via [SafeEnumConverter]; member names are a schema contract (Law L13).
enum TransactionKind {
  /// Money enters an account from outside it (salary, gift, refund, ...).
  deposit,

  /// Money leaves an account to outside it (grocery, bills, ...).
  withdrawal,

  /// Money moves between two of the user's own accounts. Never counted as income or
  /// expense — see `v_account_ledger` in ARCH_2 §12.1.
  transfer,

  /// A manual correction that increases a balance (e.g. reconciling an opening balance).
  adjustmentIncrease,

  /// A manual correction that decreases a balance.
  adjustmentDecrease,
}

/// The structural flow subtype of a transaction: decides which editor form appears and
/// which analytics bucket the transaction lands in. Distinct from a [Tag], which is an
/// open, user-defined label — see ARCH_1 §3.1 for why both exist.
enum TransactionSubtype {
  /// A grocery withdrawal; its lines may fan out into Inventory.
  grocery,

  /// A household-item withdrawal; its lines may fan out into Inventory.
  household,

  /// An electronics withdrawal; its lines may fan out into the Service Manager as an Asset.
  electronics,

  /// A bill payment, optionally linked to a Recurring Template.
  bill,

  /// A transfer to one of the user's own other accounts. Kind is `transfer`.
  transferSelf,

  /// A payment to someone else framed as "transfer" in the UI. Kind is `withdrawal`.
  transferOut,

  /// Recurring income such as salary. Kind is `deposit`.
  salaryIn,

  /// Any other deposit not covered by a more specific subtype.
  otherIn,

  /// Any other withdrawal not covered by a more specific subtype.
  otherOut,
}

/// What a container of money is, for display grouping and iconography.
enum AccountKind {
  /// Physical cash on hand.
  cash,

  /// A bank account.
  bank,

  /// A digital wallet (e.g. Paytm, Google Pay balance).
  wallet,

  /// A credit or debit card treated as its own balance-holding container.
  card,

  /// Anything not covered by the above.
  other,
}

/// The rail money travelled on. Carries no balance of its own — see [AccountKind] for that.
enum PaymentMethodKind {
  /// Physical cash handed over.
  cash,

  /// UPI (or an equivalent real-time payment rail).
  upi,

  /// A bank transfer (NEFT/IMPS/wire/ACH or equivalent).
  bankTransfer,

  /// A credit or debit card swipe/tap.
  card,

  /// A paper cheque.
  cheque,

  /// A digital wallet payment.
  wallet,

  /// Anything not covered by the above; the user's own custom rail.
  other,
}

/// The counterparty on a transaction — used for both `From` (deposits) and `To`
/// (withdrawals).
enum PayeeKind {
  /// An individual (friend, family member, tenant, ...).
  person,

  /// A shop or business.
  merchant,

  /// The user's employer, for salary deposits.
  employer,

  /// A utility or service company (electricity, telecom, ...).
  utility,

  /// Anything not covered by the above.
  other,
}

/// What a [TransactionLine] produced elsewhere in the app, if anything. A line produces at
/// most one artefact, recorded by whichever `created*Id` column matches this value.
enum TransactionLineDestination {
  /// This line created nothing beyond itself.
  none,

  /// This line created (or added a batch to) an Inventory Item.
  inventory,

  /// This line created a Service Manager Asset.
  asset,

  /// This line created a Recurring Template.
  recurring,
}

```

### `lib/core/enums/inventory_enums.dart`

```dart
/// A rough classification of what kind of consumable an Item is, independent of its
/// [UnitCategory]. Drives a few UI defaults (e.g. medicine expiry surfacing on the
/// calendar) — see ARCH_2 §5.1.
enum ItemKind {
  /// No more specific classification applies.
  generic,

  /// Food and groceries.
  food,

  /// Medicines and health-related consumables.
  medicine,

  /// Beauty and personal-care products.
  beauty,

  /// Household and cleaning supplies.
  household,

  /// Anything not covered by the above.
  other,
}

/// Where an Inventory Batch came from.
enum BatchOrigin {
  /// Created by a withdrawal's line item.
  purchase,

  /// Added directly by the user, with no linked transaction.
  manual,

  /// Brought in from an external source (e.g. a data import or migration). Named `imported`
  /// rather than `import` — the latter is a reserved word in Dart and cannot be an enum
  /// member name, so this is a deliberate, one-value deviation from ARCH_2's literal text.
  imported,

  /// Created by a stock-correction/adjustment action.
  adjustment,

  /// Its source transaction was deleted; the batch survives on its own (see ARCH_3 §4.1 —
  /// deleting a receipt must never delete food already eaten).
  detached,
}

/// One kind of event in the append-only `stock_movements` ledger (Law L3/L6 exception: this
/// table has no soft delete — see ARCH_2 §5.3). [quantityMilli] is always positive; this
/// value carries the direction.
enum StockMovementKind {
  /// The opening stock recorded when an Item is first created with existing quantity.
  openingIn,

  /// Stock added by a withdrawal's line item.
  purchaseIn,

  /// Stock added manually by the user.
  manualIn,

  /// Stock used up through normal use.
  consume,

  /// Stock discarded as spoiled/expired before use.
  waste,

  /// Stock that reached its expiry date without being consumed or explicitly wasted.
  expired,

  /// A manual correction that increases the recorded stock.
  adjustIn,

  /// A manual correction that decreases the recorded stock.
  adjustOut,
}

```

### `lib/core/enums/shopping_enums.dart`

```dart
/// How a [ShoppingEntry] came to exist, which decides whether it can be silently
/// regenerated/removed by the low-stock suggestion engine.
enum ShoppingEntryOrigin {
  /// Added directly by the user.
  manual,

  /// Generated automatically because an Item fell below its low-stock threshold. Editing
  /// such an entry promotes it to [manual] so it is never auto-removed afterwards.
  autoLowStock,

  /// Generated from a Recurring Template (e.g. a subscription that needs a physical item).
  fromRecurring,
}

/// The lifecycle state of an auto-generated [ShoppingEntry], letting a user dismiss a
/// suggestion without it reappearing on the very next regeneration.
enum ShoppingEntryAutoState {
  /// Currently shown to the user as a live suggestion.
  active,

  /// Hidden until the stock condition that generated it re-triggers after first clearing.
  snoozed,

  /// Permanently dismissed by the user for this occurrence of the low-stock condition.
  dismissed,
}

```

### `lib/core/enums/recurring_enums.dart`

```dart
/// A rough classification of what a Recurring Template represents, for grouping and
/// iconography.
enum RecurringKind {
  /// A recurring bill (electricity, water, ...).
  bill,

  /// A recurring subscription (streaming, software, ...).
  subscription,

  /// Rent, paid or received.
  rent,

  /// Salary, paid or received.
  salary,

  /// A recurring fee for a service (e.g. a house maid's monthly payment).
  serviceFee,

  /// Anything not covered by the above.
  other,
}

/// Which way money moves when a Recurring Template's occurrence is settled. This is what
/// lets salary live in the same system as bills, rather than needing a second, parallel
/// mechanism (ARCH_1 §3.2).
enum RecurringDirection {
  /// Settling an occurrence creates a withdrawal (a bill, a subscription, ...).
  outflow,

  /// Settling an occurrence creates a deposit (salary, recurring income, ...).
  inflow,
}

/// The unit a Recurring Template's repeat interval is counted in.
enum RecurringIntervalUnit {
  /// Every N days.
  day,

  /// Every N weeks.
  week,

  /// Every N months, anchored to a day-of-month that is clamped (never mutated) at render
  /// time for short months — see ARCH_2 §7.1.
  month,

  /// Every N years.
  year,
}

/// The settlement state of one dated instance of a Recurring Template. `due` past its date
/// renders as overdue — a derived state, never stored separately.
enum RecurringOccurrenceStatus {
  /// Materialised but not yet acted on.
  due,

  /// Settled — money moved and is linked back via `paidTransactionId`.
  paid,

  /// The user explicitly chose not to pay this occurrence.
  skipped,

  /// The user dismissed this occurrence without it ever being due in a meaningful sense
  /// (e.g. a template was paused retroactively).
  dismissed,
}

```

### `lib/core/enums/service_enums.dart`

```dart
/// What kind of durable, serviceable thing (or person) an Asset represents.
enum AssetType {
  /// A home appliance (fridge, washing machine, ...).
  appliance,

  /// A consumer electronics item (TV, laptop, phone, ...).
  electronics,

  /// A car, motorbike, or other vehicle.
  vehicle,

  /// Furniture.
  furniture,

  /// A property (house, flat, land, ...).
  property,

  /// A person providing an ongoing service (e.g. a house maid), tracked the same way as a
  /// physical asset so a single system covers both — see ARCH_2 §8.1.
  serviceProvider,

  /// A non-physical recurring subscription tracked here for its service history rather than
  /// only as a Recurring Template.
  subscription,

  /// Anything not covered by the above.
  other,
}

/// The current lifecycle state of an Asset. There is no "deleted" state — disposal is a
/// status change with a reason, never a delete (ARCH_3 §4.1).
enum AssetStatus {
  /// In normal use.
  active,

  /// Temporarily out of service, e.g. sent for repair.
  underRepair,

  /// No longer owned/in use. See [AssetDisposalReason] for why.
  disposed,
}

/// Why an Asset was disposed. Recorded so its purchase history and cost remain in analytics
/// even after disposal.
enum AssetDisposalReason {
  /// Sold to someone else.
  sold,

  /// Reached the end of its usable/warranty life.
  expired,

  /// Broken beyond economical repair.
  damaged,

  /// Given away.
  gifted,

  /// Lost or stolen.
  lost,

  /// Replaced by a newer Asset.
  replaced,

  /// Anything not covered by the above.
  other,
}

/// What kind of event a [ServiceRecord] represents.
enum ServiceRecordType {
  /// A routine service visit.
  service,

  /// A repair for a specific fault.
  repair,

  /// General maintenance not tied to a specific fault.
  maintenance,

  /// An inspection or checkup with no work performed.
  inspection,

  /// A salary payment to a [AssetType.serviceProvider] asset (e.g. a house maid).
  salaryPaid,

  /// Anything not covered by the above.
  other,
}

```

### `lib/core/enums/ops_enums.dart`

```dart
/// What kind of event a scheduled local notification is for. Paired with a stable Android
/// notification id in `notification_schedule` so it can be cancelled when the underlying
/// record changes (ARCH_3 §7).
enum NotificationKind {
  /// An inventory batch is approaching (or has passed) its expiry date.
  expiry,

  /// An Asset's next service is due.
  serviceDue,

  /// A Recurring Template's occurrence is due.
  recurringDue,

  /// An Item has fallen below its low-stock threshold.
  lowStock,

  /// An Asset's warranty is ending soon.
  warrantyEnd,
}

/// The lifecycle state of one scheduled local notification.
enum NotificationStatus {
  /// Scheduled with the OS but not yet fired.
  scheduled,

  /// Already delivered.
  fired,

  /// Cancelled before firing, e.g. because the underlying record was deleted or resolved.
  cancelled,
}

/// How a backup was produced, recorded in `backup_history` for the user's own reference.
enum BackupKind {
  /// Explicitly triggered by the user.
  manual,

  /// Produced by a scheduled background job.
  auto,
}

```

### `lib/core/enums/safe_enum_converter.dart`

```dart
/// Converts between a Dart enum and its stored `TEXT` representation, mapping any string
/// that doesn't match a current member to a declared [fallback] instead of throwing
/// (Law L13). This is what lets an older build of the app open a database written by a
/// newer one — an unrecognised value degrades to a safe default rather than crashing — and
/// why the stored form is always the enum's own name (`"grocery"`, not `3`): a plain-text
/// backup file stays human-readable, and Law L13 forbids ever renaming an enum value once
/// shipped, since that would silently change what every existing stored row means.
final class SafeEnumConverter<T extends Enum> {
  /// Creates a converter for an enum whose members are [values] (pass `T.values`), falling
  /// back to [fallback] for any unrecognised stored string.
  const SafeEnumConverter(this.values, this.fallback);

  /// All members of the enum, in declaration order.
  final List<T> values;

  /// The member returned when a stored string matches no current member's name.
  final T fallback;

  /// The stored `TEXT` representation of [value] — always its Dart enum name.
  String toSql(T value) => value.name;

  /// The enum member whose name matches [raw], or [fallback] if none does.
  T fromSql(String raw) {
    for (final candidate in values) {
      if (candidate.name == raw) return candidate;
    }
    return fallback;
  }
}

```

### `lib/core/logging/logger.dart`

```dart
import 'dart:developer' as developer;

/// Severity levels for [Logger] output, ordered from least to most severe.
enum LogLevel {
  /// Verbose, developer-only detail.
  debug,

  /// Routine, expected events.
  info,

  /// Something unexpected happened but the app can continue normally.
  warning,

  /// An operation failed and could not recover on its own.
  error,
}

/// A minimal, injectable logging facade so call sites never depend on `dart:developer`
/// directly, and tests can capture or silence output.
abstract interface class Logger {
  /// Records [message] at [level], with an optional [error]/[stackTrace] pair and a [tag]
  /// identifying which subsystem logged it.
  void log(
    String message, {
    LogLevel level = LogLevel.info,
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  });
}

/// The production [Logger]: writes to `dart:developer`'s `log()`, so output is visible in
/// DevTools and `flutter logs` without adding a third-party logging package.
final class DeveloperLogger implements Logger {
  /// Creates a logger that writes via `dart:developer`.
  const DeveloperLogger();

  @override
  void log(
    String message, {
    LogLevel level = LogLevel.info,
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: tag ?? 'alaya',
      level: _severity(level),
      error: error,
      stackTrace: stackTrace,
    );
  }

  static int _severity(LogLevel level) => switch (level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warning => 900,
        LogLevel.error => 1000,
      };
}

/// A [Logger] that discards everything. Useful as a default in tests that don't care about
/// log output but still need to inject something.
final class NoopLogger implements Logger {
  /// Creates a logger that discards everything it's given.
  const NoopLogger();

  @override
  void log(
    String message, {
    LogLevel level = LogLevel.info,
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

```

### `tool/check_layering.dart`

```dart
import 'dart:io';

/// Enforces Law L12: `lib/domain/` may never import Flutter, drift, or `lib/data/`, and
/// `lib/core/` may never import Flutter. Run with `dart run tool/check_layering.dart`; exits
/// with code 1 and a list of violations if the rule is broken, or 0 if the tree is clean.
Future<void> main() async {
  final violations = <String>[
    ..._scan(
      directory: 'lib/domain',
      bannedImportPrefixes: const [
        'package:flutter/',
        'package:drift/',
        'package:alaya/data/',
      ],
      bannedRelativeSegment: '/data/',
    ),
    ..._scan(
      directory: 'lib/core',
      bannedImportPrefixes: const ['package:flutter/'],
      bannedRelativeSegment: null,
    ),
  ];

  if (violations.isEmpty) {
    stdout.writeln('check_layering: OK — no boundary violations found.');
    return;
  }

  stderr.writeln('check_layering: FAILED — ${violations.length} violation(s):');
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  exitCode = 1;
}

/// Scans every `.dart` file under [directory] and returns one description per import
/// statement that starts with a banned prefix or contains [bannedRelativeSegment].
List<String> _scan({
  required String directory,
  required List<String> bannedImportPrefixes,
  required String? bannedRelativeSegment,
}) {
  final root = Directory(directory);
  if (!root.existsSync()) return const [];

  final found = <String>[];
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;

    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('import ') && !line.startsWith('export ')) continue;

      final isBannedPrefix = bannedImportPrefixes.any(
        (prefix) => line.contains("'$prefix") || line.contains('"$prefix'),
      );
      final isBannedRelative = bannedRelativeSegment != null &&
          line.contains(bannedRelativeSegment) &&
          !line.contains('package:');

      if (isBannedPrefix || isBannedRelative) {
        found.add('${entity.path}:${i + 1}: $line');
      }
    }
  }
  return found;
}

```

### `test/core/money_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/rounding.dart';

void main() {
  group('Money construction', () {
    test('stores minor units and currency code as given', () {
      const money = Money(12345, 'INR');
      expect(money.minor, 12345);
      expect(money.currencyCode, 'INR');
    });

    test('Money.zero is zero in the given currency', () {
      const zero = Money.zero('INR');
      expect(zero.minor, 0);
      expect(zero.isZero, isTrue);
      expect(zero.currencyCode, 'INR');
    });
  });

  group('Money arithmetic (same currency)', () {
    test('addition sums minor units', () {
      expect(const Money(100, 'INR') + const Money(50, 'INR'), const Money(150, 'INR'));
    });

    test('subtraction can go negative', () {
      expect(const Money(50, 'INR') - const Money(100, 'INR'), const Money(-50, 'INR'));
    });

    test('multiplication by an int scales minor units', () {
      expect(const Money(100, 'INR') * 3, const Money(300, 'INR'));
    });

    test('unary minus negates minor units, keeping currency', () {
      expect(-const Money(100, 'INR'), const Money(-100, 'INR'));
    });

    test('abs returns a positive amount regardless of sign', () {
      expect(const Money(-100, 'INR').abs(), const Money(100, 'INR'));
      expect(const Money(100, 'INR').abs(), const Money(100, 'INR'));
    });

    test('isNegative, isPositive, isZero classify correctly', () {
      expect(const Money(-1, 'INR').isNegative, isTrue);
      expect(const Money(1, 'INR').isPositive, isTrue);
      expect(const Money(0, 'INR').isZero, isTrue);
    });
  });

  group('Money cross-currency arithmetic throws', () {
    test('addition across currencies throws CurrencyMismatchError', () {
      expect(
        () => const Money(100, 'INR') + const Money(100, 'USD'),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });

    test('subtraction across currencies throws CurrencyMismatchError', () {
      expect(
        () => const Money(100, 'INR') - const Money(100, 'USD'),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });
  });

  group('Money comparisons (same currency)', () {
    test('compareTo orders by minor units', () {
      expect(const Money(100, 'INR').compareTo(const Money(200, 'INR')), lessThan(0));
      expect(const Money(200, 'INR').compareTo(const Money(100, 'INR')), greaterThan(0));
      expect(const Money(100, 'INR').compareTo(const Money(100, 'INR')), 0);
    });

    test('< <= > >= behave as expected', () {
      expect(const Money(100, 'INR') < const Money(200, 'INR'), isTrue);
      expect(const Money(100, 'INR') <= const Money(100, 'INR'), isTrue);
      expect(const Money(200, 'INR') > const Money(100, 'INR'), isTrue);
      expect(const Money(100, 'INR') >= const Money(100, 'INR'), isTrue);
    });
  });

  group('Money cross-currency comparison throws', () {
    test('compareTo across currencies throws CurrencyMismatchError', () {
      expect(
        () => const Money(100, 'INR').compareTo(const Money(100, 'USD')),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });

    test('< across currencies throws CurrencyMismatchError', () {
      expect(
        () => const Money(100, 'INR') < const Money(100, 'USD'),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });
  });

  group('Money equality and hashCode', () {
    test('equal minor units and currency are equal', () {
      expect(const Money(100, 'INR'), const Money(100, 'INR'));
      expect(const Money(100, 'INR').hashCode, const Money(100, 'INR').hashCode);
    });

    test('different currency is never equal even with the same minor units', () {
      expect(const Money(100, 'INR') == const Money(100, 'USD'), isFalse);
    });

    test('different minor units are never equal', () {
      expect(const Money(100, 'INR') == const Money(200, 'INR'), isFalse);
    });
  });

  group('Money.convert', () {
    test('same decimal digits, simple rate', () {
      final converted = const Money(10000, 'INR').convert(
        rate: 0.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 2,
        toDecimalDigits: 2,
      );
      expect(converted, const Money(5000, 'XXX'));
    });

    test('converting to a zero-decimal currency (JPY) scales correctly', () {
      final converted = const Money(10000, 'INR').convert(
        rate: 1.9,
        toCurrencyCode: 'JPY',
        fromDecimalDigits: 2,
        toDecimalDigits: 0,
      );
      expect(converted, const Money(190, 'JPY'));
    });

    test('does not mutate the original amount (Law L9)', () {
      const original = Money(10000, 'INR');
      original.convert(
        rate: 2,
        toCurrencyCode: 'USD',
        fromDecimalDigits: 2,
        toDecimalDigits: 2,
      );
      expect(original.minor, 10000);
      expect(original.currencyCode, 'INR');
    });

    test('halfUp rounds an exact .5 away from zero', () {
      final positive = const Money(1, 'INR').convert(
        rate: 2.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 0,
        toDecimalDigits: 0,
      );
      expect(positive.minor, 3);

      final negative = const Money(-1, 'INR').convert(
        rate: 2.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 0,
        toDecimalDigits: 0,
      );
      expect(negative.minor, -3);
    });

    test('halfEven rounds an exact .5 to the nearest even integer', () {
      final roundsDown = const Money(1, 'INR').convert(
        rate: 2.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 0,
        toDecimalDigits: 0,
        rounding: MoneyRounding.halfEven,
      );
      expect(roundsDown.minor, 2); // 2 is already even

      final roundsUp = const Money(1, 'INR').convert(
        rate: 3.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 0,
        toDecimalDigits: 0,
        rounding: MoneyRounding.halfEven,
      );
      expect(roundsUp.minor, 4); // 3 is odd, rounds up to even 4
    });

    test('halfDown rounds an exact .5 toward zero', () {
      final result = const Money(1, 'INR').convert(
        rate: 2.5,
        toCurrencyCode: 'XXX',
        fromDecimalDigits: 0,
        toDecimalDigits: 0,
        rounding: MoneyRounding.halfDown,
      );
      expect(result.minor, 2);
    });
  });
}

```

### `test/core/qty_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';

void main() {
  group('Qty construction', () {
    test('stores milliBase and category as given', () {
      const qty = Qty(2000000, UnitCategory.weight);
      expect(qty.milliBase, 2000000);
      expect(qty.category, UnitCategory.weight);
    });

    test('Qty.zero is zero in the given category', () {
      const zero = Qty.zero(UnitCategory.weight);
      expect(zero.milliBase, 0);
      expect(zero.isZero, isTrue);
      expect(zero.category, UnitCategory.weight);
    });
  });

  group('Qty arithmetic (same category)', () {
    test('addition sums milliBase', () {
      expect(
        const Qty(1000, UnitCategory.weight) + const Qty(500, UnitCategory.weight),
        const Qty(1500, UnitCategory.weight),
      );
    });

    test('subtraction can go negative', () {
      expect(
        const Qty(500, UnitCategory.weight) - const Qty(1000, UnitCategory.weight),
        const Qty(-500, UnitCategory.weight),
      );
    });

    test('multiplication by an int scales milliBase', () {
      expect(
        const Qty(1000, UnitCategory.weight) * 3,
        const Qty(3000, UnitCategory.weight),
      );
    });

    test('unary minus negates milliBase, keeping category', () {
      expect(-const Qty(1000, UnitCategory.weight), const Qty(-1000, UnitCategory.weight));
    });

    test('isNegative, isPositive, isZero classify correctly', () {
      expect(const Qty(-1, UnitCategory.count).isNegative, isTrue);
      expect(const Qty(1, UnitCategory.count).isPositive, isTrue);
      expect(const Qty(0, UnitCategory.count).isZero, isTrue);
    });
  });

  group('Qty cross-category arithmetic throws', () {
    test('addition across categories throws UnitCategoryMismatchError', () {
      expect(
        () => const Qty(1000, UnitCategory.weight) + const Qty(1000, UnitCategory.volume),
        throwsA(isA<UnitCategoryMismatchError>()),
      );
    });

    test('subtraction across categories throws UnitCategoryMismatchError', () {
      expect(
        () => const Qty(1000, UnitCategory.weight) - const Qty(1000, UnitCategory.count),
        throwsA(isA<UnitCategoryMismatchError>()),
      );
    });
  });

  group('Qty comparisons (same category)', () {
    test('compareTo orders by milliBase', () {
      expect(
        const Qty(100, UnitCategory.weight).compareTo(const Qty(200, UnitCategory.weight)),
        lessThan(0),
      );
    });

    test('< <= > >= behave as expected', () {
      expect(const Qty(100, UnitCategory.weight) < const Qty(200, UnitCategory.weight), isTrue);
      expect(
        const Qty(100, UnitCategory.weight) <= const Qty(100, UnitCategory.weight),
        isTrue,
      );
      expect(
        const Qty(200, UnitCategory.weight) > const Qty(100, UnitCategory.weight),
        isTrue,
      );
      expect(
        const Qty(100, UnitCategory.weight) >= const Qty(100, UnitCategory.weight),
        isTrue,
      );
    });
  });

  group('Qty cross-category comparison throws', () {
    test('compareTo across categories throws UnitCategoryMismatchError', () {
      expect(
        () => const Qty(100, UnitCategory.weight).compareTo(const Qty(100, UnitCategory.volume)),
        throwsA(isA<UnitCategoryMismatchError>()),
      );
    });
  });

  group('Qty equality and hashCode', () {
    test('equal milliBase and category are equal', () {
      expect(const Qty(1000, UnitCategory.weight), const Qty(1000, UnitCategory.weight));
      expect(
        const Qty(1000, UnitCategory.weight).hashCode,
        const Qty(1000, UnitCategory.weight).hashCode,
      );
    });

    test('different category is never equal even with the same milliBase', () {
      expect(const Qty(1000, UnitCategory.weight) == const Qty(1000, UnitCategory.volume), isFalse);
    });

    test('different milliBase is never equal', () {
      expect(const Qty(1000, UnitCategory.weight) == const Qty(2000, UnitCategory.weight), isFalse);
    });
  });

  group('UnitCategory.baseUnitCode', () {
    test('maps each category to its base unit code', () {
      expect(UnitCategory.weight.baseUnitCode, 'g');
      expect(UnitCategory.volume.baseUnitCode, 'ml');
      expect(UnitCategory.count.baseUnitCode, 'pc');
    });
  });
}

```

### `test/core/qty_formatter_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';
import 'package:alaya/core/quantity/unit_category.dart';

void main() {
  const formatter = QtyFormatter();

  group('CRITICAL required test cases (ARCH_1 §5.4, mixed style)', () {
    test('250_000 + 2_000_000 + 1_500_000 + 700_000 weight = 4_450_000 -> "4 kg 450 g"', () {
      // `final`, not `const`: a constant expression may only use the built-in `num`/`String`
      // operators, never a user-defined `operator +` like Qty's.
      final sum = const Qty(250000, UnitCategory.weight) +
          const Qty(2000000, UnitCategory.weight) +
          const Qty(1500000, UnitCategory.weight) +
          const Qty(700000, UnitCategory.weight);
      expect(sum.milliBase, 4450000);
      expect(formatter.format(sum), '4 kg 450 g');
    });

    test('2_000_000 weight -> "2 kg", never "2 kg 0 g"', () {
      const qty = Qty(2000000, UnitCategory.weight);
      expect(formatter.format(qty), '2 kg');
    });

    test('1_200_000 volume -> "1 L 200 ml"', () {
      const qty = Qty(1200000, UnitCategory.volume);
      expect(formatter.format(qty), '1 L 200 ml');
    });

    test('500 count -> "0.5 pc"', () {
      const qty = Qty(500, UnitCategory.count);
      expect(formatter.format(qty), '0.5 pc');
    });

    test('3_000 count -> "3 pc"', () {
      const qty = Qty(3000, UnitCategory.count);
      expect(formatter.format(qty), '3 pc');
    });
  });

  group('mixed style — additional edge cases', () {
    test('zero renders without a big-unit part', () {
      expect(formatter.format(const Qty(0, UnitCategory.weight)), '0 g');
      expect(formatter.format(const Qty(0, UnitCategory.volume)), '0 ml');
      expect(formatter.format(const Qty(0, UnitCategory.count)), '0 pc');
    });

    test('sub-base fractional weight with no whole big unit', () {
      // 250 milliBase = 0.25 g — less than one base unit, no kg part at all.
      expect(formatter.format(const Qty(250, UnitCategory.weight)), '0.25 g');
    });

    test('fractional remainder in the small unit alongside a whole big unit', () {
      // 1_000_250 milliBase weight = 1 kg + 0.25 g.
      expect(formatter.format(const Qty(1000250, UnitCategory.weight)), '1 kg 0.25 g');
    });

    test('a tiny sub-thousandth-of-a-gram amount keeps 3 decimal places', () {
      // 5 milliBase = 0.005 g exactly.
      expect(formatter.format(const Qty(5, UnitCategory.weight)), '0.005 g');
    });

    test('negative quantity is prefixed with a minus sign', () {
      expect(formatter.format(const Qty(-2000000, UnitCategory.weight)), '-2 kg');
    });
  });

  group('compact style', () {
    test('4_450_000 weight -> "4.45 kg"', () {
      const qty = Qty(4450000, UnitCategory.weight);
      expect(formatter.format(qty, style: UnitStyle.compact), '4.45 kg');
    });

    test('a value under 1 big unit still renders in the big unit', () {
      // 450_000 milliBase = 0.45 kg, expressed in kg even though it's under 1.
      const qty = Qty(450000, UnitCategory.weight);
      expect(formatter.format(qty, style: UnitStyle.compact), '0.45 kg');
    });

    test('count is unaffected by compact style', () {
      const qty = Qty(3000, UnitCategory.count);
      expect(formatter.format(qty, style: UnitStyle.compact), '3 pc');
    });

    test('uses the locale decimal separator', () {
      const qty = Qty(4450000, UnitCategory.weight);
      expect(formatter.format(qty, style: UnitStyle.compact, localeTag: 'de_DE'), '4,45 kg');
    });
  });

  group('base style', () {
    test('4_450_000 weight -> "4450 g", no decomposition', () {
      const qty = Qty(4450000, UnitCategory.weight);
      expect(formatter.format(qty, style: UnitStyle.base), '4450 g');
    });

    test('1_200_000 volume -> "1200 ml"', () {
      const qty = Qty(1200000, UnitCategory.volume);
      expect(formatter.format(qty, style: UnitStyle.base), '1200 ml');
    });

    test('count is unaffected by base style', () {
      const qty = Qty(3000, UnitCategory.count);
      expect(formatter.format(qty, style: UnitStyle.base), '3 pc');
    });
  });
}

```

### `test/core/date_key_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/time/date_key.dart';

void main() {
  group('DateKey.fromYmd — valid dates', () {
    test('packs year/month/day into yyyymmdd', () {
      expect(DateKey.fromYmd(2026, 7, 28).value, 20260728);
    });

    test('accepts the last day of a 31-day month', () {
      expect(DateKey.fromYmd(2026, 7, 31).value, 20260731);
    });

    test('accepts 29 February on a leap year', () {
      expect(DateKey.fromYmd(2024, 2, 29).value, 20240229);
    });
  });

  group('DateKey.fromYmd — invalid dates rejected', () {
    test('rejects 30 February', () {
      expect(() => DateKey.fromYmd(2026, 2, 30), throwsArgumentError);
    });

    test('rejects 29 February on a non-leap year', () {
      expect(() => DateKey.fromYmd(2026, 2, 29), throwsArgumentError);
    });

    test('rejects month 0 and month 13', () {
      expect(() => DateKey.fromYmd(2026, 0, 1), throwsArgumentError);
      expect(() => DateKey.fromYmd(2026, 13, 1), throwsArgumentError);
    });

    test('rejects day 0 and day 32', () {
      expect(() => DateKey.fromYmd(2026, 1, 0), throwsArgumentError);
      expect(() => DateKey.fromYmd(2026, 1, 32), throwsArgumentError);
    });

    test('rejects 31 April (a 30-day month)', () {
      expect(() => DateKey.fromYmd(2026, 4, 31), throwsArgumentError);
    });
  });

  group('DateKey component getters', () {
    test('year, month, day, monthKey all read back correctly', () {
      final date = DateKey.fromYmd(2026, 7, 28);
      expect(date.year, 2026);
      expect(date.month, 7);
      expect(date.day, 28);
      expect(date.monthKey, 202607);
    });

    test('weekday matches the known calendar weekday', () {
      // 28 July 2026 is a Tuesday (ISO weekday 2).
      expect(DateKey.fromYmd(2026, 7, 28).weekday, DateTime.tuesday);
    });
  });

  group('DateKey.addDays', () {
    test('stays within a month', () {
      expect(DateKey.fromYmd(2026, 7, 28).addDays(2), DateKey.fromYmd(2026, 7, 30));
    });

    test('crosses a month boundary', () {
      expect(DateKey.fromYmd(2026, 7, 31).addDays(1), DateKey.fromYmd(2026, 8, 1));
    });

    test('crosses a year boundary', () {
      expect(DateKey.fromYmd(2026, 12, 31).addDays(1), DateKey.fromYmd(2027, 1, 1));
    });

    test('crosses a leap-year 29 February correctly', () {
      expect(DateKey.fromYmd(2024, 2, 28).addDays(1), DateKey.fromYmd(2024, 2, 29));
      expect(DateKey.fromYmd(2024, 2, 29).addDays(1), DateKey.fromYmd(2024, 3, 1));
    });

    test('negative days moves backward', () {
      expect(DateKey.fromYmd(2026, 8, 1).addDays(-1), DateKey.fromYmd(2026, 7, 31));
    });
  });

  group('DateKey.diffDays', () {
    test('is positive when this date is later', () {
      final later = DateKey.fromYmd(2026, 8, 1);
      final earlier = DateKey.fromYmd(2026, 7, 28);
      expect(later.diffDays(earlier), 4);
    });

    test('is negative when this date is earlier', () {
      final later = DateKey.fromYmd(2026, 8, 1);
      final earlier = DateKey.fromYmd(2026, 7, 28);
      expect(earlier.diffDays(later), -4);
    });

    test('is zero for the same date', () {
      final date = DateKey.fromYmd(2026, 7, 28);
      expect(date.diffDays(date), 0);
    });
  });

  group('DateKey comparisons', () {
    test('compareTo, isBefore, isAfter, and operators agree', () {
      final earlier = DateKey.fromYmd(2026, 7, 28);
      final later = DateKey.fromYmd(2026, 8, 1);

      expect(earlier.compareTo(later), lessThan(0));
      expect(earlier.isBefore(later), isTrue);
      expect(later.isAfter(earlier), isTrue);
      expect(earlier < later, isTrue);
      expect(later > earlier, isTrue);
      expect(earlier <= earlier, isTrue);
      expect(earlier >= earlier, isTrue);
    });

    test('isWithin is inclusive of both bounds', () {
      final start = DateKey.fromYmd(2026, 7, 1);
      final end = DateKey.fromYmd(2026, 7, 31);
      expect(DateKey.fromYmd(2026, 7, 15).isWithin(start, end), isTrue);
      expect(start.isWithin(start, end), isTrue);
      expect(end.isWithin(start, end), isTrue);
      expect(DateKey.fromYmd(2026, 8, 1).isWithin(start, end), isFalse);
    });
  });

  group('DateKey.fromDateTime', () {
    test('uses the DateTime\'s own year/month/day fields', () {
      final localDateTime = DateTime(2026, 7, 28, 23, 45);
      expect(DateKey.fromDateTime(localDateTime), DateKey.fromYmd(2026, 7, 28));

      final utcDateTime = DateTime.utc(2027, 1, 1, 0, 15);
      expect(DateKey.fromDateTime(utcDateTime), DateKey.fromYmd(2027, 1, 1));
    });

    test('reads the local calendar date, never one shifted through .toUtc()', () {
      // Pick a local time-of-day placed right at whichever edge of the day would cross
      // into an adjacent UTC calendar day for this machine's actual UTC offset, so the
      // test is a real, portable proof rather than one that only works by coincidence.
      final offset = DateTime.now().timeZoneOffset;
      final local = offset.isNegative
          ? DateTime(2026, 7, 28, 23, 59)
          : DateTime(2026, 7, 28, 0, 1);

      expect(DateKey.fromDateTime(local), DateKey.fromYmd(2026, 7, 28));
    });
  });

  group('DateKey.toIso', () {
    test('renders as zero-padded yyyy-mm-dd', () {
      expect(DateKey.fromYmd(2026, 1, 5).toIso(), '2026-01-05');
    });
  });
}

```

### `test/core/normalizer_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/text/normalizer.dart';

void main() {
  const normalizer = Normalizer();

  group('casefolding', () {
    test('uppercase folds to lowercase', () {
      expect(normalizer.normalize('POTATO'), 'potato');
    });

    test('mixed case folds to lowercase', () {
      expect(normalizer.normalize('PoTaTo'), 'potato');
    });
  });

  group('diacritic stripping', () {
    test('strips a single acute accent', () {
      expect(normalizer.normalize('café'), 'cafe');
    });

    test('strips a tilde', () {
      expect(normalizer.normalize('jalapeño'), 'jalapeno');
    });

    test('strips diacritics on uppercase letters too, after casefolding', () {
      expect(normalizer.normalize('MÜNCHEN'), 'munchen');
    });

    test('folds ligatures to their letter pairs', () {
      expect(normalizer.normalize('œuf'), 'oeuf');
    });

    test('folds eszett to ss', () {
      expect(normalizer.normalize('straße'), 'strasse');
    });
  });

  group('punctuation stripping', () {
    test('a comma becomes whitespace and is collapsed', () {
      expect(normalizer.normalize('Rice, White'), 'rice white');
    });

    test('an apostrophe becomes whitespace, consistent with all other punctuation', () {
      expect(normalizer.normalize("Tomato's"), 'tomato s');
    });

    test('digits are preserved, only punctuation is stripped', () {
      expect(normalizer.normalize('Vitamin B-12!'), 'vitamin b 12');
    });
  });

  group('whitespace collapse and trim', () {
    test('multiple internal spaces collapse to one', () {
      expect(normalizer.normalize('Rice    Flour'), 'rice flour');
    });

    test('leading and trailing whitespace is trimmed', () {
      expect(normalizer.normalize('   Rice Flour   '), 'rice flour');
    });

    test('tabs and newlines count as whitespace', () {
      expect(normalizer.normalize('Rice\tFlour\n'), 'rice flour');
    });
  });

  group('combined pipeline', () {
    test('casefold, diacritics, punctuation, and whitespace all apply together', () {
      expect(normalizer.normalize('  CAFÉ-Au-Lait!!  '), 'cafe au lait');
    });
  });

  group('exact-match-only (no stemming, no singularisation) — A07', () {
    test('a plural and its singular remain two different normalized strings', () {
      expect(normalizer.normalize('tomato'), isNot(normalizer.normalize('tomatoes')));
      expect(normalizer.normalize('tomatoes'), 'tomatoes');
    });

    test('near-identical words are not silently merged', () {
      expect(normalizer.normalize('onion'), isNot(normalizer.normalize('onions')));
    });
  });

  group('non-Latin scripts pass through unchanged (beyond casefold/whitespace)', () {
    test('Devanagari text is preserved, not stripped as punctuation', () {
      expect(normalizer.normalize('टमाटर'), 'टमाटर');
    });

    test('Devanagari text still has its surrounding whitespace trimmed', () {
      expect(normalizer.normalize('  टमाटर  '), 'टमाटर');
    });
  });

  group('empty and whitespace-only input', () {
    test('an empty string normalizes to an empty string', () {
      expect(normalizer.normalize(''), '');
    });

    test('a whitespace-only string normalizes to an empty string', () {
      expect(normalizer.normalize('   '), '');
    });
  });
}

```
