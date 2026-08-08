/// View-model state for one asset (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/service_record.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';

/// The asset, or null when it does not exist.
///
/// **Derived from the two list streams, not a one-shot `byId`.** A `FutureProvider` reads once and then
/// serves its cache, and the detail screen stays mounted beneath the editor — so it would keep showing
/// the pre-edit asset until the app restarted. Both streams re-emit on every write, and a disposed
/// asset must stay reachable by id even though it has left `watchInUse` (anomaly A30).
final assetByIdProvider = Provider.autoDispose
    .family<AsyncValue<Asset?>, String>((ref, id) {
      final inUse = ref.watch(assetsInUseProvider);
      final disposed = ref.watch(disposedAssetsProvider);
      if (inUse.hasError)
        return AsyncValue.error(inUse.error!, inUse.stackTrace!);
      if (disposed.hasError) {
        return AsyncValue.error(disposed.error!, disposed.stackTrace!);
      }
      final active = inUse.valueOrNull;
      final retired = disposed.valueOrNull;
      if (active == null || retired == null) return const AsyncValue.loading();
      for (final asset in [...active, ...retired]) {
        if (asset.id == id) return AsyncValue.data(asset);
      }
      return const AsyncValue.data(null);
    });

/// Every service record against one asset, newest first.
final serviceRecordsProvider = StreamProvider.autoDispose
    .family<List<ServiceRecord>, String>(
      (ref, assetId) =>
          ref.watch(serviceRecordRepositoryProvider).watchForAsset(assetId),
    );

/// What has been spent servicing one asset, per currency.
///
/// A map rather than a single figure because a machine serviced abroad genuinely has two lifetime
/// totals, and summing them would invent an exchange rate the user never agreed to (Law L1).
final lifetimeServiceCostProvider = FutureProvider.autoDispose
    .family<Map<String, Money>, String>((ref, assetId) {
      // Watched so recording a service updates the figure rather than leaving it stale until a restart.
      ref.watch(serviceRecordsProvider(assetId));
      return ref
          .watch(serviceRecordRepositoryProvider)
          .lifetimeCostByCurrency(assetId);
    });

/// The recurring templates that pay this asset.
///
/// `watchTemplatesForAsset` was built in Phase 3A and deferred to this phase by 6D's coverage table:
/// it is what makes a maid's monthly salary visible from her own record rather than only from the
/// recurring list.
final assetTemplatesProvider = StreamProvider.autoDispose
    .family<List<RecurringTemplate>, String>(
      (ref, assetId) => ref
          .watch(recurringRepositoryProvider)
          .watchTemplatesForAsset(assetId),
    );

/// Writes the asset detail screen performs.
final assetActionsProvider = Provider<AssetActions>(AssetActions.new);

/// Changes an asset's status, and brings it back.
class AssetActions {
  /// Creates the actions.
  AssetActions(this._ref);

  final Ref _ref;

  /// Reverses a disposal, returning the failure's own message or null on success.
  ///
  /// The counterpart to disposal existing at all: a thing sold by mistake is put back, and nothing was
  /// destroyed in the meantime because disposal never deleted anything.
  Future<String?> undispose(String id) async {
    final result = await _ref.read(assetRepositoryProvider).undispose(id);
    return result.failureOrNull?.message;
  }

  /// Marks an asset as being repaired, or active again.
  Future<String?> setStatus({
    required String id,
    required AssetStatus status,
  }) async {
    final result = await _ref
        .read(assetRepositoryProvider)
        .setStatus(id: id, status: status);
    return result.failureOrNull?.message;
  }

  /// Deletes one service record.
  ///
  /// The record, not the asset. There is no path in this module that deletes an asset.
  Future<String?> deleteRecord(String recordId) async {
    final result = await _ref
        .read(serviceRecordRepositoryProvider)
        .delete(recordId);
    return result.failureOrNull?.message;
  }
}
