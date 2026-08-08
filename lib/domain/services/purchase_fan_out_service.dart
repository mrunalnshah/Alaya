import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/text/normalizer.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';

/// Which artefact a purchase line produces, if any.
enum FanOutTarget {
  /// Nothing — a plain expense line.
  none,

  /// An `inventory_batches` row.
  batch,

  /// An `assets` row.
  asset,

  /// A `recurring_templates` row.
  recurringTemplate,
}

/// Exactly one artefact to create, and the line to write its id back to.
///
/// **At most one of [batch] and [asset] is ever non-null.** That is the invariant the whole class
/// exists to enforce: a line has one `destination`, so it produces one artefact, and
/// `transaction_lines` has three separate `created*Id` columns precisely so a reader can tell which
/// (ARCH_2 §4.2). A line that produced both a batch and an asset would make "what did this purchase
/// create" unanswerable — which is anomaly A12.
class FanOutPlan {
  /// Creates a plan.
  const FanOutPlan({
    required this.lineId,
    required this.target,
    this.batch,
    this.asset,
    this.recurringTemplateName,
  });

  /// A plan that creates nothing.
  const FanOutPlan.none(this.lineId)
    : target = FanOutTarget.none,
      batch = null,
      asset = null,
      recurringTemplateName = null;

  /// The line this plan came from, and where the created id is written back.
  final String lineId;

  /// What to create.
  final FanOutTarget target;

  /// The batch to create, when [target] is [FanOutTarget.batch].
  final Batch? batch;

  /// The asset to create, when [target] is [FanOutTarget.asset].
  final Asset? asset;

  /// The name for a template the user will finish configuring, when [target] is
  /// [FanOutTarget.recurringTemplate].
  ///
  /// A name rather than a whole `RecurringTemplate`: a schedule needs an interval and an anchor that
  /// a receipt line simply does not contain, and inventing a monthly-on-the-1st default would create
  /// obligations the user never agreed to. The caller opens the template editor pre-filled instead.
  final String? recurringTemplateName;

  /// True when the caller must create something.
  bool get createsArtefact => target != FanOutTarget.none;

  /// Sanity invariant: never more than one artefact.
  bool get isWellFormed {
    final count = [
      batch != null,
      asset != null,
      recurringTemplateName != null,
    ].where((set) => set).length;
    return target == FanOutTarget.none ? count == 0 : count == 1;
  }
}

/// Turns a saved transaction line into the one artefact its `destination` calls for.
///
/// **Pure.** It builds entities and returns them; the caller writes them and calls
/// `TransactionLineDao.setCreatedArtefact` to record the link. Nothing here touches a database, so
/// the "asset destination creates no batch" guarantee is testable directly rather than inferred from
/// what a repository happened to do.
///
/// This is the only service in Phase 4B with no prior implementation — the `created*Id` columns and
/// the *detach* path existed from Phase 1B and 3B, but nothing ever populated them.
final class PurchaseFanOutService {
  /// Creates the service.
  const PurchaseFanOutService({Normalizer normalizer = const Normalizer()})
    : _normalizer = normalizer;

  final Normalizer _normalizer;

  /// Plans the artefact [line] should produce.
  ///
  /// [newArtefactId] is used only when something is actually created, so a caller may generate a
  /// UUID unconditionally without leaking an unused one.
  ///
  /// Fails with a [ValidationFailure] when the destination needs data the line lacks — an inventory
  /// line without a quantity, or without a catalogued item to attach the batch to. Refusing is the
  /// point: a batch with a guessed quantity is stock the user never bought.
  Result<FanOutPlan, Failure> plan({
    required TransactionLine line,
    required Transaction transaction,
    required String newArtefactId,
  }) {
    switch (line.destination) {
      case TransactionLineDestination.none:
        return Result.ok(FanOutPlan.none(line.id));

      case TransactionLineDestination.inventory:
        return _planBatch(
          line: line,
          transaction: transaction,
          newId: newArtefactId,
        );

      case TransactionLineDestination.asset:
        return _planAsset(
          line: line,
          transaction: transaction,
          newId: newArtefactId,
        );

      case TransactionLineDestination.recurring:
        return Result.ok(
          FanOutPlan(
            lineId: line.id,
            target: FanOutTarget.recurringTemplate,
            recurringTemplateName: line.description,
          ),
        );
    }
  }

