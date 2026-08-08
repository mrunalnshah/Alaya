import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/core/time/date_key.dart';

/// Picks a civil date, working in [DateKey] throughout.
///
/// Converts to `DateTime` only to hand Material's picker something it understands, and converts
/// straight back. Holding a `DateTime` in the field's state would reintroduce the time-of-day and
/// timezone that `DateKey` exists to eliminate — and a date that shifts by a day near midnight is the
/// exact bug the type prevents.
class DatePickerField extends StatelessWidget {
  /// Creates a date field.
  const DatePickerField({
    required this.value,
    required this.onChanged,
    required this.formatted,
    this.label,
    this.hint,
    this.errorText,
    this.firstDate,
    this.lastDate,
    this.enabled = true,
    super.key,
  });

  /// The selected date, or null when unset.
  final DateKey? value;

  /// Called with the newly chosen date.
  final ValueChanged<DateKey> onChanged;

  /// Renders [value] for display.
  ///
  /// Injected because date formatting is locale-dependent and belongs with the caller's formatter,
  /// not duplicated inside a field widget.
  final String Function(DateKey) formatted;

  /// The field's label.
  final String? label;

  /// Placeholder shown when [value] is null.
  final String? hint;

  /// An error from the caller.
  final String? errorText;

  /// Earliest selectable date. Defaults to ten years back.
  final DateKey? firstDate;

  /// Latest selectable date. Defaults to five years forward.
  final DateKey? lastDate;

  /// Whether the field accepts input.
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = value?.toUtcMidnight() ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate?.toUtcMidnight() ?? DateTime(now.year - 10),
      lastDate: lastDate?.toUtcMidnight() ?? DateTime(now.year + 5),
    );
    if (picked != null) onChanged(DateKey.fromDateTime(picked));
  }

  @override
  Widget build(BuildContext context) {
    final current = value;
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      child: InputDecorator(
        // **The hint belongs to the decoration, not to the child.** With `isEmpty: true` the label sits
        // inside the field rather than floating, and a child `Text(hint)` then renders in exactly the
        // same place — so an unset date showed its label and its hint on top of each other. Handing the
        // hint to `InputDecoration` lets the decorator own that collision, which is the only thing that
        // knows where the label currently is.
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: errorText,
          suffixIcon: Icon(
            Icons.calendar_today_outlined,
            size: AlayaIconSize.md,
          ),
          enabled: enabled,
        ),
        isEmpty: current == null,
        child: current == null
            ? const SizedBox.shrink()
            : Text(formatted(current)),
      ),
    );
  }
}
