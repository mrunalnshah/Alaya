import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// A repeating obligation or income.
///
/// [direction] is what lets salary live in the same system as bills rather than needing a second,
/// parallel one (anomaly A27).
class RecurringTemplate {
  /// Creates a template.
  const RecurringTemplate({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.kind,
    required this.direction,
    required this.defaultAmount,
    required this.intervalUnit,
    required this.intervalCount,
    required this.startDateKey,
    required this.nextDueDateKey,
    required this.isPaused,
    required this.autoRemind,
    required this.remindDaysBefore,
    this.payeeId,
    this.defaultAccountId,
    this.defaultPaymentMethodId,
    this.tagId,
    this.anchorDayOfMonth,
    this.anchorMonth,
    this.anchorWeekday,
    this.endDateKey,
    this.linkedAssetId,
    this.note,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name as the user typed it.
  final String name;

  /// Normalised form used for identity matching only, never displayed.
  final String normalizedName;

  /// Rough classification, for grouping and iconography.
  final RecurringKind kind;

  /// Whether settling an occurrence creates a withdrawal or a deposit.
  final RecurringDirection direction;

  /// The usual amount. An occurrence may be settled for a different one, recorded on the
  /// occurrence rather than overwriting this (anomaly A29).
  final Money defaultAmount;

  /// The unit the repeat interval is counted in.
  final RecurringIntervalUnit intervalUnit;

  /// How many [intervalUnit]s between occurrences.
  final int intervalCount;

  /// First civil date this template is active from.
  final DateKey startDateKey;

  /// The next civil date an occurrence is due on.
  final DateKey nextDueDateKey;

  /// Suspended without being deleted; no new occurrences materialise.
  final bool isPaused;

  /// Whether to schedule a local notification before each due date.
  final bool autoRemind;

  /// How many days before the due date to remind.
  final int remindDaysBefore;

  /// Who is billed, or who pays.
  final String? payeeId;

  /// The account settlement defaults to.
  final String? defaultAccountId;

  /// The rail settlement defaults to.
  final String? defaultPaymentMethodId;

  /// The tag applied to transactions this template creates.
  final String? tagId;

  /// Day of month, 1-31, for monthly and yearly intervals.
  ///
  /// **Stored once and clamped at render, never rewritten** (anomaly A13). A bill anchored on the
  /// 31st renders as 28, 29 or 30 in short months but stays anchored on the 31st — write the
  /// clamped value back and it walks permanently backwards after one February. Use
  /// [clampedDayFor] to render it.
  final int? anchorDayOfMonth;

  /// Month of year, 1-12, for yearly intervals.
  final int? anchorMonth;

  /// ISO weekday, 1-7, for weekly intervals.
  final int? anchorWeekday;

  /// Last civil date this template is active until, or null for indefinite.
  final DateKey? endDateKey;

  /// The asset this template pays for — the link that hangs a house maid's monthly salary off an
  /// `Asset` row.
  final String? linkedAssetId;

  /// Optional free-text note.
  final String? note;

  /// True when this template creates a withdrawal on settlement.
  bool get isOutflow => direction == RecurringDirection.outflow;

  /// True when this template has an end date that [today] has passed.
  bool hasEnded(DateKey today) {
    final end = endDateKey;
    return end != null && end < today;
  }

  /// True when this template should currently be materialising occurrences.
  bool isActiveAsOf(DateKey today) =>
      !isPaused && !hasEnded(today) && !startDateKey.isAfter(today);

  /// [anchorDayOfMonth] clamped into the given month's real length.
  ///
  /// The render-time half of anomaly A13: an anchor of 31 returns 28 for a non-leap February, 29
  /// for a leap one, 30 for April. Returns null when no day-of-month anchor is set.
  int? clampedDayFor({required int year, required int month}) {
    final anchor = anchorDayOfMonth;
    if (anchor == null) return null;
    final lastDayOfMonth = DateTime.utc(year, month + 1, 0).day;
    return anchor < lastDayOfMonth ? anchor : lastDayOfMonth;
  }

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  RecurringTemplate copyWith({
    String? id,
    String? name,
    String? normalizedName,
    RecurringKind? kind,
    RecurringDirection? direction,
    Money? defaultAmount,
    RecurringIntervalUnit? intervalUnit,
    int? intervalCount,
    DateKey? startDateKey,
    DateKey? nextDueDateKey,
    bool? isPaused,
    bool? autoRemind,
    int? remindDaysBefore,
    String? payeeId,
    String? defaultAccountId,
    String? defaultPaymentMethodId,
    String? tagId,
    int? anchorDayOfMonth,
    int? anchorMonth,
    int? anchorWeekday,
    DateKey? endDateKey,
    String? linkedAssetId,
    String? note,
  }) {
    return RecurringTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      kind: kind ?? this.kind,
      direction: direction ?? this.direction,
      defaultAmount: defaultAmount ?? this.defaultAmount,
      intervalUnit: intervalUnit ?? this.intervalUnit,
      intervalCount: intervalCount ?? this.intervalCount,
      startDateKey: startDateKey ?? this.startDateKey,
      nextDueDateKey: nextDueDateKey ?? this.nextDueDateKey,
      isPaused: isPaused ?? this.isPaused,
      autoRemind: autoRemind ?? this.autoRemind,
      remindDaysBefore: remindDaysBefore ?? this.remindDaysBefore,
      payeeId: payeeId ?? this.payeeId,
      defaultAccountId: defaultAccountId ?? this.defaultAccountId,
      defaultPaymentMethodId: defaultPaymentMethodId ?? this.defaultPaymentMethodId,
      tagId: tagId ?? this.tagId,
      anchorDayOfMonth: anchorDayOfMonth ?? this.anchorDayOfMonth,
      anchorMonth: anchorMonth ?? this.anchorMonth,
      anchorWeekday: anchorWeekday ?? this.anchorWeekday,
      endDateKey: endDateKey ?? this.endDateKey,
      linkedAssetId: linkedAssetId ?? this.linkedAssetId,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecurringTemplate &&
          other.id == id &&
          other.name == name &&
          other.normalizedName == normalizedName &&
          other.kind == kind &&
          other.direction == direction &&
          other.defaultAmount == defaultAmount &&
          other.intervalUnit == intervalUnit &&
          other.intervalCount == intervalCount &&
          other.startDateKey == startDateKey &&
          other.nextDueDateKey == nextDueDateKey &&
          other.isPaused == isPaused &&
          other.autoRemind == autoRemind &&
          other.remindDaysBefore == remindDaysBefore &&
          other.payeeId == payeeId &&
          other.defaultAccountId == defaultAccountId &&
          other.defaultPaymentMethodId == defaultPaymentMethodId &&
          other.tagId == tagId &&
          other.anchorDayOfMonth == anchorDayOfMonth &&
          other.anchorMonth == anchorMonth &&
          other.anchorWeekday == anchorWeekday &&
          other.endDateKey == endDateKey &&
          other.linkedAssetId == linkedAssetId &&
          other.note == note;

  @override
  int get hashCode => Object.hashAll([
    id, name, normalizedName, kind, direction, defaultAmount, intervalUnit,
    intervalCount, startDateKey, nextDueDateKey, isPaused, autoRemind,
    remindDaysBefore, payeeId, defaultAccountId, defaultPaymentMethodId, tagId,
    anchorDayOfMonth, anchorMonth, anchorWeekday, endDateKey, linkedAssetId, note,
  ]);

  @override
  String toString() => 'RecurringTemplate($id, $name, ${direction.name})';
}