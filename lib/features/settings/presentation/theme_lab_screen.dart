import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/app.dart';
import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_elevation.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/loading_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Every token, component and semantic colour on one page, light and dark side by side (ARCH_3 §8.2).
///
/// **This is how palettes actually get chosen.** The alternative is navigating the real app hunting for
/// a screen that happens to use `warning`, discovering it only renders in one state, and guessing about
/// the rest. Everything enumerates from the token maps rather than a hand-written list, so a token
/// added later appears here without anyone remembering to add it.
///
/// Debug-only. In a release build it renders a single line saying so rather than the lab, which keeps
/// it out of the shipped UI without a conditional route that could be got wrong.
class ThemeLabScreen extends ConsumerWidget {
  /// Creates the lab.
  const ThemeLabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    if (!kDebugMode) {
      return Center(child: Text(strings.themeLabTitle));
    }

    final palette = ref.watch(activePaletteProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AlayaSpacing.screenEdge,
            AlayaSpacing.md,
            AlayaSpacing.screenEdge,
            0,
          ),
          child: Text(
            strings.themeLabSubtitle,
            style: AlayaTypography.body.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SectionHeader(label: strings.themeLabSectionPalettes),
        _PalettePicker(
          current: palette,
          // **Phase 8A: `use`, not `state =`.** `activePaletteProvider` became a persisted `Notifier` when
          // ARCH_4 §5.1 item 23 was closed, and assigning `state` directly would retheme this session while
          // never reaching `app_settings` — the exact bug item 23 was about, moved one screen along.
          onSelected: (next) =>
              ref.read(activePaletteProvider.notifier).use(next),
        ),
        SectionHeader(label: strings.themeLabSectionSemantic),
        _SideBySide(
          palette: palette,
          builder: (context) => const _SemanticSwatches(),
        ),
        SectionHeader(label: strings.themeLabSectionSurfaces),
        _SideBySide(
          palette: palette,
          builder: (context) => const _SurfaceTiers(),
        ),
        SectionHeader(label: strings.themeLabSectionTypography),
        const _TypeScale(),
        SectionHeader(label: strings.themeLabSectionSpacing),
        const _SpacingScale(),
        SectionHeader(label: strings.themeLabSectionRadii),
        const _RadiiScale(),
        SectionHeader(label: strings.themeLabSectionElevation),
        _SideBySide(
          palette: palette,
          builder: (context) => const _ElevationScale(),
        ),
        SectionHeader(label: strings.themeLabSectionComponents),
        _SideBySide(
          palette: palette,
          builder: (context) => const _Components(),
        ),
      ],
    );
  }
}

/// Renders [builder] twice, in light and dark, so a palette is judged as a pair.
class _SideBySide extends StatelessWidget {
  const _SideBySide({required this.palette, required this.builder});

  final AlayaPalette palette;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Pane(
              label: strings.themeLabLight,
              theme: AlayaTheme.light(palette),
              child: builder(context),
            ),
          ),
          const SizedBox(width: AlayaSpacing.sm),
          Expanded(
            child: _Pane(
              label: strings.themeLabDark,
              theme: AlayaTheme.dark(palette),
              child: builder(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.label, required this.theme, required this.child});

  final String label;
  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AlayaTypography.overline),
      const SizedBox(height: AlayaSpacing.xxs),
      Theme(
        data: theme,
        child: Builder(
          builder: (context) => DecoratedBox(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: AlayaRadii.borderSm,
              border: Border.all(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AlayaSpacing.sm),
              child: child,
            ),
          ),
        ),
      ),
    ],
  );
}

class _PalettePicker extends StatelessWidget {
  const _PalettePicker({required this.current, required this.onSelected});

  final AlayaPalette current;
  final ValueChanged<AlayaPalette> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final preset in AlayaPresets.all)
          Padding(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
            child: AlayaCard(
              tier: preset.name == current.name ? 2 : 1,
              border: preset.name == current.name,
              onTap: () => onSelected(preset),
              child: Row(
                children: [
                  for (final swatch in [
                    preset.light.primary,
                    preset.light.accent,
                    preset.dark.surfaceBase,
                    preset.light.income,
                    preset.light.expense,
                  ]) ...[
                    _Swatch(color: swatch),
                    const SizedBox(width: AlayaSpacing.xxs),
                  ],
                  const SizedBox(width: AlayaSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(preset.name, style: AlayaTypography.cardTitle),
                        Text(
                          preset.description,
                          style: AlayaTypography.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: AlayaSpacing.lg,
    height: AlayaSpacing.lg,
    decoration: BoxDecoration(color: color, borderRadius: AlayaRadii.borderXs),
  );
}

class _SemanticSwatches extends StatelessWidget {
  const _SemanticSwatches();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in semantic.byName.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
            child: Row(
              children: [
                _Swatch(color: entry.value),
                const SizedBox(width: AlayaSpacing.xs),
                Expanded(
                  child: Text(entry.key, style: AlayaTypography.caption),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SurfaceTiers extends StatelessWidget {
  const _SurfaceTiers();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final tier in [-1, 0, 1, 2])
        Padding(
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
          child: AlayaCard(
            tier: tier,
            border: true,
            padding: const EdgeInsets.all(AlayaSpacing.xs),
            child: Text('tier $tier', style: AlayaTypography.caption),
          ),
        ),
    ],
  );
}

class _TypeScale extends StatelessWidget {
  const _TypeScale();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in AlayaTypography.all.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.key, style: AlayaTypography.overline),
                // 1,234,567.89 rather than lorem: the figures are what the tabular treatment is
                // for, and a pangram would hide the thing being judged.
                Text('1,234,567.89 Alaya', style: entry.value),
              ],
            ),
          ),
      ],
    ),
  );
}

