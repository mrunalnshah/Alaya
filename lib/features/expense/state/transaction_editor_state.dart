import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/state/split_draft.dart';

/// Everything the transaction editor is holding (ARCH_5 §3 archetype B).
///
/// **The currency is here and has no setter.** Law L9 makes `originalCurrencyCode` immutable once
/// saved: changing it would reinterpret the stored minor units against a different precision and
/// symbol, silently and unrecoverably. The amount *is* editable — forbidding that would make a
/// mistyped figure permanent with delete-and-recreate as the only remedy, which loses the batch and
/// asset links the fan-out created (ARCH_4 §5.1 item 18).
class TransactionEditorState {
  /// Creates the editor's state.
  const TransactionEditorState({
    required this.currencyCode,
    required this.dateKey,
    this.id,
    this.kind = TransactionKind.withdrawal,
    this.subtype = TransactionSubtype.otherOut,
    this.amount,
    this.fromAccountId,
    this.toAccountId,
    this.paymentMethodId,
    this.payeeId,
    this.note,
    this.tagIds = const <String>{},
    this.lines = const <TransactionLine>[],
    this.warrantyStart,
    this.warrantyEnd,
    this.alsoAddToInventory = false,
    this.toOwnAccount = true,
    this.needsReview = false,
    this.submitting = false,
    this.amountMissing = false,
    this.shakeTrigger = 0,
    this.dirty = false,
    this.fanOutError,
    this.saveError,
    this.wantsTemplate = false,
    this.recurringOccurrenceId,
    this.accountMissing = false,
    this.createdAssetId,
    this.sourceEntryIds = const <String>[],
    this.split,
    this.splitError,
  });

  /// The transaction being edited, or null when this is a new one.
  final String? id;

  /// The flow type. Drives which accounts the shape requires (ARCH_2 §4.1).
  final TransactionKind kind;

  /// The structural subtype. Decides which sub-form is visible.
  final TransactionSubtype subtype;

  /// The amount. The one required field.
  final Money? amount;

  /// The currency, fixed for the life of the record (Law L9).
  final String currencyCode;

  /// The civil date the money moved.
  final DateKey dateKey;

  /// Where the money came from.
  final String? fromAccountId;

  /// Where the money went.
  final String? toAccountId;

  /// The rail it travelled on.
  final String? paymentMethodId;

  /// The counterparty.
  final String? payeeId;

  /// A free note, searchable through FTS.
  final String? note;

  /// The tags applied.
  final Set<String> tagIds;

  /// The lines itemising this transaction.
  final List<TransactionLine> lines;

  /// Warranty start for the asset an electronics line will create.
  final DateKey? warrantyStart;

  /// Warranty end for the asset an electronics line will create.
  final DateKey? warrantyEnd;

  /// Whether an electronics purchase should also produce an inventory batch.
  ///
  /// Off by default: a television is an Asset, not consumable stock, and pushing it to both is
  /// anomaly A12 — neither module then owns the truth.
  final bool alsoAddToInventory;

  /// For the transfer form: whether the money is going to the user's own account.
  ///
  /// True means `kind = transfer` and both accounts are the user's. False means a real withdrawal
  /// with `subtype = transferOut` and a payee — the distinction anomaly A02 exists for, because
  /// treating a self-transfer as a withdrawal destroys net worth.
  final bool toOwnAccount;

  /// Whether the record is still flagged as needing details.
  final bool needsReview;

  /// Whether a save is in flight.
  final bool submitting;

  /// Whether submit was pressed with no parseable amount.
  final bool amountMissing;

  /// Incremented to shake the amount field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (Law U10).
  final bool dirty;

  /// Why the last save wrote the transaction but could not create the stock or assets its lines
  /// asked for, or null when it created them all.
  final String? fanOutError;

  /// Why the last save was refused outright, or null when it committed.
  ///
  /// The repository's own message. A withdrawal with no account and a line that will not validate
  /// fail for entirely different reasons, and reporting both as "something went wrong" is why neither
  /// was diagnosable from the screen.
  final String? saveError;

  /// Whether a line asked to become a recurring template, so the editor hands the user to the builder
  /// instead of dropping the request on the floor.
  final bool wantsTemplate;

  /// The recurring occurrence this payment settles, or null for an ordinary bill.
  ///
  /// **When set, saving goes through `payOccurrence` instead of `create`.** That call writes the
  /// transaction *and* settles the occurrence together, so there is exactly one write and exactly one
  /// record — an editor that created its own transaction as well would produce two for one payment.
  final String? recurringOccurrenceId;

