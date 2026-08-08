import 'package:flutter/widgets.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/money_formatter.dart';

/// How large an amount renders.
enum AmountSize {
  /// The dashboard headline. One per screen.
  display,

  /// A card's primary figure.
  large,

  /// A ledger row. The default.
  medium,

  /// A converted or secondary figure.
  small,
}

/// Renders a [Money] with the app's colour convention and tabular figures.
///
/// **This is the widget the design is built around.** Three things happen here that make a column of
/// amounts readable:
///
/// 1. Tabular figures, from `AlayaTypography`. Digits share one advance width, so values align on the
///    decimal as they change instead of jittering.
/// 2. Colour from [AlayaSemanticColors.forAmount] and nowhere else, so the red/green rule has one
///    definition (ARCH_3 §8.1).
/// 3. **An explicit sign, always.** Colour alone would exclude the roughly eight percent of men with
///    a red-green deficiency; the palettes additionally keep income lighter than expense, but a glyph
///    is the only signal that survives both colour blindness and a greyscale screenshot.
class AmountText extends StatelessWidget {
  /// Creates an amount.
  const AmountText(
    this.amount, {
    this.size = AmountSize.medium,
    this.decimalDigits = 2,
    this.symbol,
    this.kind,
    this.showSign = true,
    this.muted = false,
    this.textAlign,
    super.key,
  });

  /// The amount.
  final Money amount;

  /// How large to render it.
  final AmountSize size;

  /// The currency's minor-unit precision.
  ///
  /// Defaults to 2. The real value lives on the `currencies` row, and a feature screen that has the
  /// currency to hand should pass it — JPY has 0 and rendering `¥1,200.00` is wrong.
  final int decimalDigits;

  /// The currency symbol.
  ///
  /// Defaults to the currency code, which is never wrong even when it is less pretty than `₹`. A
  /// hardcoded symbol would be wrong for every other currency the app supports.
  final String? symbol;

  /// The transaction kind, when known.
  ///
  /// Supplied only to colour a transfer neutrally: a transfer's leg is signed like any other, so
  /// without this it would render as income on the way in and expense on the way out — one movement
  /// of money looking like two different things.
  final TransactionKind? kind;

  /// Whether to render the sign.
  ///
  /// Defaults to true. Set false only where the direction is already unambiguous in the layout — a
  /// column headed "Spent", for instance.
  final bool showSign;

  /// Renders in the muted colour instead of the semantic one, for a disabled or historical row.
  final bool muted;

  /// How to align the text. Amounts in a column should be [TextAlign.right].
  final TextAlign? textAlign;

  static const MoneyFormatter _formatter = MoneyFormatter();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final color = muted
        ? semantic.muted
        : kind == null
        ? semantic.forAmount(amount)
        : semantic.forTransactionKind(kind!, amount);

    return Text(
      _formatter.format(
        amount,
        decimalDigits: decimalDigits,
        symbol: symbol ?? amount.currencyCode,
        showPlusSign: showSign && amount.isPositive,
      ),
      style: _styleFor(size).copyWith(color: color),
      textAlign: textAlign,
      maxLines: 1,
      // An amount is never truncated with an ellipsis: a partly shown number reads as a smaller
      // number. Scaling down is wrong for the same reason, so it clips and the caller gives it room.
      overflow: TextOverflow.clip,
      softWrap: false,
    );
  }

  TextStyle _styleFor(AmountSize size) => switch (size) {
    AmountSize.display => AlayaTypography.displayAmount,
    AmountSize.large => AlayaTypography.amountLarge,
    AmountSize.medium => AlayaTypography.amountMedium,
    AmountSize.small => AlayaTypography.amountSmall,
  };
}
