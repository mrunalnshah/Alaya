import 'package:flutter/widgets.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';

/// Renders a [Qty] through [QtyFormatter].
///
/// **Never `Qty.toString()`.** That is a debug representation — it prints milli-base units and the
/// category name, which would put `2000000 milli weight` in front of a user instead of `2 kg`. The
/// formatter is the only path to a displayable quantity.
class QtyText extends StatelessWidget {
  /// Creates a quantity.
  const QtyText(
    this.quantity, {
    this.style = UnitStyle.mixed,
    this.muted = false,
    this.textStyle,
    this.textAlign,
    super.key,
  });

  /// The quantity.
  final Qty quantity;

  /// Which unit presentation to use — [UnitStyle.mixed] decomposes `4 kg 450 g`.
  final UnitStyle style;

  /// Renders in the muted colour, for a depleted batch or a disabled row.
  final bool muted;

  /// Overrides the default [AlayaTypography.quantity].
  final TextStyle? textStyle;

  /// How to align the text.
  final TextAlign? textAlign;

  static const QtyFormatter _formatter = QtyFormatter();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Text(
      _formatter.format(quantity, style: style),
      style: (textStyle ?? AlayaTypography.quantity).copyWith(
        // Not `forAmount`: a quantity has no financial direction, so a negative one is a correction
        // rather than an expense and colouring it red would assert something false.
        color: muted ? semantic.muted : null,
      ),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
    );
  }
}
