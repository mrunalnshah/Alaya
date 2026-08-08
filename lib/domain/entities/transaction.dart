import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// One movement of money — the first of the app's three append-only truths (ARCH_1 §3.3).
///
/// A `transfer` is **one** transaction, not a pair. The ledger expands it into two signed legs,
/// which is why a self-transfer nets to zero by construction (anomaly A02) — and why
/// [signedAmount] is zero for one, while [signedAmountFor] gives each account its own side.
class Transaction {
  /// Creates a transaction.
  const Transaction({
    required this.id,
    required this.kind,
    required this.subtype,
    required this.occurredAtUtc,
    required this.dateKey,
    required this.originalAmount,
    required this.needsReview,
    this.fromAccountId,
    this.toAccountId,
    this.paymentMethodId,
    this.payeeId,
    this.note,
    this.recurringTemplateId,
    this.recurringOccurrenceId,
    this.frozenConversion,
    this.frozenConversionRate,
    this.frozenConversionRateRaw,
    this.frozenConversionDateKey,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Which direction money moved.
  final TransactionKind kind;

  /// The structural flow subtype, which decides the editor form and the analytics bucket.
  final TransactionSubtype subtype;

  /// When it happened. Always UTC; the civil date is [dateKey], which is the timezone-independent
  /// one (Law L4).
  final DateTime occurredAtUtc;

  /// The local civil date it happened on.
  final DateKey dateKey;

  /// The amount as stored, always positive — the sign comes from [kind] (Law L1). Immutable
  /// once saved, together with its currency (Law L9).
  final Money originalAmount;

  /// Set by quick-add when only an amount was supplied; drives the "add details" nudge.
  final bool needsReview;

  /// Source account for withdrawals, decreases and transfers.
  final String? fromAccountId;

  /// Destination account for deposits, increases and transfers.
  final String? toAccountId;

  /// The rail money travelled on.
  final String? paymentMethodId;

  /// The counterparty.
  final String? payeeId;

  /// Optional free-text note. Indexed for full-text search.
  final String? note;

  /// The recurring template this settled, if any.
  final String? recurringTemplateId;

  /// The specific occurrence this settled, if any.
  final String? recurringOccurrenceId;

  /// A frozen converted amount, written only by the explicit per-transaction freeze action and
  /// never recomputed (Law L9).
  final Money? frozenConversion;

  /// The rate used at freeze time.
  final double? frozenConversionRate;

  /// The exact rate string the API returned, so a questioned figure can be reproduced.
  final String? frozenConversionRateRaw;

  /// The civil date the frozen rate was quoted for.
  final DateKey? frozenConversionDateKey;

  /// `yyyymm`, derived from [dateKey] rather than stored on this entity.
  ///
  /// The database keeps a denormalised `month_key` column so monthly analytics never computes it
  /// per row, and a CHECK constraint keeps the two consistent — but a domain entity that stored it
  /// too would just be a third copy able to disagree with both.
  int get monthKey => dateKey.monthKey;

  /// This transaction's effect on **total net worth**.
  ///
  /// Positive for a deposit or increase, negative for a withdrawal or decrease, and exactly
  /// **zero for a transfer** — moving money between your own accounts does not change how much you
  /// have (anomaly A02). For one account's side of a transfer, use [signedAmountFor].
  Money get signedAmount => switch (kind) {
    TransactionKind.deposit || TransactionKind.adjustmentIncrease => originalAmount,
    TransactionKind.withdrawal || TransactionKind.adjustmentDecrease => -originalAmount,
    TransactionKind.transfer => Money.zero(originalAmount.currencyCode),
  };

  /// This transaction's effect on [accountId]'s balance, or zero if it does not touch it.
  ///
  /// Mirrors `v_account_ledger`: a transfer contributes `-amount` to the source and `+amount` to
  /// the destination, so summing this across a transfer's two accounts gives zero.
  Money signedAmountFor(String accountId) {
    final zero = Money.zero(originalAmount.currencyCode);
    if (kind == TransactionKind.transfer) {
      if (accountId == fromAccountId) return -originalAmount;
      if (accountId == toAccountId) return originalAmount;
      return zero;
    }
    if (accountId == toAccountId) return originalAmount;
    if (accountId == fromAccountId) return -originalAmount;
    return zero;
  }

  /// True when this moves money between two of the user's own accounts.
  bool get isTransfer => kind == TransactionKind.transfer;

  /// True when this increases an account's balance.
  bool get isInflow =>
      kind == TransactionKind.deposit || kind == TransactionKind.adjustmentIncrease;

  /// True when this decreases an account's balance.
  bool get isOutflow =>
      kind == TransactionKind.withdrawal || kind == TransactionKind.adjustmentDecrease;

  /// True when this is a manual reconciliation rather than a real-world movement.
  bool get isAdjustment =>
      kind == TransactionKind.adjustmentIncrease || kind == TransactionKind.adjustmentDecrease;

  /// True when this settled a recurring obligation, the discriminator for the
  /// recurring-versus-discretionary split (ARCH_3 §5.1 query 18).
  bool get isRecurring => recurringTemplateId != null;

  /// True when an explicit conversion snapshot has been frozen against this transaction.
  bool get hasFrozenConversion => frozenConversion != null;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  Transaction copyWith({
    String? id,
    TransactionKind? kind,
    TransactionSubtype? subtype,
    DateTime? occurredAtUtc,
    DateKey? dateKey,
    Money? originalAmount,
    bool? needsReview,
    String? fromAccountId,
    String? toAccountId,
    String? paymentMethodId,
    String? payeeId,
    String? note,
    String? recurringTemplateId,
    String? recurringOccurrenceId,
    Money? frozenConversion,
    double? frozenConversionRate,
    String? frozenConversionRateRaw,
    DateKey? frozenConversionDateKey,
  }) {
    return Transaction(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      subtype: subtype ?? this.subtype,
      occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
      dateKey: dateKey ?? this.dateKey,
      originalAmount: originalAmount ?? this.originalAmount,
      needsReview: needsReview ?? this.needsReview,
      fromAccountId: fromAccountId ?? this.fromAccountId,
      toAccountId: toAccountId ?? this.toAccountId,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      payeeId: payeeId ?? this.payeeId,
      note: note ?? this.note,
      recurringTemplateId: recurringTemplateId ?? this.recurringTemplateId,
      recurringOccurrenceId: recurringOccurrenceId ?? this.recurringOccurrenceId,
      frozenConversion: frozenConversion ?? this.frozenConversion,
      frozenConversionRate: frozenConversionRate ?? this.frozenConversionRate,
      frozenConversionRateRaw: frozenConversionRateRaw ?? this.frozenConversionRateRaw,
      frozenConversionDateKey: frozenConversionDateKey ?? this.frozenConversionDateKey,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Transaction &&
          other.id == id &&
          other.kind == kind &&
          other.subtype == subtype &&
          other.occurredAtUtc == occurredAtUtc &&
          other.dateKey == dateKey &&
          other.originalAmount == originalAmount &&
          other.needsReview == needsReview &&
          other.fromAccountId == fromAccountId &&
          other.toAccountId == toAccountId &&
          other.paymentMethodId == paymentMethodId &&
          other.payeeId == payeeId &&
          other.note == note &&
          other.recurringTemplateId == recurringTemplateId &&
          other.recurringOccurrenceId == recurringOccurrenceId &&
          other.frozenConversion == frozenConversion &&
          other.frozenConversionRate == frozenConversionRate &&
          other.frozenConversionRateRaw == frozenConversionRateRaw &&
          other.frozenConversionDateKey == frozenConversionDateKey;

  @override
  int get hashCode => Object.hashAll([
    id, kind, subtype, occurredAtUtc, dateKey, originalAmount, needsReview,
    fromAccountId, toAccountId, paymentMethodId, payeeId, note,
    recurringTemplateId, recurringOccurrenceId, frozenConversion,
    frozenConversionRate, frozenConversionRateRaw, frozenConversionDateKey,
  ]);

  @override
  String toString() => 'Transaction($id, ${kind.name}, $originalAmount)';
}
