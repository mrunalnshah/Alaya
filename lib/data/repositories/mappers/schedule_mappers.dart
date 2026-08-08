import 'package:alaya/core/money/money.dart';
import 'package:drift/drift.dart' show Value;

import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/money_converter.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/service_record.dart';

/// Converts between `RecurringTemplateRow` and the domain `RecurringTemplate` entity.
extension RecurringTemplateMapper on RecurringTemplateRow {
  /// Maps this row to a domain entity.
  RecurringTemplate toEntity() => RecurringTemplate(
    id: id,
    name: name,
    normalizedName: normalizedName,
    kind: kind,
    direction: direction,
    defaultAmount: MoneyColumns.read(defaultAmountMinor, currencyCode),
    intervalUnit: intervalUnit,
    intervalCount: intervalCount,
    startDateKey: startDateKey,
    nextDueDateKey: nextDueDateKey,
    isPaused: isPaused,
    autoRemind: autoRemind,
    remindDaysBefore: remindDaysBefore,
    payeeId: payeeId,
    defaultAccountId: defaultAccountId,
    defaultPaymentMethodId: defaultPaymentMethodId,
    tagId: tagId,
    anchorDayOfMonth: anchorDayOfMonth,
    anchorMonth: anchorMonth,
    anchorWeekday: anchorWeekday,
    endDateKey: endDateKey,
    linkedAssetId: linkedAssetId,
    note: note,
  );
}