  /// The asset a line just created, so the editor can hand the user to it.
  ///
  /// **The fan-out was already creating it.** A line marked for assets produces an `Asset` named after
  /// the description, typed `other`, with no warranty — because a receipt line carries none of that.
  /// Nothing then said so, so a television bought as an expense appeared under "Other" with no cover
  /// dates and looked like the feature had not worked. The id travels out and the editor opens on it.
  final String? createdAssetId;

  /// Whether a bill payment could not resolve an account and needs one chosen.
  ///
  /// A field-level error rather than a snack: the choice is made in the form, so the message belongs
  /// beside it (§5.5). It is only ever set when the template, the app default and a sole account all
  /// failed to answer.
  final bool accountMissing;

  /// Shopping entries this transaction fulfils, carried in from a draft and marked purchased on save.
  final List<String> sourceEntryIds;

  /// The split being drafted, or null when this expense is not shared.
  ///
  /// **Held here rather than in its own provider**, because it is part of *this* draft: abandoning the
  /// editor abandons the split with it, and `AlayaFormScaffold`'s unsaved-changes guard (Law U10) then
  /// covers both without a second thing to remember.
  ///
  /// A draft rather than a `SplitExpense`, because that entity needs a transaction id and there is no
  /// transaction until this editor saves. The service turns instructions into shares afterwards — the
  /// same ordering the purchase fan-out already uses.
  final SplitDraft? split;

  /// Why the split could not be saved, when the transaction itself did.
  ///
  /// The exact shape of [fanOutError], and for the same reason: the transaction is saved either way,
  /// and what failed is the artefact a step asked for. Saying nothing is how a shared bill silently
  /// fails to become a debt (Law U9).
  final String? splitError;

  /// Whether this is editing an existing record rather than creating one.
  bool get isEditing => id != null;

  /// The subtypes offered for the current [kind].
  List<TransactionSubtype> get availableSubtypes => subtypesFor(kind);

  /// The subtypes a given [kind] may take.
  ///
  /// **Static, and taking the kind explicitly, because callers need to ask about a kind the state
  /// does not have yet.** `setKind` must decide whether the current subtype survives the switch, and
  /// an instance getter can only answer for the kind already applied — which silently answers the
  /// wrong question and leaves the record in a shape the subtype picker cannot render. That defect
  /// showed up as a red screen the moment the user chose Income.
  ///
  /// A deposit cannot be a grocery purchase, and offering the full list would let a user save a
  /// shape the schema's CHECK constraints reject at write time rather than at choose time.
  static List<TransactionSubtype> subtypesFor(
    TransactionKind kind,
  ) => switch (kind) {
    TransactionKind.deposit => const [
      TransactionSubtype.salaryIn,
      TransactionSubtype.otherIn,
    ],
    TransactionKind.transfer => const [TransactionSubtype.transferSelf],
    TransactionKind.withdrawal => const [
      TransactionSubtype.grocery,
      TransactionSubtype.household,
      TransactionSubtype.electronics,
      TransactionSubtype.bill,
      TransactionSubtype.transferOut,
      TransactionSubtype.otherOut,
    ],
    TransactionKind.adjustmentIncrease => const [TransactionSubtype.otherIn],
    TransactionKind.adjustmentDecrease => const [TransactionSubtype.otherOut],
  };

  /// The sum of the lines, or null when there are none.
  Money? get lineTotal {
    if (lines.isEmpty) return null;
    var total = Money.zero(currencyCode);
    for (final line in lines) {
      final lineAmount = line.lineAmount;
      if (lineAmount != null) total += lineAmount;
    }
    return total;
  }

