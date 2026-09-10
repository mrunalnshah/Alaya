import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/services/split/debt_simplifier.dart' show DebtEdge;

/// Shared expenses, settlements, and the balances derived from them.
///
/// **Every balance here is derived (Law L3).** Nothing in this contract returns a stored total, and
/// nothing in it lets a caller write one — which is what makes a balance in this module structurally
/// unable to drift. It is also why [watchBalances] is a stream over a view rather than a getter over a
/// column.
abstract interface class SplitLedgerRepository {
  // ── expenses ────────────────────────────────────────────────────────────────────────────

  /// Expenses in `[from, to]`, newest first, as summaries.
  ///
  /// Summaries rather than full entities: a list of forty expenses should not fetch four hundred share
  /// rows to display forty totals. Load the entity when one is opened.
  Stream<List<SplitExpenseSummary>> watchExpenses({
    required DateKey from,
    required DateKey to,
    String? groupId,
  });

  /// One expense with its shares, or null if it does not exist.
  Stream<SplitExpense?> watchExpenseById(String id);

  /// Fetches one expense with its shares.
  Future<SplitExpense?> expenseById(String id);

  /// The expense attached to [transactionId], or null when that transaction is not a split.
  ///
  /// What the expense editor reads when reopening a transaction: it has the transaction id and needs to
  /// know whether a split already hangs off it.
  Future<SplitExpense?> expenseForTransaction(String transactionId);

  /// Inserts or replaces [expense] and its whole share list, atomically (Law L14).
  ///
  /// **Does not create the transaction.** In the "you paid" case a transaction must already exist and
  /// [SplitExpense.transactionId] must point at it — writing one here would put money movement behind
  /// a split save, and `TransactionRepository` is where that belongs.
  ///
  /// Rejects: a share whose `transactionLineNo` is set on an expense with no transaction — the
  /// cross-table half of the itemising rule that SQLite cannot express as a CHECK; a share list with
  /// the same payee twice for the same line; a negative share; and a currency on any share that
  /// differs from the expense's.
  ///
  /// **Accepts shares that do not sum to the total.** That is a real state, not an error: percentages
  /// mid-edit, or a tip nobody assigned. [SplitExpense.unallocated] reports it and the screen decides
  /// what to say — the same treatment `v_transaction_allocation` gives an un-itemised transaction.
  Future<Result<SplitExpense, Failure>> saveExpense(SplitExpense expense);

  /// Soft-deletes the expense and its shares.
  ///
  /// Leaves any linked transaction alone. The money did move, and deleting the split is a statement
  /// about who owed what — not about whether the payment happened.
  Future<Result<void, Failure>> deleteExpense(String id);

  // ── naming an unnamed participant ───────────────────────────────────────────────────────

  /// Makes [placeholderPayeeId] and [payeeId] one person, keeping the second.
  ///
  /// **What a rename cannot do.** Saving a split with unnamed participants writes a
  /// `PayeeKind.splitPlaceholder` row so the debt can exist at all — `split_shares.payee_id` is
  /// `NOT NULL REFERENCES payees(id)`. Renaming that row is right when the person turns out to be
  /// somebody new; when they are somebody the app already knows, the two identities have to *become*
  /// one, or that person ends up with two balances and settling one leaves the other outstanding with
  /// nothing on screen to explain it.
  ///
  /// Every share, settlement, membership and paid-by reference moves, and the placeholder is retired —
  /// atomically, because a half-moved identity is two debts where there should be one.
  ///
  /// **Shares are summed where both already exist on the same expense**, rather than refused.
  /// `idx_split_share` is unique on `(split_expense_id, payee_id, transaction_line_no)`, so a
  /// reassignment onto an expense the target is already on collides — and somebody telling the app who
  /// a participant really was is a statement it should be able to record. The merged row's stored input
  /// becomes `exact`, because 40% plus somebody else's ₹800 is not 40% of anything, and a percentage
  /// that no longer reproduces the amount beside it is the one thing this module must never show.
  ///
  /// Rejects merging a payee into itself, merging into a deleted payee, and merging *from* anything that
  /// is not a placeholder. The last is the important one: this is destructive in one direction — whichever
  /// payee is named first stops existing — which is right for *"Person 4 was Ravi all along"* and wrong as
  /// a general "combine two contacts" tool, where a caller with the arguments the wrong way round would
  /// silently delete the row they meant to keep.
  Future<Result<void, Failure>> mergePlaceholder({
    required String placeholderPayeeId,
    required String payeeId,
  });

  // ── settlements ─────────────────────────────────────────────────────────────────────────

  /// Settlements in `[from, to]`, newest first.
  Stream<List<SplitSettlement>> watchSettlements({
    required DateKey from,
    required DateKey to,
    String? groupId,
  });

  /// Records [settlement] and the [transaction] that moved the money, **atomically**.
  ///
  /// **One call rather than two, and that is the point.** Splitwise's "settle up" is a bookkeeping
  /// marker it cannot back with anything; here the deposit or withdrawal is an ordinary
  /// `transactions` row written in the same database transaction as the settlement. Two calls would
  /// commit independently, and a settlement written without its transaction clears a debt with no
  /// money anywhere — the one failure in this module a user could not see.
  ///
  /// [transaction] is required whenever the user is a party, and null only for a settlement between
  /// two other people, which an accepted simplification plan can suggest and which moves none of the
  /// user's money. The implementation refuses the mismatch rather than trusting the caller, because a
  /// null here silently produces exactly the invisible failure above.
  ///
  /// The caller builds both — `SettlementService` — so that this contract stays a write and the
  /// decisions about deposit-versus-withdrawal, subtype and payee stay in the domain where they can
  /// be tested without a database.
  Future<Result<SplitSettlement, Failure>> recordSettlement({
    required SplitSettlement settlement,
    Transaction? transaction,
  });

  /// Soft-deletes a settlement.
  Future<Result<void, Failure>> deleteSettlement(String id);

  // ── derived reads ───────────────────────────────────────────────────────────────────────

  /// What each person owes you and you owe them, per currency.
  ///
  /// Only counterparties with something outstanding, so an empty stream means settled up with
  /// everybody. Grouped by currency and never summed across it.
  Stream<List<SplitBalance>> watchBalances();

  /// The same, restricted to one group.
  Stream<List<SplitBalance>> watchGroupBalances(String groupId);

  /// One counterparty's balance across every currency, or an empty list when settled.
  Stream<List<SplitBalance>> watchBalanceWith(String payeeId);

  /// Expenses and settlements interleaved, newest first.
  Stream<List<SplitActivityEntry>> watchActivity({String? groupId, int limit});

  /// Every real pairwise debt in [groupId], for the simplifier.
  ///
  /// **Returns [DebtEdge]s, not [SplitBalance]s, and the difference is the whole point.**
  /// `DebtSimplifier`'s partition tie-break prefers transfers along debts that genuinely exist — the
  /// answer to *"she never lent me money"* — so it needs the edges as incurred. A netted summary would
  /// have discarded exactly the information the tie-break runs on, before the algorithm could see it.
  ///
  /// **Imports [DebtEdge] from the service rather than declaring a twin here.** A repository contract
  /// naming a service's type is the wrong direction, and the honest fix is that `DebtEdge` is a domain
  /// *value* — "X owes Y this much" — that belongs in `entities/` rather than inside
  /// `debt_simplifier.dart`. It has since moved there, and this import now resolves through a
  /// re-export; the `show` clause stays because it documents which single type is wanted.
  Future<List<DebtEdge>> debtsIn(String groupId);
}
