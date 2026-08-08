# Phase 4A — Unit Engine, Balance Service & the Currency Subsystem

**7 new files · 2 test files · 664 lines of tests · 2 duplications removed · 4 unused imports found.**

## Fix in this revision

`RateTable._byQuote` is initialized at its declaration (`final Map<...> _byQuote = {};`) **and**
again in `RateTable.empty()`'s initializer list. Dart forbids initializing a final field twice, and
the primary constructor was already correct — it relies on the declaration initializer and populates
the map in its body, so only the `empty()` variant was wrong.

Fixed by dropping the redundant assignment: `RateTable.empty() : _decimalDigits = const {};`.

I then checked it as a *class* of error rather than an instance, with a scanner for any final field
initialized both at declaration and in an initializer list, plus the related `this.x` parameter
variant. **This was the only occurrence** across all 142 files.

Because `RateTable.empty()` is used by five call sites in the two test files, I also traced each one
against what its test asserts — an empty map from the declaration must behave identically to the old
explicit `{}`. It does: `legFor('USD')` still returns rate 1 exact (the pivot needs no cached row),
`INR→USD` still yields `unconverted`, `INR→INR` still short-circuits before any lookup, and the
single-currency-user-with-empty-cache case still totals correctly with `unconvertedCount == 0` —
which is the assertion that would have been most annoying to break silently.

## Add dependencies

```bash
flutter pub add dio
```

`dio` is listed against phase **4A** in ARCH_1 §7's tech-stack table, so this is the phase it
belongs in. It is imported by exactly one file, `data/remote/currency_api_client.dart` — verified:
`dio` appears nowhere under `lib/domain/`, which Law L12 requires.

## Two duplications removed rather than created

