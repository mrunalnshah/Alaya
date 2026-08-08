import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/currency_dao.dart';
import 'package:alaya/data/repositories/mappers/currency_mapper.dart';
import 'package:alaya/data/repositories/mappers/rate_mappers.dart';
import 'package:alaya/data/repositories/unconverted_count.dart';
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
  ///
  /// [unconvertedCounter] is **required**, unlike [rateService], and the asymmetry is deliberate. A
  /// null rate service degrades a *write* to a no-op, which Law L11 permits outright — a rate that
  /// never arrives costs nothing. A null counter would degrade a *read* to `0`, and zero
  /// unconverted amounts is a claim that everything converted rather than an admission that nobody
  /// checked. Three phases of `Stream.value(0)` is exactly what an optional parameter here buys.
  const CurrencyRepositoryImpl(
    this._dao,
    this._clock,
    this._settings, {
    required UnconvertedCounter unconvertedCounter,
    CurrencyRateService? rateService,
  }) : _unconvertedCounter = unconvertedCounter,
       _rateService = rateService;

  final CurrencyDao _dao;
  final Clock _clock;
  final SettingsRepository _settings;
  final CurrencyRateService? _rateService;
  final UnconvertedCounter _unconvertedCounter;

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
  Future<Currency?> byCode(String code) async =>
      (await _dao.byCode(code))?.toEntity();

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
    return table.convert(
      amount: amount,
      toCurrencyCode: toCurrencyCode,
      on: on,
    );
  }

  @override
  Future<ConvertedMoney> convertToHome({
    required Money amount,
    required DateKey on,
  }) async {
    final homeCode =
        await _settings.readHomeCurrencyCode() ?? _fallbackHomeCurrencyCode;
    return convert(amount: amount, toCurrencyCode: homeCode, on: on);
  }

  @override
  /// Delegates to [UnconvertedCounter], which owns the query and the re-evaluation.
  ///
  /// **This replaced a `Stream.value(0)` stub that had stood since Phase 3B** (ARCH_3 §1.5, ARCH_5
  /// §7.3). The stub was correct to exist: a real count re-evaluates every active transaction's
  /// convertibility whenever the rate cache changes, which is analytics work, and guessing at a
  /// query would have shipped a wrong number instead of an unimplemented one.
  ///
  /// It lives in a collaborator rather than here because ARCH_3 §1.5 is explicit that the count
  /// belongs with whatever is being totalled rather than with the rate subsystem — this repository
  /// holds a `CurrencyDao` and cannot see `transactions` at all. The counter converts through the
  /// same `RateTable` this class does, so the chip and the totals it annotates cannot disagree.
  Stream<int> watchUnconvertedCount() => _unconvertedCounter.watch();

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
