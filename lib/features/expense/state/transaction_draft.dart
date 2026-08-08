import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/transaction_line.dart';

/// A transaction another module has prepared for the user to confirm.
///
/// **Carries lines, not a saved transaction.** `ShoppingRepository.buildPurchaseDraft` deliberately
/// returns drafts rather than writing anything, because the amount, the account and the payee are
/// decisions only the expense editor can collect. Handing them over as a draft is what lets the
/// shopping module close the loop without reimplementing the editor (anomaly A25).
class TransactionDraft {
  /// Creates a draft.
  const TransactionDraft({
    required this.lines,
    required this.kind,
    required this.subtype,
    this.note,
    this.sourceEntryIds = const <String>[],
    this.sourceListId,
  });

  /// The lines the editor should open with.
  final List<TransactionLine> lines;

  /// The flow type the editor should open on.
  final TransactionKind kind;

  /// The subtype the editor should open on.
  final TransactionSubtype subtype;

  /// A note to seed, if the origin has something worth saying.
  final String? note;

  /// Which shopping entries these lines came from, so they can be marked purchased on save.
  final List<String> sourceEntryIds;

  /// Which shopping list they came from.
  final String? sourceListId;
}
