import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/split/presentation/widgets/quick_split_card.dart';
import 'package:alaya/features/split/providers/split_bill_provider.dart';

import '../../support/split_harness.dart';

/// One `save` that reached the provider.
typedef RecordedSave = ({
  Money total,
  List<BillParticipant> participants,
  SplitMethod method,
  bool recordExpense,
});

/// A [SplitBill] that records what it was asked to write and writes nothing.
///
/// **Overriding the notifier rather than the repositories underneath it.** `SplitBill.save` reaches
/// `payeeRepositoryProvider` and `splitExpenseServiceProvider`, neither of which the split harness
/// supplies — so pressing the button in a widget test would throw on a provider that has nothing to do
/// with what is being tested. What matters here is *what the card asks for*, and that is exactly what this
/// captures.
class _RecordingSplitBill extends SplitBill {
  final List<RecordedSave> saves = [];

  @override
  Future<bool> save({
    required Money total,
    required List<BillParticipant> participants,
    required SplitMethod method,
    required bool recordExpense,
    String? expenseId,
    String? paidByPayeeId,
    // Added when the bill screen began composing a ledger note. **A fake overriding a method must track its
    // signature exactly**, and the compiler says so — which is the third time this cycle that widening a
    // contract has broken an implementer, after `FakeSplitLedger` and two construction sites.
    String? note,
    String? accountId,
    String? groupId,
    String? title,
    String? place,
    String? occasion,
    DateKey? on,
    DateKey? settleBy,
  }) async {
    saves.add((
      total: total,
      participants: participants,
      method: method,
      recordExpense: recordExpense,
    ));
    return true;
  }
}

