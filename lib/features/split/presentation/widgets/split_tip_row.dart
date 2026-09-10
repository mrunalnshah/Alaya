import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/shared/widgets/amount_text.dart';

/// A tip or service charge on top of the bill.
///
/// ## Any percentage, not four of them
///
/// The first version offered 5, 10, 15 and round-up, which covers a lot of restaurants and none of the
/// other reasons somebody adds to a bill. **1% happens** — a card surcharge, a small service charge, a
/// rounding the table agreed to — and a fixed row of chips makes an ordinary number unreachable.
///
/// So the chips stay for the common cases and a **Custom** chip reveals a field. The two are one value,
/// not two that agree by habit: choosing 10% writes 1000 basis points, and the field edits the same
/// number, so a chip and a field cannot disagree.
///
/// **Basis points, not percent, and that is what makes fractions expressible.** 12.5% is 1250 with no
/// rounding anywhere; a percent-typed field would have had to store 12 or 13.
///
/// ## Round-up is not a percentage and does not pretend to be
///
/// It answers *"make it a round number"*, which no percentage expresses — ₹4,730 to ₹4,800 is 1.48%, and
/// nobody thinks in those terms at a counter. It is a separate flag, applied after the tip, so "10% and
/// then make it round" is one state rather than a choice between two.
class SplitTipRow extends StatefulWidget {
  /// Creates the row.
  const SplitTipRow({
    required this.base,
    required this.basisPoints,
    required this.roundUp,
    required this.decimalDigits,
    required this.onTip,
    required this.onRoundUp,
    super.key,
  });

  /// The bill before any tip, or null while nothing has been typed.
  final Money? base;

  /// The tip as a fraction of the bill, in basis points. 1000 is 10%.
  final int basisPoints;

  /// Whether the total is rounded up to a whole major unit afterwards.
  final bool roundUp;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  /// Called with a new tip in basis points.
  final ValueChanged<int> onTip;

  /// Called when the round-up flag changes.
  final ValueChanged<bool> onRoundUp;

  /// The percentages offered as chips.
  ///
  /// A shortcut list rather than a product decision: any number is reachable through **Custom**, and
  /// these three are the ones worth one tap.
  static const List<int> presetPercents = [5, 10, 15];

  /// The largest tip accepted, in basis points.
  ///
  /// A tip larger than the bill is a typo far more often than an intention, and a field that accepts
  /// 1000% turns a slipped keypress into a balance nobody can explain.
  static const int maxBasisPoints = 10000;

  /// The tip [basisPoints] produces on [base].
  ///
  /// **Floor, and that is the honest direction.** A tip is a number somebody says out loud — "ten
  /// percent" — so rounding it up to make the arithmetic prettier charges the table for a decision nobody
  /// made. The stray paise show up in the total, where they are visible.
  ///
  /// Public and static because it is pure arithmetic with no widget in it, which is what lets the visuals
  /// test assert 5%, 10% and 15% without pumping a frame.
  static Money tipOn(Money base, int basisPoints) =>
      Money(base.minor * basisPoints ~/ 10000, base.currencyCode);

  /// The granularity a round-up reaches for, in minor units.
  ///
  /// **Ten major units — ₹10, not ₹1.** Rounding ₹4,730 to ₹4,731 is not a round-up; nobody at a counter
  /// means that. Ten is the step people actually reach for, and it is what makes the chip's promise true.
  ///
  /// **Derived from [decimalDigits] rather than hardcoded**, because JPY has none: a literal 1000 would
  /// make "round up" mean ¥1,000 in Tokyo and ₹10 in Ahmedabad, and only one of those is what the chip
  /// says. Ten of whatever the currency counts in.
  static int stepFor(int decimalDigits) => 10 * _pow10(decimalDigits);

  /// What actually gets divided: [base], plus the tip, rounded up if asked.
  ///
  /// **Static, because the screen owns the number and this widget only edits it.** The bill and the
  /// figure being split are held apart so the chips stay reversible — adding 10% and clearing it must
  /// return the original bill, which is impossible once the two have been merged.
  ///
  /// **Floor on the tip, ceiling on the round-up**, and each is the honest direction for what it means.
  /// A tip is a number somebody says out loud, so rounding it up charges the table for a decision nobody
  /// made; a round-up is a request to reach the next whole unit, so it can only go up.
  static Money? totalFor({
    required Money? base,
    required int basisPoints,
    required bool roundUp,
    required int decimalDigits,
  }) {
    if (base == null) return null;
    // Through `tipOn` and `stepFor` rather than inlining both: two copies of the same arithmetic is how a
    // widget and its test come to disagree about what 12.5% means.
    final tipped = base.minor + tipOn(base, basisPoints).minor;
    if (!roundUp) return Money(tipped, base.currencyCode);
    final unit = stepFor(decimalDigits);
    final remainder = tipped % unit;
    return Money(
      remainder == 0 ? tipped : tipped + (unit - remainder),
      base.currencyCode,
    );
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  @override
  State<SplitTipRow> createState() => _SplitTipRowState();
}

class _SplitTipRowState extends State<SplitTipRow> {
  /// Whether the percent field is showing.
  ///
  /// Starts open when the tip is not one of the presets, so reopening a 12% split shows the number that
  /// produced it rather than a row of chips none of which is selected.
  late bool _custom = widget.basisPoints > 0 && !_isPreset(widget.basisPoints);

