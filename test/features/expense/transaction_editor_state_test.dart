import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';

/// Pure unit tests for the editor's state — no widgets, no providers, no database.
///
/// This is where the rules that would otherwise only be visible through the UI get asserted: the
/// subtypes a kind may take, the unallocated arithmetic that must never auto-balance, and the
/// copyWith clear flags that are the difference between "leave it alone" and "the user cleared it".
void main() {
  const inr = 'INR';
  const today = DateKey(20260801);

  TransactionEditorState seed({
    TransactionKind kind = TransactionKind.withdrawal,
    TransactionSubtype subtype = TransactionSubtype.grocery,
    Money? amount,
    List<TransactionLine> lines = const [],
  }) => TransactionEditorState(
    currencyCode: inr,
    dateKey: today,
    kind: kind,
    subtype: subtype,
    amount: amount,
    lines: lines,
  );

  TransactionLine line(String id, int minor) => TransactionLine(
    id: id,
    transactionId: 'tx-1',
    lineNo: 1,
    description: 'Potatoes',
    destination: TransactionLineDestination.inventory,
    lineAmount: Money(minor, inr),
  );

  group('availableSubtypes', () {
    test('a deposit cannot be a grocery purchase', () {
      final subtypes = seed(kind: TransactionKind.deposit).availableSubtypes;
      expect(subtypes, contains(TransactionSubtype.salaryIn));
      expect(subtypes, isNot(contains(TransactionSubtype.grocery)));
    });

    test('a transfer has exactly one', () {
      expect(
        seed(kind: TransactionKind.transfer).availableSubtypes,
        [TransactionSubtype.transferSelf],
      );
    });

    test('a withdrawal offers the six spending shapes', () {
      final subtypes = seed().availableSubtypes;
      expect(subtypes, hasLength(6));
      expect(subtypes, contains(TransactionSubtype.electronics));
      expect(subtypes, contains(TransactionSubtype.transferOut));
    });

    test('every kind offers at least one, so the picker is never empty', () {
      for (final kind in TransactionKind.values) {
        expect(
          seed(kind: kind).availableSubtypes,
          isNotEmpty,
          reason: kind.name,
        );
      }
    });
  });

  group('allocation', () {
    test('no lines means no total and nothing unallocated', () {
      final state = seed(amount: const Money(50000, inr));
      expect(state.lineTotal, isNull);
      // With no lines at all the difference equals the whole amount, which is not a mismatch —
      // showing a chip here would accuse the user of an error they have not made (anomaly A11).
      expect(state.unallocated, isNull);
    });

    test('lines that sum to the amount leave nothing unallocated', () {
      final state = seed(
        amount: const Money(50000, inr),
        lines: [line('l1', 30000), line('l2', 20000)],
      );
      expect(state.lineTotal, const Money(50000, inr));
      expect(state.unallocated, isNull);
    });

    test('a shortfall is reported and never balanced away', () {
      final state = seed(
        amount: const Money(50000, inr),
        lines: [line('l1', 48000)],
      );
      expect(state.unallocated, const Money(2000, inr));
      // The lines are untouched: the transaction amount is the source of truth and the lines are
      // optional detail, so forcing them equal would invent a purchase.
      expect(state.lineTotal, const Money(48000, inr));
    });

    test(
      'lines exceeding the amount give a negative difference rather than zero',
      () {
        final state = seed(
          amount: const Money(50000, inr),
          lines: [line('l1', 60000)],
        );
        expect(state.unallocated, const Money(-10000, inr));
      },
    );

    test('a line with no amount contributes nothing', () {
      final state = seed(
        amount: const Money(50000, inr),
        lines: [
          const TransactionLine(
            id: 'l1',
            transactionId: 'tx-1',
            lineNo: 1,
            description: 'Unpriced',
            destination: TransactionLineDestination.none,
          ),
        ],
      );
      expect(state.lineTotal, Money.zero(inr));
      expect(state.unallocated, const Money(50000, inr));
    });
  });

  group('copyWith', () {
    test('marks the state dirty by default, for the unsaved-changes guard', () {
      expect(seed().dirty, isFalse);
      expect(seed().copyWith(subtype: TransactionSubtype.bill).dirty, isTrue);
    });

    test(
      'an explicit dirty:false wins, so a completed save can clear the guard',
      () {
        expect(seed().copyWith(dirty: false).dirty, isFalse);
      },
    );

    test('a null argument leaves a nullable field alone', () {
      final state = seed(amount: const Money(1000, inr));
      expect(state.copyWith().amount, const Money(1000, inr));
    });

    test('a clear flag is what actually clears one', () {
      final state = seed(amount: const Money(1000, inr));
      expect(state.copyWith(clearAmount: true).amount, isNull);
    });

    test('clearing one nullable does not disturb the others', () {
      final state = seed().copyWith(
        fromAccountId: 'acc-1',
        payeeId: 'pay-1',
        paymentMethodId: 'pm-1',
      );
      final cleared = state.copyWith(clearPayee: true);
      expect(cleared.payeeId, isNull);
      expect(cleared.fromAccountId, 'acc-1');
      expect(cleared.paymentMethodId, 'pm-1');
    });

    test('the currency survives every copy — Law L9 has no setter for it', () {
      final state = seed(amount: const Money(1000, inr));
      expect(state.copyWith(amount: const Money(2000, inr)).currencyCode, inr);
    });
  });

  group('toTransaction', () {
    test(
      'uses the supplied id when creating and keeps its own when editing',
      () {
        final when = DateTime.utc(2026, 8, 1, 4);
        final created = seed(
          amount: const Money(1000, inr),
        ).toTransaction(newId: 'new-1', occurredAtUtc: when);
        expect(created.id, 'new-1');

        final editing = seed(
          amount: const Money(1000, inr),
        ).copyWith(id: 'tx-9');
        expect(
          editing.toTransaction(newId: 'new-1', occurredAtUtc: when).id,
          'tx-9',
        );
      },
    );

    test('a missing amount becomes zero rather than throwing', () {
      // save() rejects a null amount before ever calling this, but the entity cannot hold null —
      // so the fallback exists and is asserted rather than left to chance.
      final built = seed().toTransaction(
        newId: 'new-1',
        occurredAtUtc: DateTime.utc(2026, 8, 1, 4),
      );
      expect(built.originalAmount, Money.zero(inr));
    });

    test('the date carries through as a civil date', () {
      final built = seed(amount: const Money(1000, inr)).toTransaction(
        newId: 'new-1',
        occurredAtUtc: DateTime.utc(2026, 8, 1, 4),
      );
      expect(built.dateKey, today);
      expect(built.monthKey, 202608);
    });
  });

  group('fromTransaction', () {
    final source = Transaction(
      id: 'tx-1',
      kind: TransactionKind.transfer,
      subtype: TransactionSubtype.transferSelf,
      occurredAtUtc: DateTime.utc(2026, 8, 1, 4),
      dateKey: today,
      originalAmount: const Money(500000, inr),
      needsReview: true,
      fromAccountId: 'acc-1',
      toAccountId: 'acc-2',
    );

    test('round trips the fields the editor owns', () {
      final state = TransactionEditorState.fromTransaction(
        source,
        lines: const [],
        tagIds: const {'tag-1'},
      );
      expect(state.id, 'tx-1');
      expect(state.amount, const Money(500000, inr));
      expect(state.currencyCode, inr);
      expect(state.needsReview, isTrue);
      expect(state.tagIds, {'tag-1'});
      expect(state.isEditing, isTrue);
    });

    test(
      'opens clean, so loading a record does not trip the unsaved guard',
      () {
        final state = TransactionEditorState.fromTransaction(
          source,
          lines: const [],
          tagIds: const {},
        );
        expect(state.dirty, isFalse);
      },
    );

    test('a transfer loads with the own-account toggle already set', () {
      final state = TransactionEditorState.fromTransaction(
        source,
        lines: const [],
        tagIds: const {},
      );
      expect(state.toOwnAccount, isTrue);
    });

    test('a withdrawal does not', () {
      final withdrawal = Transaction(
        id: 'tx-2',
        kind: TransactionKind.withdrawal,
        subtype: TransactionSubtype.grocery,
        occurredAtUtc: DateTime.utc(2026, 8, 1, 4),
        dateKey: today,
        originalAmount: const Money(1000, inr),
        needsReview: false,
        fromAccountId: 'acc-1',
      );
      final state = TransactionEditorState.fromTransaction(
        withdrawal,
        lines: const [],
        tagIds: const {},
      );
      expect(state.toOwnAccount, isFalse);
    });
  });
}
