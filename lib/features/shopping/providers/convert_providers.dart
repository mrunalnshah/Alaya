/// View-model state for convert-to-purchase (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/providers/transaction_draft_provider.dart';
import 'package:alaya/features/expense/state/transaction_draft.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';

/// The draft lines a list's ticked entries would produce.
final purchaseDraftProvider = FutureProvider.autoDispose
    .family<List<TransactionLine>, String>((ref, listId) async {
      // Watched, not read: ticking a row on the list behind this screen should change what it offers.
      ref.watch(entriesProvider(listId));
      final result = await ref
          .watch(shoppingRepositoryProvider)
          .buildPurchaseDraft(listId);
      return result.valueOrNull ?? const <TransactionLine>[];
    });

/// Builds the handoff to the expense editor.
final convertActionsProvider = Provider<ConvertActions>(ConvertActions.new);

/// Turns a finished list into a draft the expense editor can open.
class ConvertActions {
  /// Creates the actions.
  ConvertActions(this._ref);

  final Ref _ref;

  /// Offers the draft to the next editor, returning false when there is nothing to convert.
  ///
  /// **This writes no transaction.** `buildPurchaseDraft` returns lines precisely so the amount, the
  /// account and the payee stay decisions the expense editor collects — reimplementing that here
  /// would fork the one screen in the app that knows how a withdrawal is shaped (anomaly A25).
  bool offerDraft({
    required String listId,
    required List<TransactionLine> lines,
  }) {
    if (lines.isEmpty) return false;
    final entries = _ref.read(entriesProvider(listId)).valueOrNull ?? const [];
    _ref
        .read(transactionDraftProvider.notifier)
        .offer(
          TransactionDraft(
            lines: lines,
            kind: TransactionKind.withdrawal,
            subtype: TransactionSubtype.grocery,
            sourceListId: listId,
            sourceEntryIds: [
              for (final entry in entries)
                if (entry.isChecked && !entry.isPurchased) entry.id,
            ],
          ),
        );
    return true;
  }
}
