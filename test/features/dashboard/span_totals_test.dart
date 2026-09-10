import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';

/// `SpanTotals.from` is a pure mapping, so it is tested as one — no provider, no repository, no pump.
/// The three decisions it encodes are all invisible from the screen and all wrong in a way a reader
/// would believe: a transfer counted twice, a second currency added to the first, an empty span
/// reporting two confident zeroes.
void main() {
  Transaction tx({
    required String id,
    required TransactionKind kind,
    required int minor,
    String currency = 'INR',
  }) => Transaction(
    id: id,
    kind: kind,
    // Irrelevant to the mapping, which reads only `kind` and `originalAmount`.
    subtype: TransactionSubtype.otherOut,
    occurredAtUtc: DateTime.utc(2026, 8, 10),
    dateKey: const DateKey(20260810),
    originalAmount: Money(minor, currency),
    needsReview: false,
  );

  test(
    'deposits and increases count in, withdrawals and decreases count out',
    () {
      final totals = SpanTotals.from([
        tx(id: 't1', kind: TransactionKind.deposit, minor: 50000),
        tx(id: 't2', kind: TransactionKind.adjustmentIncrease, minor: 500),
        tx(id: 't3', kind: TransactionKind.withdrawal, minor: 12000),
        tx(id: 't4', kind: TransactionKind.adjustmentDecrease, minor: 300),
      ]);

      expect(totals.inMinor, 50500);
      expect(totals.outMinor, 12300);
      expect(totals.currencyCode, 'INR');
      expect(totals.isEmpty, isFalse);
    },
  );

  test('a transfer counts as neither', () {
    // Money moving between your own accounts is not spending and not income. Counting it as both
    // would double the totals of anyone who moves money in order to save it.
    final totals = SpanTotals.from([
      tx(id: 't1', kind: TransactionKind.transfer, minor: 99999),
    ]);

    expect(totals.inMinor, 0);
    expect(totals.outMinor, 0);
  });

  test('a second currency is skipped rather than added to the first', () {
    // Adding minor units across currencies produces a number that looks right and is not. Converting
    // properly needs the frozen-rate path, which belongs to analytics — so the figure stays honest by
    // covering less.
    final totals = SpanTotals.from([
      tx(id: 't1', kind: TransactionKind.withdrawal, minor: 10000),
      tx(
        id: 't2',
        kind: TransactionKind.withdrawal,
        minor: 7000,
        currency: 'USD',
      ),
    ]);

    expect(totals.outMinor, 10000);
    expect(totals.currencyCode, 'INR');
  });

  test('an empty span reports empty, not zero', () {
    // The screen hides the figures when this is true. Two zeroes read like a finding — "you spent
    // nothing" — where nothing was measured at all.
    expect(SpanTotals.from(const []).isEmpty, isTrue);
  });
}
