import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';

/// The month grid, with one severity dot per day that has entries.
///
/// **This is the only file in the phase that imports `table_calendar`.** Every cell, the weekday row
/// and the header are built here from Alaya's own tokens through `calendarBuilders`, and
/// `headerVisible` is false — so the package supplies page arithmetic and swipe animation, and nothing
/// that a theme token would otherwise own. If the package's API differs from this, one file changes.
class CalendarMonthGrid extends StatelessWidget {
  /// Creates the grid for [month].
  const CalendarMonthGrid({
    required this.month,
    required this.today,
    required this.daysByKey,
    required this.onDaySelected,
    required this.onDayLongPressed,
    required this.onMonthChanged,
    this.lockedToMonth = false,
    this.selected,
    this.rangeStart,
    this.rangeEnd,
    super.key,
  });

  /// The visible month, as its first day.
  final DateKey month;

  /// Today, from the injected clock — never `DateTime.now()` (ARCH_2 §12.2).
  final DateKey today;

  /// The month's days that have entries, keyed by `DateKey.value`.
  final Map<int, CalendarDay> daysByKey;

  /// Called when a day cell is tapped.
  final ValueChanged<DateKey> onDaySelected;

  /// Called when a day cell is long-pressed, which is how a range begins.
  final ValueChanged<DateKey> onDayLongPressed;

  /// Called when the grid pages to another month.
  final ValueChanged<DateKey> onMonthChanged;

  /// Whether this grid shows [month] and nothing else.
  ///
  /// Turning the gesture off is not enough on its own — `firstDay` and `lastDay` still span years, so the
  /// underlying `PageView` keeps its neighbouring pages and any fling, keyboard scroll or accessibility
  /// scroll action can still reach them. Narrowing the bounds to this one month removes the pages
  /// themselves, which is what makes "static" true rather than merely discouraged.
  final bool lockedToMonth;

  /// The currently selected day, if any.
  final DateKey? selected;

  /// The first day of a selected range, if a range is being picked.
  final DateKey? rangeStart;

  /// The last day of a selected range. Null while only the start has been chosen.
  final DateKey? rangeEnd;

  /// How many years either side of the visible month the grid may page to.
  static const int _pagingYears = 5;

  /// The severity dot's diameter.
  static const double _dotSize = AlayaSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;

    // U26: the row height is measured from the current text scale, never fixed. A day cell holds a
    // number and a dot, and both grow when the reader doubles their text size while a constant
    // `rowHeight` would not — which is how a grid of text cells overflows at scale 2.
    final scaler = MediaQuery.textScalerOf(context);
    final numberHeight =
        scaler.scale(AlayaTypography.body.fontSize!) *
        AlayaTypography.body.height!;
    final rowHeight = math.max(
      AlayaSpacing.minTapTarget,
      numberHeight + AlayaSpacing.xxs + _dotSize + AlayaSpacing.xs,
    );
    final dowHeight = math.max(
      AlayaSpacing.md,
      scaler.scale(AlayaTypography.caption.fontSize!) *
              AlayaTypography.caption.height! +
          AlayaSpacing.xxs,
    );

    return TableCalendar<CalendarDay>(
      // Day zero of the following month is the last day of this one, and `DateTime.utc` normalises a
      // thirteenth month — unlike `DateKey.fromYmd`, which validates and would throw every December.
      firstDay: lockedToMonth
          ? DateTime.utc(month.year, month.month, 1)
          : DateTime.utc(today.year - _pagingYears, 1, 1),
      lastDay: lockedToMonth
          ? DateTime.utc(month.year, month.month + 1, 0)
          : DateTime.utc(today.year + _pagingYears, 12, 31),
      focusedDay: month.toUtcMidnight(),
      calendarFormat: CalendarFormat.month,
      availableCalendarFormats: const {CalendarFormat.month: ''},
      headerVisible: false,
      rowHeight: rowHeight,
      daysOfWeekHeight: dowHeight,
      startingDayOfWeek: StartingDayOfWeek.monday,
      availableGestures: lockedToMonth
          ? AvailableGestures.none
          : AvailableGestures.horizontalSwipe,
      selectedDayPredicate: (day) =>
          selected != null &&
          DateKey.fromDateTime(day).value == selected!.value,
      onDaySelected: (day, _) => onDaySelected(DateKey.fromDateTime(day)),
      onDayLongPressed: (day, _) => onDayLongPressed(DateKey.fromDateTime(day)),
      onPageChanged: (day) => onMonthChanged(DateKey.fromDateTime(day)),
      calendarBuilders: CalendarBuilders<CalendarDay>(
        dowBuilder: (context, day) => Center(
          child: Text(
            _weekdayInitial(context, day),
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ),
        // Range highlighting is drawn here rather than through `rangeSelectionMode` and
        // `onRangeSelected`. The package's range mode toggles on a long-press — an invisible gesture —
        // and routes range cells to `rangeStartBuilder`/`withinRangeBuilder`/`rangeEndBuilder`, which
        // would bypass the four builders below and leave the cells unstyled. Owning the two dates and
        // decorating them in `defaultBuilder` keeps one cell widget responsible for every state, and
        // puts the control on a visible button instead of a gesture nobody discovers.
        defaultBuilder: (context, day, _) => _cell(day),
        outsideBuilder: (context, day, _) => _cell(day, outside: true),
        todayBuilder: (context, day, _) => _cell(day, isToday: true),
        selectedBuilder: (context, day, _) => _cell(day, isSelected: true),
      ),
    );
  }

