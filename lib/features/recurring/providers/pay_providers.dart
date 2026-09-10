/// View-model state for the pay sheet and occurrence history (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/recurring/state/pay_state.dart';

/// Which occurrence a pay sheet is settling, and what the template says it usually costs.
typedef PayArgs = ({
  String occurrenceId,
  int defaultMinor,
  String currencyCode,
  String? accountId,
});

/// Accounts the payment may come from.
final payAccountsProvider = StreamProvider.autoDispose<List<Account>>(
  // `watchSelectable`, not a list of everything: an archived account is not somewhere a payment can
  // come from, and offering it is how a closed account acquires new transactions.
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// The home currency's decimal digits (ARCH_1 §4.1).
final payDecimalDigitsProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, code) async =>
      (await ref.watch(currencyRepositoryProvider).byCode(code))
          ?.decimalDigits ??
      2,
);

/// The pay sheet for one occurrence.
final payProvider = NotifierProvider.autoDispose
    .family<PayNotifier, PayState, PayArgs>(PayNotifier.new);

/// Holds the pending payment and commits it.
///
/// **State is synchronous.** Everything the sheet needs — the occurrence, the default, the template's
/// account — arrives in the family argument from the row that opened it, so the amount field accepts a
/// keystroke on the first frame rather than after a spinner (ARCH_5 §5.2).
class PayNotifier extends AutoDisposeFamilyNotifier<PayState, PayArgs> {
  @override
  PayState build(PayArgs arg) {
    final defaultAmount = Money(arg.defaultMinor, arg.currencyCode);
    return PayState(
      occurrenceId: arg.occurrenceId,
      defaultAmount: defaultAmount,
      // Pre-filled, so the common case — it cost what it usually costs — is one tap.
      amount: defaultAmount,
      paidOn: ref.read(clockProvider).today(),
      accountId: arg.accountId,
    );
  }

  /// Sets what is actually being paid.
  void setAmount(Money? amount) =>
      state = state.copyWith(amount: amount, clearIssue: true, dirty: true);

  /// Sets which account it came from.
  void setAccount(String? accountId) => state = state.copyWith(
    accountId: accountId,
    clearIssue: true,
    dirty: true,
  );

  /// Sets when it was paid.
  void setPaidOn(DateKey date) =>
      state = state.copyWith(paidOn: date, dirty: true);

  /// Sets the free note.
  void setNote(String note) => state = state.copyWith(note: note, dirty: true);

  /// Commits the payment, returning the id of the transaction it created.
  ///
  /// `payOccurrence` writes the transaction and settles the occurrence together; nothing here does it
  /// by hand. Returns null on rejection, with the reason on the state.
  Future<String?> commit() async {
    final amount = state.amount;
    if (amount == null || !amount.isPositive) {
      state = state.copyWith(
        issue: PayIssue.amountMissing,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return null;
    }
    final accountId = state.accountId;
    if (accountId == null) {
      state = state.copyWith(issue: PayIssue.accountMissing);
      return null;
    }

    state = state.copyWith(submitting: true, clearIssue: true);
    try {
      final result = await ref
          .read(recurringRepositoryProvider)
          .payOccurrence(
            occurrenceId: state.occurrenceId,
            amount: amount,
            paidOn: state.paidOn,
            accountId: accountId,
            paymentMethodId: state.paymentMethodId,
          );
      final failure = result.failureOrNull;
      if (failure != null) {
        state = state.copyWith(
          issue: PayIssue.rejected,
          rejection: failure.message,
        );
        return null;
      }
      return result.valueOrNull?.id;
    } on Object catch (error, stack) {
      ref
          .read(loggerProvider)
          .log(
            'Recurring payment failed',
            level: LogLevel.error,
            tag: 'recurring.pay',
            error: error,
            stackTrace: stack,
          );
      state = state.copyWith(
        issue: PayIssue.rejected,
        rejection: error.toString(),
      );
      return null;
    } finally {
      state = state.copyWith(submitting: false);
    }
  }
}

/// Writes an occurrence row performs.
final occurrenceActionsProvider = Provider<OccurrenceActions>(
  OccurrenceActions.new,
);

/// Skips and un-pays occurrences.
class OccurrenceActions {
  /// Creates the actions.
  OccurrenceActions(this._ref);

  final Ref _ref;

  /// Marks an occurrence deliberately skipped, so it stops being outstanding without inventing money.
  Future<String?> skip({required String occurrenceId, String? note}) async {
    final result = await _ref
        .read(recurringRepositoryProvider)
        .skipOccurrence(occurrenceId: occurrenceId, note: note);
    return result.failureOrNull?.message;
  }

  /// Undoes a payment: the occurrence returns to due, then the transaction it created is deleted.
  ///
  /// **That order is deliberate.** Neither half can be inside the other's transaction, so one of two
  /// partial states survives a failure between them: an occurrence due while its transaction still
  /// exists shows a visible duplicate the user can fix, whereas a transaction deleted while the
  /// occurrence still reads paid hides an obligation with nothing on screen to reveal it. Order for the
  /// visible failure (ARCH_4 R21).
  Future<String?> undoPayment({
    required String occurrenceId,
    required String transactionId,
  }) async {
    final unsettled = await _ref
        .read(recurringRepositoryProvider)
        .unsettleOccurrence(occurrenceId);
    final unsettleFailure = unsettled.failureOrNull;
    if (unsettleFailure != null) return unsettleFailure.message;

    final deleted = await _ref
        .read(transactionRepositoryProvider)
        .delete(id: transactionId);
    return deleted.failureOrNull?.message;
  }
}
