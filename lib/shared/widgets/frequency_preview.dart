import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/shared/widgets/date_text.dart';

/// One date a schedule will land on, and whether the anchor had to shorten to reach it.
class PreviewedDate {
  /// Creates a previewed date.
  const PreviewedDate({required this.dateKey, this.clamped = false});

  /// When it lands.
  final DateKey dateKey;

  /// Whether the anchor day exceeded this month and was pulled back to its last day.
  final bool clamped;
}

/// Shows where a schedule actually lands (ARCH_5 §8 — the one shared addition Phase 6D makes).
///
/// **This is the only way a user can tell a clamp is doing what they meant.** A bill anchored on the
/// 31st shows Jan 31, Feb 28, Mar 31 — and the February row says it was shortened. Without that, a
/// user who typed 31 and saw 28 would reasonably conclude the app lost their input, and the
/// alternative designs are worse: refusing days above 28 makes the 31st unexpressible, and silently
/// storing 28 walks the anchor backwards forever (anomaly A13).
///
/// The dates are computed by the caller from `RecurringEngine.nextDue`, not here. This widget renders;
/// duplicating the arithmetic would give the preview and the materialiser two answers.
class FrequencyPreview extends StatelessWidget {
  /// Creates the preview.
  const FrequencyPreview({required this.dates, super.key});

  /// The next few dates, soonest first. Empty renders a prompt rather than nothing.
  final List<PreviewedDate> dates;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Container(
      padding: const EdgeInsets.all(AlayaSpacing.sm),
      decoration: BoxDecoration(
        color: semantic.surfaceSunken,
        borderRadius: AlayaRadii.borderMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.event_repeat,
                size: AlayaIconSize.sm,
                color: semantic.muted,
              ),
              const SizedBox(width: AlayaSpacing.xxs),
              Expanded(
                child: Text(
                  strings.previewTitle,
                  style: AlayaTypography.label.copyWith(color: semantic.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: AlayaSpacing.xs),
          if (dates.isEmpty)
            Text(
              strings.previewEmpty,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            )
          else
            for (final date in dates)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
                // A `Wrap`: the date and the clamp note both grow with text scale, and a `Row` would
                // starve one of them at 320dp (Law U21).
                child: Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DateText(date.dateKey, style: DateTextStyle.full),
                    if (date.clamped)
                      Text(
                        strings.previewClamped,
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.warning,
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
