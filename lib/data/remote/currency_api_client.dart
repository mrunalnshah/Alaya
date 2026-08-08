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
