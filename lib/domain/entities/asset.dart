import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// A durable, serviceable, non-consumable thing **or person**.
///
/// [AssetType.serviceProvider] is how a house maid lives in the same table as a TV — an asset, plus
/// a linked recurring template for salary, plus a service record per payment. No second system
/// (anomaly A30).
///
/// There is no delete. Removal is [AssetStatus.disposed] plus a [disposalReason], so the money
/// spent stays in analytics after the thing is gone (ARCH_3 §4.1).
class Asset {
  /// Creates an asset.
  const Asset({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.type,
    required this.status,
    this.brand,
    this.modelNo,
    this.serialNo,
    this.purchaseDateKey,
    this.purchasePrice,
    this.sourceTransactionLineId,
    this.warrantyStartDateKey,
    this.warrantyEndDateKey,
    this.warrantyProvider,
    this.warrantyNote,
    this.serviceIntervalDays,
    this.nextServiceDueDateKey,
    this.primaryContactName,
    this.primaryContactPhone,
    this.location,
    this.linkedRecurringTemplateId,
    this.disposedAtDateKey,
    this.disposalReason,
    this.disposalNote,
    this.disposalAmount,
    this.notes,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name as the user typed it.
  final String name;

  /// Normalised form used for identity matching only, never displayed.
  final String normalizedName;

  /// What kind of asset — or person — this is.
  final AssetType type;

  /// Current lifecycle state.
  final AssetStatus status;

  /// Manufacturer or brand.
  final String? brand;

  /// Model number.
  final String? modelNo;

  /// Serial number.
  final String? serialNo;

  /// Civil date acquired.
  final DateKey? purchaseDateKey;

  /// Purchase price.
  final Money? purchasePrice;

  /// The transaction line that created this asset, if it came from a purchase.
  final String? sourceTransactionLineId;

  /// Civil date warranty cover begins.
  final DateKey? warrantyStartDateKey;

  /// Civil date warranty cover ends.
  final DateKey? warrantyEndDateKey;

  /// Who provides the warranty.
  final String? warrantyProvider;

  /// Free-text warranty detail.
  final String? warrantyNote;

  /// Nominal days between services.
  final int? serviceIntervalDays;

  /// Civil date the next service is due.
  final DateKey? nextServiceDueDateKey;

  /// Primary contact name — the technician, or the person themselves.
  final String? primaryContactName;

  /// Primary contact phone, made tappable in the UI.
  final String? primaryContactPhone;

  /// Where the asset physically is.
  final String? location;

  /// The recurring template that pays for this asset.
  final String? linkedRecurringTemplateId;

  /// Civil date of disposal.
  final DateKey? disposedAtDateKey;

  /// Why it was disposed of. Non-null exactly when [status] is disposed.
  final AssetDisposalReason? disposalReason;

  /// Free-text disposal detail.
  final String? disposalNote;

  /// Sale proceeds, if sold. Denominated in the same currency as [purchasePrice], since the schema
  /// carries no separate disposal currency.
  final Money? disposalAmount;

  /// Optional free-text notes.
  final String? notes;

  /// True when this asset has been retired.
  bool get isDisposed => status == AssetStatus.disposed;

  /// True when this asset is currently in normal use.
  bool get isInUse => status != AssetStatus.disposed;

  /// True when a phone number is recorded, so the UI can offer a tappable dial action.
  bool get hasContactPhone =>
      primaryContactPhone != null && primaryContactPhone!.isNotEmpty;

  /// True when this asset represents a person rather than a thing.
  bool get isServiceProvider => type == AssetType.serviceProvider;

  /// Days of warranty remaining as of [today] — negative once expired, null when no warranty end
  /// is recorded.
  ///
  /// A **method taking [today]**, not the bare getter the phase brief sketched: days-remaining is
  /// meaningless without a reference date, and a getter would have to read the clock — making it
  /// non-deterministic and untestable, exactly the problem ARCH_2 §12.2 solved for the views. The
  /// brief's intent, that derived state is computed rather than stored, is honoured.
  int? warrantyDaysLeftFrom(DateKey today) => warrantyEndDateKey?.diffDays(today);

  /// True when a warranty is recorded and still in force as of [today]. The last day counts.
  bool isUnderWarranty(DateKey today) {
    final end = warrantyEndDateKey;
    if (end == null) return false;
    final start = warrantyStartDateKey;
    if (start != null && today.isBefore(start)) return false;
    return !end.isBefore(today);
  }

  /// True when the warranty ends within [days] of [today], already-expired included.
  bool isWarrantyEndingWithin(DateKey today, int days) {
    final left = warrantyDaysLeftFrom(today);
    return left != null && left <= days;
  }

  /// Days until the next service as of [today] — negative once overdue, null when unscheduled.
  int? serviceDaysLeftFrom(DateKey today) => nextServiceDueDateKey?.diffDays(today);

  /// True when a service is scheduled and its date has passed as of [today].
  bool isServiceOverdue(DateKey today) {
    final due = nextServiceDueDateKey;
    return due != null && due < today;
  }

  /// Net cost of ownership — what was paid, less anything recovered on disposal.
  ///
  /// Null when no purchase price is recorded. Both amounts share a currency by construction, so
  /// this cannot throw a currency mismatch.
  Money? get netCost {
    final paid = purchasePrice;
    if (paid == null) return null;
    final recovered = disposalAmount;
    return recovered == null ? paid : paid - recovered;
  }

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables —
  /// notably, undisposing an asset clears four fields and so constructs directly.
  Asset copyWith({
    String? id,
    String? name,
    String? normalizedName,
    AssetType? type,
    AssetStatus? status,
    String? brand,
    String? modelNo,
    String? serialNo,
    DateKey? purchaseDateKey,
    Money? purchasePrice,
    String? sourceTransactionLineId,
    DateKey? warrantyStartDateKey,
    DateKey? warrantyEndDateKey,
    String? warrantyProvider,
    String? warrantyNote,
    int? serviceIntervalDays,
    DateKey? nextServiceDueDateKey,
    String? primaryContactName,
    String? primaryContactPhone,
    String? location,
    String? linkedRecurringTemplateId,
    DateKey? disposedAtDateKey,
    AssetDisposalReason? disposalReason,
    String? disposalNote,
    Money? disposalAmount,
    String? notes,
  }) {
    return Asset(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      type: type ?? this.type,
      status: status ?? this.status,
      brand: brand ?? this.brand,
      modelNo: modelNo ?? this.modelNo,
      serialNo: serialNo ?? this.serialNo,
      purchaseDateKey: purchaseDateKey ?? this.purchaseDateKey,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      sourceTransactionLineId: sourceTransactionLineId ?? this.sourceTransactionLineId,
      warrantyStartDateKey: warrantyStartDateKey ?? this.warrantyStartDateKey,
      warrantyEndDateKey: warrantyEndDateKey ?? this.warrantyEndDateKey,
      warrantyProvider: warrantyProvider ?? this.warrantyProvider,
      warrantyNote: warrantyNote ?? this.warrantyNote,
      serviceIntervalDays: serviceIntervalDays ?? this.serviceIntervalDays,
      nextServiceDueDateKey: nextServiceDueDateKey ?? this.nextServiceDueDateKey,
      primaryContactName: primaryContactName ?? this.primaryContactName,
      primaryContactPhone: primaryContactPhone ?? this.primaryContactPhone,
      location: location ?? this.location,
      linkedRecurringTemplateId:
      linkedRecurringTemplateId ?? this.linkedRecurringTemplateId,
      disposedAtDateKey: disposedAtDateKey ?? this.disposedAtDateKey,
      disposalReason: disposalReason ?? this.disposalReason,
      disposalNote: disposalNote ?? this.disposalNote,
      disposalAmount: disposalAmount ?? this.disposalAmount,
      notes: notes ?? this.notes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Asset &&
          other.id == id &&
          other.name == name &&
          other.normalizedName == normalizedName &&
          other.type == type &&
          other.status == status &&
          other.brand == brand &&
          other.modelNo == modelNo &&
          other.serialNo == serialNo &&
          other.purchaseDateKey == purchaseDateKey &&
          other.purchasePrice == purchasePrice &&
          other.sourceTransactionLineId == sourceTransactionLineId &&
          other.warrantyStartDateKey == warrantyStartDateKey &&
          other.warrantyEndDateKey == warrantyEndDateKey &&
          other.warrantyProvider == warrantyProvider &&
          other.warrantyNote == warrantyNote &&
          other.serviceIntervalDays == serviceIntervalDays &&
          other.nextServiceDueDateKey == nextServiceDueDateKey &&
          other.primaryContactName == primaryContactName &&
          other.primaryContactPhone == primaryContactPhone &&
          other.location == location &&
          other.linkedRecurringTemplateId == linkedRecurringTemplateId &&
          other.disposedAtDateKey == disposedAtDateKey &&
          other.disposalReason == disposalReason &&
          other.disposalNote == disposalNote &&
          other.disposalAmount == disposalAmount &&
          other.notes == notes;

  @override
  int get hashCode => Object.hashAll([
    id, name, normalizedName, type, status, brand, modelNo, serialNo,
    purchaseDateKey, purchasePrice, sourceTransactionLineId, warrantyStartDateKey,
    warrantyEndDateKey, warrantyProvider, warrantyNote, serviceIntervalDays,
    nextServiceDueDateKey, primaryContactName, primaryContactPhone, location,
    linkedRecurringTemplateId, disposedAtDateKey, disposalReason, disposalNote,
    disposalAmount, notes,
  ]);

  @override
  String toString() => 'Asset($id, $name, ${status.name})';
}
