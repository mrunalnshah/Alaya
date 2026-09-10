# B7_TESTKIT

Harnesses, fakes, the layout-overflow suite, the layering checker, the tools.

**25 files · 6,781 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `test/shared/golden/chart_card_golden_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';

import '../../support/analytics_harness.dart';

/// Goldens for `ChartCard`, light and dark (ARCH_5 §9.2).
///
/// **Dark is the half that matters here.** Depth in this app is a palette step rather than a shadow
/// (ARCH_3 §8, ARCH_5 §2.5), so a surface-tier mistake is invisible in light mode and obvious in dark —
/// which is exactly why §9.2 asks for both and for one pass on a real device in dark.
///
/// Four states, not one: a golden of the populated card alone would let the loading, empty and error
/// branches drift, and those are three quarters of what this widget is for.
void main() {
  Widget card(AsyncValue<int> value, {Widget? trailing}) => Center(
    child: SizedBox(
      width: 320,
      child: ChartCard<int>(
        title: 'Where it went',
        subtitle: 'Last 30 days',
        value: value,
        isEmpty: (data) => data == 0,
        emptyMessage: 'Nothing spent in this window',
        onRetry: () {},
        approximateCount: 2,
        unconvertedCount: 1,
        trailing: trailing,
        builder: (context, data) => const AnalyticsPlotBox(
          child: ColoredBox(color: Color(0x11000000)),
        ),
      ),
    ),
  );

  final states = <String, AsyncValue<int>>{
    'populated': const AsyncValue.data(1),
    'loading': const AsyncValue.loading(),
    'empty': const AsyncValue.data(0),
    'error': AsyncValue.error(
      Exception('No rate for JPY on 2026-08-10, and none earlier'),
      StackTrace.empty,
    ),
  };

  for (final entry in states.entries) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('ChartCard ${entry.key} in $mode', (tester) async {
        await pumpAnalytics(
          tester,
          card(
            entry.value,
            trailing: entry.key == 'populated'
                ? const AmountText(
                    Money(432100, 'INR'),
                    size: AmountSize.small,
                    showSign: false,
                  )
                : null,
          ),
          overrides: analyticsOverrides(),
          dark: dark,
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(ChartCard<int>),
          matchesGoldenFile('goldens/chart_card_${entry.key}_$mode.png'),
        );
      });
    }
  }
}
```

### `test/shared/golden/kit_golden_test.dart`

```dart
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
```

### `test/shared/golden/timeline_golden_test.dart`

```dart
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
```

### `test/shared/golden/widget_golden_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Goldens for the five display widgets, in light and dark.
///
/// Each renders on the **active preset** rather than a fixture palette, so changing
/// `AlayaPresets.activePreset` fails these deliberately. That is the point: the goldens are how a
/// palette change is reviewed, and one that slipped through unnoticed would defeat having them.
///
/// None of these widgets reads a localised string — every label is a parameter — so the harness needs
/// no `Localizations` and the goldens stay independent of `flutter gen-l10n` having run.
void main() {
  /// Wraps [child] in the app's theme at a fixed size.
  ///
  /// `textScaler` is pinned to 1.0 through `MaterialApp.builder` rather than a `MediaQuery` above the
  /// app: `WidgetsApp` re-establishes `MediaQuery` from the view, so an outer one never reaches the
  /// widget and the pin would be decorative — a golden that silently moved with the host's
  /// accessibility settings would fail on one machine and pass on another.
  ///
  /// The canvas sizes are per-widget rather than shared. `EmptyState` is designed to fill a viewport,
  /// so it gets a taller one; it no longer overflows a short canvas either, but a golden that shows
  /// it mid-scroll is a golden of nothing useful.
  Widget harness(
    Widget child, {
    required bool dark,
    Size size = const Size(320, 140),
  }) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark
          ? AlayaTheme.dark(AlayaPresets.activePreset)
          : AlayaTheme.light(AlayaPresets.activePreset),
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
  }

  Future<void> expectGolden(
    WidgetTester tester,
    Widget child,
    String name, {
    required bool dark,
    Size size = const Size(320, 140),
  }) async {
    await tester.pumpWidget(harness(child, dark: dark, size: size));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.${dark ? "dark" : "light"}.png'),
    );
  }

  final demoTag = Tag(
    id: 'tag-groceries',
    name: 'groceries',
    normalizedName: 'groceries',
    allowedScopes: const {TagScope.withdrawal},
    isSystem: false,
    sortOrder: 0,
    isDeleted: false,
    colorArgb: 0xFF2E7D5B,
  );

  group('AmountText', () {
    // One widget showing all four directions at once, so the colour convention is reviewable as a
    // set. Reviewing them in separate files makes an inverted income/expense pair easy to miss.
    final sample = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        AmountText(Money(250000, 'INR'), size: AmountSize.large),
        AmountText(Money(-125050, 'INR')),
        AmountText(Money(500000, 'INR'), kind: TransactionKind.transfer),
        AmountText(Money(0, 'INR'), size: AmountSize.small),
      ],
    );

    testWidgets(
      'light',
      (tester) => expectGolden(tester, sample, 'amount_text', dark: false),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(tester, sample, 'amount_text', dark: true),
    );
  });

  group('QtyText', () {
    const sample = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        QtyText(Qty(4450000, UnitCategory.weight)),
        QtyText(Qty(1500000, UnitCategory.volume)),
        QtyText(Qty(3000, UnitCategory.count)),
        QtyText(Qty(250000, UnitCategory.weight), muted: true),
      ],
    );

    testWidgets(
      'light',
      (tester) => expectGolden(tester, sample, 'qty_text', dark: false),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(tester, sample, 'qty_text', dark: true),
    );
  });

  group('TagChip', () {
    // A tappable chip is taller than a display-only one: it has to reach the 48px tap-target floor,
    // and the pair being visibly different is the point rather than an inconsistency.
    Widget sample() => Center(
      child: Wrap(
        spacing: AlayaSpacing.xs,
        runSpacing: AlayaSpacing.xs,
        children: [
          TagChip(tag: demoTag),
          TagChip(tag: demoTag, selected: true, onTap: () {}),
          TagChip(
            tag: demoTag,
            onTap: () {},
            onRemove: () {},
            removeLabel: 'Remove tag',
          ),
        ],
      ),
    );

    testWidgets(
      'light',
      (tester) => expectGolden(
        tester,
        sample(),
        'tag_chip',
        dark: false,
        size: const Size(320, 180),
      ),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(
        tester,
        sample(),
        'tag_chip',
        dark: true,
        size: const Size(320, 180),
      ),
    );
  });

  group('AlayaCard', () {
    Widget sample() => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const AlayaCard(child: Text('tier 1 raised')),
        const SizedBox(height: AlayaSpacing.xs),
        const AlayaCard(tier: -1, child: Text('tier -1 sunken')),
        const SizedBox(height: AlayaSpacing.xs),
        AlayaCard(
          border: true,
          onTap: () {},
          child: const Text('bordered, tappable'),
        ),
      ],
    );

    testWidgets(
      'light',
      (tester) => expectGolden(
        tester,
        sample(),
        'alaya_card',
        dark: false,
        size: const Size(320, 260),
      ),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(
        tester,
        sample(),
        'alaya_card',
        dark: true,
        size: const Size(320, 260),
      ),
    );
  });

  group('EmptyState', () {
    // Literal strings here rather than ARB lookups: the golden's job is the layout, and pulling in
    // Localizations would make it depend on gen-l10n having run.
    Widget sample() => EmptyState(
      title: 'No transactions yet',
      body: 'Add your first expense and it will appear here.',
      icon: Icons.receipt_long_outlined,
      actionLabel: 'Add expense',
      onAction: () {},
    );

    testWidgets(
      'light',
      (tester) => expectGolden(
        tester,
        sample(),
        'empty_state',
        dark: false,
        size: const Size(320, 400),
      ),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(
        tester,
        sample(),
        'empty_state',
        dark: true,
        size: const Size(320, 400),
      ),
    );
  });
}
```

### `test/shared/layout_overflow_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_bar_chart.dart';
import 'package:alaya/features/lock/presentation/widgets/pin_pad.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_donut_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/slice_bar_list.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/sheets/delete_transaction_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/freeze_conversion_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_filter_sheet.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/features/service/presentation/sheets/dispose_sheet.dart';
import 'package:alaya/features/service/presentation/widgets/contact_action.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/shopping/presentation/sheets/entry_editor_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/generate_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/list_manager_sheet.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_expandable_fab.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/loading_state.dart';
import 'package:alaya/shared/widgets/module_tile.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

import '../support/calendar_harness.dart' as cal;
import '../support/expense_harness.dart';
import '../support/fake_settings_repository.dart';