class _SpacingScale extends StatelessWidget {
  const _SpacingScale();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    const steps = {
      'xxs 4': AlayaSpacing.xxs,
      'xs 8': AlayaSpacing.xs,
      'sm 12': AlayaSpacing.sm,
      'md 16': AlayaSpacing.md,
      'lg 20': AlayaSpacing.lg,
      'xl 24': AlayaSpacing.xl,
      'xxl 32': AlayaSpacing.xxl,
      'xxxl 48': AlayaSpacing.xxxl,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in steps.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(entry.key, style: AlayaTypography.caption),
                  ),
                  Container(
                    width: entry.value,
                    height: AlayaSpacing.sm,
                    color: semantic.transfer,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RadiiScale extends StatelessWidget {
  const _RadiiScale();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    const steps = {
      'xs 4': AlayaRadii.xs,
      'sm 8': AlayaRadii.sm,
      'md 12': AlayaRadii.md,
      'lg 20': AlayaRadii.lg,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Row(
        children: [
          for (final entry in steps.entries)
            Padding(
              padding: const EdgeInsets.only(right: AlayaSpacing.xs),
              child: Column(
                children: [
                  Container(
                    width: AlayaSpacing.xxl,
                    height: AlayaSpacing.xxl,
                    decoration: BoxDecoration(
                      color: semantic.transfer,
                      borderRadius: BorderRadius.circular(entry.value),
                    ),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  Text(entry.key, style: AlayaTypography.overline),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ElevationScale extends StatelessWidget {
  const _ElevationScale();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadows = {
      'raised': AlayaElevation.raised(isDark: isDark),
      'floating': AlayaElevation.floating(isDark: isDark),
      'overlay': AlayaElevation.overlay(isDark: isDark),
    };
    return Column(
      children: [
        for (final entry in shadows.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.sm),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.semantic.surfaceRaised,
                borderRadius: AlayaRadii.borderMd,
                boxShadow: entry.value,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AlayaSpacing.xs),
                child: Text(entry.key, style: AlayaTypography.caption),
              ),
            ),
          ),
      ],
    );
  }
}

class _Components extends StatelessWidget {
  const _Components();

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final tag = Tag(
      id: 'demo',
      name: 'groceries',
      normalizedName: 'groceries',
      allowedScopes: const {TagScope.withdrawal},
      isSystem: false,
      sortOrder: 0,
      isDeleted: false,
      colorArgb: 0xFF2E7D5B,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AmountText(Money(-125050, 'INR'), size: AmountSize.large),
        const AmountText(Money(250000, 'INR')),
        const AmountText(
          Money(500000, 'INR'),
          kind: TransactionKind.transfer,
          size: AmountSize.small,
        ),
        const SizedBox(height: AlayaSpacing.xs),
        const QtyText(Qty(4450000, UnitCategory.weight)),
        const QtyText(Qty(3000, UnitCategory.count)),
        const SizedBox(height: AlayaSpacing.xs),
        Wrap(
          spacing: AlayaSpacing.xxs,
          children: [
            TagChip(tag: tag, onTap: () {}),
            TagChip(tag: tag, selected: true, onTap: () {}),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xs),
        FilledButton(onPressed: () {}, child: Text(strings.actionSave)),
        const SizedBox(height: AlayaSpacing.xxs),
        OutlinedButton(onPressed: () {}, child: Text(strings.actionCancel)),
        const SizedBox(height: AlayaSpacing.xxs),
        TextButton(onPressed: () {}, child: Text(strings.actionUndo)),
        const SizedBox(height: AlayaSpacing.xs),
        TextField(decoration: InputDecoration(labelText: strings.labelAmount)),
        const SizedBox(height: AlayaSpacing.xs),
        SizedBox(
          height: 150,
          child: EmptyState(
            title: strings.emptyTitleNoResults,
            body: strings.emptyBodyNoResults,
            icon: Icons.search_off_outlined,
          ),
        ),
        SizedBox(height: 120, child: LoadingState(label: strings.loadingLabel)),
        SizedBox(
          height: 170,
          child: ErrorState(
            title: strings.errorTitleGeneric,
            body: strings.errorBodyGeneric,
            retryLabel: strings.actionRetry,
            onRetry: () {},
          ),
        ),
        Text(
          '${AlayaDurations.fast.inMilliseconds} / ${AlayaDurations.base.inMilliseconds} / '
          // `page` was deleted in Phase 9: `FadeForwardsPageTransitionsBuilder` carries its own timing, so the
          // token documented a value nothing read (ARCH_4 §5.1 item 22).
          '${AlayaDurations.slow.inMilliseconds} ms',
          style: AlayaTypography.caption,
        ),
      ],
    );
  }
}
