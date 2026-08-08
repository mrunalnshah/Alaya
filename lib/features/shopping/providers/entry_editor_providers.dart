/// View-model state for the shopping entry editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/shopping/state/entry_editor_state.dart';

/// Which entry an editor is pointed at. A record, so the family argument has structural equality.
typedef EntryEditorArgs = ({String listId, String? entryId});

/// Items offered for linking, so an entry can restock something the inventory tracks.
final entryItemsProvider = StreamProvider.autoDispose<List<Item>>(
  (ref) => ref.watch(itemRepositoryProvider).watchAll(),
);

/// Tags scoped to shopping, which is what groups the list into aisles.
final entryTagsProvider = StreamProvider.autoDispose<List<Tag>>(
  (ref) => ref.watch(tagRepositoryProvider).watchByScope(TagScope.shopping),
);

/// Units in one category, so a linked item never offers a cross-category unit (Law L8).
final entryUnitsProvider = StreamProvider.autoDispose
    .family<List<Unit>, UnitCategory?>(
      (ref, category) => category == null
          ? Stream.value(const <Unit>[])
          : ref.watch(unitRepositoryProvider).watchByCategory(category),
    );

/// The home currency, so an estimate is never denominated in a guess.
final entryCurrencyProvider = FutureProvider.autoDispose<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      'INR',
);

/// The home currency's decimal digits (ARCH_1 §4.1).
final entryDecimalDigitsProvider = FutureProvider.autoDispose<int>((ref) async {
  final code = await ref.watch(entryCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// The editor for one entry, or for a new one when `entryId` is null.
final entryEditorProvider = NotifierProvider.autoDispose
    .family<EntryEditorNotifier, AsyncValue<EntryEditorState>, EntryEditorArgs>(
      EntryEditorNotifier.new,
    );

/// Loads, edits and saves one shopping entry.
class EntryEditorNotifier
    extends
        AutoDisposeFamilyNotifier<
          AsyncValue<EntryEditorState>,
          EntryEditorArgs
        > {
  @override
  AsyncValue<EntryEditorState> build(EntryEditorArgs arg) {
    // A new entry needs nothing fetched, so it starts populated rather than flashing a skeleton —
    // and assigning state from an async gap inside `build` is what Riverpod refuses.
    if (arg.entryId == null) {
      return AsyncValue.data(EntryEditorState(listId: arg.listId));
    }
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(EntryEditorArgs arg) async {
    try {
      final entries = await ref
          .read(shoppingRepositoryProvider)
          .watchEntries(arg.listId)
          .first;
      for (final entry in entries) {
        if (entry.id != arg.entryId) continue;
        state = AsyncValue.data(EntryEditorState.fromEntry(entry));
        return;
      }
      state = AsyncValue.error(
        StateError('Entry ${arg.entryId} not found.'),
        StackTrace.current,
      );
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _edit(EntryEditorState Function(EntryEditorState) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(change(current));
  }

  /// Sets what to buy, in the user's words.
  void setFreeText(String text) =>
      _edit((s) => s.copyWith(freeText: text, identityMissing: false));

  /// Links the entry to a catalogued item, or unlinks it.
  ///
  /// Linking seeds the name and the unit from the item, because the receipt almost always says the
  /// item's name and retyping it is friction with no purpose. An edit of the user's own is never
  /// overwritten.
  void setItem(Item? item) => _edit((s) {
    if (item == null) return s.copyWith(clearItem: true, clearQuantity: true);
    final typed = s.freeText.trim();
    return s.copyWith(
      itemId: item.id,
      freeText: typed.isEmpty ? item.name : s.freeText,
      unitCode: item.defaultDisplayUnitCode,
      identityMissing: false,
      clearQuantity: true,
    );
  });

  /// Sets how much to buy.
  void setQuantity(Qty? quantity) => _edit(
    (s) => quantity == null
        ? s.copyWith(clearQuantity: true)
        : s.copyWith(quantity: quantity),
  );

  /// Sets the unit the quantity is entered in.
  void setUnitCode(String code) => _edit((s) => s.copyWith(unitCode: code));

  /// Sets the aisle-ish grouping.
  void setTag(String? tagId) => _edit(
    (s) =>
        tagId == null ? s.copyWith(clearTag: true) : s.copyWith(tagId: tagId),
  );

  /// Sets what the user expects it to cost.
  void setEstimatedPrice(Money? price) => _edit(
    (s) => price == null
        ? s.copyWith(clearPrice: true)
        : s.copyWith(estimatedPrice: price),
  );

  /// Saves the entry, returning its id on success and null on rejection or failure.
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (!current.hasIdentity) {
      _edit(
        (s) =>
            s.copyWith(identityMissing: true, shakeTrigger: s.shakeTrigger + 1),
      );
      return null;
    }

    _edit((s) => s.copyWith(submitting: true));
    try {
      final id = current.id ?? ref.read(uidGeneratorProvider).generate();
      final saved = await ref
          .read(shoppingRepositoryProvider)
          .saveEntry(current.toEntry(newId: id));
      if (saved.isFailure) return null;
      _edit((s) => s.copyWith(dirty: false));
      return id;
    } on Object catch (error, stack) {
      ref
          .read(loggerProvider)
          .log(
            'Shopping entry save failed',
            level: LogLevel.error,
            tag: 'shopping.entryEditor',
            error: error,
            stackTrace: stack,
          );
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false));
    }
  }
}
