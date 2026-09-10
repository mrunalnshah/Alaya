import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/measure.dart';
import 'package:alaya/core/quantity/measure_formatter.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Renders a [Measure] in a named unit, and is the only path from one to pixels.
///
/// **A sibling of [QtyText] rather than a parameter on it, and the split is deliberate.** `QtyText` is
/// consumed by six features and derives its own unit from the category — `4 kg 450 g`, `3 pc` — because a
/// stored quantity is unit-free and the best presentation of it is a property of the number. Adding an
/// optional `unit` would have put a concern belonging to three recipe screens into a widget every screen
/// uses, and given `QtyText` two modes that need explaining to every reader of every call site.
///
/// **The unit's `code` is the label, not its `displayName`.** `1 1/2 tbsp` is how a recipe is written;
/// `1 1/2 Tablespoon` is how a database is written. The code is already the abbreviation cooks use, which
/// also side-steps pluralisation — there is no `displayNamePlural` column and "1 1/2 tablespoon" would
/// need one.
///
/// **`≈` when the amount was snapped, and never otherwise.** [MeasureStyle.kitchen] rounds to what a
/// measuring set can produce, so the text can stop being the stored value — and a row that showed a
/// snapped figure as though it were exact would be asserting something false. The glyph is the whole cost
/// of not doing that, and `RenderedMeasure.isApproximate` decides when it appears, so at a recipe's own
/// serving count nothing is marked anywhere.
class MeasureText extends StatelessWidget {
  /// Renders [measure] in [unit].
  const MeasureText(
    this.measure, {
    required this.unit,
    this.style = MeasureStyle.exact,
    this.muted = false,
    this.textStyle,
    this.textAlign,
    super.key,
  });

  /// The amount, in thousandths of [unit].
  final Measure measure;

  /// The unit to render in. Its `code` becomes the label and its factor is not needed here — [measure] is
  /// already expressed in this unit.
  final Unit unit;

  /// Whether to render what the amount is, or what a cook should reach for.
  final MeasureStyle style;

  /// Renders in the muted colour, for a secondary row.
  final bool muted;

  /// Overrides the default [AlayaTypography.quantity].
  final TextStyle? textStyle;

  /// How to align the text.
  final TextAlign? textAlign;

  static const MeasureFormatter _formatter = MeasureFormatter();

  /// The approximation mark. A mathematical symbol rather than copy, like the decimal separator — it
  /// carries no language and is not translated. The sentence explaining it is an ARB string; this is not.
  static const String _approximately = '\u2248';

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final rendered = _formatter.format(
      measure,
      style: style,
      localeTag: Localizations.localeOf(context).toString(),
    );
    final prefix = rendered.isApproximate ? '$_approximately ' : '';

    return Text(
      '$prefix${rendered.text} ${unit.code}',
      style: (textStyle ?? AlayaTypography.quantity).copyWith(
        color: muted ? semantic.muted : null,
      ),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
