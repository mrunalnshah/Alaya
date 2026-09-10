import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_month_grid.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';

/// This month at a glance. Each day opens its entries in a sheet — where the day is big enough to hit.
///
/// **The interaction is measured, not assumed.** Seven columns need 336dp to give every day the 48dp
/// tap-target floor, and this card's inner width is the screen minus 64dp of padding. So a 320dp phone
/// yields 36.6dp per day and a 412dp phone yields 49.7dp: the same widget is compliant on one and not on
/// the other. Rather than ship undersized targets everywhere or drop the feature everywhere, the grid
/// asks its own constraints:
///
/// * **48dp or more per cell** — every day is tappable and opens `DaySheet`.
/// * **less than that** — the days go inert (`IgnorePointer` removes the gestures, `ExcludeSemantics` the
///   undersized nodes) and the whole card becomes one large target that opens the calendar screen, which
///   has the room to do this properly.
///
/// That is why the dashboard's `androidTapTargetGuideline` test passes at 320dp with no exclusion: at
/// that width there are genuinely no small targets, rather than small targets the test agreed to ignore.
/// Suppressing the check would have hidden a real defect on exactly the phones least able to afford it.
///
/// `DaySheet` is the same sheet the calendar's deep link opens, so a day reads identically wherever it is
/// reached from. Ranges and month paging stay on the full screen.
///
/// Dots only in the grid itself: "Coming Up" sits directly below this card, and repeating the same events
/// as cards would say the same thing twice in one scroll. What the grid adds is shape — which days have
/// something on them — which no list conveys.
class DashboardCalendar extends ConsumerWidget {
  /// Creates the section.
  const DashboardCalendar({super.key});

  /// The Android tap-target floor, below which a day cell stops accepting taps.
  static const double _tapTargetFloor = 48;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    // `currentMonthProvider`, never `focusedMonthProvider`: this grid must not follow wherever the
    // calendar screen was last left, or returning from December would show December here.
    final month = ref.watch(currentMonthProvider);
    final today = ref.watch(calendarTodayProvider);
    final index = ref.watch(calendarDayIndexProvider(month));
    final label = DateFormat.yMMMM(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(month.toUtcMidnight());

    return LayoutBuilder(
      builder: (context, constraints) {
        // The width the grid will actually hand each of its seven columns.
        final cellWidth =
            (constraints.maxWidth - 2 * AlayaSpacing.md) / DateTime.daysPerWeek;
        final tappable = cellWidth >= _tapTargetFloor;

        final grid = CalendarMonthGrid(
          month: month,
          today: today,
          daysByKey: index.valueOrNull ?? const <int, CalendarDay>{},
          selected: today,
          onDaySelected: (day) => DaySheet.show(context: context, dateKey: day),
          // A long-press starts a range on the full screen; here there is nowhere to show one, so it
          // opens the same sheet. One gesture, one outcome, no hidden mode.
          onDayLongPressed: (day) =>
              DaySheet.show(context: context, dateKey: day),
          // Nothing to change to: the grid is bounded to this month and its gestures are off.
          onMonthChanged: (_) {},
          lockedToMonth: true,
        );

        final card = AlayaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                style: AlayaTypography.cardTitle.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AlayaSpacing.xs),
              if (tappable)
                grid
              else
                IgnorePointer(child: ExcludeSemantics(child: grid)),
              // Full width and free to wrap. Beside the month title this button wanted 435dp of the 256
              // available at a doubled text scale — the 179dp of overflow the dashboard's layout test
              // reported (Law U21).
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => context.push(Routes.calendar),
                  icon: const Icon(Icons.open_in_new, size: AlayaIconSize.sm),
                  label: Text(strings.dashboardOpenCalendar),
                ),
              ),
            ],
          ),
        );

        // Narrow: the card itself is the target, so the month is still one tap from being explored.
        if (tappable) return card;
        return Semantics(
          container: true,
          button: true,
          label: strings.dashboardCalendarSemantics(label),
          child: InkWell(
            onTap: () => context.push(Routes.calendar),
            child: card,
          ),
        );
      },
    );
  }
}
