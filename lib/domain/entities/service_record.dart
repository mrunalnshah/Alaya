import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// One service, repair or payment event against an `Asset`.
///
/// Also the payment log for a service provider, via [ServiceRecordType.salaryPaid].
class ServiceRecord {
  /// Creates a service record.
  const ServiceRecord({
    required this.id,
    required this.assetId,
    required this.serviceDateKey,
    required this.type,
    this.providerName,
    this.providerPhone,
    this.cost,
    this.linkedTransactionId,
    this.nextDueDateKey,
    this.notes,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// The asset this record belongs to.
  final String assetId;

  /// The civil date of the event.
  final DateKey serviceDateKey;

  /// What kind of event this was.
  final ServiceRecordType type;

  /// Who performed it.
  final String? providerName;

  /// Their contact number.
  final String? providerPhone;

  /// What it cost. Drives lifetime service cost per asset (ARCH_3 §5.1 query 19), which must be
  /// totalled per currency rather than summed across them (anomaly A34).
  final Money? cost;

  /// The withdrawal this cost was booked as, when the user chose to record it as an expense.
  final String? linkedTransactionId;

  /// The civil date the next service was scheduled for at the time of this one.
  final DateKey? nextDueDateKey;

  /// Optional free-text notes.
  final String? notes;

  /// True when this record has a recorded cost.
  bool get hasCost => cost != null;

  /// True when this cost was also booked as a transaction.
  bool get isBookedAsExpense => linkedTransactionId != null;

  /// True when a phone number is recorded, so the UI can offer a tappable dial action.
  bool get hasProviderPhone => providerPhone != null && providerPhone!.isNotEmpty;

  /// True when this record is a salary payment to a service provider rather than a repair.
  bool get isSalaryPayment => type == ServiceRecordType.salaryPaid;

  /// Days from [today] until the next scheduled service — negative once overdue, null when none is
  /// scheduled.
  int? daysUntilNextDue(DateKey today) => nextDueDateKey?.diffDays(today);

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  ServiceRecord copyWith({
    String? id,
    String? assetId,
    DateKey? serviceDateKey,
    ServiceRecordType? type,
    String? providerName,
    String? providerPhone,
    Money? cost,
    String? linkedTransactionId,
    DateKey? nextDueDateKey,
    String? notes,
  }) {
    return ServiceRecord(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      serviceDateKey: serviceDateKey ?? this.serviceDateKey,
      type: type ?? this.type,
      providerName: providerName ?? this.providerName,
      providerPhone: providerPhone ?? this.providerPhone,
      cost: cost ?? this.cost,
      linkedTransactionId: linkedTransactionId ?? this.linkedTransactionId,
      nextDueDateKey: nextDueDateKey ?? this.nextDueDateKey,
      notes: notes ?? this.notes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ServiceRecord &&
          other.id == id &&
          other.assetId == assetId &&
          other.serviceDateKey == serviceDateKey &&
          other.type == type &&
          other.providerName == providerName &&
          other.providerPhone == providerPhone &&
          other.cost == cost &&
          other.linkedTransactionId == linkedTransactionId &&
          other.nextDueDateKey == nextDueDateKey &&
          other.notes == notes;

  @override
  int get hashCode => Object.hashAll([
    id, assetId, serviceDateKey, type, providerName, providerPhone, cost,
    linkedTransactionId, nextDueDateKey, notes,
  ]);

  @override
  String toString() => 'ServiceRecord($id, ${type.name}, ${serviceDateKey.toIso()})';
}