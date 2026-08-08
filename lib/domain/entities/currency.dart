import 'package:alaya/core/money/money.dart';

/// A supported currency, with the decimal precision that keeps `100` out of the codebase.
class Currency {
  /// Creates a currency.
  const Currency({
    required this.code,
    required this.name,
    required this.symbol,
    required this.decimalDigits,
    required this.isEnabled,
    required this.sortOrder,
  });

  /// ISO 4217 code, e.g. `INR`.
  final String code;

  /// Display name, e.g. `Indian Rupee`.
  final String name;

  /// Display symbol, e.g. `₹`.
  final String symbol;

  /// Minor units per major unit as a power of ten — 2 for INR/USD/EUR/CNY, 0 for JPY.
  final int decimalDigits;

  /// Whether this currency is offered in pickers.
  final bool isEnabled;

  /// Manual ordering within pickers.
  final int sortOrder;

  /// A zero amount in this currency.
  Money get zero => Money.zero(code);

  /// A copy with the given fields replaced.
  ///
  /// Every parameter is nullable and falls back to the current value, so this cannot *clear* a
  /// nullable field. Where clearing matters — disposing an asset, unlinking a transaction — the
  /// repository constructs a new instance directly instead. The alternative, a sentinel per
  /// parameter, costs far more noise across 21 entities than it earns.
  Currency copyWith({
    String? code,
    String? name,
    String? symbol,
    int? decimalDigits,
    bool? isEnabled,
    int? sortOrder,
  }) {
    return Currency(
      code: code ?? this.code,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      decimalDigits: decimalDigits ?? this.decimalDigits,
      isEnabled: isEnabled ?? this.isEnabled,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Currency &&
          other.code == code &&
          other.name == name &&
          other.symbol == symbol &&
          other.decimalDigits == decimalDigits &&
          other.isEnabled == isEnabled &&
          other.sortOrder == sortOrder;

  @override
  int get hashCode =>
      Object.hashAll([code, name, symbol, decimalDigits, isEnabled, sortOrder]);

  @override
  String toString() => 'Currency($code)';
}