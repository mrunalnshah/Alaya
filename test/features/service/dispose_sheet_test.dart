import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/features/service/presentation/sheets/dispose_sheet.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/dispose_providers.dart';
import 'package:alaya/features/service/state/dispose_state.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/service_harness.dart';

/// **This sheet reads no async source, so it has no loading or error state and none is faked.** Its only
/// inputs are a chip row, a date and two optional fields; an `AsyncValue` branch would be unreachable
/// code asserted by an unreachable test. §9.1's four states apply where there is something to await.
void main() {
  const args = (assetId: 'asset-1', currencyCode: 'INR');

  List<Override> overrides({DisposeState? seed}) => [
    clockProvider.overrideWithValue(kServiceClock),
    serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    disposeProvider.overrideWith(
      () => _StubDispose(
        seed ??
            const DisposeState(
              assetId: 'asset-1',
              currencyCode: 'INR',
              dateKey: kToday,
            ),
      ),
    ),
  ];

  Widget host() => const Scaffold(
    body: AlayaBottomSheet(
      child: DisposeSheet(assetId: 'asset-1', currencyCode: 'INR'),
    ),
  );

  testWidgets('it says what disposal will not do', (tester) async {
    await pumpService(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    // Anomaly A30 out loud: a user reaching for this button is entitled to know nothing is destroyed.
    expect(find.text('What happened to it?'), findsOneWidget);
    expect(
      find.textContaining('what you spent on it still counts'),
      findsOneWidget,
    );
  });

  testWidgets('every reason is offered', (tester) async {
    await pumpService(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    expect(
      find.byType(ChoiceChip),
      findsNWidgets(AssetDisposalReason.values.length),
    );
    expect(find.text('Sold it'), findsOneWidget);
    expect(find.text('Broke'), findsOneWidget);
  });

  testWidgets('nothing is chosen until the user picks', (tester) async {
    await pumpService(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    final selected = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((chip) => chip.selected);
    expect(selected, isEmpty);
  });

  testWidgets('the recovered amount is optional', (tester) async {
    await pumpService(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    // Most disposals recover nothing — a broken kettle is thrown away, not sold — and requiring a zero
    // would make the common case extra typing.
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.text('Got back'), findsOneWidget);
  });

  testWidgets('committing with no reason shakes rather than closing', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        seed: const DisposeState(
          assetId: 'asset-1',
          currencyCode: 'INR',
          dateKey: kToday,
          reasonMissing: true,
          shakeTrigger: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShakeOnError), findsOneWidget);
    expect(find.text('Pick what happened'), findsOneWidget);
  });

  testWidgets('a rejection is shown in the repository own words', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        seed: const DisposeState(
          assetId: 'asset-1',
          currencyCode: 'INR',
          dateKey: kToday,
          reason: AssetDisposalReason.sold,
          rejection: 'That asset is already disposed.',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('already disposed'), findsOneWidget);
  });

  testWidgets('a chosen reason and a recovered amount both show', (
    tester,
  ) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        seed: const DisposeState(
          assetId: 'asset-1',
          currencyCode: 'INR',
          dateKey: kToday,
          reason: AssetDisposalReason.sold,
          amount: Money(1500000, 'INR'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final selected = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((chip) => chip.selected)
        .length;
    expect(selected, 1);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpService(tester, host(), overrides: overrides(), textScale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpService(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubDispose extends DisposeNotifier {
  _StubDispose(this._value);

  final DisposeState _value;

  @override
  DisposeState build(DisposeArgs arg) => _value;
}
