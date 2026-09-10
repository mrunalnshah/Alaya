import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/service_record.dart';

/// Why a service record was refused, when it was refused for a reason worth naming.
enum ServiceSaveIssue {
  /// The expense toggle is on with no cost to record.
  costMissingForExpense,

  /// The expense toggle is on with no account to record it against.
  accountMissingForExpense,

  /// The write failed for a reason the repository named.
  rejected,
}

/// Everything the service editor is holding (ARCH_5 §3 archetype B).
///
/// **`type = salaryPaid` is what makes a person work in this table.** A maid's monthly payment is a
/// service record like any other — same asset, same cost column, same optional expense — so the
/// salary history on the detail screen is simply this table filtered by type. There is no second
/// system to keep in step.
class ServiceEditorState {
  /// Creates the editor's state.
  const ServiceEditorState({
    required this.assetId,
    required this.currencyCode,
    required this.serviceDateKey,
    this.id,
    this.type = ServiceRecordType.service,
    this.providerName,
    this.providerPhone,
    this.cost,
    this.nextDueDateKey,
    this.notes,
    this.alsoRecordAsExpense = false,
    this.accountId,
    this.paymentMethodId,
    this.submitting = false,
    this.issue,
    this.rejection,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// The record being edited, or null for a new one.
  final String? id;

  /// Which asset it belongs to.
  final String assetId;

  /// The currency costs are entered in.
  final String currencyCode;

  /// What happened.
  final ServiceRecordType type;

  /// When.
  final DateKey serviceDateKey;

  /// Who did it, or who was paid.
  final String? providerName;

  /// Their number, so the detail screen can offer a call.
  final String? providerPhone;

  /// What it cost.
  final Money? cost;

  /// When the next one is due, which also advances the asset's own due date.
  final DateKey? nextDueDateKey;

  /// Free notes.
  final String? notes;

  /// Whether the repository should also write a withdrawal for [cost].
  ///
  /// **The repository owns that write, not this editor.** `ServiceRecordRepository.save` takes the flag
  /// and does both, which is the only way the two stay consistent — the sequence is not atomic across
  /// aggregates, so it is ordered and idempotent instead (ARCH_4 R21).
  final bool alsoRecordAsExpense;

  /// Which account the expense comes from, required only when the toggle is on.
  final String? accountId;

  /// How it was paid, if the user cares to say.
  ///
  /// Always optional. It travels to the expense and never onto the record: how a service was settled is
  /// a property of the payment, not of the work.
  final String? paymentMethodId;

  /// Whether a save is in flight.
  final bool submitting;

  /// Why the last save was refused, or null if it was not.
  final ServiceSaveIssue? issue;

  /// The repository's own message when it rejected the write.
  final String? rejection;

  /// Incremented to shake the offending field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (Law U10).
  final bool dirty;

  /// Whether this is editing an existing record.
  bool get isEditing => id != null;

  /// Whether this record is a salary payment rather than work done on a thing.
  bool get isSalary => type == ServiceRecordType.salaryPaid;

  /// Whether the expense toggle has everything it needs.
  bool get expenseIsSatisfiable =>
      !alsoRecordAsExpense ||
      ((cost?.isPositive ?? false) && accountId != null);

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  ServiceEditorState copyWith({
    String? id,
    ServiceRecordType? type,
    DateKey? serviceDateKey,
    String? providerName,
    String? providerPhone,
    Money? cost,
    bool clearCost = false,
    DateKey? nextDueDateKey,
    bool clearNextDue = false,
    String? notes,
    bool? alsoRecordAsExpense,
    String? accountId,
    String? paymentMethodId,
    bool? submitting,
    ServiceSaveIssue? issue,
    String? rejection,
    bool clearIssue = false,
    int? shakeTrigger,
    bool? dirty,
  }) => ServiceEditorState(
    assetId: assetId,
    currencyCode: currencyCode,
    id: id ?? this.id,
    type: type ?? this.type,
    serviceDateKey: serviceDateKey ?? this.serviceDateKey,
    providerName: providerName ?? this.providerName,
    providerPhone: providerPhone ?? this.providerPhone,
    cost: clearCost ? null : (cost ?? this.cost),
    nextDueDateKey: clearNextDue
        ? null
        : (nextDueDateKey ?? this.nextDueDateKey),
    notes: notes ?? this.notes,
    alsoRecordAsExpense: alsoRecordAsExpense ?? this.alsoRecordAsExpense,
    accountId: accountId ?? this.accountId,
    paymentMethodId: paymentMethodId ?? this.paymentMethodId,
    submitting: submitting ?? this.submitting,
    issue: clearIssue ? null : (issue ?? this.issue),
    rejection: clearIssue ? null : (rejection ?? this.rejection),
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? true,
  );

  /// Builds the entity this state describes.
  ServiceRecord toRecord({
    required String newId,
    ServiceRecord? existing,
  }) => ServiceRecord(
    id: id ?? newId,
    assetId: assetId,
    serviceDateKey: serviceDateKey,
    type: type,
    providerName: providerName,
    providerPhone: providerPhone,
    cost: cost,
    // Preserved rather than rewritten: the repository owns this link, and an editor that cleared it
    // would orphan a transaction that genuinely happened (Law L6).
    linkedTransactionId: existing?.linkedTransactionId,
    nextDueDateKey: nextDueDateKey,
    notes: notes,
  );

  /// Loads an existing record into an editor state.
  static ServiceEditorState fromRecord(
    ServiceRecord record,
    String currencyCode,
  ) => ServiceEditorState(
    assetId: record.assetId,
    currencyCode: record.cost?.currencyCode ?? currencyCode,
    id: record.id,
    type: record.type,
    serviceDateKey: record.serviceDateKey,
    providerName: record.providerName,
    providerPhone: record.providerPhone,
    cost: record.cost,
    nextDueDateKey: record.nextDueDateKey,
    notes: record.notes,
    // An existing record already wrote its expense or did not. Re-offering the toggle on edit would
    // let one service produce two withdrawals — the same shape as ARCH_4 R35.
    alsoRecordAsExpense: false,
  );
}
