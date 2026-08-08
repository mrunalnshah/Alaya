import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_parser.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/shared/widgets/unit_picker.dart';

/// A quantity input paired with its unit.
///
/// The number and the unit are one control because a quantity without a unit is meaningless — `2` is
/// not a quantity until you know whether it is kilograms or pieces. Splitting them into two fields
/// lets a user submit a number with the wrong unit still selected.
///
/// Parses through [QtyParser], so no `double` touches a quantity (Law L2) and a value finer than the
/// selected unit can express is reported rather than rounded away.
///
/// Like `AmountField`, it never rewrites what is being typed: [onChanged] receives null while the
/// input is incomplete, and the text is left alone.
class QtyField extends StatefulWidget {
  /// Creates a quantity field.
  const QtyField({
    required this.category,
    required this.units,
    required this.selectedUnit,
    required this.onChanged,
    required this.onUnitChanged,
    this.initialValue,
    this.label,
    this.hint,
    this.errorText,
    this.unitLabel,
    super.key,
  });

  /// The category being measured. Constrains which units are offered (Law L8).
  final UnitCategory category;

  /// The units available in [category].
  final List<Unit> units;

  /// The unit currently chosen.
  final Unit? selectedUnit;

  /// Called with the parsed quantity, or null while the input is not yet a valid one.
  final ValueChanged<Qty?> onChanged;

  /// Called when the user picks a different unit.
  final ValueChanged<Unit> onUnitChanged;

  /// A starting quantity.
  final Qty? initialValue;

  /// The field's label.
  final String? label;

  /// Placeholder text.
  final String? hint;

  /// An error from the caller — a business rule, not a parse failure.
  final String? errorText;

  /// The unit picker's label.
  final String? unitLabel;

  @override
  State<QtyField> createState() => _QtyFieldState();
}

class _QtyFieldState extends State<QtyField> {
  static const QtyParser _parser = QtyParser();

  late final TextEditingController _controller = TextEditingController(
    text: _initialText(),
  );
  ParseFailure? _failure;

  String _initialText() {
    final initial = widget.initialValue;
    final unit = widget.selectedUnit;
    if (initial == null || initial.isZero || unit == null) return '';
    return _parser.format(initial, factorToBaseMilli: unit.factorToBaseMilli);
  }

  /// Re-derives the quantity from [raw].
  ///
  /// [unit] overrides `widget.selectedUnit`, and the unit picker must supply it. The parent has not
  /// rebuilt yet when the picker fires, so `widget.selectedUnit` still holds the *previous* unit —
  /// re-parsing against it stored `10 g` for a field displaying `10 kg`.
  void _handleChanged(String raw, {Unit? unit}) {
    unit ??= widget.selectedUnit;
    if (unit == null || raw.trim().isEmpty) {
      setState(() => _failure = null);
      widget.onChanged(null);
      return;
    }
    final result = _parser.parse(
      raw,
      category: widget.category,
      factorToBaseMilli: unit.factorToBaseMilli,
    );
    setState(() => _failure = result.failureOrNull);
    widget.onChanged(result.valueOrNull);
  }

  /// The parse failures worth showing mid-typing.
  ///
  /// A trailing decimal point is [ParseFailure.malformed] and is also what everyone types on the way
  /// to entering a fraction, so it stays silent — only failures that cannot become valid by typing
  /// more are surfaced. `tooManyDecimalDigits` is one of those and matters most: it is the case the
  /// old `double` path resolved by silently rounding.
  String? _parseMessage(BuildContext context) {
    final failure = _failure;
    if (failure == null) return null;
    final strings = AlayaStrings.of(context);
    return switch (failure) {
      ParseFailure.invalidCharacter => strings.errorQuantityInvalidCharacter,
      ParseFailure.negativeNotAllowed =>
        strings.errorQuantityNegativeNotAllowed,
      ParseFailure.tooManyDecimalDigits => strings.errorQuantityTooPrecise,
      ParseFailure.tooLarge => strings.errorQuantityTooLarge,
      ParseFailure.empty || ParseFailure.malformed => null,
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 3,
        child: TextField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.right,
          style: AlayaTypography.quantity,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            LengthLimitingTextInputFormatter(12),
          ],
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            errorText: widget.errorText ?? _parseMessage(context),
          ),
          onChanged: _handleChanged,
        ),
      ),
      const SizedBox(width: AlayaSpacing.xs),
      Expanded(
        flex: 2,
        child: UnitPicker(
          category: widget.category,
          units: widget.units,
          selected: widget.selectedUnit,
          label: widget.unitLabel,
          onChanged: (unit) {
            widget.onUnitChanged(unit);
            // Re-derive with the new factor: the typed number means something different now,
            // and it may no longer be expressible — 0.5 is half a piece but not half a
            // milligram. The unit is passed explicitly because `widget.selectedUnit` is still the
            // old one until the parent rebuilds.
            _handleChanged(_controller.text, unit: unit);
          },
        ),
      ),
    ],
  );
}
