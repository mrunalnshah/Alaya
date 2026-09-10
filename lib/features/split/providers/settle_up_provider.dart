/// Recording a settlement (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// Runs a settle-up and holds why it failed.
///
/// `AsyncValue<void>` rather than a bool, so the reason survives to the sheet. *"Choose which person is
/// you"* and *"that account is in USD, not INR"* are different problems with different remedies, and
/// collapsing them into one message is what makes a sheet impossible to get past (Law U9).
final settleUpProvider = NotifierProvider<SettleUp, AsyncValue<void>>(
  SettleUp.new,
);

/// Settles a debt, in whichever direction it runs.
class SettleUp extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Records that [amount] moved between the user and [payeeId].
  ///
  /// **The direction is derived here rather than asked for.** `SettlementService.settle` takes a
  /// `from` and a `to`, and a sheet that made the caller assemble those would let a screen record a
  /// payment in the wrong direction — which is the one mistake in this module that produces a
  /// plausible-looking wrong balance rather than an error. `theyOweMe` is the only question a user can
  /// answer, and the balance row already knows it.
  ///
  /// [note] is what the ledger row will say, composed by the sheet.
  ///
  /// **Passed through rather than built here, and that is a layering point rather than a convenience.** A note
  /// is a sentence, a sentence needs the ARB, and `AlayaStrings.of(context)` needs a `BuildContext` no notifier
  /// has. `SettlementService` cannot build one either — it holds payee *ids* and a group repository, not names.
  /// So the feature decides the words and the domain records them.
  Future<bool> settle({
    required String payeeId,
    required bool theyOweMe,
    required Money amount,
    required String accountId,
    String? groupId,
    String? paymentMethodId,
    String? note,
    DateKey? on,
  }) async {
    final self = await ref.read(splitSelfProvider.future);
    if (self == null) {
      state = AsyncError<void>(
        const BusinessRuleFailure(
          'Choose which person is you before settling up.',
          rule: 'splitSelfPayeeUnset',
        ),
        StackTrace.current,
      );
      return false;
    }

    state = const AsyncLoading<void>();
    final result = await ref
        .read(settlementServiceProvider)
        .settle(
          fromPayeeId: theyOweMe ? payeeId : self,
          toPayeeId: theyOweMe ? self : payeeId,
          amount: amount,
          accountId: accountId,
          groupId: groupId,
          paymentMethodId: paymentMethodId,
          note: note,
          on: on,
        );

    final failure = result.failureOrNull;
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData(null);
    // The balance views recompute from the new rows on their own — nothing here invalidates a
    // provider, because Law L3 means there is no cached total to invalidate. That is the whole point
    // of deriving balances rather than storing them.
    return true;
  }

  /// The message from the last failure, or null.
  ///
  /// Typed, not cast: an `as dynamic` to reach `message` would compile against anything and fail at
  /// runtime the first time a non-`Failure` landed in the error slot.
  String? get lastError {
    final error = state.error;
    return error is Failure ? error.message : null;
  }
}
