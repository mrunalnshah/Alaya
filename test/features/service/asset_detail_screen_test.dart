import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/service_record.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/presentation/widgets/contact_action.dart';
import 'package:alaya/features/service/providers/asset_detail_providers.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/service_harness.dart';

/// Four states, and the §7.2 rows this screen closes: a call action, a salary history, and a disposed
/// asset that is still fully readable.
///
/// **The history sliver sits below the fold, so its assertions pass `skipOffstage: false`.** The
/// diagnostic that found this reported `sliver 2 RenderSliverList: scrollExtent=100.0 paintExtent=0.0
/// visible=false` while `AlayaTimeline: 1 in tree` — the widget is built, and a `Finder` skips
/// off-screen widgets by default. Scrolling first would also work, but the question these tests ask is
/// whether the screen *builds* the right thing, not whether 584 logical pixels happen to reach it.
///
/// **No test asserts a ledger badge.** With the expense toggle on by default a service reaching the
/// ledger is the rule rather than the exception, so the chip was removed as noise — marking the *inverse*
/// would carry information, and is a design decision nobody has taken.
///
/// **And `SectionHeader` upper-cases its label**, so a header is found as `SALARY HISTORY`, never as the
/// ARB string. Both are ARCH_4 P6: the harness, not the product (five failures, zero defects).
void main() {
  const id = 'asset-1';

  List<Override> overrides({
    List<Asset>? inUse,
    List<Asset> disposed = const [],
    List<ServiceRecord> records = const [],
    Map<String, Money> lifetime = const {},
    bool pending = false,
    bool fail = false,
  }) => [
    clockProvider.overrideWithValue(kServiceClock),
    serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    serviceCurrencyProvider.overrideWith((ref) async => 'INR'),
    assetsInUseProvider.overrideWith(
      (ref) => Stream.value(inUse ?? [television()]),
    ),
    disposedAssetsProvider.overrideWith((ref) => Stream.value(disposed)),
    lifetimeServiceCostProvider(id).overrideWith((ref) async => lifetime),
    assetTemplatesProvider(
      id,
    ).overrideWith((ref) => Stream.value(const <RecurringTemplate>[])),
    if (pending)
      serviceRecordsProvider(
        id,
      ).overrideWith((ref) => pendingStream<List<ServiceRecord>>())
    else if (fail)
      serviceRecordsProvider(id).overrideWith(
        (ref) => Stream<List<ServiceRecord>>.error(StateError('boom')),
      )
    else
      serviceRecordsProvider(id).overrideWith((ref) => Stream.value(records)),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(pending: true),
    );
    await tester.pump();
    expect(find.byType(AlayaListSkeleton, skipOffstage: false), findsWidgets);
  });

  testWidgets('an unknown id reads as not found rather than as an error', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: 'nope'),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
  });

  testWidgets('a failed history read shows the real reason', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(fail: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState, skipOffstage: false), findsOneWidget);
    expect(find.textContaining('boom', skipOffstage: false), findsOneWidget);
  });

  testWidgets('populated shows the hero, the details and the history', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(records: [serviceRecord()]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.text('LG'), findsOneWidget);
    expect(find.byType(AlayaTimeline, skipOffstage: false), findsOneWidget);
    expect(find.text('Serviced', skipOffstage: false), findsOneWidget);
  });

  testWidgets('a phone number becomes a call action', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(inUse: [television(contactPhone: '+911234567890')]),
    );
    await tester.pumpAndSettle();
    // §7.2: `primaryContactPhone` is reachable as an action, not just readable as text.
    expect(find.byType(ContactAction), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
  });

  testWidgets('no phone number offers no call action', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(inUse: [television()]),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ContactAction), findsNothing);
  });

  testWidgets('a person shows a salary history and offers a payment', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(
        inUse: [maid(id: id)],
        records: [
          serviceRecord(
            assetId: id,
            type: ServiceRecordType.salaryPaid,
            costMinor: 800000,
            providerName: 'Lakshmi',
          ),
        ],
        lifetime: const {'INR': Money(800000, 'INR')},
      ),
    );
    await tester.pumpAndSettle();
    // The maid case end to end: her own wording, her own history, her own lifetime total — one table.
    expect(find.text('SALARY HISTORY', skipOffstage: false), findsWidgets);
    expect(find.text('Salary paid', skipOffstage: false), findsOneWidget);
    expect(find.text('Record a payment'), findsOneWidget);
    expect(find.text('Paid so far'), findsOneWidget);
  });

  testWidgets('a linked recurring template is shown against the person', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(inUse: [maid(id: id)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paid on a schedule'), findsOneWidget);
  });

  testWidgets('a disposed asset stays fully readable and offers a way back', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(
        inUse: const [],
        disposed: [
          television(
            status: AssetStatus.disposed,
            disposedAt: const DateKey(20260601),
            disposalReason: AssetDisposalReason.sold,
            disposalMinor: 1500000,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    // Anomaly A30: the price paid survives disposal, and so does everything else about it.
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.text('Disposed'), findsWidgets);
    expect(find.text('Bring it back'), findsOneWidget);
    expect(find.text('Dispose of it'), findsNothing);
  });

  testWidgets('lifetime service cost is one figure per currency, never summed', (
    tester,
  ) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(
        records: [serviceRecord()],
        lifetime: const {
          'INR': Money(120000, 'INR'),
          'USD': Money(4500, 'USD'),
        },
      ),
    );
    await tester.pumpAndSettle();
    // Adding them would invent an exchange rate the user never agreed to (Law L1).
    expect(find.text('Spent on service so far'), findsOneWidget);
    expect(find.textContaining('1,200.00'), findsWidgets);
    expect(find.textContaining('45.00'), findsWidgets);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(
        inUse: [
          television(
            name: 'A television with a name long enough to wrap twice over',
            contactPhone: '+911234567890',
            nextService: const DateKey(20260715),
            serviceIntervalDays: 180,
          ),
        ],
        records: [
          serviceRecord(),
          serviceRecord(id: 'rec-2', costMinor: null),
        ],
        lifetime: const {'INR': Money(120000, 'INR')},
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
      const AssetDetailScreen(assetId: id),
      overrides: overrides(
        inUse: [television(contactPhone: '+911234567890')],
        records: [serviceRecord()],
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
