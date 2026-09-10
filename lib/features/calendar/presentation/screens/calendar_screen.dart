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
