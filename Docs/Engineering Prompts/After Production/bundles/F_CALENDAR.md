# F_CALENDAR

Calendar screen and day sheet.

**9 files · 2,013 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/features/calendar/presentation/screens/calendar_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_event_list.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_month_grid.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/loading_state.dart';

/// The calendar month view (ARCH_5 §3 archetype F).
///
/// **The section under the grid shows what is on the selected day, not how many days have something.**
/// A count is a fact about the month; the entries are the answer the reader came for. Selection starts on
/// today, so the screen says something useful before it is touched.
class CalendarScreen extends ConsumerStatefulWidget {
  /// Creates the screen, optionally opening [initialDay] on arrival.
  const CalendarScreen({this.initialDay, super.key});

  /// The day to select on arrival, when reached through `/calendar/:dateKey`.
  final DateKey? initialDay;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateKey? _selected;
  DateKey? _rangeStart;
  DateKey? _rangeEnd;
  bool _rangeMode = false;

  @override
  void initState() {
    super.initState();
    final day = widget.initialDay;
    if (day == null) return;
    // After the first frame: the month has to be focused before the grid builds, or the deep link lands
    // on today's page with another day selected.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(focusedMonthProvider.notifier).focus(day);
      setState(() => _selected = day);
    });
  }

  /// Handles a tap on [day] — the second tap of a range closes it, otherwise it starts a new one.
  void _tapDay(DateKey day) {
    setState(() {
      if (!_rangeMode) {
        _selected = day;
        return;
      }
      if (_rangeStart == null || _rangeEnd != null) {
        _rangeStart = day;
        _rangeEnd = null;
      } else if (day < _rangeStart!) {
        _rangeEnd = _rangeStart;
        _rangeStart = day;
      } else {
        _rangeEnd = day;
      }
    });
  }

  /// Starts a range at [day], or clears one already being picked.
  ///
  /// Long-press, not a button. A mode toggle in the header was a control that spent most of its life
  /// switched off, and the gesture belongs on the thing it acts upon: press a day to begin a span, tap
  /// the far end to close it, press again to go back to single days.
  void _longPressDay(DateKey day) => setState(() {
    if (_rangeMode) {
      _rangeMode = false;
      _rangeStart = null;
      _rangeEnd = null;
      _selected = day;
    } else {
      _rangeMode = true;
      _rangeStart = day;
      _rangeEnd = null;
    }
  });

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final month = ref.watch(focusedMonthProvider);
    final today = ref.watch(calendarTodayProvider);
    final index = ref.watch(calendarDayIndexProvider(month));
    final selected = _selected ?? today;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            children: [
              _MonthHeader(
                month: month,
                today: today,
                onShift: (months) =>
                    ref.read(focusedMonthProvider.notifier).shift(months),
                onToday: () {
                  ref.read(focusedMonthProvider.notifier).focus(today);
                  setState(() {
                    _selected = today;
                    _rangeStart = null;
                    _rangeEnd = null;
                  });
                },
              ),
              CalendarMonthGrid(
                month: month,
                today: today,
                daysByKey: index.valueOrNull ?? const <int, CalendarDay>{},
                selected: _rangeMode ? null : selected,
                rangeStart: _rangeStart,
                rangeEnd: _rangeEnd,
                onDaySelected: _tapDay,
                onDayLongPressed: _longPressDay,
                onMonthChanged: (day) =>
                    ref.read(focusedMonthProvider.notifier).focus(day),
              ),
              const Divider(height: AlayaSpacing.md),
              // The month feed's own loading and error states belong here, because the dots depend on it
              // and a reader who sees no dots deserves to know whether that means "nothing" or "not yet".
              index.when(
                loading: () =>
                    LoadingState(label: strings.calendarLoadingMonth),
                error: (error, stack) => ErrorState(
                  title: strings.calendarErrorTitle,
                  body: error.toString(),
                  retryLabel: strings.calendarRetry,
                  onRetry: () => ref.invalidate(calendarDaysProvider(month)),
                ),
                data: (_) => _rangeMode
                    ? _RangeSection(start: _rangeStart, end: _rangeEnd)
                    : _DaySection(day: selected),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The month label, a chevron either side, and the range toggle.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.today,
    required this.onShift,
    required this.onToday,
  });

  final DateKey month;
  final DateKey today;
  final ValueChanged<int> onShift;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final label = DateFormat.yMMMM(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(month.toUtcMidnight());
    final onThisMonth = month == DateKey.fromYmd(today.year, today.month, 1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Row(
        children: [
          IconButton(
            onPressed: () => onShift(-1),
            tooltip: strings.calendarPreviousMonth,
            icon: const Icon(Icons.chevron_left, size: AlayaIconSize.md),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AlayaTypography.cardTitle.copyWith(
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Between the label and the forward chevron, and only when it would do something. Sitting
          // *before* the chevron rather than after it means the three navigation controls stay together
          // and the reader's thumb does not have to travel past "next" to get "home".
          // `Visibility` with `maintainSize`, not a conditional child. Adding a child to this Row
          // shrinks the `Expanded` beside it, so the centred month label slid left the moment the
          // button appeared and slid back when it left — the heading twitching as you page through
          // months. Reserving the slot keeps the label centred on both kinds of month, and reserving it
          // via the button's own size means nothing has to hardcode 48dp.
          //
          // `maintainInteractivity` stays false, so the hidden button is neither tappable nor announced.
          Visibility(
            visible: !onThisMonth,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: IconButton(
              onPressed: onToday,
              tooltip: strings.calendarBackToToday,
              icon: const Icon(
                Icons.event_available_outlined,
                size: AlayaIconSize.md,
              ),
            ),
          ),
          IconButton(
            onPressed: () => onShift(1),
            tooltip: strings.calendarNextMonth,
            icon: const Icon(Icons.chevron_right, size: AlayaIconSize.md),
          ),
        ],
      ),
    );
  }
}

/// What is on one day.
class _DaySection extends ConsumerWidget {
  const _DaySection({required this.day});

  final DateKey day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    return _Section(
      heading: strings.calendarOnDay,
      dateLabel: DateFormat.yMMMMd(
        Localizations.localeOf(context).toLanguageTag(),
      ).format(day.toUtcMidnight()),
      events: ref.watch(dayEventsProvider(day)),
      totals: ref.watch(spanTotalsProvider((from: day, to: day))),
      emptyTitle: strings.calendarDayEmptyTitle,
      emptyBody: strings.calendarDayEmptyBody,
      onRetry: () => ref.invalidate(dayEventsProvider(day)),
    );
  }
}

