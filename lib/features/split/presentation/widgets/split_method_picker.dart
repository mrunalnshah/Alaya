import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/split_enums.dart';

/// How a bill divides: equally, by shares, by percentage, or exact amounts.
///
/// ## Why this is not a `SegmentedButton`
///
/// It was one, with four segments. At the 320dp gate that is **eighty pixels each**, and a segmented
/// button cannot wrap — its children get an equal slice of whatever width there is and clip. "By
/// percentage" at a doubled text scale had nowhere to go, so the control was unreadable exactly for the
/// users Law U15 exists to protect.
///
/// Chips in a `Wrap` reflow to two lines and then three, each staying legible. One tap either way, and the
/// row grows downward instead of squeezing sideways.
///
/// ## And it says what the choice means
///
/// A caption under the chips explains the selected method in a sentence. "By shares" is not
/// self-explanatory — it is the 2:1:1 case, and somebody who has not met it before will otherwise tap all
/// four to find out which one they wanted. The four labels were doing two jobs and only managing one.
class SplitMethodPicker extends StatelessWidget {
  /// Creates the picker.
  const SplitMethodPicker({
    required this.method,
    required this.onChanged,
    super.key,
  });

  /// The method in force.
  final SplitMethod method;

  /// Called with the newly chosen method.
  final ValueChanged<SplitMethod> onChanged;

  /// The methods this control offers.
  ///
  /// **[SplitMethod.perLine] is excluded and that is not an oversight.** An itemised split comes from a
  /// receipt's lines, which this screen does not have — the expense editor does. Offering it here would be
  /// a chip that cannot work, and the resolver would refuse it.
  static const List<SplitMethod> offered = [
    SplitMethod.equal,
    SplitMethod.shares,
    SplitMethod.percent,
    SplitMethod.exactAmounts,
  ];

  static String _label(
    AlayaStrings strings,
    SplitMethod method,
  ) => switch (method) {
    SplitMethod.equal => strings.splitMethodEqual,
    SplitMethod.shares => strings.splitMethodShares,
    SplitMethod.percent => strings.splitMethodPercent,
    SplitMethod.exactAmounts => strings.splitMethodExact,
    // Named rather than defaulted, so adding a method fails to compile here instead of silently
    // borrowing another one's label (Law L13).
    SplitMethod.perLine => strings.splitMethodPerLine,
  };

  static String _explains(AlayaStrings strings, SplitMethod method) =>
      switch (method) {
        SplitMethod.equal => strings.splitMethodEqualHelp,
        SplitMethod.shares => strings.splitMethodSharesHelp,
        SplitMethod.percent => strings.splitMethodPercentHelp,
        SplitMethod.exactAmounts => strings.splitMethodExactHelp,
        SplitMethod.perLine => strings.splitMethodPerLineHelp,
      };

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.splitMethodTitle,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final option in offered)
              ChoiceChip(
                label: Text(_label(strings, option)),
                selected: option == method,
                onSelected: (_) => onChanged(option),
              ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          // The sentence the four labels could not carry. Shown for the selected one only — four
          // explanations at once is a paragraph nobody reads.
          _explains(strings, method),
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
      ],
    );
  }
}
