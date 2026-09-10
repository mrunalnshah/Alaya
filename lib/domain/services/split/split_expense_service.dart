import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/domain/repositories/split_ledger_repository.dart';
import 'package:alaya/domain/services/split/split_resolver.dart';

/// Turns split instructions into a persisted expense, in both directions the module supports.
///
/// ## The two cases
///
/// **You paid.** Cash left your account, so a `transactions` withdrawal for the *full* amount already
/// exists and [transactionId] points at it. The split is attached to a transaction the expense editor
/// has already saved — this service never creates one, which is what keeps money movement in
/// `TransactionRepository` where its own validation lives.
///
/// **Somebody else paid.** No money has left your account, so there is **no transaction at all**
/// until you settle. [transactionId] is null and `paidByPayeeId` names who covered it.
///
/// The ordering is forced and it is the safe one: an expense saved without its split leaves a
/// transaction the user can see and re-split. There is no path that writes a split against a
/// transaction that does not exist, because the repository refuses a `transactionLineNo` on an expense
/// with no transaction and the id has to come from a save that already succeeded.
///
/// ## What it does not do
///
/// It does not resolve *and* store two versions of the same answer. `SplitResolver` decides the
/// amounts, and both the resolved figure and the input that produced it are written — so reopening a
/// 40/30/30 split shows 40/30/30 rather than three amounts the user has to reverse-engineer.
final class SplitExpenseService {
  /// Creates the service.
  const SplitExpenseService({
    required SplitLedgerRepository ledger,
    required UidGenerator uids,
    required Clock clock,
    SplitResolver resolver = const SplitResolver(),
  }) : _ledger = ledger,
       _uids = uids,
       _clock = clock,
       _resolver = resolver;

  final SplitLedgerRepository _ledger;
  final UidGenerator _uids;
  final Clock _clock;
  final SplitResolver _resolver;

  /// Records a split of [total] among [inputs].
  ///
  /// [id] is supplied when re-saving an existing split, so an edit replaces rather than duplicates.
  ///
  /// **A split whose shares do not sum to the total is saved, not refused.** Percentages that reach
  /// 90%, or a tip nobody assigned, are real states — `SplitExpense.unallocated` reports the gap and
  /// the screen decides what to say. `transaction_lines` already treats an un-itemised transaction
  /// exactly this way (ARCH_2 §4.2), and refusing would make the editor unusable mid-typing.
  Future<Result<SplitExpense, Failure>> record({
    required Money total,
    required String paidByPayeeId,
    required List<ShareInput> inputs,
    required SplitMethod method,
    String? id,
    String? transactionId,
    String? groupId,
    String? title,
    String? place,
    String? occasion,
    String? note,
    DateKey? on,
    DateKey? settleBy,
    SplitConversion? converted,
  }) async {
    if (method == SplitMethod.perLine) {
      return const Result.failure(
        BusinessRuleFailure(
          'An itemised split is recorded line by line.',
          rule: 'splitUseRecordItemised',
        ),
      );
    }

    final SplitResolution resolution;
    try {
      resolution = _resolver.resolve(total: total, inputs: inputs);
    } on ArgumentError catch (error) {
      // The resolver throws only for things a user cannot cause — no participants, the same person
      // twice, percent mixed with weights. Surfacing them as a failure rather than letting an
      // `ArgumentError` escape means a controller can show a message instead of crashing.
      return Result.failure(
        ValidationFailure(
          error.message?.toString() ?? 'That split could not be worked out.',
          field: 'inputs',
        ),
      );
    }

    final expenseId = id ?? _uids.generate();
    return _ledger.saveExpense(
      SplitExpense(
        id: expenseId,
        paidByPayeeId: paidByPayeeId,
        total: total,
        dateKey: on ?? _clock.today(),
        splitMethod: method,
        shares: [
          for (final share in resolution.shares)
            _shareOf(share, expenseId: expenseId),
        ],
        groupId: groupId,
        transactionId: transactionId,
        title: title,
        place: place,
        occasion: occasion,
        note: note,
        settleByDateKey: settleBy,
        converted: converted,
      ),
    );
  }

