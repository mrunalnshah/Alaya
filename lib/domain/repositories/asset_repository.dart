import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';

/// Reads and writes service-manager assets.
///
/// **There is no delete method.** Removal is [dispose], which records a reason and a date, so the
/// money spent stays in analytics after the thing is gone (ARCH_3 §4.1).
abstract interface class AssetRepository {
  /// Emits assets in use — everything not disposed.
  Stream<List<Asset>> watchInUse();

  /// Emits non-disposed assets of [type], including service providers.
  Stream<List<Asset>> watchByType(AssetType type);

  /// Emits disposed assets, most recent first — still viewable with their full history.
  Stream<List<Asset>> watchDisposed();

  /// Reads one asset by id, disposed ones included.
  Future<Asset?> byId(String id);

  /// Emits non-disposed assets whose warranty ends within `[from, to]`.
  Stream<List<Asset>> watchWarrantyEndingInRange({
    required DateKey from,
    required DateKey to,
  });

  /// Emits non-disposed assets whose next service falls within `[from, to]`.
  Stream<List<Asset>> watchServiceDueInRange({
    required DateKey from,
    required DateKey to,
  });

  /// Creates or updates an asset.
  ///
  /// Rejects a status of [AssetStatus.disposed] with a [BusinessRuleFailure] — disposal needs a
  /// reason and a date, so it goes through [dispose].
  Future<Result<Asset, Failure>> save(Asset asset);

  /// Moves an asset between active and under-repair.
  Future<Result<void, Failure>> setStatus({
    required String id,
    required AssetStatus status,
  });

  /// Retires an asset — the only removal path.
  ///
  /// [amountMinor] is the sale proceeds when [reason] is [AssetDisposalReason.sold]. It is
  /// denominated in the asset's own purchase currency, since the schema carries no separate disposal
  /// currency — pairing an amount with the wrong currency is the mistake Law L1 exists to prevent.
  Future<Result<void, Failure>> dispose({
    required String assetId,
    required AssetDisposalReason reason,
    required DateKey dateKey,
    int? amountMinor,
    String? note,
  });

  /// Returns a disposed asset to service, clearing its disposal fields — the undo for a mis-tap.
  Future<Result<void, Failure>> undispose(String id);

  /// Clears the link to a deleted source transaction (anomaly A10) — the TV does not un-exist
  /// because the receipt did.
  Future<Result<void, Failure>> detachFromDeletedTransaction(String id);
}