/// [QuickSplitCard].
///
/// **The card exists to answer a bill in three taps**, so the tests are about what appears without anybody
/// being named, about the rounding — which is where a quick calculator quietly lies — and now about saving,
/// which used to mean crossing a whole screen to confirm inputs that were already on this card.
void main() {
  /// The card as the home screen actually mounts it: inside a scrolling list.
  ///
  /// **Not a bare `Scaffold(body: card)`, which is what the first version of this file used.** At a doubled
  /// text scale the card is taller than 640dp, and with nowhere to scroll it overflowed by 191 pixels — a
  /// failure the app cannot produce, because `SplitHomeScreen` puts it in a `ListView`. A host that differs
  /// from production tests a situation nobody can reach and misses the ones they can.
  ///
  /// The vertical dimension is therefore the list's problem and the horizontal one is the card's, which is
  /// what the U15 gate below still checks.
  Widget host() => Scaffold(
    // `ListView` has no const constructor — it does list work at build time — so the `const` moves inward
    // to the children, which do. `Scaffold` being const-constructible is what made the outer one look
    // correct.
    body: ListView(children: const [QuickSplitCard()]),
  );

  Future<void> enterAmount(WidgetTester tester, String rupees) async {
    await tester.enterText(find.byType(TextField).first, rupees);
    await tester.pump();
  }

  Future<void> tapPlus(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.widgetWithIcon(IconButton, Icons.add).first);
      await tester.pump();
    }
  }

  group('before there is an amount', () {
    testWidgets('shows a hint and no figures', (tester) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.textContaining('Type an amount'), findsOneWidget);
      expect(find.text('Each pays'), findsNothing);
      expect(find.text('Owed to you'), findsNothing);
    });
  });

  group('the split', () {
    testWidgets('divides as soon as an amount is typed', (tester) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await enterAmount(tester, '5000');
      await tapPlus(tester, 2); // two people become four

      expect(find.text('4'), findsOneWidget);
      expect(find.textContaining('1,250'), findsWidgets);
    });

    testWidgets('the stepper never goes below two', (tester) async {
      // One person is not a split, and the card's whole premise is dividing between people.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      final minus = find.widgetWithIcon(IconButton, Icons.remove).first;
      expect(tester.widget<IconButton>(minus).onPressed, isNull);
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('who paid', () {
    testWidgets('paying it all shows what you are owed', (tester) async {
      // ₹5,000 four ways: everybody else owes ₹1,250, so ₹3,750 comes back.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await enterAmount(tester, '5000');
      await tapPlus(tester, 2);

      expect(find.text('Owed to you'), findsOneWidget);
      expect(find.textContaining('3,750'), findsWidgets);
    });

    testWidgets('each their own shows no debt at all', (tester) async {
      // **Showing "owed to you" here would invent a debt.** Nobody owes anybody; the division is the whole
      // answer.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await enterAmount(tester, '5000');
      await tester.tap(find.text('Each their own'));
      await tester.pump();

      expect(find.text('Owed to you'), findsNothing);
      expect(find.text('Each pays'), findsOneWidget);
    });

    testWidgets('defaults to having paid, because that is why you are here', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      await enterAmount(tester, '5000');

      expect(find.text('Owed to you'), findsOneWidget);
    });
  });

  group('the rounding, which is where a quick calculator lies', () {
    testWidgets('the payer absorbs the odd paise and the card says so', (
      tester,
    ) async {
      // ₹1,000 three ways is ₹333.33 each with one paisa left. Giving it to the payer makes "₹333.33 each"
      // true for everybody who owes — which is the sentence being read out loud.
      //
      // An earlier version showed ₹333.34 as "each pays" while computing what was owed from ₹333.33: two
      // figures describing different splits, differing by the amount nobody would notice.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await enterAmount(tester, '1000');
      await tapPlus(tester, 1); // three people

      expect(find.textContaining('333.33'), findsWidgets);
      expect(find.textContaining('666.66'), findsWidgets);
      expect(find.textContaining('You cover the odd'), findsOneWidget);
    });

    testWidgets('an even division says nothing about a remainder', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      expect(find.textContaining('You cover the odd'), findsNothing);
      expect(find.textContaining('left over'), findsNothing);
    });

    testWidgets('with no payer the leftover is named, not hidden', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await enterAmount(tester, '1000');
      await tapPlus(tester, 1);
      await tester.tap(find.text('Each their own'));
      await tester.pump();

      expect(find.textContaining('left over'), findsOneWidget);
    });
  });

  group('saving, without leaving the screen', () {
    /// The card with a notifier that records instead of writing.
    Future<_RecordingSplitBill> pumpWithRecorder(
      WidgetTester tester, {
      String? self = 'me',
    }) async {
      final recorder = _RecordingSplitBill();
      await pumpSplit(
        tester,
        host(),
        overrides: [
          ...splitOverrides(self: self),
          splitBillProvider.overrideWith(() => recorder),
        ],
        size: kTallViewport,
      );
      return recorder;
    }

    testWidgets('is offered once you have paid a bill', (tester) async {
      // **This is #1b.** Keeping a split used to mean crossing to the bill editor to confirm inputs that
      // were already here.
      final _ = await pumpWithRecorder(tester);
      expect(find.text('Save to balances'), findsNothing);

      await enterAmount(tester, '5000');
      expect(find.text('Save to balances'), findsOneWidget);
    });

    testWidgets('is not offered when everybody pays their own', (
      tester,
    ) async {
      // No debt exists, so there is nothing to record. A button that wrote an empty split would be worse
      // than none.
      await pumpWithRecorder(tester);
      await enterAmount(tester, '5000');
      await tester.tap(find.text('Each their own'));
      await tester.pump();

      expect(find.text('Save to balances'), findsNothing);
    });

    testWidgets('is not offered before the app knows who you are', (
      tester,
    ) async {
      // A balance has no direction without `split.selfPayeeId`: nothing can say whether the others owe you
      // or you owe them, so every figure saved would be a guess.
      await pumpWithRecorder(tester, self: null);
      await enterAmount(tester, '5000');

      expect(find.text('Save to balances'), findsNothing);
    });

    testWidgets('puts you in your own split', (tester) async {
      // **The assertion that guards the over-owing bug.** Four anonymous participants with you as payer
      // means four strangers each owing a quarter — ₹5,000 owed to you on a ₹5,000 bill, when one of those
      // four *was* you. Participant one is the user; the rest are unnamed.
      final recorder = await pumpWithRecorder(tester);
      await enterAmount(tester, '5000');
      await tapPlus(tester, 2); // four people
      await tester.tap(find.text('Save to balances'));
      await tester.pump();

      expect(recorder.saves, hasLength(1));
      final save = recorder.saves.single;
      expect(save.participants, hasLength(4));
      expect(save.participants.first.payeeId, 'me');
      expect(
        save.participants.skip(1).every((p) => p.payeeId == null),
        isTrue,
      );
      expect(save.total.minor, 500000);
      expect(save.method, SplitMethod.equal);
    });

    testWidgets('records the debt and not the money', (tester) async {
      // Recording the expense needs an account, and an account picker on a three-tap card is the screen this
      // exists to avoid. The caption says so rather than leaving it to be found while reconciling.
      final recorder = await pumpWithRecorder(tester);
      await enterAmount(tester, '5000');

      // **Read before the tap, not after.** A successful save clears the card — the test below asserts
      // exactly that — so the whole result block, caption included, is gone by the time the button has been
      // pressed. Checking afterwards was two of my own tests contradicting each other.
      expect(
        find.textContaining("account balance isn't touched"),
        findsOneWidget,
      );

      await tester.tap(find.text('Save to balances'));
      await tester.pump();
      expect(recorder.saves.single.recordExpense, isFalse);
    });

    testWidgets('clears itself afterwards', (tester) async {
      // A card still showing the figures it just wrote looks like it did nothing, and the next bill gets
      // typed on top of the last one.
      await pumpWithRecorder(tester);
      await enterAmount(tester, '5000');
      await tapPlus(tester, 2);
      await tester.tap(find.text('Save to balances'));
      await tester.pump();

      expect(find.textContaining('1,250'), findsNothing);
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('the way on', () {
    testWidgets('copying needs no names', (tester) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(people: []),
        size: kTallViewport,
      );
      await enterAmount(tester, '5000');

      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the fuller editor is offered once there is a result', (
      tester,
    ) async {
      // **Was "Add names", and the rename is not cosmetic.** With saving on the card, this button is the way
      // to a tip, a split method, who paid and an account — somebody wanting to add 10% would never press
      // something labelled "Add names".
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('More options'), findsNothing);
      await enterAmount(tester, '5000');
      expect(find.text('More options'), findsOneWidget);
    });
  });

  group('the U15 gate', () {
    testWidgets('no horizontal overflow at 320dp with the scaler doubled', (
      tester,
    ) async {
      // **Horizontal is the card's responsibility; vertical is the list's.** Every row pairing a label with
      // a figure is a `Wrap`, which is what this holds — a `Row` there is the shape that overran the home
      // screen by 215 pixels on the right.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kNarrowPhone,
        textScale: 2,
      );

      await enterAmount(tester, '1234567');
      await tapPlus(tester, 5);
      expect(tester.takeException(), isNull);
    });
  });
}