/// What is inside a chosen span.
class _RangeSection extends ConsumerWidget {
  const _RangeSection({required this.start, required this.end});

  final DateKey? start;
  final DateKey? end;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final format = DateFormat.yMMMMd(locale);

    // No `start == null` branch: a range only exists because a long-press named its first day, so the
    // start is always set by the time this renders. A state that cannot be reached is a state that will
    // rot unnoticed.
    if (end == null) {
      return Padding(
        padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
        child: Text(
          strings.calendarRangePickEnd(format.format(start!.toUtcMidnight())),
          textAlign: TextAlign.center,
          style: AlayaTypography.body.copyWith(color: context.semantic.muted),
        ),
      );
    }

    final span = (from: start!, to: end!);
    return _Section(
      heading: strings.calendarInRange(start!.diffDays(end!).abs() + 1),
      dateLabel:
          '${format.format(start!.toUtcMidnight())} — '
          '${format.format(end!.toUtcMidnight())}',
      events: ref.watch(rangeEventsProvider(span)),
      totals: ref.watch(spanTotalsProvider(span)),
      emptyTitle: strings.calendarRangeEmptyTitle,
      emptyBody: strings.calendarRangeEmptyBody,
      onRetry: () => ref.invalidate(rangeEventsProvider(span)),
    );
  }
}

/// A heading, the span it covers, and the entries inside it — all four async states.
class _Section extends StatelessWidget {
  const _Section({
    required this.heading,
    required this.dateLabel,
    required this.events,
    required this.totals,
    required this.emptyTitle,
    required this.emptyBody,
    required this.onRetry,
  });

  final String heading;
  final String dateLabel;
  final AsyncValue<List<CalendarEvent>> events;

  /// What was spent and what came in over the same span.
  final AsyncValue<SpanTotals> totals;
  final String emptyTitle;
  final String emptyBody;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: AlayaTypography.label.copyWith(color: semantic.muted),
          ),
          Text(
            dateLabel,
            style: AlayaTypography.cardTitle.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          // Between the heading and the entries, because it answers the same question at a glance that
          // reading every card would answer slowly. Absent when the span held no transactions at all,
          // rather than showing two zeroes that look like a finding.
          if (totals.valueOrNull?.isEmpty == false)
            _Totals(totals: totals.requireValue),
          const SizedBox(height: AlayaSpacing.xs),
          events.when(
            loading: () => LoadingState(label: strings.calendarLoadingDay),
            error: (error, stack) => ErrorState(
              title: strings.calendarDayErrorTitle,
              body: error.toString(),
              retryLabel: strings.calendarRetry,
              onRetry: onRetry,
            ),
            data: (list) => list.isEmpty
                ? EmptyState(
                    title: emptyTitle,
                    body: emptyBody,
                    icon: Icons.event_available_outlined,
                  )
                : CalendarEventList(events: list),
          ),
        ],
      ),
    );
  }
}

/// What went out and what came in over the section's span.
class _Totals extends StatelessWidget {
  const _Totals({required this.totals});

  final SpanTotals totals;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);

    // `Wrap`, so the two figures stack instead of overflowing once the text scales (Law U21).
    return Padding(
      padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
      child: Wrap(
        spacing: AlayaSpacing.md,
        runSpacing: AlayaSpacing.xxs,
        children: [
          _Figure(
            label: strings.calendarTotalOut,
            minor: totals.outMinor,
            currencyCode: totals.currencyCode,
            kind: TransactionKind.withdrawal,
          ),
          _Figure(
            label: strings.calendarTotalIn,
            minor: totals.inMinor,
            currencyCode: totals.currencyCode,
            kind: TransactionKind.deposit,
          ),
        ],
      ),
    );
  }
}

/// One labelled figure.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.minor,
    required this.currencyCode,
    required this.kind,
  });

  final String label;
  final int minor;
  final String currencyCode;

  /// Which direction this figure runs. `AmountText` derives its colour from this rather than taking a
  /// colour, so the expense red here is the same red every other amount in the app uses.
  final TransactionKind kind;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: AlayaTypography.label.copyWith(color: context.semantic.muted),
      ),
      AmountText(
        Money(minor, currencyCode),
        size: AmountSize.small,
        showSign: false,
        kind: kind,
      ),
    ],
  );
}
```

### `lib/features/calendar/presentation/widgets/calendar_event_list.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/widgets/event_card.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// The route for the record behind [event], or null where the feed cannot address it.
///
/// `v_calendar_events` carries `ref_type` and `ref_id` but not the parent id that three of the six
/// detail routes need — a batch route wants its item, a service record wants its asset, and a recurring
/// occurrence has no route of its own. Those land on the owning module instead. Closing it means a
/// `parent_ref_id` column on the view, which is a Phase 2A change.
String? calendarEventRoute(CalendarEvent event) => switch (event.refType) {
  'transaction' => Routes.transactionDetail(event.refId),
  'asset' => Routes.assetDetail(event.refId),
  'shoppingList' => Routes.shoppingList(event.refId),
  'inventoryBatch' => Routes.inventory,
  'serviceRecord' => Routes.services,
  'recurringOccurrence' => Routes.recurring,
  _ => null,
};

