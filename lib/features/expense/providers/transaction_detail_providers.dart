/// View-model providers for one transaction's detail screen (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';

/// One transaction, re-read whenever it changes.
///
/// A `StreamProvider` over the date-range watch would be the wrong shape here — the detail screen
/// wants one row, and `byId` is a future. It is invalidated explicitly after a write instead.
final transactionByIdProvider = FutureProvider.autoDispose
    .family<Transaction?, String>(
      (ref, id) => ref.watch(transactionRepositoryProvider).byId(id),
    );

/// The lines itemising one transaction, in entry order.
final transactionLinesProvider = StreamProvider.autoDispose
    .family<List<TransactionLine>, String>(
      (ref, id) => ref.watch(transactionRepositoryProvider).watchLines(id),
    );

/// One transaction's allocation summary, for the unallocated chip.
final transactionAllocationProvider = StreamProvider.autoDispose
    .family<TransactionAllocation?, String>(
      (ref, id) => ref.watch(transactionRepositoryProvider).watchAllocation(id),
    );

/// The tags applied to one transaction.
final transactionTagsProvider = StreamProvider.autoDispose
    .family<List<Tag>, String>(
      (ref, id) => ref.watch(tagRepositoryProvider).watchForTransaction(id),
    );

/// Payment methods by id, so a detail row can name one without a query per row.
final paymentMethodsByIdProvider = StreamProvider<Map<String, PaymentMethod>>(
  (ref) => ref
      .watch(paymentMethodRepositoryProvider)
      .watchAll()
      .map((rows) => {for (final row in rows) row.id: row}),
);

/// The currencies a conversion may be frozen into.
final enabledCurrenciesProvider = StreamProvider<List<Currency>>(
  (ref) => ref.watch(currencyRepositoryProvider).watchEnabled(),
);

/// Writes for the detail screen, so the widget holds no repository call of its own.
final transactionActionsProvider = Provider<TransactionActions>(
  (ref) => TransactionActions(ref),
);

/// Delete, undo and freeze, with the invalidations each one implies.
class TransactionActions {
  /// Creates the action set.
  const TransactionActions(this._ref);

  final Ref _ref;

  /// Deletes [id], optionally recording [reason], and reports what it detached.
  ///
  /// Never cascades to the batches or assets the transaction's lines created — you deleted a
  /// receipt, not the groceries (anomaly A10). The returned report is what lets the screen offer to
  /// remove a provably untouched batch as a separate, explicit action.
  Future<DetachedArtefacts?> delete(String id, {String? reason}) async {
    final result = await _ref
        .read(transactionRepositoryProvider)
        .delete(id: id, reason: reason);
    _ref.invalidate(transactionByIdProvider(id));
    return result.valueOrNull;
  }

  // There is deliberately no undoDelete here, and it is a contract gap rather than an omission.
  //
  // `TransactionRepository` exposes exactly one deletion method and no `restore`. `update()` cannot
  // stand in for one: it reads `TransactionDao.byId` first, that DAO selects from
  // `v_active_transactions`, and the view filters `deleted_at IS NULL` — so a deleted row is
  // invisible to it and `update()` returns `NotFoundFailure`. An Undo wired to `update()` would
  // fail silently, which is the worst outcome Law U9 exists to prevent.
  //
  // Until `restore(String id)` is added to the 3A contract, deletion is treated as the
  // non-reversible tier of ARCH_5 §5.5: a sheet that names the consequence, not a snack with Undo.

  /// Freezes a converted snapshot of [id] into [toCurrencyCode], on the transaction's own date.
  ///
  /// A separate, frozen artefact that is never recomputed. It cannot touch the original amount or
  /// its currency — those are immutable once saved (Law L9) and the signature has no parameter for
  /// them.
  Future<bool> freezeConversion({
    required Transaction transaction,
    required String toCurrencyCode,
  }) async {
    final result = await _ref
        .read(transactionRepositoryProvider)
        .freezeConversion(
          id: transaction.id,
          on: transaction.dateKey,
          toCurrencyCode: toCurrencyCode,
        );
    _ref.invalidate(transactionByIdProvider(transaction.id));
    return result.isOk;
  }
}
