import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';

/// One purchased thing inside a `Transaction`.
///
/// Optional detail: the transaction's own amount stays the source of truth, and when the lines do
/// not sum to it the difference is surfaced rather than auto-balanced (anomaly A11).
class TransactionLine {
  /// Creates a line.
  const TransactionLine({
    required this.id,
    required this.transactionId,
    required this.lineNo,
    required this.description,
    required this.destination,
    this.itemId,
    this.quantity,
    this.unitCode,
    this.unitPrice,
    this.lineAmount,
    this.createdBatchId,
    this.createdAssetId,
    this.createdRecurringTemplateId,
    this.note,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// The owning transaction.
  final String transactionId;

  /// Position within the transaction, 1-based.
  final int lineNo;

  /// What was bought, as free text.
  final String description;

  /// What this line produced elsewhere in the app — the field that removes the
  /// electronics/inventory/service ambiguity (anomaly A12).
  final TransactionLineDestination destination;

  /// The catalogued item, when this line refers to one.
  final String? itemId;

  /// How much was bought. Already in base units, so aggregating it needs no conversion.
  final Qty? quantity;

  /// The unit the user actually typed, kept so the line renders as `2 kg` rather than `2000 g`.
  final String? unitCode;

  /// Price per [unitCode]. Drives the personal-inflation series (ARCH_3 §5.1 query 12).
  final Money? unitPrice;

  /// Total for this line.
  final Money? lineAmount;

  /// The inventory batch this line created, if [destination] was inventory.
  final String? createdBatchId;

  /// The asset this line created, if [destination] was asset.
  final String? createdAssetId;

  /// The recurring template this line created, if [destination] was recurring.
  final String? createdRecurringTemplateId;

  /// Optional free-text note.
  final String? note;

  /// True when this line produced an artefact elsewhere.
  bool get hasArtefact =>
      createdBatchId != null ||
          createdAssetId != null ||
          createdRecurringTemplateId != null;

  /// The id of whatever artefact this line produced, or null if none.
  ///
  /// At most one is ever set, matching [destination] (ARCH_2 §4.2).
  String? get createdArtefactId =>
      createdBatchId ?? createdAssetId ?? createdRecurringTemplateId;

  /// True when this line refers to a catalogued item rather than free text.
  bool get isCatalogued => itemId != null;

  /// Price per base unit — what makes prices comparable across purchases in different units
  /// (ARCH_3 §5.1 query 24). Null when either the amount or the quantity is missing or zero.
  ///
  /// Returns minor units per base unit as a double, because a per-unit price is a derived ratio
  /// for display and comparison, not a stored amount — Law L1 governs amounts that are persisted.
  double? get pricePerBaseUnit {
    final amount = lineAmount;
    final qty = quantity;
    if (amount == null || qty == null || qty.milliBase == 0) return null;
    return amount.minor / (qty.milliBase / 1000);
  }

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  TransactionLine copyWith({
    String? id,
    String? transactionId,
    int? lineNo,
    String? description,
    TransactionLineDestination? destination,
    String? itemId,
    Qty? quantity,
    String? unitCode,
    Money? unitPrice,
    Money? lineAmount,
    String? createdBatchId,
    String? createdAssetId,
    String? createdRecurringTemplateId,
    String? note,
  }) {
    return TransactionLine(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      lineNo: lineNo ?? this.lineNo,
      description: description ?? this.description,
      destination: destination ?? this.destination,
      itemId: itemId ?? this.itemId,
      quantity: quantity ?? this.quantity,
      unitCode: unitCode ?? this.unitCode,
      unitPrice: unitPrice ?? this.unitPrice,
      lineAmount: lineAmount ?? this.lineAmount,
      createdBatchId: createdBatchId ?? this.createdBatchId,
      createdAssetId: createdAssetId ?? this.createdAssetId,
      createdRecurringTemplateId:
      createdRecurringTemplateId ?? this.createdRecurringTemplateId,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TransactionLine &&
          other.id == id &&
          other.transactionId == transactionId &&
          other.lineNo == lineNo &&
          other.description == description &&
          other.destination == destination &&
          other.itemId == itemId &&
          other.quantity == quantity &&
          other.unitCode == unitCode &&
          other.unitPrice == unitPrice &&
          other.lineAmount == lineAmount &&
          other.createdBatchId == createdBatchId &&
          other.createdAssetId == createdAssetId &&
          other.createdRecurringTemplateId == createdRecurringTemplateId &&
          other.note == note;

  @override
  int get hashCode => Object.hashAll([
    id, transactionId, lineNo, description, destination, itemId, quantity,
    unitCode, unitPrice, lineAmount, createdBatchId, createdAssetId,
    createdRecurringTemplateId, note,
  ]);

  @override
  String toString() => 'TransactionLine($id, $description)';
}