  late final TextEditingController _field = TextEditingController(
    text: widget.basisPoints == 0 ? '' : _percentText(widget.basisPoints),
  );

  static bool _isPreset(int basisPoints) =>
      SplitTipRow.presetPercents.any((p) => p * 100 == basisPoints);

  /// Basis points as a percentage string, dropping a trailing `.0`.
  ///
  /// 1250 reads as `12.5`, 1000 as `10` — a field showing `10.0` invites somebody to delete the zero and
  /// then the point, which is two keystrokes of fighting the field.
  static String _percentText(int basisPoints) {
    final whole = basisPoints ~/ 100;
    final frac = basisPoints % 100;
    if (frac == 0) return '$whole';
    return frac % 10 == 0 ? '$whole.${frac ~/ 10}' : '$whole.$frac';
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  /// Selects [basisPoints], or clears the tip when it is already selected.
  ///
  /// **Tapping the chosen chip again clears it**, which a `ChoiceChip` does not do on its own. Choosing 10%
  /// and then deciding against it should not require finding the "None" chip — the thing you just tapped is
  /// where your thumb already is. My rewrite dropped this and a test caught it.
  void _choose(int basisPoints) {
    final next = (!_custom && widget.basisPoints == basisPoints)
        ? 0
        : basisPoints;
    setState(() {
      _custom = false;
      final text = next == 0 ? '' : _percentText(next);
      if (_field.text != text) _field.text = text;
    });
    widget.onTip(next);
  }

  void _typed(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      // Cleared means no tip. Distinct from unparseable, which is left alone so a half-typed "1." does
      // not blank the figure somebody is in the middle of writing.
      widget.onTip(0);
      return;
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return;
    widget.onTip(
      (parsed * 100).round().clamp(0, SplitTipRow.maxBasisPoints),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final base = widget.base;
    final total = SplitTipRow.totalFor(
      base: base,
      basisPoints: widget.basisPoints,
      roundUp: widget.roundUp,
      decimalDigits: widget.decimalDigits,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.splitTipTitle,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.xs),

        // A `Wrap`, so six chips reflow onto a second line at 320dp with the scaler doubled rather than
        // overflowing — the shape that caught the balance rows and the group rows before them (Law U15).
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            ChoiceChip(
              label: Text(strings.splitTipNone),
              selected: widget.basisPoints == 0 && !_custom,
              onSelected: (_) => _choose(0),
            ),
            for (final percent in SplitTipRow.presetPercents)
              ChoiceChip(
                label: Text(strings.splitTipPercentChip(percent)),
                selected: !_custom && widget.basisPoints == percent * 100,
                onSelected: (_) => _choose(percent * 100),
              ),
            ChoiceChip(
              // **The chip that makes 1% reachable.** Selecting it changes no number — it reveals the
              // field, which is where the number comes from.
              label: Text(strings.splitTipCustom),
              selected: _custom,
              onSelected: (_) => setState(() => _custom = true),
            ),
            FilterChip(
              // A `FilterChip`, not a `ChoiceChip`, because it is independent: "10% and make it round" is
              // one state, and a choice chip would have forced a decision between the two.
              label: Text(strings.splitRoundUp),
              selected: widget.roundUp,
              onSelected: widget.onRoundUp,
            ),
          ],
        ),

        if (_custom) ...[
          const SizedBox(height: AlayaSpacing.sm),
          SizedBox(
            width: 108,
            child: TextField(
              controller: _field,
              // **`autofocus` kept here, and it is one of four places in the app that keeps it.** This
              // field does not exist until somebody taps **Custom %** — a tap whose only meaning is "I want
              // to type a number". Without focus that tap costs a second one, to reach a field the first
              // tap conjured.
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // Digits and one point, so `_typed` is about range rather than shape. A tip of 12.5% is a
              // real thing to want and basis points carry it exactly.
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                LengthLimitingTextInputFormatter(5),
              ],
              style: AlayaTypography.sectionHeader,
              decoration: InputDecoration(
                isDense: true,
                suffixText: '%',
                labelText: strings.splitTipCustom,
              ),
              onChanged: _typed,
            ),
          ),
        ],

        if (base != null && total != null && total.minor != base.minor) ...[
          const SizedBox(height: AlayaSpacing.xs),
          // **Labels and figures as separate widgets, not one interpolated sentence.** Every other amount
          // in this app renders through `AmountText`, which knows the currency's symbol, its decimal
          // places and its grouping; a string built here would have reimplemented all three and got JPY
          // wrong. An earlier version of this row did exactly that, with a private `_plain` helper that
          // hardcoded a divisor.
          //
          // A `Wrap`, so the four parts reflow at 320dp with the scaler doubled rather than clipping.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AlayaSpacing.xxs,
            children: [
              Text(
                strings.splitTipAdded,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              AmountText(
                Money(total.minor - base.minor, base.currencyCode),
                size: AmountSize.small,
                showSign: false,
                muted: true,
                decimalDigits: widget.decimalDigits,
              ),
              Text(
                strings.splitTipTotalLabel,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              AmountText(
                total,
                size: AmountSize.small,
                showSign: false,
                muted: true,
                decimalDigits: widget.decimalDigits,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
