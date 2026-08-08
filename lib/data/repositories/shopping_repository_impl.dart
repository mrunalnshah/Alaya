import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/item_dao.dart';
import 'package:alaya/data/daos/shopping_entry_dao.dart';
import 'package:alaya/data/daos/shopping_list_dao.dart';
import 'package:alaya/data/daos/transaction_line_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/mappers/shopping_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/repositories/shopping_repository.dart';

/// `ShoppingRepository` backed by `ShoppingListDao` and `ShoppingEntryDao`.
final class ShoppingRepositoryImpl implements ShoppingRepository {
  /// Creates the repository.
  const ShoppingRepositoryImpl(
    this._listDao,
    this._entryDao,
    this._itemDao,
    this._lineDao,
    this._categories,
    this._settings,
    this._uids,
    this._clock,
  );

  final ShoppingListDao _listDao;
  final ShoppingEntryDao _entryDao;
  final ItemDao _itemDao;
  final TransactionLineDao _lineDao;
  final ItemCategoryResolver _categories;
  final SettingsRepository _settings;
  final UidGenerator _uids;
  final Clock _clock;

  // ── lists ─────────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<ShoppingList>> watchSelectableLists() => _listDao
      .watchSelectable()
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<ShoppingList>> watchAllLists() => _listDao
      .watchAllIncludingArchived()
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<ShoppingList?> watchDefaultList() =>
      _listDao.watchDefault().map((row) => row?.toEntity());

