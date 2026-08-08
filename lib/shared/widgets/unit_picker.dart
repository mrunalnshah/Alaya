import 'package:flutter/material.dart';

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Picks a unit from within one category.
///
/// **Only units in [category] are offered, and that is a correctness constraint rather than a
/// convenience.** A `Qty` is a bare integer plus a category, so offering litres for a weight would
/// store a number that is reinterpreted on read — Law L8's cross-category prohibition, broken
/// silently rather than loudly.
class UnitPicker extends StatelessWidget {
  /// Creates a unit picker.
  const UnitPicker({
    required this.category,
    required this.units,
    required this.selected,
    required this.onChanged,
    this.label,
    this.enabled = true,
    super.key,
  });

  /// The category whose units may be chosen.
  final UnitCategory category;

  /// The available units. Any not in [category] are filtered out rather than trusted.
  final List<Unit> units;

  /// The current selection.
  final Unit? selected;

  /// Called with the newly chosen unit.
  final ValueChanged<Unit> onChanged;

  /// The field's label.
  final String? label;

  /// Whether the picker accepts input.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Filtered here rather than assumed of the caller: a picker that trusts its input to already be
    // category-correct is one bad call site away from breaking L8.
    final eligible = units.where((unit) => unit.category == category).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // Resolved to the instance in `eligible` that shares the selected code, not passed through. A
    // dropdown matches its value against its items by `==`, and `Unit`'s equality covers every
    // field — so a caller holding an instance read before the row was edited would match nothing
    // and the field would render blank with no error.
    Unit? current;
    for (final unit in eligible) {
      if (unit.code == selected?.code) {
        current = unit;
        break;
      }
    }

    return DropdownButtonFormField<Unit>(
      // Keyed on the selection so a change from the caller rebuilds the form field rather than
      // being absorbed: a FormField keeps its own copy of the value it was created with.
      key: ValueKey(current?.code),
      initialValue: current,
      // Without this the button lays its items out at their natural width against unbounded
      // constraints and then overflows the narrow column a QtyField gives it.
      isExpanded: true,
      decoration: InputDecoration(labelText: label, enabled: enabled),
      items: [
        for (final unit in eligible)
          DropdownMenuItem(
            value: unit,
            child: Text(
              unit.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: enabled
          ? (unit) => unit == null ? null : onChanged(unit)
          : null,
    );
  }
}
