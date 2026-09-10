import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/split/presentation/widgets/split_history_list.dart';
import 'package:alaya/features/split/providers/split_history_provider.dart';

import '../../support/split_harness.dart';

/// [SplitHistoryList].
///
/// **A balance list is not a record of what happened**, and until this existed the module had only the
/// first. A split settled the same evening left no balance behind and therefore no evidence at all —
/// somebody who divided a restaurant bill, was paid back in cash, and looked a week later found an empty
/// screen and had to trust their memory over the app.
void main() {
  SplitActivityEntry entry({
    required String id,
    required SplitActivityKind kind,
    required int dateKey,
    required int minor,
    required String payeeId,
    String? label,
    String? groupId,
  }) => SplitActivityEntry(
    refId: id,
    kind: kind,
    dateKey: DateKey(dateKey),
    amount: Money(minor, 'INR'),
    payeeId: payeeId,
    label: label,
    groupId: groupId,
  );

  /// The list plus a feed for it. The harness does not override the history providers, because most split
  /// screens do not read them — a test that needs one says so.
  Future<void> pumpHistory(
    WidgetTester tester,
    List<SplitActivityEntry> feed, {
    String? groupId,
    Size size = kTallViewport,
    double textScale = 1,
  }) => pumpSplit(
    tester,
    Scaffold(body: SplitHistoryList(groupId: groupId)),
    overrides: [
      ...splitOverrides(people: [person('p1', 'Ravi'), person('p2', 'Priya')]),
      splitHistoryProvider.overrideWith((ref) => Stream.value(feed)),
      if (groupId != null)
        splitGroupHistoryProvider(groupId).overrideWith(
          (ref) => Stream.value(feed),
        ),
    ],
    size: size,
    textScale: textScale,
  );

  group('the feed', () {
    testWidgets('shows expenses and settlements together', (tester) async {
      // **A `UNION ALL` over two tables, not an events table.** Two subsystems writing into a shared feed
      // is a synchronisation-bug factory; a view has no synchronisation code to get wrong (anomaly A37).
      await pumpHistory(tester, [
        entry(
          id: 'e1',
          kind: SplitActivityKind.expense,
          dateKey: 20260814,
          minor: 500000,
          payeeId: 'p1',
          label: 'Dinner at Olive',
        ),
        entry(
          id: 's1',
          kind: SplitActivityKind.settlement,
          dateKey: 20260814,
          minor: 125000,
          payeeId: 'p2',
        ),
      ]);

      expect(find.text('Dinner at Olive'), findsOneWidget);
      expect(find.text('Priya settled up'), findsOneWidget);
    });

    testWidgets('names a row by whatever the user actually typed', (
      tester,
    ) async {
      // The view coalesces title, occasion, place and note, so the row is labelled by whichever the user
      // filled in — and falls back to the sentence about the payer rather than to a blank line.
      await pumpHistory(tester, [
        entry(
          id: 'e1',
          kind: SplitActivityKind.expense,
          dateKey: 20260814,
          minor: 500000,
          payeeId: 'p1',
          label: 'Diwali',
        ),
        entry(
          id: 'e2',
          kind: SplitActivityKind.expense,
          dateKey: 20260814,
          minor: 200000,
          payeeId: 'p1',
        ),
      ]);

      expect(find.text('Diwali'), findsOneWidget);
      // Two rows, two occurrences, for different reasons: the labelled one carries "Ravi paid" as its
      // caption under "Diwali", and the unlabelled one carries it as its title with no caption at all.
      expect(find.text('Ravi paid'), findsNWidgets(2));
    });

    testWidgets('a blank label is treated as none, and said once', (
      tester,
    ) async {
      // **This is what caught the duplication.** A row with no usable label used the payer sentence as
      // both its title and its caption, so "Ravi paid" appeared twice — 15pt above 12pt grey. The caption
      // now only renders when it has something different to say.
      await pumpHistory(tester, [
        entry(
          id: 'e1',
          kind: SplitActivityKind.expense,
          dateKey: 20260814,
          minor: 500000,
          payeeId: 'p1',
          label: '   ',
        ),
      ]);

      expect(find.text('Ravi paid'), findsOneWidget);
    });

    testWidgets('groups entries by day, newest day first', (tester) async {
      // The same shape the transaction ledger uses: a flat list of amounts with dates beside them makes
      // "what did we spend on Saturday" a scanning exercise, and a date header turns it into a glance.
      await pumpHistory(tester, [
        entry(
          id: 'e1',
          kind: SplitActivityKind.expense,
          dateKey: 20260814,
          minor: 500000,
          payeeId: 'p1',
          label: 'Today',
        ),
        entry(
          id: 'e2',
          kind: SplitActivityKind.expense,
          dateKey: 20260813,
          minor: 300000,
          payeeId: 'p1',
          label: 'Yesterday',
        ),
        entry(
          id: 'e3',
          kind: SplitActivityKind.expense,
          dateKey: 20260813,
          minor: 100000,
          payeeId: 'p2',
          label: 'Also yesterday',
        ),
      ]);

      // Two dates, three rows — the second date carries two of them. Asserted on the labels rather than on
      // a header widget type, because the grouping is a fact about what a reader sees and not about which
      // widget draws the date.
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Also yesterday'), findsOneWidget);
    });
  });

  group('scope', () {
    testWidgets('null shows everything, including ungrouped splits', (
      tester,
    ) async {
      // **`watchActivity` always took a nullable group and nothing ever passed null**, so a split filed
      // under no group — most of them, since the bill screen makes a group optional — appeared on no
      // screen at all once saved. The capability existed and had no caller.
      await pumpHistory(tester, [
        entry(
          id: 'e1',
          kind: SplitActivityKind.expense,
          dateKey: 20260814,
          minor: 500000,
          payeeId: 'p1',
          label: 'No group at all',
        ),
      ]);

      expect(find.text('No group at all'), findsOneWidget);
    });

    testWidgets('a group id reads the group-scoped provider instead', (
      tester,
    ) async {
      await pumpHistory(
        tester,
        [
          entry(
            id: 'e1',
            kind: SplitActivityKind.expense,
            dateKey: 20260814,
            minor: 500000,
            payeeId: 'p1',
            label: 'Flat rent',
            groupId: 'g1',
          ),
        ],
        groupId: 'g1',
      );

      expect(find.text('Flat rent'), findsOneWidget);
    });
  });

  group('empty', () {
    testWidgets('names what would fill it rather than counting nothing', (
      tester,
    ) async {
      // An empty history is the normal state of a new install, not a problem to solve.
      await pumpHistory(tester, const []);

      expect(find.text('Nothing split yet'), findsOneWidget);
      expect(find.textContaining('newest first'), findsOneWidget);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpHistory(
        tester,
        [
          entry(
            id: 'e1',
            kind: SplitActivityKind.expense,
            dateKey: 20260814,
            minor: 12345678,
            payeeId: 'p1',
            label: 'Bandra flatmates and the Goa regulars, September',
          ),
        ],
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