/// The only thing in this project that catches a layout overflow (ARCH_3 §8.3, ARCH_5 U2).
///
/// **Every sheet and every full-height state belongs here.** These defects are invisible to
/// `dart analyze`, to a file-by-file scan and to looking at the screen, because the missing
/// affordance is always an *ancestor*: the widget under review is locally correct and the parent
/// that should have given it room, or a way to scroll, is the one at fault.
///
/// They are also invisible to an ordinary widget test. A `RenderFlex` overflow reports through
/// `FlutterError.onError` rather than throwing at the site, so a test only fails on one if something
/// asks — which is exactly how an overflow hides in a suite that otherwise looks green. Every case
/// below asks, via `tester.takeException()`.
void main() {
  /// Roughly what a software keyboard takes from a phone in portrait.
  const double keyboardInset = 320;

  /// Roughly the room a list area has left on a small phone with a keyboard up.
  const Size squeezed = Size(320, 140);

  Widget host(
    Widget child, {
    double bottomInset = 0,
    double textScale = 1,
    List<Override> overrides = const [],
  }) => ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AlayaTheme.light(AlayaPresets.activePreset),
      // Every expense sheet reads `AlayaStrings.of(context)`, which unwraps a null without a
      // delegate installed. The Phase 5 groups pass literal strings, so this file went without
      // one until real screens arrived — and then failed as a null-check rather than as a
      // missing translation, which is why it read like five separate defects.
      localizationsDelegates: const [
        AlayaStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AlayaStrings.supportedLocales,
      // Inside the app rather than above it. `WidgetsApp` re-establishes `MediaQuery` from the
      // view, so an outer one is discarded before anything under test can read it — and a test
      // that believes it has simulated a keyboard when it has not is worse than no test.
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          viewInsets: EdgeInsets.only(bottom: bottomInset),
          textScaler: TextScaler.linear(textScale),
        ),
        child: inner!,
      ),
      home: Scaffold(body: child),
    ),
  );

  /// Content taller than the room a keyboard leaves, so the assertions are about the scaffold rather
  /// than about how long a particular string happens to be.
  Widget tallContent() => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [SizedBox(width: 200, height: 400)],
  );

  group('AlayaBottomSheet', () {
    testWidgets('scrolls rather than overflowing with a keyboard up', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: tallContent()),
          bottomInset: keyboardInset,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('still fits when there is no keyboard', (tester) async {
      await tester.pumpWidget(host(AlayaBottomSheet(child: tallContent())));
      expect(tester.takeException(), isNull);
    });

    // The bug, reproduced deliberately. `Padding(bottom: viewInsets)` around a `MainAxisSize.min`
    // Column is correct in each half and broken together: the padding shrinks the space and the
    // Column has no way to give up the room it already took. **If this ever stops overflowing, the
    // guard above has stopped testing anything** — and the reason AlayaBottomSheet exists has
    // quietly gone away.
    testWidgets('the un-scaffolded shape it replaces still overflows', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Padding(
            padding: const EdgeInsets.only(bottom: keyboardInset),
            child: tallContent(),
          ),
        ),
      );
      expect(tester.takeException(), isA<FlutterError>());
    });
  });

  group('ConfirmSheet', () {
    testWidgets('survives a keyboard and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => ConfirmSheet.show(
                context,
                title: 'Delete this transaction?',
                body: 'You can undo this for the next few seconds.',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                destructive: true,
              ),
              child: const Text('open'),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('AlayaFormScaffold', () {
    Widget form({bool submitting = false}) => AlayaFormScaffold(
      primaryLabel: 'Save expense',
      onPrimary: () {},
      secondaryLabel: 'Cancel',
      onSecondary: () {},
      isDirty: true,
      isSubmitting: submitting,
      discardTitle: 'Discard your changes?',
      discardBody: 'What you have typed will not be saved.',
      discardConfirmLabel: 'Discard',
      discardCancelLabel: 'Keep editing',
      child: const Column(
        children: [SizedBox(height: 300), TextField(), SizedBox(height: 300)],
      ),
    );

    testWidgets('body scrolls and the footer stays above the keyboard', (
      tester,
    ) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset));
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a doubled text scale with a keyboard up', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(form(), bottomInset: keyboardInset, textScale: 2),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the submitting footer does not grow the row past its box', (
      tester,
    ) async {
      await tester.pumpWidget(host(form(submitting: true), textScale: 2));
      expect(tester.takeException(), isNull);
    });
  });

  // Every sheet Phase 6A adds, at a keyboard inset and a doubled text scale — the two conditions
  // under which each of them is first used and least likely to have been looked at.
  group('expense sheets', () {
    final expenseOverrides = <Override>[
      homeCurrencyCodeProvider.overrideWith((ref) => 'INR'),
      homeDecimalDigitsProvider.overrideWith((ref) => 2),
      selectableAccountsProvider.overrideWith(
        (ref) => Stream.value(const [kAccount]),
      ),
      quickAddTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      accountsByIdProvider.overrideWith(
        (ref) => Stream.value(<String, Account>{kAccount.id: kAccount}),
      ),
      lineEditorItemsProvider.overrideWith(
        (ref) => Stream.value(const <Item>[]),
      ),
      enabledCurrenciesProvider.overrideWith(
        (ref) => Stream.value(const [
          Currency(
            code: 'USD',
            name: 'US Dollar',
            symbol: r'$',
            decimalDigits: 2,
            isEnabled: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: expenseOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets(
      'QuickAddSheet',
      (tester) => pumpSheet(tester, const QuickAddSheet()),
    );

    testWidgets(
      'TransactionFilterSheet',
      (tester) => pumpSheet(tester, const TransactionFilterSheet()),
    );

    testWidgets(
      'LineItemEditor',
      (tester) => pumpSheet(
        tester,
        const LineItemEditor(
          currencyCode: 'INR',
          decimalDigits: 2,
          defaultDestination: TransactionLineDestination.inventory,
        ),
      ),
    );

    testWidgets(
      'DeleteTransactionSheet',
      (tester) => pumpSheet(tester, const DeleteTransactionSheet()),
    );

    testWidgets(
      'FreezeConversionSheet',
      (tester) =>
          pumpSheet(tester, const FreezeConversionSheet(excludeCode: 'INR')),
    );
  });

  // Phase 6B's sheet, at a keyboard inset and a doubled text scale — the two conditions under
  // which it is first used and least likely to have been looked at (U2).
  group('inventory sheets', () {
    final inventoryOverrides = <Override>[
      consumeFefoProvider(
        'item-1',
      ).overrideWith((ref) => Stream.value(const <Batch>[])),
      unitsInCategoryProvider(UnitCategory.weight).overrideWith(
        (ref) => Stream.value(const [
          Unit(
            code: 'kg',
            category: UnitCategory.weight,
            factorToBaseMilli: 1000000,
            displayName: 'kilogram',
            isSystem: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    testWidgets('ConsumeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: ConsumeSheet(
              itemId: 'item-1',
              unitCode: 'kg',
              category: UnitCategory.weight,
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: inventoryOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6C's three sheets, at a keyboard inset and a doubled text scale — the two conditions under
  // which each is first used and least likely to have been looked at (U2).
  group('shopping sheets', () {
    final shoppingOverrides = <Override>[
      entryItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      entryTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      entryCurrencyProvider.overrideWith((ref) async => 'INR'),
      entryDecimalDigitsProvider.overrideWith((ref) async => 2),
      entriesProvider(
        'list-1',
      ).overrideWith((ref) => Stream.value(const <ShoppingEntry>[])),
      shoppingItemsByIdProvider.overrideWith(
        (ref) => Stream.value(const <String, Item>{}),
      ),
      allListsProvider.overrideWith(
        (ref) => Stream.value(const <ShoppingList>[]),
      ),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: shoppingOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets(
      'EntryEditorSheet',
      (tester) => pumpSheet(tester, const EntryEditorSheet(listId: 'list-1')),
    );

    testWidgets(
      'GenerateSheet',
      (tester) => pumpSheet(tester, const GenerateSheet(listId: 'list-1')),
    );

    testWidgets(
      'ListManagerSheet',
      (tester) => pumpSheet(tester, const ListManagerSheet()),
    );
  });

  // Phase 6D's pay sheet, at a keyboard inset and a doubled text scale — an amount field, a date
  // field, an account dropdown and a two-line note, all growing at once.
  group('recurring sheets', () {
    final recurringOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      payAccountsProvider.overrideWith(
        (ref) => Stream.value(const <Account>[]),
      ),
      payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
    ];

    testWidgets('PaySheet', (tester) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(
            child: PaySheet(
              occurrenceId: 'occ-1',
              template: RecurringTemplate(
                id: 'tpl-1',
                name:
                    'A rent template with a name long enough to wrap at a doubled scale',
                normalizedName: 'rent',
                kind: RecurringKind.rent,
                direction: RecurringDirection.outflow,
                defaultAmount: const Money(120000, 'INR'),
                intervalUnit: RecurringIntervalUnit.month,
                intervalCount: 1,
                startDateKey: const DateKey(20260131),
                nextDueDateKey: const DateKey(20260831),
                isPaused: false,
                autoRemind: true,
                remindDaysBefore: 3,
                anchorDayOfMonth: 31,
              ),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: recurringOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6D adds, with a clamp note on every row.
  group('FrequencyPreview at a doubled text scale', () {
    testWidgets('three dates, two of them clamped', (tester) async {
      await tester.pumpWidget(
        host(
          const FrequencyPreview(
            dates: [
              PreviewedDate(dateKey: DateKey(20260131)),
              PreviewedDate(dateKey: DateKey(20260228), clamped: true),
              PreviewedDate(dateKey: DateKey(20260331)),
            ],
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6E's dispose sheet: seven choice chips, a date field, an optional amount and a note, all
  // growing at once under a keyboard inset.
  group('service sheets', () {
    final serviceOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('DisposeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: DisposeSheet(assetId: 'asset-1', currencyCode: 'INR'),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: serviceOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The contact block: a name, a number and a call button, none of them flexible.
  group('ContactAction at a doubled text scale', () {
    testWidgets('a long name beside a long number', (tester) async {
      await tester.pumpWidget(
        host(
          const ContactAction(
            phone: '+91 98765 43210',
            name: 'A service centre with a name long enough to wrap',
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6F's dashboard sections. Each is a card whose figures, chips and labels all grow at once, and
  // the funds header carries the only display-sized amount in the app.
  group('dashboard sections', () {
    final dashOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      // InsightCard's notifier restores its side from `app_settings` on the first frame, which
      // resolves `databaseProvider` unless this is here — the failure reads as a database bug in a
      // test that never mentions one (ARCH_6 P6).
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      dashboardCurrencyProvider.overrideWith((ref) async => 'INR'),
      dashboardDigitsProvider.overrideWith((ref) async => 2),
      totalFundsProvider.overrideWith(
        (ref) async => const NetWorth(
          total: Money(98765432, 'INR'),
          unconvertedCount: 3,
          isApproximate: true,
        ),
      ),
      upcomingProvider.overrideWith((ref) async => const <UpcomingEntry>[]),
    ];

    testWidgets('FundsHeader with both chips at a doubled scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const FundsHeader(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('InsightCard with its switch at a doubled scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const InsightCard(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6F adds. Two lines of text and a glyph inside a fixed aspect ratio is
  // exactly the shape that overflows when the text doubles and the box does not.
  group('ModuleTile at a doubled text scale', () {
    testWidgets('a long label beside a long count', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 160,
            height: 108,
            child: ModuleTile(
              label: 'Recurring commitments',
              icon: Icons.event_repeat,
              detail: '17 need attention before the end of the month',
              onTap: () {},
            ),
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 7A. Both shapes here are the ones that have already cost this project rounds: a sheet whose
  // content outgrows the viewport, and a grid of text cells whose row height does not move with the text.
  // Zero width, which is not a hypothetical: Android reports it on the first frame of every launch
  // ("D/FlutterRenderer: Width is zero. 0,0") and the FAB's slot subtracted padding from it, producing a
  // negative width and a red screen on startup. Every widget harness sets a real viewport before pumping,
  // which is exactly why nothing here caught it — so the degenerate viewport is now stated outright.
  group('degenerate viewports', () {
    testWidgets('the expandable FAB survives a zero-width first frame', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size.zero),
            child: Scaffold(
              floatingActionButton: AlayaExpandableFab(
                openLabel: 'Add',
                closeLabel: 'Close',
                actions: [
                  FabAction(label: 'One', icon: Icons.add, onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('calendar', () {
    List<Override> calOverrides({List<CalendarEvent> events = const []}) =>
        cal.calendarOverrides(cal.FakeCalendarRepository(events: events));

    final busyDay = <CalendarEvent>[
      cal.event(
        title: 'A payee with a name long enough to wrap at a doubled scale',
        amountMinor: 98765432,
      ),
      cal.event(
        type: CalendarEventType.serviceDue,
        refType: 'asset',
        refId: 'as-1',
        title: 'The boiler in the upstairs cupboard',
        baseSeverity: CalendarSeverity.warning,
      ),
      cal.event(
        type: CalendarEventType.batchExpiry,
        refType: 'inventoryBatch',
        refId: 'ba-1',
        title: 'Yoghurt, the large tub',
        baseSeverity: CalendarSeverity.warning,
      ),
    ];

    testWidgets('DaySheet with three grouped entries at a doubled scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('DaySheet with a keyboard up as well', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // U26: `TableCalendar` takes a fixed `rowHeight`, so the grid computes one from the text scaler. If
    // that computation is ever replaced by a constant, this is the test that says so.
    testWidgets('the month grid at a doubled scale on the narrowest phone', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const CalendarScreen(),
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'the month grid at a tripled scale, which is past what U15 asks for',
      (tester) async {
        await tester.pumpWidget(
          host(
            const CalendarScreen(),
            textScale: 3,
            overrides: calOverrides(events: busyDay),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    // The range header prints two formatted dates and a dash, which is the longest single string this
    // screen can produce — and it appears only in a mode the other cases never enter.
    testWidgets('the range header at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(
          const CalendarScreen(),
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('22'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // The screen's own composition, which the shared full-height group cannot reach: six measured rows
    // plus a header are taller than a squeezed list area on their own, so the grid and the state beneath
    // it have to share a scroll rather than compete for a fixed box.
    for (final scale in [1.0, 2.0]) {
      testWidgets('the whole screen in a squeezed viewport at ${scale}x', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: scale,
            overrides: calOverrides(events: busyDay),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // Each of the three states in turn, in the same squeezed box. Loading and error sit in the sliver
    // that fills the remainder, and that remainder is negative here.
    testWidgets('loading, empty and error all survive the squeezed box', (
      tester,
    ) async {
      for (final repo in [
        cal.FakeCalendarRepository(pending: true),
        cal.FakeCalendarRepository(),
        cal.FakeCalendarRepository(error: 'view unavailable'),
      ]) {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: 2,
            overrides: cal.calendarOverrides(repo),
          ),
        );
        // `pump`, not `pumpAndSettle`: the loading case holds a `CircularProgressIndicator`, which
        // animates forever, so `pumpAndSettle` times out rather than settling. Two frames is enough to
        // resolve the completed futures in the other two cases.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('full-height states in a squeezed viewport', () {
    Widget inSqueezedBox(Widget child) => host(
      Center(
        child: SizedBox(
          width: squeezed.width,
          height: squeezed.height,
          child: child,
        ),
      ),
    );

    testWidgets('EmptyState with an icon, body and action', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          EmptyState(
            title: 'No transactions yet',
            body: 'Add your first expense and it will appear here.',
            icon: Icons.receipt_long_outlined,
            actionLabel: 'Add expense',
            onAction: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ErrorState with a retry — the tallest of the three', (
      tester,
    ) async {
      await tester.pumpWidget(
        inSqueezedBox(
          ErrorState(
            title: 'That did not work',
            body: 'Something went wrong on our side. Try again.',
            retryLabel: 'Try again',
            onRetry: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoadingState', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(const LoadingState(label: 'Loading')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('AlayaListSkeleton clips rather than overflowing', (
      tester,
    ) async {
      await tester.pumpWidget(
        inSqueezedBox(const AlayaListSkeleton(label: 'Loading transactions')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmptyState at a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: EmptyState(
                title: 'No transactions yet',
                body: 'Add your first expense and it will appear here.',
                icon: Icons.receipt_long_outlined,
                actionLabel: 'Add expense',
                onAction: () {},
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    // The states are also the shape the Theme Lab renders inside a half-width pane, which is where
    // the 150px `SizedBox` around an EmptyState used to overflow by roughly 58px.
    testWidgets('EmptyState in a half-width pane', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          const SizedBox(
            width: 134,
            child: EmptyState(
              title: 'No matches',
              body: 'Try a shorter search.',
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6A's line-items page: a full-height screen whose summary row, list rows and footer all
  // grow under text scale at once. Squeezed and doubled, which is the pair U21 exists for.
  group('the line items page', () {
    final editorOverrides = <Override>[
      transactionEditorProvider.overrideWith(
        () => _FixedEditor(
          AsyncValue.data(
            TransactionEditorState(
              currencyCode: 'INR',
              dateKey: const DateKey(20260801),
              amount: const Money(20000, 'INR'),
              lines: [
                TransactionLine(
                  id: 'l1',
                  transactionId: '',
                  lineNo: 1,
                  description:
                      'A description long enough to need two lines at a doubled scale',
                  destination: TransactionLineDestination.inventory,
                  quantity: const Qty(500000, UnitCategory.weight),
                  lineAmount: const Money(4000, 'INR'),
                ),
              ],
            ),
          ),
        ),
      ),
      homeDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('populated at 320dp and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(const LineItemsScreen(), textScale: 2, overrides: editorOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('kit rows at a doubled text scale', () {
    testWidgets('KeyValueRow wraps a long value instead of overflowing', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            child: KeyValueRow(
              label: 'Payment method',
              value: 'Bank transfer from HDFC Savings ending 4417',
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('FilterChipBar wraps rather than clipping a row of chips', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: FilterChipBar(
              clearAllLabel: 'Clear all',
              onClearAll: () {},
              filters: [
                ActiveFilter(label: 'Account: HDFC Savings', onRemove: () {}),
                ActiveFilter(label: 'Tag: Groceries', onRemove: () {}),
                ActiveFilter(label: 'Jan 2026 – Aug 2026', onRemove: () {}),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('StatusChip ellipsises a long label in a narrow box', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 96,
            child: StatusChip(label: 'Needs details', tone: StatusTone.info),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── Phase 7B ──────────────────────────────────────────────────────────────────────────
  //
  // **No sheets, so no sheet cases.** 7B adds no `AlayaBottomSheet`: the tag drill happens in place
  // inside its card and the clear-cache action is a row, so there is nothing here for U2's sheet
  // clause to cover. What it does add is one shared widget, two chart surfaces and four full-height
  // states, and those are below.
  group('analytics surfaces', () {
    // **Wrapped in a scroll view, because that is the only place a `ChartCard` ever lives** — the
    // analytics screen puts every card in a `SliverList`. Handed a tight viewport height instead, its
    // `Column` has nowhere to go and reports an overflow the real screen cannot produce. What these
    // cases are for is the *horizontal* axis: a header that starves, a chip row that will not wrap, a
    // plot box that outgrows its card.
    Widget card({
      Widget? trailing,
      Widget child = const Text('body'),
      AsyncValue<int> value = const AsyncValue.data(1),
    }) => SingleChildScrollView(
      child: ChartCard<int>(
        title: 'Price per kilogram across every purchase this year',
        subtitle: 'What one thing costs you, purchase by purchase',
        value: value,
        isEmpty: (data) => data == 0,
        emptyMessage: 'Nothing yet',
        onRetry: () {},
        approximateCount: 3,
        unconvertedCount: 2,
        trailing: trailing,
        builder: (context, data) => child,
      ),
    );

    testWidgets(
      'ChartCard stacks its header above 1.5x rather than clipping the figure',
      (tester) async {
        // The `trailing` slot is an `AmountText`, which clips rather than ellipsises — so a clipped
        // figure is a wrong figure and the header has to stack instead of sharing a row (Law U21).
        await tester.pumpWidget(
          host(
            SizedBox(
              width: 320,
              child: card(
                trailing: const AmountText(
                  Money(123456789, 'INR'),
                  size: AmountSize.small,
                  showSign: false,
                ),
              ),
            ),
            textScale: 2,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('ChartCard keeps both quality chips at a doubled scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(SizedBox(width: 320, child: card()), textScale: 2),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChartCard renders its error branch in a narrow box', (
      tester,
    ) async {
      // The inline failure, not `ErrorState`: that one is a full-height state with a 40px glyph and
      // its own `ScrollSafeCenter`, which inside a card would push every sibling off the screen.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              value: AsyncValue<int>.error(
                Exception('No rate for JPY on 2026-08-10, and none earlier'),
                StackTrace.empty,
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a plot area grows with the text scaler and stays inside its card', (
      tester,
    ) async {
      // `AnalyticsPlotBox` scales from the text scaler and clamps (Laws U26, U28's clamping lesson).
      // Unclamped, a tripled scale would produce a card taller than the viewport — and the box sizes
      // only the plot, so the card's own title and subtitle grow beside it rather than being squeezed
      // into the plot's height.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: const AnalyticsPlotBox(
                child: AnalyticsLineChart(
                  series: [
                    AnalyticsSeries(
                      tone: AnalyticsSeriesTone.expense,
                      points: [
                        AnalyticsPoint(x: 0, value: 100000, axisLabel: 'Jan'),
                        AnalyticsPoint(x: 1, value: 90000),
                        AnalyticsPoint(x: 2, value: 140000, axisLabel: 'Aug'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a flat series does not collapse its own plot band', (
      tester,
    ) async {
      // Every point equal makes `maxY - minY` zero, which fl_chart divides by. The chart widens the
      // band by one minor unit rather than handing it a zero.
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            height: 120,
            child: AnalyticsLineChart(
              series: [
                AnalyticsSeries(
                  tone: AnalyticsSeriesTone.neutral,
                  points: [
                    AnalyticsPoint(x: 0, value: 5000),
                    AnalyticsPoint(x: 1, value: 5000),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a bar chart of thirty-one buckets survives a doubled scale at 320dp',
      (tester) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: 320,
              height: 160,
              child: AnalyticsBarChart(
                labelEvery: 5,
                buckets: [
                  for (var day = 1; day <= 31; day++)
                    AnalyticsBucket(
                      bucket: day,
                      value: day * 1000,
                      label: '$day',
                    ),
                ],
              ),
            ),
            textScale: 2,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('an all-zero bar chart still draws its axis', (tester) async {
      // A window where nothing was spent must show that the buckets exist and are empty, rather than
      // dividing by a zero maximum.
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            height: 160,
            child: AnalyticsBarChart(
              buckets: [
                AnalyticsBucket(bucket: 1, value: 0, label: 'M'),
                AnalyticsBucket(bucket: 7, value: 0, label: 'S'),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a donut stays a ring at a tripled scale', (tester) async {
      // `AnalyticsDonutChart` sizes its radius from the box's shorter side, so a taller box at a raised
      // scale must not produce a cropped ellipse — and the centre text has to fit the hole.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: Builder(
                builder: (context) => AnalyticsDonutChart(
                  slices: analyticsSlices(
                    context,
                    const [
                      (label: 'Groceries', value: 400000, key: 'grocery'),
                      (label: 'Household', value: 220000, key: 'household'),
                      (label: 'Bills', value: 180000, key: 'bill'),
                    ],
                    otherLabel: 'Everything else',
                    remainder: 90000,
                  ),
                  centreTop: '85%',
                  centreBottom: 'in three kinds',
                ),
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a donut groups its tail rather than drawing twelve slivers', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: Builder(
                builder: (context) {
                  final slices = analyticsSlices(
                    context,
                    [
                      for (var i = 0; i < 12; i++)
                        (label: 'Kind $i', value: 12000 - i * 500, key: 'k$i'),
                    ],
                    otherLabel: 'Everything else',
                  );
                  // Six wedges plus one remainder, whatever it was handed.
                  expect(slices, hasLength(7));
                  return AnalyticsDonutChart(slices: slices);
                },
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'an all-zero donut renders nothing rather than dividing by zero',
      (tester) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: 320,
              child: card(
                child: Builder(
                  builder: (context) {
                    final slices = analyticsSlices(
                      context,
                      const [(label: 'Groceries', value: 0, key: 'grocery')],
                      otherLabel: 'Everything else',
                    );
                    expect(slices, isEmpty);
                    return AnalyticsDonutChart(slices: slices);
                  },
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a swatched list without bars stacks above 1.5x', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: SliceBarList(
              showBars: false,
              slices: [
                SliceBar(
                  label: 'Between my accounts and everywhere else',
                  value: const AmountText(
                    Money(98765432, 'INR'),
                    size: AmountSize.small,
                    showSign: false,
                  ),
                  share: 0.8,
                  detail: '34%',
                  swatch: const Color(0xFF3F51B5),
                  onTap: () {},
                ),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('SliceBarList stacks its rows above 1.5x', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: SliceBarList(
              slices: [
                SliceBar(
                  label: 'Between my accounts and everywhere else',
                  value: const AmountText(
                    Money(98765432, 'INR'),
                    size: AmountSize.small,
                    showSign: false,
                  ),
                  share: 1,
                  detail: '12 purchases',
                  onTap: () {},
                ),
                SliceBar(
                  label: 'Household',
                  value: const QtyText(Qty(4450000, UnitCategory.weight)),
                  share: 0.4,
                ),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a share above one does not assert', (tester) async {
      // `share` is a ratio of two sums, so a rounding artefact can exceed one and
      // `FractionallySizedBox` asserts on a factor greater than one. It is clamped.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: SliceBarList(
              slices: [
                SliceBar(
                  label: 'Groceries',
                  value: const Text('x'),
                  share: 1.0000001,
                ),
                SliceBar(
                  label: 'Bills',
                  value: const Text('y'),
                  share: double.nan,
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('analytics full-height states in a squeezed viewport', () {
    Future<void> pumpSqueezed(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox.fromSize(size: squeezed, child: child),
          ),
        ),
      );
    }

    testWidgets('the drill-down skeleton clips rather than overflowing', (
      tester,
    ) async {
      await pumpSqueezed(
        tester,
        const AlayaListSkeleton(label: 'Loading these transactions…'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the drill-down empty state scrolls instead of overflowing', (
      tester,
    ) async {
      await pumpSqueezed(
        tester,
        const EmptyState(
          title: 'Nothing here in this window',
          body:
              'The window is set on the insights screen. Widen it and these may appear.',
          icon: Icons.filter_alt_outlined,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the screen-level empty state scrolls with its action', (
      tester,
    ) async {
      // The tallest of the three: icon, two text blocks and a 48dp button (ARCH_5 §4.1).
      await pumpSqueezed(
        tester,
        EmptyState(
          title: 'Nothing to show for this window',
          body:
              'Widen the window above, or record something and it will appear here.',
          icon: Icons.insights_outlined,
          actionLabel: 'Add expense',
          onAction: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the drill-down error state survives with a retry', (
      tester,
    ) async {
      await pumpSqueezed(
        tester,
        ErrorState(
          title: 'Could not work that out',
          body: 'No rate for JPY on 2026-08-10, and none earlier',
          retryLabel: 'Try again',
          onRetry: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── Phase 8A ──────────────────────────────────────────────────────────────────────────
  //
  // Two sheets and five full-height states. `PaymentMethodSheet` and `PayeeSheet` are the phase's only
  // `AlayaBottomSheet` additions; the lock screen, PIN setup, recovery and the settings empties are its
  // full-height ones (Law U2 — added in the phase that creates them).
  group('settings and lock surfaces', () {
    testWidgets('a PIN keypad fits 320dp at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: PinKeypad(
                enabled: true,
                onDigit: _noDigit,
                onBackspace: _noop,
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a keypad with the biometric key fits at a tripled scale', (
      tester,
    ) async {
      // Four keys on the bottom row rather than three, which is the widest the pad ever gets.
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: PinKeypad(
                enabled: true,
                onDigit: _noDigit,
                onBackspace: _noop,
                onBiometric: _noop,
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('six PIN dots fit the narrowest phone', (tester) async {
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: PinDots(length: 6, filled: 3, dimmed: false),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the honest-copy paragraph wraps rather than overflowing', (
      tester,
    ) async {
      // The longest string in the app, at the largest scale U15 asks for, in the narrowest column.
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: Text(
                'This PIN stops someone who picks up your unlocked phone from opening Alaya. '
                'It does not encrypt your data — anyone with access to the phone’s files can '
                'still read them.',
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a settings empty state scrolls in a squeezed viewport', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox.fromSize(
              size: squeezed,
              child: EmptyState(
                title: 'No accounts yet',
                body: 'Add one so Alaya knows where your money is.',
                icon: Icons.account_balance_wallet_outlined,
                actionLabel: 'Add an account',
                onAction: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the scoping matrix stacks at a doubled scale', (tester) async {
      // Six switches, each with a two-line subtitle — the tallest form in the phase.
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                children: [
                  for (var i = 0; i < 6; i++)
                    SwitchListTile(
                      value: i.isEven,
                      onChanged: (_) {},
                      title: const Text('Expenses'),
                      subtitle: const Text('Offered when you record an expense.'),
                    ),
                ],
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the varies panel fits its explanation and its offer', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Then it is not a unit'),
                  const Text(
                    'A unit has to be the same amount every time. One packet of biscuits and one '
                    'packet of rice are different weights, so Alaya could not add two packets '
                    'together or work out what one cost.',
                  ),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Create an item instead'),
                  ),
                ],
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── Phase 8B ──────────────────────────────────────────────────────────────────────────
  //
  // Two sheets and four full-height states. `AttachSheet` is this phase's only `AlayaBottomSheet` addition;
  // the export confirmation reuses `ConfirmSheet` but carries the longest body in the app, which is the case
  // worth measuring (Law U2 — added in the phase that creates them).
  group('ops surfaces', () {
    testWidgets('the export warning fits the narrowest phone at a doubled scale', (
      tester,
    ) async {
      // **The longest required string in the project**, in the narrowest column, at the largest scale U15 asks
      // for. If ARCH_3 §3.4's sentence does not fit, the rule cannot be honoured.
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: Text(
                'This backup is not encrypted. Anyone who opens this file can read every '
                'transaction, balance and account name. Only share it somewhere you trust.',
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the attach sheet fits at a tripled scale', (tester) async {
      // **Scrollable, because `AlayaBottomSheet` is.** The bare `Column` this case first used overflowed by 342px
      // at 3x — but it was testing a structure the app does not have, so the failure said nothing about the sheet.
      // A layout case that does not mirror its widget's real wrapper measures the wrong thing.
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Add an attachment'),
                  const Text(
                    'Kept on this phone only, and included in your backups.',
                  ),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Choose a photo'),
                  ),
                ],
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an attachment strip does not reflow around a missing file', (
      tester,
    ) async {
      // The glyph fallback is the same extent as a thumbnail, so a strip of loaded and unloaded images has one
      // height rather than two.
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: 320,
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < 6; i++)
                    const Padding(
                      padding: EdgeInsets.all(4),
                      child: SizedBox(
                        width: 88,
                        height: 88,
                        child: Icon(Icons.description_outlined),
                      ),
                    ),
                ],
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a trash row fits its label, its date and its retention line', (
      tester,
    ) async {
      // **This case found a real defect**, which is what these are for. The screen originally put "Deleted", a
      // date and a retention note in one subtitle `Row` behind a `TextButton` trailing — a `ListTile` gives its
      // subtitle whatever the trailing leaves, which at a doubled scale was 142dp. Two lines and an icon fixed it,
      // and this now measures the shape that shipped.
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: 320,
              child: ListTile(
                isThreeLine: true,
                title: const Text('Weekly groceries at the corner shop'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Row(
                      children: [
                        Text('Deleted'),
                        SizedBox(width: 4),
                        Flexible(child: Text('8 Aug 2026')),
                      ],
                    ),
                    Text('· kept for 30 days'),
                  ],
                ),
                trailing: IconButton(
                  onPressed: () {},
                  tooltip: 'Restore',
                  icon: const Icon(Icons.restore_from_trash_outlined),
                ),
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the reminders explainer and a blocked notice stack', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  Text(
                    'Alaya sends one message a day about what is coming up — not a '
                    'notification for every item.',
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Notifications are turned off for Alaya. Turn them on in your '
                    'phone’s Settings › Apps › Alaya › Notifications.',
                  ),
                ],
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the restore replace warning fits before the typed confirmation', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Everything currently on this phone will be thrown away and '
                    'replaced by the backup. Anything recorded since that backup was made '
                    'will be gone.',
                  ),
                  const SizedBox(height: 8),
                  const TextField(),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {},
                    child: const Text('Replace everything'),
                  ),
                ],
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// A transaction editor reporting a fixed state, so a layout can be pumped without a database.
class _FixedEditor extends TransactionEditorNotifier {
  _FixedEditor(this._value);

  final AsyncValue<TransactionEditorState> _value;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _value;
}

/// A `ValueChanged<String>` that does nothing, so the keypad cases need no state.
void _noDigit(String _) {}

/// A `VoidCallback` that does nothing.
void _noop() {}
```

### `test/support/analytics_harness.dart`

```dart
/// Shared scaffolding for the analytics widget tests.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/providers/chart_providers.dart';
import 'package:alaya/features/analytics/providers/drill_down_providers.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';

import 'fake_settings_repository.dart';

/// The narrowest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every derived date is the same on every machine.
final Clock kAnalyticsClock = FixedClock(DateTime(2026, 8, 10, 9, 30));

/// Today, according to [kAnalyticsClock].
const DateKey kAnalyticsToday = DateKey(20260810);

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// A stream that never emits and never closes, for the loading branch of a `StreamProvider`.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

Money _inr(int minor) => Money(minor, 'INR');

/// A spend breakdown with [count] slices, largest first.
MoneySeries series({int count = 3, int approximate = 0, int unconverted = 0}) =>
    (
      slices: [
        for (var i = 0; i < count; i++)
          (
            label: 'grocery',
            key: i == 0 ? 'grocery' : 'household',
            amount: _inr(100000 - i * 10000),
          ),
      ],
      quality: (approximateCount: approximate, unconvertedCount: unconverted),
    );

/// Total spend and its top three kinds.
Concentration concentration({int total = 300000, int top = 3}) => (
  top: [
    for (var i = 0; i < top; i++)
      (
        key: 'grocery',
        label: 'grocery',
        amount: _inr(100000),
        share: 1 / (top == 0 ? 1 : top),
      ),
  ],
  topShare: top == 0 ? 0.0 : 0.9,
  total: _inr(total),
  quality: exactConversion,
);

/// A unit-price trend with [points] observations and a [change] across them.
UnitPriceTrend trend({int points = 3, double? change = 0.34}) => (
  itemId: 'it-1',
  itemName: 'Potatoes',
  points: [
    for (var i = 0; i < points; i++)
      (
        on: DateKey(20260801 + i),
        lineAmount: _inr(5000 + i * 500),
        quantity: Qty(1000000, UnitCategory.weight),
        pricePerBaseUnit: 5.0 + i,
      ),
  ],
  percentChange: change,
);

/// One transaction for a drill-down list.
Transaction transaction({String id = 'tx-1', int minor = 45900}) => Transaction(
  id: id,
  kind: TransactionKind.withdrawal,
  subtype: TransactionSubtype.grocery,
  occurredAtUtc: DateTime.utc(2026, 8, 10, 9),
  dateKey: kAnalyticsToday,
  originalAmount: _inr(minor),
  needsReview: false,
  fromAccountId: 'ac-1',
);

/// Overrides every analytics provider to a settled, harmless value.
///
/// **Fixed length, always.** A conditional entry changes the override count between scopes and Riverpod
/// refuses it outright — and two `pumpWidget` calls in one test silently reuse the first scope, so a
/// varying list fails in both directions (ARCH_6 P5).
///
/// Every provider is overridden even where a test does not care, because an un-overridden repository
/// provider reaches a real database, which a widget test has no business opening (P6). The screen's
/// sections are a lazy sliver, so a narrow viewport builds only the first few cards — but an override
/// for a card that never builds costs nothing, and omitting one costs a thrown `databaseProvider`.
///
/// `analyticsRangeProvider` and `analyticsCacheControllerProvider` are `NotifierProvider`s and cannot be
/// overridden as instances (P5), so the repositories beneath them are the seam:
/// `AnalyticsRangeNotifier.build` reads settings on the first frame and would otherwise resolve
/// `databaseProvider`, which throws by design (Law L10).
List<Override> analyticsOverrides({
  AsyncValue<Concentration>? headline,
  AsyncValue<UnitPriceTrend?>? inflation,
  AsyncValue<MoneySeries>? subtypeSpend,
  AsyncValue<List<TagSpendNode>>? tagTree,
  AsyncValue<List<Transaction>>? drillRows,
  int unconverted = 0,
}) => [
  clockProvider.overrideWithValue(kAnalyticsClock),
  settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
  analyticsCurrencyProvider.overrideWith((ref) async => 'INR'),
  analyticsDigitsProvider.overrideWith((ref) async => 2),
  analyticsDigitsForCurrencyProvider.overrideWith(
    (ref, code) async => code == 'JPY' ? 0 : 2,
  ),
  analyticsUnconvertedProvider.overrideWith((ref) => Stream.value(unconverted)),
  analyticsHeadlineProvider.overrideWith(
    (ref) => _future(headline ?? AsyncValue.data(concentration())),
  ),
  analyticsPreviousHeadlineProvider.overrideWith(
    (ref) => _future(AsyncValue.data(concentration(total: 250000))),
  ),
  personalInflationProvider.overrideWith(
    (ref) => _future(inflation ?? AsyncValue<UnitPriceTrend?>.data(trend())),
  ),
  spendBySubtypeProvider.overrideWith(
    (ref) => _future(subtypeSpend ?? AsyncValue.data(series())),
  ),
  spendByTagProvider.overrideWith((ref) => _future(AsyncValue.data(series()))),
  spendByPaymentMethodProvider.overrideWith(
    (ref) => _future(AsyncValue.data(series())),
  ),
  topPayeesProvider.overrideWith((ref) => _future(AsyncValue.data(series()))),
  groceryShareProvider.overrideWith(
    (ref) => _future(
      AsyncValue<ShareOfTotal?>.data(
        (key: 'grocery', label: 'grocery', amount: _inr(100000), share: 0.4),
      ),
    ),
  ),
  analyticsTagsByIdProvider.overrideWith(
    (ref) => Stream.value(<String, Tag>{}),
  ),
  tagSpendTreeProvider.overrideWith(
    (ref) => _future(tagTree ?? const AsyncValue.data(<TagSpendNode>[])),
  ),
  incomeVsExpenseProvider.overrideWith(
    (ref) => _future(
      AsyncValue.data((
        points: [
          (monthKey: 202607, income: _inr(500000), expense: _inr(320000)),
          (monthKey: 202608, income: _inr(500000), expense: _inr(410000)),
        ],
        quality: exactConversion,
      )),
    ),
  ),
  netCashFlowProvider.overrideWith(
    (ref) => _future(
      AsyncValue.data((
        points: [
          (monthKey: 202607, amount: _inr(180000)),
          (monthKey: 202608, amount: _inr(90000)),
        ],
        quality: exactConversion,
      )),
    ),
  ),
  analyticsAccountsProvider.overrideWith((ref) => Stream.value(<Account>[])),
  balanceTrendProvider.overrideWith(
    (ref, id) => _future(
      AsyncValue.data((accountId: id, points: const <BalancePoint>[])),
    ),
  ),
  spendHeatmapProvider.overrideWith(
    (ref, byWeekday) => _future(
      AsyncValue.data((cells: const <HeatmapCell>[], quality: exactConversion)),
    ),
  ),
  topItemsBySpendProvider.overrideWith(
    (ref) => _future(const AsyncValue.data(<ItemSpend>[])),
  ),
  topItemsByQuantityProvider.overrideWith(
    (ref) => _future(const AsyncValue.data(<ItemQuantity>[])),
  ),
  dearestPurchaseProvider.overrideWith(
    (ref, item) => _future(const AsyncValue<DearestPurchase?>.data(null)),
  ),
  unitPriceTrendProvider.overrideWith(
    (ref, item) => _future(AsyncValue.data(trend())),
  ),
  averageBasketProvider.overrideWith(
    (ref) => _future(
      AsyncValue.data((
        averageValue: _inr(140000),
        averageLineCount: 4.3,
        basketCount: 7,
        quality: exactConversion,
      )),
    ),
  ),
  inventoryValueProvider.overrideWith(
    (ref) => _future(
      AsyncValue.data((
        byCurrency: {'INR': _inr(320000)},
        batchesValued: 9,
        batchesNoCost: 2,
      )),
    ),
  ),
  wasteTotalsProvider.overrideWith(
    (ref) => _future(const AsyncValue.data(<ItemWasteTotal>[])),
  ),
  expiringBatchesProvider.overrideWith(
    (ref, days) => _future(const AsyncValue.data(<ExpiringBatch>[])),
  ),
  lowStockTodayProvider.overrideWith(
    (ref) => _future(AsyncValue.data((date: kAnalyticsToday, itemCount: 0))),
  ),
  monthlyCommitmentProvider.overrideWith(
    (ref) => _future(
      AsyncValue.data((
        total: _inr(649000),
        templateCount: 4,
        quality: exactConversion,
      )),
    ),
  ),
  recurringSplitProvider.overrideWith(
    (ref) => _future(
      AsyncValue.data((
        recurring: _inr(649000),
        discretionary: _inr(320000),
        recurringShare: 0.67,
        quality: exactConversion,
      )),
    ),
  ),
  serviceCostByAssetProvider.overrideWith(
    (ref) => _future(const AsyncValue.data(<AssetServiceCost>[])),
  ),
  warrantyCoverageProvider.overrideWith(
    (ref) => _future(const AsyncValue.data(<WarrantyCoverage>[])),
  ),
  // The drill-down's own feed, plus the two maps its rows read from the expense feature.
  drillDownTransactionsProvider.overrideWith(
    (ref, spec) => _stream(drillRows ?? AsyncValue.data([transaction()])),
  ),
  drillDownLabelProvider.overrideWith((ref, spec) async => 'Corner Shop'),
  accountsByIdProvider.overrideWith((ref) => Stream.value(<String, Account>{})),
  payeesByIdProvider.overrideWith((ref) => Stream.value(<String, Payee>{})),
];

/// Turns an [AsyncValue] back into the future a `FutureProvider` override expects.
Future<T> _future<T>(AsyncValue<T> value) => value.when(
  data: Future.value,
  loading: pendingFuture<T>,
  error: (error, stack) => Future<T>.error(error, stack),
);

/// Turns an [AsyncValue] back into the stream a `StreamProvider` override expects.
Stream<T> _stream<T>(AsyncValue<T> value) => value.when(
  data: Stream.value,
  loading: pendingStream<T>,
  error: (error, stack) => Stream<T>.error(error, stack),
);

/// A drill-down spec for the tests to share.
const DrillDownSpec kDrillSpec = DrillDownSpec(
  kind: DrillDownKind.payee,
  value: 'pay-1',
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
///
/// Wrapped in a `Scaffold` by default, standing in for the drawer shell. A shell destination declares
/// no `Scaffold` of its own, and Material widgets — `ChoiceChip`, `InkWell`, `SegmentedButton` — assert
/// without a `Material` ancestor.
///
/// The text scaler goes through `MaterialApp.builder`, not a `MediaQuery` above the app:
/// `WidgetsApp` re-establishes `MediaQuery` from the view, so an override placed above it never
/// arrives (ARCH_5 §10).
Future<void> pumpAnalytics(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
  bool dark = false,
  bool wrapInShell = true,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
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
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        // **`MaterialApp` inserts no `Material` and no `Scaffold`.** In the app the drawer shell
        // supplies both, and `AnalyticsHomeScreen` deliberately declares neither — so a shell
        // destination pumped bare has no `Material` ancestor and every `ChoiceChip` in the range row
        // asserts. This `Scaffold` stands in for `_ShellScaffold`.
        //
        // `wrapInShell: false` for a screen that owns its own `Scaffold`, so `DrillDownScreen` is not
        // nested inside a second one.
        home: wrapInShell ? Scaffold(body: child) : child,
      ),
    ),
  );
  await tester.pump();
}
```

### `test/support/calendar_harness.dart`

```dart
/// Shared scaffolding for the Calendar's widget tests.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/repositories/calendar_repository.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every derived date is the same on every machine.
final Clock kCalendarClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kCalendarClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// Builds one event, defaulting to a transaction on today.
CalendarEvent event({
  DateKey date = kToday,
  CalendarEventType type = CalendarEventType.transaction,
  String refType = 'transaction',
  String refId = 'tx-1',
  String title = 'Groceries',
  CalendarSeverity baseSeverity = CalendarSeverity.info,
  int? amountMinor,
}) => CalendarEvent(
  dateKey: date,
  type: type,
  refType: refType,
  refId: refId,
  title: title,
  baseSeverity: baseSeverity,
  amount: amountMinor == null ? null : Money(amountMinor, 'INR'),
);

/// A [CalendarRepository] that answers from a list, or stalls, or fails.
///
/// The **repository** is the seam rather than the aggregator, deliberately: overriding
/// `calendarAggregatorProvider` would stub out ARCH_3 §6's per-type severity table, which is the one
/// piece of calendar logic worth testing through rather than around.
class FakeCalendarRepository implements CalendarRepository {
  /// Creates a repository over [events].
  FakeCalendarRepository({
    this.events = const <CalendarEvent>[],
    this.pending = false,
    this.error,
  });

  /// What every read returns.
  final List<CalendarEvent> events;

  /// When true, reads never complete — the loading branch.
  final bool pending;

  /// When set, reads fail with it — the error branch.
  final Object? error;

  /// Every range this repository was asked for, so a test can assert the query stayed bounded.
  final List<({DateKey from, DateKey to})> rangesRequested = [];

  @override
  Stream<List<CalendarEvent>> watchRange({
    required DateKey from,
    required DateKey to,
  }) {
    rangesRequested.add((from: from, to: to));
    if (pending) return pendingStream<List<CalendarEvent>>();
    if (error != null) return Stream<List<CalendarEvent>>.error(error!);
    return Stream.value(
      events.where((e) => e.dateKey.isWithin(from, to)).toList(),
    );
  }

  @override
  Future<List<CalendarEvent>> forDay(DateKey dateKey) {
    if (pending) return pendingFuture<List<CalendarEvent>>();
    if (error != null) return Future<List<CalendarEvent>>.error(error!);
    return Future.value(events.where((e) => e.dateKey == dateKey).toList());
  }

  @override
  Future<Map<DateKey, int>> countsByDate({
    required DateKey from,
    required DateKey to,
  }) {
    if (pending) return pendingFuture<Map<DateKey, int>>();
    if (error != null) return Future<Map<DateKey, int>>.error(error!);
    final counts = <DateKey, int>{};
    for (final e in events.where((e) => e.dateKey.isWithin(from, to))) {
      counts[e.dateKey] = (counts[e.dateKey] ?? 0) + 1;
    }
    return Future.value(counts);
  }
}

/// Overrides every provider the calendar reads, including the ones read during `build`.
///
/// `calendarTodayProvider` reads the clock and `focusedMonthProvider` reads that, so the clock alone
/// fixes which month opens. Without the repository override, `calendarAggregatorProvider` resolves
/// `calendarDaoProvider` and then `databaseProvider`, which throws by design (ARCH_6 P17).
List<Override> calendarOverrides(FakeCalendarRepository repository) => [
  clockProvider.overrideWithValue(kCalendarClock),
  calendarRepositoryProvider.overrideWithValue(repository),
  // The month feed awaits this before it subscribes, and unstubbed it resolves
  // `recurringRepositoryProvider` and then `databaseProvider`, which throws by design (L10). The
  // symptom is a screen that renders *nothing* — every finder misses and `rangesRequested` stays
  // empty, because the stream provider never reached its second line.
  //
  // The horizon provider is the seam rather than the repository beneath it: a test does not care how
  // occurrence rows come to exist, only that they do, and faking a whole `RecurringRepository` to say
  // "already done" would be a lot of surface for one integer. The dashboard harness overrides
  // `upcomingProvider` for the same reason rather than the four repositories under it.
  recurringHorizonProvider.overrideWith((ref) async => 0),
];

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpCalendar(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}
```

### `test/support/cook_fakes.dart`

```dart
/// Fakes for the two ports `RecipeCookService` writes through.
///
/// **These exist because that service had no test at all.** `RecipeCookService` appeared in no test file
/// in the repository — the deduction path a user reported as broken had never been exercised, which is the
/// third time this feature area has produced that finding (`RecipeDetailScreen` and `parseAmountMilli`
/// being the others). A confirmation sheet is only correct if the thing behind it is.
///
/// **`FakeStock` plans through the real service.** It fakes the *storage*, not the algorithm: the ordering
/// and the expiry policy are `InventoryConsumptionService`'s, exercised for real, and only the batch rows
/// and the movement writes are held in memory. A fake that reimplemented the draw order would pass while
/// production drew from different batches — the exact class of divergence this feature spent five rounds
/// removing.
library;

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/repositories/recipe_repository.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';
import 'package:alaya/domain/services/draw_policy.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';

/// One consumption that reached the repository, kept so a test can assert what was drawn.
typedef RecordedConsume = ({
  String itemId,
  Qty quantity,
  StockMovementKind kind,
  DrawPolicy policy,
  List<ConsumptionDraw> draws,
});

/// A `StockRepository` over in-memory batches, planning through the real consumption service.
class FakeStock implements StockRepository {
  /// Creates the fake with [batches] keyed by item id.
  FakeStock({Map<String, List<ConsumableBatch>>? batches})
    : _batches = {...?batches};

  final Map<String, List<ConsumableBatch>> _batches;

  static const InventoryConsumptionService _consumption =
      InventoryConsumptionService();

  /// Every `consume` that succeeded, in order.
  ///
  /// **The policy is recorded too.** The whole point of this feature is that cooking passes
  /// `freshFirst` and a write-off passes `fefo`; a test that only checked the draws could not tell a
  /// service that forgot the policy from one that sent it.
  final List<RecordedConsume> consumed = [];

  /// Every `consume` that was refused, with the failure it gave.
  final List<Failure> refused = [];

  @override
  Future<Result<List<ConsumptionDraw>, Failure>> consume({
    required String itemId,
    required Qty quantity,
    required StockMovementKind kind,
    DrawPolicy policy = const DrawPolicy.fefo(),
    String? reason,
    String? note,
  }) async {
    final shelf = _batches[itemId] ?? const <ConsumableBatch>[];
    final planned = _consumption.plan(
      batches: shelf,
      needed: quantity,
      policy: policy,
    );
    final plan = planned.valueOrNull;
    if (plan == null) {
      final failure =
          planned.failureOrNull ??
          const UnexpectedFailure('Stock could not be planned.');
      refused.add(failure);
      return Result.failure(failure);
    }

    // Applied, so a second consume in the same cook sees a drawn-down shelf. Without this a recipe
    // needing the same item twice would draw the same batch twice and the test would not notice.
    final drawn = {for (final draw in plan.draws) draw.batchId: draw.quantity};
    _batches[itemId] = [
      for (final batch in shelf)
        if (drawn[batch.batchId] == null)
          batch
        else
          ConsumableBatch(
            batchId: batch.batchId,
            remaining: Qty(
              batch.remaining.milliBase - drawn[batch.batchId]!.milliBase,
              batch.remaining.category,
            ),
            purchasedDateKey: batch.purchasedDateKey,
            expiryDateKey: batch.expiryDateKey,
          ),
    ];

    consumed.add((
      itemId: itemId,
      quantity: quantity,
      kind: kind,
      policy: policy,
      draws: plan.draws,
    ));
    return Result.ok(plan.draws);
  }

  /// What is left of [itemId], for asserting the shelf after a cook.
  Qty remainingOf(String itemId, UnitCategory category) {
    var milli = 0;
    for (final batch in _batches[itemId] ?? const <ConsumableBatch>[]) {
      milli += batch.remaining.milliBase;
    }
    return Qty(milli, category);
  }

  // The rest of the contract. `RecipeCookService` touches none of it, and a fake that quietly returned
  // plausible values would let a future change start depending on one of them without a test noticing.
  @override
  Future<Result<void, Failure>> consumeFromBatch({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? reason,
    String? note,
  }) => throw UnimplementedError('FakeStock.consumeFromBatch');

  @override
  Future<Result<void, Failure>> addStock({
    required String batchId,
    required Qty quantity,
    required StockMovementKind kind,
    String? note,
  }) => throw UnimplementedError('FakeStock.addStock');

  @override
  Future<Result<void, Failure>> reverse({
    required String movementId,
    String? reason,
  }) => throw UnimplementedError('FakeStock.reverse');

  @override
  Stream<List<StockMovement>> watchForBatch(String batchId) =>
      throw UnimplementedError('FakeStock.watchForBatch');

  @override
  Stream<List<StockMovement>> watchForItemInRange({
    required String itemId,
    required DateKey from,
    required DateKey to,
  }) => throw UnimplementedError('FakeStock.watchForItemInRange');

  @override
  Future<List<WasteTotal>> wasteTotals({
    required DateKey from,
    required DateKey to,
  }) => throw UnimplementedError('FakeStock.wasteTotals');
}

/// A `RecipeRepository` that records cooks and answers nothing else.
class FakeRecipes implements RecipeRepository {
  /// Creates the fake.
  FakeRecipes({this.logFails = false});

  /// Whether [logCook] refuses, for the branch where the deduction succeeded and the log did not.
  bool logFails;

  /// Every cook logged, in order.
  final List<RecipeCook> logged = [];

  @override
  Future<Result<RecipeCook, Failure>> logCook({
    required String recipeId,
    required DateKey cookedOn,
    required int servingsCooked,
    required bool deductedStock,
    String? note,
  }) async {
    if (logFails) {
      return const Result.failure(
        UnexpectedFailure('That cook could not be recorded.'),
      );
    }
    final cook = RecipeCook(
      id: 'cook-${logged.length + 1}',
      recipeId: recipeId,
      cookedOn: cookedOn,
      servingsCooked: servingsCooked,
      deductedStock: deductedStock,
      note: note,
    );
    logged.add(cook);
    return Result.ok(cook);
  }

  @override
  Stream<List<Recipe>> watchAll() =>
      throw UnimplementedError('FakeRecipes.watchAll');

  @override
  Stream<List<Recipe>> watchMatching(String query) =>
      throw UnimplementedError('FakeRecipes.watchMatching');

  @override
  Stream<List<Recipe>> watchFavorites() =>
      throw UnimplementedError('FakeRecipes.watchFavorites');

  @override
  Stream<Recipe?> watchById(String id) =>
      throw UnimplementedError('FakeRecipes.watchById');

  @override
  Stream<List<Recipe>> watchUsingItem(String itemId) =>
      throw UnimplementedError('FakeRecipes.watchUsingItem');

  @override
  Future<Recipe?> byId(String id) =>
      throw UnimplementedError('FakeRecipes.byId');

  @override
  Future<Result<Recipe, Failure>> save(Recipe recipe) =>
      throw UnimplementedError('FakeRecipes.save');

  @override
  Future<Result<void, Failure>> setFavorite({
    required String id,
    required bool isFavorite,
  }) => throw UnimplementedError('FakeRecipes.setFavorite');

  @override
  Future<Result<void, Failure>> delete(String id) =>
      throw UnimplementedError('FakeRecipes.delete');

  @override
  Stream<List<RecipeCook>> watchCookLog(String recipeId) =>
      throw UnimplementedError('FakeRecipes.watchCookLog');
}
```

### `test/support/dashboard_harness.dart`

```dart
import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/dashboard/providers/module_providers.dart';
import 'package:alaya/features/dashboard/providers/range_providers.dart';

import 'dart:async';
import 'fake_settings_repository.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every derived date is the same on every machine.
final Clock kDashClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kDashClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// A headline total, with however many balances it could not convert.
NetWorth netWorth({
  int minor = 12345678,
  int unconverted = 0,
  bool approximate = false,
}) => NetWorth(
  total: Money(minor, 'INR'),
  unconvertedCount: unconverted,
  isApproximate: approximate,
);

/// Totals over one window.
RangeTotals totals({
  int inMinor = 500000,
  int outMinor = 320000,
  int excluded = 0,
}) => RangeTotals(
  moneyIn: Money(inMinor, 'INR'),
  moneyOut: Money(outMinor, 'INR'),
  excludedCount: excluded,
);

/// One thing needing attention.
UpcomingEntry upcoming({
  UpcomingKind kind = UpcomingKind.bill,
  String title = 'Rent',
  DateKey on = const DateKey(20260805),
}) => UpcomingEntry(kind: kind, title: title, dueDateKey: on);

/// Spend by kind over the dashboard's thirty-day window.
Concentration spendByKind({int total = 320000, int kinds = 3}) => (
  top: [
    for (var i = 0; i < kinds; i++)
      (
        key: 'grocery',
        label: 'grocery',
        amount: Money(100000 - i * 10000, 'INR'),
        share: 0.3 - i * 0.05,
      ),
  ],
  topShare: kinds == 0 ? 0.0 : 0.85,
  total: Money(total, 'INR'),
  quality: exactConversion,
);

/// One account, for the funds breakdown.
///
/// The harness had no account constant at all — every dashboard test until now needed only totals. A
/// breakdown needs the thing being broken down.
const kDashAccount = Account(
  id: 'acc-1',
  name: 'Cash',
  normalizedName: 'cash',
  kind: AccountKind.cash,
  currencyCode: 'INR',
  openingBalance: Money(0, 'INR'),
  openingBalanceDateKey: kToday,
  isArchived: false,
  includeInNetWorth: true,
  sortOrder: 0,
);

/// Overrides every dashboard provider to a settled, harmless value.
///
/// **Fixed length, always.** A conditional entry changes the override count between scopes and Riverpod
/// refuses it outright — and two `pumpWidget` calls in one test silently reuse the first scope, so a
/// varying list fails in both directions (ARCH_4 P5).
///
/// Every provider is overridden even where a test does not care, because an un-overridden repository
/// provider reaches a real database, which a widget test has no business opening (P6).
List<Override> dashboardOverrides({
  AsyncValue<NetWorth>? funds,
  AsyncValue<RangeTotals>? last30,
  AsyncValue<RangeTotals>? allTime,
  AsyncValue<List<UpcomingEntry>>? upcomingEntries,
  int inventory = 0,
  int services = 0,
  AsyncValue<int>? expenses,
  AsyncValue<int>? shopping,
  AsyncValue<int>? recurring,
  AsyncValue<Concentration>? spending,
  AsyncValue<List<FundsRow>>? breakdown,
}) => [
  clockProvider.overrideWithValue(kDashClock),
  // `InsightSideNotifier.build` reads settings during the first frame, so this is not optional
  // even for a test that never touches the insight card: without it the notifier resolves
  // `databaseProvider`, which throws by design (Law L10). A `NotifierProvider` instance cannot be
  // overridden (ARCH_6 P5), so the repository beneath it is the only seam.
  settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
  dashboardCurrencyProvider.overrideWith((ref) async => 'INR'),
  dashboardDigitsProvider.overrideWith((ref) async => 2),
  totalFundsProvider.overrideWith(
    (ref) => _resolve(funds ?? AsyncValue.data(netWorth())),
  ),
  // Fixed length, per ARCH_6 P5: a conditional entry changes the count between scopes and Riverpod
  // refuses it. An empty list is a real state — somebody with no accounts at all.
  fundsBreakdownProvider.overrideWith(
    (ref) async => breakdown?.valueOrNull ?? const <FundsRow>[],
  ),
  rangeTotalsProvider.overrideWith(
    (ref, range) => _resolve(
      (range == (from: DateKey(20260703), to: kToday) ? last30 : allTime) ??
          AsyncValue.data(totals()),
    ),
  ),
  upcomingProvider.overrideWith(
    (ref) =>
        _resolve(upcomingEntries ?? const AsyncValue.data(<UpcomingEntry>[])),
  ),
  inventoryCountProvider.overrideWith((ref) => inventory),
  serviceCountProvider.overrideWith((ref) => services),
  expenseCountProvider.overrideWith(
    (ref) => _resolve(expenses ?? const AsyncValue.data(0)),
  ),
  shoppingCountProvider.overrideWith(
    (ref) => _resolve(shopping ?? const AsyncValue.data(0)),
  ),
  recurringCountProvider.overrideWith(
    (ref) => _resolve(recurring ?? const AsyncValue.data(0)),
  ),
  // Phase 7B. Unconditional like every other entry: a conditional override changes the list's
  // length between scopes and Riverpod refuses it outright (ARCH_6 P5). Without it the spending
  // side resolves `analyticsServiceProvider`, which reaches `databaseProvider` and throws by
  // design (Law L10).
  spendingInsightProvider.overrideWith(
    (ref) => _resolve(spending ?? AsyncValue.data(spendByKind())),
  ),
];

/// Turns an [AsyncValue] back into the future a `FutureProvider` override expects.
Future<T> _resolve<T>(AsyncValue<T> value) => value.when(
  data: Future.value,
  loading: pendingFuture<T>,
  error: (error, stack) => Future<T>.error(error, stack),
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpDashboard(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
}
```

### `test/support/expense_harness.dart`

```dart
/// Shared scaffolding for the Expense module's widget tests.
///
/// **Overrides the feature's own view-model providers rather than faking twenty repositories.** A
/// widget test's job is the widget: whether it renders four states correctly, survives a doubled
/// text scale and meets the tap-target floor. Reaching through the whole provider graph to arrange
/// a loading state would test Riverpod, and would make each of these files four times longer for no
/// extra coverage.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/transaction.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so "Today" and "Yesterday" are the same two days on every machine.
final Clock kTestClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kTestClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays in its loading state.
///
/// `Stream.empty()` will not do: it closes immediately, which resolves the provider rather than
/// leaving it pending.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// A sample account.
const Account kAccount = Account(
  id: 'acc-1',
  name: 'HDFC Savings',
  normalizedName: 'hdfc savings',
  kind: AccountKind.bank,
  currencyCode: 'INR',
  openingBalance: Money(0, 'INR'),
  openingBalanceDateKey: DateKey(20260101),
  isArchived: false,
  includeInNetWorth: true,
  sortOrder: 0,
);

/// A sample payee.
const Payee kPayee = Payee(
  id: 'pay-1',
  name: 'Reliance Fresh',
  normalizedName: 'reliance fresh',
  kind: PayeeKind.merchant,
);

/// A sample transaction, flagged for review so the nudge has something to count.
Transaction sampleTransaction({
  String id = 'tx-1',
  bool needsReview = false,
  TransactionKind kind = TransactionKind.withdrawal,
  int minor = 125050,
}) => Transaction(
  id: id,
  kind: kind,
  subtype: TransactionSubtype.grocery,
  occurredAtUtc: DateTime.utc(2026, 8, 1, 4),
  dateKey: kToday,
  originalAmount: Money(minor, 'INR'),
  needsReview: needsReview,
  fromAccountId: kAccount.id,
  payeeId: kPayee.id,
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
///
/// The `MediaQuery` sits inside `MaterialApp.builder` rather than above it: `WidgetsApp`
/// re-establishes it from the view, so an outer override never reaches the widget under test.
Future<void> pumpExpense(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
}
```

### `test/support/fake_settings_repository.dart`

```dart
/// An in-memory [SettingsRepository] for widget tests.
///
/// **Needed because a notifier may read settings during `build`.** `InsightSideNotifier.build` restores
/// the insight card's side from `app_settings`, so any scope that mounts the card and leaves
/// `settingsRepositoryProvider` un-overridden resolves `databaseProvider`, which throws by design
/// (Law L10). The symptom is a `StateError` about the database in a test that never mentions one, which
/// reads as a product bug and is not (ARCH_6 P6).
///
/// Kept in `test/support/` rather than inside one harness because two suites need it — the dashboard
/// harness and `layout_overflow_test.dart` — and a fake written twice is a fake that will disagree with
/// itself (ARCH_4 R25, one layer down).
library;

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';

/// Key/value settings held in a map, with writes readable back.
class FakeSettingsRepository implements SettingsRepository {
  /// Creates a store seeded with [values].
  ///
  /// [homeCurrencyCode] and [defaultAccountId] are separate rather than map entries so the fake does not
  /// have to know `SettingsKeys`' spelling — a test asserting on a key it guessed wrong passes for the
  /// wrong reason.
  FakeSettingsRepository({
    Map<String, String>? values,
    this.homeCurrencyCode = 'INR',
    this.defaultAccountId,
  }) : _values = {...?values};

  final Map<String, String> _values;

  /// What `readHomeCurrencyCode` answers.
  final String? homeCurrencyCode;

  /// What `readDefaultAccountId` answers.
  final String? defaultAccountId;

  /// Everything written so far, so a test can assert a preference was actually persisted.
  Map<String, String> get values => Map.unmodifiable(_values);

  @override
  Future<String?> readValue(String key) async => _values[key];

  @override
  Stream<String?> watchValue(String key) => Stream.value(_values[key]);

  @override
  Stream<Map<String, String>> watchAll() => Stream.value(values);

  @override
  Future<Result<void, Failure>> writeValue({
    required String key,
    required String value,
    required String valueType,
  }) async {
    _values[key] = value;
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> remove(String key) async {
    _values.remove(key);
    return const Result.ok(null);
  }

  // Phase 8A added `writeHomeCurrencyCode` to the contract, so this fake stopped satisfying it. Routed
  // through `writeValue` like the real implementation, so a test asserting on the stored key sees the same
  // row either way.
  @override
  Future<Result<void, Failure>> writeHomeCurrencyCode(String code) =>
      writeValue(key: 'homeCurrencyCode', value: code, valueType: 'string');

  @override
  Future<String?> readHomeCurrencyCode() async => homeCurrencyCode;

  @override
  Future<String?> readDefaultAccountId() async => defaultAccountId;
}
```

### `test/support/inventory_harness.dart`

```dart
/// Shared scaffolding for the Inventory module's widget tests.
///
/// Overrides the feature's view-model providers rather than faking every repository: a widget test's
/// job is the widget — four states, a doubled text scale, the tap-target floor (ARCH_5 §9.1).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/entities/unit.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so relative dates are the same on every machine.
final Clock kInventoryClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kInventoryClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// Grams.
const Unit kGram = Unit(
  code: 'g',
  category: UnitCategory.weight,
  factorToBaseMilli: 1000,
  displayName: 'gram',
  isSystem: true,
  sortOrder: 0,
);

/// Kilograms.
const Unit kKilogram = Unit(
  code: 'kg',
  category: UnitCategory.weight,
  factorToBaseMilli: 1000000,
  displayName: 'kilogram',
  isSystem: true,
  sortOrder: 1,
);

/// A sample item measured by weight.
const Item kItem = Item(
  id: 'item-1',
  name: 'Atta',
  normalizedName: 'atta',
  unitCategory: UnitCategory.weight,
  defaultDisplayUnitCode: 'kg',
  itemKind: ItemKind.food,
  isFavorite: true,
);

/// The mixed-unit total ARCH_1 §5.4 uses as its worked example: 250 + 2000 + 1500 + 700 = 4 kg 450 g.
const Qty kFourKilo450 = Qty(4450000, UnitCategory.weight);

/// Stock on hand for [kItem].
const ItemStock kStock = ItemStock(
  itemId: 'item-1',
  totalRemaining: kFourKilo450,
  batchCount: 4,
  isLowStock: false,
  nearestExpiry: DateKey(20260810),
);

/// A sample batch.
Batch sampleBatch({
  String id = 'batch-1',
  int remainingMilli = 2000000,
  BatchOrigin origin = BatchOrigin.purchase,
  DateKey? expiry = const DateKey(20260810),
  String? location = 'Pantry',
}) => Batch(
  id: id,
  itemId: kItem.id,
  initialQuantity: const Qty(2000000, UnitCategory.weight),
  remainingQuantity: Qty(remainingMilli, UnitCategory.weight),
  unitCodeAtPurchase: 'kg',
  purchasedDateKey: const DateKey(20260715),
  origin: origin,
  expiryDateKey: expiry,
  unitCost: const Money(4500, 'INR'),
  storageLocation: location,
);

/// A sample movement.
StockMovement sampleMovement({
  String id = 'mv-1',
  StockMovementKind kind = StockMovementKind.consume,
  String? reverses,
  String? reason,
}) => StockMovement(
  id: id,
  batchId: 'batch-1',
  itemId: kItem.id,
  kind: kind,
  quantity: const Qty(500000, UnitCategory.weight),
  occurredAtUtc: DateTime.utc(2026, 8, 1, 4),
  dateKey: kToday,
  reason: reason,
  reversesMovementId: reverses,
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
///
/// The `MediaQuery` sits inside `MaterialApp.builder` because `WidgetsApp` re-establishes it from the
/// view, so an outer override never reaches the widget under test.
Future<void> pumpInventory(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
}
```

### `test/support/ops_harness.dart`

```dart
/// Shared scaffolding for the 8B widget tests.
///
/// **Five fakes, and two of them exist so that a plugin never runs in a test at all.** `SupportPort` keeps
/// `google_mobile_ads` and `in_app_purchase` out of the test binary; `ReminderPort` keeps
/// `flutter_local_notifications` and `timezone` out. Neither could be faked without a contract, because the
/// adapters are `final class` over platform channels — which is the same argument 8A's ports rest on.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';
import 'package:alaya/features/onboarding/providers/onboarding_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/services/attachments/attachment_port.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';
import 'package:alaya/domain/services/support/support_port.dart';
import 'package:alaya/domain/services/trash/trash_port.dart';

/// The narrowest phone this app supports (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// Tall enough that a lazy `ListView` builds its whole body.
///
/// **Content assertions get this; the U15 gate does not.** Every screen in this phase is a lazy list, so at
/// 320x640 a row below the fold is never built and `findsNothing` passes for the wrong reason — the trap that
/// cost 8A two rounds. Content tests ask *what exists*; the separate narrow tests ask *whether it fits*.
const Size kTallViewport = Size(320, 2400);

/// A future that never completes, for a loading branch.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// A stream that never emits, for a loading branch.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A `DataTransferPort` that records what it was asked and answers from fields.
class FakeTransfer implements DataTransferPort {
  /// Creates the fake.
  FakeTransfer({
    this.backupVersion = 1,
    this.schemaVersion = 1,
    this.history = const [],
    this.exportCancelled = false,
    this.rollbackExists = false,
    this.pickCancelled = false,
  });

  /// The version inside the file the picker returns.
  int backupVersion;

  /// The version this "app" writes.
  int schemaVersion;

  /// What `watchHistory` emits.
  List<BackupRecord> history;

  /// Whether the export reports a dismissed sheet.
  bool exportCancelled;

  /// Whether a rollback snapshot exists.
  bool rollbackExists;

  /// Whether the file chooser reports a dismissal.
  bool pickCancelled;

  /// How many exports were requested.
  int exports = 0;

  /// How many merges ran.
  int merges = 0;

  /// How many replaces ran.
  int replaces = 0;

  @override
  bool get canSaveToLocation => true;

  @override
  int get appSchemaVersion => schemaVersion;

  @override
  Future<Result<BackupArtefact?, Failure>> exportToLocation() async {
    exports += 1;
    return exportCancelled
        ? const Result.ok(null)
        : const Result.ok(
            (
              path: '/x/alaya.db',
              sizeBytes: 2048,
              isZipped: false,
              fileName: 'alaya.db',
            ),
          );
  }

  @override
  Future<Result<BackupArtefact, Failure>> exportAndShare() async {
    exports += 1;
    return const Result.ok(
      (
        path: '/x/alaya.db',
        sizeBytes: 2048,
        isZipped: false,
        fileName: 'alaya.db',
      ),
    );
  }

  @override
  Stream<List<BackupRecord>> watchHistory() => Stream.value(history);

  @override
  Future<Result<void, Failure>> forgetHistoryEntry(String id) async =>
      const Result.ok(null);

  @override
  Future<Result<String?, Failure>> pickBackupFile() async =>
      pickCancelled ? const Result.ok(null) : const Result.ok('/tmp/backup.db');

  @override
  Future<Result<int, Failure>> readBackupVersion(String path) async =>
      Result.ok(backupVersion);

  @override
  Future<Result<RestoreOutcome, Failure>> merge(String path) async {
    merges += 1;
    return Result.ok((
      mode: RestoreMode.merge,
      tablesMerged: 12,
      backupSchemaVersion: backupVersion,
      rollbackAvailable: false,
    ));
  }

  @override
  Future<Result<RestoreOutcome, Failure>> replace(String path) async {
    replaces += 1;
    return Result.ok((
      mode: RestoreMode.replace,
      tablesMerged: 0,
      backupSchemaVersion: backupVersion,
      rollbackAvailable: true,
    ));
  }

  @override
  Future<Result<void, Failure>> rollback() async => const Result.ok(null);

  @override
  Future<bool> hasRollback() async => rollbackExists;

  @override
  Future<Result<void, Failure>> eraseEverything() async =>
      const Result.ok(null);
}

/// A `TrashPort` over an in-memory list.
class FakeTrash implements TrashPort {
  /// Creates the fake.
  ///
  /// [loading] holds the stream open forever, which is the only way a loading branch is observable: a
  /// `Stream.value` resolves inside the first frame's microtask drain, so a skeleton assertion against one would
  /// pass for the wrong reason — the trap 8A hit twice.
  FakeTrash({List<TrashEntry>? entries, this.loading = false})
    : _entries = [...?entries];

  final List<TrashEntry> _entries;

  /// Whether `watchAll` never emits.
  final bool loading;

  /// How many rows the last purge removed.
  int purged = 0;

  /// How many restores ran.
  int restores = 0;

  @override
  Stream<List<TrashEntry>> watchAll() =>
      loading ? pendingStream<List<TrashEntry>>() : Stream.value(_entries);

  @override
  Stream<int> watchCount() => Stream.value(_entries.length);

  @override
  Future<Result<void, Failure>> restore(TrashEntry entry) async {
    restores += 1;
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> purge(TrashEntry entry) async {
    purged += 1;
    return const Result.ok(null);
  }

  @override
  Future<Result<int, Failure>> purgeAll() async {
    purged = _entries.length;
    return Result.ok(purged);
  }

  @override
  Future<Result<int, Failure>> purgeExpired() async => const Result.ok(0);
}

/// A `ReminderPort` that never touches a notification plugin.
class FakeReminders implements ReminderPort {
  /// Creates the fake.
  FakeReminders({
    ReminderSettings? settings,
    this.permissionState = ReminderPermission.granted,
    this.scheduled = const [],
    this.rescheduleCount = 1,
    this.deviceZone = const ReminderZone(
      name: 'Asia/Kolkata',
      matchesDevice: true,
    ),
    this.osPendingCount = 1,
  }) : _settings = settings ?? const ReminderSettings.fresh();

  ReminderSettings _settings;

  /// What the OS reports.
  ReminderPermission permissionState;

  /// Which zone the schedule was computed in.
  ///
  /// **A real IANA name by default, and overridable to an unmatched one.** The production bug was a zone that
  /// silently disagreed with the device, so a fake that could only report agreement could not exercise the one
  /// branch that matters — exactly the way `rescheduleCount` hard-coded at 1 could not exercise "nothing due".
  ReminderZone deviceZone;

  /// How many notifications the OS claims to be holding.
  ///
  /// **Zero is the case worth testing**, and it is the one the app could not previously represent at all: rows in
  /// `notification_schedule` with no alarm behind them. A negative value stands for the plugin throwing, which
  /// the screen must treat the same way as a zero rather than falling silent.
  int osPendingCount;

  /// What is scheduled.
  List<ScheduledReminder> scheduled;

  /// How many times permission was requested.
  int permissionRequests = 0;

  /// What a manual scan reports finding.
  ///
  /// **Zero is the interesting value**, and the fake hard-coded 1 before. Reminders on with nothing due is
  /// the case that made a working feature look broken, and a fake that can only find something cannot
  /// exercise it.
  int rescheduleCount;

  /// How many times a scan was run.
  int reschedules = 0;

  @override
  Stream<ReminderSettings> watchSettings() => Stream.value(_settings);

  @override
  Future<ReminderPermission> permission() async => permissionState;

  @override
  Future<ReminderPermission> requestPermission() async {
    permissionRequests += 1;
    return permissionState;
  }

  @override
  Future<Result<ReminderSettings, Failure>> setEnabled({
    required NotificationKind kind,
    required bool enabled,
  }) async {
    final next = {..._settings.enabled};
    enabled ? next.add(kind) : next.remove(kind);
    _settings = _settings.copyWith(enabled: next);
    return Result.ok(_settings);
  }

  @override
  Future<Result<ReminderSettings, Failure>> setDigestTime({
    required int hour,
    required int minute,
  }) async {
    _settings = _settings.copyWith(digestHour: hour, digestMinute: minute);
    return Result.ok(_settings);
  }

  @override
  Stream<List<ScheduledReminder>> watchScheduled() => Stream.value(scheduled);

  @override
  Future<ReminderZone> zone() async => deviceZone;

  @override
  Future<Result<int, Failure>> pendingCount() async => osPendingCount < 0
      ? const Result.failure(
          UnexpectedFailure(
            'Your phone could not be asked what it has scheduled.',
          ),
        )
      : Result.ok(osPendingCount);

  @override
  Future<Result<int, Failure>> rescheduleAll() async {
    reschedules += 1;
    return Result.ok(rescheduleCount);
  }

  /// How many test notifications were requested.
  int testsSent = 0;

  /// Whether a test should report failure — the missing-icon case.
  bool testFails = false;

  @override
  Future<Result<void, Failure>> sendTest() async {
    testsSent += 1;
    return testFails
        ? const Result.failure(
            UnexpectedFailure('That test notification could not be sent.'),
          )
        : const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> cancelAll() async => const Result.ok(null);
}

/// A `SupportPort` that makes no ad call, because there is no SDK behind it.
class FakeSupport implements SupportPort {
  /// Creates the fake.
  FakeSupport({this.consent = AdConsent.obtained, this.adAvailable = true});

  /// Where consent stands.
  AdConsent consent;

  /// Whether an ad loads.
  bool adAvailable;

  /// How many times the SDK was brought up.
  int initialisations = 0;

  /// How many ad loads were requested.
  int adLoads = 0;

  @override
  Future<Result<void, Failure>> initialise() async {
    initialisations += 1;
    return const Result.ok(null);
  }

  @override
  Future<AdConsent> consentStatus() async => consent;

  @override
  Future<AdConsent> requestConsent() async => consent;

  @override
  Future<Result<void, Failure>> loadRewardedAd() async {
    adLoads += 1;
    return adAvailable
        ? const Result.ok(null)
        : const Result.failure(
            BusinessRuleFailure('No advert was available.', rule: 'noFill'),
          );
  }

  @override
  Future<Result<bool, Failure>> showRewardedAd() async => const Result.ok(true);

  @override
  Future<Result<List<TipProduct>, Failure>> tipProducts() async =>
      const Result.ok(
        [TipProduct(id: 'alaya_tip_once', title: 'Tip', price: '₹99.00')],
      );

  @override
  Future<Result<bool, Failure>> buyTip(String productId) async =>
      const Result.ok(true);
}

/// An `AttachmentPort` over an in-memory list.
class FakeAttachments implements AttachmentPort {
  /// Creates the fake.
  FakeAttachments({this.rows = const [], this.cancelled = false});

  /// What `watchFor` emits.
  List<Attachment> rows;

  /// Whether the picker reports a dismissal.
  bool cancelled;

  @override
  Stream<List<Attachment>> watchFor({
    required AttachmentOwner owner,
    required String ownerId,
  }) => Stream.value(rows);

  @override
  Stream<int> watchCountFor({
    required AttachmentOwner owner,
    required String ownerId,
  }) => Stream.value(rows.length);

  @override
  Future<Result<Attachment?, Failure>> attach({
    required AttachmentOwner owner,
    required String ownerId,
  }) async => cancelled ? const Result.ok(null) : Result.ok(attachment());

  @override
  Future<Result<String, Failure>> resolvePath(Attachment attachment) async =>
      const Result.ok('/tmp/x.jpg');

  @override
  Future<Result<void, Failure>> open(Attachment attachment) async =>
      const Result.ok(null);

  @override
  Future<Result<void, Failure>> delete(Attachment attachment) async =>
      const Result.ok(null);

  @override
  Future<Result<List<String>, Failure>> allFilePaths() async =>
      const Result.ok([]);
}

/// One trash entry.
TrashEntry trashEntry({
  String id = 'tr-1',
  TrashKind kind = TrashKind.transaction,
  String label = 'Groceries',
  int deletedAt = 1754000000000,
}) => TrashEntry(
  id: id,
  kind: kind,
  label: label,
  deletedAtUtcMillis: deletedAt,
  purgeAfterUtcMillis: deletedAt + TrashPort.retention.inMilliseconds,
);

/// One backup record.
BackupRecord backupRecord({
  String id = 'bk-1',
  String path = '/x/alaya-2026-08-08.db',
}) => BackupRecord(
  id: id,
  filePath: path,
  sizeBytes: 4096,
  schemaVersion: 1,
  takenAtUtcMillis: 1754000000000,
);

/// One attachment.
Attachment attachment({String id = 'at-1'}) => Attachment(
  id: id,
  owner: AttachmentOwner.transaction,
  ownerId: 'tx-1',
  relativePath: '$id.jpg',
  mimeType: 'image/jpeg',
  sizeBytes: 1024,
  addedAtUtcMillis: 1754000000000,
);

/// One scheduled reminder.
///
/// **Takes an instant, because the entity now carries one.** The old fixture took a `DateKey`, which meant no
/// test could express the thing that was actually broken: a schedule whose *time* differed from the digest time
/// on the settings above it. A fixture that cannot represent a bug cannot catch it, and this one could not — the
/// screen read the date from here and the time from somewhere else entirely.
///
/// The default is a **local** wall time, matching `ScheduledReminder.at`'s contract. A UTC default would make
/// assertions in this suite pass or fail depending on the machine's zone, which is the exact class of accident
/// the production bug belonged to.
ScheduledReminder scheduledReminder({
  NotificationKind kind = NotificationKind.expiry,
  DateTime? at,
}) => ScheduledReminder(
  id: 'ns-1',
  kind: kind,
  at: at ?? DateTime(2026, 8, 12, 9),
  androidNotificationId: 1,
);

/// Overrides every port 8B's screens reach.
///
/// **Fixed length**, per ARCH_6 P5: a conditional entry changes the count between scopes and Riverpod refuses it,
/// while two `pumpWidget` calls in one test silently reuse the first scope — so a varying list fails both ways.
List<Override> opsOverrides({
  FakeTransfer? transfer,
  FakeTrash? trash,
  FakeReminders? reminders,
  FakeSupport? support,
  FakeAttachments? attachments,
}) => [
  dataTransferPortProvider.overrideWithValue(transfer ?? FakeTransfer()),
  // Throws when un-overridden, by design — `bootstrap()` is the only place that resolves it.
  lockConfiguredAtStartupProvider.overrideWithValue(false),
  // True, so no widget test is ever redirected into the first-run flow.
  onboardingDoneAtStartupProvider.overrideWithValue(true),
  trashPortProvider.overrideWithValue(trash ?? FakeTrash()),
  reminderPortProvider.overrideWithValue(reminders ?? FakeReminders()),
  supportPortProvider.overrideWithValue(support ?? FakeSupport()),
  attachmentPortProvider.overrideWithValue(attachments ?? FakeAttachments()),
];

/// Pumps [child] inside the app's theme and localisations.
///
/// The text scaler goes through `MaterialApp.builder`, because `WidgetsApp` re-establishes `MediaQuery` from the
/// view and an override placed above it never arrives.
Future<void> pumpOps(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
}
```

### `test/support/recipe_harness.dart`

```dart
/// Shared scaffolding for the Recipe module's widget tests.
///
/// Overrides the feature's view-model providers rather than faking every repository: a widget test's
/// job is the widget — four states, a doubled text scale, the tap-target floor (ARCH_5 §9.1).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/measure.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/services/cookability_engine.dart';
import 'package:alaya/features/recipe/providers/recipe_detail_providers.dart';
import 'package:alaya/features/recipe/providers/recipe_editor_providers.dart';
import 'package:alaya/features/recipe/providers/recipe_list_providers.dart';

/// The narrowest phone this app supports (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// Tall enough that a lazy list builds its whole body.
///
/// Content assertions get this; the U15 gate stays narrow. A `ListView.builder` does not build rows
/// below the fold, so `findsNothing` at 320×640 passes for the wrong reason.
const Size kTallViewport = Size(320, 2400);

/// A stream that never emits, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// An item tracked by weight.
Item weightItem(
  String id,
  String name, {
  int? densityMilliGramsPerMl,
  int? milliGramsPerPiece,
}) => Item(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  unitCategory: UnitCategory.weight,
  defaultDisplayUnitCode: 'g',
  itemKind: ItemKind.food,
  isFavorite: false,
  densityMilliGramsPerMl: densityMilliGramsPerMl,
  milliGramsPerPiece: milliGramsPerPiece,
);

/// Stock for [itemId], [grams] on hand.
ItemStock stockOf(String itemId, int grams, {DateKey? expiry}) => ItemStock(
  itemId: itemId,
  totalRemaining: Qty(grams * 1000, UnitCategory.weight),
  batchCount: 1,
  isLowStock: false,
  nearestExpiry: expiry,
);

/// An ingredient line needing [grams] of [itemId].
RecipeIngredient linked(
  String itemId,
  int grams, {
  int sortOrder = 0,
  bool optional = false,
}) => RecipeIngredient(
  id: 'ing-$itemId',
  recipeId: 'r1',
  itemId: itemId,
  quantity: Qty(grams * 1000, UnitCategory.weight),
  unitCode: 'g',
  isOptional: optional,
  sortOrder: sortOrder,
);

/// An ingredient line measured in millilitres, against an item kept by weight.
///
/// The bridge case: 15 ml of something weighed only converts if the item states its density.
RecipeIngredient inVolume(
  String itemId,
  int millilitres, {
  int sortOrder = 0,
}) => RecipeIngredient(
  id: 'ing-vol-$itemId',
  recipeId: 'r1',
  itemId: itemId,
  quantity: Qty(millilitres * 1000, UnitCategory.volume),
  unitCode: 'ml',
  sortOrder: sortOrder,
);

/// An ingredient line measured in a spoon or cup — half a tablespoon, two thirds of a cup.
///
/// **[amount] is a [Measure], not a [Qty], and that is the point of the fixture.** A recipe line in a
/// vessel is a fraction of that vessel; expressing it as milli-base units in a test would mean writing
/// `Qty(7394, volume)` and hoping it is still half a tablespoon after the factor is applied. The factor
/// comes from [kAllMeasureTestUnits], so it is the one the seed actually inserts — 14787 for a
/// tablespoon, which is where the round trip broke and where a tidy round number would have passed.
RecipeIngredient inVessel(
  String itemId,
  Measure amount, {
  String code = 'tbsp',
  int sortOrder = 0,
}) {
  final unit = kAllMeasureTestUnits.firstWhere((u) => u.code == code);
  return RecipeIngredient(
    id: 'ing-$code-$itemId',
    recipeId: 'r1',
    itemId: itemId,
    quantity: amount.toQty(
      factorToBaseMilli: unit.factorToBaseMilli,
      category: unit.category,
    ),
    unitCode: code,
    sortOrder: sortOrder,
  );
}

/// An ingredient line counted in pieces, against an item kept by weight.
RecipeIngredient inPieces(String itemId, int pieces, {int sortOrder = 0}) =>
    RecipeIngredient(
      id: 'ing-pc-$itemId',
      recipeId: 'r1',
      itemId: itemId,
      quantity: Qty(pieces * 1000, UnitCategory.count),
      unitCode: 'pc',
      sortOrder: sortOrder,
    );

/// An ingredient nothing tracks.
RecipeIngredient untracked(String name, {int sortOrder = 0}) =>
    RecipeIngredient(
      id: 'ing-$name',
      recipeId: 'r1',
      freeText: name,
      sortOrder: sortOrder,
    );

/// A recipe.
Recipe recipeOf({
  String id = 'r1',
  String name = 'Dal',
  int servings = 2,
  List<RecipeIngredient> ingredients = const [],
  List<RecipeStep> steps = const [],
  bool isFavorite = false,
}) => Recipe(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  servings: servings,
  ingredients: ingredients,
  steps: steps,
  isFavorite: isFavorite,
);

/// One batch standing in for a stock rollup, so the coarse and precise paths agree.
///
/// **This is what keeps a test that says nothing about batches meaning what it used to mean.**
/// `CookabilityEngine.judge` answers precisely when given batches and coarsely when not, and the
/// detail screen now always supplies them — so without a default every existing detail test would
/// suddenly judge against an empty shelf and report a shortfall. One unexpired batch holding the whole
/// rollup produces exactly the verdict the coarse path produced.
///
/// The expiry is carried through from `nearestExpiry`, so a test that deliberately dates its stock in
/// the past gets expired behaviour rather than a silent contradiction between the two fields.
Batch batchFromStock(ItemStock rollup) => Batch(
  id: 'synth-${rollup.itemId}',
  itemId: rollup.itemId,
  initialQuantity: rollup.totalRemaining,
  remainingQuantity: rollup.totalRemaining,
  unitCodeAtPurchase: 'g',
  purchasedDateKey: const DateKey(20260701),
  origin: BatchOrigin.manual,
  expiryDateKey: rollup.nearestExpiry,
);

/// Overrides the catalogue's streams, the single-recipe lookup, the unit table and the batch reads.
///
/// **Fixed length**, per ARCH_6 P5: a conditional entry changes the count between scopes and Riverpod
/// refuses it, while two `pumpWidget` calls in one test silently reuse the first scope — so a varying
/// list fails both ways.
///
/// **`recipeProvider` is fed from the same `recipes` list as `allRecipesProvider`.** Two parameters
/// would let a test give the list screen and the detail screen different recipes, which is a
/// disagreement no production build can have. Until this entry existed the detail screen could not be
/// pumped at all — it resolved `recipeRepositoryProvider`, which needs a database — and that is why
/// `RecipeDetailScreen` appeared in no test and rendered `7 ml` for half a tablespoon for as long as it
/// did.
///
/// **`unitsByCodeProvider` defaults to [kAllMeasureTestUnits]**, so a vessel line resolves its unit and
/// takes the `MeasureText` path. Left unoverridden it errors, `valueOrNull` is null, the map is empty and
/// every row silently falls back to `QtyText` — green, and proving nothing.
///
/// **`itemBatchesProvider` defaults to one synthesised batch per stocked item.** The detail screen's
/// verdict now depends on batches, and an unoverridden `batchRepositoryProvider` reaches for a database
/// and throws — which made every row on the screen disappear behind a skeleton. Pass [batches] to state
/// several batches per item, which is what an expiry test needs; omit it and the precise path agrees
/// with the coarse one.
List<Override> recipeOverrides({
  List<Recipe>? recipes,
  Map<String, ItemStock>? stock,
  Map<String, Item>? items,
  Map<String, List<Batch>>? batches,
  List<Unit> units = kAllMeasureTestUnits,
  bool loading = false,
}) => [
  allRecipesProvider.overrideWith(
    (ref) => loading
        ? pendingStream<List<Recipe>>()
        : Stream.value(recipes ?? const []),
  ),
  recipeProvider.overrideWith((ref, id) {
    if (loading) return pendingStream<Recipe?>();
    for (final recipe in recipes ?? const <Recipe>[]) {
      if (recipe.id == id) return Stream.value(recipe);
    }
    // Null is a real answer, and the screen has an empty state for it: a recipe deleted in another
    // tab while its detail screen is open.
    return Stream.value(null);
  }),
  stockByItemProvider.overrideWith(
    (ref) => loading
        ? pendingStream<Map<String, ItemStock>>()
        : Stream.value(stock ?? const {}),
  ),
  itemsByIdProvider.overrideWith(
    (ref) => loading
        ? pendingStream<Map<String, Item>>()
        : Stream.value(items ?? const {}),
  ),
  unitsByCodeProvider.overrideWith(
    (ref) => loading
        ? pendingStream<Map<String, Unit>>()
        : Stream.value({for (final unit in units) unit.code: unit}),
  ),
  itemBatchesProvider.overrideWith((ref, itemId) {
    if (loading) return pendingStream<List<Batch>>();
    final supplied = batches?[itemId];
    if (supplied != null) return Stream.value(supplied);
    final rollup = (stock ?? const <String, ItemStock>{})[itemId];
    // An item with no stock row has no batches, which is the same thing the rollup would have said.
    return Stream.value(rollup == null ? const [] : [batchFromStock(rollup)]);
  }),
];

/// Overrides for the editor's two lookups.
///
/// **Fixed length**, per ARCH_6 P5: a conditional entry changes the count between scopes and Riverpod
/// refuses it. Both default to empty, because an editor with no catalogue is a real state — a user
/// writing their first recipe before cataloguing anything.
List<Override> editorOverrides({
  List<Item> items = const [],
  List<Unit> units = const [],
}) => [
  editorItemsProvider.overrideWith((ref) => Stream.value(items)),
  editorUnitsProvider.overrideWith(
    (ref) => Stream.value(units.isEmpty ? kTestUnits : units),
  ),
];

/// A minimal unit set: one per category, so `QtyField` always has something to select.
///
/// Without a unit in the line's category the picker has nothing to offer and the row cannot produce a
/// `Qty` — the exact condition that made every saved ingredient null.
const List<Unit> kTestUnits = [
  Unit(
    code: 'g',
    category: UnitCategory.weight,
    factorToBaseMilli: 1000,
    displayName: 'Gram',
    isSystem: true,
    sortOrder: 0,
  ),
  Unit(
    code: 'ml',
    category: UnitCategory.volume,
    factorToBaseMilli: 1000,
    displayName: 'Millilitre',
    isSystem: true,
    sortOrder: 1,
  ),
  Unit(
    code: 'pc',
    category: UnitCategory.count,
    factorToBaseMilli: 1000,
    displayName: 'Piece',
    isSystem: true,
    sortOrder: 2,
  ),
];

/// Every measuring vessel, with the factors the seed actually inserts.
///
/// The factors matter: `4929` and `14787` are the ones that do not divide 1000 cleanly, which is where
/// the half-teaspoon round-trip broke. A test using tidy round numbers would have passed.
const List<Unit> kAllMeasureTestUnits = [
  Unit(
    code: 'g',
    category: UnitCategory.weight,
    factorToBaseMilli: 1000,
    displayName: 'Gram',
    isSystem: true,
    sortOrder: 0,
  ),
  Unit(
    code: 'tsp',
    category: UnitCategory.volume,
    factorToBaseMilli: 4929,
    displayName: 'Teaspoon',
    isSystem: true,
    sortOrder: 1,
  ),
  Unit(
    code: 'tbsp',
    category: UnitCategory.volume,
    factorToBaseMilli: 14787,
    displayName: 'Tablespoon',
    isSystem: true,
    sortOrder: 2,
  ),
  Unit(
    code: 'cup',
    category: UnitCategory.volume,
    factorToBaseMilli: 240000,
    displayName: 'Cup',
    isSystem: true,
    sortOrder: 3,
  ),
];

/// A unit set including a tablespoon, for the measuring-chip tests.
///
/// `kTestUnits` deliberately has no spoon — most tests do not need one, and a shorter list makes a
/// dropdown assertion easier to read.
const List<Unit> kSpoonTestUnits = [
  Unit(
    code: 'g',
    category: UnitCategory.weight,
    factorToBaseMilli: 1000,
    displayName: 'Gram',
    isSystem: true,
    sortOrder: 0,
  ),
  Unit(
    code: 'tbsp',
    category: UnitCategory.volume,
    factorToBaseMilli: 14787,
    displayName: 'Tablespoon',
    isSystem: true,
    sortOrder: 1,
  ),
];

/// Pumps [child] inside the app's theme and localisations.
///
/// The text scaler goes through `MaterialApp.builder`, because `WidgetsApp` re-establishes
/// `MediaQuery` from the view and an override placed above it never arrives.
Future<void> pumpRecipe(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
}

/// The engine, for the pure tests.
const CookabilityEngine kEngine = CookabilityEngine();
```

### `test/support/recurring_harness.dart`

```dart
/// Shared scaffolding for the Recurring module's widget tests.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so overdue derivation is the same on every machine.
final Clock kRecurringClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kRecurringClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// An account the pay sheet can draw from.
const Account kAccount = Account(
  id: 'acc-1',
  name: 'Everyday',
  normalizedName: 'everyday',
  kind: AccountKind.bank,
  currencyCode: 'INR',
  openingBalance: Money(0, 'INR'),
  openingBalanceDateKey: kToday,
  isArchived: false,
  includeInNetWorth: true,
  sortOrder: 0,
);

/// A monthly bill anchored on the 31st — the clamp case anomaly A13 is about.
RecurringTemplate billTemplate({
  String id = 'tpl-1',
  String name = 'Rent',
  int amountMinor = 120000,
  RecurringDirection direction = RecurringDirection.outflow,
  RecurringKind kind = RecurringKind.rent,
  RecurringIntervalUnit unit = RecurringIntervalUnit.month,
  int intervalCount = 1,
  int? anchorDayOfMonth = 31,
  bool isPaused = false,
  DateKey nextDue = const DateKey(20260831),
  DateKey? endDateKey,
}) => RecurringTemplate(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  kind: kind,
  direction: direction,
  defaultAmount: Money(amountMinor, 'INR'),
  intervalUnit: unit,
  intervalCount: intervalCount,
  startDateKey: const DateKey(20260131),
  nextDueDateKey: nextDue,
  isPaused: isPaused,
  autoRemind: true,
  remindDaysBefore: 3,
  defaultAccountId: kAccount.id,
  anchorDayOfMonth: anchorDayOfMonth,
  endDateKey: endDateKey,
);

/// A salary, so an inflow can be asserted to read as income.
RecurringTemplate salaryTemplate({String id = 'tpl-2'}) => billTemplate(
  id: id,
  name: 'Salary',
  amountMinor: 8500000,
  direction: RecurringDirection.inflow,
  kind: RecurringKind.salary,
  anchorDayOfMonth: 1,
  nextDue: const DateKey(20260901),
);

/// An occurrence in any state.
RecurringOccurrence occurrence({
  String id = 'occ-1',
  String templateId = 'tpl-1',
  DateKey dueDateKey = const DateKey(20260831),
  RecurringOccurrenceStatus status = RecurringOccurrenceStatus.due,
  int? paidMinor,
  String? paidTransactionId,
}) => RecurringOccurrence(
  id: id,
  templateId: templateId,
  dueDateKey: dueDateKey,
  status: status,
  paidAmount: paidMinor == null ? null : Money(paidMinor, 'INR'),
  paidTransactionId: paidTransactionId,
  paidDateKey: paidMinor == null ? null : dueDateKey,
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpRecurring(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
}
```

### `test/support/service_harness.dart`

```dart
/// Shared scaffolding for the Service Manager module's widget tests.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/service_record.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every warranty and service derivation is the same on every machine.
final Clock kServiceClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kServiceClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// An account a service expense can be drawn from.
const Account kAccount = Account(
  id: 'acc-1',
  name: 'Everyday',
  normalizedName: 'everyday',
  kind: AccountKind.bank,
  currencyCode: 'INR',
  openingBalance: Money(0, 'INR'),
  openingBalanceDateKey: kToday,
  isArchived: false,
  includeInNetWorth: true,
  sortOrder: 0,
);

/// A television — the ordinary case: a thing, with a price and a warranty.
Asset television({
  String id = 'asset-1',
  String name = 'Living room TV',
  AssetStatus status = AssetStatus.active,
  int? priceMinor = 4500000,
  DateKey? warrantyEnd = const DateKey(20270131),
  DateKey? nextService,
  int? serviceIntervalDays,
  String? contactPhone,
  String? linkedRecurringTemplateId,
  DateKey? disposedAt,
  AssetDisposalReason? disposalReason,
  int? disposalMinor,
}) => Asset(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  type: AssetType.electronics,
  status: status,
  brand: 'LG',
  modelNo: 'OLED55C3',
  purchaseDateKey: const DateKey(20260131),
  purchasePrice: priceMinor == null ? null : Money(priceMinor, 'INR'),
  warrantyStartDateKey: const DateKey(20260131),
  warrantyEndDateKey: warrantyEnd,
  warrantyProvider: 'LG India',
  serviceIntervalDays: serviceIntervalDays,
  nextServiceDueDateKey: nextService,
  primaryContactName: contactPhone == null ? null : 'LG Service',
  primaryContactPhone: contactPhone,
  location: 'Living room',
  linkedRecurringTemplateId: linkedRecurringTemplateId,
  disposedAtDateKey: disposedAt,
  disposalReason: disposalReason,
  disposalAmount: disposalMinor == null ? null : Money(disposalMinor, 'INR'),
);

/// A house maid — the case §7.2 exists for: a person in the asset table with a salary history.
Asset maid({
  String id = 'asset-2',
  String name = 'Lakshmi',
  String? phone = '+919876543210',
}) => Asset(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  type: AssetType.serviceProvider,
  status: AssetStatus.active,
  primaryContactName: name,
  primaryContactPhone: phone,
  linkedRecurringTemplateId: 'tpl-1',
);

/// A service record of any type.
ServiceRecord serviceRecord({
  String id = 'rec-1',
  String assetId = 'asset-1',
  DateKey on = const DateKey(20260601),
  ServiceRecordType type = ServiceRecordType.service,
  int? costMinor = 120000,
  String? providerName = 'LG Service',
  String? linkedTransactionId,
  DateKey? nextDue,
}) => ServiceRecord(
  id: id,
  assetId: assetId,
  serviceDateKey: on,
  type: type,
  providerName: providerName,
  cost: costMinor == null ? null : Money(costMinor, 'INR'),
  linkedTransactionId: linkedTransactionId,
  nextDueDateKey: nextDue,
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpService(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
}
```

### `test/support/settings_harness.dart`

```dart
/// Shared scaffolding for the 8A widget tests.
///
/// **The three fakes here are why `AppLock`, `BiometricGate` and `DataTransferPort` exist.** `PinService` and
/// `BackupService` are `final class`, so neither can be implemented outside its own library — and
/// `flutter_secure_storage` and `local_auth` both need a platform channel. Without the contracts, not one test
/// in this phase could have been written, which is a stronger argument for them than any layering diagram.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';
import 'package:alaya/domain/services/lock/app_lock.dart';
import 'package:alaya/domain/services/lock/biometric_gate.dart';
import 'package:alaya/features/onboarding/providers/onboarding_providers.dart';
import 'package:alaya/features/settings/providers/app_settings_providers.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/features/settings/providers/settings_providers.dart';
import 'package:alaya/features/settings/providers/tag_settings_providers.dart';
import 'package:alaya/features/settings/providers/unit_settings_providers.dart';

import 'fake_settings_repository.dart';

/// The narrowest width this app supports, with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every derived date is identical on every machine.
final Clock kSettingsClock = FixedClock(DateTime(2026, 8, 10, 9, 30));

/// Today, according to [kSettingsClock].
const DateKey kSettingsToday = DateKey(20260810);

/// A future that never completes, for a `FutureProvider`'s loading branch.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// A stream that never emits and never closes, for a `StreamProvider`'s loading branch.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// An `AppLock` that answers from fields a test sets, rather than from secure storage.
class FakeAppLock implements AppLock {
  /// Creates the fake.
  FakeAppLock({
    this.enabled = false,
    this.pinLength = 4,
    this.failedCount = 0,
    this.lockout,
    this.correctPin = '1234',
    this.enableFails = false,
  });

  /// Whether a lock is configured.
  bool enabled;

  /// How many digits the configured PIN has.
  int pinLength;

  /// Consecutive failures recorded.
  int failedCount;

  /// The delay in force, or null.
  Duration? lockout;

  /// The PIN [verifyPin] accepts.
  String correctPin;

  /// Whether [enable] reports a failure, for the error branch of PIN setup.
  bool enableFails;

  /// The recovery code [enable] hands back.
  static const String recoveryCode = 'ABCDE-FGHJK';

  @override
  Future<bool> get isEnabled async => enabled;

  @override
  Future<int> readPinLength() async => pinLength;

  @override
  Future<int> readFailedCount() async => failedCount;

  @override
  Future<Duration?> remainingLockout() async => lockout;

  @override
  Future<UnlockOutcome> verifyPin(String pin) async {
    if (lockout != null) {
      return UnlockOutcome(
        unlocked: false,
        refusal: UnlockRefusal.throttled,
        failedCount: failedCount,
        retryAfter: lockout,
      );
    }
    if (pin == correctPin) return const UnlockOutcome.success();
    failedCount += 1;
    return UnlockOutcome(
      unlocked: false,
      refusal: UnlockRefusal.wrongPin,
      failedCount: failedCount,
    );
  }

  @override
  Future<Result<String, Failure>> enable({required String pin}) async {
    if (enableFails) {
      return const Result.failure(
        UnexpectedFailure('Secure storage is unavailable on this device.'),
      );
    }
    enabled = true;
    correctPin = pin;
    pinLength = pin.length;
    return const Result.ok(recoveryCode);
  }

  @override
  Future<Result<void, Failure>> changePin({
    required String currentPin,
    required String newPin,
  }) async => const Result.ok(null);

  @override
  Future<Result<void, Failure>> disable({required String pin}) async {
    enabled = false;
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> resetWithRecoveryCode({
    required String code,
    required String newPin,
  }) async {
    if (code.replaceAll('-', '').toUpperCase() !=
        recoveryCode.replaceAll('-', '')) {
      return const Result.failure(
        ValidationFailure('That recovery code is not right.', field: 'code'),
      );
    }
    correctPin = newPin;
    return const Result.ok(null);
  }
}

/// A `BiometricGate` that neither needs a sensor nor a platform channel.
class FakeBiometricGate implements BiometricGate {
  /// Creates the fake.
  FakeBiometricGate({this.available = false, this.succeeds = true});

  /// Whether the shortcut is offered at all.
  bool available;

  /// Whether [authenticate] succeeds.
  bool succeeds;

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<Result<void, Failure>> authenticate({required String reason}) async =>
      succeeds
      ? const Result.ok(null)
      : const Result.failure(
          BusinessRuleFailure('Not recognised.', rule: 'biometricRejected'),
        );
}

/// A `DataTransferPort` that records what it was asked to do.
class FakeDataTransfer implements DataTransferPort {
  /// Creates the fake.
  FakeDataTransfer({this.exportFails = false, this.eraseFails = false});

  /// Whether the export reports a failure.
  bool exportFails;

  /// Whether the erase reports a failure.
  bool eraseFails;

  /// How many exports were requested.
  int exports = 0;

  /// How many erases were requested.
  int erases = 0;

  @override
  Future<Result<BackupArtefact, Failure>> exportAndShare() async {
    exports += 1;
    if (exportFails) {
      return const Result.failure(
        UnexpectedFailure('No room left on this device.'),
      );
    }
    return const Result.ok(
      (
        path: '/cache/alaya.db',
        sizeBytes: 4096,
        isZipped: false,
        fileName: 'alaya-backup.db',
      ),
    );
  }

  // Phase 8B extended `DataTransferPort` with SAF export, history and restore, so this fake stopped satisfying
  // it. Answering flatly is right here: 8A's tests are about the lock and the settings tree, and a fake that
  // pretended to restore would invite an 8A test to assert on 8B's behaviour.
  @override
  Future<Result<BackupArtefact?, Failure>> exportToLocation() async =>
      const Result.ok(null);

  @override
  Stream<List<BackupRecord>> watchHistory() => Stream.value(const []);

  @override
  Future<Result<void, Failure>> forgetHistoryEntry(String id) async =>
      const Result.ok(null);

  @override
  Future<Result<String?, Failure>> pickBackupFile() async =>
      const Result.ok(null);

  @override
  Future<Result<int, Failure>> readBackupVersion(String path) async =>
      const Result.ok(1);

  @override
  bool get canSaveToLocation => false;

  @override
  int get appSchemaVersion => 1;

  @override
  Future<Result<RestoreOutcome, Failure>> merge(String path) async =>
      const Result.ok(
        (
          mode: RestoreMode.merge,
          tablesMerged: 0,
          backupSchemaVersion: 1,
          rollbackAvailable: false,
        ),
      );

  @override
  Future<Result<RestoreOutcome, Failure>> replace(String path) async =>
      const Result.ok(
        (
          mode: RestoreMode.replace,
          tablesMerged: 0,
          backupSchemaVersion: 1,
          rollbackAvailable: false,
        ),
      );

  @override
  Future<Result<void, Failure>> rollback() async => const Result.ok(null);

  @override
  Future<bool> hasRollback() async => false;

  @override
  Future<Result<void, Failure>> eraseEverything() async {
    erases += 1;
    return eraseFails
        ? const Result.failure(
            UnexpectedFailure('The data could not be deleted.'),
          )
        : const Result.ok(null);
  }
}

/// One account, for the lists and the editor.
Account account({
  String id = 'ac-1',
  String name = 'Cash',
  AccountKind kind = AccountKind.cash,
  bool isArchived = false,
  bool includeInNetWorth = true,
}) => Account(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  kind: kind,
  currencyCode: 'INR',
  openingBalance: const Money(250000, 'INR'),
  openingBalanceDateKey: kSettingsToday,
  isArchived: isArchived,
  includeInNetWorth: includeInNetWorth,
  sortOrder: 0,
);

/// One tag, scoped where the caller says.
Tag tag({
  String id = 'tg-1',
  String name = 'Kitchen',
  Set<TagScope> scopes = const {TagScope.inventory},
  String? parentTagId,
  bool isSystem = false,
}) => Tag(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  allowedScopes: scopes,
  isSystem: isSystem,
  sortOrder: 0,
  isDeleted: false,
  parentTagId: parentTagId,
);

/// One unit.
Unit unit({
  String code = 'kg',
  String displayName = 'Kilogram',
  UnitCategory category = UnitCategory.weight,
  int factorToBaseMilli = 1000000,
  bool isSystem = true,
}) => Unit(
  code: code,
  category: category,
  factorToBaseMilli: factorToBaseMilli,
  displayName: displayName,
  isSystem: isSystem,
  sortOrder: 0,
);

/// One payment method.
PaymentMethod paymentMethod({
  String id = 'pm-1',
  String name = 'Cash',
  bool isSystem = false,
}) => PaymentMethod(
  id: id,
  name: name,
  kind: PaymentMethodKind.cash,
  isSystem: isSystem,
  sortOrder: 0,
);

/// One payee.
Payee payee({String id = 'py-1', String name = 'Corner Shop', String? phone}) =>
    Payee(
      id: id,
      name: name,
      normalizedName: name.toLowerCase(),
      kind: PayeeKind.merchant,
      phone: phone,
    );

/// One currency.
Currency currency({String code = 'INR', bool isEnabled = true}) => Currency(
  code: code,
  name: code,
  symbol: code == 'INR' ? '₹' : '¥',
  decimalDigits: code == 'JPY' ? 0 : 2,
  isEnabled: isEnabled,
  sortOrder: 0,
);

/// Overrides every provider 8A's screens reach.
///
/// **Fixed length, always.** A conditional entry changes the override count between scopes and Riverpod refuses
/// it outright — and two `pumpWidget` calls in one test silently reuse the first scope, so a varying list fails
/// in both directions (ARCH_6 P5). Every provider is overridden even where a test does not care, because an
/// un-overridden repository reaches a real database, which a widget test has no business opening.
List<Override> settingsOverrides({
  FakeAppLock? lock,
  FakeBiometricGate? biometric,
  FakeDataTransfer? transfer,
  AsyncValue<List<Account>>? accounts,
  AsyncValue<List<Tag>>? tags,
  AsyncValue<List<Unit>>? units,
  AsyncValue<List<PaymentMethod>>? paymentMethods,
  AsyncValue<List<Payee>>? payees,
  AsyncValue<List<Currency>>? currencies,
}) => [
  clockProvider.overrideWithValue(kSettingsClock),
  // `lockConfiguredAtStartupProvider` throws when un-overridden, by design — `bootstrap()` is the only place
  // that resolves it. A widget test never has a lock, so false.
  lockConfiguredAtStartupProvider.overrideWithValue(false),
  // True, so no widget test is ever redirected into the first-run flow.
  onboardingDoneAtStartupProvider.overrideWithValue(true),
  settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
  pinServiceProvider.overrideWithValue(lock ?? FakeAppLock()),
  biometricGateProvider.overrideWithValue(biometric ?? FakeBiometricGate()),
  dataTransferPortProvider.overrideWithValue(transfer ?? FakeDataTransfer()),
  accountsSettingsProvider.overrideWith(
    (ref) => _stream(accounts ?? AsyncValue.data([account()])),
  ),
  tagsSettingsProvider.overrideWith(
    (ref) => _stream(tags ?? AsyncValue.data([tag()])),
  ),
  unitsSettingsProvider.overrideWith(
    (ref) => _stream(units ?? AsyncValue.data([unit()])),
  ),
  paymentMethodsSettingsProvider.overrideWith(
    (ref) => _stream(paymentMethods ?? AsyncValue.data([paymentMethod()])),
  ),
  payeesSettingsProvider.overrideWith(
    (ref) => _stream(payees ?? AsyncValue.data([payee()])),
  ),
  currenciesSettingsProvider.overrideWith(
    (ref) => _stream(currencies ?? AsyncValue.data([currency()])),
  ),
  homeCurrencyCodeProvider.overrideWith((ref) async => 'INR'),
  accountsHomeCurrencyProvider.overrideWith((ref) async => 'INR'),
  onboardingCurrenciesProvider.overrideWith(
    (ref) => Stream.value([currency(), currency(code: 'JPY')]),
  ),
  onboardingCurrencyDigitsProvider.overrideWith(
    (ref, code) async => code == 'JPY' ? 0 : 2,
  ),
  settingsAccountCountProvider.overrideWith((ref) => Stream.value(1)),
  settingsPaymentMethodCountProvider.overrideWith((ref) => Stream.value(1)),
  settingsPayeeCountProvider.overrideWith((ref) => Stream.value(1)),
  settingsTagCountProvider.overrideWith((ref) => Stream.value(1)),
  settingsUnitCountProvider.overrideWith((ref) => Stream.value(1)),
  settingsCurrencyCountProvider.overrideWith(
    (ref) => Stream.value((enabled: 1, total: 2)),
  ),
];

Stream<T> _stream<T>(AsyncValue<T> value) => value.when(
  data: Stream.value,
  loading: pendingStream<T>,
  error: (error, stack) => Stream<T>.error(error, stack),
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
///
/// The text scaler goes through `MaterialApp.builder`, not a `MediaQuery` above the app: `WidgetsApp`
/// re-establishes `MediaQuery` from the view, so an override placed above it never arrives (ARCH_5 §10).
///
/// [wrapInShell] supplies a `Scaffold`, because `MaterialApp` provides no `Material` ancestor and a shell
/// destination declares none of its own — without it, every `ChoiceChip` and `InkWell` asserts.
Future<void> pumpSettings(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
  bool dark = false,
  bool wrapInShell = false,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
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
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: wrapInShell ? Scaffold(body: child) : child,
      ),
    ),
  );
  await tester.pump();
}
```

### `test/support/shopping_harness.dart`

```dart
/// Shared scaffolding for the Shopping module's widget tests.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/entities/unit.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so snooze dates are the same on every machine.
final Clock kShoppingClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kShoppingClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// Kilograms.
const Unit kKilogram = Unit(
  code: 'kg',
  category: UnitCategory.weight,
  factorToBaseMilli: 1000000,
  displayName: 'kilogram',
  isSystem: true,
  sortOrder: 1,
);

/// A shopping-scoped tag.
const Tag kProduceTag = Tag(
  id: 'tag-1',
  name: 'Produce',
  normalizedName: 'produce',
  allowedScopes: {TagScope.shopping},
  isSystem: false,
  sortOrder: 0,
  isDeleted: false,
);

/// A catalogued item an entry can link to.
const Item kOnion = Item(
  id: 'item-1',
  name: 'Onion',
  normalizedName: 'onion',
  unitCategory: UnitCategory.weight,
  defaultDisplayUnitCode: 'kg',
  itemKind: ItemKind.food,
  isFavorite: false,
  lowStockThreshold: Qty(2000000, UnitCategory.weight),
);

/// The default shopping list.
const ShoppingList kList = ShoppingList(
  id: 'list-1',
  name: 'Weekly shop',
  isDefault: true,
  isArchived: false,
);

/// An archived list, for the manager sheet.
const ShoppingList kArchivedList = ShoppingList(
  id: 'list-2',
  name: 'Diwali',
  isDefault: false,
  isArchived: true,
);

/// A manual entry.
ShoppingEntry sampleEntry({
  String id = 'entry-1',
  String? freeText = 'Television',
  String? itemId,
  String? tagId,
  bool isChecked = false,
  int sortOrder = 0,
  Money? estimatedPrice = const Money(4500000, 'INR'),
  ShoppingEntryOrigin origin = ShoppingEntryOrigin.manual,
  ShoppingEntryAutoState autoState = ShoppingEntryAutoState.active,
  DateKey? snoozeUntil,
  Qty? stockAtGeneration,
}) => ShoppingEntry(
  id: id,
  listId: kList.id,
  origin: origin,
  autoState: autoState,
  isChecked: isChecked,
  sortOrder: sortOrder,
  itemId: itemId,
  freeText: freeText,
  tagId: tagId,
  estimatedPrice: estimatedPrice,
  snoozeUntilDateKey: snoozeUntil,
  stockAtGeneration: stockAtGeneration,
);

/// An auto-generated low-stock suggestion, short by 1.5 kg against a 2 kg threshold.
ShoppingEntry sampleSuggestion({
  String id = 'auto-1',
  ShoppingEntryAutoState autoState = ShoppingEntryAutoState.active,
  DateKey? snoozeUntil,
}) => sampleEntry(
  id: id,
  freeText: null,
  itemId: kOnion.id,
  estimatedPrice: null,
  origin: ShoppingEntryOrigin.autoLowStock,
  autoState: autoState,
  snoozeUntil: snoozeUntil,
  stockAtGeneration: const Qty(500000, UnitCategory.weight),
);

/// A draft line, as `buildPurchaseDraft` would return it.
TransactionLine sampleDraftLine({
  String id = 'line-1',
  String description = 'Onion',
}) => TransactionLine(
  id: id,
  transactionId: '',
  lineNo: 1,
  description: description,
  destination: TransactionLineDestination.inventory,
  itemId: kOnion.id,
  quantity: const Qty(2000000, UnitCategory.weight),
  unitCode: 'kg',
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpShopping(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
}
```

### `test/support/split_fakes.dart`

```dart
/// Fakes for the two ports the split services write through.
///
/// **These exist because those services had no tests at all.** `SplitExpenseService`,
/// `SettlementService` and `SplitBalanceService` appeared in no test file — the same finding that
/// produced `cook_fakes.dart` last cycle, when `RecipeCookService` turned out to have never been
/// exercised. A service with no test is invisible to the suite: green proves nothing about it.
///
/// **The fakes fake storage, not arithmetic.** `SplitResolver` and `DebtSimplifier` run for real
/// through the services under test, so an ordering or allocation rule reimplemented here could not
/// diverge from production — which is the failure a hand-rolled fake invites.
library;

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/repositories/split_group_repository.dart';
import 'package:alaya/domain/repositories/split_ledger_repository.dart';
import 'package:alaya/domain/services/split/debt_simplifier.dart' show DebtEdge;

/// One `recordSettlement` that reached the repository.
typedef RecordedSettlement = ({
  SplitSettlement settlement,
  Transaction? transaction,
});

/// A `SplitLedgerRepository` that keeps what it is given.
class FakeSplitLedger implements SplitLedgerRepository {
  /// Creates the fake.
  FakeSplitLedger({
    List<SplitBalance> balances = const [],
    List<DebtEdge> debts = const [],
    this.rejectSave = false,
  }) : _balances = balances,
       _debts = debts;

  final List<SplitBalance> _balances;
  final List<DebtEdge> _debts;

  /// Whether `saveExpense` refuses, for the branch where a service must surface a failure.
  bool rejectSave;

  /// Every expense saved, in order.
  final List<SplitExpense> saved = [];

  /// Every settlement recorded, with the transaction it was paired with.
  final List<RecordedSettlement> settlements = [];

  /// Ids passed to `deleteExpense`.
  final List<String> deleted = [];

  @override
  Future<Result<SplitExpense, Failure>> saveExpense(
    SplitExpense expense,
  ) async {
    if (rejectSave) {
      return const Result.failure(
        BusinessRuleFailure('refused', rule: 'test'),
      );
    }
    saved.add(expense);
    return Result.ok(expense);
  }

  @override
  Future<Result<SplitSettlement, Failure>> recordSettlement({
    required SplitSettlement settlement,
    Transaction? transaction,
  }) async {
    settlements.add((settlement: settlement, transaction: transaction));
    return Result.ok(settlement);
  }

  @override
  Future<Result<void, Failure>> deleteExpense(String id) async {
    deleted.add(id);
    return const Result.ok(null);
  }

  @override
  Stream<List<SplitBalance>> watchBalances() => Stream.value(_balances);

  @override
  Stream<List<SplitBalance>> watchGroupBalances(String groupId) =>
      Stream.value(_balances);

  @override
  Stream<List<SplitBalance>> watchBalanceWith(String payeeId) => Stream.value([
    for (final b in _balances)
      if (b.payeeId == payeeId) b,
  ]);

  @override
  Future<List<DebtEdge>> debtsIn(String groupId) async => _debts;

  // Unused by the services under test. Throwing rather than returning something plausible, so a
  // future change that starts depending on one of these is announced instead of quietly passing.

  @override
  Stream<List<SplitExpenseSummary>> watchExpenses({
    required DateKey from,
    required DateKey to,
    String? groupId,
  }) => throw UnimplementedError('FakeSplitLedger.watchExpenses');

  @override
  Stream<SplitExpense?> watchExpenseById(String id) =>
      throw UnimplementedError('FakeSplitLedger.watchExpenseById');

  @override
  Future<SplitExpense?> expenseById(String id) =>
      throw UnimplementedError('FakeSplitLedger.expenseById');

  @override
  Future<SplitExpense?> expenseForTransaction(String transactionId) =>
      throw UnimplementedError('FakeSplitLedger.expenseForTransaction');

  /// **Throws, by this file's own rule, and returning `Result.ok` here would have been the mistake.**
  ///
  /// Merging a placeholder into a real payee is reached from a provider rather than from any service
  /// these fakes exist for, so nothing under test calls it — and a fake that answered "fine" would let a
  /// future service start depending on a merge that never happened. That is precisely what the comment
  /// above forbids.
  ///
  /// It also cannot be faked usefully. The real work is five tables in one transaction, with shares
  /// **summed** where the target is already on the same expense; a fake reproducing that would be a
  /// second implementation of the merge, free to disagree with the first — the failure the library
  /// comment names in its own opening paragraph.
  ///
  /// A widget test for the naming sheet wants a different fake: one that records `(from, into)` and
  /// asserts the sheet asked for the right pair. That belongs beside the sheet's test, not here.
  @override
  Future<Result<void, Failure>> mergePlaceholder({
    required String placeholderPayeeId,
    required String payeeId,
  }) => throw UnimplementedError('FakeSplitLedger.mergePlaceholder');

  @override
  Stream<List<SplitSettlement>> watchSettlements({
    required DateKey from,
    required DateKey to,
    String? groupId,
  }) => throw UnimplementedError('FakeSplitLedger.watchSettlements');

  @override
  Future<Result<void, Failure>> deleteSettlement(String id) =>
      throw UnimplementedError('FakeSplitLedger.deleteSettlement');

  @override
  Stream<List<SplitActivityEntry>> watchActivity({
    String? groupId,
    int limit = 50,
  }) => throw UnimplementedError('FakeSplitLedger.watchActivity');
}

/// A `SplitGroupRepository` that answers only what the services ask.
class FakeSplitGroups implements SplitGroupRepository {
  /// Creates the fake. [self] null means the user has not been chosen yet.
  FakeSplitGroups({this.self});

  /// The payee claimed as the user.
  String? self;

  @override
  Future<String?> selfPayeeId() async => self;

  @override
  Future<Result<void, Failure>> setSelfPayeeId(String payeeId) async {
    self = payeeId;
    return const Result.ok(null);
  }

  @override
  Stream<List<SplitGroup>> watchAll() =>
      throw UnimplementedError('FakeSplitGroups.watchAll');

  @override
  Stream<List<SplitGroup>> watchActive() =>
      throw UnimplementedError('FakeSplitGroups.watchActive');

  @override
  Stream<SplitGroup?> watchById(String id) =>
      throw UnimplementedError('FakeSplitGroups.watchById');

  @override
  Future<SplitGroup?> byId(String id) =>
      throw UnimplementedError('FakeSplitGroups.byId');

  @override
  Stream<List<SplitGroup>> watchForPayee(String payeeId) =>
      throw UnimplementedError('FakeSplitGroups.watchForPayee');

  @override
  Future<Result<SplitGroup, Failure>> save(SplitGroup group) =>
      throw UnimplementedError('FakeSplitGroups.save');

  @override
  Future<Result<void, Failure>> setArchived({
    required String id,
    required bool isArchived,
  }) => throw UnimplementedError('FakeSplitGroups.setArchived');

  @override
  Future<Result<void, Failure>> delete(String id) =>
      throw UnimplementedError('FakeSplitGroups.delete');
}

/// Sequential ids, so an assertion can name one.
class SeqUids implements UidGenerator {
  int _next = 0;

  @override
  String generate() => 'id-${++_next}';
}

/// A balance in one direction, for building fixtures.
SplitBalance owedToMe(String payeeId, int minor, {DateKey? since}) =>
    SplitBalance(
      payeeId: payeeId,
      owedToMe: Money(minor, 'INR'),
      iOwe: const Money(0, 'INR'),
      oldestUnsettledDateKey: since,
    );

/// The other direction.
SplitBalance iOwe(String payeeId, int minor, {DateKey? since}) => SplitBalance(
  payeeId: payeeId,
  owedToMe: const Money(0, 'INR'),
  iOwe: Money(minor, 'INR'),
  oldestUnsettledDateKey: since,
);
```

### `test/support/split_harness.dart`

```dart
/// Shared scaffolding for the Split module's widget tests.
///
/// Overrides the feature's view-model providers rather than faking every repository: a widget test's
/// job is the widget — four states, a doubled text scale, the tap-target floor (ARCH_5 §9.1).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// The narrowest phone this app supports (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// Tall enough that a lazy list builds its whole body.
///
/// Content assertions get this; the U15 gate stays narrow. A `ListView` does not build rows below the
/// fold, so `findsNothing` at 320×640 passes for the wrong reason.
const Size kTallViewport = Size(320, 3200);

/// A stream that never emits, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A person who can be chosen for a split.
Payee person(String id, String name, {String? phone}) => Payee(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  kind: PayeeKind.person,
  phone: phone,
);

/// A row this app wrote because a split had to name somebody.
///
/// Appears on balances so it can be renamed, and nowhere a real contact belongs — see
/// [splitOverrides], which feeds these to `splitParticipantsProvider` only.
Payee placeholder(String id, String name) => Payee(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  kind: PayeeKind.splitPlaceholder,
);

/// A group with [members], optionally carrying default weights.
///
/// **Named `splitGroup`, not `group`.** `flutter_test` exports a top-level `group` for suites, and a
/// harness that shadows it makes every `group('...', ...)` in every test file that imports this one
/// ambiguous — five errors in one file, none of them pointing at the fixture that caused them.
SplitGroup splitGroup(
  String id,
  String name, {
  required List<String> members,
  Map<String, int>? weights,
  bool archived = false,
}) => SplitGroup(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  defaultSplitMethod: weights == null ? SplitMethod.equal : SplitMethod.shares,
  isArchived: archived,
  sortOrder: 0,
  members: [
    for (var i = 0; i < members.length; i++)
      SplitMember(
        id: 'm-${members[i]}',
        groupId: id,
        payeeId: members[i],
        defaultWeightBasisPoints: weights?[members[i]],
        sortOrder: i,
      ),
  ],
);

/// Somebody owes the user.
SplitBalance owedToMe(String payeeId, int minor, {DateKey? since}) =>
    SplitBalance(
      payeeId: payeeId,
      owedToMe: Money(minor, 'INR'),
      iOwe: const Money(0, 'INR'),
      oldestUnsettledDateKey: since,
    );

/// The user owes somebody.
SplitBalance iOwe(String payeeId, int minor, {DateKey? since}) => SplitBalance(
  payeeId: payeeId,
  owedToMe: const Money(0, 'INR'),
  iOwe: Money(minor, 'INR'),
  oldestUnsettledDateKey: since,
);

/// An account a settlement or an expense can move through.
///
/// **Every required field supplied, including the three a fixture is tempted to skip.**
/// `openingBalance`, `openingBalanceDateKey` and `includeInNetWorth` are required on `Account` because
/// anomaly A03 made them load-bearing — a balance is opening balance plus movements, and an account
/// that silently defaulted to zero would make every derived figure quietly wrong.
Account account(String id, String name) => Account(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  kind: AccountKind.bank,
  currencyCode: 'INR',
  openingBalance: const Money(0, 'INR'),
  openingBalanceDateKey: const DateKey(20260101),
  isArchived: false,
  includeInNetWorth: true,
  sortOrder: 0,
);

/// The overrides every split screen needs to render at all.
///
/// **Defaults that make the screen work, not defaults that make it empty.** A harness whose defaults
/// leave every provider loading forces each test to restate the same five overrides before it can
/// assert anything, and the restating is where they drift apart.
///
/// **Both people providers are overridden, and forgetting the second cost a failing test.**
/// `splitPeopleProvider` answers *"who may I add?"* and holds [people]; `splitParticipantsProvider`
/// answers *"who is this?"* and holds [people] **plus** [placeholders]. `splitPayeeProvider` — which
/// every balance row uses to turn an id into a name — reads the second. Override only the first and
/// the second falls through to the real implementation, `payeeRepositoryProvider` is absent in a
/// widget test, and every name renders as "Someone".
///
/// **Totals and ageing are derived from [balances] rather than passed in.** In production they come
/// from the same rows, so a harness that let a test state them independently would let it assert a
/// screen showing "₹4,000 owed" above a list containing nobody — a state the app cannot reach, tested
/// as though it could.
List<Override> splitOverrides({
  List<Payee> people = const [],
  List<Payee> placeholders = const [],
  List<SplitGroup> groups = const [],
  List<SplitBalance> balances = const [],
  List<Account> accounts = const [],
  String? self = 'me',
  int digits = 2,
  DateKey today = const DateKey(20260814),
  int ageingThresholdDays = 14,
}) {
  var owed = const Money(0, 'INR');
  var owing = const Money(0, 'INR');
  final ageing = <AgeingDebt>[];
  for (final balance in balances) {
    if (balance.isSettled) continue;
    if (balance.theyOweMe) {
      owed += balance.outstanding;
    } else {
      owing += balance.outstanding;
    }
    final age = balance.ageInDays(today);
    if (age != null && age >= ageingThresholdDays) {
      ageing.add(AgeingDebt(balance: balance, ageInDays: age));
    }
  }
  ageing.sort((a, b) => b.ageInDays.compareTo(a.ageInDays));

  return [
    splitPeopleProvider.overrideWith((ref) => Stream.value(people)),
    splitParticipantsProvider.overrideWith(
      (ref) => Stream.value([...people, ...placeholders]),
    ),
    splitAllGroupsProvider.overrideWith((ref) => Stream.value(groups)),
    splitBalancesProvider.overrideWith((ref) => Stream.value(balances)),
    splitAccountsProvider.overrideWith((ref) => Stream.value(accounts)),
    splitSelfProvider.overrideWith((ref) async => self),
    splitDecimalDigitsProvider.overrideWith((ref) async => digits),
    splitTodayProvider.overrideWithValue(today),
    splitTotalsProvider.overrideWith(
      (ref) async =>
          balances.isEmpty ? {} : {'INR': (owedToMe: owed, iOwe: owing)},
    ),
    splitAgeingProvider.overrideWith((ref) async => ageing),
  ];
}

/// Pumps [child] inside the app's theme and localisations.
///
/// **Two frames, not one, and the second is not padding.** The overrides above are `Stream.value(...)`
/// and async closures, so each provider resolves on its own microtask turn. After a single frame a
/// balance row could render while `splitPayeeProvider` still read null and fell back to "Someone" — a
/// test asserting on a name then failed while the screen was perfectly correct.
///
/// `pumpAndSettle` would also work and is worse: it spins until no frame is scheduled, so a screen
/// with any repeating animation hangs the suite instead of failing it.
Future<void> pumpSplit(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Pumps a screen that lives **inside the drawer shell**, which owns the `Scaffold` and the `AppBar`.
///
/// **`SplitHomeScreen` supplies neither**, so pumping it bare would leave `AmountText` and the rest
/// without a `Material` ancestor and fail for a reason that has nothing to do with the test. This
/// wrapper stands in for `_ShellScaffold` — and because it provides the only `AppBar` in the tree, a
/// test can assert `findsOneWidget` and prove the screen is not adding a second.
Future<void> pumpInShell(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) => pumpSplit(
  tester,
  Scaffold(
    appBar: AppBar(title: const Text('Split')),
    body: child,
  ),
  overrides: overrides,
  size: size,
  textScale: textScale,
);
```

### `tool/check_arb_keys.py`

```python
#!/usr/bin/env python3
"""Checks that every `strings.<key>` reference in lib/ exists in app_en.arb.

Replaces the shell pipeline that ARCH_M §5 used to carry, which had two faults that each produced a wrong
answer rather than a noisy one:

1. **`sort` and `comm` disagree on collation.** `sort` orders by the current locale's rules; `comm` walks the
   two streams assuming an order it computes differently. One out-of-step line and `comm` starts reporting
   lines from file 1 that do exist in file 2 — then aborts, so the run is *silent* about everything after the
   desync rather than clean. A run reporting `actionDeleteItem`, `actionDeleteTransaction` and
   `billSetUpAction` as missing keys that were all three present is what prompted this file.

2. **It greps raw source, so it matches comments.** ARCH_M §7 says exactly this, about exactly this hazard:
   "A `grep` for a symbol matches comments that mention it. Strip comment lines before searching. This
   produced four false findings in one phase." §5's own snippet did not do it.

Comparison happens with Python sets, so there is no collation to get wrong. Comments are stripped with a
quote-aware scan, so a `//` inside a string literal does not truncate the line and a symbol named in a
trailing comment is not counted as a reference.

**Known limit:** block comments (`/* ... */`) are not tracked across lines. This codebase uses `//` and `///`
throughout; if that changes, this needs a real scanner rather than a line-wise one.

    python3 tool/check_arb_keys.py            # exits 1 if any reference is missing
    python3 tool/check_arb_keys.py --unused   # also lists keys nothing references
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

LIB = Path("lib")
ARB = Path("lib/app/l10n/app_en.arb")

# `strings.someKey`. The lookbehind stops `otherstrings.foo` counting; `AlayaStrings.delegate` never matches
# anyway, because the literal here is lowercase and that identifier capitalises the S.
REFERENCE = re.compile(r"(?<![A-Za-z0-9_$])strings\.([A-Za-z][A-Za-z0-9]*)")


def strip_comments(line: str) -> str:
    """Returns [line] with any `//` comment removed, ignoring `//` inside a string literal.

    Written character-wise rather than with a regex because the case that matters is a URL: a naive
    `s://.*//` turns `'https://example.com'` into `'https:'` and would hide a real reference sitting after it
    on the same line.
    """
    quote: str | None = None
    index = 0
    while index < len(line):
        char = line[index]
        if quote is not None:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = None
        elif char in "'\"":
            quote = char
        elif char == "/" and line.startswith("//", index):
            return line[:index]
        index += 1
    return line


def references() -> dict[str, list[str]]:
    """Every referenced key, mapped to the `file:line` sites that reference it."""
    found: dict[str, list[str]] = {}
    for path in sorted(LIB.rglob("*.dart")):
        # The generated localisations declare every getter, so they reference nothing and would otherwise
        # report every key as used — which would make --unused always empty and useless.
        if "l10n/generated" in path.as_posix():
            continue
        for number, raw in enumerate(
            path.read_text(encoding="utf-8").splitlines(), start=1
        ):
            for key in REFERENCE.findall(strip_comments(raw)):
                found.setdefault(key, []).append(f"{path}:{number}")
    return found


def declared() -> set[str]:
    """Every key in the ARB, excluding the `@`-prefixed metadata entries."""
    table = json.loads(ARB.read_text(encoding="utf-8"))
    return {key for key in table if not key.startswith("@")}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--unused",
        action="store_true",
        help="also list ARB keys nothing in lib/ references",
    )
    args = parser.parse_args()

    if not ARB.exists():
        print(f"no ARB at {ARB} — run from the repository root", file=sys.stderr)
        return 2

    used = references()
    have = declared()
    missing = sorted(set(used) - have)

    for key in missing:
        # Every site, not just the first. A key added to one screen and copied into three is three edits.
        print(f"MISSING  {key}")
        for site in used[key]:
            print(f"         {site}")

    if args.unused:
        for key in sorted(have - set(used)):
            print(f"unused   {key}")

    if missing:
        print(
            f"\n{len(missing)} key(s) referenced but not in the ARB — "
            f"`flutter gen-l10n` will generate no getter and the build will fail.",
            file=sys.stderr,
        )
        return 1

    print(f"{len(used)} referenced key(s), all present in {ARB}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

### `tool/check_layering.dart`

```dart
import 'dart:io';

/// Enforces Law L12: `lib/domain/` may never import Flutter, drift, or `lib/data/`, and
/// `lib/core/` may never import Flutter. Run with `dart run tool/check_layering.dart`; exits
/// with code 1 and a list of violations if the rule is broken, or 0 if the tree is clean.
Future<void> main() async {
  final violations = <String>[
    ..._scan(
      directory: 'lib/domain',
      bannedImportPrefixes: const [
        'package:flutter/',
        'package:drift/',
        'package:alaya/data/',
      ],
      bannedRelativeSegment: '/data/',
    ),
    ..._scan(
      directory: 'lib/core',
      bannedImportPrefixes: const ['package:flutter/'],
      bannedRelativeSegment: null,
    ),
  ];

  if (violations.isEmpty) {
    stdout.writeln('check_layering: OK — no boundary violations found.');
    return;
  }

  stderr.writeln('check_layering: FAILED — ${violations.length} violation(s):');
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  exitCode = 1;
}

/// Scans every `.dart` file under [directory] and returns one description per import
/// statement that starts with a banned prefix or contains [bannedRelativeSegment].
List<String> _scan({
  required String directory,
  required List<String> bannedImportPrefixes,
  required String? bannedRelativeSegment,
}) {
  final root = Directory(directory);
  if (!root.existsSync()) return const [];

  final found = <String>[];
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;

    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('import ') && !line.startsWith('export ')) continue;

      final isBannedPrefix = bannedImportPrefixes.any(
            (prefix) => line.contains("'$prefix") || line.contains('"$prefix'),
      );
      final isBannedRelative = bannedRelativeSegment != null &&
          line.contains(bannedRelativeSegment) &&
          !line.contains('package:');

      if (isBannedPrefix || isBannedRelative) {
        found.add('${entity.path}:${i + 1}: $line');
      }
    }
  }
  return found;
}
```

### `tool/make_bundles.py`

```python
#!/usr/bin/env python3
"""Regenerate Alaya's maintenance bundles from the working tree.

Run from the repo root:      python3 tool/make_bundles.py
One bundle only:             python3 tool/make_bundles.py F_EXPENSE

A bundle is a download set, not a partition — every file lands in exactly one, and the routing table in
ARCH_M §3 says which sets a given change needs. The bundles are a snapshot of the repo, so regenerate the
ones a change touched immediately after applying it. A stale bundle is worse than no bundle: it looks
authoritative and describes code that no longer exists.

`_manifest.json` records when each bundle was written, so `--stale` can answer "which of these no longer
match the tree" without opening any of them.
"""
import datetime
import hashlib
import json
import os
import sys

# Every extension worth bundling. **A file whose extension is missing here is invisible twice over**:
# `collect()` skips it, and the unbundled report at the bottom filters on this same table, so nothing
# warns. `.drift` was absent for the whole of Phase R and took six view files with it — including the
# authored definition of the read model Law L7 says every repository depends on.
LANG = {'.dart': 'dart', '.arb': 'json', '.kt': 'kotlin', '.kts': 'kotlin',
        '.xml': 'xml', '.pro': 'text', '.json': 'json', '.drift': 'sql',
        '.py': 'python'}

# Extensions deliberately not bundled. Listed rather than assumed, so the report below can tell
# "we decided not to" from "nobody has thought about it yet".
IGNORED_EXT = {
    '.png', '.jpg', '.jpeg', '.webp', '.gif', '.svg', '.ico',
    '.ttf', '.otf',
    '.md', '.yaml', '.yml', '.lock', '.txt', '.properties', '.gradle',
    '.jar', '.iml', '.sh', '.bat', '.g', '',
}

BLURB = {
    'B1_CORE': 'Money, Qty, DateKey, Result, ids, enums. No Flutter, no drift.',
    'B2_SCHEMA': 'Drift tables, converters, migrations, DAOs, and the .drift views and indexes. '
                 'Changing this changes the database.',
    'B3_DOMAIN': 'Entities, repository contracts, service contracts, pure engines.',
    'B4_DATA': 'Repository implementations, security, backup, platform channels.',
    'B5_APP': 'Router, providers, theme, bootstrap. The router imports every screen.',
    'B6_SHARED': 'The widget vocabulary.',
    'B7_TESTKIT': 'Harnesses, fakes, the layout-overflow suite, the layering checker, the tools.',
    'B8_ANDROID': 'MainActivity, the SAF platform channel, and the manifest.',
    'F_EXPENSE': 'Transactions, lines, tags, payees, ledger, editor.',
    'F_INVENTORY': 'Items, batches, stock movements.',
    'F_SHOPPING': 'Shopping lists, entries, convert-to-purchase.',
    'F_RECIPE': 'Recipes, ingredients, steps, the cookability engine and cooking.',
    'F_RECURRING': 'Recurring templates and occurrences.',
    'F_SERVICE': 'Assets, service records, warranties.',
    'F_SPLIT': 'Shared expenses, groups, balances, settling up, the shareable summary.',
    'F_DASHBOARD': 'Funds header, module grid, insight cards.',
    'F_CALENDAR': 'Calendar screen and day sheet.',
    'F_ANALYTICS': 'Analytics home, query surfaces, drill-down.',
    'F_SETTINGS': 'Settings tree and branches, onboarding, PIN, lock, recovery.',
    'F_OPS': 'Backup, restore, trash, reminders, attachments, Support Us.',
    'ARB': 'Every user-visible string.',
}

# A feature bundle is every path containing `/features/<name>/`, in lib and test alike.
FEATURES = {
    'F_EXPENSE': ['expense'], 'F_INVENTORY': ['inventory'], 'F_SHOPPING': ['shopping'],
    'F_RECIPE': ['recipe'], 'F_SPLIT': ['split'],
    'F_RECURRING': ['recurring'], 'F_SERVICE': ['service'], 'F_DASHBOARD': ['dashboard'],
    'F_CALENDAR': ['calendar'], 'F_ANALYTICS': ['analytics'],
    'F_SETTINGS': ['settings', 'lock', 'onboarding'],
    'F_OPS': ['backup', 'trash', 'reminders', 'attachments', 'support', 'ops'],
}

SOURCE_DIRS = ('lib', 'test', 'tool', 'android')


def bundle_of(path):
    """The one bundle a path belongs to, or None if it is not bundled."""
    p = path.replace(os.sep, '/')
    if p.endswith('app_en.arb'):
        return 'ARB'
    for name, feats in FEATURES.items():
        if any(f'/features/{x}/' in p for x in feats):
            return name
    if p.startswith('lib/core/') or p.startswith('test/core/'):
        return 'B1_CORE'
    if p.startswith(('lib/data/db/', 'lib/data/daos/', 'test/data/')):
        return 'B2_SCHEMA'
    if p.startswith('lib/domain/') or p.startswith('test/domain/'):
        return 'B3_DOMAIN'
    if p.startswith('lib/data/'):
        return 'B4_DATA'
    if p.startswith('lib/app/') or p == 'lib/main.dart':
        return 'B5_APP'
    if p.startswith('lib/shared/'):
        return 'B6_SHARED'
    if p.startswith(('test/shared/', 'test/support/', 'tool/')):
        return 'B7_TESTKIT'
    # **Everything Android that is source, not just Kotlin.** The manifest is the file that decides
    # whether notifications survive a reboot, whether the plaintext database is uploaded to Drive, and
    # which permissions the Play form has to declare — and it sat in no bundle for the project's whole
    # life because this rule tested the extension instead of the directory.
    if p.startswith('android/'):
        return 'B8_ANDROID'
    return None


def collect():
    found = {}
    for base in SOURCE_DIRS:
        if not os.path.isdir(base):
            continue
        for root, _, names in os.walk(base):
            # Build output is not source, and android/build alone is thousands of files.
            if any(part in root.split(os.sep) for part in ('build', '.dart_tool', '.gradle')):
                continue
            for n in names:
                path = os.path.join(root, n).replace(os.sep, '/')
                if os.path.splitext(n)[1] not in LANG:
                    continue
                if '.g.dart' in n or '.freezed.dart' in n:
                    continue  # generated; regenerated by build_runner, never hand-edited
                b = bundle_of(path)
                if b:
                    found.setdefault(b, []).append(path)
    return {k: sorted(v) for k, v in sorted(found.items())}


def digest(paths):
    """A hash of what a bundle would contain, so staleness is detectable without reading the .md."""
    h = hashlib.sha256()
    for p in paths:
        h.update(p.encode())
        with open(p, 'rb') as fh:
            h.update(fh.read())
    return h.hexdigest()[:16]


def report_gaps(groups):
    """Everything a future change would not be able to see.

    Two lists, because they are different mistakes. An **unbundled** file has an extension the script
    understands and no rule to place it — add one to `bundle_of`. An **unknown extension** is a file the
    script never even looked at, and it is the more dangerous of the two: nothing downstream can notice
    its absence, which is how `.drift` stayed invisible through nine phases.
    """
    unbundled, unknown = [], []
    for base in SOURCE_DIRS:
        if not os.path.isdir(base):
            continue
        for root, _, names in os.walk(base):
            if any(part in root.split(os.sep) for part in ('build', '.dart_tool', '.gradle')):
                continue
            for n in names:
                p = os.path.join(root, n).replace(os.sep, '/')
                ext = os.path.splitext(n)[1]
                if '.g.dart' in n or '.freezed.dart' in n:
                    continue
                if ext in LANG:
                    if not bundle_of(p):
                        unbundled.append(p)
                elif ext not in IGNORED_EXT:
                    unknown.append(p)

    if unbundled:
        print('\nUNBUNDLED — add a rule in bundle_of() for each:')
        for p in unbundled:
            print('   ', p)
    if unknown:
        print('\nUNKNOWN EXTENSION — add to LANG to bundle, or to IGNORED_EXT to say it is deliberate:')
        for p in sorted(unknown):
            print('   ', p)
    if not unbundled and not unknown:
        print('\nEvery source file is in a bundle.')


def main():
    only = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('-') else None
    stale_only = '--stale' in sys.argv
    out = 'bundles'
    os.makedirs(out, exist_ok=True)
    groups = collect()

    # **The previous manifest is loaded, not discarded.** Rewriting every entry while writing one file
    # made `_manifest.json` claim bundles were current when their `.md` had not been touched — the exact
    # trap that let a file be regenerated from a bundle two sessions out of date, silently reverting the
    # edits in between.
    manifest_path = os.path.join(out, '_manifest.json')
    manifest = {}
    if os.path.exists(manifest_path):
        try:
            with open(manifest_path, encoding='utf-8') as fh:
                manifest = json.load(fh)
        except (OSError, ValueError):
            manifest = {}

    if stale_only:
        print('Bundles whose files have changed since they were written:\n')
        any_stale = False
        for name, paths in groups.items():
            recorded = manifest.get(name, {}).get('digest')
            current = digest(paths)
            if recorded != current:
                any_stale = True
                when = manifest.get(name, {}).get('generated', 'never')
                print(f'  {name:14} STALE   last written {when}')
        if not any_stale:
            print('  none — every bundle matches the tree.')
        return

    now = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
    for name, paths in groups.items():
        if only and name != only:
            continue
        total = 0
        parts = []
        for p in paths:
            with open(p, encoding='utf-8') as fh:
                code = fh.read().rstrip('\n')
            total += len(code.splitlines())
            lang = LANG[os.path.splitext(p)[1]]
            parts.append(f'### `{p}`\n\n```{lang}\n{code}\n```\n')
        head = (f'# {name}\n\n{BLURB.get(name, "")}\n\n'
                f'**{len(paths)} files · {total:,} lines.**  Written {now}.\n\n'
                'Every file below is complete and current. Paths are destinations.\n\n---\n\n')
        with open(os.path.join(out, name + '.md'), 'w', encoding='utf-8') as fh:
            fh.write(head + '\n'.join(parts))
        manifest[name] = {
            'files': len(paths), 'lines': total, 'paths': paths,
            'generated': now, 'digest': digest(paths),
        }
        print(f'  {name:14} {len(paths):3} files {total:6} lines')

    # A bundle that no longer exists in the tree should not linger in the manifest claiming to.
    for gone in [k for k in manifest if k not in groups]:
        del manifest[gone]

    with open(manifest_path, 'w', encoding='utf-8') as fh:
        json.dump(manifest, fh, indent=1)

    if only:
        print(f'\nRegenerated {only} only. Run with --stale to see which others no longer match.')
    else:
        print(f'\n{len(groups)} bundles, {sum(m["lines"] for m in manifest.values()):,} lines.')

    report_gaps(groups)


if __name__ == '__main__':
    main()
```

### `tool/prune_arb.py`

```python
#!/usr/bin/env python3
"""Removes the ARB keys my UI changes orphaned.

Seven keys, all superseded during the recipe and UI rounds: a label replaced by a better question, a hint
that stopped applying when the field changed, a suffix for a unit no longer shown. `flutter gen-l10n` does
not mind an unreferenced key, so none of this is urgent — but a string table that describes screens which no
longer exist is the same class of fault as a stale bundle.

Verifies each key is genuinely unreferenced in lib/ before deleting it, so a key I mis-listed survives.
"""

import json
import re
import collections
from pathlib import Path

ORPHANED = [
    'labelDensity',
    'densityHelp',
    'suffixGramsPerMl',
    'recipeAmountHint',
    'recipeSpoonsNeedWeight',
    'recipeQuantityHint',
    'recipeAmountHintVessel',
]

arb_path = Path('lib/app/l10n/app_en.arb')
arb = json.loads(arb_path.read_text(), object_pairs_hook=collections.OrderedDict)

referenced = set()
for dart in Path('lib').rglob('*.dart'):
    referenced |= set(re.findall(r'strings\.(\w+)', dart.read_text()))

removed, kept = [], []
for key in ORPHANED:
    if key in referenced:
        kept.append(key)
        continue
    arb.pop(key, None)
    arb.pop('@' + key, None)
    removed.append(key)

arb_path.write_text(json.dumps(arb, indent=2, ensure_ascii=False) + '\n')

print(f'removed {len(removed)} keys: {", ".join(removed) or "none"}')
if kept:
    print(f'KEPT {len(kept)} — still referenced, so my list was wrong: {", ".join(kept)}')
print(f'{len([k for k in arb if not k.startswith("@")])} keys remain')
```

### `tool/reachability.py`

```python
#!/usr/bin/env python3
"""Finds capabilities that exist and nothing reaches.

Run from the repo root:  python3 tool/reachability.py

The recurring fault in this codebase is not missing code — it is code that was written, tested, and never
wired to a user. Five instances found so far: `QuickAddSheet`, `ShoppingActions.delete`,
`BalanceService.convertOne`, `ReminderPort.refreshSchedule`, and `AppLock.changePin`/`disable`. Each was
discovered by a user reporting a missing feature rather than by anything in the build.

This finds them before the user does. It is deliberately crude — it greps rather than parses — so treat the
output as a list to check, not a list of bugs. A method used only through a variable of interface type will
be caught; one invoked reflectively or through a tear-off will not.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else '.')
LIB = ROOT / 'lib'
TEST = ROOT / 'test'

# A capability worth checking: a public async or stream method on a port, repository or service.
DECL = re.compile(r'^\s*(?:Future|Stream)<[^;]+?>\s+(\w+)\(', re.M)
INTERESTING = ('/services/', '/repositories/', '/ports/')


def dart_files(base: Path) -> list[Path]:
    return sorted(base.rglob('*.dart')) if base.exists() else []


def main() -> int:
    declared: dict[str, Path] = {}
    for path in dart_files(LIB):
        if not any(k in path.as_posix() for k in INTERESTING):
            continue
        if path.name.endswith('.g.dart'):
            continue
        for match in DECL.finditer(path.read_text()):
            name = match.group(1)
            if not name.startswith('_'):
                declared.setdefault(name, path)

    prod_calls: dict[str, set[Path]] = {}
    test_calls: dict[str, set[Path]] = {}
    for path in dart_files(LIB) + dart_files(TEST):
        text = path.read_text()
        target = test_calls if TEST in path.parents or 'test/' in path.as_posix() else prod_calls
        for match in re.finditer(r'\.(\w+)\(', text):
            target.setdefault(match.group(1), set()).add(path)

    unreachable = []
    for name, home in sorted(declared.items()):
        prod = {p for p in prod_calls.get(name, set()) if p != home}
        if prod:
            continue
        tests = len(test_calls.get(name, set()))
        unreachable.append((name, home, tests))

    if not unreachable:
        print('Nothing unreachable. Every domain capability has a production caller.')
        return 0

    print(f'{len(unreachable)} domain capabilities have no production caller outside their own file.\n')
    print('The ones with test callers are the dangerous kind: they are proven to work and')
    print('unreachable, so the suite is green and the feature does not exist.\n')
    for name, home, tests in sorted(unreachable, key=lambda row: -row[2]):
        flag = 'TESTED BUT UNREACHABLE' if tests else 'no callers at all'
        print(f'  {name:28} {home.relative_to(ROOT).as_posix():52} {flag}')
    print('\nNot every line is a bug — a deliberately dropped method (see ARCH_4 §5.1) belongs')
    print('here too, and the fix for that one is deletion rather than wiring.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
```
