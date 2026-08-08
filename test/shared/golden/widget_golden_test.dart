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
