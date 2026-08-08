import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/money_parser.dart';
import 'package:alaya/core/result/failure.dart';

/// A money input backed by [MoneyParser].
///
/// **It never rejects an intermediate typing state.** Typing `1`, then `1.`, then `1.2` passes through
/// three inputs of which only two parse — and the field rewrites the text in none of them. A field
/// that "corrects" as you type is unusable: deleting a digit to fix a typo momentarily produces
/// something unparseable, and a field that reformats at that instant moves the cursor and eats the
/// next keystroke.
///
/// So parsing drives [onChanged] and the error text only, never the controller's value.
/// [onChanged] receives null while the input is not yet a valid amount, which is the signal a Save
/// button should disable on — distinct from a zero amount, which is valid input the caller may still
/// choose to reject.
class AmountField extends StatefulWidget {
  /// Creates an amount field.
  const AmountField({
    required this.currencyCode,
    required this.onChanged,
    this.decimalDigits = 2,
    this.initialValue,
    this.label,
    this.hint,
    this.errorText,
    this.allowNegative = false,
    this.autofocus = false,
    this.controller,
    super.key,
  });

  /// The currency the typed number is denominated in.
  final String currencyCode;

  /// Called on every keystroke with the parsed amount, or null while it does not parse.
  final ValueChanged<Money?> onChanged;

  /// The currency's minor-unit precision. JPY is 0.
  final int decimalDigits;

  /// A starting amount, rendered as plain digits so it is immediately editable.
  final Money? initialValue;

  /// The field's label, already localised.
  final String? label;

  /// Placeholder text, already localised.
  final String? hint;

  /// An error from the caller — a business rule, not a parse failure.
  ///
  /// Takes precedence over the internal parse message, because "you have insufficient balance" is more
  /// useful than "enter an amount" when both are true.
  final String? errorText;

  /// Whether a leading minus is accepted.
  final bool allowNegative;

  /// Whether to focus on mount.
  final bool autofocus;

  /// An external controller, when the caller needs to clear or preset the text.
  final TextEditingController? controller;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  static const MoneyParser _parser = MoneyParser();

  late final TextEditingController _controller =
      widget.controller ?? TextEditingController(text: _initialText());
  ParseFailure? _failure;

  String _initialText() {
    final initial = widget.initialValue;
    if (initial == null || initial.isZero) return '';
    // Plain digits with a decimal point, not a formatted string: grouping separators in an editable
    // field fight the cursor, and the parser accepts either so there is nothing to gain.
    //
    // Split into a sign and a magnitude rather than dividing the signed minor value: `~/` truncates
    // toward zero, so -50 minor over a divisor of 100 gives a whole part of 0 and the minus sign
    // disappears — a -0.50 opening balance would load as 0.50.
    final divisor = _pow10(widget.decimalDigits);
    final sign = initial.isNegative ? '-' : '';
    final magnitude = initial.minor.abs();
    final whole = magnitude ~/ divisor;
    if (widget.decimalDigits == 0) return '$sign$whole';
    final fraction = (magnitude % divisor).toString().padLeft(
      widget.decimalDigits,
      '0',
    );
    return '$sign$whole.$fraction';
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  void _handleChanged(String raw) {
    if (raw.trim().isEmpty) {
      setState(() => _failure = null);
      widget.onChanged(null);
      return;
    }
    final result = _parser.parse(
      raw,
      currencyCode: widget.currencyCode,
      decimalDigits: widget.decimalDigits,
      allowNegative: widget.allowNegative,
    );
    setState(() => _failure = result.failureOrNull);
    widget.onChanged(result.valueOrNull);
  }

  /// The parse failures worth showing mid-typing.
  ///
  /// A trailing decimal point is [ParseFailure.malformed] but is also what every user types on the way
  /// to entering paise — so it stays silent. Only failures that cannot become valid by typing more are
  /// surfaced.
  String? _parseMessage(BuildContext context) {
    final failure = _failure;
    if (failure == null) return null;
    final strings = AlayaStrings.of(context);
    return switch (failure) {
      ParseFailure.invalidCharacter => strings.errorAmountInvalidCharacter,
      ParseFailure.negativeNotAllowed => strings.errorAmountNegativeNotAllowed,
      ParseFailure.tooManyDecimalDigits => strings.errorAmountTooManyDecimals,
      ParseFailure.tooLarge => strings.errorAmountTooLarge,
      ParseFailure.empty || ParseFailure.malformed => null,
    };
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    autofocus: widget.autofocus,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textAlign: TextAlign.right,
    style: AlayaTypography.amountLarge,
    inputFormatters: [
      // Filters at the keystroke rather than validating after: a letter in a numeric field is
      // never intentional, and blocking it is not the same as rejecting an incomplete number.
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-\u0020]')),
      LengthLimitingTextInputFormatter(24),
    ],
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      errorText: widget.errorText ?? _parseMessage(context),
      prefixText: widget.currencyCode,
    ),
    onChanged: _handleChanged,
  );
}
