/// View-model state for the item editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/state/item_editor_state.dart';

/// The units available in one category.
///
/// Category-filtered, always. Law L8 says cross-category conversion does not exist, so offering
/// `ml` for an item measured by weight would present a choice the domain cannot honour.
final unitsInCategoryProvider = StreamProvider.autoDispose
    .family<List<Unit>, UnitCategory>(
      (ref, category) =>
          ref.watch(unitRepositoryProvider).watchByCategory(category),
    );

/// The editor for one item, or for a new one when the argument is null.
final itemEditorProvider = NotifierProvider.autoDispose
    .family<ItemEditorNotifier, AsyncValue<ItemEditorState>, String?>(
      ItemEditorNotifier.new,
    );

/// Loads, edits and saves one item.
class ItemEditorNotifier
    extends AutoDisposeFamilyNotifier<AsyncValue<ItemEditorState>, String?> {
  @override
  AsyncValue<ItemEditorState> build(String? arg) {
    // **A new item starts populated, not loading.** `_load` assigned `state` with no `await` before
    // it, which means it ran *during* `build` — Riverpod refuses that, the assignment was lost or
    // threw, and the screen sat on its skeleton with no form and no error. There is also nothing to
    // fetch for a blank item, so pretending to load was wrong twice over.
    if (arg == null) {
      return const AsyncValue.data(
        ItemEditorState(
          unitCategory: UnitCategory.count,
          displayUnitCode: 'pc',
        ),
      );
    }
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(String id) async {
    try {
      final item = await ref.read(itemRepositoryProvider).byId(id);
      if (item == null) {
        state = AsyncValue.error(
          StateError('Item $id not found.'),
          StackTrace.current,
        );
        return;
      }
      state = AsyncValue.data(ItemEditorState.fromItem(item));
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _edit(ItemEditorState Function(ItemEditorState) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(change(current));
  }

  /// Sets the name.
  void setName(String name) => _edit(
    (s) => s.copyWith(name: name, nameMissing: false, clearIssue: true),
  );

  /// Sets how this item is measured, and resets the display unit to that category's base.
  ///
  /// **Only callable while creating.** Law L8 makes the category immutable once saved, so the editor
  /// hides the control on edit and this method refuses the change rather than trusting it not to be
  /// called — a guard on the state is worth more than a guard on the widget.
  void setCategory(UnitCategory category, String baseUnitCode) => _edit(
    (s) => s.isEditing
        ? s
        : ItemEditorState(
            id: s.id,
            name: s.name,
            unitCategory: category,
            displayUnitCode: baseUnitCode,
            thresholdUnitCode: baseUnitCode,
            itemKind: s.itemKind,
            isFavorite: s.isFavorite,
            expiryNotifyDays: s.expiryNotifyDays,
            notes: s.notes,
            dirty: true,
          ),
  );

  /// Sets the unit quantities are displayed in.
  void setDisplayUnit(Unit unit) =>
      _edit((s) => s.copyWith(displayUnitCode: unit.code));

  /// Sets the unit the low-stock threshold is being entered in.
  void setThresholdUnit(Unit unit) =>
      _edit((s) => s.copyWith(thresholdUnitCode: unit.code));

  /// Sets what sort of thing this is.
  void setKind(ItemKind kind) => _edit((s) => s.copyWith(itemKind: kind));

  /// Stars or unstars it.
  void toggleFavourite() => _edit((s) => s.copyWith(isFavorite: !s.isFavorite));

  /// Sets the level below which the `low` chip appears.
  void setThreshold(Qty? threshold) => _edit(
    (s) => threshold == null
        ? s.copyWith(clearThreshold: true)
        : s.copyWith(lowStockThreshold: threshold),
  );

  /// Sets how many days of expiry warning Phase 8B should give.
  void setExpiryNotifyDays(int? days) => _edit(
    (s) => days == null
        ? s.copyWith(clearNotifyDays: true)
        : s.copyWith(expiryNotifyDays: days),
  );

  /// Sets the free notes.
  void setNotes(String notes) => _edit((s) => s.copyWith(notes: notes));

  /// Saves the item, returning its id on success and null on rejection or failure.
  ///
  /// **Every refusal is named before the database gets a chance to refuse it.** `items` carries a
  /// partial unique index on `(normalized_name, unit_category)` and `default_display_unit_code`
  /// references `units`, so a blind write can fail two ways that look identical to the user. Checking
  /// first turns "something went wrong" into a sentence they can act on — and the duplicate case
  /// hands back the id of the item they already have, so the editor can offer to open it.
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.name.trim().isEmpty) {
      _edit(
        (s) => s.copyWith(nameMissing: true, shakeTrigger: s.shakeTrigger + 1),
      );
      return null;
    }

    _edit((s) => s.copyWith(submitting: true, clearIssue: true));
    try {
      final repository = ref.read(itemRepositoryProvider);
      final normalized = ref
          .read(normalizerProvider)
          .normalize(current.name.trim());

      final clash = await repository.findByIdentity(
        normalizedName: normalized,
        unitCategory: current.unitCategory,
      );
      if (clash != null && clash.id != current.id) {
        _edit(
          (s) => s.copyWith(
            issue: ItemSaveIssue.duplicate,
            conflictItemId: clash.id,
          ),
        );
        return null;
      }

      // The display unit is a foreign key. Resolving it against the units that actually exist keeps a
      // thinly-seeded category from failing as an opaque constraint error.
      final units = await ref
          .read(unitRepositoryProvider)
          .watchByCategory(current.unitCategory)
          .first;
      if (units.isEmpty) {
        _edit((s) => s.copyWith(issue: ItemSaveIssue.unitsMissing));
        return null;
      }
      final displayUnit =
          units.any((unit) => unit.code == current.displayUnitCode)
          ? current.displayUnitCode
          : units.first.code;

      final id = current.id ?? ref.read(uidGeneratorProvider).generate();
      final saved = await repository.save(
        current
            .copyWith(displayUnitCode: displayUnit)
            .toItem(
              newId: id,
              normalizedName: normalized,
            ),
      );
      if (saved.isFailure) {
        _edit((s) => s.copyWith(issue: ItemSaveIssue.unknown));
        return null;
      }
      _edit((s) => s.copyWith(dirty: false));
      return id;
    } on Object catch (error, stack) {
      ref
          .read(loggerProvider)
          .log(
            'Item save failed',
            level: LogLevel.error,
            tag: 'inventory.itemEditor',
            error: error,
            stackTrace: stack,
          );
      _edit((s) => s.copyWith(issue: ItemSaveIssue.unknown));
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false));
    }
  }

  /// Looks up items sharing this name under a different measure, for the informational note.
  Future<void> refreshSimilar() async {
    final current = state.valueOrNull;
    if (current == null || current.name.trim().isEmpty) return;
    final similar = await ref
        .read(itemRepositoryProvider)
        .findSimilar(
          name: current.name.trim(),
          unitCategory: current.unitCategory,
        );
    _edit(
      (s) => s.copyWith(
        similarInOtherMeasures: [
          for (final item in similar)
            if (item.id != current.id &&
                item.unitCategory != current.unitCategory)
              item,
        ],
        dirty: s.dirty,
      ),
    );
  }
}
