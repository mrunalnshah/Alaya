import 'package:drift/drift.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to `stock_movements` — the append-only ledger, the second of the app's three
/// (ARCH_1 §3.3).
///
/// **There is no delete method, and none of the update methods can touch `kind` or
/// `quantityMilli`.** This is deliberate at the type level, not by convention: the only mutation
/// this class exposes after insert is [markReversalLinked], which writes nothing but
/// `reversesMovementId` and only via the `Companion`-free [insert] path — there is no
/// `update(_table)` call anywhere in this file. A correction is a new row via [insert] with
/// [StockMovementsCompanion.reversesMovementId] set, summed against the original by
/// `v_batch_stock_check`'s `CASE WHEN kind IN (...)` — never an edit of the row it corrects.
class StockMovementDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  StockMovementDao(super.db);

  $StockMovementsTable get _table => attachedDatabase.stockMovements;

  /// Kinds that increase `remainingQuantityMilli`. Matches `v_batch_stock_check`'s
  /// `CASE WHEN m.kind IN (...)` exactly — kept in sync deliberately, since a repair path and
  /// its reconciliation probe must never disagree about which direction a kind moves stock.
  static const Set<StockMovementKind> incomingKinds = {
    StockMovementKind.openingIn,
    StockMovementKind.purchaseIn,
    StockMovementKind.manualIn,
    StockMovementKind.adjustIn,
  };

  /// The signed quantity [movement] represents: positive for an incoming kind, negative
  /// otherwise. The single place that direction rule is expressed in Dart.
  static int signedQuantityOf({required StockMovementKind kind, required int quantityMilli}) =>
      incomingKinds.contains(kind) ? quantityMilli : -quantityMilli;

  /// Inserts one movement. Callers needing the cache updated too want
  /// `BatchDao.applyMovement`, not this method directly — see that class's doc comment.
  Future<void> insert(StockMovementsCompanion movement) => into(_table).insert(movement);

  /// Emits the movements for [batchId], oldest first — a batch's full history.
  Stream<List<StockMovementRow>> watchForBatch(String batchId) {
    return (select(_table)
      ..where((t) => t.batchId.equals(batchId))
      ..orderBy([(t) => OrderingTerm(expression: t.occurredAt)]))
        .watch();
  }

  /// Reads the movements for [batchId] once, oldest first.
  Future<List<StockMovementRow>> forBatch(String batchId) {
    return (select(_table)
      ..where((t) => t.batchId.equals(batchId))
      ..orderBy([(t) => OrderingTerm(expression: t.occurredAt)]))
        .get();
  }

  /// Emits the movements for [itemId] across all its batches within `[from, to]`, newest first —
  /// the basis for the food-waste analytics in ARCH_3 §5.1 query 14.
  Stream<List<StockMovementRow>> watchForItemInRange({
    required String itemId,
    required DateKey from,
    required DateKey to,
  }) {
    return (select(_table)
      ..where((t) => t.itemId.equals(itemId) & t.dateKey.isInDateRange(from, to))
      ..orderBy([(t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Reads the movements of [kind] for [itemId] within `[from, to]` — used to total waste and
  /// expired quantity separately from ordinary consumption.
  Future<List<StockMovementRow>> forItemByKindInRange({
    required String itemId,
    required StockMovementKind kind,
    required DateKey from,
    required DateKey to,
  }) {
    return (select(_table)
      ..where((t) =>
      t.itemId.equals(itemId) &
      t.kind.equalsValue(kind) &
      t.dateKey.isInDateRange(from, to)))
        .get();
  }

  /// Reads every movement of [kinds] within `[from, to]`, across **all** items.
  ///
  /// The per-item [forItemByKindInRange] cannot answer "what did I waste this month" without the
  /// caller already enumerating every item in the catalogue — which inverts the question, since
  /// the answer is precisely the small set of items that *have* waste. This scans
  /// `idx_move_item_date` over the date range instead and lets the caller group.
  ///
  /// Takes a set of kinds because waste and expiry are distinct events — food thrown out
  /// deliberately versus food that rotted unnoticed — but ARCH_3 §5.1 query 14 counts both as
  /// stock paid for and never used.
  /// Returns an empty list for an empty [kinds] rather than querying — a query matching no kind
  /// would return nothing anyway, and building an always-false predicate is needless SQL.
  Future<List<StockMovementRow>> forKindsInRange({
    required Set<StockMovementKind> kinds,
    required DateKey from,
    required DateKey to,
  }) {
    if (kinds.isEmpty) return Future.value(const []);
    return (select(_table)
      ..where((t) {
        // Folded ORs of `equalsValue` rather than `isInValues`: `kind` carries a type
        // converter, so its SQL type is `String` and `isInValues` would demand the mapped
        // strings. `equalsValue` is the API that compares against the Dart value.
        Expression<bool> kindMatches = t.kind.equalsValue(kinds.first);
        for (final kind in kinds.skip(1)) {
          kindMatches = kindMatches | t.kind.equalsValue(kind);
        }
        return t.dateKey.isInDateRange(from, to) & kindMatches;
      })
      ..orderBy([(t) => OrderingTerm(expression: t.occurredAt)]))
        .get();
  }

  /// Reads one movement by id — for resolving what a reversal points at.
  Future<StockMovementRow?> byId(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads the reversal of [movementId], if one has been recorded.
  Future<StockMovementRow?> reversalOf(String movementId) =>
      (select(_table)..where((t) => t.reversesMovementId.equals(movementId)))
          .getSingleOrNull();
}