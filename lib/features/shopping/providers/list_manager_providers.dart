/// View-model state for the shopping list manager (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/shopping_list.dart';

/// Writes the list manager performs.
final listManagerActionsProvider = Provider<ListManagerActions>(
  ListManagerActions.new,
);

/// Creates, renames, archives and re-points shopping lists.
///
/// Every method reports the failure's own message rather than a generic one, so a rejected write
/// says what the database actually refused.
class ListManagerActions {
  /// Creates the actions.
  ListManagerActions(this._ref);

  final Ref _ref;

  /// Creates a list, returning its id on success.
  ///
  /// The first list a user creates becomes the default, because a shopping module with no default
  /// list has nowhere to open and nowhere to put a low-stock suggestion.
  Future<({String? id, String? error})> create(
    String name, {
    required bool isFirst,
  }) async {
    final id = _ref.read(uidGeneratorProvider).generate();
    final saved = await _ref
        .read(shoppingRepositoryProvider)
        .saveList(
          ShoppingList(
            id: id,
            name: name.trim(),
            isDefault: isFirst,
            isArchived: false,
          ),
        );
    final failure = saved.failureOrNull;
    return failure == null
        ? (id: id, error: null)
        : (id: null, error: failure.message);
  }

  /// Renames a list.
  Future<String?> rename(ShoppingList list, String name) async {
    final saved = await _ref
        .read(shoppingRepositoryProvider)
        .saveList(list.copyWith(name: name.trim()));
    return saved.failureOrNull?.message;
  }

  /// Makes a list the one that opens by default.
  Future<String?> setDefault(String id) async {
    final result = await _ref
        .read(shoppingRepositoryProvider)
        .setDefaultList(id);
    return result.failureOrNull?.message;
  }

  /// Archives or restores a list.
  Future<String?> setArchived({
    required String id,
    required bool isArchived,
  }) async {
    final result = await _ref
        .read(shoppingRepositoryProvider)
        .setListArchived(id: id, isArchived: isArchived);
    return result.failureOrNull?.message;
  }
}
