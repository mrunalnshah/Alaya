import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// How many people are sharing: two taps, or type it.
///
/// **Both, because the two cases are genuinely different.** Going from two to four is a tap each way
/// and a keyboard would be slower; going from two to *fourteen* is twelve taps, which is where a
/// stepper stops being a convenience and becomes a chore. The number between the buttons is therefore
/// a field, not a label.
///
/// **The field reads the count and never fights it.** Its controller is only rewritten when the value
/// arriving from outside differs from what is displayed — otherwise every keystroke would rebuild the
/// parent, push the same text back in, and reset the cursor to the start. That is the same trap the
/// `_loaded` guard solves in `TagEditorScreen`, in its live-editing form rather than its adoption one.
///
/// **Empty is allowed while typing and never committed.** Somebody clearing the field to type "12"
/// passes through "" — treating that as zero would collapse the split, and rejecting it would make the
/// field impossible to clear. It simply reports nothing until a valid number exists.
class PeopleCounter extends StatefulWidget {
  /// Creates the counter.
  const PeopleCounter({
    required this.count,
    required this.onChanged,
    this.minimum = 1,
    super.key,
  });

  /// How many people there are now.
  final int count;

  /// Called with a valid new count.
  final ValueChanged<int> onChanged;

  /// The fewest allowed — one on the full editor, two on the quick card.
  final int minimum;

  /// The most this will accept.
  ///
  /// Not a product rule so much as a guard against a typo: somebody who means 12 and types 120 would
  /// otherwise get a hundred and twenty rows and a frozen screen.
  static const int maximum = 99;

  @override
  State<PeopleCounter> createState() => _PeopleCounterState();
}

class _PeopleCounterState extends State<PeopleCounter> {
  late final TextEditingController _field = TextEditingController(
    text: '${widget.count}',
  );

  @override
  void didUpdateWidget(PeopleCounter old) {
    super.didUpdateWidget(old);
    // Only when it actually differs — see the class doc. A blanket assignment here is what turns a
    // typable field into one that clears itself on the second digit.
    if (_field.text != '${widget.count}') {
      _field.text = '${widget.count}';
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _step(int by) {
    final next = (widget.count + by).clamp(
      widget.minimum,
      PeopleCounter.maximum,
    );
    if (next != widget.count) widget.onChanged(next);
  }

  void _typed(String text) {
    final parsed = int.tryParse(text.trim());
    // Nothing yet, or nonsense: leave the count where it is and let them keep typing.
    if (parsed == null) return;
    final next = parsed.clamp(widget.minimum, PeopleCounter.maximum);
    if (next != widget.count) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton.filledTonal(
          // Disabled at the floor rather than clamping silently: a button that looks live and does
          // nothing is worse than one that plainly cannot be pressed.
          onPressed: widget.count > widget.minimum ? () => _step(-1) : null,
          icon: const Icon(Icons.remove, size: AlayaIconSize.md),
        ),
        SizedBox(
          width: 56,
          child: TextField(
            controller: _field,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            // Digits only, so the parse above is about range rather than shape and the keyboard cannot
            // introduce a minus sign or a decimal point that would need rejecting after the fact.
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            style: AlayaTypography.sectionHeader,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                vertical: AlayaSpacing.xs,
              ),
            ),
            onChanged: _typed,
            // Leaving the field empty puts the real count back, so it never looks blank once the
            // keyboard closes.
            onTapOutside: (_) {
              if (int.tryParse(_field.text) == null) {
                _field.text = '${widget.count}';
              }
              FocusScope.of(context).unfocus();
            },
          ),
        ),
        IconButton.filledTonal(
          onPressed: widget.count < PeopleCounter.maximum
              ? () => _step(1)
              : null,
          icon: const Icon(Icons.add, size: AlayaIconSize.md),
        ),
      ],
    );
  }
}
