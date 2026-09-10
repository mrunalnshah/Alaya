import 'dart:async';
import 'package:alaya/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';
import 'package:alaya/features/dashboard/providers/range_providers.dart';
import 'package:alaya/features/dashboard/state/insight_side.dart';

/// One thing that needs attention, and when.
class UpcomingEntry {
  /// Creates an entry.
  const UpcomingEntry({
    required this.kind,
    required this.title,
    required this.dueDateKey,
    this.route,
  });

  /// Which sort of obligation this is, which decides its wording and glyph.
  final UpcomingKind kind;

  /// What it is called.
  final String title;

  /// When it falls due.
  final DateKey dueDateKey;

  /// Where tapping it goes, when there is somewhere useful.
  final String? route;

  /// Whether it is already past its date, derived from the clock and never stored (ARCH_2 §12.2).
  bool isOverdue(DateKey today) => dueDateKey < today;
}

/// The four sorts of thing the upcoming side collects.
enum UpcomingKind {
  /// A recurring occurrence that is due.
  bill,

  /// An asset whose service interval has come round.
  service,

  /// A warranty about to lapse.
  warranty,

  /// A batch at or near its expiry date.
  batch,
}

/// How far ahead the upcoming side looks.
///
/// A fortnight: long enough that a monthly bill appears before it is late, short enough that the card
/// stays a shortlist rather than a second ledger.
const int upcomingHorizonDays = 14;

/// Spend by kind over the dashboard's own thirty-day window — the insight card's spending side.
///
/// **Added in Phase 7B, which closed the gap this side was built around.** 6F shipped it as an inline
/// empty state naming what it waited for, because `AnalyticsService` had no `AnalyticsPort` adapter and
/// aggregating spending in the dashboard would have left 7B a competing implementation to reconcile
/// (ARCH_4 P7, ARCH_5 §7). The adapter now exists, so the side reads the engine.
///
/// **Its own window, not the analytics screen's.** `last30Provider` is fixed; `analyticsWindowProvider`
/// follows a chip the user last touched on another screen. Sharing it would make the dashboard change
/// when nothing on the dashboard was touched.
final spendingInsightProvider = FutureProvider<Concentration>((ref) async {
  final service = await ref.watch(analyticsServiceProvider.future);
  return service.categoryConcentration(ref.watch(last30Provider));
});

/// Which face of the insight card is showing, restored from `app_settings`.
final insightSideProvider = NotifierProvider<InsightSideNotifier, InsightSide>(
  InsightSideNotifier.new,
);

/// Holds and persists the insight card's side.
class InsightSideNotifier extends Notifier<InsightSide> {
  @override
  InsightSide build() {
    unawaited(_restore());
    return InsightSide.upcoming;
  }

  Future<void> _restore() async {
    final stored = await ref
        .read(settingsRepositoryProvider)
        .readValue(InsightSide.settingsKey);
    final restored = InsightSide.parse(stored);
    if (restored != state) state = restored;
  }

  /// Shows [side] and remembers it.
  ///
  /// The write is not awaited: the card should flip on the frame the user taps, and a settings row that
  /// lands a millisecond later changes nothing they can see.
  void show(InsightSide side) {
    state = side;
    unawaited(
      ref
          .read(settingsRepositoryProvider)
          .writeValue(
            key: InsightSide.settingsKey,
            value: side.stored,
            // `app_settings` stores its own type alongside the value, and every row this app writes is a
            // string. An enum's name is a string; declaring it anything else would be a claim the reader
            // has to unpick.
            valueType: 'string',
          ),
    );
  }
}

