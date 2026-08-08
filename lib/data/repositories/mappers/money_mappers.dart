import 'package:alaya/core/money/money.dart';
import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/money_converter.dart';
import 'package:alaya/data/db/converters/qty_converter.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';

/// Converts between `AccountRow` and the domain `Account` entity.
///
/// Uses `MoneyColumns` rather than a drift `TypeConverter` because `Money` spans two sibling
/// columns (`openingBalanceMinor` + the row's own `currencyCode`) — see `money_converter.dart`'s
/// class doc for why no converter can do this.
extension AccountMapper on AccountRow {
  /// Maps this row to a domain entity.
  Account toEntity() => Account(
    id: id,
    name: name,
    normalizedName: normalizedName,
    kind: kind,
    currencyCode: currencyCode,
    openingBalance: MoneyColumns.read(openingBalanceMinor, currencyCode),
    openingBalanceDateKey: openingBalanceDateKey,
    isArchived: isArchived,
    includeInNetWorth: includeInNetWorth,
    sortOrder: sortOrder,
    colorArgb: colorArgb,
    iconKey: iconKey,
  );
}

/// Builds the companion for [account].
AccountsCompanion accountToCompanion(
  Account account, {
  required int createdAt,
  required int updatedAt,
}) {
  return AccountsCompanion.insert(
    id: account.id,
    name: account.name,
    normalizedName: account.normalizedName,
    kind: account.kind,
    currencyCode: account.currencyCode,
    openingBalanceMinor: MoneyColumns.minorOf(account.openingBalance),
    openingBalanceDateKey: account.openingBalanceDateKey,
    isArchived: account.isArchived,
    includeInNetWorth: account.includeInNetWorth,
    sortOrder: account.sortOrder,
    colorArgb: Value(account.colorArgb),
    iconKey: Value(account.iconKey),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `PaymentMethodRow` and the domain `PaymentMethod` entity.
extension PaymentMethodMapper on PaymentMethodRow {
  /// Maps this row to a domain entity.
  PaymentMethod toEntity() => PaymentMethod(
    id: id,
    name: name,
    kind: kind,
    isSystem: isSystem,
    sortOrder: sortOrder,
  );
}

/// Builds the companion for [method].
PaymentMethodsCompanion paymentMethodToCompanion(
  PaymentMethod method, {
  required int createdAt,
  required int updatedAt,
}) {
  return PaymentMethodsCompanion.insert(
    id: method.id,
    name: method.name,
    kind: method.kind,
    isSystem: method.isSystem,
    sortOrder: method.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `PayeeRow` and the domain `Payee` entity.
extension PayeeMapper on PayeeRow {
  /// Maps this row to a domain entity.
  Payee toEntity() => Payee(
    id: id,
    name: name,
    normalizedName: normalizedName,
    kind: kind,
    phone: phone,
    note: note,
  );
}

/// Builds the companion for [payee].
PayeesCompanion payeeToCompanion(
  Payee payee, {
  required int createdAt,
  required int updatedAt,
}) {
  return PayeesCompanion.insert(
    id: payee.id,
    name: payee.name,
    normalizedName: payee.normalizedName,
    kind: payee.kind,
    phone: Value(payee.phone),
    note: Value(payee.note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts `ActiveTransactionRow` (from `v_active_transactions`, what every read method on
/// `TransactionDao` returns) into the domain `Transaction` entity.
///
/// Not `TransactionRow` — no read path in `TransactionDao` ever returns one; every method reads
/// the view, per Law L7. The view aliases the primary key as `tx_id` (so `Transaction` and
/// `TransactionLine` share the unqualified name `id` in a join), which is why this reads
/// [ActiveTransactionRow.txId] rather than `.id`.
///
/// The view originally omitted `conversionRate`, `conversionRateRaw`, `conversionDateKey`,
/// `createdAt` and `updatedAt` — only enough columns to render a list, not enough to fully
/// reconstruct a row. The first three would have silently dropped the rate and date behind
/// every frozen conversion; the last two are why `TransactionRepositoryImpl.update` could not
/// preserve a transaction's true creation time on edit. Fixed by adding all five to
/// `transaction_views.drift` in this phase; see the phase report. `createdAt`/`updatedAt` are
/// read directly off [ActiveTransactionRow] by the repository for that bookkeeping — [toEntity]
/// itself still ignores them, since `Transaction` carries no persistence timestamps.
extension ActiveTransactionMapper on ActiveTransactionRow {
  /// Maps this row to a domain entity.
  Transaction toEntity() {
    final hasFreeze = convertedAmountMinor != null;
    return Transaction(
      id: txId,
      kind: kind,
      subtype: subtype,
      occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
        occurredAt,
        isUtc: true,
      ),
      dateKey: dateKey,
      originalAmount: MoneyColumns.read(
        originalAmountMinor,
        originalCurrencyCode,
      ),
      needsReview: needsReview,
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      paymentMethodId: paymentMethodId,
      payeeId: payeeId,
      note: note,
      recurringTemplateId: recurringTemplateId,
      recurringOccurrenceId: recurringOccurrenceId,
      frozenConversion: hasFreeze
          ? MoneyColumns.read(convertedAmountMinor!, convertedCurrencyCode!)
          : null,
      frozenConversionRate: hasFreeze ? conversionRate : null,
      frozenConversionRateRaw: hasFreeze ? conversionRateRaw : null,
      frozenConversionDateKey: hasFreeze ? conversionDateKey : null,
    );
  }
}

/// Builds the companion for [transaction].
///
/// [monthKey] is a required parameter here, not derived inside this function — deriving it in a
/// mapper that only ever runs after the repository has already validated and computed it would
/// invite a second, possibly-inconsistent derivation. `TransactionRepositoryImpl.create` and
/// `.update` are the one place `monthKey` is computed, from `dateKey.monthKey`.
TransactionsCompanion transactionToCompanion(
  Transaction transaction, {
  required int monthKey,
  required int createdAt,
  required int updatedAt,
}) {
  return TransactionsCompanion.insert(
    id: transaction.id,
    kind: transaction.kind,
    subtype: transaction.subtype,
    occurredAt: transaction.occurredAtUtc.millisecondsSinceEpoch,
    dateKey: transaction.dateKey,
    monthKey: monthKey,
    originalAmountMinor: MoneyColumns.minorOf(transaction.originalAmount),
    originalCurrencyCode: MoneyColumns.codeOf(transaction.originalAmount),
    fromAccountId: Value(transaction.fromAccountId),
    toAccountId: Value(transaction.toAccountId),
    paymentMethodId: Value(transaction.paymentMethodId),
    payeeId: Value(transaction.payeeId),
    note: Value(transaction.note),
    needsReview: transaction.needsReview,
    recurringTemplateId: Value(transaction.recurringTemplateId),
    recurringOccurrenceId: Value(transaction.recurringOccurrenceId),
    convertedAmountMinor: Value(
      MoneyColumns.minorOfNullable(transaction.frozenConversion),
    ),
    convertedCurrencyCode: Value(
      MoneyColumns.codeOfNullable(transaction.frozenConversion),
    ),
    conversionRate: Value(transaction.frozenConversionRate),
    conversionRateRaw: Value(transaction.frozenConversionRateRaw),
    conversionDateKey: Value(transaction.frozenConversionDateKey),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `TransactionLineRow` and the domain `TransactionLine` entity.
///
/// `transaction_lines` carries no currency column of its own (ARCH_2 §4.2) — every amount on a
/// line is implicitly in its parent transaction's currency. [toEntity] therefore requires
/// [transactionCurrencyCode] explicitly; there is no way to construct a correct
/// [TransactionLine.unitPrice] or [TransactionLine.lineAmount] from this row alone.
///
/// [categoryResolver] supplies the [UnitCategory] a `quantity` needs but this row does not carry
/// directly — looking up [TransactionLineRow.itemId]'s category, or [TransactionLineRow.unitCode]'s
/// when there is no item, exactly as `qty_converter.dart`'s class doc describes. Returns null from
/// the resolver when neither is available, in which case the mapped line's `quantity` is null too.
extension TransactionLineMapper on TransactionLineRow {
  /// Maps this row to a domain entity.
  TransactionLine toEntity({
    required String transactionCurrencyCode,
    required UnitCategory? Function(TransactionLineRow row) categoryResolver,
  }) {
    final category = categoryResolver(this);
    return TransactionLine(
      id: id,
      transactionId: transactionId,
      lineNo: lineNo,
      description: description,
      destination: destination,
      itemId: itemId,
      quantity: QtyColumns.readOrNull(quantityMilli, category),
      unitCode: unitCode,
      // `readNullable` enforces a pairing invariant — both null or both present — and throws on a
      // half-populated pair. It is right only where the currency is a nullable column written and
      // cleared with its own amount. Here the currency is always present, so a null amount is a
      // legitimate absence rather than a broken pair, and the nullability belongs to the amount.
      //
      // `transactionCurrencyCode` is a `required String` from the parent transaction, so every line
      // without a unit price — which is every line a shopping list produces — threw, and the detail
      // screen showed "that did not work" instead of the items.
      unitPrice: unitPriceMinor == null
          ? null
          : Money(unitPriceMinor!, transactionCurrencyCode),
      lineAmount: lineAmountMinor == null
          ? null
          : Money(lineAmountMinor!, transactionCurrencyCode),
      createdBatchId: createdBatchId,
      createdAssetId: createdAssetId,
      createdRecurringTemplateId: createdRecurringTemplateId,
      note: note,
    );
  }
}

/// Builds the companion for [line].
TransactionLinesCompanion transactionLineToCompanion(
  TransactionLine line, {
  required int createdAt,
  required int updatedAt,
}) {
  return TransactionLinesCompanion.insert(
    id: line.id,
    transactionId: line.transactionId,
    lineNo: line.lineNo,
    description: line.description,
    destination: line.destination,
    itemId: Value(line.itemId),
    quantityMilli: Value(QtyColumns.milliOfNullable(line.quantity)),
    unitCode: Value(line.unitCode),
    unitPriceMinor: Value(MoneyColumns.minorOfNullable(line.unitPrice)),
    lineAmountMinor: Value(MoneyColumns.minorOfNullable(line.lineAmount)),
    createdBatchId: Value(line.createdBatchId),
    createdAssetId: Value(line.createdAssetId),
    createdRecurringTemplateId: Value(line.createdRecurringTemplateId),
    note: Value(line.note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
