import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/repositories/split_group_repository.dart';
import 'package:alaya/domain/repositories/split_ledger_repository.dart';

/// Records money changing hands to settle a split debt.
///
/// **A settlement you are part of is a real transaction, and that is the module's whole claim.**
/// Splitwise's "settle up" is a marker it cannot back with anything — it has no access to your bank.
/// Here the deposit or withdrawal is an ordinary `transactions` row written in the *same* database
/// transaction as the settlement itself, so the account ledger and the split ledger cannot diverge.
///
/// **This service does no I/O ordering, deliberately.** It builds the pair and hands both to one
/// repository call. An earlier design had it write through two repositories and called that
/// "atomic", which it could not have been: two repositories commit independently, and a settlement
/// written without its transaction clears a debt with no money anywhere — invisible, and the worst
/// of the available failures. The atomicity lives in `SplitDao`, which is the only layer that can
/// open a drift transaction.
final class SettlementService {
  /// Creates the service.
  const SettlementService({
    required SplitLedgerRepository ledger,
    required SplitGroupRepository groups,
    required UidGenerator uids,
    required Clock clock,
  }) : _ledger = ledger,
       _groups = groups,
       _uids = uids,
       _clock = clock;

  final SplitLedgerRepository _ledger;
  final SplitGroupRepository _groups;
  final UidGenerator _uids;
  final Clock _clock;

  /// Records that [amount] moved from [fromPayeeId] to [toPayeeId].
  ///
  /// [accountId] is the account the money landed in or left, and is **required whenever you are a
  /// party** — which is every settlement a single-user ledger normally records. It is null only for a
  /// settlement between two other people, which an accepted simplification plan can suggest and which
  /// moves none of your money.
  ///
  /// Decision 1 of the module plan, made concrete: money owed is not spendable until it arrives, and
  /// the moment it does it becomes an ordinary deposit in an account of the user's choosing. There is
  /// no separate split wallet and nothing to reconcile.
  ///
  /// Fails rather than guessing when the self payee is unset, when a settlement involving you names no
  /// account, or when the amount is not positive.
  Future<Result<SplitSettlement, Failure>> settle({
    required String fromPayeeId,
    required String toPayeeId,
    required Money amount,
    String? accountId,
    String? groupId,
    String? paymentMethodId,
    String? note,
    DateKey? on,
  }) async {
    if (!amount.isPositive) {
      return const Result.failure(
        ValidationFailure('A settlement needs an amount.', field: 'amount'),
      );
    }
    if (fromPayeeId == toPayeeId) {
      return const Result.failure(
        BusinessRuleFailure(
          'Paying yourself is not a settlement.',
          rule: 'splitSelfSettlement',
        ),
      );
    }

    final self = await _groups.selfPayeeId();
    if (self == null) {
      // Not an edge case worth papering over: with no self payee the module cannot tell which side of
      // any debt the user is on, so every balance it could show would be a guess.
      return const Result.failure(
        BusinessRuleFailure(
          'Choose which person is you before settling up.',
          rule: 'splitSelfPayeeUnset',
        ),
      );
    }

    final youArePaying = fromPayeeId == self;
    final youArePaid = toPayeeId == self;
    final involvesYou = youArePaying || youArePaid;

    if (involvesYou && accountId == null) {
      return const Result.failure(
        ValidationFailure(
          'Choose the account this money moved through.',
          field: 'accountId',
        ),
      );
    }

    final today = on ?? _clock.today();
    final settlementId = _uids.generate();

    final settlement = SplitSettlement(
      id: settlementId,
      fromPayeeId: fromPayeeId,
      toPayeeId: toPayeeId,
      amount: amount,
      dateKey: today,
      groupId: groupId,
      transactionId: involvesYou ? _uids.generate() : null,
      paymentMethodId: paymentMethodId,
      note: note,
    );

    return _ledger.recordSettlement(
      settlement: settlement,
      transaction: involvesYou
          ? _transactionFor(
              settlement: settlement,
              accountId: accountId!,
              youArePaid: youArePaid,
              today: today,
            )
          : null,
    );
  }

  /// Builds the ledger entry for a settlement you are part of.
  ///
  /// **A deposit when they pay you, a withdrawal when you pay them.** Money arriving is money you can
  /// spend from that instant — decision 1 again, from the other side: nothing marks it as
  /// split-related once it has landed, because a rupee that has arrived is just a rupee.
  ///
  /// `otherIn` and `otherOut` rather than a subtype of their own. A settlement is not a category of
  /// spending — the *original* expense already carried whatever category it deserved, and counting the
  /// repayment as spending too would double it in every analytics surface. Law L13 also makes a new
  /// enum member a schema contract, and one added to dodge a naming question is one nobody can remove.
  ///
  /// `needsReview` is false: the user just typed the amount, chose the account and confirmed. Flagging
  /// their own deliberate entry would make the review queue meaningless.
  Transaction _transactionFor({
    required SplitSettlement settlement,
    required String accountId,
    required bool youArePaid,
    required DateKey today,
  }) => Transaction(
    id: settlement.transactionId!,
    kind: youArePaid ? TransactionKind.deposit : TransactionKind.withdrawal,
    subtype: youArePaid
        ? TransactionSubtype.otherIn
        : TransactionSubtype.otherOut,
    occurredAtUtc: _clock.now(),
    dateKey: today,
    originalAmount: settlement.amount,
    needsReview: false,
    // A deposit fills an account and a withdrawal empties one; only the relevant side is set, which
    // is what `v_account_balances` reads to decide the direction.
    toAccountId: youArePaid ? accountId : null,
    fromAccountId: youArePaid ? null : accountId,
    paymentMethodId: settlement.paymentMethodId,
    // The counterparty, so the transaction is legible in the ledger on its own: "₹1,850 from Ravi"
    // rather than an unexplained deposit the user has to open the split module to understand.
    payeeId: youArePaid ? settlement.fromPayeeId : settlement.toPayeeId,
    note: settlement.note,
  );
}
