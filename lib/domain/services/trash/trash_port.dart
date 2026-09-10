import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// Which table a trashed row came from.
///
/// **Not a table name string.** The purge builds `DELETE FROM` from this, and a free-text table name reaching a
/// delete statement is how a typo becomes data loss — an enum cannot name a table that does not exist.
enum TrashKind {
  /// A deleted transaction.
  transaction,

  /// A deleted inventory item.
  item,

  /// A deleted asset.
  asset,

  /// A deleted shopping list.
  shoppingList,

  /// A deleted recurring template.
  recurringTemplate,

  /// A deleted tag.
  tag,

  /// A deleted payee.
  payee,
}

/// One row in the trash.
class TrashEntry {
  /// Creates an entry.
  const TrashEntry({
    required this.id,
    required this.kind,
    required this.label,
    required this.deletedAtUtcMillis,
    required this.purgeAfterUtcMillis,
    this.detail,
  });

  /// The row's own id, for restoring or purging it.
  final String id;

  /// Which table it belongs to.
  final TrashKind kind;

  /// What the user called it.
  final String label;

  /// A second line — an amount, a date, a quantity — already formatted by the adapter.
  final String? detail;

  /// When it was deleted.
  final int deletedAtUtcMillis;

  /// When it becomes eligible for purge (ARCH_3 §4.2: thirty days).
  final int purgeAfterUtcMillis;
}

/// The trash: what was deleted, restoring it, and the one hard delete in the codebase (ARCH_3 §4.2).
///
/// **`purge` is the only hard delete anywhere, and it exists once.** Every other deletion in Alaya sets
/// `deletedAt`. That is what makes a trash screen possible at all, and it is why this is the single place where
/// a `DELETE FROM` is written — a second one somewhere else would mean a row that could vanish without ever
/// appearing here.
abstract interface class TrashPort {
  /// How long a deleted row is kept.
  static const Duration retention = Duration(days: 30);

  /// Everything currently in the trash, most recently deleted first.
  Stream<List<TrashEntry>> watchAll();

  /// How many rows are in the trash.
  Stream<int> watchCount();

  /// Un-deletes [entry], clearing its `deletedAt`.
  ///
  /// **Restore can fail for a reason worth stating**, not only a technical one: a deleted transaction may name
  /// an account that has since been deleted too, and reviving it would leave a row pointing at nothing. The
  /// implementation reports that rather than writing it.
  Future<Result<void, Failure>> restore(TrashEntry entry);

  /// Hard-deletes [entry] and anything the schema cascades from it.
  Future<Result<void, Failure>> purge(TrashEntry entry);

  /// Hard-deletes everything in the trash.
  ///
  /// Returns how many rows went, so the screen can say what happened rather than only that it happened.
  Future<Result<int, Failure>> purgeAll();

  /// Hard-deletes only what is past [retention].
  ///
  /// Called by the daily `workmanager` job, never by a button. Thirty-day retention that nothing enforces is a
  /// promise the app does not keep — and a trash that grows forever is a backup that grows forever with it.
  Future<Result<int, Failure>> purgeExpired();
}