  /// The difference between the transaction amount and its lines.
  ///
  /// Surfaced as an "unallocated" chip and **never auto-balanced**: the transaction amount is the
  /// source of truth and the lines are optional detail, so forcing them equal would silently invent
  /// a line the user did not buy (anomaly A11).
  Money? get unallocated {
    final total = lineTotal;
    final value = amount;
    if (total == null || value == null) return null;
    final difference = value - total;
    return difference.isZero ? null : difference;
  }

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  TransactionEditorState copyWith({
    String? id,
    TransactionKind? kind,
    TransactionSubtype? subtype,
    Money? amount,
    bool clearAmount = false,
    DateKey? dateKey,
    String? fromAccountId,
    bool clearFromAccount = false,
    String? toAccountId,
    bool clearToAccount = false,
    String? paymentMethodId,
    bool clearPaymentMethod = false,
    String? payeeId,
    bool clearPayee = false,
    String? note,
    Set<String>? tagIds,
    List<TransactionLine>? lines,
    DateKey? warrantyStart,
    DateKey? warrantyEnd,
    bool? alsoAddToInventory,
    bool? toOwnAccount,
    bool? needsReview,
    bool? submitting,
    bool? amountMissing,
    int? shakeTrigger,
    bool? dirty,
    String? fanOutError,
    String? saveError,
    bool? wantsTemplate,
    String? recurringOccurrenceId,
    bool? accountMissing,
    String? createdAssetId,
    bool clearOccurrence = false,
    bool clearErrors = false,
    List<String>? sourceEntryIds,
    SplitDraft? split,
    bool clearSplit = false,
    String? splitError,
  }) => TransactionEditorState(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    subtype: subtype ?? this.subtype,
    amount: clearAmount ? null : (amount ?? this.amount),
    currencyCode: currencyCode,
    dateKey: dateKey ?? this.dateKey,
    fromAccountId: clearFromAccount
        ? null
        : (fromAccountId ?? this.fromAccountId),
    toAccountId: clearToAccount ? null : (toAccountId ?? this.toAccountId),
    paymentMethodId: clearPaymentMethod
        ? null
        : (paymentMethodId ?? this.paymentMethodId),
    payeeId: clearPayee ? null : (payeeId ?? this.payeeId),
    note: note ?? this.note,
    tagIds: tagIds ?? this.tagIds,
    lines: lines ?? this.lines,
    warrantyStart: warrantyStart ?? this.warrantyStart,
    warrantyEnd: warrantyEnd ?? this.warrantyEnd,
    alsoAddToInventory: alsoAddToInventory ?? this.alsoAddToInventory,
    toOwnAccount: toOwnAccount ?? this.toOwnAccount,
    needsReview: needsReview ?? this.needsReview,
    submitting: submitting ?? this.submitting,
    amountMissing: amountMissing ?? this.amountMissing,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? true,
    // **Preserved unless explicitly cleared.** These were written as `fanOutError: fanOutError`,
    // so every later `copyWith` that did not mention them — including the `submitting: false` in
    // `save`'s `finally` — wiped the reason microseconds before the screen read it. Two separate
    // attempts to surface a real failure produced "something went wrong" because of this line.
    fanOutError: clearErrors ? null : (fanOutError ?? this.fanOutError),
    saveError: clearErrors ? null : (saveError ?? this.saveError),
    wantsTemplate: wantsTemplate ?? this.wantsTemplate,
    recurringOccurrenceId: clearOccurrence
        ? null
        : (recurringOccurrenceId ?? this.recurringOccurrenceId),
    accountMissing: accountMissing ?? this.accountMissing,
    createdAssetId: createdAssetId ?? this.createdAssetId,
    sourceEntryIds: sourceEntryIds ?? this.sourceEntryIds,
    split: clearSplit ? null : (split ?? this.split),
    // Cleared by `clearErrors` alongside the other two, so `save`'s `finally` does not leave a stale
    // reason on screen — the defect the `fanOutError` comment above records having been caught twice.
    splitError: clearErrors ? null : (splitError ?? this.splitError),
  );

  /// Builds the entity this state describes.
  ///
  /// [occurredAtUtc] comes from the caller's clock rather than `DateTime.now()`, so a save is
  /// reproducible in a test.
  Transaction toTransaction({
    required String newId,
    required DateTime occurredAtUtc,
  }) => Transaction(
    id: id ?? newId,
    kind: kind,
    subtype: subtype,
    occurredAtUtc: occurredAtUtc,
    dateKey: dateKey,
    originalAmount: amount ?? Money.zero(currencyCode),
    needsReview: needsReview,
    fromAccountId: fromAccountId,
    toAccountId: toAccountId,
    paymentMethodId: paymentMethodId,
    payeeId: payeeId,
    note: note,
  );

  /// Loads an existing transaction into an editor state.
  static TransactionEditorState fromTransaction(
    Transaction transaction, {
    required List<TransactionLine> lines,
    required Set<String> tagIds,
  }) => TransactionEditorState(
    id: transaction.id,
    kind: transaction.kind,
    subtype: transaction.subtype,
    amount: transaction.originalAmount,
    currencyCode: transaction.originalAmount.currencyCode,
    dateKey: transaction.dateKey,
    fromAccountId: transaction.fromAccountId,
    toAccountId: transaction.toAccountId,
    paymentMethodId: transaction.paymentMethodId,
    payeeId: transaction.payeeId,
    note: transaction.note,
    tagIds: tagIds,
    lines: lines,
    needsReview: transaction.needsReview,
    toOwnAccount: transaction.kind == TransactionKind.transfer,
  );
}
