import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/presentation/widgets/asset_row.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/service_harness.dart';

/// Four states, 320dp at a doubled text scale, and both accessibility floors (ARCH_5 §9.1).
void main() {
  List<Override> overrides({
    List<Asset>? inUse,
    List<Asset> disposed = const [],
    bool pending = false,
    bool fail = false,
  }) => [
    clockProvider.overrideWithValue(kServiceClock),
    serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    disposedAssetsProvider.overrideWith((ref) => Stream.value(disposed)),
    if (pending)
      assetsInUseProvider.overrideWith((ref) => pendingStream<List<Asset>>())
    else if (fail)
      assetsInUseProvider.overrideWith(
        (ref) => Stream<List<Asset>>.error(StateError('boom')),
      )
    else
      assetsInUseProvider.overrideWith(
        (ref) => Stream.value(inUse ?? const <Asset>[]),
      ),
  ];

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(pending: true),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'empty invites the first asset and says a person belongs here too',
    (tester) async {
      await pumpService(
        tester,
        const AssetListScreen(),
        overrides: overrides(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
      // §7.2's maid case has to be discoverable from the empty state, or nobody ever finds it.
      expect(
        find.textContaining('the person who helps around the house'),
        findsOneWidget,
      );
    },
  );

  testWidgets('error shows the real reason with a retry', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(fail: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('populated groups by kind', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(inUse: [television(), maid()]),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AssetRowTile), findsNWidgets(2));
    expect(find.text('Electronics'), findsOneWidget);
    // A person gets her own group, labelled as people rather than as equipment.
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Lakshmi'), findsOneWidget);
  });

  testWidgets('a disposed asset is hidden until the filter asks for it', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(
        inUse: [television()],
        disposed: [
          television(
            id: 'asset-9',
            name: 'Old kettle',
            status: AssetStatus.disposed,
            disposedAt: const DateKey(20260601),
            disposalReason: AssetDisposalReason.damaged,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    // Nothing is ever deleted (anomaly A30), so the kettle exists — it is simply not something you own.
    expect(find.text('Old kettle'), findsNothing);
    await tester.tap(find.text('Include disposed'));
    await tester.pumpAndSettle();
    expect(find.text('Old kettle'), findsOneWidget);
    expect(find.text('Disposed'), findsOneWidget);
  });

  testWidgets('an overdue service is derived from the clock, not a stored flag', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(
        // Due in July against a clock fixed to 1 August. Nothing on the entity says "overdue".
        inUse: [
          television(
            nextService: const DateKey(20260715),
            serviceIntervalDays: 180,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Service due'), findsWidgets);
  });

  testWidgets('a warranty still running reads as covered', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(
        inUse: [television(warrantyEnd: const DateKey(20270131))],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('In warranty'), findsOneWidget);
    expect(find.text('Out of warranty'), findsNothing);
  });

  testWidgets('a warranty already past reads as expired', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(
        inUse: [television(warrantyEnd: const DateKey(20260601))],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Out of warranty'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(
        inUse: [
          television(
            name: 'A television with a name long enough to wrap twice over',
            nextService: const DateKey(20260715),
            linkedRecurringTemplateId: 'tpl-1',
          ),
          maid(),
        ],
      ),
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
      const AssetListScreen(),
      overrides: overrides(inUse: [television(), maid()]),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
