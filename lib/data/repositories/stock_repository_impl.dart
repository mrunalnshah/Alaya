import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/batch_dao.dart';
import 'package:alaya/data/daos/stock_movement_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/mappers/stock_mappers.dart';
import 'package:alaya/domain/services/draw_policy.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';

/// `StockRepository` backed by `BatchDao` and `StockMovementDao`.
///
/// Every write here goes through [BatchDao.applyMovements], which pairs each movement with its
/// batch's cache update inside one transaction (Laws L3, L14). There is no path that records a
/// movement without updating the cache, or the reverse.
final class StockRepositoryImpl implements StockRepository {
  /// Creates the repository.
  const StockRepositoryImpl(
    this._batchDao,
    this._movementDao,
    this._categories,
    this._uids,
    this._clock,
  );

  final BatchDao _batchDao;
  final StockMovementDao _movementDao;
  final ItemCategoryResolver _categories;
  final UidGenerator _uids;
  final Clock _clock;

  /// Formats quantities for the user-facing text on a failure. `Qty.toString()` is a debug
  /// representation (`2500000m(weight)`) and its own doc says never to show it — these messages are
  /// read by a person, so they go through the formatter.
  static const QtyFormatter _qtyFormat = QtyFormatter();

  /// The one definition of the draw order.
  ///
  /// This class used to implement the ordering and the draw-down itself. Phase 4B moved the algorithm
  /// into the service so there is one definition of it — the same consolidation Phase 4A made for the
  /// currency cross-rate, and for the same reason: two copies of an ordering rule drift apart. What
  /// stays here is the part only a repository can do — writing every draw in one transaction.
  static const InventoryConsumptionService _consumption =
      InventoryConsumptionService();

