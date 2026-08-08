import 'package:drift/drift.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// Counts the active transactions whose currency no cached rate can convert (ARCH_3 §1.5).
///
/// **The count belongs with whatever is being totalled, not with the rate subsystem** — ARCH_3 §1.5
/// says so outright, and lists this half as Phase 7B's. `CurrencyRepositoryImpl` returned
/// `Stream.value(0)` because it holds a `CurrencyDao` and nothing that can see `transactions`;
/// adding a transaction query to that DAO would have been the wrong aggregate, and injecting
/// `TransactionDao` into the currency repository would have coupled two modules for one figure. So
/// the query lives here and the repository delegates.
///
/// **Built over the same `RateTable`, never a second lookup path.** §1.5 asks for exactly that: the
/// weekend-gap rule and the approximate fallback have one implementation (ARCH_3 §1.3), and a count
/// that disagreed with the totals it annotates would be worse than no count.
final class UnconvertedCounter {
  /// Creates a counter over [database], converting through [rates].
  const UnconvertedCounter({
    required AlayaDatabase database,
    required CurrencyRateService rates,
    required SettingsRepository settings,
    String fallbackHomeCurrencyCode = 'INR',
  }) : _database = database,
       _rates = rates,
       _settings = settings,
       _fallbackHome = fallbackHomeCurrencyCode;

  final AlayaDatabase _database;
  final CurrencyRateService _rates;
  final SettingsRepository _settings;
  final String _fallbackHome;

  /// Emits how many active transactions cannot be converted into the home currency.
  ///
  /// **Re-emits when the rate cache changes, which is the requirement.** ARCH_3 §1.5 rejects a
  /// static implementation precisely because convertibility has to be re-evaluated whenever a rate
  /// arrives — a fetch that fills in last Tuesday's missing rate must drop the chip's count without
  /// anyone touching a transaction. The query does not read `currency_rates`, so `readsFrom` names
  /// that table anyway: it is the set of tables whose writes invalidate the stream, not a claim
  /// about what was selected.
  ///
  /// **Affordable because it excludes the home currency in SQL.** An unbounded aggregate is
  /// ARCH_4 R7's risk, and this one has no window to bound it by — an unconvertible transaction from
  /// four years ago is still unconvertible. Filtering `<> home` means the common case, a household
  /// with one currency, returns **zero rows** however large the ledger is; a household with two
  /// returns one row per distinct date in the second currency.
  Stream<int> watch() async* {
    final home = await _settings.readHomeCurrencyCode() ?? _fallbackHome;

    yield* _database
        .customSelect(
          '''
          SELECT t.original_currency_code AS currency_code,
                 t.date_key AS date_key,
                 COUNT(*) AS row_count
            FROM v_active_transactions t
           WHERE t.original_currency_code <> ?
           GROUP BY t.original_currency_code, t.date_key
          ''',
          variables: [Variable<String>(home)],
          readsFrom: {_database.transactions, _database.currencyRates},
        )
        .watch()
        .asyncMap((rows) async {
          if (rows.isEmpty) return 0;
          final table = await _rates.table();
          var unconverted = 0;
          for (final row in rows) {
            final result = table.convert(
              // One probe per (currency, date) group rather than per transaction: convertibility is
              // a property of that pair, so a thousand rupee-denominated rows on one day ask the
              // same question once. The amount is a single minor unit because only the *quality*
              // of the answer is read.
              amount: Money(1, row.read<String>('currency_code')),
              toCurrencyCode: home,
              on: DateKey(row.read<int>('date_key')),
            );
            if (result.isExcludedFromTotals)
              unconverted += row.read<int>('row_count');
          }
          return unconverted;
        });
  }
}
