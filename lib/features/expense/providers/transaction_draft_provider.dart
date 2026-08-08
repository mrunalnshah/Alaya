/// The one-shot channel a module uses to hand the expense editor a pre-filled transaction.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/features/expense/state/transaction_draft.dart';

/// A draft waiting to be picked up by the next new-transaction editor.
///
/// **Set immediately before pushing the editor, consumed by its first load, then cleared.** A
/// `go_router` `extra` cannot reach the notifier that builds the editor's state, and widening the
/// family argument to carry a `List<TransactionLine>` would break its structural equality — a list
/// compares by identity, so every rebuild would allocate a fresh provider. A single-slot channel
/// that empties on read is the smaller compromise, and `take()` makes the one-shot explicit rather
/// than leaving a stale draft to ambush the next blank editor.
final transactionDraftProvider =
    NotifierProvider<TransactionDraftNotifier, TransactionDraft?>(
      TransactionDraftNotifier.new,
    );

/// Holds at most one pending draft.
class TransactionDraftNotifier extends Notifier<TransactionDraft?> {
  @override
  TransactionDraft? build() => null;

  /// Offers a draft to the next editor that opens.
  void offer(TransactionDraft draft) => state = draft;

  /// Returns the pending draft and clears it, so it is never applied twice.
  TransactionDraft? take() {
    final draft = state;
    state = null;
    return draft;
  }
}
