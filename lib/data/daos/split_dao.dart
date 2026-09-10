import 'package:drift/drift.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to the five split tables.
///
/// One DAO rather than five, for the reason `RecipeDao` gives: a split expense is an aggregate whose
/// shares have no meaning apart from it, and nothing ever loads a share without the expense it
/// belongs to. Groups and members are the same pairing.
///
/// **Reads of derived figures are not here.** Balances, activity and the per-expense allocation
/// totals come from views, and `SplitViewDao` reads those — the same separation `CalendarDao` has
/// from the seven tables its view unions. Keeping them apart is what stops a caller reaching for a
/// table when it wanted the view, which Law L7 forbids and which a single DAO exposing both would
/// make easy.
class SplitDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  SplitDao(super.db);

  $SplitGroupsTable get _groups => attachedDatabase.splitGroups;
  $SplitMembersTable get _members => attachedDatabase.splitMembers;
  $SplitExpensesTable get _expenses => attachedDatabase.splitExpenses;
  $SplitSharesTable get _shares => attachedDatabase.splitShares;
  $SplitSettlementsTable get _settlements => attachedDatabase.splitSettlements;

  SimpleSelectStatement<$SplitGroupsTable, SplitGroupRow> _activeGroups() =>
      select(_groups)..where((t) => t.deletedAt.isNull());

  // ── groups and members ──────────────────────────────────────────────────────────────────

  /// Emits every active group, in sort order then name. Archived groups included.
  Stream<List<SplitGroupRow>> watchGroups() {
    return (_activeGroups()..orderBy([
          (t) => OrderingTerm(expression: t.sortOrder),
          (t) => OrderingTerm(expression: t.normalizedName),
        ]))
        .watch();
  }

  /// Emits the groups a picker should offer — active and not archived.
  Stream<List<SplitGroupRow>> watchActiveGroups() {
    return (_activeGroups()
          ..where((t) => t.isArchived.equals(false))
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder),
            (t) => OrderingTerm(expression: t.normalizedName),
          ]))
        .watch();
  }

  /// Emits one group header, or null when it does not exist or is soft-deleted.
  Stream<SplitGroupRow?> watchGroupById(String id) =>
      (_activeGroups()..where((t) => t.id.equals(id))).watchSingleOrNull();

  /// Reads one group header.
  Future<SplitGroupRow?> groupById(String id) =>
      (_activeGroups()..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads one active group by normalized name, for the duplicate check.
  ///
  /// Active only, so a name freed by deleting a group can be reused — `idx_split_groups_name` is
  /// partial on `deleted_at IS NULL` for exactly that (anomaly A19), and a check that ignored the
  /// filter would refuse a name the index would happily accept.
  Future<SplitGroupRow?> byNormalizedName(String normalizedName) =>
      (_activeGroups()..where((t) => t.normalizedName.equals(normalizedName)))
          .getSingleOrNull();

  /// Emits the active members of [groupId], in display order.
  Stream<List<SplitMemberRow>> watchMembers(String groupId) {
    return (select(_members)
          ..where((t) => t.groupId.equals(groupId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Reads the active members of several groups at once.
  ///
  /// A group list showing "4 people" per row needs every group's members. One query with `isIn`
  /// rather than N, because the alternative is a query per visible row on every rebuild of a
  /// virtualised list — the reason `RecipeDao.watchIngredientsForAll` exists.
  Stream<List<SplitMemberRow>> watchMembersForAll(List<String> groupIds) {
    return (select(_members)
          ..where((t) => t.groupId.isIn(groupIds) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Emits the groups [payeeId] belongs to.
  ///
  /// A join rather than two round trips, with `useColumns: false` because only the group rows are
  /// wanted — without it drift materialises the membership columns for every match too.
  ///
  /// No `groupBy` is needed here, unlike `RecipeDao.watchUsingItem`: `idx_split_member` makes one
  /// membership per person per group unique, so the join cannot return a group twice.
  Stream<List<SplitGroupRow>> watchGroupsForPayee(String payeeId) {
    final query =
        select(_groups).join([
            innerJoin(
              _members,
              _members.groupId.equalsExp(_groups.id),
              useColumns: false,
            ),
          ])
          ..where(
            _groups.deletedAt.isNull() &
                _members.deletedAt.isNull() &
                _members.payeeId.equals(payeeId),
          )
          ..orderBy([OrderingTerm(expression: _groups.normalizedName)]);
    return query.watch().map(
      (rows) => rows.map((r) => r.readTable(_groups)).toList(),
    );
  }

  /// Replaces a group and its whole member list, atomically.
  ///
  /// Delete-then-insert inside one transaction rather than diffing, matching
  /// `RecipeDao.saveAggregate`: an editor can add, remove and reorder members in one sitting, and a
  /// minimal diff would need stable identities the UI does not carry. Soft-deleted rather than
  /// dropped, so the trash keeps its promise (ARCH_3 §4.2).
  Future<void> saveGroup({
    required SplitGroupsCompanion group,
    required List<SplitMembersCompanion> members,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await into(_groups).insertOnConflictUpdate(group);
      final id = group.id.value;

      await (update(
        _members,
      )..where((t) => t.groupId.equals(id) & t.deletedAt.isNull())).write(
        SplitMembersCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      for (final member in members) {
        await into(_members).insertOnConflictUpdate(member);
      }
    });
  }

  /// Archives or unarchives a group.
  Future<void> setGroupArchived({
    required String id,
    required bool isArchived,
    required int nowUtcMillis,
  }) {
    return (update(_groups)..where((t) => t.id.equals(id))).write(
      SplitGroupsCompanion(
        isArchived: Value(isArchived),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }

  /// How many active expenses are filed under [groupId].
  ///
  /// What the repository checks before allowing a delete. Counted in SQL rather than by fetching the
  /// expenses and taking `.length`, because the answer is a number and a busy group is hundreds of
  /// rows to discard.
  Future<int> expenseCountInGroup(String groupId) async {
    final total = countAll();
    final query = selectOnly(_expenses)
      ..addColumns([total])
      ..where(_expenses.groupId.equals(groupId) & _expenses.deletedAt.isNull());
    final row = await query.getSingle();
    return row.read(total) ?? 0;
  }

  /// Soft-deletes a group and its memberships, in one transaction.
  ///
  /// **Does not touch the expenses**, which is why the repository refuses this call while any exist.
  /// Cascading would delete a shared history because a label was tidied away, and the balances those
  /// expenses feed would vanish with them.
  Future<void> softDeleteGroup({
    required String id,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await (update(_groups)..where((t) => t.id.equals(id))).write(
        SplitGroupsCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      await (update(_members)..where((t) => t.groupId.equals(id))).write(
        SplitMembersCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
    });
  }

  // ── expenses and shares ─────────────────────────────────────────────────────────────────

  /// Emits one expense header, or null when it does not exist or is soft-deleted.
  Stream<SplitExpenseRow?> watchExpenseById(String id) => (select(
    _expenses,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).watchSingleOrNull();

  /// Reads one expense header.
  Future<SplitExpenseRow?> expenseById(String id) => (select(
    _expenses,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  /// Reads the expense attached to [transactionId], or null when that transaction is not a split.
  ///
  /// `getSingleOrNull` rather than `get().firstOrNull`: at most one split may hang off a transaction,
  /// and if a second ever appeared this would throw rather than silently pick one — which is the
  /// behaviour worth having, because two splits on one payment is a bug nothing else would surface.
  Future<SplitExpenseRow?> expenseForTransaction(String transactionId) =>
      (select(_expenses)..where(
            (t) => t.transactionId.equals(transactionId) & t.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  /// Emits the active shares of [splitExpenseId], in insertion order.
  Stream<List<SplitShareRow>> watchShares(String splitExpenseId) {
    return (select(_shares)
          ..where(
            (t) =>
                t.splitExpenseId.equals(splitExpenseId) & t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  /// Reads the active shares of several expenses at once. See [watchMembersForAll].
  Stream<List<SplitShareRow>> watchSharesForAll(List<String> expenseIds) {
    return (select(_shares)
          ..where(
            (t) => t.splitExpenseId.isIn(expenseIds) & t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  /// Replaces an expense and its whole share list, atomically (Law L14).
  ///
  /// Delete-then-insert, matching [saveGroup] and `RecipeDao.saveAggregate`. A share carries no
  /// identity the editor preserves across a re-split — changing four equal shares to 40/30/20/10
  /// replaces all four — so diffing would buy nothing and could leave a half-applied list.
  Future<void> saveExpense({
    required SplitExpensesCompanion expense,
    required List<SplitSharesCompanion> shares,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await into(_expenses).insertOnConflictUpdate(expense);
      final id = expense.id.value;

      await (update(
            _shares,
          )..where((t) => t.splitExpenseId.equals(id) & t.deletedAt.isNull()))
          .write(
            SplitSharesCompanion(
              deletedAt: Value(nowUtcMillis),
              updatedAt: Value(nowUtcMillis),
            ),
          );
      for (final share in shares) {
        await into(_shares).insertOnConflictUpdate(share);
      }
    });
  }

  /// Soft-deletes an expense and its shares, in one transaction.
  ///
  /// The shares go too. An expense in the trash whose shares were still active would keep feeding
  /// `v_split_balances` — somebody would still owe you for a bill you deleted.
  Future<void> softDeleteExpense({
    required String id,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      await (update(_expenses)..where((t) => t.id.equals(id))).write(
        SplitExpensesCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      await (update(_shares)..where((t) => t.splitExpenseId.equals(id))).write(
        SplitSharesCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
    });
  }

  // ── merging one payee into another ──────────────────────────────────────────────────────

  /// What a merge needs to know about a payee: what kind it is, and whether it is in the trash.
  ///
  /// **Here rather than through `PayeeDao`, and that decision saved two call sites.** The first version
  /// took a `PayeeDao` as a sixth constructor argument to the repository, which meant every place that
  /// builds one — `repository_providers.dart` and `daily_job.dart` — had to be found and changed. This DAO
  /// already reaches `payees` for [mergePayee]; a read beside that write is the same scope stretch, already
  /// justified, and costs nobody else anything.
  ///
  /// Returns a record rather than the drift row, so the repository's guard reads the two fields it cares
  /// about without the data layer's generated type crossing into it.
  Future<({PayeeKind kind, int? deletedAt})?> payeeIdentity(String id) async {
    final row = await (select(
      _payees,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : (kind: row.kind, deletedAt: row.deletedAt);
  }

  /// Moves every split reference from [fromPayeeId] to [intoPayeeId], then retires the first.
  ///
  /// **What "Person 4 is actually Ravi" costs.** Saving a split with unnamed participants writes a
  /// `PayeeKind.splitPlaceholder` row so the debt can exist at all, and renaming that row is only right
  /// when the person is somebody new. When they are somebody the app already knows, the two identities have
  /// to become one — every share, settlement, membership and paid-by reference reassigned — or Ravi ends up
  /// with two balances and settling one leaves the other outstanding.
  ///
  /// **Five tables, one transaction, and `payees` is the fifth.** Reaching outside the split tables is a
  /// scope stretch this DAO already makes for the same reason: `insertSettlementWithTransaction` writes a
  /// `transactions` row because a settlement without its transaction clears a debt with no money anywhere.
  /// Here, a reassignment that committed without retiring the placeholder would leave a payee nothing
  /// references, still offered in a picker.
  ///
  /// ## The two collisions, and why neither refuses
  ///
  /// **`idx_split_share` is unique on `(split_expense_id, payee_id, transaction_line_no)`**, so when Ravi
  /// already has a share on the same expense the reassignment lands on a key that exists. The shares are
  /// **summed** into his: he genuinely owes both. Refusing would be telling the user their own statement
  /// about who somebody is cannot be recorded.
  ///
  /// A summed share's stored input no longer describes it — 40% plus somebody else's ₹800 is not 40% of
  /// anything — so the merged row becomes [ShareInputKind.exact] with the total. Keeping the old percentage
  /// would show a figure that does not reproduce the amount beside it, which is the one thing a split app
  /// must never do.
  ///
  /// **`idx_split_member` is unique on `(group_id, payee_id)`**, so a placeholder that somehow reached a
  /// group Ravi is already in has its membership dropped rather than reassigned. Nothing is lost: a
  /// membership carries only a weight and a sort order, and Ravi's own row already has his.
  Future<void> mergePayee({
    required String fromPayeeId,
    required String intoPayeeId,
    required int nowUtcMillis,
  }) {
    return transaction(() async {
      final touched = SplitSharesCompanion(
        payeeId: Value(intoPayeeId),
        updatedAt: Value(nowUtcMillis),
      );
      final retired = SplitSharesCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      );

      // Read both sides before writing either. Reassigning row by row while querying would have the
      // target's set change underneath the loop.
      final moving =
          await (select(_shares)..where(
                (t) => t.payeeId.equals(fromPayeeId) & t.deletedAt.isNull(),
              ))
              .get();
      final existing =
          await (select(_shares)..where(
                (t) => t.payeeId.equals(intoPayeeId) & t.deletedAt.isNull(),
              ))
              .get();

      final byKey = {
        for (final row in existing)
          '${row.splitExpenseId}#${row.transactionLineNo ?? -1}': row,
      };

      for (final row in moving) {
        final key = '${row.splitExpenseId}#${row.transactionLineNo ?? -1}';
        final clash = byKey[key];
        if (clash == null) {
          await (update(_shares)..where((t) => t.id.equals(row.id))).write(
            touched,
          );
          continue;
        }
        // Summed, then the placeholder's row retired — in that order, so a failure between the two leaves
        // the smaller debt rather than none of it.
        await (update(_shares)..where((t) => t.id.equals(clash.id))).write(
          SplitSharesCompanion(
            shareAmountMinor: Value(
              clash.shareAmountMinor + row.shareAmountMinor,
            ),
            inputKind: const Value(ShareInputKind.exact),
            inputValue: Value(clash.shareAmountMinor + row.shareAmountMinor),
            updatedAt: Value(nowUtcMillis),
          ),
        );
        await (update(_shares)..where((t) => t.id.equals(row.id))).write(
          retired,
        );
      }

      // Settlements have no unique index, so both ends reassign without collision. The CHECK forbidding
      // `from = to` cannot fire either: that would need a settlement between the placeholder and the payee
      // it is becoming, which is money moving between one person and themselves.
      await (update(
        _settlements,
      )..where((t) => t.fromPayeeId.equals(fromPayeeId))).write(
        SplitSettlementsCompanion(
          fromPayeeId: Value(intoPayeeId),
          updatedAt: Value(nowUtcMillis),
        ),
      );
      await (update(
        _settlements,
      )..where((t) => t.toPayeeId.equals(fromPayeeId))).write(
        SplitSettlementsCompanion(
          toPayeeId: Value(intoPayeeId),
          updatedAt: Value(nowUtcMillis),
        ),
      );

      // A placeholder is never the payer in practice — the bill screen always names the user — but a
      // dangling reference here would be an expense pointing at a retired row.
      await (update(
        _expenses,
      )..where((t) => t.paidByPayeeId.equals(fromPayeeId))).write(
        SplitExpensesCompanion(
          paidByPayeeId: Value(intoPayeeId),
          updatedAt: Value(nowUtcMillis),
        ),
      );

      final memberships =
          await (select(_members)..where(
                (t) => t.payeeId.equals(fromPayeeId) & t.deletedAt.isNull(),
              ))
              .get();
      for (final row in memberships) {
        final already =
            await (select(_members)..where(
                  (t) =>
                      t.groupId.equals(row.groupId) &
                      t.payeeId.equals(intoPayeeId) &
                      t.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        await (update(_members)..where((t) => t.id.equals(row.id))).write(
          already == null
              ? SplitMembersCompanion(
                  payeeId: Value(intoPayeeId),
                  updatedAt: Value(nowUtcMillis),
                )
              : SplitMembersCompanion(
                  deletedAt: Value(nowUtcMillis),
                  updatedAt: Value(nowUtcMillis),
                ),
        );
      }

      // **Last, and inside the same transaction.** Retiring the placeholder before its references moved
      // would leave shares pointing at a deleted payee if anything after it failed — and
      // `v_split_balances` joins `payees` on `deleted_at IS NULL`, so those debts would vanish from every
      // screen while still sitting in the table.
      await (update(_payees)..where((t) => t.id.equals(fromPayeeId))).write(
        PayeesCompanion(
          deletedAt: Value(nowUtcMillis),
          updatedAt: Value(nowUtcMillis),
        ),
      );
    });
  }

  // ── settlements ─────────────────────────────────────────────────────────────────────────

  /// Records a settlement.
  Future<void> insertSettlement(SplitSettlementsCompanion settlement) =>
      into(_settlements).insertOnConflictUpdate(settlement);

  $TransactionsTable get _transactions => attachedDatabase.transactions;

  /// `payees`, for [mergePayee] only.
  ///
  /// Outside this DAO's five tables, and kept for the same reason [_transactions] is: retiring the
  /// placeholder has to commit with the reassignment that made it redundant.
  $PayeesTable get _payees => attachedDatabase.payees;

  /// Writes a settlement and the transaction that moved the money, in one transaction (Law L14).
  ///
  /// **This is the method the module's central claim rests on.** Splitwise's "settle up" is a
  /// bookkeeping marker that cannot touch your bank; here the deposit or withdrawal is an ordinary
  /// `transactions` row, and the whole point is that the two ledgers cannot diverge. Two separate
  /// repository calls would commit independently — a settlement written without its transaction
  /// clears a debt with no money anywhere, which is invisible and wrong.
  ///
  /// **Writing a `transactions` row from this DAO is deliberate and has precedent.**
  /// `TransactionRepositoryImpl` holds `BatchDao` and `StockMovementDao` and says so in its own class
  /// doc: *"any repository may depend on any DAO it needs."* Atomicity across tables belongs in a DAO
  /// because a DAO is the only layer that can open one — no repository in this codebase opens a drift
  /// transaction, and the three services that do (`EraseService`, `RestoreService`, `TrashAdapter`)
  /// hold `AlayaDatabase` itself.
  ///
  /// The transaction is written first so that, in the impossible case of a partial commit, the
  /// surviving artefact is the visible one. SQLite gives all-or-nothing here, so the ordering is
  /// belt-and-braces rather than load-bearing.
  Future<void> insertSettlementWithTransaction({
    required TransactionsCompanion transaction,
    required SplitSettlementsCompanion settlement,
  }) {
    return this.transaction(() async {
      await into(_transactions).insert(transaction);
      await into(_settlements).insert(settlement);
    });
  }

  /// Emits settlements in `[fromDateKey, toDateKey]`, newest first.
  ///
  /// Takes raw `int` date keys rather than `DateKey`, matching `CalendarDao`. The repository holds
  /// the typed boundary and converts once; a DAO that took `DateKey` would need
  /// `date_key_filters.dart` on every comparison for no gain, since nothing here does date
  /// arithmetic.
  Stream<List<SplitSettlementRow>> watchSettlements({
    required int fromDateKey,
    required int toDateKey,
    String? groupId,
  }) {
    final query = select(_settlements)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.dateKey.isBetweenValues(fromDateKey, toDateKey),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.dateKey, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ]);
    if (groupId != null) {
      query.where((t) => t.groupId.equals(groupId));
    }
    return query.watch();
  }

  /// Reads every active settlement involving [payeeId] on either side.
  ///
  /// Both directions in one query rather than two unioned in Dart, because a balance needs the pair
  /// and running them separately would emit twice per change.
  Future<List<SplitSettlementRow>> settlementsWith(String payeeId) {
    return (select(_settlements)..where(
          (t) =>
              t.deletedAt.isNull() &
              (t.fromPayeeId.equals(payeeId) | t.toPayeeId.equals(payeeId)),
        ))
        .get();
  }

  /// Soft-deletes a settlement.
  ///
  /// **Leaves any linked transaction alone.** The money did move; deleting the settlement is a
  /// statement about the debt it discharged, not about whether the payment happened. Reversing the
  /// transaction is `StockRepository.reverse`'s analogue on the money side and belongs to the caller.
  Future<void> softDeleteSettlement({
    required String id,
    required int nowUtcMillis,
  }) {
    return (update(_settlements)..where((t) => t.id.equals(id))).write(
      SplitSettlementsCompanion(
        deletedAt: Value(nowUtcMillis),
        updatedAt: Value(nowUtcMillis),
      ),
    );
  }
}
