import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `payment_methods` — the rail money travelled on, which never holds a balance
/// (ARCH_1 §3.1).
class PaymentMethodDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  PaymentMethodDao(super.db);

  $PaymentMethodsTable get _table => attachedDatabase.paymentMethods;

  SimpleSelectStatement<$PaymentMethodsTable, PaymentMethodRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits every active payment method in display order.
  Stream<List<PaymentMethodRow>> watchAll() =>
      (_activeRows()..orderBy([(t) => OrderingTerm(expression: t.sortOrder)])).watch();

  /// Reads one payment method by id, including a soft-deleted one, so historical transactions
  /// still render a name.
  Future<PaymentMethodRow?> byIdIncludingDeleted(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Inserts or updates a payment method.
  Future<void> upsert(PaymentMethodsCompanion method) =>
      into(_table).insertOnConflictUpdate(method);

  /// Soft-deletes a user-created payment method; 0 rows changed for a system one.
  Future<int> softDeleteUserMethod({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id) & t.isSystem.equals(false))).write(
      PaymentMethodsCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Counts active transactions using [methodId], for the "in use" check.
  Future<int> activeTransactionCount(String methodId) async {
    final transactions = attachedDatabase.transactions;
    final count = countAll();
    final row = await (selectOnly(transactions)
      ..addColumns([count])
      ..where(transactions.paymentMethodId.equals(methodId) &
      transactions.deletedAt.isNull()))
        .getSingle();
    return row.read(count) ?? 0;
  }
}