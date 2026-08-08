import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `payees` — the counterparty, used for both `From` on deposits and `To` on
/// withdrawals (ARCH_1 §3.1).
class PayeeDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  PayeeDao(super.db);

  $PayeesTable get _table => attachedDatabase.payees;

  SimpleSelectStatement<$PayeesTable, PayeeRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits every active payee, alphabetically.
  Stream<List<PayeeRow>> watchAll() =>
      (_activeRows()..orderBy([(t) => OrderingTerm(expression: t.normalizedName)])).watch();

  /// Reads one payee by id, including a soft-deleted one.
  Future<PayeeRow?> byIdIncludingDeleted(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads one active payee by normalized name, for the merge-or-create decision.
  ///
  /// `idx_payees_name` is a partial unique index on this column, so at most one active row can
  /// match — which is why this returns a single row rather than a list.
  Future<PayeeRow?> byNormalizedName(String normalizedName) =>
      (_activeRows()..where((t) => t.normalizedName.equals(normalizedName))).getSingleOrNull();

  /// Emits active payees whose normalized name contains [term], for the picker's search field.
  Stream<List<PayeeRow>> watchMatching(String term) {
    final needle = '%${term.toLowerCase()}%';
    return (_activeRows()
      ..where((t) => t.normalizedName.like(needle))
      ..orderBy([(t) => OrderingTerm(expression: t.normalizedName)])
      ..limit(50))
        .watch();
  }

  /// Inserts or updates a payee.
  Future<void> upsert(PayeesCompanion payee) => into(_table).insertOnConflictUpdate(payee);

  /// Soft-deletes a payee.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      PayeesCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Counts active transactions naming [payeeId], for the "in use" check.
  Future<int> activeTransactionCount(String payeeId) async {
    final transactions = attachedDatabase.transactions;
    final count = countAll();
    final row = await (selectOnly(transactions)
      ..addColumns([count])
      ..where(transactions.payeeId.equals(payeeId) & transactions.deletedAt.isNull()))
        .getSingle();
    return row.read(count) ?? 0;
  }
}