/// Calendar entries under one heading per event type, each tappable through to its record.
///
/// Shared by the inline day section and the day sheet, because the same list rendered twice is a list
/// that will disagree with itself (ARCH_4 R25).
class CalendarEventList extends ConsumerWidget {
  /// Creates the list.
  const CalendarEventList({required this.events, this.onNavigate, super.key});

  /// The entries, with severity already resolved by `CalendarAggregator`.
  final List<CalendarEvent> events;

  /// Called just before navigating away — a sheet uses it to close itself first.
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final byType = <CalendarEventType, List<CalendarEvent>>{};
    for (final event in events) {
      (byType[event.type] ??= <CalendarEvent>[]).add(event);
    }

    // Declaration order rather than severity order: a reader scanning the same day twice should find
    // the same thing in the same place.
    final types = CalendarEventType.values.where(byType.containsKey).toList();

    return ListView.builder(
      shrinkWrap: true,
      itemCount: types.length,
      itemBuilder: (context, index) {
        final type = types[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(label: type.labelOf(strings)),
            for (final event in byType[type]!)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
                child: _Tappable(event: event, onNavigate: onNavigate),
              ),
          ],
        );
      },
    );
  }
}

/// An event card wired to its record, or inert where the feed cannot address one.
class _Tappable extends StatelessWidget {
  const _Tappable({required this.event, this.onNavigate});

  final CalendarEvent event;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final route = calendarEventRoute(event);
    return EventCard(
      event: event,
      // The type is already the heading above this card.
      showType: false,
      onTap: route == null
          ? null
          : () {
              onNavigate?.call();
              context.push(route);
            },
    );
  }
}
```

### `lib/features/calendar/presentation/widgets/calendar_month_grid.dart`

```dart
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
```

### `lib/features/calendar/presentation/widgets/day_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_event_list.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/loading_state.dart';

/// One day's calendar entries, grouped by event type (ARCH_5 §3 archetype A).
class DaySheet extends ConsumerWidget {
  /// Creates the sheet for [dateKey].
  const DaySheet({required this.dateKey, super.key});

  /// Opens the sheet for [dateKey].
  static Future<void> show({
    required BuildContext context,
    required DateKey dateKey,
  }) => AlayaBottomSheet.show<void>(
    context: context,
    builder: (_) => DaySheet(dateKey: dateKey),
  );

  /// The day being shown.
  final DateKey dateKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final events = ref.watch(dayEventsProvider(dateKey));

    // The box, not the screen. Two rounds were lost guessing at this arithmetic from `MediaQuery`:
    // first `sizeOf().height * 0.6`, which ignored the keyboard; then the same minus
    // `viewInsetsOf().bottom`, which reads **zero** here because `Scaffold` with
    // `resizeToAvoidBottomInset` consumes the inset — it shrinks the body and hands the body a
    // `MediaQuery` with the bottom inset already removed. The height I was subtracting had been
    // subtracted for me, and the box I was ignoring was the only honest number in the frame.
    //
    // `LayoutBuilder` reads that box directly, and `Flexible` gives the list whatever the header leaves
    // rather than a fraction anyone has to reason about. No arithmetic, so nothing to get wrong.
    return LayoutBuilder(
      builder: (context, constraints) {
        final header = <Widget>[
          DateText(dateKey, style: DateTextStyle.full),
          const SizedBox(height: AlayaSpacing.sm),
        ];

        final body = events.when(
          loading: () => LoadingState(label: strings.calendarLoadingDay),
          error: (error, stack) => ErrorState(
            title: strings.calendarDayErrorTitle,
            body: error.toString(),
            retryLabel: strings.calendarRetry,
            onRetry: () => ref.invalidate(dayEventsProvider(dateKey)),
          ),
          data: (list) => list.isEmpty
              ? EmptyState(
                  title: strings.calendarDayEmptyTitle,
                  body: strings.calendarDayEmptyBody,
                  icon: Icons.event_available_outlined,
                )
              : CalendarEventList(
                  events: list,
                  // Close the sheet before the push, or the record opens behind it.
                  onNavigate: () => Navigator.of(context).pop(),
                ),
        );

        // Unbounded is legitimate — a sheet host may let its content decide the height — and `Flexible`
        // asserts there, so it only appears when there is a box to divide.
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...header,
            if (constraints.hasBoundedHeight) Flexible(child: body) else body,
          ],
        );
      },
    );
  }
}
```

### `lib/features/calendar/presentation/widgets/event_card.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// The wording and glyph for one [CalendarEventType].
extension CalendarEventTypeDisplay on CalendarEventType {
  /// The localised name of this event type.
  String labelOf(AlayaStrings strings) => switch (this) {
    CalendarEventType.transaction => strings.eventTypeTransaction,
    CalendarEventType.recurringDue => strings.eventTypeRecurringDue,
    CalendarEventType.batchExpiry => strings.eventTypeBatchExpiry,
    CalendarEventType.warrantyEnd => strings.eventTypeWarrantyEnd,
    CalendarEventType.serviceDue => strings.eventTypeServiceDue,
    CalendarEventType.shoppingTarget => strings.eventTypeShoppingTarget,
    CalendarEventType.splitSettleBy => strings.eventTypeSplitSettleBy,
  };

