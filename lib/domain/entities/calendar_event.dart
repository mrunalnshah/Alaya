import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// What kind of thing a calendar entry represents (ARCH_3 §6).
///
/// Declared here rather than in `core/enums/` because these values are never stored: the
/// `v_calendar_events` view computes them, so Law L13's "renaming an enum value is a breaking
/// migration" does not apply.
enum CalendarEventType {
  /// A recorded transaction.
  transaction,

  /// A recurring obligation that is due.
  recurringDue,

  /// An inventory batch reaching its expiry.
  batchExpiry,

  /// An asset's warranty ending.
  warrantyEnd,

  /// An asset's next service falling due.
  serviceDue,

  /// A shopping list's target date.
  shoppingTarget,

  /// A shared expense with a settle-by date.
  ///
  /// **The deadline, not the expense.** When the user paid, the bill already reaches this feed through
  /// its own `transactions` row; carrying it twice would show one dinner as two entries on two days.
  ///
  /// Declared last on purpose. The day sheet groups by `CalendarEventType.values`, so declaration order
  /// is display order — and a deadline belongs after the things that have already happened.
  splitSettleBy,
}

/// How urgently a calendar entry should read.
enum CalendarSeverity {
  /// Informational — it happened, or it is simply scheduled.
  info,

  /// Approaching and worth attention.
  warning,

  /// Already past its date.
  danger,
}

/// One entry in the unified calendar feed.
///
/// Read-only: it comes from `v_calendar_events`, a `UNION ALL` view rather than a physical table,
/// so there is no synchronisation code to get wrong (anomaly A37).
class CalendarEvent {
  /// Creates a calendar entry.
  const CalendarEvent({
    required this.dateKey,
    required this.type,
    required this.refType,
    required this.refId,
    required this.title,
    required this.baseSeverity,
    this.amount,
  });

  /// The civil date this entry falls on.
  final DateKey dateKey;

  /// What kind of thing this is.
  final CalendarEventType type;

  /// Which kind of record [refId] names, e.g. `transaction`, `inventoryBatch`.
  final String refType;

  /// The owning record's id, for navigation.
  final String refId;

  /// What to show on the card.
  final String title;

  /// The static baseline severity the view emits.
  ///
  /// Resolve it through `CalendarAggregator.severityFor` before display. The view never consults the
  /// clock (ARCH_2 §12.2) and the escalation thresholds differ per type (ARCH_3 §6), so neither the
  /// view nor this entity can answer what an entry should look like today.
  final CalendarSeverity baseSeverity;

  /// The amount, where the entry has one — transactions and recurring dues do, expiries do not.
  final Money? amount;

  /// Days from [today] until this entry — negative once past.
  int daysAwayFrom(DateKey today) => dateKey.diffDays(today);

  /// True when this entry's date has already passed as of [today].
  bool isPast(DateKey today) => dateKey < today;

  @override
  bool operator ==(Object other) =>
      other is CalendarEvent &&
      other.dateKey == dateKey &&
      other.type == type &&
      other.refType == refType &&
      other.refId == refId &&
      other.title == title &&
      other.baseSeverity == baseSeverity &&
      other.amount == amount;

  @override
  int get hashCode => Object.hashAll([
    dateKey,
    type,
    refType,
    refId,
    title,
    baseSeverity,
    amount,
  ]);

  @override
  String toString() =>
      'CalendarEvent(${type.name} $refId on ${dateKey.toIso()})';
}
