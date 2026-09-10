import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';

/// Why an asset save was refused, when it was refused for a reason worth naming.
enum AssetSaveIssue {
  /// The name was blank.
  nameMissing,

  /// The warranty ends before it starts.
  warrantyBackwards,

  /// The write failed for a reason the repository named.
  rejected,
}

/// Everything the asset editor is holding (ARCH_5 §3 archetype B).
///
/// **`type = serviceProvider` is a first-class case, not an afterthought.** A house maid is an asset
/// with a linked recurring template and a `service_records` row per payment — the same three tables a
/// television uses. Every field below is optional except the name precisely so a person can be
/// recorded without inventing a serial number for them.
class AssetEditorState {
  /// Creates the editor's state.
  const AssetEditorState({
    required this.currencyCode,
    this.id,
    this.name = '',
    this.type = AssetType.appliance,
    this.status = AssetStatus.active,
    this.brand,
    this.modelNo,
    this.serialNo,
    this.purchaseDateKey,
    this.purchasePrice,
    this.warrantyStartDateKey,
    this.warrantyEndDateKey,
    this.warrantyProvider,
    this.serviceIntervalDays,
    this.nextServiceDueDateKey,
    this.contactName,
    this.contactPhone,
    this.location,
    this.notes,
    this.submitting = false,
    this.issue,
    this.rejection,
    this.shakeTrigger = 0,
    this.dirty = false,
    this.nextServiceChosen = false,
  });

  /// The asset being edited, or null for a new one.
  final String? id;

  /// What it is. The one required field (U11).
  final String name;

  /// Which kind, which decides the wording everywhere else in the module.
  final AssetType type;

  /// Active, being repaired, or disposed. Disposal goes through the sheet, never this field.
  final AssetStatus status;

  /// The currency prices are entered in.
  final String currencyCode;

  /// Who made it.
  final String? brand;

  /// Which model.
  final String? modelNo;

  /// Its serial number.
  final String? serialNo;

  /// When it was bought.
  final DateKey? purchaseDateKey;

  /// What it cost. Kept forever, including after disposal (anomaly A30).
  final Money? purchasePrice;

  /// When the warranty starts.
  final DateKey? warrantyStartDateKey;

  /// When the warranty ends.
  final DateKey? warrantyEndDateKey;

  /// Who honours the warranty.
  final String? warrantyProvider;

  /// How many days between services.
  final int? serviceIntervalDays;

  /// When the next service is due.
  final DateKey? nextServiceDueDateKey;

  /// Who to call about it.
  final String? contactName;

  /// The number to call.
  final String? contactPhone;

  /// Where it is kept.
  final String? location;

  /// Free notes.
  final String? notes;

  /// Whether a save is in flight.
  final bool submitting;

  /// Why the last save was refused, or null if it was not.
  final AssetSaveIssue? issue;

  /// The repository's own message when it rejected the write.
  final String? rejection;

  /// Incremented to shake the offending field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (Law U10).
  final bool dirty;

  /// Whether the user picked the next service date themselves.
  ///
  /// **Typing "30" fires twice: once with 3, once with 30.** The due date was seeded with `?? `, so the
  /// first keystroke set it to three days out and every keystroke after that found it non-null and left
  /// it alone. It has to be recomputed on every change to the interval — and this flag is what stops
  /// that recomputation trampling a date the user chose deliberately.
  final bool nextServiceChosen;

  /// Whether this is editing an existing asset.
  bool get isEditing => id != null;

