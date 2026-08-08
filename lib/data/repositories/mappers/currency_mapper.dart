import 'package:drift/drift.dart' show Value;

import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/entities/currency.dart';

/// Converts between `CurrencyRow` and the domain `Currency` entity.
extension CurrencyMapper on CurrencyRow {
  /// Maps this row to a domain entity.
  Currency toEntity() => Currency(
    code: code,
    name: name,
    symbol: symbol,
    decimalDigits: decimalDigits,
    isEnabled: isEnabled,
    sortOrder: sortOrder,
  );
}

/// Builds the companion for [currency], given the `(createdAt, updatedAt)` pair
/// `WriteTimestamps.resolve` decided.
CurrenciesCompanion currencyToCompanion(
    Currency currency, {
      required int createdAt,
      required int updatedAt,
    }) {
  return CurrenciesCompanion.insert(
    code: currency.code,
    name: currency.name,
    symbol: currency.symbol,
    decimalDigits: currency.decimalDigits,
    isEnabled: currency.isEnabled,
    sortOrder: currency.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: const Value(null),
  );
}