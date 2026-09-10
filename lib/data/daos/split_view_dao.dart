import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Reads the four split views: the module's whole derived read model.
///
/// **Separate from `SplitDao` on purpose**, the same separation `CalendarDao` has from the tables its
/// view unions. Law L7 says repositories read views, and a single DAO exposing both the tables and
/// the views would make reaching for the wrong one a matter of autocomplete.
///
/// **Nothing here is stored (Law L3).** Every figure these views return is recomputed from shares and
/// settlements on each read, which is why a balance in this module cannot drift — there is nowhere
/// for it to drift from. It is also why the balance reads are unbounded while the expense and
/// activity reads are not: a balance list is one row per counterparty and stays small forever, but
/// expenses accumulate.
///
/// **No view here consults the clock** (ARCH_2 §12.2), so `oldest_unsettled_date_key` arrives as a
/// plain date and the ageing that the notification digest wants — *"owed for three weeks"* — is
/// computed in Dart against the injected `Clock`. A view containing `now` could not be asserted
/// against a `FixedClock`.
class SplitViewDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  SplitViewDao(super.db);

  // ── expenses ────────────────────────────────────────────────────────────────────────────

  /// Emits expense summaries in `[fromDateKey, toDateKey]`, newest first.
  ///
  /// **Bounded, like every `CalendarDao` read.** Unbounded, this scans every expense and its shares;
  /// bounded on `date_key`, it uses `idx_split_exp_date`. There is deliberately no "all expenses"
  /// method for a caller to reach for.
  ///
  /// Raw `int` date keys, matching `CalendarDao`: a view's columns carry no type converter, so the
  /// typed boundary lives in the repository and is crossed once.
  Stream<List<SplitExpenseSummaryRow>> watchExpenses({
    required int fromDateKey,
    required int toDateKey,
    String? groupId,
  }) {
    final view = attachedDatabase.vSplitExpenses;
    final query = select(view)
      ..where((t) => t.dateKey.isBetweenValues(fromDateKey, toDateKey))
      ..orderBy([
        (t) => OrderingTerm.desc(t.dateKey),
        (t) => OrderingTerm.desc(t.splitExpenseId),
      ]);
    if (groupId != null) {
      query.where((t) => t.groupId.equals(groupId));
    }
    return query.watch();
  }

  /// Reads one expense summary, or null when it does not exist.
  Future<SplitExpenseSummaryRow?> expenseSummary(String splitExpenseId) =>
      (select(attachedDatabase.vSplitExpenses)
            ..where((t) => t.splitExpenseId.equals(splitExpenseId)))
          .getSingleOrNull();

  /// Emits the expenses whose shares do not account for their total.
  ///
  /// The list a "needs attention" surface shows. Filtered in SQL rather than by fetching everything
  /// and testing in Dart, because on a healthy ledger the answer is almost always empty and the whole
  /// point is not to materialise the rows that are fine.
  Stream<List<SplitExpenseSummaryRow>> watchUnallocated({
    required int fromDateKey,
    required int toDateKey,
  }) {
    final view = attachedDatabase.vSplitExpenses;
    return (select(view)
          ..where(
            (t) =>
                t.dateKey.isBetweenValues(fromDateKey, toDateKey) &
                t.unallocatedMinor.equals(0).not(),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.dateKey)]))
        .watch();
  }

  // ── balances ────────────────────────────────────────────────────────────────────────────

  /// Emits every counterparty with something outstanding, per currency.
  ///
  /// Rows that net to zero are filtered out here rather than in the view: the view has to keep them,
  /// because a settled counterparty still contributes to a group's history and to
  /// [watchBalanceWith], which must be able to say "settled" rather than return nothing at all.
  Stream<List<SplitBalanceRow>> watchBalances() {
    final view = attachedDatabase.vSplitBalances;
    return (select(view)
          ..where((t) => t.netMinor.equals(0).not())
          ..orderBy([
            (t) => OrderingTerm.desc(t.netMinor),
            (t) => OrderingTerm.asc(t.payeeId),
          ]))
        .watch();
  }

  /// Emits one counterparty's balance across every currency, settled or not.
  Stream<List<SplitBalanceRow>> watchBalanceWith(String payeeId) {
    return (select(attachedDatabase.vSplitBalances)
          ..where((t) => t.payeeId.equals(payeeId))
          ..orderBy([(t) => OrderingTerm.asc(t.currencyCode)]))
        .watch();
  }

  /// Emits the balances within [groupId].
  Stream<List<SplitGroupBalanceRow>> watchGroupBalances(String groupId) {
    return (select(attachedDatabase.vSplitGroupBalances)
          ..where((t) => t.groupId.equals(groupId) & t.netMinor.equals(0).not())
          ..orderBy([
            (t) => OrderingTerm.desc(t.netMinor),
            (t) => OrderingTerm.asc(t.payeeId),
          ]))
        .watch();
  }

  /// Reads the balances within [groupId], settled rows included.
  ///
  /// **Includes the settled ones, unlike [watchGroupBalances], and that is not an oversight.** This
  /// feeds `DebtSimplifier`, whose zero-sum partition is what beats greedy — and a person at zero can
  /// be the reason a subset sums to zero. Filtering them out here would remove the input the
  /// algorithm's best case runs on.
  Future<List<SplitGroupBalanceRow>> groupBalances(String groupId) => (select(
    attachedDatabase.vSplitGroupBalances,
  )..where((t) => t.groupId.equals(groupId))).get();

  // ── activity ────────────────────────────────────────────────────────────────────────────

  /// Emits expenses and settlements interleaved, newest first.
  ///
  /// [limit] is required rather than optional. The feed is a `UNION ALL` over two growing tables with
  /// no date bound, so an unlimited read is the one query in this module that gets slower every month
  /// a user keeps using it — and a screen showing a feed always has a page size in mind anyway.
  Stream<List<SplitActivityRow>> watchActivity({
    required int limit,
    String? groupId,
  }) {
    final view = attachedDatabase.vSplitActivity;
    final query = select(view)
      ..orderBy([
        (t) => OrderingTerm.desc(t.dateKey),
        (t) => OrderingTerm.desc(t.refId),
      ])
      ..limit(limit);
    if (groupId != null) {
      query.where((t) => t.groupId.equals(groupId));
    }
    return query.watch();
  }
}