  @override
  Future<Result<List<ConsumptionDraw>, Failure>> consume({
    required String itemId,
    required Qty quantity,
    required StockMovementKind kind,
    DrawPolicy policy = const DrawPolicy.fefo(),
    String? reason,
    String? note,
  }) async {
    if (!quantity.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'The quantity to consume must be greater than zero.',
          field: 'quantity',
        ),
      );
    }

    final category = await _categories.categoryOf(itemId);
    if (category == null) {
      return Result.failure(NotFoundFailure('Item not found.', id: itemId));
    }
    if (category != quantity.category) {
      return Result.failure(
        ValidationFailure(
          'This item is measured in ${category.name}, not ${quantity.category.name}.',
          field: 'quantity',
        ),
      );
    }

    // FEFO order from SQL, already filtered to batches holding stock (anomaly A08). The service sorts
    // again under whichever policy applies — a pure function that trusts its input's order is one
    // whose correctness depends on something it cannot see — so this ordering is a query optimisation
    // rather than a guarantee the plan relies on.
    final batches = _consumable(await _batchDao.byItemFefo(itemId), category);

    // **Counted under the policy, not over the whole shelf.** Excluding expired stock means excluding
    // it from the total too, or the refusal would quote a figure the plan could not have reached —
    // "only 250 g is on hand" beside a cupboard holding 550 g, 300 g of it off.
    final available = _consumption.availableUnder(
      batches,
      policy: policy,
      ofCategory: quantity,
    );
    if (available.milliBase < quantity.milliBase) {
      // Checked before any write, and nothing is written on this path. A partial consumption would
      // leave the ledger describing something that did not happen — worse than refusing, because
      // the user would have no way to tell how much actually came out.
      return Result.failure(
        BusinessRuleFailure(
          'Only ${_qtyFormat.format(available)} is on hand, less than the '
          '${_qtyFormat.format(quantity)} requested.',
          rule: 'insufficientStock',
        ),
      );
    }

    final planned = _consumption.plan(
      batches: batches,
      needed: quantity,
      policy: policy,
    );
    final plan = planned.valueOrNull;
    if (plan == null) {
      // **Forwarded rather than swallowed.** This used to read `plan.valueOrNull?.draws ?? const []`,
      // on the reasoning that the caller had already checked availability so a failure was impossible.
      // Under a policy that can legitimately refuse, that swallow would apply zero draws and report
      // success — a consumption the user was told happened and did not.
      return Result.failure(
        planned.failureOrNull ??
            const UnexpectedFailure('Stock could not be planned.'),
      );
    }

    await _applyDraws(
      itemId: itemId,
      draws: plan.draws,
      kind: kind,
      reason: reason,
      note: note,
    );
    return Result.ok(plan.draws);
  }

  @override
  Future<Result<void, Failure>> consumeFromBatch({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? reason,
    String? note,
  }) async {
    if (!quantity.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'The quantity to consume must be greater than zero.',
          field: 'quantity',
        ),
      );
    }

    final batch = await _batchDao.byIdIncludingDeleted(batchId);
    if (batch == null) {
      return Result.failure(NotFoundFailure('Batch not found.', id: batchId));
    }
    final category = await _categories.categoryOf(batch.itemId);
    if (category == null) {
      return Result.failure(
        NotFoundFailure('Item not found.', id: batch.itemId),
      );
    }
    if (category != quantity.category) {
      return Result.failure(
        ValidationFailure(
          'This batch is measured in ${category.name}, not ${quantity.category.name}.',
          field: 'quantity',
        ),
      );
    }
    if (batch.remainingQuantityMilli < quantity.milliBase) {
      return Result.failure(
        BusinessRuleFailure(
          'This batch holds only '
          '${_qtyFormat.format(Qty(batch.remainingQuantityMilli, category))}, less than the '
          '${_qtyFormat.format(quantity)} requested.',
          rule: 'insufficientStock',
        ),
      );
    }

    await _applyDraws(
      itemId: batch.itemId,
      draws: [ConsumptionDraw(batchId: batchId, quantity: quantity)],
      kind: kind,
      reason: reason,
      note: note,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> addStock({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? note,
  }) async {
    if (!quantity.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'The quantity to add must be greater than zero.',
          field: 'quantity',
        ),
      );
    }
    if (!StockMovementDao.incomingKinds.contains(kind)) {
      // Guarding the direction rather than trusting it: an outgoing kind passed here would reduce
      // stock while the caller believed it was adding, and the cache would faithfully follow.
      return Result.failure(
        ValidationFailure(
          '${kind.name} removes stock rather than adding it.',
          field: 'kind',
        ),
      );
    }

    final batch = await _batchDao.byIdIncludingDeleted(batchId);
    if (batch == null) {
      return Result.failure(NotFoundFailure('Batch not found.', id: batchId));
    }
    final category = await _categories.categoryOf(batch.itemId);
    if (category == null) {
      return Result.failure(
        NotFoundFailure('Item not found.', id: batch.itemId),
      );
    }
    if (category != quantity.category) {
      return Result.failure(
        ValidationFailure(
          'This batch is measured in ${category.name}, not ${quantity.category.name}.',
          field: 'quantity',
        ),
      );
    }

    await _applyDraws(
      itemId: batch.itemId,
      draws: [ConsumptionDraw(batchId: batchId, quantity: quantity)],
      kind: kind,
      note: note,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> reverse({
    required String movementId,
    String? reason,
  }) async {
    final original = await _movementDao.byId(movementId);
    if (original == null) {
      return Result.failure(
        NotFoundFailure('Movement not found.', id: movementId),
      );
    }

    final alreadyReversed = await _movementDao.reversalOf(movementId);
    if (alreadyReversed != null) {
      return const Result.failure(
        BusinessRuleFailure(
          'This movement has already been reversed.',
          rule: 'alreadyReversed',
        ),
      );
    }
    if (original.reversesMovementId != null) {
      // Reversing a reversal would be indistinguishable from re-applying the original, and would
      // let a chain build up that nothing can interpret. Undo is one level deep by design.
      return const Result.failure(
        BusinessRuleFailure(
          'A correction cannot itself be reversed — record a new movement instead.',
          rule: 'cannotReverseAReversal',
        ),
      );
    }

    // The compensating kind, chosen so the pair nets to zero under the same direction rule
    // `v_batch_stock_check` applies: an incoming movement is undone by an adjustOut and vice versa.
    final compensating = StockMovementDao.incomingKinds.contains(original.kind)
        ? StockMovementKind.adjustOut
        : StockMovementKind.adjustIn;

    final now = _clock.nowUtcMillis();
    await _batchDao.applyMovements(
      entries: [
        (
          batchId: original.batchId,
          movement: StockMovementsCompanion.insert(
            id: _uids.generate(),
            batchId: original.batchId,
            itemId: original.itemId,
            kind: compensating,
            quantityMilli: original.quantityMilli,
            occurredAt: now,
            dateKey: _clock.today(),
            reason: Value(reason),
            reversesMovementId: Value(movementId),
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ],
      nowUtcMillis: now,
    );
    return const Result.ok(null);
  }

  @override
  Stream<List<StockMovement>> watchForBatch(String batchId) {
    return _movementDao.watchForBatch(batchId).asyncMap(_mapAll);
  }

  @override
  Stream<List<StockMovement>> watchForItemInRange({
    required String itemId,
    required DateKey from,
    required DateKey to,
  }) {
    return _movementDao
        .watchForItemInRange(itemId: itemId, from: from, to: to)
        .asyncMap(_mapAll);
  }

  @override
  Future<List<WasteTotal>> wasteTotals({
    required DateKey from,
    required DateKey to,
  }) async {
    // Both waste kinds, totalled separately per item. `expired` and `waste` are distinct events —
    // food that rotted unnoticed versus food thrown out deliberately — but both are stock that was
    // paid for and never used, which is what ARCH_3 §5.1 query 14 measures.
    final byItem = <String, ({int milli, MoneyByCurrency cost})>{};

    // One query across all items, both waste kinds. Asking per item would require the caller to
    // already know which items have waste — inverting the question, since that set is the answer.
    final movements = await _movementDao.forKindsInRange(
      kinds: const {StockMovementKind.waste, StockMovementKind.expired},
      from: from,
      to: to,
    );

    // Batch costs are cached: a single wasted item is typically spread over few batches, and
    // re-reading the same batch row once per movement would dominate the cost of this query.
    final batchCosts = <String, ({int? unitCostMinor, String? currencyCode})>{};

    for (final m in movements) {
      final entry = byItem.putIfAbsent(
        m.itemId,
        () => (milli: 0, cost: MoneyByCurrency()),
      );
      byItem[m.itemId] = (
        milli: entry.milli + m.quantityMilli,
        cost: entry.cost,
      );

      final cost = batchCosts[m.batchId] ??= await () async {
        final batch = await _batchDao.byIdIncludingDeleted(m.batchId);
        return (
          unitCostMinor: batch?.unitCostMinor,
          currencyCode: batch?.costCurrencyCode,
        );
      }();

      final unitCost = cost.unitCostMinor;
      final costCode = cost.currencyCode;
      if (unitCost != null && costCode != null) {
        entry.cost.add(
          currencyCode: costCode,
          // unitCost is per purchased unit; the movement is in base-milli units, so the wasted
          // money is unitCost x (milli / 1000). Truncated: a fraction of a minor unit cannot be
          // represented, and waste valuation is an estimate rather than a ledger figure.
          minor: (unitCost * m.quantityMilli / 1000).truncate(),
        );
      }
    }

    final result = <WasteTotal>[];
    for (final e in byItem.entries) {
      final category = await _categories.categoryOf(e.key);
      if (category == null) continue;
      result.add(
        WasteTotal(
          itemId: e.key,
          quantity: Qty(e.value.milli, category),
          costByCurrency: e.value.cost.totals,
        ),
      );
    }
    return result;
  }

  /// Narrows DAO rows to the four fields the consumption service takes.
  ///
  /// [category] comes from the item rather than the row, because `inventory_batches` stores a bare
  /// integer and Law L8 forbids reinterpreting one without knowing its dimension.
  List<ConsumableBatch> _consumable(
    List<InventoryBatchRow> rows,
    UnitCategory category,
  ) => [
    for (final row in rows)
      ConsumableBatch(
        batchId: row.id,
        remaining: Qty(row.remainingQuantityMilli, category),
        purchasedDateKey: row.purchasedDateKey,
        expiryDateKey: row.expiryDateKey,
      ),
  ];

  /// Records one movement per draw, all in a single transaction (Law L14).
  Future<void> _applyDraws({
    required String itemId,
    required List<ConsumptionDraw> draws,
    required StockMovementKind kind,
    String? reason,
    String? note,
  }) {
    final now = _clock.nowUtcMillis();
    final today = _clock.today();
    return _batchDao.applyMovements(
      entries: draws
          .map(
            (draw) => (
              batchId: draw.batchId,
              movement: StockMovementsCompanion.insert(
                id: _uids.generate(),
                batchId: draw.batchId,
                itemId: itemId,
                kind: kind,
                quantityMilli: draw.quantity.milliBase,
                occurredAt: now,
                dateKey: today,
                reason: Value(reason),
                note: Value(note),
                createdAt: now,
                updatedAt: now,
              ),
            ),
          )
          .toList(),
      nowUtcMillis: now,
    );
  }

  Future<List<StockMovement>> _mapAll(List<StockMovementRow> rows) async {
    final categories = await _categories.categoriesFor(
      rows.map((r) => r.itemId),
    );
    return rows
        .where((r) => categories.containsKey(r.itemId))
        .map((r) => r.toEntity(categories[r.itemId]!))
        .toList();
  }
}
