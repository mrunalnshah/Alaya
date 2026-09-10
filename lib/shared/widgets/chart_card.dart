import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One analytics figure in a card, owning all four of its states (ARCH_5 §7's `ChartCard`).
///
/// **The reason this is shared rather than written per surface is Law U4.** Twenty-four figures each
/// needing loading, empty, error and populated is ninety-six states, and the failure mode ARCH_5 §0
/// names — "a screen that is nearly a screen" — is what happens when the twenty-fourth author is
/// bored. Here they are written once and every surface inherits them.
///
/// **A failing card costs the reader that card and nothing else** (ARCH_5 §3 archetype F). The error
/// branch renders inside the card, so an unreachable rate table blanks one figure rather than the
/// screen.
///
/// This *is* the tier-1 surface, so nothing handed to [builder] may be another [AlayaCard]
/// (ARCH_5 §2.5). Group inside it with space and a `SectionHeader`.
///
/// **A `StatelessWidget` that imports `flutter_riverpod` for `AsyncValue` and nothing else.** It reads
/// no provider and takes no `WidgetRef` — the caller watches, this renders. `shared/tag_picker.dart`
/// already imports the package for the same reason, and Law L12's layering is about `core` → `domain`
/// → `data` → `features`, which a state-management type does not cross.
class ChartCard<T> extends StatelessWidget {
  /// Creates a card for [value], titled [title].
  const ChartCard({
    required this.title,
    required this.value,
    required this.isEmpty,
    required this.emptyMessage,
    required this.builder,
    required this.onRetry,
    this.subtitle,
    this.approximateCount = 0,
    this.unconvertedCount = 0,
    this.onTap,
    this.trailing,
    super.key,
  });

  /// What this figure answers, already localised. Sentence case (ARCH_5 §2.8).
  final String title;

  /// An optional line under the title — the window, the unit, the caveat.
  final String? subtitle;

  /// The figure, consumed with all three branches (Law U4).
  final AsyncValue<T> value;

  /// Whether the loaded figure holds nothing.
  ///
  /// Required rather than inferred: "empty" is different for every result type — an empty slice
  /// list, a zero total, a trend with one point — and a widget guessing at it would show a chart
  /// axis with no data and call that populated.
  final bool Function(T data) isEmpty;

  /// What to say when there is nothing yet. Names the next action where there is one (ARCH_5 §2.8).
  final String emptyMessage;

  /// Renders the populated figure.
  final Widget Function(BuildContext context, T data) builder;

  /// Recomputes this figure. Wired to `ref.invalidate` of the provider behind it.
  final VoidCallback onRetry;

  /// How many of this figure's data points converted only approximately (ARCH_3 §1.3).
  final int approximateCount;

  /// How many could not be converted at all, and are therefore **excluded** from the figure.
  ///
  /// Surfaced rather than hidden, because a total that silently omitted an unconvertible amount
  /// would look complete while under-reporting (anomaly A15, A34).
  final int unconvertedCount;

  /// Opens the drill-down behind this figure.
  final VoidCallback? onTap;

  /// A rendered value beside the title — an `AmountText` carrying the figure's headline.
  final Widget? trailing;

  /// Above this text scale the header stacks instead of sharing a row (Law U21).
  static const double _stackAboveScale = 1.5;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final scale = MediaQuery.textScalerOf(context).scale(1);

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.md),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            title: title,
            subtitle: subtitle,
            trailing: trailing,
            showChevron: onTap != null,
            stacked: scale >= _stackAboveScale,
          ),
          const SizedBox(height: AlayaSpacing.sm),
          value.when(
            // Not a spinner: a card that is about to hold a chart reads as "slow" behind one
            // (ARCH_5 §5.2). A muted line naming what is coming says more and costs no layout.
            loading: () => Text(
              strings.chartLoading,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            // The repository's own message, never a generic body (Law U9). A figure that fails
            // identically for every cause is a bug nobody can find.
            error: (error, stack) => _CardError(
              message: error.toString(),
              retryLabel: strings.actionRetry,
              onRetry: onRetry,
            ),
            // **The builder is never wrapped in a fixed height.** A card sizes to its own content and
            // the screen's `SliverList` scrolls; a chart inside it asks for its own height through
            // `AnalyticsPlotBox`. Bounding the whole builder here squeezed the title and the subtitle of
            // any card that put chrome above its plot.
            data: (data) => isEmpty(data)
                ? Text(
                    emptyMessage,
                    style: AlayaTypography.body.copyWith(color: semantic.muted),
                  )
                : builder(context, data),
          ),
          if (approximateCount > 0 || unconvertedCount > 0) ...[
            const SizedBox(height: AlayaSpacing.sm),
            Wrap(
              spacing: AlayaSpacing.xs,
              runSpacing: AlayaSpacing.xxs,
              children: [
                if (unconvertedCount > 0)
                  StatusChip(
                    label: strings.chartUnconverted(unconvertedCount),
                    tone: StatusTone.warning,
                  ),
                if (approximateCount > 0)
                  StatusChip(
                    label: strings.chartApproximate(approximateCount),
                    tone: StatusTone.info,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The title, its subtitle, and whatever sits opposite them.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.showChevron,
    required this.stacked,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showChevron;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            subtitle!,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],
      ],
    );

    final chevron = showChevron
        ? Padding(
            padding: const EdgeInsets.only(left: AlayaSpacing.xs),
            child: Icon(
              Icons.chevron_right,
              size: AlayaIconSize.md,
              color: semantic.muted,
            ),
          )
        : null;

    // **Stacked above 1.5x, and `Flexible` on the value is not the fix** (Law U21). `trailing` is
    // usually an `AmountText`, which clips rather than ellipsises — so a clipped figure is a wrong
    // figure, and it must be given its own row rather than squeezed. Against a tight `Expanded` the
    // two would split evenly and the *title* would truncate at scale 1 instead.
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: label),
              if (chevron != null) chevron,
            ],
          ),
          if (trailing != null) ...[
            const SizedBox(height: AlayaSpacing.xs),
            Align(alignment: Alignment.centerLeft, child: trailing),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: label),
        if (trailing != null) ...[
          const SizedBox(width: AlayaSpacing.sm),
          trailing!,
        ],
        if (chevron != null) chevron,
      ],
    );
  }
}

/// An inline failure, sized for a card rather than for a screen.
///
/// Not `ErrorState`: that one is a full-height state with a 40px glyph and its own
/// `ScrollSafeCenter`, which inside a card would push every sibling off the screen.
class _CardError extends StatelessWidget {
  const _CardError({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              size: AlayaIconSize.md,
              color: semantic.danger,
            ),
            const SizedBox(width: AlayaSpacing.xs),
            Expanded(
              child: Text(
                message,
                style: AlayaTypography.caption.copyWith(color: semantic.danger),
              ),
            ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onRetry,
            child: Text(retryLabel, style: AlayaTypography.button),
          ),
        ),
      ],
    );
  }
}