  @override
  Future<ShoppingList?> listById(String id) async =>
      (await _listDao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Future<Result<ShoppingList, Failure>> saveList(ShoppingList list) async {
    if (list.name.trim().isEmpty) {
      return const Result.failure(
        ValidationFailure('A shopping list needs a name.', field: 'name'),
      );
    }

    final existing = await _listDao.byIdIncludingDeleted(list.id);
    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _listDao.upsert(
      shoppingListToCompanion(
        list,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );

    // `isDefault` carries no database-level uniqueness constraint, so setting it through a plain
    // upsert would leave two lists flagged. The DAO's setDefault clears every other list's flag in
    // the same transaction; routing through it keeps "exactly one default" true in practice.
    if (list.isDefault && existing?.isDefault != true) {
      await _listDao.setDefault(id: list.id, nowUtcMillis: stamps.updatedAt);
    }
    return Result.ok(list);
  }

  @override
  Future<Result<void, Failure>> setDefaultList(String id) async {
    final list = await _listDao.byIdIncludingDeleted(id);
    if (list == null || list.deletedAt != null) {
      return Result.failure(
        NotFoundFailure('Shopping list not found.', id: id),
      );
    }
    if (list.isArchived) {
      return const Result.failure(
        BusinessRuleFailure(
          'An archived list cannot be the default — unarchive it first.',
          rule: 'archivedCannotBeDefault',
        ),
      );
    }
    await _listDao.setDefault(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> setListArchived({
    required String id,
    required bool isArchived,
  }) async {
    final list = await _listDao.byIdIncludingDeleted(id);
    if (list == null || list.deletedAt != null) {
      return Result.failure(
        NotFoundFailure('Shopping list not found.', id: id),
      );
    }
    if (isArchived && list.isDefault) {
      // Archiving the default would leave quick-add with nowhere to write, silently. Refusing
      // makes the user pick a new default first, which is the decision they actually need to make.
      return const Result.failure(
        BusinessRuleFailure(
          'This is the default list. Make another list the default before archiving it.',
          rule: 'cannotArchiveDefaultList',
        ),
      );
    }
    await _listDao.setArchived(
      id: id,
      isArchived: isArchived,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> deleteList(String id) async {
    // Cascades to the list's entries inside one transaction, in the DAO.
    await _listDao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  // ── entries ───────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<ShoppingEntry>> watchEntries(String listId) =>
      _entryDao.watchForList(listId).asyncMap(_mapEntries);

  @override
  Stream<List<ShoppingEntry>> watchUncheckedEntries(String listId) =>
      _entryDao.watchUncheckedForList(listId).asyncMap(_mapEntries);

  @override
  Future<Result<ShoppingEntry, Failure>> saveEntry(ShoppingEntry entry) async {
    // An entry names a catalogued item OR carries free text — never neither, or the row renders as
    // a blank line nobody can act on (anomaly A24 is about allowing free text, not about allowing
    // nothing).
    final hasItem = entry.itemId != null;
    final hasText = entry.freeText != null && entry.freeText!.trim().isNotEmpty;
    if (!hasItem && !hasText) {
      return const Result.failure(
        ValidationFailure(
          'A shopping entry needs either an item or some text.',
          field: 'freeText',
        ),
      );
    }

    if (hasItem) {
      final item = await _itemDao.byIdIncludingDeleted(entry.itemId!);
      if (item == null) {
        return Result.failure(
          NotFoundFailure('Item not found.', id: entry.itemId!),
        );
      }
      final quantity = entry.quantity;
      if (quantity != null && quantity.category != item.unitCategory) {
        // A quantity in the wrong category would be stored as a bare integer and reinterpreted on
        // read as the item's own category — 2 pieces becoming 2 grams (Law L8).
        return Result.failure(
          ValidationFailure(
            'This entry is measured in ${quantity.category.name} but the item is measured in '
            '${item.unitCategory.name}.',
            field: 'quantity',
          ),
        );
      }
    }

    final existing = await _entryDao.byIdIncludingDeleted(entry.id);
    final now = _clock.nowUtcMillis();

    // Editing an auto-generated entry promotes it to `manual`, after which the suggestion engine
    // never touches it again (anomaly A22). Detected by comparing against the stored row rather
    // than trusting the incoming entity's own `origin`: a UI that round-trips an entity would
    // otherwise have to remember to flip the flag itself, and forgetting would let regeneration
    // silently overwrite the user's edit.
    final wasAuto =
        existing != null && existing.origin == ShoppingEntryOrigin.autoLowStock;
    final effectiveOrigin = wasAuto ? ShoppingEntryOrigin.manual : entry.origin;

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    final promoted = entry.copyWith(origin: effectiveOrigin);
    await _entryDao.upsert(
      shoppingEntryToCompanion(
        promoted,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    if (wasAuto) {
      // Belt and braces: the companion already carries `manual`, but routing through the DAO's own
      // promote method means the transition is expressed in one place if it ever grows.
      await _entryDao.promoteToManual(id: entry.id, nowUtcMillis: now);
    }
    return Result.ok(promoted);
  }

  @override
  Future<Result<void, Failure>> setEntryChecked({
    required String id,
    required bool isChecked,
  }) async {
    await _entryDao.setChecked(
      id: id,
      isChecked: isChecked,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> snoozeEntry({
    required String id,
    required DateKey until,
  }) async {
    final stock = await _stockAtDecisionMilli(id);
    if (stock == null) {
      return Result.failure(
        NotFoundFailure('Shopping entry not found.', id: id),
      );
    }
    await _entryDao.setAutoState(
      id: id,
      autoState: ShoppingEntryAutoState.snoozed,
      stockAtDecisionMilli: stock,
      snoozeUntil: until,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> dismissEntry(String id) async {
    final stock = await _stockAtDecisionMilli(id);
    if (stock == null) {
      return Result.failure(
        NotFoundFailure('Shopping entry not found.', id: id),
      );
    }
    // Records the stock level at the moment of dismissal alongside the state. A dismissal that
    // stored only the flag would never come back — but one that came back on a timer would nag.
    // Storing the reading means the suggestion returns exactly when stock has genuinely risen
    // above the threshold and fallen below it again (anomaly A23).
    await _entryDao.setAutoState(
      id: id,
      autoState: ShoppingEntryAutoState.dismissed,
      stockAtDecisionMilli: stock,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> reorderEntries(List<String> orderedIds) async {
    await _entryDao.reorder(
      orderedIds: orderedIds,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> deleteEntry(String id) async {
    await _entryDao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  // ── the suggestion engine ─────────────────────────────────────────────────────────────

  @override
  Future<Result<int, Failure>> regenerateLowStockSuggestions(
    String listId,
  ) async {
    final list = await _listDao.byIdIncludingDeleted(listId);
    if (list == null || list.deletedAt != null) {
      return Result.failure(
        NotFoundFailure('Shopping list not found.', id: listId),
      );
    }

    final lowStock = await _itemDao.watchLowStock().first;
    final existingAuto = await _entryDao
        .watchActiveAutoSuggestions(listId)
        .first;
    var sortOrder = existingAuto.length;
    var active = 0;

    for (final row in lowStock) {
      final threshold = row.lowStockThresholdMilli;
      if (threshold == null) continue;
      final shortfall = threshold - row.totalRemainingMilli;
      if (shortfall <= 0) continue;

      final existing = await _entryDao.findAutoEntry(
        listId: listId,
        itemId: row.itemId,
      );

      // A dismissed or snoozed suggestion stays suppressed until stock has recovered past the
      // reading taken when the user dismissed it. Comparing against `generatedAtStockMilli` rather
      // than against the threshold is what distinguishes "still the same shortage they already
      // said no to" from "they bought some and ran out again" (anomaly A23).
      if (existing != null &&
          existing.autoState != ShoppingEntryAutoState.active) {
        final atDecision = existing.generatedAtStockMilli;
        final recovered =
            atDecision != null && row.totalRemainingMilli > atDecision;
        if (!recovered) continue;
      }

      // Idempotent by construction: `idx_shopping_auto` makes
      // `(listId, itemId, origin='autoLowStock')` unique among live rows, and the DAO's
      // read-then-write honours it — a partial index cannot be an `ON CONFLICT` target, which is
      // why this is not a plain upsert (see the DAO's own note).
      await _entryDao.upsertAutoEntry(
        newId: _uids.generate(),
        listId: listId,
        itemId: row.itemId,
        unitCode: await _itemUnitCode(row.itemId),
        quantityMilli: shortfall,
        stockAtGenerationMilli: row.totalRemainingMilli,
        sortOrder: sortOrder++,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      active++;
    }
    return Result.ok(active);
  }

  // ── closing the loop back to money ────────────────────────────────────────────────────

  @override
  Future<Result<List<TransactionLine>, Failure>> buildPurchaseDraft(
    String listId,
  ) async {
    // Mapped to entities first, deliberately. Building drafts straight off `ShoppingEntryRow`
    // means hand-assembling a `Qty` from `quantityMilli` and a `Money` from
    // `estimatedPriceMinor` — re-deriving, at a second site, the category and currency resolution
    // that `_mapEntries` already does correctly.
    final entries = await _mapEntries(
      await _entryDao.watchForList(listId).first,
    );
    final checked = entries
        .where((e) => e.isChecked && e.purchasedTransactionLineId == null)
        .toList();
    if (checked.isEmpty) {
      return const Result.failure(
        BusinessRuleFailure(
          'Nothing on this list is ticked off yet.',
          rule: 'nothingToPurchase',
        ),
      );
    }

    // Drafts only — nothing is written here. The user still confirms the amount and account in the
    // expense editor, and `TransactionRepository.create` is what commits. `transactionId` is left
    // empty deliberately: the transaction does not exist yet, and inventing an id here would let a
    // caller persist a line pointing at nothing.
    final drafts = <TransactionLine>[];
    var lineNo = 1;
    for (final entry in checked) {
      final itemId = entry.itemId;
      drafts.add(
        TransactionLine(
          id: _uids.generate(),
          transactionId: '',
          lineNo: lineNo++,
          description: entry.freeText ?? await _itemName(itemId) ?? 'Item',
          // A catalogued item becomes stock on purchase; free text has nowhere to land, so it
          // stays a plain expense line (ARCH_2 §4.2's `destination` is what removes that
          // ambiguity — anomaly A12).
          destination: itemId != null
              ? TransactionLineDestination.inventory
              : TransactionLineDestination.none,
          itemId: itemId,
          quantity: entry.quantity,
          // Falls back to the item's own display unit. An auto-generated low-stock suggestion is
          // written without one — nothing asked the user — and a line bound for inventory with no
          // unit cannot become a batch, because the column is a foreign key into `units`.
          unitCode: entry.unitCode ?? await _itemUnitCode(itemId),
          lineAmount: entry.estimatedPrice,
        ),
      );
    }
    return Result.ok(drafts);
  }

  @override
  Future<Result<void, Failure>> markPurchased({
    required List<String> entryIds,
    required String transactionId,
  }) async {
    final lines = await _lineDao.forTransaction(transactionId);
    if (lines.isEmpty) {
      return Result.failure(
        NotFoundFailure(
          'That transaction has no lines to link.',
          id: transactionId,
        ),
      );
    }

    // The contract hands over a transaction id, but an entry links to one specific *line*
    // (anomaly A25 — knowing which line fulfilled it is what lets the UI show the price paid).
    // Matching is by `itemId`, since `buildPurchaseDraft` built each line from an entry and
    // carried that id across; free-text entries fall back to matching the description.
    final byItemId = <String, String>{};
    final byDescription = <String, String>{};
    for (final line in lines) {
      final itemId = line.itemId;
      if (itemId != null) {
        byItemId.putIfAbsent(itemId, () => line.id);
      } else {
        byDescription.putIfAbsent(
          line.description.trim().toLowerCase(),
          () => line.id,
        );
      }
    }

    final now = _clock.nowUtcMillis();
    final unmatched = <String>[];
    for (final entryId in entryIds) {
      final entry = await _entryDao.byIdIncludingDeleted(entryId);
      if (entry == null) {
        unmatched.add(entryId);
        continue;
      }
      final lineId = entry.itemId != null
          ? byItemId[entry.itemId]
          : byDescription[(entry.freeText ?? '').trim().toLowerCase()];
      if (lineId == null) {
        unmatched.add(entryId);
        continue;
      }
      await _entryDao.markPurchased(
        id: entryId,
        transactionLineId: lineId,
        nowUtcMillis: now,
      );
    }

    if (unmatched.isNotEmpty) {
      // Reported rather than swallowed: the entries that *did* match are already linked, and
      // silently dropping the rest would leave the user's list half-updated with no explanation.
      return Result.failure(
        BusinessRuleFailure(
          '${unmatched.length} of ${entryIds.length} entries had no matching line in that '
          'transaction and were left unticked.',
          rule: 'entryLineMismatch',
        ),
      );
    }
    return const Result.ok(null);
  }

  /// The item's current total stock in base-milli units, for recording alongside a snooze or
  /// dismissal. Returns 0 for a free-text entry, which has no stock to read.
  Future<int?> _stockAtDecisionMilli(String entryId) async {
    final entry = await _entryDao.byIdIncludingDeleted(entryId);
    if (entry == null) return null;
    final itemId = entry.itemId;
    if (itemId == null) return 0;
    final stock = await _itemDao.stockOf(itemId);
    return stock?.totalRemainingMilli ?? 0;
  }

  /// The display unit code of [itemId], or null when there is no item.
  Future<String?> _itemUnitCode(String? itemId) async {
    if (itemId == null) return null;
    final item = await _itemDao.byIdIncludingDeleted(itemId);
    return item?.defaultDisplayUnitCode;
  }

  Future<String?> _itemName(String? itemId) async {
    if (itemId == null) return null;
    final row = await _itemDao.byIdIncludingDeleted(itemId);
    return row?.name;
  }

  Future<List<ShoppingEntry>> _mapEntries(List<ShoppingEntryRow> rows) async {
    final categories = await _categories.categoriesFor(
      rows.map((r) => r.itemId).whereType<String>(),
    );
    final homeCurrencyCode = await _homeCurrencyCode();
    return rows
        .map(
          (r) => r.toEntity(
            category: r.itemId == null ? null : categories[r.itemId],
            homeCurrencyCode: homeCurrencyCode,
          ),
        )
        .toList();
  }

  /// The user's home currency, for reading an entry's estimated price.
  ///
  /// Falls back to `INR` only if the seeded setting is somehow absent — Phase 1C always writes it,
  /// so this is defensive rather than an expected path.
  Future<String> _homeCurrencyCode() async =>
      await _settings.readHomeCurrencyCode() ?? 'INR';
}
