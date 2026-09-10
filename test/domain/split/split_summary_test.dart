import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/domain/services/split/split_summary_builder.dart';

/// [SplitSummaryBuilder].
///
/// **The UPI tests are gone with the UPI link**, and their absence is the point: a `upi://` intent
/// needed major-unit conversion, zero-padded fractions, percent-encoded fields and a currency
/// parameter — four things that could each be subtly wrong in a way that opens a payment app with the
/// wrong number. A line of free text has none of them, and works outside India.
void main() {
  const builder = SplitSummaryBuilder();
  Money inr(int minor) => Money(minor, 'INR');

  SplitBalance owedToMe(String id, int minor) =>
      SplitBalance(payeeId: id, owedToMe: inr(minor), iOwe: inr(0));

  SplitBalance iOwe(String id, int minor) =>
      SplitBalance(payeeId: id, owedToMe: inr(0), iOwe: inr(minor));

  SplitSummary build(
    List<SplitBalance> balances, {
    String? handle,
  }) => builder.build(
    balances: balances,
    nameOf: (id) => id == 'ravi' ? 'Ravi' : 'Priya',
    // A fake formatter, so these tests assert the builder's assembly rather than
    // `MoneyFormatter`'s grouping rules — which have their own tests and are not what this file is
    // about.
    formatAmount: (amount) => '${amount.currencyCode} ${amount.minor}',
    labels: const SummaryLabels(
      heading: 'Goa trip',
      owesYou: 'Owes you',
      youOwe: 'You owe',
      payMeAt: 'Pay me at:',
    ),
    paymentHandle: handle,
  );

  group('the summary', () {
    test('names both directions', () {
      final summary = build([owedToMe('ravi', 185000), iOwe('priya', 40000)]);
      expect(summary.text, contains('Owes you Ravi: INR 185000'));
      expect(summary.text, contains('You owe Priya: INR 40000'));
    });

    test('drops settled counterparties', () {
      final settled = SplitBalance(
        payeeId: 'ravi',
        owedToMe: inr(5000),
        iOwe: inr(5000),
      );
      expect(build([settled]).isEmpty, isTrue);
    });

    test('an empty set produces the heading and nothing else', () {
      final summary = build(const []);
      expect(summary.isEmpty, isTrue);
      expect(summary.text.trim(), 'Goa trip');
    });

    test('is perfectly useful with no payment handle', () {
      final summary = build([owedToMe('ravi', 185000)]);
      expect(summary.text, contains('Ravi'));
      expect(summary.text, isNot(contains('Pay me at')));
    });
  });

  group('the payment handle', () {
    test('closes the message when somebody owes you', () {
      final summary = build([owedToMe('ravi', 185000)], handle: 'me@bank');
      expect(summary.text, endsWith('Pay me at: me@bank'));
    });

    test(
      'is anything at all, because it makes no claim about how money moves',
      () {
        // The whole reason it replaced a `upi://` link: this works in every country, and the app does not
        // have to know which one it is in.
        for (final handle in [
          'me@okhdfc',
          'paypal.me/mrunal',
          'IBAN DE89 3704 0044 0532 0130 00',
          'Venmo @mrunal',
          'cash is fine',
        ]) {
          expect(
            build([owedToMe('ravi', 100)], handle: handle).text,
            endsWith('Pay me at: $handle'),
          );
        }
      },
    );

    test('is omitted when the user only owes people', () {
      // Asking to be paid on a summary where every line is a debt the user holds reads as a mistake.
      final summary = build([iOwe('priya', 40000)], handle: 'me@bank');
      expect(summary.text, isNot(contains('Pay me at')));
    });

    test('a blank handle is treated as none', () {
      final summary = build([owedToMe('ravi', 100)], handle: '   ');
      expect(summary.text, isNot(contains('Pay me at')));
    });
  });
}
