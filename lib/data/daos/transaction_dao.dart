import 'package:drift/drift.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/date_key_filters.dart';

/// Typed access to `transactions`, its lines and tags, and the three views derived from them.
///
/// Every read here goes through `v_active_transactions`, `v_monthly_totals` or
/// `v_transaction_allocation` (Law L7) — the base table is touched only by writes and by the
/// `rowid` join full-text search needs.
class TransactionDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  TransactionDao(super.db);

  $TransactionsTable get _table => attachedDatabase.transactions;
  // Type inferred deliberately. The row class name is fixed by `AS ActiveTransactionRow`
  // in transaction_views.drift, but drift's name for a view's *table* class is not
  // something this file should assert; inference gets it right whatever it is called.
  late final _active = attachedDatabase.vActiveTransactions;

  // ── writes ────────────────────────────────────────────────────────────────────────────

  /// Inserts a transaction together with its lines and tags, atomically (Law L14).
  ///
  /// Three tables in one `transaction {}`. Without it a crash between statements would leave a
  /// transaction whose lines are missing — and `v_transaction_allocation` would then report the
  /// whole amount as unallocated, which looks exactly like a user who has not itemised yet.
  ///
  /// `monthKey` is *not* derived here. It is a required column on the companion and the schema's
  /// third CHECK constraint enforces `date_key / 100 = month_key`, so a caller that gets it wrong
  /// is rejected by the database rather than silently producing a transaction that is invisible to
  /// monthly analytics. Deriving it here would hide that error.
  Future<void> insertWithDetails({
    required TransactionsCompanion header,
    List<TransactionLinesCompanion> lines = const [],
    List<String> tagIds = const [],
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await into(_table).insert(header);
      for (final line in lines) {
        await into(attachedDatabase.transactionLines).insert(line);
      }
      for (final tagId in tagIds) {
        await into(attachedDatabase.transactionTags).insert(
          TransactionTagsCompanion.insert(
            transactionId: header.id.value,
            tagId: tagId,
            createdAt: nowUtcMillis,
            updatedAt: nowUtcMillis,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Updates a transaction's own columns. Lines and tags are replaced separately.
  Future<void> updateTransaction(TransactionsCompanion header) =>
      update(_table).replace(header);

  /// Soft-deletes a transaction and its lines, atomically (Law L14).
  ///
  /// Cascades to `transaction_lines` and nothing else. Batches and assets a line created are
  /// deliberately untouched: you deleted a receipt, not the groceries (anomaly A10). Detaching
  /// those artefacts is the repository's job, via
  /// [TransactionLineDao.clearCreatedArtefacts].
  ///
  /// `transaction_tags` links are left in place too — they carry no soft-delete column and the
  /// transaction they point at is already filtered out of every view.
  Future<void> softDelete({
    required String id,
    String? reason,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await (update(_table)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
          deleteReason: reason == null ? const Value.absent() : Value(reason),
        ),
      );
      await (update(attachedDatabase.transactionLines)
        ..where((t) => t.transactionId.equals(id) & t.deletedAt.isNull()))
          .write(
        TransactionLinesCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
    });
  }

  /// Clears `needsReview` once the user has filled in the details quick-add skipped.
  Future<void> markReviewed({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(needsReview: const Value(false), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Writes the frozen conversion snapshot for one transaction.
  ///
  /// Only ever writes the `converted*` columns. `originalAmountMinor` and
  /// `originalCurrencyCode` are immutable once saved (Law L9) and are not parameters here, so this
  /// method cannot rewrite them even by mistake.
  Future<void> freezeConversion({
    required String id,
    required int convertedAmountMinor,
    required String convertedCurrencyCode,
    required double conversionRate,
    required String conversionRateRaw,
    required DateKey conversionDateKey,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        convertedAmountMinor: Value(convertedAmountMinor),
        convertedCurrencyCode: Value(convertedCurrencyCode),
        conversionRate: Value(conversionRate),
        conversionRateRaw: Value(conversionRateRaw),
        conversionDateKey: Value(conversionDateKey),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  // ── reads: all through the views ──────────────────────────────────────────────────────

  /// Reads one active transaction by id.
  Future<ActiveTransactionRow?> byId(String id) =>
      (select(_active)..where((t) => t.txId.equals(id))).getSingleOrNull();

  /// Emits active transactions whose civil date falls in `[from, to]`, newest first.
  ///
  /// Inclusive at both ends, and always bounded so the query uses `idx_tx_date`.
  Stream<List<ActiveTransactionRow>> watchByDateRange({
    required DateKey from,
    required DateKey to,
  }) {
    return (select(_active)
      ..where((t) => t.dateKey.isInDateRange(from, to))
      ..orderBy([
            (t) => OrderingTerm(expression: t.dateKey, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc),
      ]))
        .watch();
  }

  /// Emits active transactions touching [accountId] on either side, newest first.
  ///
  /// Matches both `fromAccountId` and `toAccountId`, so a transfer appears in both accounts'
  /// lists — once as an outflow and once as an inflow, which is what the user expects to see.
  Stream<List<ActiveTransactionRow>> watchByAccount(String accountId) {
    return (select(_active)
      ..where((t) =>
      t.fromAccountId.equals(accountId) | t.toAccountId.equals(accountId))
      ..orderBy([
            (t) => OrderingTerm(expression: t.dateKey, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc),
      ]))
        .watch();
  }

  /// Emits active transactions of [subtype], newest first, optionally bounded by month.
  Stream<List<ActiveTransactionRow>> watchBySubtype(
      TransactionSubtype subtype, {
        int? fromMonthKey,
        int? toMonthKey,
      }) {
    final query = select(_active)..where((t) => t.subtype.equalsValue(subtype));
    if (fromMonthKey != null) {
      query.where((t) => t.monthKey.isBiggerOrEqualValue(fromMonthKey));
    }
    if (toMonthKey != null) {
      query.where((t) => t.monthKey.isSmallerOrEqualValue(toMonthKey));
    }
    query.orderBy([
          (t) => OrderingTerm(expression: t.dateKey, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  /// Emits active transactions still flagged `needsReview`, for the dashboard nudge.
  Stream<List<ActiveTransactionRow>> watchNeedingReview() {
    return (select(_active)
      ..where((t) => t.needsReview.equals(true))
      ..orderBy([(t) => OrderingTerm(expression: t.dateKey, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Emits the count of transactions needing review.
  Stream<int> watchNeedsReviewCount() {
    final count = countAll();
    return (selectOnly(_active)
      ..addColumns([count])
      ..where(_active.needsReview.equals(true)))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }

  /// Emits `(monthKey, kind, currencyCode) -> (sumMinor, txCount)` from `v_monthly_totals`.
  ///
  /// Grouped by currency, so nothing here can add rupees to yen (anomaly A34) — conversion to the
  /// home currency happens per data point in the currency service, above this layer.
  Stream<List<MonthlyTotalRow>> watchMonthlyTotals({
    int? fromMonthKey,
    int? toMonthKey,
  }) {
    final view = attachedDatabase.vMonthlyTotals;
    final query = select(view);
    if (fromMonthKey != null) {
      query.where((t) => t.monthKey.isBiggerOrEqualValue(fromMonthKey));
    }
    if (toMonthKey != null) {
      query.where((t) => t.monthKey.isSmallerOrEqualValue(toMonthKey));
    }
    query.orderBy([(t) => OrderingTerm(expression: t.monthKey, mode: OrderingMode.desc)]);
    return query.watch();
  }

  /// Reads the monthly totals once.
  Future<List<MonthlyTotalRow>> monthlyTotals({int? fromMonthKey, int? toMonthKey}) {
    final view = attachedDatabase.vMonthlyTotals;
    final query = select(view);
    if (fromMonthKey != null) {
      query.where((t) => t.monthKey.isBiggerOrEqualValue(fromMonthKey));
    }
    if (toMonthKey != null) {
      query.where((t) => t.monthKey.isSmallerOrEqualValue(toMonthKey));
    }
    query.orderBy([(t) => OrderingTerm(expression: t.monthKey, mode: OrderingMode.desc)]);
    return query.get();
  }

  // ── full-text search ──────────────────────────────────────────────────────────────────

  /// Full-text search over transaction notes, best match first.
  ///
  /// Two steps by design. FTS5 returns `rowid`s ranked by relevance, so the first query resolves
  /// those to transaction ids and the second reads the matching rows from `v_active_transactions`
  /// — which is what keeps soft-deleted transactions out of the results, since the FTS index knows
  /// nothing about `deletedAt`. Rank order is then restored in Dart, because a typed `WHERE id IN
  /// (...)` cannot preserve it.
  Future<List<ActiveTransactionRow>> search(String query, {int limit = 50}) async {
    final ids = await searchIds(query, limit: limit);
    if (ids.isEmpty) return const [];

    final rows = await (select(_active)..where((t) => t.txId.isIn(ids))).get();
    final byId = {for (final row in rows) row.txId: row};
    return [
      for (final id in ids)
        if (byId[id] case final row?) row,
    ];
  }

  /// The ranked transaction ids matching [query], most relevant first.
  ///
  /// Returns an empty list for input with no usable characters rather than running a MATCH that
  /// would throw — see [_toFtsMatchQuery].
  Future<List<String>> searchIds(String query, {int limit = 50}) async {
    final match = _toFtsMatchQuery(query);
    if (match == null) return const [];

    final rows = await customSelect(
      'SELECT base.id AS id FROM transactions_fts f '
          'JOIN transactions base ON base.rowid = f.rowid '
          'WHERE transactions_fts MATCH ? AND base.deleted_at IS NULL '
          'ORDER BY rank LIMIT ?',
      variables: [Variable<String>(match), Variable<int>(limit)],
      readsFrom: {_table},
    ).get();
    return rows.map((row) => row.read<String>('id')).toList();
  }

  /// Turns raw user input into a safe FTS5 MATCH expression, or null if nothing is searchable.
  ///
  /// Necessary rather than defensive. FTS5's MATCH grammar treats `"`, `*`, `:`, `^`, `-`, `(`,
  /// `)` and the bare words `AND`/`OR`/`NOT`/`NEAR` as syntax, so raw input raises a syntax error
  /// inside what the user thinks is a search box. Verified against a real FTS5 index: `rent (July)
  /// - paid`, `AND` and `foo"bar` all throw unescaped, and `***` fails with "unknown special
  /// query". Each run of letters, digits and combining marks becomes one double-quoted term with a
  /// trailing `*` for prefix matching, space-joined, which FTS5 reads as implicit AND.
  ///
  /// `\p{M}` matters as much as `\p{L}` here. Devanagari and Gujarati vowel signs are Unicode
  /// category M, not L, so `[\p{L}\p{N}]+` alone splits `टमाटर` into `टम` and `टर` — search would
  /// quietly stop working for exactly the languages this app's first users type in. Same bug class
  /// as the one fixed in Phase 1A's `Normalizer`.
  String? _toFtsMatchQuery(String raw) {
    final tokens = RegExp(r'[\p{L}\p{N}\p{M}]+', unicode: true)
        .allMatches(raw)
        .map((m) => m.group(0)!)
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;
    return tokens.map((t) => '"$t"*').join(' ');
  }
}