Phase 3B implemented the USD-pivot cross-rating inside `CurrencyRepositoryImpl.convert()`, because
`convert` sits on the 3A contract and no service existed yet. Writing this phase's
`currency_rate_service.dart` would have made that **two implementations of ARCH_3 §1.2 and §1.3** —
the exact shape of drift this project has been bitten by before (the stock cache versus
`v_batch_stock_check`'s formula).

So the algorithm now lives in one place, and `CurrencyRepositoryImpl.convert()` delegates to it. The
hand-rolled `_lookupUsdLeg` and its `_UsdLeg` typedef are gone; verified zero occurrences remain.
Supporting that needed one new DAO method, `CurrencyDao.allRates()`, which loads the whole cache in
a single query.

That single query is the second, better reason for the change. **ARCH_3 §1.5 specifies `toHome` as
synchronous** — which is only possible if the rates are already in hand. Converting a month of
transactions through the old per-amount path meant two asynchronous cache round trips per amount;
`RateTable` loads once and converts in memory. The contract was describing a design, not just an
API shape.

The second duplication is `AccountRepository.watchTotalInHomeCurrency` versus this phase's
`BalanceService`. I left the repository method in place — it is correct, and rewiring it would have
meant either a 3A contract change or an object cycle — but **`BalanceService` is now the canonical
definition of the net-worth rule**, and the repository method should be dropped from the contract
when a later phase touches it. Flagging rather than quietly leaving two definitions.

## The design that makes the hard parts testable

`RateTable` is **pure**: an immutable index of cached rates with no I/O. That is why the weekend-gap
test, the cross-rate test and the unconverted test all build a table from literals with no database,
no mocks and no fakes. `BalanceService.totalFrom` is pure for the same reason. The services that
*do* need I/O take function typedefs — `RateTableLoader`, `RateSnapshotSaver`, `RateSnapshotFetcher`
— rather than interfaces, so `domain/` never names a `data/` type while staying trivially fakeable.

## Verified behaviourally, not just structurally

**The weekend gap — the case the lookup rule exists for.** With Friday the 24th and Monday the 27th
cached and the weekend genuinely absent, a Saturday transaction resolves to **Friday's rate**, and
that resolution is `RateQuality.exact` — not approximate. Marking it approximate would flag every
Saturday transaction in the app as unreliable. Sunday resolves to Friday too, never forward to a
rate not yet quoted. A row months stale is still exact, because the rule is "greatest `<= D`" and it
never expires a row or extrapolates.

**The USD pivot.** `INR→JPY = (USD→JPY) / (USD→INR)`, asserted against the arithmetic to 1e-12.
1000 INR → about 1904 JPY. The reverse rate is the reciprocal to 1e-12, so a round trip returns the
original to 1e-9. USD itself needs no cached row.

**Unconverted is excluded, never zeroed.** One test asserts the two situations produce the *same*
total — an unconvertible ₹7,000 balance and an empty one — which is precisely why
`unconvertedCount` has to exist: without it those two very different states look identical.

**`syncDailyRates` never throws.** Eight tests: a client that throws, one returning null, an empty
snapshot, a save that throws, a *reader* that throws before the network is even reached, and the
happy path. Plus the one-request-per-day skip when today is already cached, which is what makes
ARCH_3 §1.2's "one request per day, forever" true rather than aspirational.

**Interval and boundary arithmetic.** `last7Days` spans exactly 7 dates, not 8 — today plus six
earlier days. `lastMonth` from January rolls back to the previous December. February resolves to 29
in a leap year and 28 otherwise. `precedingWindowOf` returns a window of the same length ending the
day before the current one starts, so a rolling comparison is like-for-like.

**Unit engine arithmetic.** 1.5 kg expressed in mg, g and kg is exact in all three. 2 dozen is
exactly 24 pc. A cross-category request is refused rather than approximated (Law L8). 1 milli-gram
cannot be expressed exactly in thousandths of a kg, and that is **surfaced as a failure rather than
truncated** — an inexact answer is a real answer worth showing.

## Verification performed

| Check | Result |
|---|---|
| **L12** — `domain/` importing flutter, drift or `data/` | **0** |
| `dio` reachable from `domain/` | **0** — one file only, under `data/remote/` |
| Missing imports — exhaustive, 142 files vs 224 types | 0 |
| **Unused imports** | 0 (4 found and removed — below) |
| Brace balance, 11 changed files | 0 |
| `const` with runtime interpolation | 0 |
| `DateTime.now()` in a service | 0 |
| `Qty` debug `toString` in user-facing text | 0 |
| Impl-to-impl imports | 0 |
| Duplicate cross-rate implementations | 0 (was about to be 2) |

**Four genuinely unused imports found and removed**, three of them pre-existing:
`date_key_filters.dart` in `item_dao.dart` and `shopping_entry_dao.dart` (neither does any date
filtering), `unit_category.dart` in `meta_tables.dart` (it names `UnitCategoryConverter`, which lives
in `enum_converters.dart`), and one I had just introduced in `unit_engine.dart`.

The scanner also flagged ten imports in `alaya_database.dart` — those are **false positives it cannot
see past**: a generated `part` file cannot declare its own imports, so everything the generated code
names must be imported by its host, exactly as Phase 1B documented. Excluded from the scan with that
reason recorded rather than silently skipped.

## Findings

**`NetworkPolicy` gates URLs this class builds itself.** `CurrencyApiClient._attempt` calls
`ensureAllowed` on every request including its own hardcoded ladder entries — an allowlist whose
author is exempt from it is worth nothing. It also requires HTTPS and rejects a URL carrying
credentials, since a keyless rate endpoint needs neither. A disallowed host **throws** rather than
returning a failure, because it is a programming mistake and should surface in development instead
of degrading into a silent no-op.

**`rateRaw` is the parsed double's shortest round-trip string, and that satisfies §1.3.7.** The
requirement is that a figure a user questions can be reproduced; Dart's `toString()` on a double
round-trips exactly. What it does not preserve is wire formatting — a body carrying `83.20` yields
`83.2` — which carries no numeric meaning. Preserving the literal token would mean scanning raw JSON
text for a difference that cannot change a figure, so the trade is stated in the code rather than
hidden.

**Frankfurter's `amount` field is divided out, not assumed to be 1.** If it ever returns something
else, every rate in that response is scaled, and treating it as 1 would silently misstate all of
them.

**A known rate with unknown precision yields `unconverted`, not a guess.** Converting into JPY needs
to know it has no minor unit; assuming 2 would misstate every yen figure by a factor of 100. There
is a test for this specifically.

**`DateRangeService` takes `today` as a parameter and holds no `Clock`.** Same rule the views
follow (ARCH_2 §12.2): a range that reads the time itself cannot be asserted against a `FixedClock`,
and every analytics figure downstream would inherit that non-determinism. `DateRangePreset.custom`
returns **null** rather than a guessed window, so a UI that forgets to handle it shows nothing
instead of the wrong month.

**`BalanceService` does not exclude archived accounts, and the task's phrasing needed resolving
against the spec.** ARCH_3 §4's table is explicit — `isArchived` is *"counted in totals? yes"*, and
only `deletedAt` removes money, because a closed bank account holding a balance is retired rather
than gone. So the only filter is `includeInNetWorth`. A test asserts an archived account still
counts, citing that table.

**`DateRangePreset` is new, in `core/enums/`.** It did not exist; `domain/` (this service,
analytics) and `features/` (the picker) both name it, and Law L12 forbids `domain/` importing from
above. Same placement reasoning as `TagScope`. It is never stored — only the resolved `DateKey` pair
reaches the database — so Law L13's enum-rename rule does not apply.

**`UnitEngine` exists because a `Qty` has no unit to convert.** A `Qty` holds milli-base-units plus a
category, so `2 kg` and `2000 g` are the *same stored value*. Units matter only at parse and format,
both already built. What is genuinely left is the arithmetic question — *how many of unit X is
this?* — plus refusing cross-category conversion and validating user-defined factors. Returning
thousandths of the target unit keeps every step integer, so no quantity can pick up the drift that
made minor-unit money necessary in the first place.



---

### `lib/core/enums/date_range_preset.dart`

```dart
/// A named reporting window the user can pick, resolved to concrete dates by `DateRangeService`.
///
/// Lives in `core/` rather than beside the service because both `domain/` (the service, analytics)
/// and `features/` (the picker widget) name it, and Law L12 forbids `domain/` importing from
/// anywhere above it. Same reasoning as `TagScope`.
///
/// **Not stored anywhere.** Law L13's "renaming an enum value is a breaking migration" does not
/// apply — the resolved `DateKey` pair is what reaches the database, never the preset itself. The
/// selected preset is persisted only as an `app_settings` string, which the repository maps by
/// name and falls back to [thisMonth] on an unknown value.
enum DateRangePreset {
  /// Today only, from midnight to midnight.
  today,

  /// The seven days ending today, today included.
  last7Days,

  /// The thirty days ending today, today included.
  last30Days,

  /// The first of this month through today.
  thisMonth,

  /// The whole of the previous calendar month.
  lastMonth,

  /// The first of this calendar year through today.
  thisYear,

  /// Every date the user could have recorded anything on.
  allTime,

  /// A window the user picked by hand; `DateRangeService` cannot resolve this one alone.
  custom,
}

```

### `lib/data/remote/network_policy.dart`

```dart
/// The complete list of hosts this app may contact, and the single gate every HTTP call passes
/// through (ARCH_3 §1.4).
///
/// Three purposes, and nothing else: currency rates, rewarded ads, and the tip purchase. No crash
/// reporter, no analytics SDK, no font CDN, no image loader. The value of an allowlist is that it
/// is checked in code rather than asserted in a document — a package that quietly wants a fourth
/// host fails [ensureAllowed] instead of shipping.
///
/// Ads and billing are Phase 8B and route through Google's own SDKs rather than this client, so
/// their hosts are recorded here for completeness but are not yet reachable through [isAllowed].
final class NetworkPolicy {
  /// Creates the policy.
  const NetworkPolicy();

  /// Hosts serving currency rates — the only hosts this app's own HTTP client may reach.
  ///
  /// `latest.currency-api.pages.dev` and `{date}.currency-api.pages.dev` are both real: the
  /// fawazahmed0 mirror puts the date in the subdomain for historical lookups, which is why
  /// [isAllowed] matches that host by suffix rather than exactly.
  static const Set<String> currencyHosts = {
    'cdn.jsdelivr.net',
    'api.frankfurter.dev',
  };

  /// The suffix that admits any `*.currency-api.pages.dev` subdomain.
  static const String currencyHostSuffix = '.currency-api.pages.dev';

  /// Hosts reached by Google's ad SDK, not by this app's HTTP client (Phase 8B).
  static const Set<String> adHosts = {'googleads.g.doubleclick.net'};

  /// Hosts reached by Google Play Billing, not by this app's HTTP client (Phase 8B).
  static const Set<String> billingHosts = {'play.google.com'};

  /// True when [url] may be requested by this app's own HTTP client.
  ///
  /// Requires HTTPS and rejects a URL carrying credentials — a rate endpoint never needs either,
  /// so anything presenting them is not the endpoint it claims to be.
  bool isAllowed(Uri url) {
    if (url.scheme != 'https') return false;
    if (url.userInfo.isNotEmpty) return false;
    final host = url.host.toLowerCase();
    return currencyHosts.contains(host) || host.endsWith(currencyHostSuffix);
  }

  /// Throws [DisallowedHostError] unless [url] passes [isAllowed].
  ///
  /// Throws rather than returning a failure deliberately: a disallowed host is a programming
  /// mistake, not a runtime condition a user can act on, and it should surface in development
  /// rather than degrade into a silent no-op.
  void ensureAllowed(Uri url) {
    if (!isAllowed(url)) throw DisallowedHostError(url);
  }
}

/// Thrown when code attempts an HTTP request to a host outside [NetworkPolicy]'s allowlist.
final class DisallowedHostError extends Error {
  /// Creates the error for [url].
  DisallowedHostError(this.url);

  /// The rejected URL.
  final Uri url;

  @override
  String toString() =>
      'DisallowedHostError: $url is not on the network allowlist (ARCH_3 §1.4). '
      'If a package needs this host, it does not go in the app.';
}

```

### `lib/data/remote/currency_api_client.dart`

```dart
import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/remote/network_policy.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// Fetches USD-pivoted rates, walking ARCH_3 §1.1's three-entry ladder and normalising two
/// incompatible response shapes into one [RateSnapshot].
///
/// The ladder exists because the endpoint most tutorials still show is dead: the fawazahmed0
/// project moved from `currency-api@1` to `@fawazahmed0/currency-api` on npm. Entry 2 is that
/// project's own mirror; entry 3 is Frankfurter, which is ECB-backed and self-hostable rather than
/// another community CDN — which is why it is the fallback.
///
/// **Never throws.** Every method returns null on failure, because ARCH_3 §1.3.2 makes a failed
/// fetch a no-op and Law L11 forbids a rate lookup from blocking a write.
final class CurrencyApiClient {
  /// Creates the client over [dio], gated by [policy].
  CurrencyApiClient({
    required Dio dio,
    NetworkPolicy policy = const NetworkPolicy(),
    Logger? logger,
  })  : _dio = dio,
        _policy = policy,
        _logger = logger;

  final Dio _dio;
  final NetworkPolicy _policy;
  final Logger? _logger;

  static const String _logTag = 'currency';

  /// The quote currencies requested from Frankfurter.
  ///
  /// Only entry 3 needs this list: the fawazahmed0 endpoints return *every* quote for a base in one
  /// file, which is exactly what makes one daily request enough (ARCH_3 §1.2).
  static const List<String> frankfurterQuotes = ['INR', 'EUR', 'JPY', 'CNY'];

  /// Fetches the latest rates, trying each ladder entry until one succeeds.
  ///
  /// Returns null only when all three failed.
  Future<RateSnapshot?> fetchLatest() async {
    for (final attempt in _latestLadder()) {
      final snapshot = await _attempt(attempt);
      if (snapshot != null && !snapshot.isEmpty) return snapshot;
    }
    _logger?.log(
      'Every currency ladder entry failed; leaving the rate cache untouched.',
      level: LogLevel.warning,
      tag: _logTag,
    );
    return null;
  }

  /// Fetches the rates quoted for [on], for backfilling a historical conversion.
  Future<RateSnapshot?> fetchOn(DateKey on) async {
    for (final attempt in _historicalLadder(on)) {
      final snapshot = await _attempt(attempt);
      if (snapshot != null && !snapshot.isEmpty) return snapshot;
    }
    return null;
  }

  List<_LadderEntry> _latestLadder() => [
        _LadderEntry(
          Uri.parse(
            'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest'
            '/v1/currencies/usd.min.json',
          ),
          'jsdelivr',
          _parseFawazahmed0,
        ),
        _LadderEntry(
          Uri.parse('https://latest.currency-api.pages.dev/v1/currencies/usd.min.json'),
          'currency-api.pages.dev',
          _parseFawazahmed0,
        ),
        _LadderEntry(
          Uri.parse(
            'https://api.frankfurter.dev/v2/rates'
            '?base=USD&quotes=${frankfurterQuotes.join(",")}',
          ),
          'frankfurter',
          _parseFrankfurter,
        ),
      ];

  List<_LadderEntry> _historicalLadder(DateKey on) {
    final iso = on.toIso();
    return [
      _LadderEntry(
        Uri.parse(
          'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@$iso'
          '/v1/currencies/usd.min.json',
        ),
        'jsdelivr@$iso',
        _parseFawazahmed0,
      ),
      _LadderEntry(
        Uri.parse('https://$iso.currency-api.pages.dev/v1/currencies/usd.min.json'),
        'currency-api.pages.dev@$iso',
        _parseFawazahmed0,
      ),
      _LadderEntry(
        Uri.parse(
          'https://api.frankfurter.dev/v2/rates'
          '?base=USD&quotes=${frankfurterQuotes.join(",")}&date=$iso',
        ),
        'frankfurter@$iso',
        _parseFrankfurter,
      ),
    ];
  }

  Future<RateSnapshot?> _attempt(_LadderEntry entry) async {
    try {
      // Every request passes the allowlist, including ones this class built itself — the gate is
      // worth nothing if the code that constructs URLs is exempt from it (ARCH_3 §1.4).
      _policy.ensureAllowed(entry.url);

      final response = await _dio.getUri<String>(
        entry.url,
        // Plain text, not Dio's automatic JSON decode, so the body can be decoded here and the raw
        // numeric text is available for `rateRaw`.
        options: Options(responseType: ResponseType.plain),
      );
      final body = response.data;
      if (body == null || body.isEmpty) return null;

      return entry.parse(body, entry.source);
    } on DisallowedHostError {
      // A programming error, not a network condition — rethrown so it surfaces in development
      // rather than being mistaken for an offline device.
      rethrow;
    } catch (error) {
      _logger?.log(
        'Currency ladder entry ${entry.source} failed.',
        level: LogLevel.debug,
        tag: _logTag,
        error: error,
      );
      return null;
    }
  }

  /// Parses the fawazahmed0 shape: `{"date":"2026-07-28","usd":{"inr":83.2,"eur":0.92,...}}`.
  ///
  /// Keys are lowercase and the rate map is nested under the base currency's own name.
  RateSnapshot? _parseFawazahmed0(String body, String source) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;

    final date = _parseIsoDate(decoded['date']);
    if (date == null) return null;

    final quotes = decoded['usd'];
    if (quotes is! Map<String, dynamic>) return null;

    return RateSnapshot(on: date, rates: _toRates(quotes, date), source: source);
  }

  /// Parses the Frankfurter shape:
  /// `{"amount":1.0,"base":"USD","date":"2026-07-28","rates":{"INR":83.2,...}}`.
  ///
  /// Keys are uppercase, the rate map is under a fixed `rates` key, and an `amount` other than 1
  /// would scale every rate — so it is divided out rather than assumed.
  RateSnapshot? _parseFrankfurter(String body, String source) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;

    final date = _parseIsoDate(decoded['date']);
    if (date == null) return null;

    final quotes = decoded['rates'];
    if (quotes is! Map<String, dynamic>) return null;

    final amount = _toDouble(decoded['amount']) ?? 1.0;
    if (amount <= 0) return null;

    return RateSnapshot(
      on: date,
      rates: _toRates(quotes, date, divisor: amount),
      source: source,
    );
  }

  /// Normalises a quote map into [UsdRate]s, upper-casing codes so both shapes index alike.
  List<UsdRate> _toRates(
    Map<String, dynamic> quotes,
    DateKey on, {
    double divisor = 1.0,
  }) {
    final rates = <UsdRate>[];
    for (final entry in quotes.entries) {
      final value = _toDouble(entry.value);
      if (value == null || value <= 0) continue;
      final rate = divisor == 1.0 ? value : value / divisor;
      rates.add(
        UsdRate(
          quoteCode: entry.key.toUpperCase(),
          on: on,
          rate: rate,
          // Dart's `toString()` on a double is its shortest round-trip form, so this reproduces the
          // exact value ARCH_3 §1.3.7 asks to be able to reproduce. What it does not preserve is
          // wire formatting — a body carrying `83.20` yields `83.2` — which carries no numeric
          // meaning. Preserving the literal token would mean scanning raw JSON text, which is
          // fragile for a difference that cannot change a figure.
          rateRaw: rate.toString(),
        ),
      );
    }
    return rates;
  }

  DateKey? _parseIsoDate(Object? raw) {
    if (raw is! String) return null;
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2].length > 2 ? parts[2].substring(0, 2) : parts[2]);
    if (year == null || month == null || day == null) return null;
    try {
      return DateKey.fromYmd(year, month, day);
    } on ArgumentError {
      return null;
    }
  }

  double? _toDouble(Object? raw) => switch (raw) {
        final num value => value.toDouble(),
        final String value => double.tryParse(value),
        _ => null,
      };
}

class _LadderEntry {
  const _LadderEntry(this.url, this.source, this.parse);

  final Uri url;
  final String source;
  final RateSnapshot? Function(String body, String source) parse;
}

```

### `lib/domain/services/unit_engine.dart`

```dart
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Converts quantities between units of the same category, and validates user-defined units.
///
/// **There is no unit conversion of a stored quantity, and that is the point.** A `Qty` holds
/// milli-base-units plus a category (Law L2), so `2 kg` and `2000 g` are the *same* stored value —
/// only their display differs. Units matter at two boundaries: parsing text into base units
/// (`UnitConverter`) and formatting base units back out (`QtyFormatter`). What is left for this
/// engine is the genuinely arithmetic question — *how many of unit X is this quantity?* — plus
/// refusing the two conversions that must never happen.
///
/// Every operation is integer-only. No step touches a `double`, so no quantity can accumulate the
/// drift that made `0.1 + 0.2 != 0.3` a reason to store money in minor units in the first place.
final class UnitEngine {
  /// Creates the engine.
  const UnitEngine();

  /// Milli-base-units per one base unit — the scale every `factorToBaseMilli` is expressed in.
  static const int milliPerBaseUnit = 1000;

  /// The largest factor a user-defined unit may declare.
  ///
  /// One million milli-base-units is one thousand base units — a `tonne` against `g`, or a
  /// `kilolitre` against `ml`. Beyond that, `amountInUnitMilli`'s intermediate
  /// `milliBase * 1000` starts approaching the 64-bit ceiling for large quantities, and no
  /// household inventory needs it.
  static const int maxFactorToBaseMilli = 1000000000;

  /// How much of [unit] the quantity [quantity] represents, in **thousandths of [unit]**.
  ///
  /// Returns thousandths rather than whole units because the answer is frequently fractional and
  /// this engine will not return a `double`: `1.5 kg` is `1500` thousandths of a kilogram, exactly.
  /// Divide by [milliPerBaseUnit] at the display boundary, where `QtyFormatter` already does.
  ///
  /// Fails with a [BusinessRuleFailure] when [unit] measures a different category (Law L8) — a
  /// weight cannot be asked to express itself in millilitres — and with a [ValidationFailure] when
  /// the conversion would not be exact, rather than silently truncating. An inexact result means
  /// the user is asking for a unit the quantity cannot be cleanly expressed in, which is a real
  /// answer worth surfacing rather than rounding away.
  Result<int, Failure> amountInUnitMilli({
    required Qty quantity,
    required Unit unit,
  }) {
    if (unit.category != quantity.category) {
      return Result.failure(
        BusinessRuleFailure(
          'A ${quantity.category.name} quantity cannot be expressed in ${unit.code}, which '
          'measures ${unit.category.name}. There is no conversion between categories.',
          rule: 'crossCategoryConversion',
        ),
      );
    }
    if (unit.factorToBaseMilli <= 0) {
      return Result.failure(
        ValidationFailure(
          'Unit ${unit.code} has a non-positive factor and cannot be converted to.',
          field: 'factorToBaseMilli',
        ),
      );
    }

    final scaled = quantity.milliBase * milliPerBaseUnit;
    if (scaled % unit.factorToBaseMilli != 0) {
      return Result.failure(
        ValidationFailure(
          'This quantity cannot be expressed exactly in ${unit.code}.',
          field: 'unit',
        ),
      );
    }
    return Result.ok(scaled ~/ unit.factorToBaseMilli);
  }

  /// The same question as [amountInUnitMilli], but truncating toward zero instead of failing.
  ///
  /// For display and estimates only. Returns null on a category mismatch, because that is not a
  /// rounding problem — it is a question with no answer.
  int? amountInUnitMilliTruncating({
    required Qty quantity,
    required Unit unit,
  }) {
    if (unit.category != quantity.category) return null;
    if (unit.factorToBaseMilli <= 0) return null;
    return (quantity.milliBase * milliPerBaseUnit) ~/ unit.factorToBaseMilli;
  }

  /// Builds a `Qty` from [amountMilli] thousandths of [unit].
  ///
  /// The inverse of [amountInUnitMilli], and always exact: multiplying into base units cannot lose
  /// precision the way dividing out of them can. `1500` thousandths of `kg` becomes `1500000`
  /// milli-grams.
  Result<Qty, Failure> quantityFromUnit({
    required int amountMilli,
    required Unit unit,
  }) {
    if (unit.factorToBaseMilli <= 0) {
      return Result.failure(
        ValidationFailure(
          'Unit ${unit.code} has a non-positive factor.',
          field: 'factorToBaseMilli',
        ),
      );
    }
    final milliBase = amountMilli * unit.factorToBaseMilli ~/ milliPerBaseUnit;
    return Result.ok(Qty(milliBase, unit.category));
  }

  /// Converts a quantity expressed in [from] into thousandths of [to].
  ///
  /// A convenience over [quantityFromUnit] + [amountInUnitMilli] for the direct question "2 dozen
  /// is how many pieces?" — `2000` thousandths of `dozen` becomes `24000` thousandths of `pc`.
  Result<int, Failure> convert({
    required int amountMilli,
    required Unit from,
    required Unit to,
  }) {
    if (from.category != to.category) {
      return Result.failure(
        BusinessRuleFailure(
          'There is no conversion between ${from.category.name} and ${to.category.name}.',
          rule: 'crossCategoryConversion',
        ),
      );
    }
    final quantity = quantityFromUnit(amountMilli: amountMilli, unit: from);
    if (quantity.isFailure) return Result.failure(quantity.failureOrNull!);
    return amountInUnitMilli(quantity: quantity.valueOrNull!, unit: to);
  }

  /// Validates a unit the user defined themselves.
  ///
  /// ARCH_1 §5.3 is explicit that a unit needs a factor the user can *state exactly*. If they
  /// cannot — "one packet of noodles" — the correct action is a new Item, not a unit with an
  /// invented factor, because every quantity recorded against a wrong factor is silently wrong and
  /// no migration can recover the intent.
  ///
  /// Rejects a non-positive factor, one above [maxFactorToBaseMilli], an empty or overlong code,
  /// and a code that collides with a seeded system unit under case folding — `KG` and `kg` would
  /// be two rows the user cannot tell apart.
  Result<void, Failure> validateUserUnit({
    required Unit unit,
    required Iterable<Unit> existingUnits,
  }) {
    final code = unit.code.trim();
    if (code.isEmpty) {
      return const Result.failure(ValidationFailure('A unit needs a code.', field: 'code'));
    }
    if (code.length > 12) {
      return const Result.failure(
        ValidationFailure('A unit code must be 12 characters or fewer.', field: 'code'),
      );
    }
    if (unit.displayName.trim().isEmpty) {
      return const Result.failure(
        ValidationFailure('A unit needs a display name.', field: 'displayName'),
      );
    }
    if (unit.factorToBaseMilli <= 0) {
      return const Result.failure(
        ValidationFailure(
          'A unit needs a positive factor to its category\'s base unit. If you cannot state one '
          'exactly, create a separate Item instead.',
          field: 'factorToBaseMilli',
        ),
      );
    }
    if (unit.factorToBaseMilli > maxFactorToBaseMilli) {
      return const Result.failure(
        ValidationFailure(
          'That factor is too large to convert safely.',
          field: 'factorToBaseMilli',
        ),
      );
    }

    final folded = code.toLowerCase();
    for (final existing in existingUnits) {
      if (existing.code == unit.code) continue;
      if (existing.code.toLowerCase() == folded) {
        return Result.failure(
          ConflictFailure('A unit with the code "${existing.code}" already exists.'),
        );
      }
    }
    return const Result.ok(null);
  }
}

```

### `lib/domain/services/date_range_service.dart`

```dart
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/time/date_key.dart';

/// An inclusive civil-date window: every `DateKey` from [from] to [to], both ends counted.
typedef DateRange = ({DateKey from, DateKey to});

/// Resolves a [DateRangePreset] into concrete dates.
///
/// Takes `today` as a parameter on every call rather than holding a `Clock`, for the same reason no
/// view in this schema consults the clock (ARCH_2 §12.2): a range that reads the time itself cannot
/// be asserted against a `FixedClock`, and every analytics figure downstream would inherit that
/// non-determinism.
///
/// Both ends are **inclusive**, matching `DateKeyColumnFilters.isInDateRange` and SQL's `BETWEEN`,
/// so a resolved range can be handed straight to a query without an off-by-one adjustment.
final class DateRangeService {
  /// Creates the service.
  const DateRangeService();

  /// The earliest date this app treats as real, used as the lower bound for [DateRangePreset.allTime].
  ///
  /// A sentinel rather than a query for the oldest row: "all time" must resolve without touching the
  /// database, and `1900-01-01` is comfortably before any household record while staying well inside
  /// `DateKey`'s range.
  static final DateKey earliest = DateKey.fromYmd(1900, 1, 1);

  /// Resolves [preset] against [today].
  ///
  /// Returns null for [DateRangePreset.custom], which by definition carries dates this service does
  /// not know — the caller supplies them. Returning null rather than a guessed window means a UI
  /// that forgets to handle `custom` shows nothing instead of silently showing the wrong month.
  DateRange? resolve(DateRangePreset preset, DateKey today) {
    switch (preset) {
      case DateRangePreset.today:
        return (from: today, to: today);

      case DateRangePreset.last7Days:
        // Six days back, not seven: "last 7 days" includes today, so today plus six earlier days is
        // seven dates. Subtracting seven would span eight.
        return (from: today.addDays(-6), to: today);

      case DateRangePreset.last30Days:
        return (from: today.addDays(-29), to: today);

      case DateRangePreset.thisMonth:
        return (from: DateKey.fromYmd(today.year, today.month, 1), to: today);

      case DateRangePreset.lastMonth:
        final year = today.month == 1 ? today.year - 1 : today.year;
        final month = today.month == 1 ? 12 : today.month - 1;
        return (
          from: DateKey.fromYmd(year, month, 1),
          to: DateKey.fromYmd(year, month, _lastDayOfMonth(year, month)),
        );

      case DateRangePreset.thisYear:
        return (from: DateKey.fromYmd(today.year, 1, 1), to: today);

      case DateRangePreset.allTime:
        return (from: earliest, to: today);

      case DateRangePreset.custom:
        return null;
    }
  }

  /// The calendar month containing [anyDayInMonth], whole.
  ///
  /// What a month-grid calendar asks for: the full month regardless of where today falls, unlike
  /// [DateRangePreset.thisMonth] which stops at today.
  DateRange wholeMonthOf(DateKey anyDayInMonth) {
    final year = anyDayInMonth.year;
    final month = anyDayInMonth.month;
    return (
      from: DateKey.fromYmd(year, month, 1),
      to: DateKey.fromYmd(year, month, _lastDayOfMonth(year, month)),
    );
  }

  /// The month before [range]'s start, whole — for a period-over-period comparison.
  DateRange previousWholeMonth(DateKey anyDayInMonth) {
    final year = anyDayInMonth.month == 1 ? anyDayInMonth.year - 1 : anyDayInMonth.year;
    final month = anyDayInMonth.month == 1 ? 12 : anyDayInMonth.month - 1;
    return (
      from: DateKey.fromYmd(year, month, 1),
      to: DateKey.fromYmd(year, month, _lastDayOfMonth(year, month)),
    );
  }

  /// A window of the same length as [range] ending the day before it starts.
  ///
  /// The honest comparison for a rolling preset: "last 30 days" against the 30 days before those,
  /// rather than against a calendar month of a different length.
  DateRange precedingWindowOf(DateRange range) {
    final lengthDays = range.to.diffDays(range.from);
    final end = range.from.addDays(-1);
    return (from: end.addDays(-lengthDays), to: end);
  }

  /// True when [date] falls inside [range], both ends counted.
  bool contains(DateRange range, DateKey date) =>
      date.isWithin(range.from, range.to);

  /// How many dates [range] spans, both ends counted.
  int lengthInDays(DateRange range) => range.to.diffDays(range.from) + 1;

  /// Day zero of the following month is the last day of this one, which handles February in both
  /// leap and non-leap years without a lookup table.
  static int _lastDayOfMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;
}

```

### `lib/domain/services/currency_rate_service.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/converted_money.dart';

/// One cached rate: how many units of [quoteCode] one USD bought on [on].
///
/// Every cached rate is USD-based (ARCH_3 §1.2) — `currency_rates` never stores any other base —
/// which is what makes a single daily fetch enough for every pair the app supports.
class UsdRate {
  /// Creates a rate.
  const UsdRate({
    required this.quoteCode,
    required this.on,
    required this.rate,
    required this.rateRaw,
  });

  /// The currency being quoted against USD.
  final String quoteCode;

  /// The civil date the rate was quoted for.
  final DateKey on;

  /// Units of [quoteCode] per one USD.
  final double rate;

  /// The source's own representation of [rate], kept so a figure a user questions can be
  /// reproduced exactly (ARCH_3 §1.3.7).
  final String rateRaw;
}

/// Everything one fetch produced, normalised so the cache never learns which source it came from.
///
/// `CurrencyApiClient` maps both the fawazahmed0 and Frankfurter response shapes into this, because
/// they disagree about almost everything — key casing, nesting depth, and where the date lives
/// (ARCH_3 §1.2).
class RateSnapshot {
  /// Creates a snapshot.
  const RateSnapshot({
    required this.on,
    required this.rates,
    required this.source,
  });

  /// The civil date every rate in [rates] is quoted for.
  final DateKey on;

  /// USD-based rates, one per quote currency.
  final List<UsdRate> rates;

  /// Which ladder entry produced this, for debugging only. Never affects a conversion.
  final String source;

  /// True when the fetch produced nothing usable.
  bool get isEmpty => rates.isEmpty;
}

/// An immutable, in-memory index of every cached USD rate, and the single owner of ARCH_3 §1.2's
/// pivot and §1.3's lookup rule.
///
/// Built once and queried many times, deliberately. ARCH_3 §1.5 specifies `toHome` as a
/// *synchronous* call, which only works if the rates are already in hand — and converting a list of
/// 500 transactions for a monthly total would otherwise mean 1000 asynchronous cache round trips,
/// two per amount. Loading the table once and converting synchronously is both what the contract
/// asks for and dramatically less work.
///
/// It is also pure, which is why the whole lookup rule — including the weekend gap and the
/// approximate fallback — is testable with a literal map and no database at all.
class RateTable {
  /// Builds a table from [rates], indexing each quote currency's rates by date.
  RateTable({
    required Iterable<UsdRate> rates,
    required Map<String, int> decimalDigitsByCode,
  }) : _decimalDigits = Map.unmodifiable(decimalDigitsByCode) {
    for (final rate in rates) {
      final code = rate.quoteCode.toUpperCase();
      (_byQuote[code] ??= <UsdRate>[]).add(rate);
    }
    // Ascending by date, so the lookup can walk backwards from the target and take the first hit.
    for (final list in _byQuote.values) {
      list.sort((a, b) => DateKey.compare(a.on, b.on));
    }
  }

  /// An empty table — every lookup misses, so every conversion is `unconverted`.
  ///
  /// Only `_decimalDigits` is initialized here. `_byQuote` already has `= {}` at its declaration —
  /// which the primary constructor depends on, since it populates the map in its body rather than
  /// its initializer list — and Dart forbids initializing a final field in both places.
  RateTable.empty() : _decimalDigits = const {};

  final Map<String, List<UsdRate>> _byQuote = {};
  final Map<String, int> _decimalDigits;

  /// The USD code, which needs no cached row: one USD is one USD on every date.
  static const String pivotCode = 'USD';

  /// True when no rate is cached for any currency.
  bool get isEmpty => _byQuote.isEmpty;

  /// Every quote currency this table can resolve.
  Iterable<String> get quoteCodes => _byQuote.keys;

  /// Resolves the USD leg for [code] as of [on], applying ARCH_3 §1.3's lookup rule.
  ///
  /// The greatest cached date **on or before** [on] wins, and counts as
  /// [RateQuality.exact] however old it is — that is what makes a Saturday transaction resolve to
  /// Friday's rate instead of failing, which the rule exists for. Only when *no* row on or before
  /// [on] exists does it fall forward to the earliest row available and mark the result
  /// [RateQuality.approximate]. Never interpolates, never extrapolates.
  RateLeg? legFor({required String code, required DateKey on}) {
    final upper = code.toUpperCase();
    if (upper == pivotCode) {
      return RateLeg(rate: 1, quotedOn: on, quality: RateQuality.exact, rateRaw: '1');
    }

    final rates = _byQuote[upper];
    if (rates == null || rates.isEmpty) return null;

    UsdRate? onOrBefore;
    for (final rate in rates) {
      if (rate.on.value <= on.value) {
        onOrBefore = rate;
      } else {
        break;
      }
    }
    if (onOrBefore != null) {
      return RateLeg(
        rate: onOrBefore.rate,
        quotedOn: onOrBefore.on,
        quality: RateQuality.exact,
        rateRaw: onOrBefore.rateRaw,
      );
    }

    final earliest = rates.first;
    return RateLeg(
      rate: earliest.rate,
      quotedOn: earliest.on,
      quality: RateQuality.approximate,
      rateRaw: earliest.rateRaw,
    );
  }

  /// The cross-rate from [from] to [to] as of [on], or null when either leg is missing.
  ///
  /// `INR→JPY = (USD→JPY) / (USD→INR)`, exactly as ARCH_3 §1.2 specifies. Both legs come from the
  /// same USD pivot, so no pair needs its own cached row.
  CrossRate? crossRate({
    required String from,
    required String to,
    required DateKey on,
  }) {
    if (from.toUpperCase() == to.toUpperCase()) {
      return CrossRate(rate: 1, quotedOn: on, quality: RateQuality.exact);
    }
    final fromLeg = legFor(code: from, on: on);
    final toLeg = legFor(code: to, on: on);
    if (fromLeg == null || toLeg == null) return null;
    if (fromLeg.rate == 0) return null;

    return CrossRate(
      rate: toLeg.rate / fromLeg.rate,
      quotedOn: _combinedQuotedOn(fromLeg, toLeg, on),
      quality: fromLeg.quality == RateQuality.approximate ||
              toLeg.quality == RateQuality.approximate
          ? RateQuality.approximate
          : RateQuality.exact,
    );
  }

  /// Converts [amount] into [toCurrencyCode] as of [on].
  ///
  /// Returns [ConvertedMoney.unconverted] when either leg has no cached rate at all, or when
  /// either currency's precision is unknown — never a zero, because a missing rate means the amount
  /// must be *excluded* from a total rather than counted as nothing (ARCH_3 §1.3.4).
  ConvertedMoney convert({
    required Money amount,
    required String toCurrencyCode,
    required DateKey on,
  }) {
    if (amount.currencyCode.toUpperCase() == toCurrencyCode.toUpperCase()) {
      return ConvertedMoney(
        original: amount,
        quality: RateQuality.exact,
        converted: amount,
        rate: 1,
        rateDateKey: on,
      );
    }

    final cross = crossRate(from: amount.currencyCode, to: toCurrencyCode, on: on);
    if (cross == null) return ConvertedMoney.unconverted(amount);

    final fromDigits = _decimalDigits[amount.currencyCode];
    final toDigits = _decimalDigits[toCurrencyCode];
    if (fromDigits == null || toDigits == null) {
      // A rate without a precision cannot produce a correct minor-unit figure — converting into
      // JPY needs to know it has none. Excluding is honest; guessing 2 would misstate every yen.
      return ConvertedMoney.unconverted(amount);
    }

    return ConvertedMoney(
      original: amount,
      quality: cross.quality,
      converted: amount.convert(
        rate: cross.rate,
        toCurrencyCode: toCurrencyCode,
        fromDecimalDigits: fromDigits,
        toDecimalDigits: toDigits,
      ),
      rate: cross.rate,
      rateDateKey: cross.quotedOn,
    );
  }

  /// The honest "as of" date for a cross-rate built from [fromLeg] and [toLeg].
  ///
  /// When both legs resolved exactly, the answer is the requested date. When a leg fell *forward*
  /// past it — the only way [RateQuality.approximate] is reached — the conversion cannot truthfully
  /// claim to be as of anything earlier than the latest such fallback.
  DateKey _combinedQuotedOn(RateLeg fromLeg, RateLeg toLeg, DateKey on) {
    final fromApprox = fromLeg.quality == RateQuality.approximate;
    final toApprox = toLeg.quality == RateQuality.approximate;
    if (!fromApprox && !toApprox) return on;
    if (fromApprox && !toApprox) return fromLeg.quotedOn;
    if (toApprox && !fromApprox) return toLeg.quotedOn;
    return fromLeg.quotedOn.value > toLeg.quotedOn.value ? fromLeg.quotedOn : toLeg.quotedOn;
  }
}

/// One resolved side of a USD-pivoted lookup.
class RateLeg {
  /// Creates a leg.
  const RateLeg({
    required this.rate,
    required this.quotedOn,
    required this.quality,
    required this.rateRaw,
  });

  /// Units of the quote currency per one USD.
  final double rate;

  /// The date the applied rate was actually quoted for, which may not be the date requested.
  final DateKey quotedOn;

  /// How reliable this leg is.
  final RateQuality quality;

  /// The source's own string for [rate].
  final String rateRaw;
}

/// A resolved rate between two non-USD currencies.
class CrossRate {
  /// Creates a cross-rate.
  const CrossRate({
    required this.rate,
    required this.quotedOn,
    required this.quality,
  });

  /// Units of the target currency per one unit of the source.
  final double rate;

  /// The honest "as of" date for this rate.
  final DateKey quotedOn;

  /// How reliable this rate is.
  final RateQuality quality;
}

/// Loads every cached USD rate plus each currency's precision, as one table.
///
/// A function rather than an interface so `domain/` never names a `data/` type (Law L12): Phase 5's
/// wiring passes a closure over `CurrencyDao`.
typedef RateTableLoader = Future<RateTable> Function();

/// Persists a fetched snapshot into the rate cache.
typedef RateSnapshotSaver = Future<void> Function(RateSnapshot snapshot);

/// Fetches today's rates, or returns null when every ladder entry failed.
typedef RateSnapshotFetcher = Future<RateSnapshot?> Function();

/// Reads the newest cached rate date, so a same-day sync can be skipped.
typedef NewestRateDateReader = Future<DateKey?> Function();

/// Orchestrates the currency subsystem: ARCH_3 §1.5's service contract.
final class CurrencyRateService {
  /// Creates the service over its four collaborators, each a function so this stays inside
  /// `domain/` without importing anything from `data/`.
  const CurrencyRateService({
    required RateTableLoader loadTable,
    required RateSnapshotSaver saveSnapshot,
    required RateSnapshotFetcher fetchSnapshot,
    required NewestRateDateReader newestCachedDate,
    required Clock clock,
  })  : _loadTable = loadTable,
        _saveSnapshot = saveSnapshot,
        _fetchSnapshot = fetchSnapshot,
        _newestCachedDate = newestCachedDate,
        _clock = clock;

  final RateTableLoader _loadTable;
  final RateSnapshotSaver _saveSnapshot;
  final RateSnapshotFetcher _fetchSnapshot;
  final NewestRateDateReader _newestCachedDate;
  final Clock _clock;

  /// Loads the current rate table. Callers converting more than one amount should hold onto it.
  Future<RateTable> table() => _loadTable();

  /// Converts [amount] into [homeCurrencyCode] as of [on].
  ///
  /// Loads the table per call, so prefer [table] plus [RateTable.convert] for a list.
  Future<ConvertedMoney> toHome({
    required Money amount,
    required DateKey on,
    required String homeCurrencyCode,
  }) async {
    final rates = await _loadTable();
    return rates.convert(amount: amount, toCurrencyCode: homeCurrencyCode, on: on);
  }

  /// The rate from [from] to [to] as of [on], for the explicit freeze action (ARCH_3 §1.3.6).
  Future<CrossRate?> rateOn({
    required String from,
    required String to,
    required DateKey on,
  }) async {
    final rates = await _loadTable();
    return rates.crossRate(from: from, to: to, on: on);
  }

  /// Fetches and caches today's rates, at most once a day.
  ///
  /// **Never throws and never blocks a write** (Law L11, ARCH_3 §1.3.2). Every failure path — no
  /// network, a ladder that exhausted all three entries, a malformed body, a database error on
  /// save — returns normally, because a rate is a display convenience and a transaction the user
  /// just typed is not. Callers may safely ignore the future entirely.
  ///
  /// Skips the fetch when the cache already holds today's date, which is what makes ARCH_3 §1.2's
  /// "one request per day for the entire app, forever" true rather than aspirational.
  Future<void> syncDailyRates() async {
    try {
      final today = _clock.today();
      final newest = await _newestCachedDate();
      if (newest != null && !newest.isBefore(today)) return;

      final snapshot = await _fetchSnapshot();
      if (snapshot == null || snapshot.isEmpty) return;
      await _saveSnapshot(snapshot);
    } catch (_) {
      // Deliberately swallowed. See the doc comment: this method exists to be safe to call from a
      // foreground hook without any caller having to reason about failure.
      return;
    }
  }
}

```

### `lib/domain/services/balance_service.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// One account's balance plus whether it counts toward net worth.
///
/// A narrow input type rather than the full `Account` entity: net worth needs three facts, and
/// asking for twenty-six would couple this service to every unrelated change to an account.
class AccountBalanceInput {
  /// Creates an input row.
  const AccountBalanceInput({
    required this.accountId,
    required this.balance,
    required this.includeInNetWorth,
  });

  /// The account.
  final String accountId;

  /// Its balance, in its own currency.
  final Money balance;

  /// Whether the user wants this account counted in the headline.
  final bool includeInNetWorth;
}

/// A converted headline total, and how many balances could not be converted into it.
///
/// The count is carried rather than discarded because a missing rate must exclude an amount, not
/// count it as zero (ARCH_3 §1.3.4). A total presented without it would be quietly wrong; presented
/// with it, the UI can show `+2 unconverted` and the number stops being a lie.
class NetWorth {
  /// Creates a headline.
  const NetWorth({
    required this.total,
    required this.unconvertedCount,
    required this.isApproximate,
  });

  /// The sum of every convertible, included balance, in the home currency.
  final Money total;

  /// How many included balances had no usable rate and were left out of [total].
  final int unconvertedCount;

  /// True when at least one contributing rate had to fall back to a date outside the requested one,
  /// so the figure is indicative rather than exact (`RateQuality.approximate`).
  final bool isApproximate;

  /// True when every included balance converted cleanly.
  bool get isComplete => unconvertedCount == 0;
}

/// Computes per-account and aggregate balances.
///
/// Owns the net-worth rule so there is exactly one definition of it. `AccountRepository` supplies
/// the raw per-account balances — which come from `v_account_balances`, where a self-transfer nets to
/// zero by construction — and this service decides what counts and converts what remains.
final class BalanceService {
  /// Creates the service.
  const BalanceService();

  /// Sums [balances] into [homeCurrencyCode] using [table], as of [asOf].
  ///
  /// Pure and synchronous: given a rate table it performs no I/O, which is why the whole net-worth
  /// rule is testable from literals. Callers converting a long list should load the table once and
  /// call this, rather than converting amount by amount.
  ///
  /// **Which accounts count.** Only `includeInNetWorth`. An **archived** account still counts —
  /// ARCH_3 §4's table is explicit that archive keeps money in your net worth and only delete
  /// removes it, because a closed bank account with a remaining balance is retired, not gone. So
  /// archived-ness is deliberately not a filter here, and `AccountRepository.watchAllIncludingArchived`
  /// is the right source to feed this.
  ///
  /// **Which balances convert.** One already in [homeCurrencyCode] passes through untouched — no
  /// rate is consulted, so an all-single-currency user never sees an `unconvertedCount` above zero
  /// even with an empty rate cache.
  NetWorth totalFrom({
    required Iterable<AccountBalanceInput> balances,
    required RateTable table,
    required String homeCurrencyCode,
    required DateKey asOf,
  }) {
    var total = Money.zero(homeCurrencyCode);
    var unconverted = 0;
    var approximate = false;

    for (final input in balances) {
      if (!input.includeInNetWorth) continue;

      final converted = table.convert(
        amount: input.balance,
        toCurrencyCode: homeCurrencyCode,
        on: asOf,
      );
      if (converted.isExcludedFromTotals) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate = true;

      // `converted.converted` is in homeCurrencyCode, matching `total`, so this cannot throw a
      // currency mismatch however many source currencies were involved.
      total = total + converted.converted!;
    }

    return NetWorth(
      total: total,
      unconvertedCount: unconverted,
      isApproximate: approximate,
    );
  }

  /// Loads the rate table and sums [balances] — the convenience form of [totalFrom].
  Future<NetWorth> totalInHome({
    required Iterable<AccountBalanceInput> balances,
    required CurrencyRateService rates,
    required String homeCurrencyCode,
    required DateKey asOf,
  }) async {
    final table = await rates.table();
    return totalFrom(
      balances: balances,
      table: table,
      homeCurrencyCode: homeCurrencyCode,
      asOf: asOf,
    );
  }

  /// Converts one balance, for a per-account row that shows both its own currency and the home one.
  ConvertedMoney convertOne({
    required Money balance,
    required RateTable table,
    required String homeCurrencyCode,
    required DateKey asOf,
  }) {
    return table.convert(amount: balance, toCurrencyCode: homeCurrencyCode, on: asOf);
  }

  /// Totals [balances] per currency without converting anything.
  ///
  /// The honest answer when no rate is available at all: `₹4,000 + $50` rather than a single number
  /// that silently dropped the dollars. Also what a currency-breakdown panel needs.
  Map<String, Money> totalsByCurrency(Iterable<AccountBalanceInput> balances) {
    final byCode = <String, int>{};
    for (final input in balances) {
      if (!input.includeInNetWorth) continue;
      byCode.update(
        input.balance.currencyCode,
        (running) => running + input.balance.minor,
        ifAbsent: () => input.balance.minor,
      );
    }
    return {
      for (final entry in byCode.entries) entry.key: Money(entry.value, entry.key),
    };
  }
}

```

### `lib/data/daos/currency_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to `currencies` and the `currency_rates` cache.
class CurrencyDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  CurrencyDao(super.db);

  $CurrenciesTable get _currencies => attachedDatabase.currencies;
  $CurrencyRatesTable get _rates => attachedDatabase.currencyRates;

  SimpleSelectStatement<$CurrenciesTable, CurrencyRow> _activeCurrencies() =>
      select(_currencies)..where((t) => t.deletedAt.isNull());

  SimpleSelectStatement<$CurrencyRatesTable, CurrencyRateRow> _activeRates() =>
      select(_rates)..where((t) => t.deletedAt.isNull());

  /// Emits enabled currencies in display order, for pickers.
  Stream<List<CurrencyRow>> watchEnabled() {
    return (_activeCurrencies()
          ..where((t) => t.isEnabled.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Emits every active currency, enabled or not, for the settings screen.
  Stream<List<CurrencyRow>> watchAll() {
    return (_activeCurrencies()..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Reads one currency by ISO code.
  Future<CurrencyRow?> byCode(String code) =>
      (_activeCurrencies()..where((t) => t.code.equals(code))).getSingleOrNull();

  /// Reads `code -> decimalDigits` for every active currency.
  ///
  /// This is the lookup that keeps `100` out of the codebase (ARCH_1 §4.1): callers cache it once
  /// at startup rather than hardcoding a currency's precision. JPY resolves to 0.
  Future<Map<String, int>> decimalDigitsByCode() async {
    final rows = await _activeCurrencies().get();
    return {for (final row in rows) row.code: row.decimalDigits};
  }

  /// Inserts or updates a currency.
  Future<void> upsert(CurrenciesCompanion currency) =>
      into(_currencies).insertOnConflictUpdate(currency);

  /// Enables or disables a currency without deleting it.
  Future<void> setEnabled({
    required String code,
    required bool isEnabled,
    required int nowUtcMillis,
  }) {
    return (update(_currencies)..where((t) => t.code.equals(code))).write(
      CurrenciesCompanion(isEnabled: Value(isEnabled), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Replaces the cached rates for one fetch, in a single transaction (Law L14).
  ///
  /// The conflict target is stated explicitly, and must be. `idx_rates_point` makes
  /// `(baseCode, quoteCode, rateDateKey)` unique, but drift's `insertOnConflictUpdate` targets the
  /// **primary key** by default — and `id` is a fresh UUID on every fetch, so it never conflicts.
  /// The row would insert and only then trip the unique index, meaning the second rate fetch of any
  /// given day threw `UNIQUE constraint failed`. Verified against SQLite: with the target named,
  /// the row updates in place; without it, the insert fails.
  ///
  /// A named target works here only because `idx_rates_point` is **not** a partial index. SQLite
  /// rejects a partial index as a conflict target unless its `WHERE` predicate is repeated in the
  /// target clause, which drift's column-list API cannot express — see
  /// `RecurringOccurrenceDao.upsertForDue` for how that case has to be handled instead.
  Future<void> upsertRates(List<CurrencyRatesCompanion> rates) {
    return transaction(() async {
      for (final rate in rates) {
        await into(_rates).insert(
          rate,
          onConflict: DoUpdate(
            (_) => CurrencyRatesCompanion(
              rate: rate.rate,
              rateRaw: rate.rateRaw,
              source: rate.source,
              fetchedAt: rate.fetchedAt,
              updatedAt: rate.updatedAt,
              deletedAt: const Value(null),
            ),
            target: [_rates.baseCode, _rates.quoteCode, _rates.rateDateKey],
          ),
        );
      }
    });
  }

  /// Reads every cached rate, for building the in-memory `RateTable`.
  ///
  /// One query rather than two per conversion. `RateTable` applies ARCH_3 §1.3's lookup rule in
  /// memory, so converting a month of transactions costs a single read here instead of two round
  /// trips per amount — which is what makes ARCH_3 §1.5's synchronous `toHome` possible at all.
  ///
  /// Every row is USD-based by construction (ARCH_3 §1.2 — `currency_rates` never stores another
  /// base), so no filter on `baseCode` is needed and none is applied.
  Future<List<CurrencyRateRow>> allRates() {
    return (_activeRates()
          ..orderBy([(t) => OrderingTerm(expression: t.rateDateKey)]))
        .get();
  }

  /// The most recent cached rate for `base -> quote` dated on or before [on].
  ///
  /// This is only the SQL shape of ARCH_3 §1.3's lookup rule — "greatest `rateDateKey <= D`".
  /// The policy that follows from a miss (fall back to the earliest row and mark the result
  /// approximate) is a decision for the currency service, not for a DAO.
  Future<CurrencyRateRow?> rateOnOrBefore({
    required String baseCode,
    required String quoteCode,
    required DateKey on,
  }) {
    return (_activeRates()
          ..where((t) =>
              t.baseCode.equals(baseCode) &
              t.quoteCode.equals(quoteCode) &
              t.rateDateKey.isDateOnOrBefore(on))
          ..orderBy([(t) => OrderingTerm(expression: t.rateDateKey, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// The earliest cached rate for `base -> quote`, for the approximate-rate fallback path.
  Future<CurrencyRateRow?> earliestRate({
    required String baseCode,
    required String quoteCode,
  }) {
    return (_activeRates()
          ..where((t) => t.baseCode.equals(baseCode) & t.quoteCode.equals(quoteCode))
          ..orderBy([(t) => OrderingTerm(expression: t.rateDateKey)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// The newest `rateDateKey` held for [baseCode], so a caller can decide whether to fetch.
  Future<DateKey?> newestRateDate(String baseCode) async {
    final row = await (_activeRates()
          ..where((t) => t.baseCode.equals(baseCode))
          ..orderBy([(t) => OrderingTerm(expression: t.rateDateKey, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row?.rateDateKey;
  }
}

```

### `lib/data/daos/item_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `items` and the three views derived from its stock.
///
/// Every stock figure — remaining quantity, batch count, nearest expiry, low-stock status —
/// comes from `v_item_stock` or `v_low_stock`. This DAO never sums `inventory_batches` itself
/// (Law L7): that sum is one view's entire reason to exist, and a second copy of it here would
/// be a second place for the zero-remaining-batch exclusion rule to be gotten wrong.
class ItemDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  ItemDao(super.db);

  $ItemsTable get _table => attachedDatabase.items;

  SimpleSelectStatement<$ItemsTable, ItemRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits every active item, alphabetically.
  Stream<List<ItemRow>> watchAll() =>
      (_activeRows()..orderBy([(t) => OrderingTerm(expression: t.normalizedName)])).watch();

  /// Emits active items measuring [category] — a picker must never offer a cross-category item,
  /// since cross-category conversion does not exist (Law L8).
  Stream<List<ItemRow>> watchByCategory(UnitCategory category) {
    return (_activeRows()
          ..where((t) => t.unitCategory.equalsValue(category))
          ..orderBy([(t) => OrderingTerm(expression: t.normalizedName)]))
        .watch();
  }

  /// Emits favourited items, for a dashboard shortcut.
  Stream<List<ItemRow>> watchFavorites() {
    return (_activeRows()
          ..where((t) => t.isFavorite.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.normalizedName)]))
        .watch();
  }

  /// Reads one item by id, including a soft-deleted one — so a historical transaction line or
  /// batch that still points at it can render a name.
  Future<ItemRow?> byIdIncludingDeleted(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads the active item whose identity is `(normalizedName, category)`, or null if none
  /// exists — the merge-or-create decision (anomaly A06).
  ///
  /// Identity is the pair, not the name alone: `idx_items_identity` is a partial unique index on
  /// both columns together, so `Milk (Weight)` and `Milk (Volume)` are two different rows and
  /// this correctly returns null for a category that has no match yet, even when the name does.
  Future<ItemRow?> findByIdentity({
    required String normalizedName,
    required UnitCategory unitCategory,
  }) {
    return (_activeRows()
          ..where((t) =>
              t.normalizedName.equals(normalizedName) &
              t.unitCategory.equalsValue(unitCategory)))
        .getSingleOrNull();
  }

  /// Emits active items whose normalized name contains [term], for the item picker's search
  /// field — exact-substring only; near-match suggestion is a repository concern (anomaly A07).
  Stream<List<ItemRow>> watchMatching(String term) {
    final needle = '%${term.toLowerCase()}%';
    return (_activeRows()
          ..where((t) => t.normalizedName.like(needle))
          ..orderBy([(t) => OrderingTerm(expression: t.normalizedName)])
          ..limit(50))
        .watch();
  }

  /// Inserts or updates an item.
  ///
  /// Does not, and cannot, guard `unitCategory` immutability (Law L8) — a `Companion` carries no
  /// memory of the row it is replacing. That check belongs to the repository, which reads the
  /// existing row first and rejects a companion that changes it.
  Future<void> upsert(ItemsCompanion item) => into(_table).insertOnConflictUpdate(item);

  /// Toggles the favourite flag.
  Future<void> setFavorite({
    required String id,
    required bool isFavorite,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ItemsCompanion(isFavorite: Value(isFavorite), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Soft-deletes an item and its active batches, in one transaction (Law L14).
  ///
  /// Cascades to batches — deliberately, and only here. `stock_movements` is append-only and is
  /// never soft-deleted (Law L6's stated exception): the ledger for food that no longer has a
  /// catalogued item stays exactly as complete as it was.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return transaction(() async {
      await (update(_table)..where((t) => t.id.equals(id))).write(
        ItemsCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
      );
      await (update(attachedDatabase.inventoryBatches)
            ..where((t) => t.itemId.equals(id) & t.deletedAt.isNull()))
          .write(
        InventoryBatchesCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
    });
  }

  // ── derived stock: always from the views ───────────────────────────────────────────────

  /// Emits every active item's stock rollup from `v_item_stock`.
  Stream<List<ItemStockRow>> watchAllStock() => select(attachedDatabase.vItemStock).watch();

  /// Emits one item's stock rollup.
  Stream<ItemStockRow?> watchStockOf(String itemId) {
    return (select(attachedDatabase.vItemStock)..where((t) => t.itemId.equals(itemId)))
        .watchSingleOrNull();
  }

  /// Reads one item's stock rollup once.
  Future<ItemStockRow?> stockOf(String itemId) {
    return (select(attachedDatabase.vItemStock)..where((t) => t.itemId.equals(itemId)))
        .getSingleOrNull();
  }

  /// Emits every item currently below its low-stock threshold, from `v_low_stock`.
  Stream<List<LowStockRow>> watchLowStock() => select(attachedDatabase.vLowStock).watch();
}

```

### `lib/data/daos/shopping_entry_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `shopping_entries`.
class ShoppingEntryDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  ShoppingEntryDao(super.db);

  $ShoppingEntriesTable get _table => attachedDatabase.shoppingEntries;

  SimpleSelectStatement<$ShoppingEntriesTable, ShoppingEntryRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits the active, unchecked entries of [listId], grouped by [ShoppingEntryRow.tagId] in the
  /// UI (the group header, ARCH_2 §6) — this DAO returns the flat, sorted list; grouping is a
  /// presentation concern.
  Stream<List<ShoppingEntryRow>> watchForList(String listId) {
    return (_activeRows()
          ..where((t) => t.listId.equals(listId))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Emits only the unchecked active entries of [listId] — what the shopping screen shows by
  /// default, before "show completed" is toggled.
  Stream<List<ShoppingEntryRow>> watchUncheckedForList(String listId) {
    return (_activeRows()
          ..where((t) => t.listId.equals(listId) & t.isChecked.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Emits the currently visible auto-generated suggestions for [listId] — `active`, not
  /// `snoozed` or `dismissed` (anomaly A23).
  Stream<List<ShoppingEntryRow>> watchActiveAutoSuggestions(String listId) {
    return (_activeRows()
          ..where((t) =>
              t.listId.equals(listId) &
              t.origin.equalsValue(ShoppingEntryOrigin.autoLowStock) &
              t.autoState.equalsValue(ShoppingEntryAutoState.active))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Reads one entry by id, including a soft-deleted one.
  Future<ShoppingEntryRow?> byIdIncludingDeleted(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads the active auto-generated entry for `(listId, itemId)`, if one exists — the read side
  /// of `idx_shopping_auto`'s partial unique index, and what the suggestion engine checks before
  /// deciding whether to insert, update or leave an entry alone.
  Future<ShoppingEntryRow?> findAutoEntry({
    required String listId,
    required String itemId,
  }) {
    return (_activeRows()
          ..where((t) =>
              t.listId.equals(listId) &
              t.itemId.equals(itemId) &
              t.origin.equalsValue(ShoppingEntryOrigin.autoLowStock)))
        .getSingleOrNull();
  }

  /// Inserts or updates an entry **by primary key**.
  ///
  /// For a manual entry that is all you need: the repository holds the row's `id`, or generates a
  /// new one. For an auto-generated suggestion use [upsertAutoEntry] instead — this method will
  /// **not** dedupe against `idx_shopping_auto`, for the reason documented there.
  Future<void> upsert(ShoppingEntriesCompanion entry) =>
      into(_table).insertOnConflictUpdate(entry);

  /// Inserts or updates the single active auto-generated suggestion for `(listId, itemId)`,
  /// idempotently (anomaly A22). Calling it repeatedly is a no-op, never a crash.
  ///
  /// Read-then-write inside one transaction, and it has to be. `idx_shopping_auto` is a
  /// **partial** unique index (`WHERE origin = 'autoLowStock' AND deleted_at IS NULL`), and SQLite
  /// refuses a partial index as an `ON CONFLICT` target unless the predicate is repeated in the
  /// target clause — which drift's column-list `DoUpdate.target` has nowhere to put. Verified
  /// against SQLite: `ON CONFLICT(list_id, item_id)` fails to compile with *"ON CONFLICT clause
  /// does not match any PRIMARY KEY or UNIQUE constraint"*, and `insertOnConflictUpdate` targets
  /// the primary key, so a fresh `id` would insert and only then trip the index. Regenerating
  /// low-stock suggestions a second time threw `UNIQUE constraint failed` before this fix.
  ///
  /// [newId] is used only when no auto entry exists yet, so a caller can generate a UUID
  /// unconditionally without leaking an unused row.
  Future<void> upsertAutoEntry({
    required String newId,
    required String listId,
    required String itemId,
    required int quantityMilli,
    String? unitCode,
    String? tagId,
    required int stockAtGenerationMilli,
    required int sortOrder,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      final existing = await findAutoEntry(listId: listId, itemId: itemId);
      if (existing == null) {
        await into(_table).insert(
          ShoppingEntriesCompanion.insert(
            id: newId,
            listId: listId,
            itemId: Value(itemId),
            quantityMilli: Value(quantityMilli),
            unitCode: Value(unitCode),
            tagId: Value(tagId),
            isChecked: false,
            origin: ShoppingEntryOrigin.autoLowStock,
            autoState: ShoppingEntryAutoState.active,
            generatedAtStockMilli: Value(stockAtGenerationMilli),
            sortOrder: sortOrder,
            createdAt: nowUtcMillis,
            updatedAt: nowUtcMillis,
          ),
        );
        return;
      }
      // Refresh the suggested quantity and the stock reading it was based on. `origin` and
      // `autoState` are left alone: an entry the user has edited was already promoted to `manual`
      // and would not be found by findAutoEntry, and one they dismissed keeps that state.
      await (update(_table)..where((t) => t.id.equals(existing.id))).write(
        ShoppingEntriesCompanion(
          quantityMilli: Value(quantityMilli),
          generatedAtStockMilli: Value(stockAtGenerationMilli),
          updatedAt: Value(nowUtcMillis),
        ),
      );
    });
  }

  /// Promotes an auto-generated entry to `manual`, so the suggestion engine never removes it
  /// after the user has edited it (anomaly A22).
  Future<void> promoteToManual({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ShoppingEntriesCompanion(
        origin: const Value(ShoppingEntryOrigin.manual),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Snoozes or dismisses an auto-generated suggestion, recording the stock level at the moment
  /// of the decision so it does not reappear until stock has genuinely changed (anomaly A23).
  Future<void> setAutoState({
    required String id,
    required ShoppingEntryAutoState autoState,
    required int stockAtDecisionMilli,
    DateKey? snoozeUntil,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ShoppingEntriesCompanion(
        autoState: Value(autoState),
        generatedAtStockMilli: Value(stockAtDecisionMilli),
        snoozeUntilDateKey:
            snoozeUntil == null ? const Value.absent() : Value(snoozeUntil),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Ticks or unticks an entry.
  Future<void> setChecked({
    required String id,
    required bool isChecked,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ShoppingEntriesCompanion(
        isChecked: Value(isChecked),
        checkedAt: isChecked ? Value(nowUtcMillis) : const Value(null),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Records which transaction line fulfilled this entry — the write half of convert-to-purchase
  /// (anomaly A25). Does not itself tick the entry; the repository does both in one call so
  /// "purchased" and "checked" cannot disagree.
  Future<void> markPurchased({
    required String id,
    required String transactionLineId,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ShoppingEntriesCompanion(
        purchasedTransactionLineId: Value(transactionLineId),
        isChecked: const Value(true),
        checkedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Reorders entries within a list by writing each id's new `sortOrder` in one transaction
  /// (Law L14), so a drag-reorder can never leave the list half-renumbered.
  Future<void> reorder({
    required List<String> orderedIds,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(_table)..where((t) => t.id.equals(orderedIds[i]))).write(
          ShoppingEntriesCompanion(sortOrder: Value(i), updatedAt: Value(nowUtcMillis)),
        );
      }
    });
  }

  /// Soft-deletes an entry.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      ShoppingEntriesCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
    );
  }
}

```

### `lib/data/db/tables/meta_tables.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';

/// Key/value store for everything user-configurable (ARCH_2 §3). Natural text key, no UUID.
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  /// Setting identifier, e.g. `homeCurrencyCode`.
  TextColumn get key => text()();

  /// The setting value, always serialised to text; [valueType] says how to read it.
  TextColumn get value => text()();

  /// How to interpret [value] — e.g. `string`, `int`, `bool`, `json`. Free text rather than an
  /// enum: Phase 1A declares no enum for it, and inventing one here would be a schema contract
  /// (Law L13) created by guesswork.
  TextColumn get valueType => text()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Supported currencies, extensible with no migration (ARCH_2 §3). Natural text key.
@DataClassName('CurrencyRow')
class Currencies extends Table {
  /// ISO 4217 code, e.g. `INR`.
  TextColumn get code => text()();

  /// Display name, e.g. `Indian Rupee`.
  TextColumn get name => text()();

  /// Display symbol, e.g. `₹`.
  TextColumn get symbol => text()();

  /// Minor units per major unit as a power of ten — 2 for INR/USD/EUR/CNY, 0 for JPY. The
  /// reason nothing in the app hardcodes `100` (ARCH_1 §4.1).
  IntColumn get decimalDigits => integer()();

  /// Whether this currency is offered in pickers.
  BoolColumn get isEnabled => boolean()();

  /// Manual ordering within pickers.
  IntColumn get sortOrder => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {code};
}

/// Daily exchange-rate cache. Only ever holds rows with `baseCode = 'USD'` — every other pair
/// is cross-rated locally from the USD pivot (ARCH_3 §1.2), which is what keeps the app to one
/// HTTP request per day.
@DataClassName('CurrencyRateRow')
class CurrencyRates extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Base currency of the quote. Always `USD` in practice.
  TextColumn get baseCode => text().references(Currencies, #code)();

  /// Quoted currency.
  TextColumn get quoteCode => text().references(Currencies, #code)();

  /// Civil date the rate applies to.
  IntColumn get rateDateKey => integer().map(const DateKeyConverter())();

  /// The rate as a double, for display and arithmetic.
  RealColumn get rate => real()();

  /// The exact string the API returned, so any number a user questions can be reproduced
  /// (ARCH_3 §1.3).
  TextColumn get rateRaw => text()();

  /// Which endpoint supplied it, for debugging the fallback ladder.
  TextColumn get source => text()();

  /// Fetch instant, epoch millis UTC.
  IntColumn get fetchedAt => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// System and user-defined units, each an exact integer factor to its category base
/// (ARCH_1 §5.3). Natural text key.
@DataClassName('UnitRow')
class Units extends Table {
  /// Unit code, e.g. `kg`, `ml`, `dozen`.
  TextColumn get code => text()();

  /// Which of the three fixed categories this unit measures.
  TextColumn get category => text().map(const UnitCategoryConverter())();

  /// Exact integer milli-base units per one of this unit — `kg` is `1000000`, `dozen` is
  /// `12000`. Integer by design: unit conversion never touches a double (Law L2).
  IntColumn get factorToBaseMilli => integer()();

  /// Human-readable name for pickers.
  TextColumn get displayName => text()();

  /// Whether this unit was seeded rather than user-created; system units cannot be deleted.
  BoolColumn get isSystem => boolean()();

  /// Manual ordering within pickers.
  IntColumn get sortOrder => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {code};
}

/// Receipt and warranty images. Defined in Phase 1B with no UI until Phase 8B, purely so that
/// adding attachments later is not a migration (ARCH_2 §3).
@DataClassName('AttachmentRow')
class Attachments extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Which kind of record owns this attachment, e.g. `transaction`, `asset`. Free text rather
  /// than a real foreign key: this is the one intentionally polymorphic pointer in the schema,
  /// and anomaly A35's fix was to avoid polymorphic FKs elsewhere by using join tables — an
  /// attachment genuinely can belong to any owner type, so integrity is enforced in the
  /// repository instead.
  TextColumn get ownerType => text()();

  /// The owning record's id.
  TextColumn get ownerId => text()();

  /// Path relative to the app's attachment directory, never absolute — absolute paths break
  /// on restore to a different device.
  TextColumn get relativePath => text()();

  /// MIME type, e.g. `image/jpeg`.
  TextColumn get mimeType => text()();

  /// File size in bytes, for the backup size estimate.
  IntColumn get sizeBytes => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
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
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/repositories/currency_repository.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';
import 'package:alaya/data/repositories/mappers/currency_mapper.dart';

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
    return RateTable(
      rates: rows.map(
            (row) => UsdRate(
          quoteCode: row.quoteCode,
          on: row.rateDateKey,
          rate: row.rate,
          rateRaw: row.rateRaw,
        ),
      ),
      decimalDigitsByCode: await _dao.decimalDigitsByCode(),
    );
  }
}

```

### `test/domain/currency_rate_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// Exercises ARCH_3 §1.2's USD pivot and §1.3's lookup rule.
///
/// Every test builds a `RateTable` from literals. That is possible because the table is pure — no
/// database, no mocks, no fakes — which is the whole reason the lookup rule lives there rather than
/// inside a repository.
void main() {
  // Frankfurter is ECB-backed and publishes no weekend rows. Friday the 24th, then Monday the 27th,
  // with the 25th and 26th deliberately absent — the gap the lookup rule exists for.
  final friday = DateKey.fromYmd(2026, 7, 24);
  final saturday = DateKey.fromYmd(2026, 7, 25);
  final sunday = DateKey.fromYmd(2026, 7, 26);
  final monday = DateKey.fromYmd(2026, 7, 27);

  const digits = {'USD': 2, 'INR': 2, 'EUR': 2, 'JPY': 0, 'CNY': 2};

  RateTable tableWithWeekendGap() => RateTable(
        rates: [
          UsdRate(quoteCode: 'INR', on: friday, rate: 83.10, rateRaw: '83.1'),
          UsdRate(quoteCode: 'INR', on: monday, rate: 83.30, rateRaw: '83.3'),
          UsdRate(quoteCode: 'JPY', on: friday, rate: 158.20, rateRaw: '158.2'),
          UsdRate(quoteCode: 'JPY', on: monday, rate: 158.60, rateRaw: '158.6'),
        ],
        decimalDigitsByCode: digits,
      );

  group('the weekend gap — §1.3 rule 3', () {
    test('a Saturday resolves to Friday\'s rate rather than failing', () {
      final leg = tableWithWeekendGap().legFor(code: 'INR', on: saturday);

      expect(leg, isNotNull, reason: 'a Saturday must resolve, not fail');
      expect(leg!.quotedOn, friday);
      expect(leg.rate, 83.10);
    });

    test('Friday\'s rate used on Saturday is EXACT, not approximate', () {
      final leg = tableWithWeekendGap().legFor(code: 'INR', on: saturday);

      // The rule is "greatest rateDateKey <= D". A hit is exact however old it is; `approximate` is
      // reserved for the case where no row on or before D exists at all. Marking a weekend
      // approximate would flag every Saturday transaction in the app as unreliable.
      expect(leg!.quality, RateQuality.exact);
    });

    test('Sunday also resolves to Friday, not forward to Monday', () {
      final leg = tableWithWeekendGap().legFor(code: 'INR', on: sunday);

      expect(leg!.quotedOn, friday);
      expect(leg.rate, 83.10, reason: 'never extrapolates forward to a rate not yet quoted');
    });

    test('Monday takes Monday\'s own rate', () {
      final leg = tableWithWeekendGap().legFor(code: 'INR', on: monday);

      expect(leg!.quotedOn, monday);
      expect(leg.rate, 83.30);
    });

    test('a rate months stale is still exact — the rule never expires a row', () {
      final leg = tableWithWeekendGap().legFor(code: 'INR', on: DateKey.fromYmd(2027, 3, 1));

      expect(leg!.quotedOn, monday);
      expect(leg.quality, RateQuality.exact);
    });

    test('a full conversion on a Saturday succeeds', () {
      final converted = tableWithWeekendGap().convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'USD',
        on: saturday,
      );

      expect(converted.quality, RateQuality.exact);
      expect(converted.isExcludedFromTotals, isFalse);
      expect(converted.rateDateKey, saturday,
          reason: 'an exact resolution reports the date asked for');
    });
  });

  group('USD pivot cross-rating — §1.2', () {
    test('INR to JPY is (USD to JPY) / (USD to INR)', () {
      final cross = tableWithWeekendGap().crossRate(from: 'INR', to: 'JPY', on: monday);

      expect(cross, isNotNull);
      expect(cross!.rate, closeTo(158.60 / 83.30, 1e-12));
      expect(cross.quality, RateQuality.exact);
    });

    test('1000 INR converts to roughly 1904 JPY', () {
      final converted = tableWithWeekendGap().convert(
        // 1000.00 INR in minor units.
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'JPY',
        on: monday,
      );

      expect(converted.converted, isNotNull);
      expect(converted.converted!.currencyCode, 'JPY');
      // JPY has zero decimal digits, so its minor unit IS the yen. 1000 x (158.6/83.3) = 1903.96,
      // which rounds to 1904.
      expect(converted.converted!.minor, closeTo(1904, 1));
    });

    test('the reverse rate is the reciprocal, so a round trip returns the original', () {
      final table = tableWithWeekendGap();
      final forward = table.crossRate(from: 'INR', to: 'JPY', on: monday)!;
      final back = table.crossRate(from: 'JPY', to: 'INR', on: monday)!;

      expect(back.rate, closeTo(1 / forward.rate, 1e-12));
      expect(1000 * forward.rate * back.rate, closeTo(1000, 1e-9));
    });

    test('USD needs no cached row — it is the pivot', () {
      final leg = RateTable.empty().legFor(code: 'USD', on: monday);

      expect(leg, isNotNull, reason: 'one USD is one USD on every date');
      expect(leg!.rate, 1);
      expect(leg.quality, RateQuality.exact);
    });

    test('converting a currency to itself needs no rate at all', () {
      final converted = RateTable.empty().convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'INR',
        on: monday,
      );

      expect(converted.quality, RateQuality.exact);
      expect(converted.converted, const Money(100000, 'INR'));
      expect(converted.isExcludedFromTotals, isFalse);
    });
  });

  group('no rate cached — §1.3 rule 4', () {
    test('a missing currency yields unconverted, never a zero', () {
      final converted = tableWithWeekendGap().convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'CNY',
        on: monday,
      );

      expect(converted.quality, RateQuality.unconverted);
      expect(converted.converted, isNull,
          reason: 'a zero would be counted in a total; null forces exclusion');
      expect(converted.isExcludedFromTotals, isTrue);
    });

    test('the original amount survives on an unconverted result', () {
      final converted = tableWithWeekendGap().convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'CNY',
        on: monday,
      );

      expect(converted.original, const Money(100000, 'INR'));
      expect(converted.display, const Money(100000, 'INR'),
          reason: 'the row still shows the amount the user typed');
    });

    test('an empty table converts nothing but throws nothing', () {
      final converted = RateTable.empty().convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'USD',
        on: monday,
      );

      expect(converted.isExcludedFromTotals, isTrue);
    });

    test('a known rate with unknown precision is excluded rather than guessed', () {
      final table = RateTable(
        rates: [UsdRate(quoteCode: 'INR', on: monday, rate: 83.30, rateRaw: '83.3')],
        // JPY's precision is absent, so its minor unit is unknown.
        decimalDigitsByCode: const {'INR': 2},
      );

      final converted = table.convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'JPY',
        on: monday,
      );

      expect(converted.isExcludedFromTotals, isTrue,
          reason: 'assuming 2 digits would misstate every yen figure by a factor of 100');
    });
  });

  group('approximate quality', () {
    test('a leg whose cache starts after the target falls forward and is approximate', () {
      final table = RateTable(
        rates: [
          UsdRate(quoteCode: 'INR', on: friday, rate: 83.10, rateRaw: '83.1'),
          // EUR's earliest row is a week after the date being asked about.
          UsdRate(quoteCode: 'EUR', on: DateKey.fromYmd(2026, 8, 1), rate: 0.92, rateRaw: '0.92'),
        ],
        decimalDigitsByCode: digits,
      );

      final cross = table.crossRate(from: 'INR', to: 'EUR', on: friday)!;

      expect(cross.quality, RateQuality.approximate);
      expect(cross.quotedOn, DateKey.fromYmd(2026, 8, 1),
          reason: 'reports the date actually used, which is the source of the doubt');
    });

    test('when both legs fall forward, the later date is reported', () {
      final table = RateTable(
        rates: [
          UsdRate(quoteCode: 'EUR', on: DateKey.fromYmd(2026, 8, 1), rate: 0.92, rateRaw: '0.92'),
          UsdRate(quoteCode: 'CNY', on: DateKey.fromYmd(2026, 9, 10), rate: 7.1, rateRaw: '7.1'),
        ],
        decimalDigitsByCode: digits,
      );

      final cross = table.crossRate(from: 'EUR', to: 'CNY', on: friday)!;

      expect(cross.quality, RateQuality.approximate);
      expect(cross.quotedOn, DateKey.fromYmd(2026, 9, 10),
          reason: 'the conversion cannot claim to be as of a date before its latest fallback');
    });

    test('one approximate leg makes the whole conversion approximate', () {
      final table = RateTable(
        rates: [
          UsdRate(quoteCode: 'INR', on: friday, rate: 83.10, rateRaw: '83.1'),
          UsdRate(quoteCode: 'EUR', on: DateKey.fromYmd(2026, 8, 1), rate: 0.92, rateRaw: '0.92'),
        ],
        decimalDigitsByCode: digits,
      );

      final converted = table.convert(
        amount: const Money(100000, 'INR'),
        toCurrencyCode: 'EUR',
        on: friday,
      );

      expect(converted.quality, RateQuality.approximate);
      expect(converted.hasConversion, isTrue,
          reason: 'approximate still converts — it is indicative, not missing');
      expect(converted.isExcludedFromTotals, isFalse);
    });
  });

  group('syncDailyRates never throws and never blocks — §1.3 rule 2, Law L11', () {
    CurrencyRateService serviceWith({
      required RateSnapshotFetcher fetch,
      required RateSnapshotSaver save,
      NewestRateDateReader? newest,
      RateTableLoader? load,
    }) {
      return CurrencyRateService(
        loadTable: load ?? () async => RateTable.empty(),
        saveSnapshot: save,
        fetchSnapshot: fetch,
        newestCachedDate: newest ?? () async => null,
        clock: FixedClock(DateTime.utc(2026, 7, 27)),
      );
    }

    test('a client that always throws is swallowed', () async {
      var saved = false;
      final service = serviceWith(
        fetch: () async => throw const SocketExceptionStub(),
        save: (_) async => saved = true,
      );

      await expectLater(service.syncDailyRates(), completes);
      expect(saved, isFalse);
    });

    test('a client returning null is a no-op', () async {
      var saved = false;
      final service = serviceWith(fetch: () async => null, save: (_) async => saved = true);

      await service.syncDailyRates();

      expect(saved, isFalse);
    });

    test('an empty snapshot is not saved', () async {
      var saved = false;
      final service = serviceWith(
        fetch: () async =>
            RateSnapshot(on: monday, rates: const [], source: 'test'),
        save: (_) async => saved = true,
      );

      await service.syncDailyRates();

      expect(saved, isFalse, reason: 'an empty fetch must not overwrite a working cache');
    });

    test('a save that throws is swallowed too', () async {
      final service = serviceWith(
        fetch: () async => RateSnapshot(
          on: monday,
          rates: [UsdRate(quoteCode: 'INR', on: monday, rate: 83.3, rateRaw: '83.3')],
          source: 'test',
        ),
        save: (_) async => throw StateError('database is locked'),
      );

      await expectLater(service.syncDailyRates(), completes);
    });

    test('a reader that throws is swallowed too', () async {
      var fetched = false;
      final service = serviceWith(
        fetch: () async {
          fetched = true;
          return null;
        },
        save: (_) async {},
        newest: () async => throw StateError('database is locked'),
      );

      await expectLater(service.syncDailyRates(), completes);
      expect(fetched, isFalse, reason: 'it failed before reaching the network');
    });

    test('a successful fetch is saved once', () async {
      RateSnapshot? saved;
      final service = serviceWith(
        fetch: () async => RateSnapshot(
          on: monday,
          rates: [UsdRate(quoteCode: 'INR', on: monday, rate: 83.3, rateRaw: '83.3')],
          source: 'test',
        ),
        save: (snapshot) async => saved = snapshot,
      );

      await service.syncDailyRates();

      expect(saved, isNotNull);
      expect(saved!.rates.single.quoteCode, 'INR');
    });

    test('today\'s rates already cached means no fetch at all — one request per day', () async {
      var fetched = false;
      final service = serviceWith(
        fetch: () async {
          fetched = true;
          return null;
        },
        save: (_) async {},
        newest: () async => monday,
      );

      await service.syncDailyRates();

      expect(fetched, isFalse, reason: 'ARCH_3 §1.2 promises one request per day, forever');
    });

    test('a stale cache does trigger a fetch', () async {
      var fetched = false;
      final service = serviceWith(
        fetch: () async {
          fetched = true;
          return null;
        },
        save: (_) async {},
        newest: () async => friday,
      );

      await service.syncDailyRates();

      expect(fetched, isTrue);
    });
  });
}

/// Stands in for a network failure without importing `dart:io`, which a pure domain test should not
/// need.
class SocketExceptionStub implements Exception {
  /// Creates the stub.
  const SocketExceptionStub();
}

```

### `test/domain/balance_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// Exercises the net-worth rule: what counts, what converts, and what is excluded.
///
/// `BalanceService.totalFrom` is pure given a rate table, so none of this needs a database.
void main() {
  const service = BalanceService();
  final asOf = DateKey.fromYmd(2026, 7, 27);

  const digits = {'USD': 2, 'INR': 2, 'EUR': 2, 'JPY': 0, 'CNY': 2};

  RateTable table() => RateTable(
        rates: [
          UsdRate(quoteCode: 'INR', on: asOf, rate: 83.30, rateRaw: '83.3'),
          UsdRate(quoteCode: 'EUR', on: asOf, rate: 0.92, rateRaw: '0.92'),
          UsdRate(quoteCode: 'JPY', on: asOf, rate: 158.60, rateRaw: '158.6'),
        ],
        decimalDigitsByCode: digits,
      );

  AccountBalanceInput account(
    String id,
    int minor,
    String code, {
    bool includeInNetWorth = true,
  }) =>
      AccountBalanceInput(
        accountId: id,
        balance: Money(minor, code),
        includeInNetWorth: includeInNetWorth,
      );

  group('what counts toward net worth', () {
    test('an account with includeInNetWorth false is excluded from the total', () {
      final result = service.totalFrom(
        balances: [
          account('cash', 400000, 'INR'),
          account('loan', 999999, 'INR', includeInNetWorth: false),
        ],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, const Money(400000, 'INR'));
      expect(result.unconvertedCount, 0,
          reason: 'deliberately excluded is not the same as unconvertible');
    });

    test('an ARCHIVED account still counts — archive keeps money in net worth', () {
      // ARCH_3 §4's table is explicit: `isArchived` is "counted in totals? yes". Only `deletedAt`
      // removes money. A closed bank account holding a balance is retired, not gone — and the
      // repository filters soft-deleted rows before this service ever sees them, so archived-ness
      // is deliberately not a filter here.
      final result = service.totalFrom(
        balances: [
          account('cash', 400000, 'INR'),
          account('old-bank', 250000, 'INR'),
        ],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, const Money(650000, 'INR'));
    });

    test('no accounts at all is a zero in the home currency, not an error', () {
      final result = service.totalFrom(
        balances: const [],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, Money.zero('INR'));
      expect(result.isComplete, isTrue);
    });

    test('a negative balance reduces the total', () {
      final result = service.totalFrom(
        balances: [account('cash', 400000, 'INR'), account('overdrawn', -150000, 'INR')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, const Money(250000, 'INR'));
    });
  });

  group('conversion', () {
    test('a balance already in the home currency needs no rate', () {
      final result = service.totalFrom(
        balances: [account('cash', 400000, 'INR')],
        // An entirely empty table: a single-currency user must never see an unconverted chip.
        table: RateTable.empty(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, const Money(400000, 'INR'));
      expect(result.unconvertedCount, 0);
      expect(result.isComplete, isTrue);
    });

    test('mixed currencies convert into one home total', () {
      final result = service.totalFrom(
        balances: [
          account('inr', 100000, 'INR'), // 1000.00 INR
          account('usd', 10000, 'USD'), // 100.00 USD -> 8330.00 INR
        ],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      // 1000 + (100 x 83.30) = 9330.00 INR
      expect(result.total.currencyCode, 'INR');
      expect(result.total.minor, closeTo(933000, 100));
      expect(result.unconvertedCount, 0);
    });

    test('a zero-decimal currency converts without being inflated', () {
      final result = service.totalFrom(
        // 10,000 yen. JPY has no minor unit, so `minor` IS the yen count.
        balances: [account('jpy', 10000, 'JPY')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      // 10000 JPY / 158.60 x 83.30 = about 5251 INR = 525,100 minor units.
      expect(result.total.minor, closeTo(525100, 2000));
    });
  });

  group('unconverted amounts are EXCLUDED, never counted as zero', () {
    test('a balance with no cached rate raises the count and leaves the total alone', () {
      final result = service.totalFrom(
        balances: [
          account('inr', 400000, 'INR'),
          // CNY has no row in the table at all.
          account('cny', 700000, 'CNY'),
        ],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, const Money(400000, 'INR'),
          reason: 'the CNY balance is left out entirely');
      expect(result.unconvertedCount, 1);
      expect(result.isComplete, isFalse);
    });

    test('counting it as zero would be indistinguishable from an empty account', () {
      final excluded = service.totalFrom(
        balances: [account('inr', 400000, 'INR'), account('cny', 700000, 'CNY')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );
      final asIfEmpty = service.totalFrom(
        balances: [account('inr', 400000, 'INR'), account('cny', 0, 'CNY')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      // The totals match, which is exactly why the count has to exist — without it these two very
      // different situations would look identical to the user.
      expect(excluded.total, asIfEmpty.total);
      expect(excluded.unconvertedCount, 1);
      expect(asIfEmpty.unconvertedCount, 1);
    });

    test('every balance unconvertible gives a zero total and a full count', () {
      final result = service.totalFrom(
        balances: [account('cny', 700000, 'CNY'), account('brl', 500000, 'BRL')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.total, Money.zero('INR'));
      expect(result.unconvertedCount, 2);
      expect(result.isComplete, isFalse);
    });

    test('an excluded account that is also unconvertible does not raise the count', () {
      final result = service.totalFrom(
        balances: [account('cny', 700000, 'CNY', includeInNetWorth: false)],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.unconvertedCount, 0,
          reason: 'it was never going to be in the total, so it is not missing from it');
    });
  });

  group('approximate rates', () {
    test('an approximate leg marks the whole headline approximate but still totals', () {
      final staleTable = RateTable(
        rates: [
          UsdRate(quoteCode: 'INR', on: asOf, rate: 83.30, rateRaw: '83.3'),
          // EUR's earliest row is after the date asked about, so the leg falls forward.
          UsdRate(
            quoteCode: 'EUR',
            on: DateKey.fromYmd(2026, 9, 1),
            rate: 0.92,
            rateRaw: '0.92',
          ),
        ],
        decimalDigitsByCode: digits,
      );

      final result = service.totalFrom(
        balances: [account('inr', 100000, 'INR'), account('eur', 10000, 'EUR')],
        table: staleTable,
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.isApproximate, isTrue);
      expect(result.unconvertedCount, 0, reason: 'approximate still converts');
      expect(result.total.minor, greaterThan(100000));
    });

    test('all-exact rates leave the headline exact', () {
      final result = service.totalFrom(
        balances: [account('inr', 100000, 'INR'), account('usd', 10000, 'USD')],
        table: table(),
        homeCurrencyCode: 'INR',
        asOf: asOf,
      );

      expect(result.isApproximate, isFalse);
    });
  });

  group('totalsByCurrency — the honest answer with no rates', () {
    test('groups per currency without converting anything', () {
      final totals = service.totalsByCurrency([
        account('a', 400000, 'INR'),
        account('b', 250000, 'INR'),
        account('c', 10000, 'USD'),
      ]);

      expect(totals['INR'], const Money(650000, 'INR'));
      expect(totals['USD'], const Money(10000, 'USD'));
    });

    test('respects includeInNetWorth', () {
      final totals = service.totalsByCurrency([
        account('a', 400000, 'INR'),
        account('b', 999999, 'INR', includeInNetWorth: false),
      ]);

      expect(totals['INR'], const Money(400000, 'INR'));
    });

    test('never adds across currencies', () {
      final totals = service.totalsByCurrency([
        account('a', 400000, 'INR'),
        account('c', 10000, 'JPY'),
      ]);

      expect(totals.keys.toSet(), {'INR', 'JPY'},
          reason: 'adding rupees to yen is exactly what this method exists to prevent');
    });
  });
}

```
