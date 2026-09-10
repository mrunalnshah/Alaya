import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/split/settlement_service.dart';

import '../../support/split_fakes.dart';

/// [SettlementService].
///
/// **The write whose failure a user could not see**, and until now the one with no test. A settlement
/// that reaches the ledger without its transaction clears a debt with no money anywhere — the whole
/// reason `recordSettlement` takes both and writes them in one database transaction.
void main() {
  late FakeSplitLedger ledger;
  late FakeSplitGroups groups;
  late SettlementService service;
  final clock = FixedClock(DateTime.utc(2026, 8, 14, 9));

  Money inr(int minor) => Money(minor, 'INR');

  setUp(() {
    ledger = FakeSplitLedger();
    groups = FakeSplitGroups(self: 'me');
    service = SettlementService(
      ledger: ledger,
      groups: groups,
      uids: SeqUids(),
      clock: clock,
    );
  });

  group('they pay you', () {
    test('writes a deposit into the chosen account', () async {
      final result = await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(185000),
        accountId: 'ac-1',
      );

      expect(result.isOk, isTrue);
      final recorded = ledger.settlements.single;
      final tx = recorded.transaction!;
      expect(tx.kind, TransactionKind.deposit);
      // A deposit fills an account; only that side is set, which is what `v_account_balances` reads.
      expect(tx.toAccountId, 'ac-1');
      expect(tx.fromAccountId, isNull);
      expect(tx.originalAmount, inr(185000));
    });

    test('names the counterparty, so the ledger row is legible alone', () async {
      // "₹1,850 from Ravi", not an unexplained deposit somebody has to open the split module to
      // understand.
      await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(185000),
        accountId: 'ac-1',
      );
      expect(ledger.settlements.single.transaction!.payeeId, 'ravi');
    });
  });

  group('you pay them', () {
    test('writes a withdrawal out of the chosen account', () async {
      await service.settle(
        fromPayeeId: 'me',
        toPayeeId: 'priya',
        amount: inr(40000),
        accountId: 'ac-1',
      );

      final tx = ledger.settlements.single.transaction!;
      expect(tx.kind, TransactionKind.withdrawal);
      expect(tx.fromAccountId, 'ac-1');
      expect(tx.toAccountId, isNull);
      expect(tx.payeeId, 'priya');
    });
  });

  group('the subtype is not a category', () {
    test('otherIn and otherOut, never a spending category', () async {
      // The *original* expense already carried whatever category it deserved. Counting the repayment
      // as spending too would double it in every analytics surface — and Law L13 makes a new enum
      // member a schema contract, so one added to dodge a naming question is one nobody can remove.
      await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(1000),
        accountId: 'ac-1',
      );
      await service.settle(
        fromPayeeId: 'me',
        toPayeeId: 'priya',
        amount: inr(1000),
        accountId: 'ac-1',
      );

      expect(
        ledger.settlements.map((s) => s.transaction!.subtype),
        [TransactionSubtype.otherIn, TransactionSubtype.otherOut],
      );
    });

    test('needsReview is false — the user just typed it', () async {
      await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(1000),
        accountId: 'ac-1',
      );
      expect(ledger.settlements.single.transaction!.needsReview, isFalse);
    });
  });

  group('the settlement and its transaction are one write', () {
    test('both carry the same id link', () async {
      await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(1000),
        accountId: 'ac-1',
      );
      final recorded = ledger.settlements.single;
      expect(recorded.settlement.transactionId, recorded.transaction!.id);
    });

    test(
      'a settlement between two other people carries no transaction',
      () async {
        // None of the user's money moves, so there is no account to put it through. An accepted
        // simplification plan can suggest one of these.
        final result = await service.settle(
          fromPayeeId: 'ravi',
          toPayeeId: 'priya',
          amount: inr(1000),
        );

        expect(result.isOk, isTrue);
        expect(ledger.settlements.single.transaction, isNull);
        expect(ledger.settlements.single.settlement.transactionId, isNull);
      },
    );
  });

  group('refusals', () {
    test('an account is required whenever you are a party', () async {
      // **The refusal that protects the central claim.** Without it a settlement of the user's own
      // money could reach the ledger with nothing in their account to match — the one failure in this
      // module they could not see.
      final result = await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(1000),
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(ledger.settlements, isEmpty);
    });

    test('an unset self payee stops everything', () async {
      // With nobody claimed, nothing can say which side of a debt the user is on, so every balance
      // would be a guess. Better to refuse than to record a direction nobody chose.
      groups.self = null;
      final result = await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(1000),
        accountId: 'ac-1',
      );

      expect(
        (result.failureOrNull as BusinessRuleFailure?)?.rule,
        'splitSelfPayeeUnset',
      );
      expect(ledger.settlements, isEmpty);
    });

    test('paying yourself is not a settlement', () async {
      final result = await service.settle(
        fromPayeeId: 'me',
        toPayeeId: 'me',
        amount: inr(1000),
        accountId: 'ac-1',
      );
      expect(
        (result.failureOrNull as BusinessRuleFailure?)?.rule,
        'splitSelfSettlement',
      );
    });

    test('a non-positive amount is refused', () async {
      for (final amount in [inr(0), inr(-100)]) {
        final result = await service.settle(
          fromPayeeId: 'ravi',
          toPayeeId: 'me',
          amount: amount,
          accountId: 'ac-1',
        );
        expect(result.failureOrNull, isA<ValidationFailure>());
      }
      expect(ledger.settlements, isEmpty);
    });
  });

  group('the date', () {
    test('comes from the clock unless given', () async {
      await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(1000),
        accountId: 'ac-1',
      );
      expect(
        ledger.settlements.single.settlement.dateKey,
        const DateKey(20260814),
      );
    });

    test('is honoured when a back-dated payment is recorded', () async {
      await service.settle(
        fromPayeeId: 'ravi',
        toPayeeId: 'me',
        amount: inr(1000),
        accountId: 'ac-1',
        on: const DateKey(20260801),
      );
      final recorded = ledger.settlements.single;
      expect(recorded.settlement.dateKey, const DateKey(20260801));
      // The transaction must agree, or the account ledger and the split ledger disagree about when.
      expect(recorded.transaction!.dateKey, const DateKey(20260801));
    });
  });
}