/// Everything falling due inside [upcomingHorizonDays], soonest first.
///
/// **Now `CalendarAggregator`, which is what the previous version said it could not be.** It read four
/// repositories directly because `CalendarRepository` had no implementation until Phase 7A
/// (ARCH_4 §5.1 item 15); it does now, so the stand-in retires rather than drifting alongside the real
/// engine. Three things were wrong with it, and none were visible from here:
///
/// 1. Its own doc comment claimed five reads including `ServiceRecordRepository.watchWithNextDueInRange`.
///    The body performed four and never called it, so a service due recorded against a **service record**
///    rather than against the asset never reached this card (ARCH_6 P18 — a comment asserting what the
///    code does not do).
/// 2. Batches were titled `batch.id`, so an expiring item showed a **UUID** where the calendar, whose
///    view `COALESCE`s the item name, showed "Yoghurt".
/// 3. Severity was nobody's job here. `CalendarAggregator` applies ARCH_3 §6's per-type thresholds
///    against the injected clock, so "needs attention" now means the same thing on both screens.
///
/// **Transactions and shopping targets are filtered out, deliberately.** Every kind this card carries is
/// consequential if ignored: a bill goes late, a service lapses, a warranty dies, food spoils. A past
/// transaction is not an obligation, and a shopping target is self-imposed — missing it costs nothing,
/// and a weekly shop would land in almost every fortnight, so it would be the one row always present and
/// therefore the one carrying no signal. The calendar is where plans belong; this card is for obligations.
final upcomingProvider = FutureProvider.autoDispose<List<UpcomingEntry>>((
  ref,
) async {
  // The same materialisation the calendar waits on. Without it this card cannot show a bill that is
  // not already overdue, which was true of the version it replaced too.
  await ref.watch(recurringHorizonProvider.future);

  final today = ref.watch(clockProvider).today();
  final horizon = today.addDays(upcomingHorizonDays);

  // A year back, not `DateRangeFloor.past`. Overdue still matters more than upcoming, but a floor in
  // 1900 makes the range nominally bounded and practically a full scan of seven tables — and nothing
  // outstanding for over a year is going to be actioned from a fortnight's shortlist.
  final days = await ref
      .watch(calendarAggregatorProvider)
      .watchDays(
        from: today.addDays(-overdueLookbackDays),
        to: horizon,
        today: today,
      )
      .first;

  final entries = <UpcomingEntry>[];
  for (final day in days) {
    for (final event in day.events) {
      final kind = _kindOf(event.type);
      if (kind == null) continue;
      entries.add(
        UpcomingEntry(
          kind: kind,
          title: event.title,
          dueDateKey: event.dateKey,
        ),
      );
    }
  }

  entries.sort((a, b) => a.dueDateKey.compareTo(b.dueDateKey));
  return entries;
});

/// The [UpcomingKind] for [type], or null where the type is not an obligation.
UpcomingKind? _kindOf(CalendarEventType type) => switch (type) {
  CalendarEventType.recurringDue => UpcomingKind.bill,
  CalendarEventType.serviceDue => UpcomingKind.service,
  CalendarEventType.warrantyEnd => UpcomingKind.warranty,
  CalendarEventType.batchExpiry => UpcomingKind.batch,
  CalendarEventType.transaction => null,
  CalendarEventType.shoppingTarget => null,
  // **Null, like the two above, and it is a decision rather than an oversight.** A settle-by date is a
  // real obligation, so the tempting move is a fifth `UpcomingKind` — but that enum is rendered by its
  // own label and icon switches, so one member here cascades into three more files for a card the split
  // module is getting anyway. Its own dashboard card, showing net owed and the oldest unsettled debt,
  // says more than one row on a list of bills would.
  CalendarEventType.splitSettleBy => null,
};

/// How far back the card reaches for things still outstanding.
const int overdueLookbackDays = 365;

/// The lower bound for a read that should include things already overdue.
///
/// Overdue matters more than upcoming, so the floor reaches back rather than starting at today — a
/// service three weeks late must not fall off the card for being too late.
abstract final class DateRangeFloor {
  /// Far enough back to catch anything still outstanding.
  static final DateKey past = DateKey.fromYmd(1900, 1, 1);
}
