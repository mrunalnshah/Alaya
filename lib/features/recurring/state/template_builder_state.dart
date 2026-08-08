import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_template.dart';

/// Why a template save was refused, when it was refused for a reason worth naming.
enum TemplateSaveIssue {
  /// The name was blank.
  nameMissing,

  /// The default amount was missing or not positive.
  amountMissing,

  /// A monthly or yearly template with no day to anchor to.
  anchorMissing,

  /// The write failed for a reason the repository named.
  rejected,
}

/// Everything the template builder is holding (ARCH_5 §3 archetype B).
class TemplateBuilderState {
  /// Creates the builder's state.
  const TemplateBuilderState({
    required this.currencyCode,
    required this.startDateKey,
    this.id,
    this.name = '',
    this.kind = RecurringKind.bill,
    this.direction = RecurringDirection.outflow,
    this.amount,
    this.intervalUnit = RecurringIntervalUnit.month,
    this.intervalCount = 1,
    this.anchorDayOfMonth,
    this.endDateKey,
    this.payeeId,
    this.accountId,
    this.tagId,
    this.remindDaysBefore = 3,
    this.autoRemind = true,
    this.isPaused = false,
    this.note,
    this.submitting = false,
    this.issue,
    this.rejection,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// The template being edited, or null for a new one.
  final String? id;

  /// What to call it.
  final String name;

  /// Bill, subscription, rent or salary.
  final RecurringKind kind;

  /// Whether money leaves or arrives.
  ///
  /// Drives the whole module's wording: an inflow salary is income, never a negative bill.
  final RecurringDirection direction;

  /// The currency amounts are entered in.
  final String currencyCode;

  /// What it usually costs. A default the pay sheet pre-fills, never a fixed figure.
  final Money? amount;

  /// Days, weeks, months or years.
  final RecurringIntervalUnit intervalUnit;

  /// How many of them.
  final int intervalCount;

  /// The day of the month it anchors to.
  ///
  /// Stored once and clamped at every render, never advanced (anomaly A13). Required for a monthly or
  /// yearly template, which is what stops a February settlement dragging every later occurrence back
  /// to the 28th permanently.
  final int? anchorDayOfMonth;

  /// When it starts.
  final DateKey startDateKey;

  /// When it stops, if it does.
  final DateKey? endDateKey;

  /// Who it is paid to, or received from.
  final String? payeeId;

  /// Which account the pay sheet should default to.
  final String? accountId;

  /// The tag every generated transaction carries.
  final String? tagId;

  /// How many days of warning Phase 8B should give.
  final int remindDaysBefore;

  /// Whether to remind at all.
  final bool autoRemind;

  /// Whether it is currently paused.
  final bool isPaused;

  /// Free note.
  final String? note;

  /// Whether a save is in flight.
  final bool submitting;

  /// Why the last save was refused, or null if it was not.
  final TemplateSaveIssue? issue;

  /// The repository's own message when it rejected the write.
  final String? rejection;

  /// Incremented to shake the offending field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (Law U10).
  final bool dirty;

  /// Whether this is editing an existing template.
  bool get isEditing => id != null;

  /// Whether the interval is anchored to a day of the month.
  bool get needsDayAnchor =>
      intervalUnit == RecurringIntervalUnit.month ||
      intervalUnit == RecurringIntervalUnit.year;

  /// Whether the state is complete enough to preview and to save.
  bool get isComplete =>
      name.trim().isNotEmpty &&
      (amount?.isPositive ?? false) &&
      intervalCount >= 1 &&
      (!needsDayAnchor || anchorDayOfMonth != null);

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  ///
  /// `issue` and `rejection` are preserved unless [clearIssue] is passed, because a bare assignment
  /// lets any later `copyWith` erase the reason before the screen reads it (ARCH_4 R31).
  TemplateBuilderState copyWith({
    String? id,
    String? name,
    RecurringKind? kind,
    RecurringDirection? direction,
    Money? amount,
    RecurringIntervalUnit? intervalUnit,
    int? intervalCount,
    int? anchorDayOfMonth,
    bool clearAnchor = false,
    DateKey? startDateKey,
    DateKey? endDateKey,
    bool clearEndDate = false,
    String? payeeId,
    String? accountId,
    String? tagId,
    int? remindDaysBefore,
    bool? autoRemind,
    bool? isPaused,
    String? note,
    bool? submitting,
    TemplateSaveIssue? issue,
    String? rejection,
    bool clearIssue = false,
    int? shakeTrigger,
    bool? dirty,
  }) => TemplateBuilderState(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    direction: direction ?? this.direction,
    currencyCode: currencyCode,
    amount: amount ?? this.amount,
    intervalUnit: intervalUnit ?? this.intervalUnit,
    intervalCount: intervalCount ?? this.intervalCount,
    anchorDayOfMonth: clearAnchor
        ? null
        : (anchorDayOfMonth ?? this.anchorDayOfMonth),
    startDateKey: startDateKey ?? this.startDateKey,
    endDateKey: clearEndDate ? null : (endDateKey ?? this.endDateKey),
    payeeId: payeeId ?? this.payeeId,
    accountId: accountId ?? this.accountId,
    tagId: tagId ?? this.tagId,
    remindDaysBefore: remindDaysBefore ?? this.remindDaysBefore,
    autoRemind: autoRemind ?? this.autoRemind,
    isPaused: isPaused ?? this.isPaused,
    note: note ?? this.note,
    submitting: submitting ?? this.submitting,
    issue: clearIssue ? null : (issue ?? this.issue),
    rejection: clearIssue ? null : (rejection ?? this.rejection),
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? true,
  );

  /// Builds the entity this state describes.
  ///
  /// `nextDueDateKey` starts at `startDateKey` for a new template: materialisation walks forward from
  /// there, so the first occurrence is the start date itself rather than one interval after it.
  RecurringTemplate toTemplate({
    required String newId,
    required String normalizedName,
    required DateKey nextDue,
  }) => RecurringTemplate(
    id: id ?? newId,
    name: name.trim(),
    normalizedName: normalizedName,
    kind: kind,
    direction: direction,
    defaultAmount: amount ?? Money.zero(currencyCode),
    intervalUnit: intervalUnit,
    intervalCount: intervalCount,
    startDateKey: startDateKey,
    nextDueDateKey: nextDue,
    isPaused: isPaused,
    autoRemind: autoRemind,
    remindDaysBefore: remindDaysBefore,
    payeeId: payeeId,
    defaultAccountId: accountId,
    tagId: tagId,
    anchorDayOfMonth: anchorDayOfMonth,
    endDateKey: endDateKey,
    note: note,
  );

  /// Loads an existing template into a builder state.
  static TemplateBuilderState fromTemplate(RecurringTemplate template) =>
      TemplateBuilderState(
        id: template.id,
        name: template.name,
        kind: template.kind,
        direction: template.direction,
        currencyCode: template.defaultAmount.currencyCode,
        amount: template.defaultAmount,
        intervalUnit: template.intervalUnit,
        intervalCount: template.intervalCount,
        anchorDayOfMonth: template.anchorDayOfMonth,
        startDateKey: template.startDateKey,
        endDateKey: template.endDateKey,
        payeeId: template.payeeId,
        accountId: template.defaultAccountId,
        tagId: template.tagId,
        remindDaysBefore: template.remindDaysBefore,
        autoRemind: template.autoRemind,
        isPaused: template.isPaused,
        note: template.note,
      );
}
