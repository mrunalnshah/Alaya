import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_labels.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/state/analytics_range.dart';

/// The reporting window, as chips.
///
/// **Every range is labelled with what it means** (anomaly A33). "Last month" is ambiguous between
/// the previous calendar month and the preceding thirty days, and no figure on the screen can
/// disambiguate itself — so the chip states the window and `DateRangeService` resolves exactly that.
///
/// Chips rather than a dropdown: six options, one tap each, and the current choice is visible without
/// opening anything (ARCH_5 §3 archetype A's reasoning, which holds wherever a choice is small and
/// frequent).
class AnalyticsRangeRow extends ConsumerWidget {
  /// Creates the row.
  const AnalyticsRangeRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final selected = ref.watch(analyticsRangeProvider);

    // A `Wrap`, not a horizontal scroller: a scroller needs a fixed height and a fixed height
    // overflows the moment the text scale is raised (Law U15). Six chips wrap to two rows at 2x and
    // stay reachable.
    return Semantics(
      label: strings.analyticsRangeLabel,
      child: Wrap(
        spacing: AlayaSpacing.xs,
        runSpacing: AlayaSpacing.xs,
        children: [
          for (final preset in AnalyticsRange.presets)
            ChoiceChip(
              label: Text(
                AnalyticsLabels.range(strings, preset),
                style: AlayaTypography.button,
              ),
              selected: preset == selected,
              onSelected: (_) =>
                  ref.read(analyticsRangeProvider.notifier).show(preset),
            ),
        ],
      ),
    );
  }
}
