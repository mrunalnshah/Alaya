import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';

/// One transaction's totals against the lines that itemise it.
///
/// [unallocated] is the difference the UI surfaces as an "unallocated ₹20" chip. Check [lineCount]
/// before showing it: with no lines at all the unallocated figure equals the whole amount, which is
/// not the same thing as a mismatch (anomaly A11).
class TransactionAllocation {
  /// Creates an allocation summary.
  const TransactionAllocation({
    required this.transactionId,
    required this.amount,
    required this.allocated,
    required this.unallocated,
    required this.lineCount,
  });

  /// The transaction this summarises.
  final String transactionId;

  /// The transaction's own amount — the source of truth.
  final Money amount;

  /// The sum of its lines.
  final Money allocated;

  /// [amount] less [allocated].
  final Money unallocated;

  /// How many lines exist.
  final int lineCount;

  /// True when lines exist and do not sum to the transaction amount.
  bool get hasMismatch => lineCount > 0 && !unallocated.isZero;
}

/// What a delete detached rather than removed, so the UI can offer a follow-up.
///
/// Deleting a transaction never cascades to the batches or assets its lines created — you deleted a
/// receipt, not the groceries (anomaly A10). These ids are what was cut loose.
class DetachedArtefacts {
  /// Creates a detachment report.
  const DetachedArtefacts({
    required this.batchIds,
    required this.assetIds,
    required this.recurringTemplateIds,
    required this.untouchedBatchIds,
  });

  /// Batches whose source link was cleared.
  final List<String> batchIds;

  /// Assets whose source link was cleared.
  final List<String> assetIds;

  /// Recurring templates whose source link was cleared.
  final List<String> recurringTemplateIds;

  /// Batches that are provably untouched — nothing consumed, remaining still equals initial.
  ///
  /// Only for these may the UI offer "also remove the 4 items this added". A batch already drawn
  /// down must never be offered for removal, because the food really was eaten (anomaly A10).
  final List<String> untouchedBatchIds;

  /// True when nothing was detached.
  bool get isEmpty =>
      batchIds.isEmpty && assetIds.isEmpty && recurringTemplateIds.isEmpty;
}

/// Reads and writes transactions and the lines that itemise them.
abstract interface class TransactionRepository {
  /// Reads one transaction by id.
  Future<Transaction?> byId(String id);

  /// Emits transactions whose civil date falls in `[from, to]`, newest first. Inclusive both ends.
  Stream<List<Transaction>> watchByDateRange({
    required DateKey from,
    required DateKey to,
  });

  /// Emits transactions touching [accountId] on either side, newest first.
  ///
  /// A transfer appears in both accounts' lists — once as an outflow and once as an inflow, which
  /// is what the user expects to see.
  Stream<List<Transaction>> watchByAccount(String accountId);

  /// Emits transactions of [subtype], newest first, optionally bounded by `yyyymm` month.
  Stream<List<Transaction>> watchBySubtype(
    TransactionSubtype subtype, {
    int? fromMonthKey,
    int? toMonthKey,
  });

  /// Emits transactions still flagged as needing details, for the dashboard nudge.
  Stream<List<Transaction>> watchNeedingReview();

  /// Emits how many transactions need details.
  Stream<int> watchNeedsReviewCount();

  /// Full-text search over notes, best match first.
  Future<List<Transaction>> search(String query, {int limit});

  /// Emits the lines of [transactionId], in entry order.
  Stream<List<TransactionLine>> watchLines(String transactionId);

  /// Emits [transactionId]'s allocation summary.
  Stream<TransactionAllocation?> watchAllocation(String transactionId);

  /// Emits the lines referencing [itemId], newest first — an item's purchase history, and the basis
  /// of the unit-price trend (ARCH_3 §5.1 queries 12 and 24).
  Stream<List<TransactionLine>> watchLinesForItem(String itemId);

  /// Creates a transaction with its lines and tags, atomically.
  ///
  /// Validates the shape [Transaction.kind] requires before writing — a deposit needs a destination
  /// and no source, a transfer needs two different accounts — and returns a [ValidationFailure]
  /// rather than letting the user hit a raw SQLite constraint error (ARCH_2 §4.1).
  ///
  /// Fills the account from last-used, then the default, so it is never null even though the UI
  /// treats it as optional (ARCH_2 §4.1). Derives `monthKey` from the date rather than trusting a
  /// caller — the DAO deliberately does not, so this layer must.
  Future<Result<Transaction, Failure>> create({
    required Transaction transaction,
    List<TransactionLine> lines,
    List<String> tagIds,
  });

  /// Updates a transaction's own fields.
  Future<Result<Transaction, Failure>> update(Transaction transaction);

  /// Replaces the lines of [transactionId].
  /// Records which artefact one line produced, after the fan-out service created it.
  ///
  /// **Not `replaceLines`.** `replaceLines` soft-deletes the existing rows and inserts new ones, so
  /// calling it with the same line ids violates the primary key — the soft-deleted row is still
  /// physically there. Writing an artefact id back onto a line that already exists is an update of
  /// one column, and this is the method for it.
  ///
  /// Exactly one of the three ids is set for a given line, matching its `destination`
  /// (ARCH_2 §4.2); the others are left untouched.
  Future<Result<void, Failure>> recordCreatedArtefact({
    required String lineId,
    String? createdBatchId,
    String? createdAssetId,
    String? createdRecurringTemplateId,
  });

  /// Replaces every line on a transaction.
  ///
  /// The supplied lines must carry **fresh ids**: the existing rows are soft-deleted rather than
  /// removed (Law L6), so reusing an id collides with the row that is still there.
  Future<Result<void, Failure>> replaceLines({
    required String transactionId,
    required List<TransactionLine> lines,
  });

  /// Clears the needs-review flag once the user has filled in the details.
  Future<Result<void, Failure>> markReviewed(String id);

  /// Freezes a converted snapshot against [id].
  ///
  /// Cannot touch the original amount or its currency — those are immutable once saved (Law L9),
  /// and the signature has no parameter for them.
  Future<Result<void, Failure>> freezeConversion({
    required String id,
    required DateKey on,
    required String toCurrencyCode,
  });

  /// Deletes a transaction and its lines, reporting what it detached.
  ///
  /// Never cascades to created batches or assets. The returned [DetachedArtefacts] is what lets the
  /// UI offer to remove an untouched batch as a *separate, explicit* action.
  Future<Result<DetachedArtefacts, Failure>> delete({
    required String id,
    String? reason,
  });
}
