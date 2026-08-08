import 'package:drift/drift.dart';

import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to `assets`, plus `v_asset_alerts` for the warranty/service read.
///
/// **There is no delete method of any kind — not even a soft one.** Removing an asset is
/// [dispose], which sets `status = disposed` plus a reason, so the ₹45,000 spent on the TV stays
/// in analytics after the TV is gone (ARCH_3 §4.1). The `deletedAt` column exists on the table and
/// nothing in this class writes it: it is reserved for Phase 8B's trash screen, and a method to
/// set it should be added there, deliberately, rather than sitting here waiting to be called by
/// mistake.
class AssetDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  AssetDao(super.db);

  $AssetsTable get _table => attachedDatabase.assets;

  SimpleSelectStatement<$AssetsTable, AssetRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits assets that are not disposed, in name order — the main list.
  Stream<List<AssetRow>> watchInUse() {
    return (_activeRows()
      ..where((t) => t.status.equalsValue(AssetStatus.disposed).not())
      ..orderBy([(t) => OrderingTerm(expression: t.normalizedName)]))
        .watch();
  }

  /// Emits non-disposed assets of [type] — including `serviceProvider`, which is how a house maid
  /// lives in the same table as a TV (anomaly A30).
  Stream<List<AssetRow>> watchByType(AssetType type) {
    return (_activeRows()
      ..where((t) =>
      t.type.equalsValue(type) & t.status.equalsValue(AssetStatus.disposed).not())
      ..orderBy([(t) => OrderingTerm(expression: t.normalizedName)]))
        .watch();
  }

  /// Emits disposed assets, most recently disposed first — still viewable with their full
  /// history, because the money spent on them has not stopped being real.
  Stream<List<AssetRow>> watchDisposed() {
    return (_activeRows()
      ..where((t) => t.status.equalsValue(AssetStatus.disposed))
      ..orderBy([
            (t) => OrderingTerm(expression: t.disposedAtDateKey, mode: OrderingMode.desc),
      ]))
        .watch();
  }

  /// Reads one asset by id, disposed or not.
  Future<AssetRow?> byId(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads one non-deleted asset by normalized name, for the merge-or-create decision.
  Future<AssetRow?> byNormalizedName(String normalizedName) =>
      (_activeRows()..where((t) => t.normalizedName.equals(normalizedName))).getSingleOrNull();

  /// Emits non-disposed assets whose warranty ends within `[from, to]`.
  Stream<List<AssetRow>> watchWarrantyEndingInRange({
    required DateKey from,
    required DateKey to,
  }) {
    return (_activeRows()
      ..where((t) =>
      t.warrantyEndDateKey.isInDateRange(from, to) &
      t.status.equalsValue(AssetStatus.disposed).not())
      ..orderBy([(t) => OrderingTerm(expression: t.warrantyEndDateKey)]))
        .watch();
  }

  /// Emits non-disposed assets whose next service falls within `[from, to]`.
  Stream<List<AssetRow>> watchServiceDueInRange({
    required DateKey from,
    required DateKey to,
  }) {
    return (_activeRows()
      ..where((t) =>
      t.nextServiceDueDateKey.isInDateRange(from, to) &
      t.status.equalsValue(AssetStatus.disposed).not())
      ..orderBy([(t) => OrderingTerm(expression: t.nextServiceDueDateKey)]))
        .watch();
  }

  /// Inserts or updates an asset.
  ///
  /// Upserts on the primary key; `assets` has no other unique index, so the repository resolves
  /// identity via [byNormalizedName] first and passes the existing `id` to update.
  Future<void> upsert(AssetsCompanion asset) => into(_table).insertOnConflictUpdate(asset);

  /// Moves an asset between `active` and `underRepair`.
  ///
  /// Deliberately cannot set `disposed`: that transition needs a reason and a date, so it goes
  /// through [dispose] instead. [ArgumentError] rather than a silent no-op, because a caller
  /// reaching for this to dispose something has misunderstood the model.
  Future<void> setStatus({
    required String id,
    required AssetStatus status,
    required int nowUtcMillis,
  }) {
    if (status == AssetStatus.disposed) {
      throw ArgumentError.value(
        status,
        'status',
        'Use dispose() — a disposal requires a reason and a date (ARCH_3 §4.1).',
      );
    }
    return (update(_table)..where((t) => t.id.equals(id))).write(
      AssetsCompanion(status: Value(status), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Retires an asset. **The only removal path** — this is what "delete my TV by selecting a
  /// reason" actually does (ARCH_3 §4.1).
  ///
  /// [amountMinor] is the sale proceeds when [reason] is [AssetDisposalReason.sold], and null
  /// otherwise. It is denominated in the asset's own `purchaseCurrencyCode`, since `assets` has no
  /// separate disposal currency column — pairing it with any other currency would silently
  /// misstate the figure (Law L1's pairing rule, as `MoneyColumns` documents).
  Future<void> dispose({
    required String assetId,
    required AssetDisposalReason reason,
    required DateKey dateKey,
    int? amountMinor,
    String? note,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(assetId))).write(
      AssetsCompanion(
        status: const Value(AssetStatus.disposed),
        disposalReason: Value(reason),
        disposedAtDateKey: Value(dateKey),
        disposalAmountMinor: amountMinor == null ? const Value.absent() : Value(amountMinor),
        disposalNote: note == null ? const Value.absent() : Value(note),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Returns a disposed asset to service, clearing the disposal fields — the undo for a
  /// mis-tapped [dispose].
  Future<void> undispose({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      AssetsCompanion(
        status: const Value(AssetStatus.active),
        disposalReason: const Value(null),
        disposedAtDateKey: const Value(null),
        disposalAmountMinor: const Value(null),
        disposalNote: const Value(null),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Moves `nextServiceDueDateKey` forward after a service is recorded.
  Future<void> advanceNextService({
    required String id,
    required DateKey nextServiceDueDateKey,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      AssetsCompanion(
        nextServiceDueDateKey: Value(nextServiceDueDateKey),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// Clears the link from this asset to the transaction line that created it, when that
  /// transaction is deleted (anomaly A10) — the TV does not un-exist because the receipt did.
  Future<void> detachFromDeletedTransaction({
    required String id,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      AssetsCompanion(
        sourceTransactionLineId: const Value(null),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  // ── the view ──────────────────────────────────────────────────────────────────────────

  /// Emits `v_asset_alerts` — non-disposed assets carrying a warranty end or a next-service date.
  ///
  /// The view applies no time window, because a view takes no parameters; filter it with
  /// [watchWarrantyEndingInRange] or [watchServiceDueInRange], which hit `idx_asset_warranty` and
  /// `idx_asset_service` rather than scanning.
  Stream<List<AssetAlertRow>> watchAlerts() => select(attachedDatabase.vAssetAlerts).watch();

  /// Reads `v_asset_alerts` once.
  Future<List<AssetAlertRow>> alerts() => select(attachedDatabase.vAssetAlerts).get();
}