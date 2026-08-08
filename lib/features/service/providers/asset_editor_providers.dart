/// View-model state for the asset editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';
import 'package:alaya/features/service/state/asset_editor_state.dart';

/// The home currency, so a price is never denominated in a guess.
final serviceCurrencyProvider = FutureProvider.autoDispose<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      'INR',
);

/// The home currency's decimal digits (ARCH_1 §4.1).
final serviceDecimalDigitsProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final code = await ref.watch(serviceCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// Whether another asset already carries this name.
///
/// **Derived from the list streams, and only ever a note.** `AssetRepositoryImpl.save` used to refuse a
/// repeated name, which made owning two of anything impossible — five iPhones are five assets, with five
/// warranties and five service histories. But a silent duplicate hides a genuine double entry, so the
/// editor says so and lets the user decide.
///
/// `AssetDao.byNormalizedName` exists and `AssetRepository` does not expose it; deriving from
/// `watchInUse` and `watchDisposed` needs no contract addition and no DAO reach-through (Law U19).
final assetNameClashProvider = Provider.autoDispose
    .family<bool, ({String? id, String name})>((ref, arg) {
      final trimmed = arg.name.trim();
      if (trimmed.isEmpty) return false;
      final normalized = ref.watch(normalizerProvider).normalize(trimmed);
      final inUse =
          ref.watch(assetsInUseProvider).valueOrNull ?? const <Asset>[];
      final disposed =
          ref.watch(disposedAssetsProvider).valueOrNull ?? const <Asset>[];
      for (final asset in [...inUse, ...disposed]) {
        if (asset.normalizedName == normalized && asset.id != arg.id)
          return true;
      }
      return false;
    });

/// The editor for one asset, or for a new one when the argument is null.
final assetEditorProvider = NotifierProvider.autoDispose
    .family<AssetEditorNotifier, AsyncValue<AssetEditorState>, String?>(
      AssetEditorNotifier.new,
    );

/// Loads, edits and saves one asset.
class AssetEditorNotifier
    extends AutoDisposeFamilyNotifier<AsyncValue<AssetEditorState>, String?> {
  @override
  AsyncValue<AssetEditorState> build(String? arg) {
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(String? id) async {
    try {
      final code =
          await ref.read(settingsRepositoryProvider).readHomeCurrencyCode() ??
          'INR';
      if (id == null) {
        state = AsyncValue.data(AssetEditorState(currencyCode: code));
        return;
      }
      final asset = await ref.read(assetRepositoryProvider).byId(id);
      if (asset == null) {
        state = AsyncValue.error(
          StateError('Asset $id not found.'),
          StackTrace.current,
        );
        return;
      }
      state = AsyncValue.data(AssetEditorState.fromAsset(asset, code));
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  /// Applies [change], clearing the last rejection unless told to keep it.
  ///
  /// A refused save is worth longer than a 2.5-second snack, so it is also a card in the form — but a card
  /// that survives the edit which fixes it is a stale error the user has to dismiss by hand. Every setter
  /// clears it; only `save` keeps it.
  void _edit(
    AssetEditorState Function(AssetEditorState) change, {
    bool keepIssue = false,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = change(current);
    state = AsyncValue.data(keepIssue ? next : next.copyWith(clearIssue: true));
  }

  /// Sets what it is.
  void setName(String name) =>
      _edit((s) => s.copyWith(name: name, clearIssue: true));

  /// Sets which kind of thing — or person — this is.
  void setType(AssetType type) => _edit((s) => s.copyWith(type: type));

  /// Sets who made it.
  void setBrand(String value) => _edit((s) => s.copyWith(brand: value));

  /// Sets the model number.
  void setModelNo(String value) => _edit((s) => s.copyWith(modelNo: value));

  /// Sets the serial number.
  void setSerialNo(String value) => _edit((s) => s.copyWith(serialNo: value));

  /// Sets when it was bought.
  void setPurchaseDate(DateKey? date) =>
      _edit((s) => date == null ? s : s.copyWith(purchaseDateKey: date));

  /// Sets what it cost.
  void setPurchasePrice(Money? price) => _edit(
    (s) => price == null
        ? s.copyWith(clearPurchasePrice: true)
        : s.copyWith(purchasePrice: price),
  );

  /// Sets when the warranty starts.
  void setWarrantyStart(DateKey? date) =>
      _edit((s) => date == null ? s : s.copyWith(warrantyStartDateKey: date));

  /// Sets when the warranty ends.
  void setWarrantyEnd(DateKey? date) => _edit(
    (s) => date == null
        ? s.copyWith(clearWarrantyEnd: true)
        : s.copyWith(warrantyEndDateKey: date, clearIssue: true),
  );

  /// Sets who honours the warranty.
  void setWarrantyProvider(String value) =>
      _edit((s) => s.copyWith(warrantyProvider: value));

  /// Sets how many days between services, and derives the first due date from it.
  ///
  /// **Recomputed on every change, not seeded once.** A text field fires per keystroke: "30" arrives as
  /// 3 and then as 30, and the old `??` meant the three-day answer stuck. The date is derived from the
  /// interval unless the user has picked one themselves, which `nextServiceChosen` records.
  ///
  /// Deriving rather than requiring both: an interval with no first date never produces a due chip, and
  /// asking for the same information twice is how one of the two ends up wrong.
  void setServiceIntervalDays(int? days) => _edit((s) {
    if (days == null || days < 1) {
      return s.copyWith(clearInterval: true, clearNextService: true);
    }
    final from = s.purchaseDateKey ?? ref.read(clockProvider).today();
    return s.copyWith(
      serviceIntervalDays: days,
      nextServiceDueDateKey: s.nextServiceChosen
          ? s.nextServiceDueDateKey
          : from.addDays(days),
    );
  });

  /// Sets when the next service is due, and stops the interval deriving it from then on.
  void setNextServiceDue(DateKey? date) => _edit(
    (s) => date == null
        ? s.copyWith(clearNextService: true, nextServiceChosen: false)
        : s.copyWith(nextServiceDueDateKey: date, nextServiceChosen: true),
  );

  /// Sets who to call about it.
  void setContactName(String value) =>
      _edit((s) => s.copyWith(contactName: value));

  /// Sets the number to call.
  void setContactPhone(String value) =>
      _edit((s) => s.copyWith(contactPhone: value));

  /// Sets where it is kept.
  void setLocation(String value) => _edit((s) => s.copyWith(location: value));

  /// Sets the free notes.
  void setNotes(String value) => _edit((s) => s.copyWith(notes: value));

  /// Saves the asset, returning its id on success and null on rejection or failure.
  ///
  /// Every refusal is named before the repository sees it, and a rejection carries the repository's own
  /// message — a blank name and a backwards warranty fail for different reasons and "something went
  /// wrong" distinguishes neither (Law U9).
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.name.trim().isEmpty) {
      _edit(
        (s) => s.copyWith(
          issue: AssetSaveIssue.nameMissing,
          shakeTrigger: s.shakeTrigger + 1,
        ),
        keepIssue: true,
      );
      return null;
    }
    final start = current.warrantyStartDateKey;
    final end = current.warrantyEndDateKey;
    if (start != null && end != null && end.isBefore(start)) {
      _edit(
        (s) => s.copyWith(issue: AssetSaveIssue.warrantyBackwards),
        keepIssue: true,
      );
      return null;
    }

    _edit(
      (s) => s.copyWith(submitting: true, clearIssue: true),
      keepIssue: true,
    );
    try {
      final repository = ref.read(assetRepositoryProvider);
      final id = current.id ?? ref.read(uidGeneratorProvider).generate();
      // The existing row is read so the fields this editor does not own — the disposal block, the
      // recurring link, the fan-out's source line — travel across untouched rather than being nulled by
      // a save that never asked about them.
      final existing = current.isEditing ? await repository.byId(id) : null;
      final saved = await repository.save(
        current.toAsset(
          newId: id,
          normalizedName: ref
              .read(normalizerProvider)
              .normalize(current.name.trim()),
          existing: existing,
        ),
      );
      final failure = saved.failureOrNull;
      if (failure != null) {
        _edit(
          (s) => s.copyWith(
            issue: AssetSaveIssue.rejected,
            rejection: failure.message,
          ),
          keepIssue: true,
        );
        return null;
      }
      _edit((s) => s.copyWith(dirty: false));
      return id;
    } on Object catch (error, stack) {
      ref
          .read(loggerProvider)
          .log(
            'Asset save failed',
            level: LogLevel.error,
            tag: 'service.assetEditor',
            error: error,
            stackTrace: stack,
          );
      _edit(
        (s) => s.copyWith(
          issue: AssetSaveIssue.rejected,
          rejection: error.toString(),
        ),
        keepIssue: true,
      );
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false), keepIssue: true);
    }
  }
}