/// Builds the companion for [template].
RecurringTemplatesCompanion recurringTemplateToCompanion(
  RecurringTemplate template, {
  required int createdAt,
  required int updatedAt,
}) {
  return RecurringTemplatesCompanion.insert(
    id: template.id,
    name: template.name,
    normalizedName: template.normalizedName,
    kind: template.kind,
    direction: template.direction,
    defaultAmountMinor: MoneyColumns.minorOf(template.defaultAmount),
    currencyCode: MoneyColumns.codeOf(template.defaultAmount),
    payeeId: Value(template.payeeId),
    defaultAccountId: Value(template.defaultAccountId),
    defaultPaymentMethodId: Value(template.defaultPaymentMethodId),
    tagId: Value(template.tagId),
    intervalUnit: template.intervalUnit,
    intervalCount: template.intervalCount,
    anchorDayOfMonth: Value(template.anchorDayOfMonth),
    anchorMonth: Value(template.anchorMonth),
    anchorWeekday: Value(template.anchorWeekday),
    startDateKey: template.startDateKey,
    endDateKey: Value(template.endDateKey),
    nextDueDateKey: template.nextDueDateKey,
    isPaused: template.isPaused,
    autoRemind: template.autoRemind,
    remindDaysBefore: template.remindDaysBefore,
    linkedAssetId: Value(template.linkedAssetId),
    note: Value(template.note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `RecurringOccurrenceRow` and the domain `RecurringOccurrence` entity.
///
/// [currencyCode] comes from the owning template: `recurring_occurrences` stores
/// `paid_amount_minor` with no currency column of its own (ARCH_2 §7), because an occurrence is
/// always denominated in its template's currency. Passing it in rather than assuming one keeps
/// Law L1's pairing rule honest.
extension RecurringOccurrenceMapper on RecurringOccurrenceRow {
  /// Maps this row to a domain entity.
  RecurringOccurrence toEntity(String currencyCode) => RecurringOccurrence(
    id: id,
    templateId: templateId,
    dueDateKey: dueDateKey,
    status: status,
    paidTransactionId: paidTransactionId,
    // `readNullable` enforces a pairing invariant — both null or both present — and throws on a
    // half-populated pair. It is right only where the currency is a nullable column written and
    // cleared with its own amount. Here the currency is always present, so a null amount is a
    // legitimate absence rather than a broken pair, and the nullability belongs to the amount.
    //
    // `recurring_occurrences.currency_code` is NOT NULL, so an occurrence that has not been paid
    // yet is exactly the half-populated pair this would reject.
    paidAmount: paidAmountMinor == null
        ? null
        : Money(paidAmountMinor!, currencyCode),
    paidDateKey: paidDateKey,
    note: note,
  );
}

/// Converts between `AssetRow` and the domain `Asset` entity.
///
/// `disposalAmountMinor` is read against `purchaseCurrencyCode`, because `assets` carries no
/// separate disposal currency (ARCH_2 §8) — sale proceeds are denominated in whatever the asset
/// was bought in. Pairing it with any other code would silently misstate the figure.
extension AssetMapper on AssetRow {
  /// Maps this row to a domain entity.
  Asset toEntity() => Asset(
    id: id,
    name: name,
    normalizedName: normalizedName,
    type: type,
    status: status,
    brand: brand,
    modelNo: modelNo,
    serialNo: serialNo,
    purchaseDateKey: purchaseDateKey,
    // Same shared currency as `disposalAmount` below, so the exposure runs both ways: an asset
    // disposed of without a recorded purchase price has the currency set and this amount null.
    purchasePrice: purchasePriceMinor == null || purchaseCurrencyCode == null
        ? null
        : Money(purchasePriceMinor!, purchaseCurrencyCode!),
    sourceTransactionLineId: sourceTransactionLineId,
    warrantyStartDateKey: warrantyStartDateKey,
    warrantyEndDateKey: warrantyEndDateKey,
    warrantyProvider: warrantyProvider,
    warrantyNote: warrantyNote,
    serviceIntervalDays: serviceIntervalDays,
    nextServiceDueDateKey: nextServiceDueDateKey,
    primaryContactName: primaryContactName,
    primaryContactPhone: primaryContactPhone,
    location: location,
    linkedRecurringTemplateId: linkedRecurringTemplateId,
    disposedAtDateKey: disposedAtDateKey,
    disposalReason: disposalReason,
    disposalNote: disposalNote,
    // `purchase_currency_code` is nullable, but it is shared with `purchasePrice` above — so an
    // asset bought for a known price and not yet disposed of has the currency set and this
    // amount null. One currency serving two amounts cannot carry a pairing invariant for either.
    disposalAmount: disposalAmountMinor == null || purchaseCurrencyCode == null
        ? null
        : Money(disposalAmountMinor!, purchaseCurrencyCode!),
    notes: notes,
  );
}

/// Builds the companion for [asset].
AssetsCompanion assetToCompanion(
  Asset asset, {
  required int createdAt,
  required int updatedAt,
}) {
  return AssetsCompanion.insert(
    id: asset.id,
    name: asset.name,
    normalizedName: asset.normalizedName,
    type: asset.type,
    brand: Value(asset.brand),
    modelNo: Value(asset.modelNo),
    serialNo: Value(asset.serialNo),
    purchaseDateKey: Value(asset.purchaseDateKey),
    purchasePriceMinor: Value(
      MoneyColumns.minorOfNullable(asset.purchasePrice),
    ),
    purchaseCurrencyCode: Value(
      MoneyColumns.codeOfNullable(asset.purchasePrice),
    ),
    sourceTransactionLineId: Value(asset.sourceTransactionLineId),
    warrantyStartDateKey: Value(asset.warrantyStartDateKey),
    warrantyEndDateKey: Value(asset.warrantyEndDateKey),
    warrantyProvider: Value(asset.warrantyProvider),
    warrantyNote: Value(asset.warrantyNote),
    serviceIntervalDays: Value(asset.serviceIntervalDays),
    nextServiceDueDateKey: Value(asset.nextServiceDueDateKey),
    primaryContactName: Value(asset.primaryContactName),
    primaryContactPhone: Value(asset.primaryContactPhone),
    location: Value(asset.location),
    linkedRecurringTemplateId: Value(asset.linkedRecurringTemplateId),
    status: asset.status,
    disposedAtDateKey: Value(asset.disposedAtDateKey),
    disposalReason: Value(asset.disposalReason),
    disposalNote: Value(asset.disposalNote),
    disposalAmountMinor: Value(
      MoneyColumns.minorOfNullable(asset.disposalAmount),
    ),
    notes: Value(asset.notes),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Converts between `ServiceRecordRow` and the domain `ServiceRecord` entity.
extension ServiceRecordMapper on ServiceRecordRow {
  /// Maps this row to a domain entity.
  ServiceRecord toEntity() => ServiceRecord(
    id: id,
    assetId: assetId,
    serviceDateKey: serviceDateKey,
    type: type,
    providerName: providerName,
    providerPhone: providerPhone,
    cost: MoneyColumns.readNullable(costMinor, currencyCode),
    linkedTransactionId: linkedTransactionId,
    nextDueDateKey: nextDueDateKey,
    notes: notes,
  );
}

/// Builds the companion for [record].
ServiceRecordsCompanion serviceRecordToCompanion(
  ServiceRecord record, {
  required int createdAt,
  required int updatedAt,
}) {
  return ServiceRecordsCompanion.insert(
    id: record.id,
    assetId: record.assetId,
    serviceDateKey: record.serviceDateKey,
    type: record.type,
    providerName: Value(record.providerName),
    providerPhone: Value(record.providerPhone),
    costMinor: Value(MoneyColumns.minorOfNullable(record.cost)),
    currencyCode: Value(MoneyColumns.codeOfNullable(record.cost)),
    linkedTransactionId: Value(record.linkedTransactionId),
    nextDueDateKey: Value(record.nextDueDateKey),
    notes: Value(record.notes),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
