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