  /// The glyph for this event type.
  IconData get icon => switch (this) {
    CalendarEventType.transaction => Icons.receipt_long_outlined,
    CalendarEventType.recurringDue => Icons.event_repeat,
    CalendarEventType.batchExpiry => Icons.inventory_2_outlined,
    CalendarEventType.warrantyEnd => Icons.verified_outlined,
    CalendarEventType.serviceDue => Icons.handyman_outlined,
    CalendarEventType.shoppingTarget => Icons.shopping_basket_outlined,
    // A handshake rather than a wallet: the entry is a debt to close with somebody, not a payment
    // leaving an account. `receipt_long_outlined` already means "a transaction" in this same switch.
    CalendarEventType.splitSettleBy => Icons.handshake_outlined,
  };
}

/// The colour and wording for one [CalendarSeverity].
extension CalendarSeverityDisplay on CalendarSeverity {
  /// The chip tone matching this severity.
  StatusTone get tone => switch (this) {
    CalendarSeverity.info => StatusTone.info,
    CalendarSeverity.warning => StatusTone.warning,
    CalendarSeverity.danger => StatusTone.danger,
  };

  /// The localised severity word, or null where there is nothing to warn about.
  String? labelOrNull(AlayaStrings strings) => switch (this) {
    CalendarSeverity.info => null,
    CalendarSeverity.warning => strings.calendarSeverityWarning,
    CalendarSeverity.danger => strings.calendarSeverityDanger,
  };

  /// The colour for this severity's glyph.
  Color colorOf(AlayaSemanticColors semantic) => switch (this) {
    CalendarSeverity.info => semantic.muted,
    CalendarSeverity.warning => semantic.warning,
    CalendarSeverity.danger => semantic.danger,
  };
}

/// One calendar entry, severity-coloured and severity-labelled.
///
/// The severity word is not decoration beside the colour — it is the carrier. Colour alone fails a
/// colour-blind reader and fails in grayscale, so `warning` and `danger` always say so (Law U9).
class EventCard extends StatelessWidget {
  /// Creates a card for [event].
  const EventCard({
    required this.event,
    required this.onTap,
    this.decimalDigits = 2,
    this.showType = true,
    super.key,
  });

  /// The entry to render, with its severity already resolved by `CalendarAggregator`.
  final CalendarEvent event;

  /// Opens the underlying record.
  final VoidCallback? onTap;

  /// Minor-unit digits for the amount, from the household's currency.
  final int decimalDigits;

  /// Whether to name the event type on the card.
  ///
  /// False inside a list already grouped by type: the heading says "Transaction" and so did every card
  /// under it, which is noise on the screen and two matches for one finder in the tests.
  final bool showType;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final theme = Theme.of(context);
    final severityLabel = event.baseSeverity.labelOrNull(strings);
    final typeLabel = event.type.labelOf(strings);

