import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';

/// Which order stock should be drawn in, and whether expired batches may participate.
///
/// **Two orders, because the same rule cannot serve both purposes.** Drawing stock down to *use* it
/// and drawing it down to *write it off* want opposite things from expired batches, and a single
/// ordering would be wrong for one of them. Making the choice a parameter with a default keeps every
/// caller written before this policy existed on the behaviour it was written against.
///
/// **Its own file, and the reason is a cycle rather than taste.** `InventoryConsumptionService` already
/// imports `StockRepository` for `ConsumptionDraw`; putting this class in the service and then naming
/// it on `StockRepository.consume` would have the contract importing the service that imports the
/// contract. A policy shared by a contract and a service belongs in neither.
final class DrawPolicy {
  /// Nearest expiry first, undated last, expired batches included.
  ///
  /// The waste-minimising order (anomaly A08) and the default, because it is what every caller before
  /// this policy existed was doing. Right for a waste or expiry write-off, where the most spoiled
  /// batch is exactly the one to reach for.
  const DrawPolicy.fefo() : today = null, allowExpired = true;

  /// Unexpired batches first — nearest expiry among those — then expired ones last, and only when
  /// [allowExpired].
  ///
  /// Right for cooking. FEFO orders by nearest expiry and an expired date *is* the nearest date, so
  /// under FEFO a recipe silently eats the food that is already off before touching anything good.
  /// That was not a bug in the ordering; it was the wrong ordering for the job.
  ///
  /// Among expired batches the order is **least spoiled first**, which is the reverse of FEFO and
  /// deliberate: strict FEFO would hand over the oldest expired batch, the most spoiled thing in the
  /// house. Among food already past its date, nearest-to-fresh is the only defensible choice.
  const DrawPolicy.freshFirst({
    required DateKey today,
    this.allowExpired = false,
  }) : today = today;

  /// The date expiry is judged against, or null under [DrawPolicy.fefo] where it is not consulted.
  ///
  /// Passed in rather than read from a clock, so a plan is reproducible under a `FixedClock` — the
  /// rule `ConsumableBatch.isExpired` and the views follow.
  final DateKey? today;

  /// Whether expired batches may be drawn from at all.
  final bool allowExpired;

  /// Whether this policy distinguishes expired stock from good stock.
  bool get isExpiryAware => today != null;

  /// Whether [batch] may be drawn from under this policy.
  ///
  /// **One definition, two readers.** `InventoryConsumptionService.plan` uses it to choose what to
  /// draw and `StockRepositoryImpl` uses it to decide what a refusal message may quote. Two copies of
  /// "which batches does this policy admit" would be the same fault the service's own doc comment
  /// records about ordering rules.
  bool admits(ConsumableBatch batch) {
    final on = today;
    return allowExpired || on == null || !batch.isExpired(on);
  }
}