  /// Records an itemised split: each line divided among its own participants.
  ///
  /// **The feature the competition charges for**, and it rests on `transaction_lines`, which this app
  /// already had for the grocery-into-inventory flow. The ₹400 dessert is one line with one
  /// participant; the ₹1,200 platter is one line split four ways; each person's total is a sum over
  /// lines rather than a division of the bill.
  ///
  /// **Each line is resolved separately rather than through `SplitResolver.resolvePerLine`**, and the
  /// distinction is not cosmetic. `resolvePerLine` aggregates per person — which is exactly right for
  /// showing somebody their total, and wrong for writing rows, because the schema wants one share per
  /// person *per line* so `split_shares.transactionLineNo` can carry which item it was. Summing first
  /// would discard the line the row is supposed to name.
  ///
  /// Requires [transactionId]: itemising needs the receipt, and the receipt is the transaction's own
  /// lines. The repository enforces the same rule, and the schema enforces the half of it that fits in
  /// a single-row CHECK.
  Future<Result<SplitExpense, Failure>> recordItemised({
    required Money total,
    required String paidByPayeeId,
    required String transactionId,
    required List<SplitLine> lines,
    String? id,
    String? groupId,
    String? title,
    String? place,
    String? occasion,
    String? note,
    DateKey? on,
    DateKey? settleBy,
    SplitConversion? converted,
  }) async {
    if (lines.isEmpty) {
      return const Result.failure(
        ValidationFailure(
          'An itemised split needs at least one line.',
          field: 'lines',
        ),
      );
    }

    final expenseId = id ?? _uids.generate();
    final shares = <SplitShare>[];
    for (final line in lines) {
      final SplitResolution resolved;
      try {
        resolved = _resolver.resolve(total: line.amount, inputs: line.inputs);
      } on ArgumentError catch (error) {
        return Result.failure(
          ValidationFailure(
            'Line ${line.lineNo}: '
            '${error.message?.toString() ?? 'that split could not be worked out.'}',
            field: 'lines',
          ),
        );
      }
      for (final share in resolved.shares) {
        // A zero share is dropped rather than written. On a whole-expense split a zero is meaningful —
        // "she was there and did not eat" — but per line it would be a row per person per item they
        // did not order, which is most of them, and every one would sit in `split_shares` forever.
        if (share.amount.isZero) continue;
        shares.add(
          _shareOf(share, expenseId: expenseId, lineNo: line.lineNo),
        );
      }
    }

    return _ledger.saveExpense(
      SplitExpense(
        id: expenseId,
        paidByPayeeId: paidByPayeeId,
        total: total,
        dateKey: on ?? _clock.today(),
        splitMethod: SplitMethod.perLine,
        shares: shares,
        groupId: groupId,
        transactionId: transactionId,
        title: title,
        place: place,
        occasion: occasion,
        note: note,
        settleByDateKey: settleBy,
        converted: converted,
      ),
    );
  }

  /// Removes a split, leaving any linked transaction alone.
  ///
  /// The money did move. Deleting the split is a statement about who owed what, not about whether the
  /// payment happened — so the expense stays in the account ledger and only the debt disappears.
  Future<Result<void, Failure>> remove(String id) => _ledger.deleteExpense(id);

  /// Builds one share row from a resolved share.
  ///
  /// A resolved share carries the inputs that produced it — a list, because per line one person can
  /// appear several times. Here exactly one applies, since each line is resolved on its own.
  SplitShare _shareOf(
    ResolvedShare share, {
    required String expenseId,
    int? lineNo,
  }) {
    final input = share.inputs.first;
    return SplitShare(
      id: _uids.generate(),
      splitExpenseId: expenseId,
      payeeId: share.payeeId,
      amount: share.amount,
      inputKind: input.kind,
      inputValue: input.value,
      transactionLineNo: lineNo,
    );
  }
}