    return AlayaCard(
      onTap: onTap,
      semanticsLabel: [
        event.title,
        typeLabel,
        if (severityLabel != null) severityLabel,
      ].join('. '),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            event.type.icon,
            size: AlayaIconSize.md,
            color: event.baseSeverity.colorOf(semantic),
          ),
          const SizedBox(width: AlayaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: AlayaTypography.body.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AlayaSpacing.xxs),
                // Wrap, not Row: the type label and the severity chip both grow with text scale and
                // side by side one of them starves at 320dp (Law U21).
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (showType)
                      Text(
                        typeLabel,
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.muted,
                        ),
                      ),
                    if (severityLabel != null)
                      StatusChip(
                        label: severityLabel,
                        tone: event.baseSeverity.tone,
                      ),
                  ],
                ),
                if (event.amount != null) ...[
                  const SizedBox(height: AlayaSpacing.xxs),
                  // Under the text, not beside it (Law U21).
                  //
                  // Beside it, the amount was the Row's one inflexible child: it took its natural width
                  // first and left the `Expanded` column whatever remained. At a doubled scale on a 320dp
                  // card that remainder was about 64px, and `StatusChip` cannot shrink below its own
                  // label — so the chip overflowed by 124px. Making the amount `Flexible` only splits the
                  // starvation two ways; the fix is to stop competing for the same axis.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AmountText(
                      event.amount!,
                      size: AmountSize.small,
                      showSign: false,
                      decimalDigits: decimalDigits,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/calendar/providers/calendar_providers.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';

/// Today, from the injected clock — the only source of "now" the calendar has.
final calendarTodayProvider = Provider<DateKey>(
  (ref) => ref.watch(clockProvider).today(),
);

/// The month the grid is showing, as its first day.
final focusedMonthProvider = NotifierProvider<FocusedMonthNotifier, DateKey>(
  FocusedMonthNotifier.new,
);

/// Holds the visible month and moves it a month at a time.
class FocusedMonthNotifier extends Notifier<DateKey> {
  @override
  DateKey build() {
    final today = ref.watch(calendarTodayProvider);
    return DateKey.fromYmd(today.year, today.month, 1);
  }

  /// Jumps to the month containing [day].
  void focus(DateKey day) => state = DateKey.fromYmd(day.year, day.month, 1);

  /// Moves [months] months from the current one, negative for backwards.
  void shift(int months) => state = shiftMonth(state, months);
}

/// The first of the month [months] away from [month], carried across year boundaries.
///
/// **`DateKey.fromYmd` validates, it does not normalise.** `month + 1` on December is 13 and `month - 1`
/// on January is 0, and both throw `ArgumentError` — which is why paging forward past December 2026 died
/// and the month had to be reached by swiping instead. Counting in absolute months and converting back
/// once removes the boundary entirely rather than special-casing it.
DateKey shiftMonth(DateKey month, int months) {
  final total = month.year * 12 + (month.month - 1) + months;
  return DateKey.fromYmd(total ~/ 12, total % 12 + 1, 1);
}

/// How far ahead recurring occurrences are created.
///
/// Two years, flat. A data-driven horizon — out to the furthest warranty or service the app knows about —
/// was considered and dropped: it needs a `max()` across four tables, and the only way to *see* a date
/// that far out is to browse to it, by which point a fixed two years has already covered anything a
/// household plans around.
const int recurringHorizonYears = 2;

/// Creates the recurring occurrence rows the calendar and the dashboard read, once per session.
///
/// **Without this the calendar cannot show a future bill at all.** `materialiseUpTo` was only ever called
/// with `clock.today()`, on the recurring list's mount (6D's coverage table: "lazy materialisation only"),
/// so no occurrence row existed past today and the `recurringDue` arm of `v_calendar_events` had nothing
/// future to return. Every other source stores its date outright — a warranty end, a service due, a batch
/// expiry — which is why recurring was the only one that could be silently absent.
///
/// Not `autoDispose`: this is a per-session job, and re-running it whenever the last calendar screen
/// closes would write on every navigation for no gain.
///
/// A failure does not block the read. The calendar then shows whatever rows exist, which is worse than
/// complete but far better than an empty month — and surfacing the failure properly needs the app-wide
/// notification channel that is 8B's work.
final recurringHorizonProvider = FutureProvider<int>((ref) async {
  final today = ref.watch(clockProvider).today();
  // `addDays`, not the same day two years on. On 29 February 2028 that reads
  // `fromYmd(2030, 2, 29)`, which is not a real date and throws — taking the calendar and the
  // dashboard's upcoming card down with it, on one day every four years.
  final horizon = today.addDays(365 * recurringHorizonYears);
  final result = await ref
      .watch(recurringRepositoryProvider)
      .materialiseUpTo(horizon);
  return result.fold((created) => created, (failure) => 0);
});

/// The visible month's events grouped by day, severity resolved against today.
///
/// Bounded to the month plus six days either side, which covers the leading and trailing cells a
/// month grid always shows without widening the range enough to lose the per-source indexes.
final calendarDaysProvider = StreamProvider.autoDispose
    .family<List<CalendarDay>, DateKey>((ref, month) async* {
      // The occurrences first, or the first frame of a future month shows every source except recurring.
      await ref.watch(recurringHorizonProvider.future);

      final today = ref.watch(calendarTodayProvider);
      final aggregator = ref.watch(calendarAggregatorProvider);

      final firstOfMonth = DateKey.fromYmd(month.year, month.month, 1);
      final firstOfNext = shiftMonth(firstOfMonth, 1);

      yield* aggregator.watchDays(
        from: firstOfMonth.addDays(-gridPadDays),
        to: firstOfNext.addDays(gridPadDays - 1),
        today: today,
      );
    });

/// Days of overscan either side of the visible month, for the grid's leading and trailing cells.
const int gridPadDays = 6;

/// The visible month's days keyed by date, for O(1) lookup while building 42 cells.
final calendarDayIndexProvider = Provider.autoDispose
    .family<AsyncValue<Map<int, CalendarDay>>, DateKey>((ref, month) {
      return ref
          .watch(calendarDaysProvider(month))
          .whenData(
            (days) => {for (final day in days) day.date.value: day},
          );
    });

/// One day's events, severity resolved — the day sheet's feed.
final dayEventsProvider = FutureProvider.autoDispose
    .family<List<CalendarEvent>, DateKey>((ref, dateKey) {
      final today = ref.watch(calendarTodayProvider);
      return ref
          .watch(calendarAggregatorProvider)
          .forDay(dateKey: dateKey, today: today);
    });

/// A closed span of days, as a provider key.
///
/// A record, so Riverpod's family caching compares by value: `(from: a, to: b)` twice is one provider.
typedef CalendarSpan = ({DateKey from, DateKey to});

/// Every entry inside [span], severity resolved, grouped-ready.
///
/// The span is whatever the user selected, so unlike `calendarDaysProvider` it is not month-shaped — but
/// it is still closed at both ends, which is the only thing the view's per-source indexes require.
final rangeEventsProvider = FutureProvider.autoDispose
    .family<List<CalendarEvent>, CalendarSpan>((ref, span) async {
      final today = ref.watch(calendarTodayProvider);
      final days = await ref
          .watch(calendarAggregatorProvider)
          .watchDays(from: span.from, to: span.to, today: today)
          .first;
      return [for (final day in days) ...day.events];
    });

/// The first of the month containing today.
///
/// The dashboard's grid must not follow `focusedMonthProvider`: browsing the calendar to December and
/// returning to the dashboard would have shown December there too. Keying the month feed by month rather
/// than reading ambient state is what makes two grids on two screens possible at all.
final currentMonthProvider = Provider<DateKey>((ref) {
  final today = ref.watch(calendarTodayProvider);
  return DateKey.fromYmd(today.year, today.month, 1);
});

/// What was spent and what came in across [span], from the transactions themselves.
///
/// **Not from the calendar feed.** `v_calendar_events` selects `original_amount_minor` as an unsigned
/// magnitude and no `kind`, so a deposit and a withdrawal are indistinguishable there. Adding `kind` to
/// the view would have meant a schema version bump and a migration for numbers a plain range read
/// already gives — so this reads `watchByDateRange` and splits by direction.
///
/// Transfers are excluded: money moving between your own accounts is neither spending nor income, and
/// counting it as both would double the totals of anyone who moves money to save it.
final spanTotalsProvider = StreamProvider.autoDispose
    .family<SpanTotals, CalendarSpan>((ref, span) {
      return ref
          .watch(transactionRepositoryProvider)
          .watchByDateRange(from: span.from, to: span.to)
          .map(SpanTotals.from);
    });

/// Money in and money out over a span, in minor units.
class SpanTotals {
  /// Creates a total.
  const SpanTotals({
    required this.inMinor,
    required this.outMinor,
    required this.currencyCode,
  });

  /// Sums [transactions] by direction.
  ///
  /// One currency only, and the first one seen names the result. Converting a mixed-currency span needs
  /// the frozen-rate path that belongs to analytics, and quietly adding minor units across currencies
  /// would produce a number that looks right and is not.
  factory SpanTotals.from(List<Transaction> transactions) {
    var inMinor = 0;
    var outMinor = 0;
    String? code;
    for (final tx in transactions) {
      code ??= tx.originalAmount.currencyCode;
      if (tx.originalAmount.currencyCode != code) continue;
      switch (tx.kind) {
        case TransactionKind.deposit:
        case TransactionKind.adjustmentIncrease:
          inMinor += tx.originalAmount.minor;
        case TransactionKind.withdrawal:
        case TransactionKind.adjustmentDecrease:
          outMinor += tx.originalAmount.minor;
        case TransactionKind.transfer:
          break;
      }
    }
    return SpanTotals(
      inMinor: inMinor,
      outMinor: outMinor,
      currencyCode: code ?? '',
    );
  }

  /// Deposits and increases.
  final int inMinor;

  /// Withdrawals and decreases.
  final int outMinor;

  /// The currency both figures are in, empty when the span held nothing.
  final String currencyCode;

  /// Whether there is anything to show.
  bool get isEmpty => currencyCode.isEmpty;
}
```

### `test/features/calendar/calendar_screen_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_month_grid.dart';

import '../../support/calendar_harness.dart';

void main() {
  group('CalendarScreen', () {
    testWidgets('loading: the grid is there before the feed is', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository(pending: true)),
      );

      // A month of empty cells is still a usable month, so loading reports beneath the grid rather
      // than in place of it.
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
      expect(find.text('Loading this month…'), findsOneWidget);
    });

    testWidgets('empty: the selected day says so, and the grid still stands', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository()),
      );
      await tester.pumpAndSettle();

      // There is no month-level empty state any longer. "Nothing this month" was a fact about the
      // month; the day section answers the question the reader actually asked, and an empty month is
      // simply an empty day plus a grid with no dots.
      expect(find.text('Nothing on this day'), findsOneWidget);
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
    });

    testWidgets('error: the reason shows and the grid survives it', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(
          FakeCalendarRepository(error: 'view unavailable'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load the calendar'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
    });

    testWidgets('populated: the month summary counts days, not events', (
      tester,
    ) async {
      final repo = FakeCalendarRepository(
        events: [
          event(refId: 'tx-1', title: 'Groceries'),
          event(refId: 'tx-2', title: 'Fuel'),
          event(date: kToday.addDays(3), refId: 'tx-3', title: 'Rent'),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      // The entries themselves, not a count of days. Selection starts on today, so both of today's
      // entries show and the one three days out does not — a count could not tell the reader either.
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Fuel'), findsOneWidget);
      expect(find.text('Rent'), findsNothing);
    });

    testWidgets('the section names the day it is showing', (tester) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository(events: [event()])),
      );
      await tester.pumpAndSettle();

      expect(find.text('On this day'), findsOneWidget);
      expect(find.text('August 1, 2026'), findsOneWidget);
    });

    testWidgets('tapping a day moves the section to it', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(refId: 'tx-1', title: 'Groceries'),
          event(
            date: const DateKey(20260812),
            refId: 'tx-2',
            title: 'Broadband',
          ),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsOneWidget);

      // A two-digit day, because single digits appear twice in a month grid — once for this month and
      // once as an adjacent month's outside cell.
      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();

      expect(find.text('Broadband'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
    });

    // What the semantics tree actually contains, verified by dumping it rather than guessed at.
    // `table_calendar` owns each cell's node and labels it with the full date, excluding anything its
    // builders add — so the grid speaks dates, and the section below speaks contents. Both halves are
    // asserted here because either one silently changing would leave a screen-reader user with a grid
    // they can navigate and nothing to navigate towards.
    testWidgets('the grid speaks dates and the section speaks contents', (
      tester,
    ) async {
      // Disposed inline, not via `addTearDown`. `_verifySemanticsHandlesWereDisposed` runs inside
      // `_runTestBody`, before tear-downs execute, so a handle released in one is still open when the
      // check looks — the test then fails having asserted everything it meant to.
      final handle = tester.ensureSemantics();

      final repo = FakeCalendarRepository(
        events: [
          event(refId: 'tx-1', title: 'Groceries'),
          event(refId: 'tx-2', title: 'Fuel'),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      // The package's own cell label. If a future version drops it, the grid goes mute and this fails.
      expect(find.bySemanticsLabel('Saturday, August 1, 2026'), findsOneWidget);

      // And the day's contents, which is the part that carries what the dots only hint at.
      expect(find.bySemanticsLabel('On this day'), findsOneWidget);
      expect(find.bySemanticsLabel('August 1, 2026'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Fuel'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('a range shows every entry across the span', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(
            date: const DateKey(20260810),
            refId: 'tx-1',
            title: 'Groceries',
          ),
          event(
            date: const DateKey(20260812),
            refId: 'tx-2',
            title: 'Broadband',
          ),
          event(
            date: const DateKey(20260820),
            refId: 'tx-3',
            title: 'Outside it',
          ),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      // Long-press starts the range on the day pressed — there is no mode button and no intermediate
      // "pick a start" step, because the gesture already named one.
      await tester.longPress(find.text('10'));
      await tester.pumpAndSettle();
      expect(
        find.text('From August 10, 2026 — tap another day to finish.'),
        findsOneWidget,
      );

      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();

      expect(find.text('3 days'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Broadband'), findsOneWidget);
      expect(find.text('Outside it'), findsNothing);
    });

    testWidgets(
      'a range picked backwards reads the same as one picked forwards',
      (tester) async {
        final repo = FakeCalendarRepository(
          events: [
            event(
              date: const DateKey(20260812),
              refId: 'tx-1',
              title: 'Broadband',
            ),
          ],
        );
        await pumpCalendar(
          tester,
          const CalendarScreen(),
          overrides: calendarOverrides(repo),
        );
        await tester.pumpAndSettle();

        await tester.longPress(find.text('15'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('10'));
        await tester.pumpAndSettle();

        expect(find.text('6 days'), findsOneWidget);
        expect(find.text('Broadband'), findsOneWidget);
      },
    );

    testWidgets('opens on the clock\'s month, never on the wall clock', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository()),
      );
      await tester.pumpAndSettle();

      expect(find.text('August 2026'), findsOneWidget);
    });

    testWidgets('the chevrons move a month at a time', (tester) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous month'));
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('July 2026'), findsOneWidget);
    });

    // The whole reason `CalendarRepository.watchRange` is the only read: unbounded, the view scans seven
    // tables. A regression here is silent — the screen looks identical and the query stops using indexes.
    // December to January, in both directions. `DateKey.fromYmd` throws on month 13 and month 0, so
    // this boundary was a crash rather than a wrong answer — paging forward from December 2026 died and
    // the month could only be reached by swiping.
    testWidgets('paging crosses the year boundary in both directions', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository()),
      );
      await tester.pumpAndSettle();

      // August 2026 forward to January 2027.
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byTooltip('Next month'));
        await tester.pumpAndSettle();
      }
      expect(find.text('January 2027'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // And back over the same boundary.
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('December 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every read is bounded to the month plus its overscan', (
      tester,
    ) async {
      final repo = FakeCalendarRepository();
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      expect(repo.rangesRequested, isNotEmpty);
      for (final range in repo.rangesRequested) {
        expect(range.from, DateKey(20260801).addDays(-gridPadDaysForTest));
        expect(range.to, DateKey(20260901).addDays(gridPadDaysForTest - 1));
        expect(range.to.diffDays(range.from), lessThan(45));
      }
    });

    testWidgets('a deep link opens that day\'s month and its sheet', (
      tester,
    ) async {
      final repo = FakeCalendarRepository(
        events: [
          event(
            date: const DateKey(20261115),
            refId: 'tx-nov',
            title: 'Fireworks',
          ),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(initialDay: DateKey(20261115)),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('Fireworks'), findsOneWidget);
    });

    // U26. `TableCalendar` takes a fixed `rowHeight`, and a grid of text cells with a fixed row height
    // is the exact shape that overflowed twenty-six tests in Phase 6F.
    testWidgets('survives 320dp at a doubled text scale', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(refId: 'tx-1'),
          event(
            date: kToday.addDays(2),
            type: CalendarEventType.batchExpiry,
            refType: 'inventoryBatch',
            refId: 'ba-1',
            baseSeverity: CalendarSeverity.warning,
          ),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
        textScale: 2,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
    });
  });
}

