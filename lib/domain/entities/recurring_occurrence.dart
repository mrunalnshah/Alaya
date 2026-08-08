import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// One dated instance of a `RecurringTemplate` — the third of the app's three append-only truths
/// (ARCH_1 §3.3).
///
/// Materialised lazily up to today, never in advance and never automatically settled: money is
/// only ever created by an explicit user tap (anomaly A14).
class RecurringOccurrence {
  /// Creates an occurrence.
  const RecurringOccurrence({
    required this.id,
    required this.templateId,
    required this.dueDateKey,
    required this.status,
    this.paidTransactionId,
    this.paidAmount,
    this.paidDateKey,
    this.note,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// The template this instance belongs to.
  final String templateId;

  /// The civil date this instance is due on.
  final DateKey dueDateKey;

  /// Settlement state. Never `paid` without [paidTransactionId].
  final RecurringOccurrenceStatus status;

  /// The transaction that settled this occurrence.
  final String? paidTransactionId;

  /// The amount actually paid, which may differ from the template's default. Analytics uses this
  /// rather than the default (anomaly A29).
  final Money? paidAmount;

  /// The civil date it was actually paid on, which may differ from [dueDateKey].
  final DateKey? paidDateKey;

  /// Optional free-text note.
  final String? note;

  /// True when this occurrence is still outstanding.
  bool get isOutstanding => status == RecurringOccurrenceStatus.due;

  /// True when this occurrence has been settled.
  bool get isPaid => status == RecurringOccurrenceStatus.paid;

  /// True when this occurrence is still due and its date has passed as of [today].
  ///
  /// **Derived, never stored** — ARCH_2 §7.2's requirement, and the reason `v_recurring_due` has no
  /// `is_overdue` column. Takes [today] rather than reading a clock so it stays deterministic under
  /// a `FixedClock`, the same rule the views follow (ARCH_2 §12.2).
  bool isOverdue(DateKey today) => isOutstanding && dueDateKey < today;

  /// Days from [today] until due — negative once overdue.
  int daysUntilDue(DateKey today) => dueDateKey.diffDays(today);

  /// True when this occurrence falls due within [days] of [today], already-overdue included.
  bool isDueWithin(DateKey today, int days) => dueDateKey.diffDays(today) <= days;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  RecurringOccurrence copyWith({
    String? id,
    String? templateId,
    DateKey? dueDateKey,
    RecurringOccurrenceStatus? status,
    String? paidTransactionId,
    Money? paidAmount,
    DateKey? paidDateKey,
    String? note,
  }) {
    return RecurringOccurrence(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      dueDateKey: dueDateKey ?? this.dueDateKey,
      status: status ?? this.status,
      paidTransactionId: paidTransactionId ?? this.paidTransactionId,
      paidAmount: paidAmount ?? this.paidAmount,
      paidDateKey: paidDateKey ?? this.paidDateKey,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecurringOccurrence &&
          other.id == id &&
          other.templateId == templateId &&
          other.dueDateKey == dueDateKey &&
          other.status == status &&
          other.paidTransactionId == paidTransactionId &&
          other.paidAmount == paidAmount &&
          other.paidDateKey == paidDateKey &&
          other.note == note;

  @override
  int get hashCode => Object.hashAll([
    id, templateId, dueDateKey, status, paidTransactionId, paidAmount,
    paidDateKey, note,
  ]);

  @override
  String toString() => 'RecurringOccurrence($id, ${dueDateKey.toIso()}, ${status.name})';
}