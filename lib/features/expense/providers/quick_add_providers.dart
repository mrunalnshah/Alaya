/// View-model state for the quick-add sheet (ARCH_5 U19).
library;

import 'package:alaya/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction.dart';

/// What the quick-add sheet is holding.
class QuickAddState {
  /// Creates the sheet's state.
  const QuickAddState({
    this.kind = TransactionKind.withdrawal,
    this.amount,
    this.accountId,
    this.tagId,
    this.submitting = false,
    this.amountMissing = false,
    this.shakeTrigger = 0,
  });

  /// Money out by default: an expense tracker is opened to record spending far more often than
  /// income, and defaulting to the rarer case costs a tap every single time.
  final TransactionKind kind;

  /// The typed amount, null while it does not parse. The one required field (Law U11).
  final Money? amount;

  /// The chosen account. Null lets the repository fill it from last-used, then the default.
  final String? accountId;

  /// An optional tag.
  final String? tagId;

  /// Whether a save is in flight.
  final bool submitting;

  /// Whether submit was pressed with no parseable amount.
  final bool amountMissing;

  /// Incremented to shake the amount field. An int rather than a bool so two consecutive rejections
  /// shake twice — a bool already true produces no change and reads as the app ignoring the tap.
  final int shakeTrigger;

  /// Whether the sheet holds anything worth confirming before a dismissal.
  bool get isDirty => amount != null || tagId != null;

  /// Returns a copy with the supplied changes.
  QuickAddState copyWith({
    TransactionKind? kind,
    Money? amount,
    bool clearAmount = false,
    String? accountId,
    String? tagId,
    bool clearTag = false,
    bool? submitting,
    bool? amountMissing,
    int? shakeTrigger,
  }) => QuickAddState(
    kind: kind ?? this.kind,
    amount: clearAmount ? null : (amount ?? this.amount),
    accountId: accountId ?? this.accountId,
    tagId: clearTag ? null : (tagId ?? this.tagId),
    submitting: submitting ?? this.submitting,
    amountMissing: amountMissing ?? this.amountMissing,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
  );
}

/// The quick-add sheet's view model.
final quickAddProvider =
    NotifierProvider.autoDispose<QuickAddNotifier, QuickAddState>(
      QuickAddNotifier.new,
    );

/// Captures an amount and as little else as the user is willing to give (Law U11).
class QuickAddNotifier extends AutoDisposeNotifier<QuickAddState> {
  @override
  QuickAddState build() => const QuickAddState();

  /// Switches between money in and money out.
  void setKind(TransactionKind kind) => state = state.copyWith(kind: kind);

  /// Records the parsed amount, clearing any outstanding "enter an amount" message.
  void setAmount(Money? amount) => state = amount == null
      ? state.copyWith(clearAmount: true)
      : state.copyWith(amount: amount, amountMissing: false);

  /// Chooses the account the money moves through.
  void setAccount(String accountId) =>
      state = state.copyWith(accountId: accountId);

  /// Applies or removes the optional tag.
  void toggleTag(String tagId) => state = state.tagId == tagId
      ? state.copyWith(clearTag: true)
      : state.copyWith(tagId: tagId);

  /// Saves, returning the created transaction, or null when the form was rejected.
  ///
  /// Marks the row `needsReview` so the nudge can offer it back later: capturing an amount and
  /// nothing else is the point of this sheet, and the flag is what stops that shortcut becoming
  /// silent data rot (ARCH_5 §7.2).
  Future<Transaction?> submit() async {
    final amount = state.amount;
    if (amount == null) {
      state = state.copyWith(
        amountMissing: true,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return null;
    }
    state = state.copyWith(submitting: true);

    final clock = ref.read(clockProvider);
    final isDeposit = state.kind == TransactionKind.deposit;
    final transaction = Transaction(
      id: ref.read(uidGeneratorProvider).generate(),
      kind: state.kind,
      subtype: isDeposit
          ? TransactionSubtype.otherIn
          : TransactionSubtype.otherOut,
      occurredAtUtc: clock.now().toUtc(),
      dateKey: clock.today(),
      originalAmount: amount,
      needsReview: true,
      fromAccountId: isDeposit ? null : state.accountId,
      toAccountId: isDeposit ? state.accountId : null,
    );

    final tagId = state.tagId;
    final result = await ref
        .read(transactionRepositoryProvider)
        .create(
          transaction: transaction,
          tagIds: [if (tagId != null) tagId],
        );
    state = state.copyWith(submitting: false);
    return result.valueOrNull;
  }

  /// Removes a transaction this sheet created, for the snack bar's Undo.
  Future<void> undo(String id) async {
    await ref.read(transactionRepositoryProvider).delete(id: id);
  }
}

/// Tags offered in the sheet, scoped to the direction the user has chosen.
///
/// A tag scoped to withdrawals must not appear while the toggle says money in — "Kitchen" in the
/// deposit picker is the spec's own test case for the scoping matrix (ARCH_2 §14).
final quickAddTagsProvider = StreamProvider.autoDispose<List<Tag>>((ref) {
  final kind = ref.watch(quickAddProvider.select((s) => s.kind));
  final scope = kind == TransactionKind.deposit
      ? TagScope.deposit
      : TagScope.withdrawal;
  return ref.watch(tagRepositoryProvider).watchByScope(scope);
});
