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