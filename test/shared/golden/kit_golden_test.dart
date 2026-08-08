import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Goldens for the three display widgets the shared kit adds, light and dark.
///
/// Unlike `widget_golden_test.dart`, this harness installs `Localizations`: `DateText.relative`
/// reads "Today" and "Yesterday" from the ARB, and a date formatter that cannot say those words in
/// the user's language is not a date formatter. `flutter gen-l10n` therefore has to have run — which
/// the documented codegen order guarantees.
void main() {
  // Fixed so "Today" and "Yesterday" are the same two days on every machine and every run.
  final clock = FixedClock(DateTime(2026, 8, 1, 9, 30));
  const today = DateKey(20260801);
  const yesterday = DateKey(20260731);
  const older = DateKey(20260114);

  Widget harness(
    Widget child, {
    required bool dark,
    Size size = const Size(320, 200),
  }) => MaterialApp(
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
    // Inside the app: WidgetsApp re-establishes MediaQuery from the view, so a pin placed
    // above MaterialApp never reaches the widget under test.
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: inner!,
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Padding(
            padding: const EdgeInsets.all(AlayaSpacing.md),
            child: child,
          ),
        ),
      ),
    ),
  );

  Future<void> expectGolden(
    WidgetTester tester,
    Widget child,
    String name, {
    required bool dark,
    Size size = const Size(320, 200),
  }) async {
    await tester.pumpWidget(harness(child, dark: dark, size: size));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.${dark ? "dark" : "light"}.png'),
    );
  }

  group('DateText', () {
    Widget sample() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const DateText(older, style: DateTextStyle.full),
        const DateText(older),
        const DateText(older, style: DateTextStyle.dayMonth),
        DateText.relative(today, clock: clock),
        DateText.relative(yesterday, clock: clock),
        DateText.relative(older, clock: clock, muted: true),
      ],
    );

    testWidgets(
      'light',
      (tester) => expectGolden(tester, sample(), 'date_text', dark: false),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(tester, sample(), 'date_text', dark: true),
    );
  });

  group('KeyValueRow', () {
    Widget sample() => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const KeyValueRow(label: 'Payee', value: 'Reliance Fresh'),
        const KeyValueRow(
          label: 'Amount',
          valueWidget: AmountText(Money(-125050, 'INR')),
        ),
        const KeyValueRow(label: 'Date', valueWidget: DateText(older)),
        // Renders nothing at all — the gap below "Date" is the point of the golden.
        const KeyValueRow(label: 'Note'),
        KeyValueRow(label: 'Account', value: 'HDFC Savings', onTap: () {}),
      ],
    );

    testWidgets(
      'light',
      (tester) => expectGolden(
        tester,
        sample(),
        'key_value_row',
        dark: false,
        size: const Size(320, 280),
      ),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(
        tester,
        sample(),
        'key_value_row',
        dark: true,
        size: const Size(320, 280),
      ),
    );
  });

  group('StatusChip', () {
    Widget sample() => Center(
      child: Wrap(
        spacing: AlayaSpacing.xs,
        runSpacing: AlayaSpacing.xs,
        children: [
          const StatusChip(label: 'Receipt deleted'),
          const StatusChip(label: 'Needs details', tone: StatusTone.info),
          const StatusChip(
            label: 'Expiring soon',
            tone: StatusTone.warning,
            icon: Icons.schedule,
          ),
          const StatusChip(label: 'Overdue', tone: StatusTone.danger),
          const StatusChip(label: 'Paid', tone: StatusTone.success),
          StatusChip(
            label: '3 need details',
            tone: StatusTone.info,
            onTap: () {},
          ),
        ],
      ),
    );

    testWidgets(
      'light',
      (tester) => expectGolden(
        tester,
        sample(),
        'status_chip',
        dark: false,
        size: const Size(320, 220),
      ),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(
        tester,
        sample(),
        'status_chip',
        dark: true,
        size: const Size(320, 220),
      ),
    );
  });
}
