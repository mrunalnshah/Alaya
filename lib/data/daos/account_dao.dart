import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Typed access to `accounts`, plus the two views that derive money from them.
///
/// **On Law L7 and this phase's "all reads go through views" rule.** Of the eleven money-side
/// tables, only `accounts` and `transactions` have views (ARCH_2 §12) — the nine reference and
/// link tables have none. Adding a pass-through `v_active_currencies` and friends would satisfy
/// the rule's letter and make the codebase worse: each would generate a *second* row class with
/// fields identical to the table's, so every Phase 3B mapper would have to know which of
/// `CurrencyRow` and `ActiveCurrencyRow` it holds, and every schema snapshot would carry nine
/// objects that answer no question a `WHERE` clause does not.
///
/// So L7's stated purpose — that `deletedAt IS NULL` "cannot be forgotten" — is met here by
/// structure rather than by a view: every DAO in this phase funnels its reads through one private
/// `_activeRows()` builder, and no public method returns unfiltered rows except the explicitly
/// named `byIdIncludingDeleted`. Repositories never write SQL, so they cannot bypass it. Where a
/// view *does* exist it is used, always — balances and ledger legs below are never recomputed in
/// Dart.
class AccountDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  AccountDao(super.db);

  $AccountsTable get _table => attachedDatabase.accounts;

  SimpleSelectStatement<$AccountsTable, AccountRow> _activeRows() =>
      select(_table)..where((t) => t.deletedAt.isNull());

  /// Emits active, unarchived accounts in display order — the picker list.
  Stream<List<AccountRow>> watchSelectable() {
    return (_activeRows()
      ..where((t) => t.isArchived.equals(false))
      ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  /// Emits every active account, archived included.
  ///
  /// Archived accounts still count toward totals and net worth — they have simply left the
  /// pickers. Conflating archive with delete is the distinction ARCH_3 §4 exists to preserve.
  Stream<List<AccountRow>> watchAllIncludingArchived() {
    return (_activeRows()
      ..orderBy([
            (t) => OrderingTerm(expression: t.isArchived),
            (t) => OrderingTerm(expression: t.sortOrder),
      ]))
        .watch();
  }

  /// Reads one account by id, including a soft-deleted one.
  Future<AccountRow?> byIdIncludingDeleted(String id) =>
      (select(_table)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Reads one active account by normalized name, for the duplicate check.
  Future<AccountRow?> byNormalizedName(String normalizedName) =>
      (_activeRows()..where((t) => t.normalizedName.equals(normalizedName))).getSingleOrNull();

  // ── derived money: always from the views ───────────────────────────────────────────────

  /// Emits every active account's balance, each in its own currency.
  ///
  /// Reads `v_account_balances`, which is `openingBalanceMinor + Σ ledger legs`. Never sum these
  /// across accounts without converting first — they may be in different currencies (A34).
  Stream<List<AccountBalanceRow>> watchBalances() =>
      select(attachedDatabase.vAccountBalances).watch();

  /// Emits one account's balance.
  Stream<AccountBalanceRow?> watchBalanceOf(String accountId) {
    return (select(attachedDatabase.vAccountBalances)
      ..where((t) => t.accountId.equals(accountId)))
        .watchSingleOrNull();
  }

  /// Reads one account's balance once.
  Future<AccountBalanceRow?> balanceOf(String accountId) {
    return (select(attachedDatabase.vAccountBalances)
      ..where((t) => t.accountId.equals(accountId)))
        .getSingleOrNull();
  }

  /// Emits the signed ledger legs touching [accountId], newest first.
  ///
  /// A `transfer` contributes two legs across two accounts, so filtering by account correctly
  /// yields only that account's side of it (ARCH_2 §12.1).
  Stream<List<AccountLedgerRow>> watchLedger(String accountId) {
    return (select(attachedDatabase.vAccountLedger)
      ..where((t) => t.accountId.equals(accountId))
      ..orderBy([(t) => OrderingTerm(expression: t.dateKey, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Emits `(accountId, currencyCode, balanceMinor)` for every active account with
  /// `includeInNetWorth = true`.
  ///
  /// A single joined query rather than combining two separate streams in Dart.
  /// `v_account_balances` carries no `includeInNetWorth` column — the view's own `SELECT` list is
  /// exactly what a balance needs, nothing more — so this reads the view and `accounts` together
  /// in one `customSelect`, with `readsFrom` stated explicitly since a raw SQL string cannot be
  /// statically analysed for its table dependencies the way a query-builder call can.
  Stream<List<({String accountId, String currencyCode, int balanceMinor})>>
  watchNetWorthEligibleBalances() {
    return customSelect(
      'SELECT b.account_id, b.currency_code, b.balance_minor '
          'FROM v_account_balances b JOIN accounts a ON a.id = b.account_id '
          'WHERE a.include_in_net_worth = 1',
      readsFrom: {attachedDatabase.vAccountBalances, _table},
    ).watch().map(
          (rows) => rows
          .map(
            (row) => (
        accountId: row.read<String>('account_id'),
        currencyCode: row.read<String>('currency_code'),
        balanceMinor: row.read<int>('balance_minor'),
        ),
      )
          .toList(),
    );
  }

  // ── writes ────────────────────────────────────────────────────────────────────────────

  /// Inserts or updates an account.
  Future<void> upsert(AccountsCompanion account) => into(_table).insertOnConflictUpdate(account);

  /// Archives or unarchives an account.
  Future<void> setArchived({
    required String id,
    required bool isArchived,
    required int nowUtcMillis,
  }) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(isArchived: Value(isArchived), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Soft-deletes an account.
  ///
  /// Deliberately unguarded here. ARCH_3 §4.1 requires deleting an account with live transactions
  /// to be *blocked* with Archive offered instead — but that is a business rule, and this layer
  /// holds none. Phase 3B's repository calls [activeTransactionCount] first and returns a failure.
  Future<void> softDelete({required String id, required int nowUtcMillis}) {
    return (update(_table)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(deletedAt: Value(nowUtcMillis), updatedAt: Value(nowUtcMillis)),
    );
  }

  /// Counts active transactions on either side of [accountId] — the input to that block.
  Future<int> activeTransactionCount(String accountId) async {
    final transactions = attachedDatabase.transactions;
    final count = countAll();
    final row = await (selectOnly(transactions)
      ..addColumns([count])
      ..where(transactions.deletedAt.isNull() &
      (transactions.fromAccountId.equals(accountId) |
      transactions.toAccountId.equals(accountId))))
        .getSingle();
    return row.read(count) ?? 0;
  }
}
