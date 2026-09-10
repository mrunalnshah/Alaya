/// Acting on a split that already exists (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/features/split/providers/split_history_provider.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// Deleting a recorded split.
final splitExpenseActionsProvider =
    NotifierProvider<SplitExpenseActions, AsyncValue<void>>(
      SplitExpenseActions.new,
    );

/// Removes a split, leaving the money alone.
class SplitExpenseActions extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Deletes [id] and its shares.
  ///
  /// **Any linked transaction stays.** The money did move; deleting the split is a statement about who owed
  /// what, not about whether the payment happened. Removing the transaction too would take a real
  /// withdrawal out of the account ledger because a debt was reconsidered.
  Future<bool> remove(String id) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(splitExpenseServiceProvider).remove(id);
    final failure = result.failureOrNull;
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    // Balances derive from the shares that just went; the history feed unions the expenses table. Both are
    // streams over views, and invalidating is what makes the screens behind this sheet agree with it.
    ref
      ..invalidate(splitBalancesProvider)
      ..invalidate(splitHistoryProvider);
    state = const AsyncData(null);
    return true;
  }

  /// The message from the last failure, or null.
  String? get lastError {
    final error = state.error;
    return error is Failure ? error.message : null;
  }
}
