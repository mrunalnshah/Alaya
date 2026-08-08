import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/transaction_line.dart';

/// Reads and writes shopping lists and their entries.
abstract interface class ShoppingRepository {
  /// Emits lists that may be chosen — active and unarchived.
  Stream<List<ShoppingList>> watchSelectableLists();

  /// Emits every list, archived included.
  Stream<List<ShoppingList>> watchAllLists();

  /// Emits the list marked default, if any.
  Stream<ShoppingList?> watchDefaultList();

  /// Reads one list by id.
  Future<ShoppingList?> listById(String id);

  /// Creates or updates a list.
  Future<Result<ShoppingList, Failure>> saveList(ShoppingList list);

  /// Marks [id] the default, clearing the flag on every other list atomically.
  Future<Result<void, Failure>> setDefaultList(String id);

  /// Archives or unarchives a list.
  Future<Result<void, Failure>> setListArchived({
    required String id,
    required bool isArchived,
  });

  /// Soft-deletes a list and its entries.
  Future<Result<void, Failure>> deleteList(String id);

  /// Emits the entries of [listId], in display order.
  Stream<List<ShoppingEntry>> watchEntries(String listId);

  /// Emits only the unticked entries of [listId].
  Stream<List<ShoppingEntry>> watchUncheckedEntries(String listId);

  /// Creates or updates an entry.
  ///
  /// Editing an auto-generated entry promotes it to manual, after which the suggestion engine never
  /// removes it (anomaly A22).
  Future<Result<ShoppingEntry, Failure>> saveEntry(ShoppingEntry entry);

  /// Ticks or unticks an entry.
  Future<Result<void, Failure>> setEntryChecked({
    required String id,
    required bool isChecked,
  });

  /// Snoozes an auto-generated suggestion until [until].
  Future<Result<void, Failure>> snoozeEntry({
    required String id,
    required DateKey until,
  });

  /// Dismisses an auto-generated suggestion.
  ///
  /// It does not return on a date — only once stock has genuinely risen above the threshold and
  /// fallen again, which the suggestion engine decides from the stock reading taken now
  /// (anomaly A23).
  Future<Result<void, Failure>> dismissEntry(String id);

  /// Reorders the entries of one list.
  Future<Result<void, Failure>> reorderEntries(List<String> orderedIds);

  /// Soft-deletes an entry.
  Future<Result<void, Failure>> deleteEntry(String id);

  /// Regenerates the auto-suggestions for [listId] from current low-stock state.
  ///
  /// Idempotent: running it repeatedly neither duplicates entries nor resurrects dismissed ones
  /// (anomalies A22, A23). Returns how many suggestions are now active.
  Future<Result<int, Failure>> regenerateLowStockSuggestions(String listId);

  /// Turns the ticked entries of [listId] into draft transaction lines, closing the loop from a
  /// finished list back to money and stock (anomaly A25).
  ///
  /// Returns drafts rather than writing anything: the user still confirms the amount and account in
  /// the expense editor, and `TransactionRepository.create` is what actually commits.
  Future<Result<List<TransactionLine>, Failure>> buildPurchaseDraft(String listId);

  /// Records that [entryIds] were fulfilled by the lines of [transactionId].
  Future<Result<void, Failure>> markPurchased({
    required List<String> entryIds,
    required String transactionId,
  });
}