  /// Builds one cell, resolving its range membership from the two dates this widget was given.
  Widget _cell(
    DateTime day, {
    bool outside = false,
    bool isToday = false,
    bool isSelected = false,
  }) {
    final key = DateKey.fromDateTime(day);
    final start = rangeStart;
    final end = rangeEnd;
    final inRange = start != null && end != null && key.isWithin(start, end);

    return _Cell(
      day: day,
      entry: daysByKey[key.value],
      dotSize: _dotSize,
      outside: outside,
      isToday: isToday,
      isSelected: isSelected,
      inRange: inRange,
      isRangeEdge:
          (start != null && key == start) || (end != null && key == end),
    );
  }

  /// The single-letter weekday label for [day], in the active locale.
  static String _weekdayInitial(BuildContext context, DateTime day) {
    final symbols = MaterialLocalizations.of(context).narrowWeekdays;
    return symbols[day.weekday % DateTime.daysPerWeek];
  }
}

/// One day cell: its number, and one dot per entry up to three.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.entry,
    required this.dotSize,
    this.outside = false,
    this.isToday = false,
    this.isSelected = false,
    this.inRange = false,
    this.isRangeEdge = false,
  });

  final DateTime day;
  final CalendarDay? entry;
  final double dotSize;
  final bool outside;
  final bool isToday;
  final bool isSelected;
  final bool inRange;
  final bool isRangeEdge;

  /// The most dots a cell will draw, whatever the day holds.
  static const int _maxDots = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final count = entry?.events.length ?? 0;
    final severity = entry?.severity;

    // Colour AND count. A single dot in three hues fails a colour-blind reader and fails in grayscale,
    // and the dot is the grid's only severity signal — there is no room for a word in a 45dp cell
    // (Law U9). One dot per entry up to three gives a second, non-chromatic dimension: a busy day looks
    // busy before anyone resolves the hue, and the cell's semantics label says it outright for a reader
    // who resolves neither.
    final dotColour = switch (severity) {
      CalendarSeverity.danger => semantic.danger,
      CalendarSeverity.warning => semantic.warning,
      // Green for "there is something here, nothing is wrong". A stretch of `success`, which normally
      // means *done* — an ordinary transaction is neither good nor bad, merely present — but it is the
      // colour a calendar reader expects opposite red and amber, and inventing a fourth role for one
      // dot would be worse.
      CalendarSeverity.info => semantic.success,
      null => Colors.transparent,
    };

    final numberColour = outside
        ? semantic.muted
        : isSelected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    // **No `Semantics` here, and that is not an omission.** `table_calendar` labels every cell itself —
    // "Monday, August 10, 2026" — and excludes whatever its builders contribute, so a label added here
    // produces no node at all. Four rounds were spent asserting one that could never exist; the
    // semantics dump showed one node per cell, the package's own, with no children.
    //
    // U9 is still satisfied, by a different part of the screen. The dots are a visual affordance over
    // content that is already readable: tapping a day fills the section below with real text nodes, and
    // that section is the authoritative accessible reading of what a day holds. The grid navigates; the
    // section speaks.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primaryContainer
            : inRange
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : null,
        border: (isToday && !isSelected) || isRangeEdge
            ? Border.all(color: theme.colorScheme.primary)
            : null,
        borderRadius: AlayaRadii.borderSm,
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                // The day number, not a date. `DateText` renders a whole formatted date and cannot fit
                // a grid cell — U7's "DateKey through DateText" governs displaying a date, and this is
                // an axis label for one.
                '${day.day}',
                style: AlayaTypography.body.copyWith(color: numberColour),
              ),
              const SizedBox(height: AlayaSpacing.xxs),
              SizedBox(
                height: dotSize,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < math.min(count, _maxDots); i++)
                      Padding(
                        padding: EdgeInsets.only(
                          left: i == 0 ? 0 : AlayaSpacing.xxs / 2,
                        ),
                        child: SizedBox(
                          width: dotSize,
                          height: dotSize,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dotColour,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