  /// Whether this asset is a person rather than a thing.
  ///
  /// Drives the wording, not the storage: the fields a television needs are simply left empty.
  bool get isPerson => type == AssetType.serviceProvider;

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  ///
  /// `issue` and `rejection` survive an unrelated `copyWith` — a bare assignment lets the
  /// `submitting: false` in a `finally` erase the reason before the screen reads it (ARCH_4 R31).
  AssetEditorState copyWith({
    String? id,
    String? name,
    AssetType? type,
    AssetStatus? status,
    String? brand,
    String? modelNo,
    String? serialNo,
    DateKey? purchaseDateKey,
    Money? purchasePrice,
    bool clearPurchasePrice = false,
    DateKey? warrantyStartDateKey,
    DateKey? warrantyEndDateKey,
    bool clearWarrantyEnd = false,
    String? warrantyProvider,
    int? serviceIntervalDays,
    bool clearInterval = false,
    DateKey? nextServiceDueDateKey,
    bool clearNextService = false,
    String? contactName,
    String? contactPhone,
    String? location,
    String? notes,
    bool? submitting,
    AssetSaveIssue? issue,
    String? rejection,
    bool clearIssue = false,
    int? shakeTrigger,
    bool? dirty,
    bool? nextServiceChosen,
  }) => AssetEditorState(
    currencyCode: currencyCode,
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    status: status ?? this.status,
    brand: brand ?? this.brand,
    modelNo: modelNo ?? this.modelNo,
    serialNo: serialNo ?? this.serialNo,
    purchaseDateKey: purchaseDateKey ?? this.purchaseDateKey,
    purchasePrice: clearPurchasePrice
        ? null
        : (purchasePrice ?? this.purchasePrice),
    warrantyStartDateKey: warrantyStartDateKey ?? this.warrantyStartDateKey,
    warrantyEndDateKey: clearWarrantyEnd
        ? null
        : (warrantyEndDateKey ?? this.warrantyEndDateKey),
    warrantyProvider: warrantyProvider ?? this.warrantyProvider,
    serviceIntervalDays: clearInterval
        ? null
        : (serviceIntervalDays ?? this.serviceIntervalDays),
    nextServiceDueDateKey: clearNextService
        ? null
        : (nextServiceDueDateKey ?? this.nextServiceDueDateKey),
    contactName: contactName ?? this.contactName,
    contactPhone: contactPhone ?? this.contactPhone,
    location: location ?? this.location,
    notes: notes ?? this.notes,
    submitting: submitting ?? this.submitting,
    issue: clearIssue ? null : (issue ?? this.issue),
    rejection: clearIssue ? null : (rejection ?? this.rejection),
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? true,
    nextServiceChosen: nextServiceChosen ?? this.nextServiceChosen,
  );

  /// Builds the entity this state describes.
  ///
  /// Disposal fields are never written here. An asset is disposed of through
  /// `AssetRepository.dispose`, which records the reason alongside the status change — saving the
  /// editor must not be able to quietly retire something (anomaly A30).
  Asset toAsset({
    required String newId,
    required String normalizedName,
    Asset? existing,
  }) => Asset(
    id: id ?? newId,
    name: name.trim(),
    normalizedName: normalizedName,
    type: type,
    status: status,
    brand: brand,
    modelNo: modelNo,
    serialNo: serialNo,
    purchaseDateKey: purchaseDateKey,
    purchasePrice: purchasePrice,
    sourceTransactionLineId: existing?.sourceTransactionLineId,
    warrantyStartDateKey: warrantyStartDateKey,
    warrantyEndDateKey: warrantyEndDateKey,
    warrantyProvider: warrantyProvider,
    warrantyNote: existing?.warrantyNote,
    serviceIntervalDays: serviceIntervalDays,
    nextServiceDueDateKey: nextServiceDueDateKey,
    primaryContactName: contactName,
    primaryContactPhone: contactPhone,
    location: location,
    linkedRecurringTemplateId: existing?.linkedRecurringTemplateId,
    disposedAtDateKey: existing?.disposedAtDateKey,
    disposalReason: existing?.disposalReason,
    disposalNote: existing?.disposalNote,
    disposalAmount: existing?.disposalAmount,
    notes: notes,
  );

  /// Loads an existing asset into an editor state.
  static AssetEditorState fromAsset(
    Asset asset,
    String currencyCode,
  ) => AssetEditorState(
    currencyCode: asset.purchasePrice?.currencyCode ?? currencyCode,
    id: asset.id,
    name: asset.name,
    type: asset.type,
    status: asset.status,
    brand: asset.brand,
    modelNo: asset.modelNo,
    serialNo: asset.serialNo,
    purchaseDateKey: asset.purchaseDateKey,
    purchasePrice: asset.purchasePrice,
    warrantyStartDateKey: asset.warrantyStartDateKey,
    warrantyEndDateKey: asset.warrantyEndDateKey,
    warrantyProvider: asset.warrantyProvider,
    serviceIntervalDays: asset.serviceIntervalDays,
    nextServiceDueDateKey: asset.nextServiceDueDateKey,
    // A saved date is one the user already lives with; recomputing it from the interval on the first
    // edit would silently move a service they may have booked.
    nextServiceChosen: asset.nextServiceDueDateKey != null,
    contactName: asset.primaryContactName,
    contactPhone: asset.primaryContactPhone,
    location: asset.location,
    notes: asset.notes,
  );
}