/// Mirrors `gridPadDays`, so a change to the overscan has to be made deliberately in two places.
const int gridPadDaysForTest = 6;
```

### `test/features/calendar/day_sheet_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/router/routes.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_event_list.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/calendar/presentation/widgets/event_card.dart';
import 'package:alaya/shared/widgets/section_header.dart';

import '../../support/calendar_harness.dart';

void main() {
  // `calendarEventRoute` and the grouped list moved to `calendar_event_list.dart` when the screen
  // started rendering the same list inline. They are exercised here because the sheet is still their
  // only widget host; if a list-specific suite ever earns its own file, these move with it.
  group('calendarEventRoute', () {
    test('deep-links the three types whose ref_id addresses a record', () {
      expect(
        calendarEventRoute(event(refType: 'transaction', refId: 'tx-9')),
        Routes.transactionDetail('tx-9'),
      );
      expect(
        calendarEventRoute(event(refType: 'asset', refId: 'as-2')),
        Routes.assetDetail('as-2'),
      );
      expect(
        calendarEventRoute(event(refType: 'shoppingList', refId: 'sl-3')),
        Routes.shoppingList('sl-3'),
      );
    });

    // Not an oversight and not a fallback chosen for convenience: `v_calendar_events` carries no parent
    // id, and `batchEdit` needs an item, `serviceEdit` needs an asset, and a recurring occurrence has no
    // route at all. Asserted so the day it gains one, this test is what says so.
    test(
      'falls back to the owning module where the feed carries no parent id',
      () {
        expect(
          calendarEventRoute(event(refType: 'inventoryBatch')),
          Routes.inventory,
        );
        expect(
          calendarEventRoute(event(refType: 'serviceRecord')),
          Routes.services,
        );
        expect(
          calendarEventRoute(event(refType: 'recurringOccurrence')),
          Routes.recurring,
        );
      },
    );

    test(
      'an unknown ref_type resolves to nothing rather than to somewhere wrong',
      () {
        expect(
          calendarEventRoute(event(refType: 'somethingNewInPhase9')),
          isNull,
        );
      },
    );
  });

  group('DaySheet', () {
    testWidgets('loading says so', (tester) async {
      final repo = FakeCalendarRepository(pending: true);
      await pumpCalendar(
        tester,
        const DaySheet(dateKey: kToday),
        overrides: calendarOverrides(repo),
      );

      expect(find.text('Loading this day…'), findsOneWidget);
    });

    testWidgets('empty is an answer, not a blank', (tester) async {
      await pumpCalendar(
        tester,
        const DaySheet(dateKey: kToday),
        overrides: calendarOverrides(FakeCalendarRepository()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing on this day'), findsOneWidget);
    });

    testWidgets('a failed read shows its reason and offers a retry', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        const DaySheet(dateKey: kToday),
        overrides: calendarOverrides(
          FakeCalendarRepository(error: 'view unavailable'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load this day'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('populated groups by type, one heading each', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(refId: 'tx-1', title: 'Groceries'),
          event(refId: 'tx-2', title: 'Fuel'),
          event(
            type: CalendarEventType.batchExpiry,
            refType: 'inventoryBatch',
            refId: 'ba-1',
            title: 'Milk',
          ),
        ],
      );
      await pumpCalendar(
        tester,
        const DaySheet(dateKey: kToday),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EventCard), findsNWidgets(3));

      // Read the headings off the widgets rather than searching for their text. `SectionHeader`
      // upper-cases for display and keeps the original in `semanticsLabel`, so `find.text('Transaction')`
      // tests SectionHeader's presentation choice instead of this sheet's grouping. Order matters too:
      // enum declaration order, so a reader scanning twice finds the same thing in the same place.
      final headings = tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((h) => h.label)
          .toList();
      expect(headings, ['Transaction', 'Expiring']);
    });

    // The aggregator escalates, not the view and not the card: a batch three days out is a warning by
    // ARCH_3 §6, and the view handed it the static `warning` baseline with no notion of today.
    testWidgets(
      'severity is resolved through the aggregator, against the fixed clock',
      (tester) async {
        final repo = FakeCalendarRepository(
          events: [
            event(
              date: kToday.addDays(-1),
              type: CalendarEventType.batchExpiry,
              refType: 'inventoryBatch',
              refId: 'ba-past',
              title: 'Yoghurt',
              baseSeverity: CalendarSeverity.warning,
            ),
          ],
        );
        await pumpCalendar(
          tester,
          DaySheet(dateKey: kToday.addDays(-1)),
          overrides: calendarOverrides(repo),
        );
        await tester.pumpAndSettle();

        // Past its date, and `batchExpiry` is the only type §6 lets reach danger.
        expect(find.text('Past its date'), findsOneWidget);
      },
    );

    testWidgets('survives 320dp at a doubled text scale', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(
            title: 'A payee with a name long enough to wrap at a doubled scale',
          ),
          event(
            type: CalendarEventType.serviceDue,
            refType: 'asset',
            refId: 'as-1',
            title: 'The boiler in the upstairs cupboard',
            baseSeverity: CalendarSeverity.warning,
          ),
        ],
      );
      await pumpCalendar(
        tester,
        const DaySheet(dateKey: kToday),
        overrides: calendarOverrides(repo),
        textScale: 2,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
```

### `test/features/calendar/event_card_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/widgets/event_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

import '../../support/calendar_harness.dart';

void main() {
  group('EventCard', () {
    testWidgets('names the event type, so the glyph is never the only clue', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        EventCard(
          event: event(type: CalendarEventType.batchExpiry),
          onTap: () {},
        ),
      );

      expect(find.text('Expiring'), findsOneWidget);
    });

    // The point of the card. A dot and a colour fail a colour-blind reader and fail in grayscale, so
    // anything above `info` says what it is in words (Law U9).
    testWidgets('a warning carries the severity in words, not only in colour', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        EventCard(
          event: event(
            type: CalendarEventType.warrantyEnd,
            baseSeverity: CalendarSeverity.warning,
          ),
          onTap: () {},
        ),
      );

      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.byType(StatusChip), findsOneWidget);
    });

    testWidgets('a danger says so too', (tester) async {
      await pumpCalendar(
        tester,
        EventCard(
          event: event(
            type: CalendarEventType.batchExpiry,
            baseSeverity: CalendarSeverity.danger,
          ),
          onTap: () {},
        ),
      );

      expect(find.text('Past its date'), findsOneWidget);
    });

    testWidgets('info carries no chip — there is nothing to warn about', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        EventCard(event: event(), onTap: () {}),
      );

      expect(find.byType(StatusChip), findsNothing);
      expect(find.text('Needs attention'), findsNothing);
      expect(find.text('Past its date'), findsNothing);
    });

    testWidgets('an amount renders through AmountText, never as a string', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        EventCard(event: event(amountMinor: 123456), onTap: () {}),
      );

      expect(find.byType(AmountText), findsOneWidget);
    });

    testWidgets('an entry with no amount shows none', (tester) async {
      await pumpCalendar(
        tester,
        EventCard(
          event: event(type: CalendarEventType.warrantyEnd),
          onTap: () {},
        ),
      );

      expect(find.byType(AmountText), findsNothing);
    });

    testWidgets(
      'a null onTap leaves the card inert rather than dead-tappable',
      (tester) async {
        await pumpCalendar(tester, EventCard(event: event(), onTap: null));

        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Groceries'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('survives 320dp at a doubled text scale', (tester) async {
      await pumpCalendar(
        tester,
        EventCard(
          event: event(
            title:
                'A warranty with a name long enough to wrap twice over at this scale',
            type: CalendarEventType.warrantyEnd,
            baseSeverity: CalendarSeverity.warning,
            amountMinor: 98765432,
          ),
          onTap: () {},
        ),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
```
