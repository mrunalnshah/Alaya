import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/qty_text.dart';

/// Goldens for the one shared widget Phase 6B adds (ARCH_5 §9.2), light and dark.
void main() {
  final entries = [
    const AlayaTimelineEntry(
      title: 'Thrown away',
      trailing: QtyText(Qty(500000, UnitCategory.weight)),
      subtitle: DateText(
        DateKey(20260801),
        style: DateTextStyle.medium,
        muted: true,
      ),
      meta: 'Mouldy',
      icon: Icons.north_east,
      tone: TimelineTone.outgoing,
      badge: 'Reversed',
    ),
    const AlayaTimelineEntry(
      title: 'Used',
      trailing: QtyText(Qty(250000, UnitCategory.weight)),
      subtitle: DateText(
        DateKey(20260729),
        style: DateTextStyle.medium,
        muted: true,
      ),
      icon: Icons.north_east,
      tone: TimelineTone.superseded,
    ),
    const AlayaTimelineEntry(
      title: 'Bought',
      trailing: QtyText(Qty(2000000, UnitCategory.weight)),
      subtitle: DateText(
        DateKey(20260715),
        style: DateTextStyle.medium,
        muted: true,
      ),
      icon: Icons.south_west,
      tone: TimelineTone.incoming,
    ),
  ];

  Future<void> pumpTimeline(WidgetTester tester, {required bool dark}) async {
    tester.view.physicalSize =
        const Size(360, 400) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark
            ? AlayaTheme.dark(AlayaPresets.activePreset)
            : AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              AlayaTimeline(
                itemCount: entries.length,
                itemBuilder: (context, index) => entries[index],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AlayaTimeline', () {
    testWidgets('light', (tester) async {
      await pumpTimeline(tester, dark: false);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/alaya_timeline.light.png'),
      );
    });

    testWidgets('dark', (tester) async {
      await pumpTimeline(tester, dark: true);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/alaya_timeline.dark.png'),
      );
    });
  });
}