  /// Plans every artefact a transaction's lines produce, skipping lines that already have one.
  ///
  /// [newArtefactIds] must supply one id per line in [lines]; ids for lines that create nothing go
  /// unused. Re-running over a transaction whose lines already carry a `created*Id` produces no
  /// plans, which is what makes the fan-out safe to retry after a partial failure.
  Result<List<FanOutPlan>, Failure> planAll({
    required List<TransactionLine> lines,
    required Transaction transaction,
    required List<String> newArtefactIds,
  }) {
    if (newArtefactIds.length < lines.length) {
      return const Result.failure(
        ValidationFailure(
          'One artefact id is needed per line.',
          field: 'newArtefactIds',
        ),
      );
    }

    final plans = <FanOutPlan>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.hasArtefact) continue;
      final planned = plan(
        line: line,
        transaction: transaction,
        newArtefactId: newArtefactIds[i],
      );
      if (planned.isFailure) return Result.failure(planned.failureOrNull!);
      final value = planned.valueOrNull!;
      if (value.createsArtefact) plans.add(value);
    }
    return Result.ok(plans);
  }

  Result<FanOutPlan, Failure> _planBatch({
    required TransactionLine line,
    required Transaction transaction,
    required String newId,
  }) {
    // **A missing unit code is refused, not defaulted to `''`.**
    // `inventory_batches.unit_code_at_purchase` is a foreign key into `units`, and the empty string
    // matches no row — so the old `?? ''` did not paper over the gap, it turned a legible rejection
    // into `FOREIGN KEY constraint failed` several layers away, after the transaction had already
    // been written.
    final unitCode = line.unitCode;
    if (unitCode == null || unitCode.isEmpty) {
      return Result.failure(
        ValidationFailure(
          'This line is marked for inventory but has no unit, so the stock it would create could '
          'not be measured.',
          field: 'unitCode',
        ),
      );
    }
    final itemId = line.itemId;
    if (itemId == null) {
      return const Result.failure(
        ValidationFailure(
          'An inventory line needs a catalogued item for its batch to belong to.',
          field: 'itemId',
        ),
      );
    }
    final quantity = line.quantity;
    if (quantity == null || !quantity.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'An inventory line needs a quantity greater than zero.',
          field: 'quantity',
        ),
      );
    }

    return Result.ok(
      FanOutPlan(
        lineId: line.id,
        target: FanOutTarget.batch,
        batch: Batch(
          id: newId,
          itemId: itemId,
          initialQuantity: quantity,
          // Nothing has been consumed yet, so remaining equals initial. `BatchRepository.create`
          // enforces this and writes the founding movement from it.
          remainingQuantity: quantity,
          unitCodeAtPurchase: unitCode,
          purchasedDateKey: transaction.dateKey,
          origin: BatchOrigin.purchase,
          unitCost: line.unitPrice,
          sourceTransactionLineId: line.id,
        ),
      ),
    );
  }

  Result<FanOutPlan, Failure> _planAsset({
    required TransactionLine line,
    required Transaction transaction,
    required String newId,
  }) {
    final name = line.description.trim();
    if (name.isEmpty) {
      return const Result.failure(
        ValidationFailure(
          'An asset line needs a description to name the asset.',
          field: 'description',
        ),
      );
    }

    return Result.ok(
      FanOutPlan(
        lineId: line.id,
        target: FanOutTarget.asset,
        // No batch, deliberately and unconditionally. Electronics defaulting to the Service Manager
        // rather than Inventory is the resolution of anomaly A12: a television is serviced and has a
        // warranty, it is not consumed in portions. A user who also wants it in inventory adds it
        // there explicitly, which creates a second line with its own destination.
        asset: Asset(
          id: newId,
          name: name,
          normalizedName: _normalizer.normalize(name),
          // `other` rather than a guess from the description. Classifying "LG 55 inch" as
          // `electronics` by keyword would be wrong often enough to matter, and the asset editor
          // asks for the type anyway.
          type: AssetType.other,
          status: AssetStatus.active,
          purchaseDateKey: transaction.dateKey,
          purchasePrice: line.lineAmount,
          sourceTransactionLineId: line.id,
        ),
      ),
    );
  }

  /// The quantity a fanned-out batch should hold, for a caller checking before it writes.
  Qty? batchQuantityFor(TransactionLine line) =>
      line.destination == TransactionLineDestination.inventory
      ? line.quantity
      : null;

  /// The price a fanned-out asset should record, for the same reason.
  Money? assetPriceFor(TransactionLine line) =>
      line.destination == TransactionLineDestination.asset
      ? line.lineAmount
      : null;

  /// The civil date any artefact from [transaction] is dated.
  DateKey artefactDateFor(Transaction transaction) => transaction.dateKey;
}
