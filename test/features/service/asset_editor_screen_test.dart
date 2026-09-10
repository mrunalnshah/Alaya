import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/service/presentation/screens/asset_editor_screen.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/state/asset_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/service_harness.dart';

/// Four states, plus the rule that makes one table hold a television and a house maid.
void main() {
  AssetEditorState state({
    String name = 'Living room TV',
    AssetType type = AssetType.electronics,
    int? priceMinor = 4500000,
    DateKey? warrantyStart = const DateKey(20260131),
    DateKey? warrantyEnd = const DateKey(20270131),
    AssetSaveIssue? issue,
    String? rejection,
  }) => AssetEditorState(
    currencyCode: 'INR',
    name: name,
    type: type,
    purchasePrice: priceMinor == null ? null : Money(priceMinor, 'INR'),
    warrantyStartDateKey: warrantyStart,
    warrantyEndDateKey: warrantyEnd,
    issue: issue,
    rejection: rejection,
  );

  // The override goes on the **family**: a NotifierProvider family instance has no `overrideWith`.
  List<Override> overrides(AsyncValue<AssetEditorState> value) => [
    assetEditorProvider.overrideWith(() => _StubEditor(value)),
    serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('an unknown asset reads as not found', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(assetId: 'nope'),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new asset opens on the form, which is its empty state', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(AsyncValue.data(state(name: '', priceMinor: null))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.text('What is it?'), findsOneWidget);
  });

  testWidgets('a thing is asked for a brand, a model and a price', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Brand'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
    expect(find.byType(AmountField), findsOneWidget);
  });

  testWidgets('a person is asked for none of them', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(name: 'Lakshmi', type: AssetType.serviceProvider),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Hidden rather than offered and left blank: an empty "Serial" on a human being is worse than its
    // absence, and that omission is what lets one table hold both cases.
    expect(find.text('Brand'), findsNothing);
    expect(find.text('Model'), findsNothing);
    expect(find.text('Serial'), findsNothing);
    expect(find.byType(AmountField), findsNothing);
    expect(
      find.textContaining('A person you pay regularly belongs here too'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a person is still asked for a phone number and a service interval',
    (tester) async {
      await pumpService(
        tester,
        const AssetEditorScreen(),
        overrides: overrides(
          AsyncValue.data(
            state(name: 'Lakshmi', type: AssetType.serviceProvider),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Both moved behind the door in the density pass — Contact and Service are refinements once the
      // asset is identified. The behaviour is unchanged and this asserts it: one tap, both fields
      // present. A person is still asked for exactly what a person needs.
      await tester.tap(find.text('More details'));
      await tester.pumpAndSettle();
      // The two fields that matter for a person: how to reach her, and how often she comes.
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Service every'), findsOneWidget);
    },
  );

  testWidgets('a blank name is refused at the field, not in a snack', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(
        AsyncValue.data(state(name: '', issue: AssetSaveIssue.nameMissing)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This is required'), findsWidgets);
  });

  testWidgets('a backwards warranty says which field is wrong', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(
            warrantyStart: const DateKey(20260601),
            warrantyEnd: const DateKey(20260101),
            issue: AssetSaveIssue.warrantyBackwards,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('The warranty cannot end before it starts'), findsWidgets);
  });

  testWidgets('a rejection is shown in the repository own words', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(
            issue: AssetSaveIssue.rejected,
            rejection: 'An asset with that name already exists.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('already exists'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(AsyncValue.data(state())),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the state', () {
    test('disposal fields are never written by a save', () {
      final asset = state().toAsset(newId: 'a1', normalizedName: 'tv');
      // Retiring something goes through `AssetRepository.dispose`, which records a reason with the
      // status change. A save that could set `status: disposed` would be a second write path (Law U22).
      expect(asset.disposedAtDateKey, isNull);
      expect(asset.disposalReason, isNull);
      expect(asset.disposalAmount, isNull);
      expect(asset.status, AssetStatus.active);
    });

    test('an issue survives an unrelated copyWith', () {
      final base = state(issue: AssetSaveIssue.nameMissing);
      // ARCH_4 R31: a bare assignment let `submitting: false` in a `finally` erase the reason before the
      // screen read it.
      expect(
        base.copyWith(submitting: false).issue,
        AssetSaveIssue.nameMissing,
      );
      expect(base.copyWith(clearIssue: true).issue, isNull);
    });
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubEditor extends AssetEditorNotifier {
  _StubEditor(this._value);

  final AsyncValue<AssetEditorState> _value;

  @override
  AsyncValue<AssetEditorState> build(String? arg) => _value;
}
