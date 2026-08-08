import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/data/daos/item_dao.dart';

/// Resolves an item's [UnitCategory], which every batch, movement and shopping quantity needs but
/// no batch, movement or entry row carries.
///
/// Lives in its own file because three repositories use it — `BatchRepositoryImpl`,
/// `StockRepositoryImpl` and `ShoppingRepositoryImpl`. Leaving it inside
/// `batch_repository_impl.dart` forced the other two to import another repository's
/// *implementation* file just to reach a shared helper: the same coupling `settings_keys.dart`
/// was extracted to avoid in Phase 3B. Nothing here touches Law L12 — all three are `data/` — so
/// it is a design smell rather than a violation, but the fix is cheap and the precedent is set.
final class ItemCategoryResolver {
  /// Creates a resolver over [itemDao].
  ItemCategoryResolver(this._itemDao);

  final ItemDao _itemDao;
  final Map<String, UnitCategory> _cache = {};

  /// The category for [itemId], or null when no such item exists.
  ///
  /// Cached per instance. An item's category is immutable once created (Law L8), so a cached value
  /// can never go stale — which is precisely what makes caching safe here rather than a risk.
  Future<UnitCategory?> categoryOf(String itemId) async {
    final cached = _cache[itemId];
    if (cached != null) return cached;

    final row = await _itemDao.byIdIncludingDeleted(itemId);
    if (row == null) return null;
    _cache[itemId] = row.unitCategory;
    return row.unitCategory;
  }

  /// Resolves categories for [itemIds] in one pass, for mapping a list of rows.
  Future<Map<String, UnitCategory>> categoriesFor(Iterable<String> itemIds) async {
    final result = <String, UnitCategory>{};
    for (final id in itemIds.toSet()) {
      final category = await categoryOf(id);
      if (category != null) result[id] = category;
    }
    return result;
  }
}