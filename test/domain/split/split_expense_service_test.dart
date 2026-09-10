import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/split/split_expense_service.dart';
import 'package:alaya/domain/services/split/split_resolver.dart';

import '../../support/split_fakes.dart';

/// [SplitExpenseService].
///
/// **The first test this service has had.** It turns instructions into stored shares, which means a
/// fault here is a wrong debt rather than a crash — the kind nothing surfaces until somebody argues
/// about money.
void main() {
  late FakeSplitLedger ledger;
  late SplitExpenseService service;
  final clock = FixedClock(DateTime.utc(2026, 8, 14, 9));

  Money inr(int minor) => Money(minor, 'INR');

  setUp(() {
    ledger = FakeSplitLedger();
    service = SplitExpenseService(
      ledger: ledger,
      uids: SeqUids(),
      clock: clock,
    );
  });

  group('record', () {
    test('resolves shares through the real resolver', () async {
      // ₹1,000 three ways is not ₹333.33 three times. The service runs `SplitResolver` for real, so
      // this asserts the same allocation production performs — a fake resolver here would prove only
      // that the fake was consistent with itself.
      final result = await service.record(
        total: inr(100000),
        paidByPayeeId: 'me',
        method: SplitMethod.equal,
        inputs: const [
          ShareInput.equal('a'),
          ShareInput.equal('b'),
          ShareInput.equal('c'),
        ],
      );

      final saved = ledger.saved.single;
      expect(saved.shares.map((s) => s.amount.minor), [33334, 33333, 33333]);
      expect(saved.allocated, inr(100000));
      expect(result.isOk, isTrue);
    });

    test('stores the input beside the resolved amount', () async {
      // Both, so reopening a 50/30/20 split shows 50/30/20 rather than three amounts the user has to
      // reverse-engineer.
      await service.record(
        total: inr(100000),
        paidByPayeeId: 'me',
        method: SplitMethod.percent,
        inputs: const [
          ShareInput.percent('a', 5000),
          ShareInput.percent('b', 3000),
          ShareInput.percent('c', 2000),
        ],
      );

      final shares = ledger.saved.single.shares;
      expect(
        shares.map((s) => s.inputKind),
        everyElement(ShareInputKind.percent),
      );
      expect(shares.map((s) => s.inputValue), [5000, 3000, 2000]);
      expect(shares.map((s) => s.amount.minor), [50000, 30000, 20000]);
    });

    test('saves a split whose shares do not cover the total', () async {
      // **A real state, not an error.** Percentages reaching 90% mid-edit, or a tip nobody assigned.
      // `transaction_lines` treats an un-itemised transaction exactly this way (ARCH_2 §4.2), and
      // refusing would make the editor unusable while somebody is still typing.
      final result = await service.record(
        total: inr(100000),
        paidByPayeeId: 'me',
        method: SplitMethod.percent,
        inputs: const [ShareInput.percent('a', 9000)],
      );

      expect(result.isOk, isTrue);
      expect(ledger.saved.single.unallocated, inr(10000));
    });

    test('refuses perLine, which is recorded line by line', () async {
      final result = await service.record(
        total: inr(100000),
        paidByPayeeId: 'me',
        method: SplitMethod.perLine,
        inputs: const [ShareInput.equal('a')],
      );

      expect(
        (result.failureOrNull as BusinessRuleFailure?)?.rule,
        'splitUseRecordItemised',
      );
      expect(ledger.saved, isEmpty);
    });

    test('turns a resolver refusal into a failure, not a crash', () async {
      // The resolver throws `ArgumentError` for things a user cannot cause — percent mixed with
      // weights. Letting it escape would crash a controller; surfacing it lets a screen say something.
      final result = await service.record(
        total: inr(100000),
        paidByPayeeId: 'me',
        method: SplitMethod.percent,
        inputs: const [
          ShareInput.percent('a', 5000),
          ShareInput.equal('b'),
        ],
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(ledger.saved, isEmpty);
    });

    test('dates from the clock when no date is given', () async {
      await service.record(
        total: inr(1000),
        paidByPayeeId: 'me',
        method: SplitMethod.equal,
        inputs: const [ShareInput.equal('a')],
      );
      expect(ledger.saved.single.dateKey, const DateKey(20260814));
    });

    test('reuses the id it is handed, so an edit replaces', () async {
      await service.record(
        id: 'existing',
        total: inr(1000),
        paidByPayeeId: 'me',
        method: SplitMethod.equal,
        inputs: const [ShareInput.equal('a')],
      );
      expect(ledger.saved.single.id, 'existing');
    });

    test('surfaces a repository refusal', () async {
      ledger.rejectSave = true;
      final result = await service.record(
        total: inr(1000),
        paidByPayeeId: 'me',
        method: SplitMethod.equal,
        inputs: const [ShareInput.equal('a')],
      );
      expect(result.isFailure, isTrue);
    });
  });

  group('recordItemised', () {
    test('writes one share per person per line', () async {
      // **The shape session 4b's API gap exposed.** `SplitResolver.resolvePerLine` aggregates per
      // person — right for showing somebody their total, wrong for writing rows, because the schema
      // wants `transactionLineNo` on each. Summing first would discard the line the column names.
      final result = await service.recordItemised(
        total: inr(180000),
        paidByPayeeId: 'me',
        transactionId: 'tx-1',
        lines: const [
          SplitLine(
            lineNo: 1,
            amount: Money(120000, 'INR'),
            inputs: [
              ShareInput.equal('ravi'),
              ShareInput.equal('a'),
              ShareInput.equal('b'),
              ShareInput.equal('c'),
            ],
          ),
          SplitLine(
            lineNo: 2,
            amount: Money(40000, 'INR'),
            inputs: [ShareInput.equal('ravi')],
          ),
          SplitLine(
            lineNo: 3,
            amount: Money(20000, 'INR'),
            inputs: [
              ShareInput.equal('ravi'),
              ShareInput.equal('a'),
              ShareInput.equal('b'),
              ShareInput.equal('c'),
            ],
          ),
        ],
      );

      expect(result.isOk, isTrue);
      final shares = ledger.saved.single.shares;
      // Four on the platter, one on the dessert, four on the delivery.
      expect(shares, hasLength(9));
      expect(shares.map((s) => s.transactionLineNo).toSet(), {1, 2, 3});

      // Ravi's total is a sum over lines: 30000 + 40000 + 5000.
      final ravi = shares
          .where((s) => s.payeeId == 'ravi')
          .fold(0, (sum, s) => sum + s.amount.minor);
      expect(ravi, 75000);
    });

    test('drops a zero share on a line', () async {
      // Per line a zero would be a row per person per item they did not order — most of them, sitting
      // in `split_shares` forever. On a whole-expense split a zero is meaningful and is kept.
      await service.recordItemised(
        total: inr(10000),
        paidByPayeeId: 'me',
        transactionId: 'tx-1',
        lines: const [
          SplitLine(
            lineNo: 1,
            amount: Money(10000, 'INR'),
            inputs: [ShareInput.shares('a', 1), ShareInput.shares('b', 0)],
          ),
        ],
      );

      final shares = ledger.saved.single.shares;
      expect(shares, hasLength(1));
      expect(shares.single.payeeId, 'a');
    });

    test('refuses an empty line list', () async {
      final result = await service.recordItemised(
        total: inr(10000),
        paidByPayeeId: 'me',
        transactionId: 'tx-1',
        lines: const [],
      );
      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('names the line when one cannot be resolved', () async {
      final result = await service.recordItemised(
        total: inr(10000),
        paidByPayeeId: 'me',
        transactionId: 'tx-1',
        lines: const [
          SplitLine(
            lineNo: 7,
            amount: Money(10000, 'INR'),
            inputs: [
              ShareInput.percent('a', 5000),
              ShareInput.shares('b', 1),
            ],
          ),
        ],
      );
      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(result.failureOrNull!.message, contains('7'));
    });
  });

  group('remove', () {
    test('deletes the split and says nothing about the transaction', () async {
      await service.remove('se-1');
      expect(ledger.deleted, ['se-1']);
    });
  });
}
