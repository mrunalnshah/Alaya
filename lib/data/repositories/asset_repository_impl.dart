import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/asset_dao.dart';
import 'package:alaya/data/repositories/mappers/schedule_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/repositories/asset_repository.dart';

/// `AssetRepository` backed by `AssetDao`.
///
/// **There is no delete method on the contract and none here.** Retiring an asset is [dispose],
/// which records a reason and a date so the money spent stays in analytics after the thing is gone
/// (ARCH_3 §4.1). The `deletedAt` column exists on the table and nothing in this class or its DAO
/// writes it — it is reserved for Phase 8B's trash screen.
final class AssetRepositoryImpl implements AssetRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const AssetRepositoryImpl(this._dao, this._clock);

  final AssetDao _dao;
  final Clock _clock;

  @override
  Stream<List<Asset>> watchInUse() =>
      _dao.watchInUse().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Asset>> watchByType(AssetType type) => _dao
      .watchByType(type)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Asset>> watchDisposed() => _dao.watchDisposed().map(
    (rows) => rows.map((r) => r.toEntity()).toList(),
  );

  @override
  Future<Asset?> byId(String id) async => (await _dao.byId(id))?.toEntity();

  @override
  Stream<List<Asset>> watchWarrantyEndingInRange({
    required DateKey from,
    required DateKey to,
  }) => _dao
      .watchWarrantyEndingInRange(from: from, to: to)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Asset>> watchServiceDueInRange({
    required DateKey from,
    required DateKey to,
  }) => _dao
      .watchServiceDueInRange(from: from, to: to)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Result<Asset, Failure>> save(Asset asset) async {
    if (asset.name.trim().isEmpty) {
      return const Result.failure(
        ValidationFailure('An asset needs a name.', field: 'name'),
      );
    }
    if (asset.status == AssetStatus.disposed) {
      // A disposal needs a reason and a date, which this method has no parameters for. Accepting
      // the status alone would produce a `disposed` asset with no record of why or when — exactly
      // the state ARCH_3 §4.1's "never deleted, always a reason" rule exists to prevent.
      return const Result.failure(
        BusinessRuleFailure(
          'Use dispose() to retire an asset — a disposal needs a reason and a date.',
          rule: 'disposalNeedsReason',
        ),
      );
    }

    // **An asset is not unique by name, and refusing a duplicate was wrong.**
    //
    // A household with five iPhones has five assets: five serial numbers, five warranties, five service
    // histories. Two identical ceiling fans are two fans. The name is a label a person chose, not an
    // identity — so a second "iPhone" is a second phone, and blocking it made the app unusable for the
    // ordinary case of owning more than one of something.
    //
    // This is the opposite of `items`, deliberately. Law L8 makes name plus unit category the identity of
    // an Item because 500g of onion *is* the same onion as another 500g; quantities of a fungible thing
    // merge. An asset never merges: it is one object and it wears out on its own schedule. The
    // name lookup stays on the DAO for the editor to offer a note with — never a block.
    final existing = await _dao.byId(asset.id);

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      assetToCompanion(
        asset,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    return Result.ok(asset);
  }

  @override
  Future<Result<void, Failure>> setStatus({
    required String id,
    required AssetStatus status,
  }) async {
    final existing = await _dao.byId(id);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Asset not found.', id: id));
    }
    if (status == AssetStatus.disposed) {
      // The DAO throws an ArgumentError for this rather than silently accepting it. Catching it
      // here first turns a programming error into a failure the UI can render.
      return const Result.failure(
        BusinessRuleFailure(
          'Use dispose() to retire an asset — a disposal needs a reason and a date.',
          rule: 'disposalNeedsReason',
        ),
      );
    }
    await _dao.setStatus(
      id: id,
      status: status,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> dispose({
    required String assetId,
    required AssetDisposalReason reason,
    required DateKey dateKey,
    int? amountMinor,
    String? note,
  }) async {
    final existing = await _dao.byId(assetId);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Asset not found.', id: assetId));
    }
    if (existing.status == AssetStatus.disposed) {
      return const Result.failure(
        BusinessRuleFailure(
          'This asset is already disposed.',
          rule: 'alreadyDisposed',
        ),
      );
    }
    if (amountMinor != null && amountMinor < 0) {
      return const Result.failure(
        ValidationFailure(
          'Sale proceeds cannot be negative.',
          field: 'amountMinor',
        ),
      );
    }
    if (amountMinor != null && existing.purchaseCurrencyCode == null) {
      // `assets` has no disposal-currency column: proceeds are denominated in whatever the asset
      // was bought in (ARCH_2 §8). With no purchase currency recorded there is nothing to pair the
      // amount with, and storing a bare number would break Law L1's pairing rule.
      return const Result.failure(
        BusinessRuleFailure(
          'This asset has no purchase currency recorded, so sale proceeds cannot be stored '
          'against it. Add a purchase price first.',
          rule: 'noCurrencyForProceeds',
        ),
      );
    }

    await _dao.dispose(
      assetId: assetId,
      reason: reason,
      dateKey: dateKey,
      amountMinor: amountMinor,
      note: note,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> undispose(String id) async {
    final existing = await _dao.byId(id);
    if (existing == null) {
      return Result.failure(NotFoundFailure('Asset not found.', id: id));
    }
    if (existing.status != AssetStatus.disposed) {
      return const Result.failure(
        BusinessRuleFailure('This asset is not disposed.', rule: 'notDisposed'),
      );
    }
    await _dao.undispose(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> detachFromDeletedTransaction(String id) async {
    await _dao.detachFromDeletedTransaction(
      id: id,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }
}
