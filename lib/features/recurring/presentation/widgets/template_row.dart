import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One recurring template: what it is, what it costs, and when it next lands.
///
/// **Overdue is derived, never stored.** `RecurringOccurrence.isOverdue(today)` is asked on every
/// build, because a stored flag is wrong the moment midnight passes with the app closed
/// (ARCH_2 §12.2).
///
/// **An inflow is not a negative outflow.** The amount is rendered unsigned with the direction carried
/// by wording and colour, so a salary reads as income rather than as a bill for minus twelve thousand
/// — the §7.2 row this row exists to close.
class TemplateRowTile extends StatelessWidget {
  /// Creates the row.
  const TemplateRowTile({
    required this.template,
    required this.next,
    required this.today,
    required this.decimalDigits,
    required this.onTap,
    this.onPay,
    this.onTogglePause,
    super.key,
  });

  /// The template.
  final RecurringTemplate template;

  /// Its soonest outstanding occurrence, or null when nothing is materialised.
  final RecurringOccurrence? next;

  /// Today, for the overdue derivation.
  final DateKey today;

  /// The currency's precision.
  final int decimalDigits;

  /// Opens the occurrence history.
  final VoidCallback onTap;

  /// Opens the pay sheet for [next].
  final VoidCallback? onPay;

  /// Pauses or resumes the template.
  final VoidCallback? onTogglePause;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final occurrence = next;
    final overdue = occurrence != null && occurrence.isOverdue(today);
    final dueToday = occurrence != null && occurrence.dueDateKey == today;

    // Collected before the tree so the tier can be omitted entirely when there is nothing unusual to
    // say, rather than rendering an empty row of padding.
    final chips = <Widget>[
      if (overdue)
        StatusChip(label: strings.recurringOverdue, tone: StatusTone.danger)
      else if (dueToday)
        StatusChip(label: strings.recurringDueToday, tone: StatusTone.warning),
      if (occurrence == null && !template.isPaused)
        StatusChip(label: strings.recurringNotYetDue),
      if (template.isPaused) StatusChip(label: strings.recurringPaused),
    ];

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
            vertical: AlayaSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    template.direction == RecurringDirection.inflow
                        ? Icons.south_west
                        : Icons.north_east,
                    size: AlayaIconSize.lg,
                    color: template.isPaused
                        ? semantic.muted
                        : template.direction == RecurringDirection.inflow
                        ? semantic.success
                        : semantic.muted,
                  ),
                  const SizedBox(width: AlayaSpacing.sm),
                  Expanded(
                    child: Text(
                      template.name,
                      style: AlayaTypography.body.copyWith(
                        color: template.isPaused
                            ? semantic.muted
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AlayaSpacing.xxs),
              // **Three tiers, not one line.** Everything below the name used to sit in a single
              // `Wrap`, so the amount, the due date, three possible chips and two buttons reflowed
              // into each other and nothing read as more important than anything else. Split by
              // role: the figure, then when it lands, then what is unusual about it, then what you
              // can do. Each tier wraps internally, so 320dp at a doubled scale still reflows
              // rather than overflowing (Law U21).
              Padding(
                padding: const EdgeInsets.only(
                  left: AlayaIconSize.lg + AlayaSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The figure, at full size. It is the thing a glance is looking for.
                    AmountText(
                      template.defaultAmount,
                      showSign: false,
                      decimalDigits: decimalDigits,
                      muted: template.isPaused,
                    ),
                    const SizedBox(height: AlayaSpacing.xxs),
                    // When it lands. Shown whether or not an occurrence exists yet: materialisation
                    // only reaches today, so a bill paid this month has nothing outstanding until
                    // next month, and an empty space where the Record button was reads as a broken
                    // screen rather than as "nothing to do".
                    Wrap(
                      spacing: AlayaSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          strings.recurringNextDue,
                          style: AlayaTypography.caption.copyWith(
                            color: semantic.muted,
                          ),
                        ),
                        DateText(
                          occurrence?.dueDateKey ?? template.nextDueDateKey,
                          style: DateTextStyle.medium,
                          muted: true,
                        ),
                      ],
                    ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      Wrap(
                        spacing: AlayaSpacing.xs,
                        runSpacing: AlayaSpacing.xxs,
                        children: chips,
                      ),
                    ],
                    if (onPay != null || onTogglePause != null) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      // Actions last and on their own line, so a destructive-feeling Pause is never
                      // adjacent to the figure it would suspend.
                      Wrap(
                        spacing: AlayaSpacing.xs,
                        runSpacing: AlayaSpacing.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (onPay != null)
                            FilledButton.tonal(
                              onPressed: onPay,
                              child: Text(strings.payCommit),
                            ),
                          if (onTogglePause != null)
                            TextButton(
                              onPressed: onTogglePause,
                              child: Text(
                                template.isPaused
                                    ? strings.actionResume
                                    : strings.actionPause,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
