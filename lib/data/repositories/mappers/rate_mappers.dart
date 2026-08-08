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
  }) => RateTable(
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
