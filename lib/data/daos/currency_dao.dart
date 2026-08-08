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
    return (_activeCurrencies()
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Reads one currency by ISO code.
  Future<CurrencyRow?> byCode(String code) =>
      (_activeCurrencies()..where((t) => t.code.equals(code)))
          .getSingleOrNull();

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
      CurrenciesCompanion(
        isEnabled: Value(isEnabled),
        updatedAt: Value(nowUtcMillis),
      ),
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

  /// Emits every cached rate, re-emitting whenever the rate cache is written.
  ///
  /// The streaming counterpart to [allRates], added in Phase 7B. Nothing here could previously
  /// observe a rate arriving: every rate read on this DAO is a `Future`, and [watchEnabled] and
  /// [watchAll] are over `currencies`. That left `CurrencyRepository.watchUnconvertedCount` unable to
  /// meet ARCH_3 §1.5's actual requirement — re-evaluate convertibility **whenever the rate cache
  /// changes** — so it stayed a `Stream.value(0)` stub for three phases.
  Stream<List<CurrencyRateRow>> watchAllRates() {
    return (_activeRates()
          ..orderBy([(t) => OrderingTerm(expression: t.rateDateKey)]))
        .watch();
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
          ..where(
            (t) =>
                t.baseCode.equals(baseCode) &
                t.quoteCode.equals(quoteCode) &
                t.rateDateKey.isDateOnOrBefore(on),
          )
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.rateDateKey,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// The earliest cached rate for `base -> quote`, for the approximate-rate fallback path.
  Future<CurrencyRateRow?> earliestRate({
    required String baseCode,
    required String quoteCode,
  }) {
    return (_activeRates()
          ..where(
            (t) => t.baseCode.equals(baseCode) & t.quoteCode.equals(quoteCode),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.rateDateKey)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// The newest `rateDateKey` held for [baseCode], so a caller can decide whether to fetch.
  Future<DateKey?> newestRateDate(String baseCode) async {
    final row =
        await (_activeRates()
              ..where((t) => t.baseCode.equals(baseCode))
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.rateDateKey,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();
    return row?.rateDateKey;
  }
}
