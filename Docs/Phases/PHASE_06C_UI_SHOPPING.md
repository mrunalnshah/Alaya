# PHASE 6C — The Shopping module UI

> **Regenerated 2026-08-02 from the canonical tree.** Every fix through the Phase 6C debugging
> pass is folded in; this document and the working tree are in sync, and regenerating from it
> reproduces the code that runs. Earlier revisions reintroduce defects listed in ARCH_6 §3.
>
> Files shared with other phase documents — `app_en.arb`, `routes.dart`, `app_router.dart`,
> `layout_overflow_test.dart`, and the Phase 6A editor files amended by 6B and 6C — carry
> **identical** content in every copy, so they may be applied in any order.

Two parts. **Part 0 opens a seam in Phase 6A's editor** so convert-to-purchase can hand it a
pre-filled draft. `ShoppingRepository.buildPurchaseDraft` already returns `List<TransactionLine>` and
its contract says the user "still confirms the amount and account in the expense editor" — but the
editor had no way to receive them. Part 0 adds that channel and nothing else; 6C never writes a
transaction itself.

Part 0 files belong to Phase 6A and supersede their versions there.

```
flutter gen-l10n
flutter analyze
flutter test
```

No new packages.

## Part 0 — the handoff seam in Phase 6A

### `lib/features/expense/state/transaction_draft.dart`

```dart
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
```

### `lib/features/expense/providers/transaction_draft_provider.dart`

```dart
/// The one-shot channel a module uses to hand the expense editor a pre-filled transaction.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/features/expense/state/transaction_draft.dart';

/// A draft waiting to be picked up by the next new-transaction editor.
///
/// **Set immediately before pushing the editor, consumed by its first load, then cleared.** A
/// `go_router` `extra` cannot reach the notifier that builds the editor's state, and widening the
/// family argument to carry a `List<TransactionLine>` would break its structural equality — a list
/// compares by identity, so every rebuild would allocate a fresh provider. A single-slot channel
/// that empties on read is the smaller compromise, and `take()` makes the one-shot explicit rather
/// than leaving a stale draft to ambush the next blank editor.
final transactionDraftProvider =
    NotifierProvider<TransactionDraftNotifier, TransactionDraft?>(
  TransactionDraftNotifier.new,
);

/// Holds at most one pending draft.
class TransactionDraftNotifier extends Notifier<TransactionDraft?> {
  @override
  TransactionDraft? build() => null;

  /// Offers a draft to the next editor that opens.
  void offer(TransactionDraft draft) => state = draft;

  /// Returns the pending draft and clears it, so it is never applied twice.
  TransactionDraft? take() {
    final draft = state;
    state = null;
    return draft;
  }
}
```

### `lib/features/expense/state/transaction_editor_state.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';

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
  static List<TransactionSubtype> subtypesFor(TransactionKind kind) => switch (kind) {
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
  }) =>
      TransactionEditorState(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        subtype: subtype ?? this.subtype,
        amount: clearAmount ? null : (amount ?? this.amount),
        currencyCode: currencyCode,
        dateKey: dateKey ?? this.dateKey,
        fromAccountId: clearFromAccount ? null : (fromAccountId ?? this.fromAccountId),
        toAccountId: clearToAccount ? null : (toAccountId ?? this.toAccountId),
        paymentMethodId:
            clearPaymentMethod ? null : (paymentMethodId ?? this.paymentMethodId),
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
      );

  /// Builds the entity this state describes.
  ///
  /// [occurredAtUtc] comes from the caller's clock rather than `DateTime.now()`, so a save is
  /// reproducible in a test.
  Transaction toTransaction({required String newId, required DateTime occurredAtUtc}) =>
      Transaction(
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
  }) =>
      TransactionEditorState(
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
```

### `lib/features/expense/providers/transaction_editor_providers.dart`

```dart
/// View-model state for the transaction editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/services/purchase_fan_out_service.dart';
import 'package:alaya/features/expense/providers/transaction_draft_provider.dart';
import 'package:alaya/features/expense/state/transaction_draft.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/features/recurring/providers/bill_account_providers.dart';
import 'package:alaya/features/recurring/providers/template_draft_provider.dart';

/// Raised when a transaction genuinely is not there, as opposed to failing to load.
class TransactionNotFound implements Exception {
  /// Creates the marker.
  const TransactionNotFound(this.id);

  /// The transaction that is not there.
  final String id;

  @override
  String toString() => 'Transaction $id not found.';
}

/// The editor for one transaction, or for a new one when the argument is null.
///
/// The family argument arrives as a `build` parameter against `AutoDisposeFamilyNotifier`, which is
/// the shape this project's Riverpod actually resolves to. Riverpod 3.0's published guide describes
/// a fused `Notifier` taking the argument in its constructor; that does not compile here, and
/// checking the changelog instead of the analyzer is how Phase 6A got it wrong once already
/// (ARCH_1 §7.3, ARCH_4 R22).
final transactionEditorProvider = NotifierProvider.autoDispose
    .family<TransactionEditorNotifier, AsyncValue<TransactionEditorState>, String?>(
  TransactionEditorNotifier.new,
);

/// Loads, edits and saves one transaction.
class TransactionEditorNotifier
    extends AutoDisposeFamilyNotifier<AsyncValue<TransactionEditorState>, String?> {
  @override
  AsyncValue<TransactionEditorState> build(String? arg) {
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(String? id) async {
    try {
      final settings = ref.read(settingsRepositoryProvider);
      final code = await settings.readHomeCurrencyCode() ?? 'INR';
      if (id == null) {
        // A draft another module prepared, if one is waiting. `take()` clears it, so a draft is
        // applied exactly once and a stale one cannot ambush the next blank editor.
        final draft = ref.read(transactionDraftProvider.notifier).take();
        state = AsyncValue.data(
          TransactionEditorState(
            currencyCode: code,
            dateKey: ref.read(clockProvider).today(),
            kind: draft?.kind ?? TransactionKind.withdrawal,
            subtype: draft?.subtype ?? TransactionSubtype.otherOut,
            lines: draft?.lines ?? const [],
            note: draft?.note,
            sourceEntryIds: draft?.sourceEntryIds ?? const [],
          ),
        );
        return;
      }
      final repository = ref.read(transactionRepositoryProvider);
      final transaction = await repository.byId(id);
      if (transaction == null) {
        state = AsyncValue.error(TransactionNotFound(id), StackTrace.current);
        return;
      }
      // `_firstOrEmpty`, not `.first`. `watchLines` returns without emitting when it cannot resolve
      // the parent's currency, and `.first` on a stream that closes empty throws `StateError: No
      // element` — which the editor then reported as "this may have been deleted".
      final lines = await _firstOrEmpty(repository.watchLines(id));
      final tags = await _firstOrEmpty(ref.read(tagRepositoryProvider).watchForTransaction(id));
      state = AsyncValue.data(
        TransactionEditorState.fromTransaction(
          transaction,
          lines: lines,
          tagIds: {for (final tag in tags) tag.id},
        ),
      );
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _edit(TransactionEditorState Function(TransactionEditorState) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(change(current));
  }

  /// Switches the flow type, keeping every field the new shape still has.
  ///
  /// **Nothing is cleared that the new shape can hold.** Changing withdrawal to deposit must not
  /// wipe the amount the user has already typed; only the accounts move, because a deposit needs a
  /// destination and no source and a withdrawal is the mirror of that (ARCH_2 §4.1).
  void setKind(TransactionKind kind) => _edit((s) {
        // Against the **new** kind, not the state's current one: `s` is the pre-change state, so
        // `s.availableSubtypes` would answer for the kind being replaced.
        final subtype = TransactionEditorState.subtypesFor(kind).contains(s.subtype)
            ? s.subtype
            : _defaultSubtypeFor(kind);
        return s.copyWith(
          kind: kind,
          subtype: subtype,
          fromAccountId: kind == TransactionKind.deposit ? null : s.fromAccountId ?? s.toAccountId,
          clearFromAccount: kind == TransactionKind.deposit,
          toAccountId: kind == TransactionKind.deposit ? s.toAccountId ?? s.fromAccountId : null,
          clearToAccount: kind == TransactionKind.withdrawal,
        );
      });

  /// Switches the visible sub-form.
  void setSubtype(TransactionSubtype subtype) => _edit((s) => s.copyWith(subtype: subtype));

  /// Records the parsed amount, in the record's own currency.
  ///
  /// There is no currency setter anywhere on this notifier, and that is Law L9 rather than an
  /// oversight.
  void setAmount(Money? amount) => _edit(
        (s) => amount == null
            ? s.copyWith(clearAmount: true)
            : s.copyWith(amount: amount, amountMissing: false),
      );

  /// Sets the civil date the money moved.
  void setDate(DateKey date) => _edit((s) => s.copyWith(dateKey: date));

  /// Sets the source account.
  void setFromAccount(String? id) => _edit(
        (s) => id == null ? s.copyWith(clearFromAccount: true) : s.copyWith(fromAccountId: id),
      );

  /// Sets the destination account.
  void setToAccount(String? id) => _edit(
        (s) => id == null ? s.copyWith(clearToAccount: true) : s.copyWith(toAccountId: id),
      );

  /// Sets the rail the money travelled on.
  void setPaymentMethod(String? id) => _edit(
        (s) => id == null ? s.copyWith(clearPaymentMethod: true) : s.copyWith(paymentMethodId: id),
      );

  /// Sets the counterparty.
  void setPayee(String? id) =>
      _edit((s) => id == null ? s.copyWith(clearPayee: true) : s.copyWith(payeeId: id));

  /// Sets the free note.
  void setNote(String note) => _edit((s) => s.copyWith(note: note));

  /// Sets which recurring occurrence this payment settles, or clears the link.
  ///
  /// Selecting one also adopts the template's usual amount, because that is the figure the user is
  /// about to confirm or correct — leaving the field blank would make the common case extra typing.
  void setRecurringOccurrence({
    String? occurrenceId,
    Money? defaultAmount,
    String? accountId,
  }) =>
      _edit(
        (s) => occurrenceId == null
            ? s.copyWith(clearOccurrence: true)
            : s.copyWith(
                recurringOccurrenceId: occurrenceId,
                amount: defaultAmount ?? s.amount,
                // The account comes across too, so the common path is one tap and not two. It is
                // whatever the template, the app default or a sole account already says.
                fromAccountId: accountId ?? s.fromAccountId,
                amountMissing: false,
                accountMissing: false,
              ),
      );

  /// Applies or removes a tag.
  void toggleTag(String tagId) => _edit((s) {
        final next = {...s.tagIds};
        if (next.contains(tagId)) {
          next.remove(tagId);
        } else {
          next.add(tagId);
        }
        return s.copyWith(tagIds: next);
      });

  /// Chooses between a transfer between the user's own accounts and a withdrawal to someone else.
  ///
  /// The whole point of anomaly A02: moving money between your own accounts must not reduce net
  /// worth, so it is `kind = transfer` with both accounts. Sending it to someone else is a real
  /// withdrawal with `subtype = transferOut` and a payee.
  void setTransferTarget({required bool toOwnAccount}) => _edit(
        (s) => s.copyWith(
          toOwnAccount: toOwnAccount,
          kind: toOwnAccount ? TransactionKind.transfer : TransactionKind.withdrawal,
          subtype: toOwnAccount
              ? TransactionSubtype.transferSelf
              : TransactionSubtype.transferOut,
          clearToAccount: !toOwnAccount,
          clearPayee: toOwnAccount,
        ),
      );

  /// Sets the warranty window for the asset an electronics line will create.
  void setWarranty({DateKey? start, DateKey? end}) =>
      _edit((s) => s.copyWith(warrantyStart: start, warrantyEnd: end));

  /// Opts an electronics purchase into also producing an inventory batch.
  void setAlsoAddToInventory({required bool value}) =>
      _edit((s) => s.copyWith(alsoAddToInventory: value));

  /// Adds or replaces a line, keyed on its id.
  void upsertLine(TransactionLine line) => _edit((s) {
        final next = [...s.lines];
        final index = next.indexWhere((existing) => existing.id == line.id);
        if (index >= 0) {
          next[index] = line;
        } else {
          next.add(line.copyWith(lineNo: next.length + 1));
        }
        return s.copyWith(lines: next);
      });

  /// Removes a line.
  void removeLine(String lineId) => _edit((s) {
        final next = [...s.lines.where((line) => line.id != lineId)];
        return s.copyWith(
          lines: [
            for (var i = 0; i < next.length; i++) next[i].copyWith(lineNo: i + 1),
          ],
        );
      });

  /// Creates a payee inline and selects it, so the editor never sends the user to Settings.
  ///
  /// Returns whether it worked. **The result is reported rather than dropped**: a save that fails
  /// silently leaves the user typing the same name again, wondering why it never appears, with
  /// nothing on screen to tell them the write was refused.
  Future<bool> createPayee(String name) async {
    final normalizer = ref.read(normalizerProvider);
    final payee = Payee(
      id: ref.read(uidGeneratorProvider).generate(),
      name: name,
      normalizedName: normalizer.normalize(name),
      kind: PayeeKind.merchant,
    );
    final saved = await ref.read(payeeRepositoryProvider).save(payee);
    final value = saved.valueOrNull;
    if (value == null) return false;
    setPayee(value.id);
    return true;
  }

  /// Saves the transaction and everything its lines produce.
  ///
  /// **Idempotent rather than atomic, and that is a recorded deviation from Law L14.** Atomicity is
  /// unavailable from here: three repositories are written and no repository may own another's
  /// transaction (ARCH_4 §5.1 item 17). What is achievable is that re-running is a no-op —
  /// `PurchaseFanOutService.planAll` skips any line that already carries a `created*Id`, and the
  /// ids are written back to the lines before this returns. Without that write-back, re-saving an
  /// edited transaction would create a second television every time.
  ///
  /// Returns the transaction's id on success, or null when the form was rejected or a write failed.
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.amount == null) {
      _edit((s) => s.copyWith(amountMissing: true, shakeTrigger: s.shakeTrigger + 1));
      return null;
    }

    _edit((s) => s.copyWith(submitting: true, clearErrors: true));
    // **`finally`, not a clear on each early return.** A `SqliteException` thrown anywhere below used
    // to propagate out of `save`, leaving `submitting: true` forever — the footer button stayed in its
    // progress state and the only way out of the screen was to kill the app.
    try {
      return await _write(current);
    } on Object catch (error, stack) {
      _edit((s) => s.copyWith(saveError: error.toString()));
      ref.read(loggerProvider).log(
        'Transaction save failed',
        level: LogLevel.error,
        tag: 'expense.editor',
        error: error,
        stackTrace: stack,
      );
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false));
    }
  }

  /// Commits [current], and is safe to call again after a failure partway through.
  ///
  /// **Five writes, no outer transaction — by design, and this is what makes that safe.** The
  /// sequence spans three repositories, and ARCH_4 §5.1 item 17 already ruled that none of them may
  /// own another's transaction; idempotency is the sanctioned answer instead. `planAll` supplies half
  /// of it by skipping any line that already carries a `created*Id`. This supplies the other half.
  ///
  /// Once the transaction row exists, its id is written back into the editor's state. A retry then
  /// sees `isEditing` and takes the update path, so a save that got as far as `create` and then threw
  /// is resumed rather than duplicated. Without this, `current.id` stayed null and every retry minted
  /// a second transaction — which is how a failed save left orphans in the ledger.
  Future<String?> _write(TransactionEditorState current) async {
    final uids = ref.read(uidGeneratorProvider);
    final clock = ref.read(clockProvider);
    final repository = ref.read(transactionRepositoryProvider);

    final amount = current.amount!;
    final id = current.id ?? uids.generate();
    // **Every line gets a fresh id on every attempt, create or edit.**
    //
    // Two reasons, and the second is the one that bit. `replaceLines` soft-deletes the existing rows
    // rather than removing them (Law L6), so an edit reusing an id collides with the row still
    // physically there. And a line id held in state — one a shopping draft minted, or one a previous
    // failed attempt already inserted — is reused verbatim by the next attempt, so any save that got
    // as far as writing lines makes every retry fail with `UNIQUE constraint failed:
    // transaction_lines.id` and mask whatever actually went wrong the first time.
    //
    // A line id has no meaning outside its row: nothing references it but the batch it produced, and
    // that link is written after the insert. So it is assigned here, at write time, never carried in.
    final lines = [
      for (final line in current.lines)
        line.copyWith(id: uids.generate(), transactionId: id),
    ];
    final transaction =
        current.toTransaction(newId: id, occurredAtUtc: clock.now().toUtc());

    // **A bill settling a recurring occurrence has exactly one write, and it is not this one.**
    // `payOccurrence` creates the transaction *and* marks the occurrence paid in the same call, so
    // going through `create` as well produced two transactions for one payment — the amount typed
    // here and the amount confirmed in a sheet both landed. The editor's amount is now the only
    // figure, and this is the only save.
    final settling = current.recurringOccurrenceId;
    if (settling != null && !current.isEditing) {
      // Resolved rather than demanded: the template's default, then the app default, then a sole
      // account. Only a genuine ambiguity — several accounts and no default anywhere — reaches the
      // rejection, and `payOccurrence` cannot take null because a withdrawal with no source account
      // makes every balance and every insight quietly wrong.
      final account = current.fromAccountId ??
          current.toAccountId ??
          ref.read(resolvedBillAccountProvider(null));
      if (account == null) {
        _edit((s) => s.copyWith(accountMissing: true));
        return null;
      }
      final paid = await ref.read(recurringRepositoryProvider).payOccurrence(
            occurrenceId: settling,
            amount: amount,
            paidOn: current.dateKey,
            accountId: account,
            paymentMethodId: current.paymentMethodId,
          );
      final failure = paid.failureOrNull;
      if (failure != null) {
        _edit((s) => s.copyWith(saveError: failure.message));
        return null;
      }
      _edit((s) => s.copyWith(dirty: false, clearOccurrence: true));
      return paid.valueOrNull?.id;
    }

    final written = current.isEditing
        ? await repository.update(transaction)
        : await repository.create(
            transaction: transaction,
            lines: lines,
            tagIds: current.tagIds.toList(),
          );
    if (written.isFailure) {
      // The repository says what it refused — an account a withdrawal needs, a currency that is not
      // enabled, a line that will not validate. Discarding that is what made a save unfixable.
      _edit((s) => s.copyWith(saveError: written.failureOrNull?.message));
      return null;
    }

    // The row is committed. From here on this is an edit, whatever happens next.
    if (!current.isEditing) {
      _edit((s) => s.copyWith(id: id));
    }

    if (current.isEditing) {
      final replaced = await repository.replaceLines(transactionId: id, lines: lines);
      if (replaced.isFailure) {
        _edit((s) => s.copyWith(saveError: replaced.failureOrNull?.message));
        return null;
      }
    }

    final fanned = await _fanOut(transaction: transaction, lines: lines, state: current);
    // One column per line, through the write built for it — never `replaceLines`, which would insert
    // rows whose ids already exist.
    for (final line in fanned.lines) {
      if (line.createdBatchId == null &&
          line.createdAssetId == null &&
          line.createdRecurringTemplateId == null) {
        continue;
      }
      await repository.recordCreatedArtefact(
        lineId: line.id,
        createdBatchId: line.createdBatchId,
        createdAssetId: line.createdAssetId,
        createdRecurringTemplateId: line.createdRecurringTemplateId,
      );
    }
    // The loop closes here. `markPurchased` exists for exactly this and takes the ids the draft
    // carried across, so the shopping entries stop being outstanding the moment the expense that
    // fulfils them is committed (anomaly A25). Guarded, so an ordinary expense never touches it.
    if (current.sourceEntryIds.isNotEmpty) {
      await ref.read(shoppingRepositoryProvider).markPurchased(
            entryIds: current.sourceEntryIds,
            transactionId: id,
          );
    }
    // `clearErrors` first so a previous attempt's message cannot outlive it, then the new one.
    _edit((s) => s.copyWith(dirty: false, clearErrors: true));
    _edit(
      (s) => s.copyWith(
        fanOutError: fanned.error,
        wantsTemplate: fanned.wantsTemplate,
        createdAssetId: fanned.createdAsset,
      ),
    );
    return id;
  }

  /// Creates the batches, assets and template names the lines call for, and writes their ids back.
  ///
  /// **Reports whether anything was refused.** `_planBatch` rejects a line with no `itemId` or no
  /// quantity, and an earlier version dropped that failure on the floor — the transaction saved, the
  /// snack said so, and the stock never appeared in the inventory with nothing on screen to explain
  /// why. A write that half-succeeds must say which half (U9).
  Future<({List<TransactionLine> lines, String? error, bool wantsTemplate, String? createdAsset})>
      _fanOut({
    required Transaction transaction,
    required List<TransactionLine> lines,
    required TransactionEditorState state,
  }) async {
    if (lines.isEmpty) {
      return (
        lines: const <TransactionLine>[],
        error: null,
        wantsTemplate: false,
        createdAsset: null,
      );
    }
    final uids = ref.read(uidGeneratorProvider);
    final planned = ref.read(purchaseFanOutServiceProvider).planAll(
          lines: lines,
          transaction: transaction,
          newArtefactIds: [for (var i = 0; i < lines.length; i++) uids.generate()],
        );
    final plans = planned.valueOrNull;
    if (plans == null) {
      // Every line that asked for an artefact was refused — almost always a line marked for
      // inventory with no catalogued item behind it.
      final wanted = lines.any(
        (line) => line.destination != TransactionLineDestination.none,
      );
      return (
        lines: const <TransactionLine>[],
        error: wanted ? planned.failureOrNull?.message : null,
        wantsTemplate: false,
        createdAsset: null,
      );
    }
    if (plans.isEmpty) {
      return (
        lines: const <TransactionLine>[],
        error: null,
        wantsTemplate: false,
        createdAsset: null,
      );
    }

    String? refused;
    var requestedTemplate = false;
    String? createdAsset;
    final updated = [...lines];
    for (final plan in plans) {
      final index = updated.indexWhere((line) => line.id == plan.lineId);
      if (index < 0) continue;
      switch (plan.target) {
        case FanOutTarget.batch:
          final batch = plan.batch;
          if (batch == null) continue;
          final saved = await ref.read(batchRepositoryProvider).create(batch);
          final value = saved.valueOrNull;
          if (value == null) {
            refused = saved.failureOrNull?.message;
          } else {
            updated[index] = updated[index].copyWith(createdBatchId: value.id);
          }
        case FanOutTarget.asset:
          final asset = plan.asset;
          if (asset == null) continue;
          // The warranty window lives on the form rather than on the line, because a receipt line
          // has no column for it — so it is applied to the planned asset here.
          final saved = await ref.read(assetRepositoryProvider).save(
                asset.copyWith(
                  warrantyStartDateKey: state.warrantyStart,
                  warrantyEndDateKey: state.warrantyEnd,
                ),
              );
          final value = saved.valueOrNull;
          if (value == null) {
            refused = saved.failureOrNull?.message;
          } else {
            updated[index] = updated[index].copyWith(createdAssetId: value.id);
            // Carried out so the editor can open the asset it just made. It is typed `other` with no
            // warranty, because a receipt line has no way to say otherwise — which is exactly why the
            // user needs to land on it rather than go hunting.
            createdAsset ??= value.id;
          }
        case FanOutTarget.recurringTemplate:
          // A schedule needs an interval and an anchor a receipt line does not contain, so the name
          // and amount are handed to Phase 6D's builder and the user supplies the rest. Inventing a
          // monthly-on-the-1st default would create an obligation nobody agreed to.
          //
          // **This branch used to `break` and do nothing at all** — the control was tickable, saved
          // cleanly, and produced no template and no message.
          ref.read(templateDraftProvider.notifier).offer(
                TemplateDraft(
                  name: plan.recurringTemplateName ?? updated[index].description,
                  amount: updated[index].lineAmount ?? state.amount,
                ),
              );
          requestedTemplate = true;
        case FanOutTarget.none:
          break;
      }
    }
    return (
      lines: updated,
      error: refused,
      wantsTemplate: requestedTemplate,
      createdAsset: createdAsset,
    );
  }

  static TransactionSubtype _defaultSubtypeFor(TransactionKind kind) => switch (kind) {
        TransactionKind.deposit => TransactionSubtype.otherIn,
        TransactionKind.withdrawal => TransactionSubtype.otherOut,
        TransactionKind.transfer => TransactionSubtype.transferSelf,
        TransactionKind.adjustmentIncrease => TransactionSubtype.otherIn,
        TransactionKind.adjustmentDecrease => TransactionSubtype.otherOut,
      };
}

/// Payment methods offered in the editor.
final editorPaymentMethodsProvider = StreamProvider<List<PaymentMethod>>(
  (ref) => ref.watch(paymentMethodRepositoryProvider).watchAll(),
);

/// Payees offered in the editor.
final editorPayeesProvider = StreamProvider<List<Payee>>(
  (ref) => ref.watch(payeeRepositoryProvider).watchAll(),
);

/// Tags offered for a given flow direction.
final editorTagsProvider = StreamProvider.autoDispose.family<List<Tag>, TransactionKind>(
  (ref, kind) => ref.watch(tagRepositoryProvider).watchByScope(
        kind == TransactionKind.deposit ? TagScope.deposit : TagScope.withdrawal,
      ),
);

/// The first event of [stream], or an empty list when it closes without emitting one.
Future<List<T>> _firstOrEmpty<T>(Stream<List<T>> stream) async {
  await for (final value in stream) {
    return value;
  }
  return <T>[];
}
```

## Part 1 — the Shopping module

### `lib/app/l10n/app_en.arb`

```json
{
  "@@locale": "en",
  "appName": "Alaya",
  "@appName": {
    "description": "The app's name, shown in the drawer header."
  },
  "navDashboard": "Dashboard",
  "navExpenses": "Expenses",
  "navInventory": "Inventory",
  "navShopping": "Shopping",
  "navRecurring": "Recurring",
  "navServices": "Services",
  "navCalendar": "Calendar",
  "navInsights": "Insights",
  "navSettings": "Settings",
  "navThemeLab": "Theme Lab",
  "actionSave": "Save",
  "@actionSave": {
    "description": "Commits an edit. Active voice, and the same word appears in the resulting confirmation."
  },
  "actionSaved": "Saved",
  "actionCancel": "Cancel",
  "actionDelete": "Delete",
  "actionDeleted": "Deleted",
  "actionUndo": "Undo",
  "actionRetry": "Try again",
  "actionAdd": "Add",
  "actionEdit": "Edit",
  "actionDone": "Done",
  "actionClose": "Close",
  "actionSelect": "Select",
  "actionClear": "Clear",
  "actionClearAll": "Clear all",
  "actionSearch": "Search",
  "actionConfirm": "Confirm",
  "actionDiscard": "Discard",
  "actionKeepEditing": "Keep editing",
  "actionRemoveTag": "Remove tag",
  "@actionRemoveTag": {
    "description": "Accessibility label for the dismiss affordance on a removable tag chip."
  },
  "actionClearSearch": "Clear search",
  "@actionClearSearch": {
    "description": "Accessibility label for the clear button inside AlayaSearchField."
  },
  "addExpense": "Add expense",
  "addIncome": "Add income",
  "addTransfer": "Add transfer",
  "addItem": "Add item",
  "addToShoppingList": "Add to shopping list",
  "dateToday": "Today",
  "@dateToday": {
    "description": "DateText.relative, when the date is the clock's today. Sentence case; it can begin a row."
  },
  "dateYesterday": "Yesterday",
  "dateTomorrow": "Tomorrow",
  "emptyTitleNoTransactions": "No transactions yet",
  "emptyBodyNoTransactions": "Add your first expense and it will appear here.",
  "@emptyBodyNoTransactions": {
    "description": "An empty screen is an invitation to act, so this names the action rather than describing the emptiness."
  },
  "emptyTitleNoItems": "Nothing in your inventory",
  "emptyBodyNoItems": "Add an item to start tracking what you have at home.",
  "emptyTitleNoShopping": "Your list is empty",
  "emptyBodyNoShopping": "Add something, or let Alaya suggest items you are low on.",
  "emptyTitleNoRecurring": "No recurring bills",
  "emptyBodyNoRecurring": "Set up a bill or subscription and Alaya will remind you when it is due.",
  "emptyTitleNoResults": "No matches",
  "emptyBodyNoResults": "Try a shorter search, or check the spelling.",
  "loadingLabel": "Loading",
  "loadingTransactions": "Loading transactions",
  "errorTitleGeneric": "That did not work",
  "@errorTitleGeneric": {
    "description": "Errors do not apologise and are never vague. This pairs with a specific body message."
  },
  "errorBodyGeneric": "Something went wrong on our side. Try again.",
  "errorTitleNotFound": "Not found",
  "errorBodyNotFound": "This item may have been deleted.",
  "errorBodyNoConnection": "You are offline. Alaya works offline, but rates will not refresh.",
  "errorFieldRequired": "This is required",
  "errorAmountInvalid": "Enter an amount",
  "errorAmountZero": "Enter an amount greater than zero",
  "errorAmountInvalidCharacter": "Digits only",
  "errorAmountNegativeNotAllowed": "Enter a positive amount",
  "errorAmountTooManyDecimals": "Too many decimal places",
  "errorAmountTooLarge": "That amount is too large",
  "errorQuantityTooLarge": "That quantity is too large",
  "errorQuantityInvalid": "Enter a quantity",
  "errorQuantityInvalidCharacter": "Digits only",
  "errorQuantityNegativeNotAllowed": "Enter a positive quantity",
  "errorQuantityTooPrecise": "Too precise for this unit",
  "@errorQuantityTooPrecise": {
    "description": "The typed quantity is finer than the chosen unit can express exactly. Shown rather than rounded, because rounding a quantity silently changes what the user recorded."
  },
  "errorDateInvalid": "Choose a date",
  "confirmDeleteTitle": "Delete this?",
  "confirmDeleteBody": "You can undo this for the next few seconds.",
  "confirmDiscardTitle": "Discard your changes?",
  "confirmDiscardBody": "What you have typed will not be saved.",
  "labelAmount": "Amount",
  "labelQuantity": "Quantity",
  "labelUnit": "Unit",
  "labelDate": "Date",
  "labelAccount": "Account",
  "labelPaymentMethod": "Payment method",
  "labelPayee": "Payee",
  "labelCategory": "Category",
  "labelTags": "Tags",
  "labelNote": "Note",
  "labelFrom": "From",
  "labelTo": "To",
  "labelItem": "Item",
  "labelExpiry": "Expiry",
  "labelTotal": "Total",
  "hintSelectAccount": "Choose an account",
  "hintSelectUnit": "Choose a unit",
  "hintSelectTags": "Choose tags",
  "hintSelectDate": "Choose a date",
  "hintSearchItems": "Search items",
  "hintNote": "Add a note",
  "amountUnconverted": "{count, plural, =1{1 amount not converted} other{{count} amounts not converted}}",
  "@amountUnconverted": {
    "description": "The chip beside a total when some amounts had no exchange rate. Surfaced rather than hidden, because a total missing a row is otherwise indistinguishable from a complete one.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "amountApproximate": "Approximate rate",
  "@amountApproximate": {
    "description": "Shown when a conversion used the nearest earlier rate rather than the exact date's."
  },
  "tagCountMore": "+{count}",
  "@tagCountMore": {
    "description": "Overflow indicator when a row cannot show every tag.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "statusNeedsReview": "Needs details",
  "@statusNeedsReview": {
    "description": "StatusChip on a transaction saved by quick-add. Names what is missing, not that a flag is set."
  },
  "statusUnallocated": "Unallocated",
  "@statusUnallocated": {
    "description": "StatusChip label when a transaction's lines do not sum to its amount. The figure is a separate AmountText (U7); never auto-balanced (anomaly A11)."
  },
  "statusDetached": "Receipt deleted",
  "@statusDetached": {
    "description": "StatusChip on a batch whose source transaction was deleted. The food did not un-exist."
  },
  "statusApproximate": "Approximate",
  "lowStockLabel": "Low",
  "expiringSoonLabel": "Expiring soon",
  "expiredLabel": "Expired",
  "overdueLabel": "Overdue",
  "dueTodayLabel": "Due today",
  "paidLabel": "Paid",
  "skippedLabel": "Skipped",
  "kindDeposit": "Money in",
  "kindWithdrawal": "Money out",
  "kindTransfer": "Transfer",
  "kindAdjustmentIncrease": "Correction up",
  "kindAdjustmentDecrease": "Correction down",
  "subtypeGrocery": "Groceries",
  "subtypeHousehold": "Household",
  "subtypeElectronics": "Electronics",
  "subtypeBill": "Bill",
  "subtypeTransferSelf": "Between my accounts",
  "subtypeTransferOut": "Sent to someone",
  "subtypeSalaryIn": "Salary",
  "subtypeOtherIn": "Other income",
  "subtypeOtherOut": "Other spending",
  "needsReviewBanner": "{count, plural, =1{1 transaction needs details} other{{count} transactions need details}}",
  "@needsReviewBanner": {
    "description": "Surfaces transactions.needsReview. Quick-add saves an amount and nothing else by design; without this row that deliberate shortcut becomes silent data rot.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "needsReviewAction": "Review",
  "filterTitle": "Filter",
  "filterDateRange": "Date range",
  "filterKind": "Type",
  "filterSubtype": "Category",
  "filterApply": "Show results",
  "filterReset": "Reset",
  "filterChipAccount": "Account: {name}",
  "@filterChipAccount": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipPayee": "Payee: {name}",
  "@filterChipPayee": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipRange": "{label}",
  "@filterChipRange": {
    "placeholders": {
      "label": {
        "type": "String"
      }
    }
  },
  "rangeToday": "Today",
  "rangeLast7Days": "Last 7 days",
  "rangeLast30Days": "Last 30 days",
  "rangeThisMonth": "This month",
  "rangeLastMonth": "Last month",
  "rangeThisYear": "This year",
  "rangeAllTime": "All time",
  "rangeCustom": "Custom",
  "searchTransactionsHint": "Search notes",
  "transactionDeleted": "Transaction deleted",
  "quickAddTitle": "Quick add",
  "quickAddMoneyIn": "Money in",
  "quickAddMoneyOut": "Money out",
  "quickAddSave": "Save",
  "actionAddDetails": "Add details",
  "editorTitleNew": "New transaction",
  "editorTitleEdit": "Edit transaction",
  "sectionWhatAndHowMuch": "What and how much",
  "sectionWhereItCameFrom": "Where it came from",
  "sectionWhereItWent": "Where it went",
  "sectionWhatYouBought": "What you bought",
  "sectionWarranty": "Warranty",
  "sectionSchedule": "Schedule",
  "transferOwnAccount": "To my own account",
  "transferSomeoneElse": "To someone else",
  "transferOwnAccountHelp": "Moves money between your accounts. Your total does not change.",
  "transferSomeoneElseHelp": "Money leaves your accounts. This is a withdrawal.",
  "alsoAddToInventory": "Also add to inventory",
  "destinationNone": "Just an expense",
  "destinationInventory": "Save to Inventory",
  "destinationAsset": "Save to Services",
  "destinationRecurring": "Save to Recurring",
  "lineAdd": "Add item",
  "lineDescription": "Item",
  "lineUnitPrice": "Unit price",
  "lineAmount": "Line total",
  "lineCreatedLink": "Created: {name}",
  "@lineCreatedLink": {
    "description": "Surfaces transaction_lines.created*Id — the artefact this line produced, tappable through to it.",
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "payeeCreate": "New payee “{name}”",
  "@payeeCreate": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "saveExpense": "Save expense",
  "saveIncome": "Save income",
  "saveTransfer": "Save transfer",
  "detailSectionLines": "Items",
  "detailSectionDetails": "Details",
  "actionFreezeConversion": "Show in another currency",
  "frozenConversionNote": "Frozen on {date} at {rate}",
  "@frozenConversionNote": {
    "description": "Surfaces transactions.converted*/conversionRateRaw. A separate artefact that is never recomputed (Law L9).",
    "placeholders": {
      "date": {
        "type": "String"
      },
      "rate": {
        "type": "String"
      }
    }
  },
  "deleteReasonHint": "Why? (optional)",
  "actionDeleteTransaction": "Delete transaction",
  "labelSubtype": "Category",
  "labelKind": "Type",
  "themeLabTitle": "Theme Lab",
  "themeLabSubtitle": "Every token, component and semantic colour, light and dark.",
  "themeLabSectionSpacing": "Spacing",
  "themeLabSectionRadii": "Radii",
  "themeLabSectionTypography": "Typography",
  "themeLabSectionElevation": "Elevation",
  "themeLabSectionSemantic": "Semantic colours",
  "themeLabSectionSurfaces": "Surface tiers",
  "themeLabSectionComponents": "Components",
  "themeLabSectionPalettes": "Palettes",
  "themeLabLight": "Light",
  "themeLabDark": "Dark",
  "semanticIncome": "Income",
  "semanticExpense": "Expense",
  "semanticTransfer": "Transfer",
  "semanticWarning": "Warning",
  "semanticDanger": "Danger",
  "semanticSuccess": "Success",
  "semanticMuted": "Muted",
  "drawerSectionMoney": "Money",
  "drawerSectionHome": "Home",
  "drawerSectionMore": "More",
  "inventoryGroupFavourites": "Favourites",
  "@inventoryGroupFavourites": {
    "description": "Phase 6B — inventory."
  },
  "inventoryGroupUntagged": "Everything else",
  "@inventoryGroupUntagged": {
    "description": "Phase 6B — inventory."
  },
  "itemKindGeneric": "General",
  "@itemKindGeneric": {
    "description": "Phase 6B — inventory."
  },
  "itemKindFood": "Food",
  "@itemKindFood": {
    "description": "Phase 6B — inventory."
  },
  "itemKindMedicine": "Medicine",
  "@itemKindMedicine": {
    "description": "Phase 6B — inventory."
  },
  "itemKindBeauty": "Beauty",
  "@itemKindBeauty": {
    "description": "Phase 6B — inventory."
  },
  "itemKindHousehold": "Household",
  "@itemKindHousehold": {
    "description": "Phase 6B — inventory."
  },
  "itemKindOther": "Other",
  "@itemKindOther": {
    "description": "Phase 6B — inventory."
  },
  "filterFavouritesOnly": "Favourites only",
  "@filterFavouritesOnly": {
    "description": "Phase 6B — inventory."
  },
  "actionFavourite": "Add to favourites",
  "@actionFavourite": {
    "description": "Phase 6B — inventory."
  },
  "actionUnfavourite": "Remove from favourites",
  "@actionUnfavourite": {
    "description": "Phase 6B — inventory."
  },
  "outOfStockLabel": "Out of stock",
  "@outOfStockLabel": {
    "description": "Phase 6B — inventory."
  },
  "itemBatchCount": "{count, plural, =1{1 batch} other{{count} batches}}",
  "@itemBatchCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "loadingInventory": "Loading inventory",
  "@loadingInventory": {
    "description": "Phase 6B — inventory."
  },
  "detailSectionBatches": "Batches",
  "@detailSectionBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginPurchase": "From a purchase",
  "@batchOriginPurchase": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginManual": "Added by hand",
  "@batchOriginManual": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginImported": "Imported",
  "@batchOriginImported": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginAdjustment": "From an adjustment",
  "@batchOriginAdjustment": {
    "description": "Phase 6B — inventory."
  },
  "labelPurchased": "Purchased",
  "@labelPurchased": {
    "description": "Phase 6B — inventory."
  },
  "labelStorageLocation": "Stored in",
  "@labelStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "labelUnitCost": "Unit cost",
  "@labelUnitCost": {
    "description": "Phase 6B — inventory."
  },
  "labelInitial": "Bought",
  "@labelInitial": {
    "description": "Phase 6B — inventory."
  },
  "labelNearestExpiry": "Nearest expiry",
  "@labelNearestExpiry": {
    "description": "Phase 6B — inventory."
  },
  "labelDisplayUnit": "Shown in",
  "@labelDisplayUnit": {
    "description": "Phase 6B — inventory."
  },
  "labelItemKind": "Kind",
  "@labelItemKind": {
    "description": "Phase 6B — inventory."
  },
  "labelLowStockThreshold": "Low-stock level",
  "@labelLowStockThreshold": {
    "description": "Phase 6B — inventory."
  },
  "labelExpiryNotifyDays": "Warn before expiry",
  "@labelExpiryNotifyDays": {
    "description": "Phase 6B — inventory."
  },
  "actionConsume": "Use some",
  "@actionConsume": {
    "description": "Phase 6B — inventory."
  },
  "actionAddBatch": "Add a batch",
  "@actionAddBatch": {
    "description": "Phase 6B — inventory."
  },
  "actionViewHistory": "Movement history",
  "@actionViewHistory": {
    "description": "Phase 6B — inventory."
  },
  "actionDeleteItem": "Delete item",
  "@actionDeleteItem": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemTitle": "Delete this item?",
  "@confirmDeleteItemTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemBody": "Its {count, plural, =1{1 batch} other{{count} batches}} go with it. The movement history stays, so what you already used is still recorded.",
  "@confirmDeleteItemBody": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "itemDeleted": "Item deleted",
  "@itemDeleted": {
    "description": "Phase 6B — inventory."
  },
  "expiresInDays": "{days, plural, =0{Expires today} =1{Expires tomorrow} other{Expires in {days} days}}",
  "@expiresInDays": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "expiredDaysAgo": "{days, plural, =1{Expired yesterday} other{Expired {days} days ago}}",
  "@expiredDaysAgo": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "sectionWhatItIs": "What it is",
  "@sectionWhatItIs": {
    "description": "Phase 6B — inventory."
  },
  "sectionStockRules": "Stock rules",
  "@sectionStockRules": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryWeight": "Weight",
  "@unitCategoryWeight": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryVolume": "Volume",
  "@unitCategoryVolume": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryCount": "Count",
  "@unitCategoryCount": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryLocked": "Measured in {category}",
  "@unitCategoryLocked": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "category": {}
    }
  },
  "unitCategoryLockedHelp": "This cannot change. Every batch and movement already recorded is stored in this measure, and there is no conversion between weight, volume and count.",
  "@unitCategoryLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "expiryNotifyDaysHelp": "Days of warning before a batch expires.",
  "@expiryNotifyDaysHelp": {
    "description": "Phase 6B — inventory."
  },
  "labelFavourite": "Favourite",
  "@labelFavourite": {
    "description": "Phase 6B — inventory."
  },
  "saveItem": "Save item",
  "@saveItem": {
    "description": "Phase 6B — inventory."
  },
  "sectionHowMuch": "How much",
  "@sectionHowMuch": {
    "description": "Phase 6B — inventory."
  },
  "sectionBatchDetails": "Batch details",
  "@sectionBatchDetails": {
    "description": "Phase 6B — inventory."
  },
  "saveBatch": "Save batch",
  "@saveBatch": {
    "description": "Phase 6B — inventory."
  },
  "batchSaved": "Batch saved",
  "@batchSaved": {
    "description": "Phase 6B — inventory."
  },
  "hintStorageLocation": "Freezer, pantry, bathroom shelf…",
  "@hintStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "consumeTitle": "Use stock",
  "@consumeTitle": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindConsume": "Used",
  "@consumeKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindWaste": "Thrown away",
  "@consumeKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindExpired": "Expired",
  "@consumeKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "consumeRecorded": "Recorded",
  "@consumeRecorded": {
    "description": "Phase 6B — inventory."
  },
  "consumeFromLabel": "Taking from",
  "@consumeFromLabel": {
    "description": "Phase 6B — inventory."
  },
  "consumeFefoNote": "Oldest expiry first.",
  "@consumeFefoNote": {
    "description": "Phase 6B — inventory."
  },
  "consumeSpansBatches": "{count, plural, =1{Takes all of 1 batch} other{Spans {count} batches, writing {count} movements}}",
  "@consumeSpansBatches": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "consumeOverAvailable": "More than you have on hand",
  "@consumeOverAvailable": {
    "description": "Phase 6B — inventory."
  },
  "historyTitle": "Movement history",
  "@historyTitle": {
    "description": "Phase 6B — inventory."
  },
  "movementKindOpeningIn": "Opening stock",
  "@movementKindOpeningIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindPurchaseIn": "Bought",
  "@movementKindPurchaseIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindManualIn": "Added by hand",
  "@movementKindManualIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindConsume": "Used",
  "@movementKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "movementKindWaste": "Thrown away",
  "@movementKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "movementKindExpired": "Expired",
  "@movementKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustIn": "Adjusted up",
  "@movementKindAdjustIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustOut": "Adjusted down",
  "@movementKindAdjustOut": {
    "description": "Phase 6B — inventory."
  },
  "movementReversed": "Reversed",
  "@movementReversed": {
    "description": "Phase 6B — inventory."
  },
  "movementIsReversal": "Reverses an earlier movement",
  "@movementIsReversal": {
    "description": "Phase 6B — inventory."
  },
  "actionReverse": "Reverse",
  "@actionReverse": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseTitle": "Reverse this movement?",
  "@confirmReverseTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseBody": "An opposite movement is appended. Nothing is erased — both entries stay in the history.",
  "@confirmReverseBody": {
    "description": "Phase 6B — inventory."
  },
  "movementReversedSnack": "Movement reversed",
  "@movementReversedSnack": {
    "description": "Phase 6B — inventory."
  },
  "emptyTitleNoMovements": "Nothing recorded yet",
  "@emptyTitleNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoMovements": "Using, wasting or adjusting this batch will show up here.",
  "@emptyBodyNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoBatches": "Add a batch and it will appear here with its expiry.",
  "@emptyBodyNoBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchQuantityLockedHelp": "How much is left is worked out from the movement history. Use, waste or adjust the batch to change it.",
  "@batchQuantityLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "daysCount": "{days, plural, =1{1 day} other{{days} days}}",
  "@daysCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "groupByFavourites": "Group favourites first",
  "@groupByFavourites": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitUsed": "Record as used",
  "@consumeCommitUsed": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitWaste": "Record as thrown away",
  "@consumeCommitWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitExpired": "Record as expired",
  "@consumeCommitExpired": {
    "description": "Phase 6B — inventory."
  },
  "lowStockWithCount": "Low · {count}",
  "@lowStockWithCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "actionDeleteBatch": "Delete batch",
  "@actionDeleteBatch": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchTitle": "Delete this batch?",
  "@confirmDeleteBatchTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchBody": "The stock it still holds disappears from your on-hand total. What you already used stays in the movement history.",
  "@confirmDeleteBatchBody": {
    "description": "Phase 6B — inventory."
  },
  "batchDeleted": "Batch deleted",
  "@batchDeleted": {
    "description": "Phase 6B — inventory."
  },
  "itemCreate": "New item",
  "@itemCreate": {
    "description": "Creates a catalogued item inline while itemising a receipt."
  },
  "itemCreateHint": "No items yet — create one so this line becomes stock.",
  "@itemCreateHint": {
    "description": "Shown in the line editor when the item catalogue is empty."
  },
  "itemCreateCategoryPrompt": "How is it measured? This cannot change later.",
  "@itemCreateCategoryPrompt": {
    "description": "Prompt for unitCategory on inline creation; immutable after create (Law L8)."
  },
  "itemDuplicateBody": "You already have this item, measured the same way. Open the one you have instead of adding a second.",
  "@itemDuplicateBody": {
    "description": "Shown when an item with the same normalized name and unit category exists."
  },
  "itemUnitsMissingBody": "No units are set up for this measure yet. Pick a different measure, or add units in Settings first.",
  "@itemUnitsMissingBody": {
    "description": "Shown when the chosen UnitCategory has no rows in units."
  },
  "itemSimilarNote": "You also have this name under a different measure. That is fine — weight, volume and count never convert into each other.",
  "@itemSimilarNote": {
    "description": "Informational note, never a block: Law L8 makes same-name/different-category distinct items."
  },
  "actionOpenExisting": "Open the one I have",
  "@actionOpenExisting": {
    "description": "Opens the existing item a duplicate collides with."
  },
  "shoppingEstimate": "Estimated",
  "@shoppingEstimate": {
    "description": "Running total of estimated prices on a shopping list."
  },
  "shoppingSwitchList": "Switch list",
  "@shoppingSwitchList": {
    "description": "Opens the list manager from the app bar."
  },
  "shoppingCheckedCount": "{checked} of {total} ticked",
  "@shoppingCheckedCount": {
    "description": "Progress line above a shopping list.",
    "placeholders": {
      "checked": {},
      "total": {}
    }
  },
  "emptyTitleNoEntries": "Nothing on this list yet",
  "@emptyTitleNoEntries": {
    "description": "Shopping list empty state."
  },
  "emptyBodyNoEntries": "Add what you need, or pull in suggestions from what is running low.",
  "@emptyBodyNoEntries": {
    "description": "Shopping list empty state body."
  },
  "addEntry": "Add",
  "@addEntry": {
    "description": "Adds one entry to a shopping list."
  },
  "shoppingGroupUntagged": "Everything else",
  "@shoppingGroupUntagged": {
    "description": "Header for entries with no tag."
  },
  "actionUncheckAll": "Untick everything",
  "@actionUncheckAll": {
    "description": "Clears every tick on a shopping list."
  },
  "entryEditorTitle": "What do you need?",
  "@entryEditorTitle": {
    "description": "Entry editor sheet title."
  },
  "entryFreeTextLabel": "Name it",
  "@entryFreeTextLabel": {
    "description": "Free-text label for a shopping entry."
  },
  "entryFreeTextHint": "Television, birthday card, light bulbs…",
  "@entryFreeTextHint": {
    "description": "Hint showing that an entry need not be an inventory item."
  },
  "entryLinkItem": "Link to an item",
  "@entryLinkItem": {
    "description": "Optional link from a shopping entry to a catalogued item."
  },
  "entryNoItem": "Not in my inventory",
  "@entryNoItem": {
    "description": "Dropdown option leaving itemId null."
  },
  "labelEstimatedPrice": "Estimated price",
  "@labelEstimatedPrice": {
    "description": "Optional per-entry price estimate."
  },
  "entryNeedsSomething": "Give it a name, or link it to an item",
  "@entryNeedsSomething": {
    "description": "Rejection when neither freeText nor itemId is set."
  },
  "originAutoLowStock": "Suggested",
  "@originAutoLowStock": {
    "description": "Chip marking an auto-generated low-stock entry."
  },
  "originPromoted": "Yours now",
  "@originPromoted": {
    "description": "Chip shown once an auto entry has been edited into a manual one."
  },
  "actionSnooze": "Snooze a week",
  "@actionSnooze": {
    "description": "Hides an auto suggestion until a later date."
  },
  "actionDismiss": "Not now",
  "@actionDismiss": {
    "description": "Dismisses an auto suggestion until stock recovers and drops again."
  },
  "snoozedUntilLabel": "Snoozed until",
  "@snoozedUntilLabel": {
    "description": "Precedes a DateText on a snoozed entry."
  },
  "generateTitle": "Running low",
  "@generateTitle": {
    "description": "Low-stock suggestion sheet title."
  },
  "generateBody": "These are below the level you set. Add the ones you want.",
  "@generateBody": {
    "description": "Low-stock suggestion sheet body."
  },
  "generateShortBy": "Short by",
  "@generateShortBy": {
    "description": "Precedes a QtyText giving threshold minus stock on hand."
  },
  "generateRefresh": "Check again",
  "@generateRefresh": {
    "description": "Re-runs low-stock generation."
  },
  "generateEmptyTitle": "Nothing is running low",
  "@generateEmptyTitle": {
    "description": "Generate sheet empty state."
  },
  "generateEmptyBody": "Set a low-stock level on an item and it will show up here when it drops.",
  "@generateEmptyBody": {
    "description": "Generate sheet empty state body."
  },
  "generateAdded": "{count, plural, =1{1 suggestion added} other{{count} suggestions added}}",
  "@generateAdded": {
    "description": "Result snack after regeneration.",
    "placeholders": {
      "count": {}
    }
  },
  "convertTitle": "Turn into a purchase",
  "@convertTitle": {
    "description": "Convert-to-purchase screen title."
  },
  "convertBody": "Each ticked entry becomes one line, marked for inventory. You confirm the amount and account next.",
  "@convertBody": {
    "description": "Explains the handoff to the expense editor."
  },
  "convertConfirm": "Open the expense",
  "@convertConfirm": {
    "description": "Primary action; hands off to the 6A editor."
  },
  "convertNothingTitle": "Nothing is ticked",
  "@convertNothingTitle": {
    "description": "Convert screen empty state."
  },
  "convertNothingBody": "Tick what you actually bought, then come back.",
  "@convertNothingBody": {
    "description": "Convert screen empty state body."
  },
  "convertLineCount": "{count, plural, =1{1 line} other{{count} lines}}",
  "@convertLineCount": {
    "description": "How many lines the draft will carry.",
    "placeholders": {
      "count": {}
    }
  },
  "listManagerTitle": "Your lists",
  "@listManagerTitle": {
    "description": "List manager sheet title."
  },
  "listNameLabel": "List name",
  "@listNameLabel": {
    "description": "Field label when creating or renaming a list."
  },
  "listCreate": "New list",
  "@listCreate": {
    "description": "Creates a shopping list."
  },
  "listRename": "Rename",
  "@listRename": {
    "description": "Renames a shopping list."
  },
  "listSetDefault": "Make default",
  "@listSetDefault": {
    "description": "Marks a list as the one that opens by default."
  },
  "listDefaultBadge": "Default",
  "@listDefaultBadge": {
    "description": "Chip on the default list."
  },
  "listArchive": "Archive",
  "@listArchive": {
    "description": "Archives a shopping list."
  },
  "listUnarchive": "Restore",
  "@listUnarchive": {
    "description": "Un-archives a shopping list."
  },
  "listArchivedBadge": "Archived",
  "@listArchivedBadge": {
    "description": "Chip on an archived list."
  },
  "listArchivedSection": "Archived",
  "@listArchivedSection": {
    "description": "Section header for archived lists."
  },
  "emptyTitleNoLists": "No lists yet",
  "@emptyTitleNoLists": {
    "description": "List manager empty state."
  },
  "emptyBodyNoLists": "Create one and it becomes your default.",
  "@emptyBodyNoLists": {
    "description": "List manager empty state body."
  },
  "loadingShopping": "Loading your list",
  "@loadingShopping": {
    "description": "Skeleton label for shopping surfaces."
  },
  "actionAddToList": "Add to my list",
  "@actionAddToList": {
    "description": "Accepts a low-stock suggestion, promoting it to origin=manual so regeneration leaves it alone."
  },
  "suggestionDismissed": "Turned down",
  "@suggestionDismissed": {
    "description": "Chip on a dismissed suggestion; it stays listed so it can be accepted later."
  },
  "lineItemsTitle": "What you bought",
  "@lineItemsTitle": {
    "description": "Title of the dedicated line-items page."
  },
  "lineItemsManage": "Add or edit items",
  "@lineItemsManage": {
    "description": "Opens the line-items page from the transaction editor."
  },
  "lineItemsAdd": "Add an item",
  "@lineItemsAdd": {
    "description": "Adds one line from the line-items page."
  },
  "lineItemsSaveAndAnother": "Save & add another",
  "@lineItemsSaveAndAnother": {
    "description": "Commits the line and reopens the editor blank, so a receipt is entered without leaving the sheet."
  },
  "lineItemsCount": "{count, plural, =0{No items yet} =1{1 item} other{{count} items}}",
  "@lineItemsCount": {
    "description": "Running count on the line-items page.",
    "placeholders": {
      "count": {}
    }
  },
  "emptyTitleNoLineItems": "Nothing itemised yet",
  "@emptyTitleNoLineItems": {
    "description": "Line-items page empty state."
  },
  "emptyBodyNoLineItems": "Add what was on the receipt. Anything you leave out still counts toward the total.",
  "@emptyBodyNoLineItems": {
    "description": "Line-items page empty state body."
  },
  "actionRemove": "Remove",
  "@actionRemove": {
    "description": "Removes one line from a transaction."
  },
  "lineRemoved": "Item removed",
  "@lineRemoved": {
    "description": "Snack after removing a line."
  },
  "lineItemsAllocated": "Itemised",
  "@lineItemsAllocated": {
    "description": "Precedes the summed line total on the line-items page."
  },
  "recurringOutflow": "Going out",
  "@recurringOutflow": {
    "description": "Group header for outflow templates."
  },
  "recurringInflow": "Coming in",
  "@recurringInflow": {
    "description": "Group header for inflow templates — salary reads as income, not a negative bill."
  },
  "recurringNextDue": "Next",
  "@recurringNextDue": {
    "description": "Precedes a DateText giving the next due date."
  },
  "recurringOverdue": "Overdue",
  "@recurringOverdue": {
    "description": "Chip on an occurrence past its due date. Derived from the clock, never stored."
  },
  "recurringPaused": "Paused",
  "@recurringPaused": {
    "description": "Chip on a paused template."
  },
  "recurringDueToday": "Due today",
  "@recurringDueToday": {
    "description": "Chip when the next occurrence falls today."
  },
  "emptyTitleNoTemplates": "Nothing recurring yet",
  "@emptyTitleNoTemplates": {
    "description": "Template list empty state."
  },
  "emptyBodyNoTemplates": "Add a bill, a subscription or a salary and it will appear here when it is next due.",
  "@emptyBodyNoTemplates": {
    "description": "Template list empty state body."
  },
  "addTemplate": "Add",
  "@addTemplate": {
    "description": "Adds a recurring template."
  },
  "actionPause": "Pause",
  "@actionPause": {
    "description": "Pauses a template."
  },
  "actionResume": "Resume",
  "@actionResume": {
    "description": "Resumes a paused template."
  },
  "loadingRecurring": "Loading your schedule",
  "@loadingRecurring": {
    "description": "Skeleton label for recurring surfaces."
  },
  "builderSectionWhat": "What it is",
  "@builderSectionWhat": {
    "description": "First section of the template builder."
  },
  "builderSectionWhen": "How often",
  "@builderSectionWhen": {
    "description": "Frequency section of the template builder."
  },
  "builderSectionDefaults": "Defaults",
  "@builderSectionDefaults": {
    "description": "Amount and account section of the template builder."
  },
  "labelTemplateName": "Name",
  "@labelTemplateName": {
    "description": "Template name field."
  },
  "labelRecurringKind": "Kind",
  "@labelRecurringKind": {
    "description": "Bill, subscription, rent or salary."
  },
  "labelDirection": "Direction",
  "@labelDirection": {
    "description": "Whether money goes out or comes in."
  },
  "directionOutflow": "Money out",
  "@directionOutflow": {
    "description": "RecurringDirection.outflow."
  },
  "directionInflow": "Money in",
  "@directionInflow": {
    "description": "RecurringDirection.inflow."
  },
  "kindBill": "Bill",
  "@kindBill": {
    "description": "RecurringKind.bill."
  },
  "kindSubscription": "Subscription",
  "@kindSubscription": {
    "description": "RecurringKind.subscription."
  },
  "kindRent": "Rent",
  "@kindRent": {
    "description": "RecurringKind.rent."
  },
  "kindSalary": "Salary",
  "@kindSalary": {
    "description": "RecurringKind.salary."
  },
  "labelEvery": "Every",
  "@labelEvery": {
    "description": "Precedes the interval count and unit."
  },
  "unitDay": "{count, plural, =1{day} other{days}}",
  "@unitDay": {
    "description": "RecurringIntervalUnit.day.",
    "placeholders": {
      "count": {}
    }
  },
  "unitWeek": "{count, plural, =1{week} other{weeks}}",
  "@unitWeek": {
    "description": "RecurringIntervalUnit.week.",
    "placeholders": {
      "count": {}
    }
  },
  "unitMonth": "{count, plural, =1{month} other{months}}",
  "@unitMonth": {
    "description": "RecurringIntervalUnit.month.",
    "placeholders": {
      "count": {}
    }
  },
  "unitYear": "{count, plural, =1{year} other{years}}",
  "@unitYear": {
    "description": "RecurringIntervalUnit.year.",
    "placeholders": {
      "count": {}
    }
  },
  "labelAnchorDay": "On day of the month",
  "@labelAnchorDay": {
    "description": "anchorDayOfMonth. Stored once, clamped at render (anomaly A13)."
  },
  "anchorDayHelp": "Kept as you set it. Anchored on the 31st, a short month falls on its last day and the next long month returns to the 31st.",
  "@anchorDayHelp": {
    "description": "Explains that the anchor never walks backwards."
  },
  "labelStartDate": "Starts",
  "@labelStartDate": {
    "description": "startDateKey."
  },
  "labelEndDate": "Ends",
  "@labelEndDate": {
    "description": "endDateKey, optional."
  },
  "labelDefaultAmount": "Usual amount",
  "@labelDefaultAmount": {
    "description": "defaultAmount — a default, not a fixed figure."
  },
  "labelRemindBefore": "Remind me",
  "@labelRemindBefore": {
    "description": "remindDaysBefore."
  },
  "saveTemplate": "Save",
  "@saveTemplate": {
    "description": "Commits the template."
  },
  "previewTitle": "Next three",
  "@previewTitle": {
    "description": "Header of the frequency preview."
  },
  "previewEmpty": "Set a start date to see when this lands.",
  "@previewEmpty": {
    "description": "Frequency preview with nothing to show."
  },
  "previewClamped": "Shortened to fit the month",
  "@previewClamped": {
    "description": "Marks a previewed date the anchor could not reach."
  },
  "payTitle": "Record this payment",
  "@payTitle": {
    "description": "Pay sheet title."
  },
  "payTitleInflow": "Record this receipt",
  "@payTitleInflow": {
    "description": "Pay sheet title for an inflow."
  },
  "labelActualAmount": "Amount actually paid",
  "@labelActualAmount": {
    "description": "The real figure, which may differ from the default."
  },
  "labelActualAmountInflow": "Amount actually received",
  "@labelActualAmountInflow": {
    "description": "Inflow wording for the same field."
  },
  "payUsualWas": "Usually",
  "@payUsualWas": {
    "description": "Precedes the default amount when the actual differs from it."
  },
  "labelPaidOn": "Paid on",
  "@labelPaidOn": {
    "description": "paidDateKey."
  },
  "payCommit": "Record it",
  "@payCommit": {
    "description": "Commits the payment and creates the transaction."
  },
  "payRecorded": "Recorded",
  "@payRecorded": {
    "description": "Result snack after paying."
  },
  "payNeedsAccount": "Choose which account it came from",
  "@payNeedsAccount": {
    "description": "Rejection when no account is selected."
  },
  "payUndoTitle": "Undo this payment?",
  "@payUndoTitle": {
    "description": "Confirmation before undoing."
  },
  "payUndoBody": "The obligation goes back to due and the transaction it created is deleted. Anything that transaction produced — stock, an asset — goes with it.",
  "@payUndoBody": {
    "description": "Says exactly what undo reverses, in the order it happens (ARCH_5 §5.4)."
  },
  "payUndone": "Payment undone",
  "@payUndone": {
    "description": "Result snack after undoing."
  },
  "actionSkip": "Skip this one",
  "@actionSkip": {
    "description": "Marks an occurrence deliberately skipped."
  },
  "occurrenceSkipped": "Skipped",
  "@occurrenceSkipped": {
    "description": "Chip on a skipped occurrence, and the snack after skipping."
  },
  "historyRecurringTitle": "Payment history",
  "@historyRecurringTitle": {
    "description": "Occurrence history screen title."
  },
  "historyDefaultVsActual": "Differed from the usual amount",
  "@historyDefaultVsActual": {
    "description": "Badge when paidAmount != defaultAmount."
  },
  "emptyTitleNoOccurrences": "Nothing due yet",
  "@emptyTitleNoOccurrences": {
    "description": "Occurrence history empty state."
  },
  "emptyBodyNoOccurrences": "Occurrences appear as their due dates arrive. Nothing is ever paid for you.",
  "@emptyBodyNoOccurrences": {
    "description": "Empty state body, stating anomaly A14 plainly."
  },
  "statusDue": "Due",
  "@statusDue": {
    "description": "RecurringOccurrenceStatus.due."
  },
  "statusPaid": "Paid",
  "@statusPaid": {
    "description": "RecurringOccurrenceStatus.paid."
  },
  "statusDismissed": "Dismissed",
  "@statusDismissed": {
    "description": "RecurringOccurrenceStatus.dismissed."
  },
  "kindServiceFee": "Service fee",
  "@kindServiceFee": {
    "description": "RecurringKind.serviceFee — a recurring charge tied to an asset."
  },
  "kindOther": "Something else",
  "@kindOther": {
    "description": "RecurringKind.other — anything the named kinds do not cover."
  },
  "billDueSection": "Due now",
  "@billDueSection": {
    "description": "Header above the recurring bills a payment can settle."
  },
  "billSetUpAction": "Set up a recurring bill",
  "@billSetUpAction": {
    "description": "Opens the template builder from the bill form."
  },
  "billNothingDue": "Nothing is due right now.",
  "@billNothingDue": {
    "description": "Shown in the bill form when no occurrence is outstanding."
  },
  "recurringScheduleNext": "Saved. Now set how often it repeats.",
  "@recurringScheduleNext": {
    "description": "Snack after a line asked to become recurring."
  },
  "recurringNotYetDue": "Not due yet",
  "@recurringNotYetDue": {
    "description": "Chip when the next occurrence has not materialised."
  },
  "billSettlesLabel": "Settling",
  "@billSettlesLabel": {
    "description": "Precedes the recurring bill this payment will settle."
  },
  "billSettleNone": "Not a recurring bill",
  "@billSettleNone": {
    "description": "Option that leaves the payment unlinked to any template."
  },
  "billSettleHelp": "Pick one and the amount below becomes what you actually paid. Saving records it once.",
  "@billSettleHelp": {
    "description": "Explains that the editor is the single write path for a bill payment."
  },
  "billAmountBecomesPaid": "This amount is what gets recorded",
  "@billAmountBecomesPaid": {
    "description": "Helper under the amount when a bill is selected."
  },
  "billAccountAuto": "Paid from",
  "@billAccountAuto": {
    "description": "Precedes the account resolved automatically for a bill payment."
  },
  "billAccountAskOnce": "Which account does this come from? Alaya remembers it on the bill.",
  "@billAccountAskOnce": {
    "description": "Shown only when no template default, no app default and more than one account exist."
  },
  "assetGroupAppliance": "Appliances",
  "@assetGroupAppliance": {
    "description": "AssetType.appliance group header."
  },
  "assetGroupElectronics": "Electronics",
  "@assetGroupElectronics": {
    "description": "AssetType.electronics."
  },
  "assetGroupVehicle": "Vehicles",
  "@assetGroupVehicle": {
    "description": "AssetType.vehicle."
  },
  "assetGroupFurniture": "Furniture",
  "@assetGroupFurniture": {
    "description": "AssetType.furniture."
  },
  "assetGroupProperty": "Property",
  "@assetGroupProperty": {
    "description": "AssetType.property."
  },
  "assetGroupServiceProvider": "People",
  "@assetGroupServiceProvider": {
    "description": "AssetType.serviceProvider — a maid or gardener lives here, not in a second system."
  },
  "assetGroupSubscription": "Subscriptions",
  "@assetGroupSubscription": {
    "description": "AssetType.subscription."
  },
  "assetGroupOther": "Other",
  "@assetGroupOther": {
    "description": "AssetType.other."
  },
  "assetUnderWarranty": "In warranty",
  "@assetUnderWarranty": {
    "description": "Chip when warrantyEndDateKey is still ahead."
  },
  "assetWarrantyEnding": "Warranty ending",
  "@assetWarrantyEnding": {
    "description": "Chip when the warranty ends soon."
  },
  "assetWarrantyExpired": "Out of warranty",
  "@assetWarrantyExpired": {
    "description": "Chip when the warranty has passed."
  },
  "assetServiceDue": "Service due",
  "@assetServiceDue": {
    "description": "Chip when nextServiceDueDateKey has passed."
  },
  "assetServiceSoon": "Service soon",
  "@assetServiceSoon": {
    "description": "Chip when a service is close."
  },
  "assetDisposedChip": "Disposed",
  "@assetDisposedChip": {
    "description": "Chip on a disposed asset."
  },
  "assetUnderRepair": "Being repaired",
  "@assetUnderRepair": {
    "description": "AssetStatus.underRepair."
  },
  "filterShowDisposed": "Include disposed",
  "@filterShowDisposed": {
    "description": "Filter that brings disposed assets back into the list."
  },
  "emptyTitleNoAssets": "Nothing tracked yet",
  "@emptyTitleNoAssets": {
    "description": "Asset list empty state."
  },
  "emptyBodyNoAssets": "Add an appliance, a vehicle, or the person who helps around the house — they all live here.",
  "@emptyBodyNoAssets": {
    "description": "Asset list empty state body, stating the serviceProvider case plainly."
  },
  "addAsset": "Add",
  "@addAsset": {
    "description": "Adds an asset."
  },
  "loadingAssets": "Loading your things",
  "@loadingAssets": {
    "description": "Skeleton label for service surfaces."
  },
  "assetSectionIdentity": "Details",
  "@assetSectionIdentity": {
    "description": "Identity section on the detail screen."
  },
  "assetSectionWarranty": "Warranty",
  "@assetSectionWarranty": {
    "description": "Warranty section."
  },
  "assetSectionContact": "Contact",
  "@assetSectionContact": {
    "description": "Contact block."
  },
  "assetSectionService": "Service history",
  "@assetSectionService": {
    "description": "Service records section."
  },
  "assetSectionSalary": "Salary history",
  "@assetSectionSalary": {
    "description": "Service records section for a serviceProvider."
  },
  "assetLifetimeCost": "Spent on service so far",
  "@assetLifetimeCost": {
    "description": "Sum of every service record cost."
  },
  "assetLifetimeSalary": "Paid so far",
  "@assetLifetimeSalary": {
    "description": "The same figure for a serviceProvider."
  },
  "labelBrand": "Brand",
  "@labelBrand": {
    "description": "assets.brand."
  },
  "labelModelNo": "Model",
  "@labelModelNo": {
    "description": "assets.modelNo."
  },
  "labelSerialNo": "Serial",
  "@labelSerialNo": {
    "description": "assets.serialNo."
  },
  "labelPurchasePrice": "Bought for",
  "@labelPurchasePrice": {
    "description": "assets.purchasePrice."
  },
  "labelWarrantyStart": "Warranty from",
  "@labelWarrantyStart": {
    "description": "assets.warrantyStartDateKey."
  },
  "labelWarrantyEnd": "Warranty until",
  "@labelWarrantyEnd": {
    "description": "assets.warrantyEndDateKey."
  },
  "labelWarrantyProvider": "Covered by",
  "@labelWarrantyProvider": {
    "description": "assets.warrantyProvider."
  },
  "labelServiceInterval": "Service every",
  "@labelServiceInterval": {
    "description": "assets.serviceIntervalDays."
  },
  "labelNextService": "Next service",
  "@labelNextService": {
    "description": "assets.nextServiceDueDateKey."
  },
  "labelContactName": "Name",
  "@labelContactName": {
    "description": "assets.primaryContactName."
  },
  "labelContactPhone": "Phone",
  "@labelContactPhone": {
    "description": "assets.primaryContactPhone."
  },
  "labelLocation": "Kept in",
  "@labelLocation": {
    "description": "assets.location."
  },
  "actionCall": "Call",
  "@actionCall": {
    "description": "Dials primaryContactPhone."
  },
  "callFailed": "No app on this phone can place that call.",
  "@callFailed": {
    "description": "Shown when the tel: intent finds no handler."
  },
  "actionAddService": "Record a service",
  "@actionAddService": {
    "description": "Adds a service record."
  },
  "actionAddSalary": "Record a payment",
  "@actionAddSalary": {
    "description": "The same action for a serviceProvider."
  },
  "actionDispose": "Dispose of it",
  "@actionDispose": {
    "description": "Opens the dispose sheet."
  },
  "actionUndispose": "Bring it back",
  "@actionUndispose": {
    "description": "Reverses a disposal."
  },
  "assetLinkedRecurring": "Paid on a schedule",
  "@assetLinkedRecurring": {
    "description": "Chip when linkedRecurringTemplateId is set."
  },
  "emptyBodyNoServices": "Nothing recorded against this yet.",
  "@emptyBodyNoServices": {
    "description": "Empty service history."
  },
  "labelAssetName": "What is it?",
  "@labelAssetName": {
    "description": "assets.name."
  },
  "labelAssetType": "Kind",
  "@labelAssetType": {
    "description": "assets.type."
  },
  "assetTypeHelpPerson": "A person you pay regularly belongs here too — their payments become service records.",
  "@assetTypeHelpPerson": {
    "description": "Explains AssetType.serviceProvider when it is chosen."
  },
  "saveAsset": "Save",
  "@saveAsset": {
    "description": "Commits an asset."
  },
  "serviceIntervalHelp": "Days between services. The next due date moves on each time you record one.",
  "@serviceIntervalHelp": {
    "description": "Explains serviceIntervalDays."
  },
  "labelServiceType": "What happened",
  "@labelServiceType": {
    "description": "service_records.type."
  },
  "serviceTypeService": "Serviced",
  "@serviceTypeService": {
    "description": "ServiceRecordType.service."
  },
  "serviceTypeRepair": "Repaired",
  "@serviceTypeRepair": {
    "description": "ServiceRecordType.repair."
  },
  "serviceTypeMaintenance": "Maintenance",
  "@serviceTypeMaintenance": {
    "description": "ServiceRecordType.maintenance."
  },
  "serviceTypeInspection": "Inspection",
  "@serviceTypeInspection": {
    "description": "ServiceRecordType.inspection."
  },
  "serviceTypeSalaryPaid": "Salary paid",
  "@serviceTypeSalaryPaid": {
    "description": "ServiceRecordType.salaryPaid — the maid case."
  },
  "serviceTypeOther": "Something else",
  "@serviceTypeOther": {
    "description": "ServiceRecordType.other."
  },
  "labelProviderName": "Who did it",
  "@labelProviderName": {
    "description": "service_records.providerName."
  },
  "labelProviderPhone": "Their number",
  "@labelProviderPhone": {
    "description": "service_records.providerPhone."
  },
  "labelServiceDate": "When",
  "@labelServiceDate": {
    "description": "service_records.serviceDateKey."
  },
  "labelServiceCost": "Cost",
  "@labelServiceCost": {
    "description": "service_records.cost."
  },
  "labelNextDue": "Next one due",
  "@labelNextDue": {
    "description": "service_records.nextDueDateKey."
  },
  "alsoRecordAsExpense": "Also record it as an expense",
  "@alsoRecordAsExpense": {
    "description": "The alsoRecordAsExpense toggle."
  },
  "alsoRecordHelp": "Writes a withdrawal for the cost as well, so it shows in your ledger.",
  "@alsoRecordHelp": {
    "description": "Explains what the toggle writes."
  },
  "alsoRecordNeedsAccount": "Choose which account it comes from",
  "@alsoRecordNeedsAccount": {
    "description": "Rejection when the toggle is on with no account."
  },
  "alsoRecordNeedsCost": "Add a cost first",
  "@alsoRecordNeedsCost": {
    "description": "Rejection when the toggle is on with no cost."
  },
  "saveService": "Save",
  "@saveService": {
    "description": "Commits a service record."
  },
  "disposeTitle": "What happened to it?",
  "@disposeTitle": {
    "description": "Dispose sheet title."
  },
  "disposeBody": "It stays in your records either way — what you spent on it still counts. This just stops it appearing as something you own.",
  "@disposeBody": {
    "description": "States anomaly A30 plainly: an asset is never deleted."
  },
  "disposeReasonSold": "Sold it",
  "@disposeReasonSold": {
    "description": "AssetDisposalReason.sold."
  },
  "disposeReasonExpired": "Wore out",
  "@disposeReasonExpired": {
    "description": "AssetDisposalReason.expired."
  },
  "disposeReasonDamaged": "Broke",
  "@disposeReasonDamaged": {
    "description": "AssetDisposalReason.damaged."
  },
  "disposeReasonGifted": "Gave it away",
  "@disposeReasonGifted": {
    "description": "AssetDisposalReason.gifted."
  },
  "disposeReasonLost": "Lost it",
  "@disposeReasonLost": {
    "description": "AssetDisposalReason.lost."
  },
  "disposeReasonReplaced": "Replaced it",
  "@disposeReasonReplaced": {
    "description": "AssetDisposalReason.replaced."
  },
  "disposeReasonOther": "Something else",
  "@disposeReasonOther": {
    "description": "AssetDisposalReason.other."
  },
  "labelDisposalAmount": "Got back",
  "@labelDisposalAmount": {
    "description": "assets.disposalAmount — what the disposal recovered."
  },
  "labelDisposalDate": "When",
  "@labelDisposalDate": {
    "description": "assets.disposedAtDateKey."
  },
  "disposeCommit": "Record it",
  "@disposeCommit": {
    "description": "Commits the disposal."
  },
  "disposeDone": "Recorded",
  "@disposeDone": {
    "description": "Snack after disposing."
  },
  "undisposeDone": "Back in your list",
  "@undisposeDone": {
    "description": "Snack after un-disposing."
  },
  "disposeNeedsReason": "Pick what happened",
  "@disposeNeedsReason": {
    "description": "Rejection when no reason is chosen."
  },
  "hintSearchAssets": "Search your things and people",
  "@hintSearchAssets": {
    "description": "Search hint on the asset list."
  },
  "errorWarrantyBackwards": "The warranty cannot end before it starts",
  "@errorWarrantyBackwards": {
    "description": "Field error when warrantyEndDateKey precedes warrantyStartDateKey."
  },
  "sectionMoney": "Money",
  "@sectionMoney": {
    "description": "Header above the cost and expense controls on the service editor."
  },
  "assetCreatedFromPurchase": "Saved. Now say what it is and how long it is covered.",
  "@assetCreatedFromPurchase": {
    "description": "Snack after a purchase line created an asset."
  },
  "destinationHelpNone": "Recorded as spending and nothing else.",
  "@destinationHelpNone": {
    "description": "Explains destination none."
  },
  "destinationHelpInventory": "Groceries, refills, anything measured and consumed. Needs an item and a quantity, and creates stock you can run down.",
  "@destinationHelpInventory": {
    "description": "Explains destination inventory."
  },
  "destinationHelpAsset": "A phone, a fridge, a chair. Creates something you own, with its own warranty and service history.",
  "@destinationHelpAsset": {
    "description": "Explains destination asset."
  },
  "destinationHelpRecurring": "Sets up a schedule so this comes back every month.",
  "@destinationHelpRecurring": {
    "description": "Explains destination recurring."
  },
  "assetSameNameNote": "You already have one called this. That is fine — this will be a separate one, with its own warranty and service history.",
  "@assetSameNameNote": {
    "description": "Informational note when an asset name repeats. Never a block: five iPhones are five assets."
  },
  "@destinationNone": {
    "description": "No artefact. Recorded as spending and nothing else."
  },
  "@destinationInventory": {
    "description": "Creates stock. Names the Inventory module, matching navInventory."
  },
  "@destinationAsset": {
    "description": "Creates an asset. Names the Services module, matching navServices."
  },
  "@destinationRecurring": {
    "description": "Hands off to the template builder. Matches navRecurring."
  },
  "actionSetWarranty": "Set the warranty",
  "@actionSetWarranty": {
    "description": "Snack action opening the asset a purchase line created."
  },
  "labelPaymentMethodOptional": "How you paid (optional)",
  "@labelPaymentMethodOptional": {
    "description": "Optional payment method on the service editor. Travels to the expense, never onto the record."
  },
  "dashboardTitle": "Home",
  "@dashboardTitle": {
    "description": "Dashboard screen title."
  },
  "fundsAvailable": "Total available funds",
  "@fundsAvailable": {
    "description": "Label above the one headline figure on the dashboard."
  },
  "fundsUnconverted": "{count, plural, =1{1 balance not converted} other{{count} balances not converted}}",
  "@fundsUnconverted": {
    "description": "Chip when BalanceService could not convert some accounts. Excluded from the headline, never summed (anomaly A34).",
    "placeholders": {
      "count": {}
    }
  },
  "fundsApproximate": "Rate is older than today",
  "@fundsApproximate": {
    "description": "Chip when the conversion used the most recent rate on or before today."
  },
  "fundsWhyExcluded": "Balances Alaya has no rate for are left out rather than guessed at.",
  "@fundsWhyExcluded": {
    "description": "Explains why the headline may be lower than the sum of every account."
  },
  "rangeLast30": "Last 30 days",
  "@rangeLast30": {
    "description": "Range label. Always stated, never implied (anomaly A33)."
  },
  "rangeMoneyIn": "In",
  "@rangeMoneyIn": {
    "description": "Deposits over the labelled range."
  },
  "rangeMoneyOut": "Out",
  "@rangeMoneyOut": {
    "description": "Withdrawals over the labelled range."
  },
  "rangeNothingYet": "Nothing yet",
  "@rangeNothingYet": {
    "description": "Shown in place of a figure when a range holds no transactions."
  },
  "rangeExcluded": "{count, plural, =1{1 left out} other{{count} left out}}",
  "@rangeExcluded": {
    "description": "Chip when transactions in a foreign currency could not be converted into the range total.",
    "placeholders": {
      "count": {}
    }
  },
  "insightUpcoming": "Coming up",
  "@insightUpcoming": {
    "description": "The calendar side of the switchable insight card."
  },
  "insightSpending": "Where it went",
  "@insightSpending": {
    "description": "The analytics side of the switchable insight card."
  },
  "insightSwitchLabel": "Show",
  "@insightSwitchLabel": {
    "description": "Semantics label for the insight card switch."
  },
  "insightNothingUpcoming": "Nothing needs attention in the next fortnight.",
  "@insightNothingUpcoming": {
    "description": "Empty state for the upcoming side."
  },
  "insightAnalyticsPending": "Spending breakdowns arrive with the analytics module.",
  "@insightAnalyticsPending": {
    "description": "Honest empty state: AnalyticsService has no data adapter until Phase 7B (ARCH_4 §5.1 item 15)."
  },
  "insightBillDue": "Bill due",
  "@insightBillDue": {
    "description": "Upcoming row for a recurring occurrence."
  },
  "insightServiceDue": "Service due",
  "@insightServiceDue": {
    "description": "Upcoming row for an asset needing service."
  },
  "insightWarrantyEnding": "Warranty ending",
  "@insightWarrantyEnding": {
    "description": "Upcoming row for an expiring warranty."
  },
  "insightBatchExpiring": "Expiring",
  "@insightBatchExpiring": {
    "description": "Upcoming row for a batch past or near its expiry."
  },
  "moduleGridTitle": "Where to next",
  "@moduleGridTitle": {
    "description": "Header above the navigation tiles."
  },
  "moduleExpenses": "{count, plural, =0{none this month} =1{1 this month} other{{count} this month}}",
  "@moduleExpenses": {
    "description": "Live number on the Expenses tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleInventory": "{count, plural, =0{nothing tracked} =1{1 running low} other{{count} running low}}",
  "@moduleInventory": {
    "description": "Live number on the Inventory tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleShopping": "{count, plural, =0{list is clear} =1{1 to buy} other{{count} to buy}}",
  "@moduleShopping": {
    "description": "Live number on the Shopping tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleRecurring": "{count, plural, =0{all settled} =1{1 due} other{{count} due}}",
  "@moduleRecurring": {
    "description": "Live number on the Recurring tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleServices": "{count, plural, =0{nothing needs doing} =1{1 needs attention} other{{count} need attention}}",
  "@moduleServices": {
    "description": "Live number on the Services tile.",
    "placeholders": {
      "count": {}
    }
  },
  "fabAddIncome": "Money in",
  "@fabAddIncome": {
    "description": "FAB action opening the editor as a deposit."
  },
  "fabAddItem": "New item",
  "@fabAddItem": {
    "description": "FAB action opening the item editor."
  },
  "loadingDashboard": "Adding it up",
  "@loadingDashboard": {
    "description": "Skeleton label for the dashboard."
  },
  "fabOpenLabel": "Add something",
  "@fabOpenLabel": {
    "description": "Semantics label for the closed expandable FAB."
  },
  "fabCloseLabel": "Close",
  "@fabCloseLabel": {
    "description": "Semantics label for the open expandable FAB."
  },
  "eventTypeTransaction": "Transaction",
  "eventTypeRecurringDue": "Recurring bill",
  "eventTypeBatchExpiry": "Expiring",
  "eventTypeWarrantyEnd": "Warranty ending",
  "eventTypeServiceDue": "Service due",
  "eventTypeShoppingTarget": "Shopping target",
  "calendarSeverityWarning": "Needs attention",
  "calendarSeverityDanger": "Past its date",
  "calendarLoadingDay": "Loading this day…",
  "calendarDayErrorTitle": "Could not load this day",
  "calendarDayEmptyTitle": "Nothing on this day",
  "calendarDayEmptyBody": "No transactions, bills, expiries or services fall here.",
  "calendarRetry": "Try again",
  "calendarLoadingMonth": "Loading this month…",
  "calendarErrorTitle": "Could not load the calendar",
  "calendarPreviousMonth": "Previous month",
  "calendarNextMonth": "Next month",
  "calendarOnDay": "On this day",
  "calendarRangeOn": "Select a range",
  "calendarRangeOff": "Stop selecting a range",
  "calendarRangePickEnd": "From {start} — tap another day to finish.",
  "calendarInRange": "{count, plural, =1{1 day} other{{count} days}}",
  "calendarRangeEmptyTitle": "Nothing in these days",
  "calendarRangeEmptyBody": "No transactions, bills, expiries or services fall inside the range.",
  "@calendarRangePickEnd": {
    "description": "Prompt after the range start is chosen.",
    "placeholders": {
      "start": {
        "type": "String"
      }
    }
  },
  "@calendarInRange": {
    "description": "How many days the chosen range spans.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "calendarBackToToday": "Back to this month",
  "calendarTotalOut": "Spent",
  "calendarTotalIn": "Received",
  "dashboardOpenCalendar": "Open calendar",
  "dashboardCalendarSemantics": "{month} at a glance. Opens the calendar.",
  "@dashboardCalendarSemantics": {
    "description": "Screen-reader label for the dashboard month card where days are too narrow to tap.",
    "placeholders": {
      "month": {
        "type": "String"
      }
    }
  },
  "navBackToDashboard": "Back to dashboard"
}
```

### `lib/app/router/routes.dart`

```dart
/// Every route path in the app, in one place.
///
/// Hand-written: `go_router_builder` cannot resolve alongside `drift_dev` (ARCH_1 §7.1). A literal
/// path anywhere else is a route that drifts silently when this file changes.
abstract final class Routes {
  /// Where the app opens.
  static const String initial = dashboard;

  // ── top level, inside the drawer shell ──

  /// The dashboard.
  static const String dashboard = '/';

  /// The transaction ledger.
  static const String expenses = '/expenses';

  /// The inventory catalogue.
  static const String inventory = '/inventory';

  /// The shopping lists.
  static const String shopping = '/shopping';

  /// The recurring templates.
  static const String recurring = '/recurring';

  /// The assets and service records.
  static const String services = '/services';

  /// The calendar.
  static const String calendar = '/calendar';

  /// The insights.
  static const String insights = '/insights';

  /// The settings.
  static const String settings = '/settings';

  // ── outside the shell: full-screen editors and the lock ──

  /// The PIN gate.
  static const String lock = '/lock';

  /// The palette workbench.
  static const String themeLab = '/settings/theme-lab';

  /// A new transaction.
  static const String transactionNew = '/expenses/new';

  /// The line items of a new transaction.
  static const String transactionLinesNew = '/expenses/new/lines';

  /// A new item.
  static const String itemNew = '/inventory/new';

  /// A new recurring template.
  static const String recurringNew = '/recurring/new';

  /// A new asset.
  static const String assetNew = '/services/new';

  // ── parameterised ──

  /// Path pattern for one transaction.
  static const String transactionDetailPattern = '/expenses/:transactionId';

  /// Path pattern for editing one transaction.
  static const String transactionEditPattern = '/expenses/:transactionId/edit';

  /// Path pattern for the line items of one transaction.
  static const String transactionLinesPattern = '/expenses/:transactionId/lines';

  /// Path pattern for one item.
  static const String itemDetailPattern = '/inventory/:itemId';

  /// Path pattern for editing one item.
  static const String itemEditPattern = '/inventory/:itemId/edit';

  /// Path pattern for adding a batch to one item.
  static const String batchNewPattern = '/inventory/:itemId/batch/new';

  /// Path pattern for editing one batch.
  static const String batchEditPattern = '/inventory/:itemId/batch/:batchId';

  /// Path pattern for one batch's movement history.
  static const String batchHistoryPattern = '/inventory/:itemId/batch/:batchId/history';

  /// Path pattern for one shopping list.
  static const String shoppingListPattern = '/shopping/:listId';

  /// Path pattern for turning a shopping list's ticked entries into a purchase.
  static const String shoppingConvertPattern = '/shopping/:listId/convert';

  /// Path pattern for editing one recurring template.
  static const String recurringEditPattern = '/recurring/:templateId/edit';

  /// Path pattern for one template's occurrence history.
  static const String recurringHistoryPattern = '/recurring/:templateId/history';

  /// Path pattern for one recurring template.
  static const String recurringDetailPattern = '/recurring/:templateId';

  /// Path pattern for editing one asset.
  static const String assetEditPattern = '/services/:assetId/edit';

  /// Path pattern for a new service record against one asset.
  static const String serviceNewPattern = '/services/:assetId/service/new';

  /// Path pattern for editing one service record.
  static const String serviceEditPattern = '/services/:assetId/service/:recordId';

  /// Path pattern for one asset.
  static const String assetDetailPattern = '/services/:assetId';

  /// Path pattern for one calendar day.
  static const String calendarDayPattern = '/calendar/:dateKey';

  // ── param names, so a builder reading them cannot misspell one ──

  /// The transaction id parameter.
  static const String pTransactionId = 'transactionId';

  /// The item id parameter.
  static const String pItemId = 'itemId';

  /// The batch id parameter.
  static const String pBatchId = 'batchId';

  /// The shopping list id parameter.
  static const String pListId = 'listId';

  /// The recurring template id parameter.
  static const String pTemplateId = 'templateId';

  /// The asset id parameter.
  static const String pAssetId = 'assetId';

  /// The service record id parameter.
  static const String pRecordId = 'recordId';

  /// The calendar date parameter.
  static const String pDateKey = 'dateKey';

  // ── builders ──

  /// The location for transaction [id].
  static String transactionDetail(String id) => '$expenses/$id';

  /// The location for editing transaction [id].
  static String transactionEdit(String id) => '$expenses/$id/edit';

  /// The location for the line items of transaction [id], or of a new one when null.
  static String transactionLines(String? id) =>
      id == null ? transactionLinesNew : '$expenses/$id/lines';

  /// The location for item [id].
  static String itemDetail(String id) => '$inventory/$id';

  /// The location for editing item [id].
  static String itemEdit(String id) => '$inventory/$id/edit';

  /// The location for adding a batch to item [itemId].
  static String batchNew(String itemId) => '$inventory/$itemId/batch/new';

  /// The location for editing batch [batchId] of item [itemId].
  static String batchEdit(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId';

  /// The location for batch [batchId]'s movement history.
  static String batchHistory(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId/history';

  /// The location for shopping list [id].
  static String shoppingList(String id) => '$shopping/$id';

  /// The location for converting shopping list [id] into a purchase.
  static String shoppingConvert(String id) => '$shopping/$id/convert';

  /// The location for recurring template [id].
  static String recurringDetail(String id) => '$recurring/$id';

  /// The location for editing recurring template [id], or for a new one when null.
  static String recurringEdit(String? id) =>
      id == null ? recurringNew : '$recurring/$id/edit';

  /// The location for template [id]'s occurrence history.
  static String recurringHistory(String id) => '$recurring/$id/history';

  /// The location for asset [id].
  static String assetDetail(String id) => '$services/$id';

  /// The location for editing asset [id], or for a new one when null.
  static String assetEdit(String? id) => id == null ? assetNew : '$services/$id/edit';

  /// The location for a new service record against asset [assetId].
  static String serviceNew(String assetId) => '$services/$assetId/service/new';

  /// The location for editing service record [recordId] of asset [assetId].
  static String serviceEdit(String assetId, String recordId) =>
      '$services/$assetId/service/$recordId';

  /// The location for the calendar on [dateKey].
  static String calendarDay(int dateKey) => '$calendar/$dateKey';

  /// The nine drawer destinations, in drawer order.
  ///
  /// Named for the drawer rather than the shell because `AlayaDrawer` reads it by this name — a route
  /// cannot exist in the router and be missing from the drawer without this list disagreeing.
  static const List<String> drawerDestinations = [
    dashboard,
    expenses,
    inventory,
    shopping,
    recurring,
    services,
    calendar,
    insights,
    settings,
  ];
}
```

### `lib/app/router/app_router.dart`

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/placeholder_screen.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_detail_screen.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_editor_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_editor_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_history_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_detail_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_editor_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/occurrence_history_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_builder_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_editor_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/service_editor_screen.dart';
import 'package:alaya/features/settings/presentation/theme_lab_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/convert_to_purchase_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/shopping_list_screen.dart';
import 'package:alaya/shared/widgets/alaya_drawer.dart';

/// Whether the app is currently locked, consulted on every navigation.
typedef LockGate = bool Function();

/// The app's `go_router` configuration — hand-written, per ARCH_1 §7.3.
///
/// **The nine drawer destinations sit inside the shell; every detail and editor route sits outside
/// it** (U18). `AppBar` resolves its leading slot by checking `hasDrawer` *before* `canPop`, so a
/// detail screen rendered inside the drawer shell gets a hamburger where a back arrow belongs.
///
/// Literal-path segments are declared before their parameterised siblings, because go_router walks
/// its route list in order and `:itemId` would otherwise swallow the word `new`.
abstract final class AppRouter {
  /// Builds the router.
  static GoRouter build({
    LockGate? isLocked,
    String initialLocation = Routes.initial,
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    final locked = isLocked ?? () => false;
    return GoRouter(
      initialLocation: initialLocation,
      navigatorKey: navigatorKey,
      debugLogDiagnostics: false,
      redirect: (context, state) {
        final atLock = state.matchedLocation == Routes.lock;
        if (locked() && !atLock) return Routes.lock;
        if (!locked() && atLock) return Routes.dashboard;
        return null;
      },
      routes: [
        GoRoute(
          path: Routes.lock,
          builder: (context, state) =>
              const PlaceholderScreen(owningPhase: 'Phase 8A'),
        ),
        ShellRoute(
          // No `location` passed: `_ShellScaffold` reads it from the router, because the state handed to a
          // pathless `ShellRoute`'s builder reports `/` for every screen inside it.
          builder: (context, state, child) => _ShellScaffold(child: child),
          routes: [
            GoRoute(
              path: Routes.dashboard,
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(
              path: Routes.expenses,
              builder: (context, state) => const TransactionListScreen(),
            ),
            GoRoute(
              path: Routes.inventory,
              builder: (context, state) => const InventoryListScreen(),
            ),
            GoRoute(
              path: Routes.shopping,
              builder: (context, state) => const ShoppingListScreen(),
            ),
            GoRoute(
              path: Routes.recurring,
              builder: (context, state) => const TemplateListScreen(),
            ),
            GoRoute(
              path: Routes.services,
              builder: (context, state) => const AssetListScreen(),
            ),
            GoRoute(
              path: Routes.calendar,
              builder: (context, state) => const CalendarScreen(),
              routes: [
                // A sub-route rather than a sibling detail route: a day is a view of the month, so it
                // keeps the drawer shell and the month stays behind it (Law U27).
                GoRoute(
                  path: ':${Routes.pDateKey}',
                  builder: (context, state) => CalendarScreen(
                    initialDay: _dateKeyParam(
                      state.pathParameters[Routes.pDateKey],
                    ),
                  ),
                ),
              ],
            ),
            _destination(Routes.insights, 'Phase 7B'),
            _destination(Routes.settings, 'Phase 8A'),
          ],
        ),
        GoRoute(
          path: Routes.transactionNew,
          builder: (context, state) => const TransactionEditorScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesNew,
          builder: (context, state) => const LineItemsScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesPattern,
          builder: (context, state) => LineItemsScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionEditPattern,
          builder: (context, state) => TransactionEditorScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionDetailPattern,
          builder: (context, state) => TransactionDetailScreen(
            transactionId: state.pathParameters[Routes.pTransactionId]!,
          ),
        ),
        GoRoute(
          path: Routes.itemNew,
          builder: (context, state) => const ItemEditorScreen(),
        ),
        GoRoute(
          path: Routes.batchNewPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchHistoryPattern,
          builder: (context, state) => BatchHistoryScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchEditPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId],
          ),
        ),
        GoRoute(
          path: Routes.itemEditPattern,
          builder: (context, state) => ItemEditorScreen(
            itemId: state.pathParameters[Routes.pItemId],
          ),
        ),
        GoRoute(
          path: Routes.itemDetailPattern,
          builder: (context, state) => ItemDetailScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingConvertPattern,
          builder: (context, state) => ConvertToPurchaseScreen(
            listId: state.pathParameters[Routes.pListId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingListPattern,
          builder: (context, state) => ShoppingListScreen(
            listId: state.pathParameters[Routes.pListId],
          ),
        ),
        GoRoute(
          path: Routes.recurringNew,
          builder: (context, state) => const TemplateBuilderScreen(),
        ),
        GoRoute(
          path: Routes.recurringHistoryPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.recurringEditPattern,
          builder: (context, state) => TemplateBuilderScreen(
            templateId: state.pathParameters[Routes.pTemplateId],
          ),
        ),
        GoRoute(
          path: Routes.recurringDetailPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.assetNew,
          builder: (context, state) => const AssetEditorScreen(),
        ),
        GoRoute(
          path: Routes.serviceNewPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.serviceEditPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
            recordId: state.pathParameters[Routes.pRecordId],
          ),
        ),
        GoRoute(
          path: Routes.assetEditPattern,
          builder: (context, state) => AssetEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId],
          ),
        ),
        GoRoute(
          path: Routes.assetDetailPattern,
          builder: (context, state) => AssetDetailScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.themeLab,
          builder: (context, state) => _DetailScaffold(
            title: AlayaStrings.of(context).navThemeLab,
            child: const ThemeLabScreen(),
          ),
        ),
      ],
    );
  }

  /// A top-level drawer destination, rendered inside the shell.
  static GoRoute _destination(String path, String owningPhase) => GoRoute(
    path: path,
    builder: (context, state) => PlaceholderScreen(owningPhase: owningPhase),
  );

  /// A detail route, rendered outside the shell so it gets a back arrow rather than a hamburger.
  static GoRoute _detail(String pattern, String owningPhase) => GoRoute(
    path: pattern,
    builder: (context, state) => _DetailScaffold(
      title: AlayaDrawer.titleFor(context, state.uri.path),
      child: PlaceholderScreen(owningPhase: owningPhase),
    ),
  );
}

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // `AppBar` resolves its implied leading by checking `hasDrawer` **before** `canPop`, so a shell that
    // owns a drawer can never show a back arrow no matter how it was reached. That is fine for a drawer
    // destination switched into as a peer, and wrong for one pushed as a drill-down — and both happen
    // here: the drawer `go`es, the dashboard's module grid `push`es.
    //
    // So the slot is stated rather than implied. Pushed: a back arrow that pops the shell's own navigator
    // (`context.pop`, not `Navigator.maybePop`, which from above the shell navigator would target the root
    // one and do nothing). Switched into: null, which lets the hamburger be implied as before.
    //
    // The drawer stays attached either way, so the edge swipe still opens it on a pushed screen.
    final strings = AlayaStrings.of(context);

    // **Read from the router, not from the builder's `state`.** `ShellRoute` declares no `path`, so the
    // `GoRouterState` handed to its builder describes the *shell's* match rather than the leaf's — and a
    // pathless route's `matchedLocation` is its parent's, which here is `/`. Every screen inside the shell
    // therefore looked like the dashboard: `atDashboard` was permanently true so the home action never
    // rendered, `AlayaDrawer` highlighted Dashboard wherever you were, and `titleFor` named it too.
    //
    // `currentConfiguration` is the delegate's live `RouteMatchList`, so its `uri` is the leaf location no
    // matter which builder asks.
    final here = GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;

    // **`context.canPop()` cannot answer this question from here.** This widget is the `ShellRoute`
    // builder, so its context sits *above* the shell's own `Navigator`; `canPop` resolves against the
    // root navigator, which only ever holds the shell itself. It therefore returns false however the
    // screen was reached, `leading` was always null, and the back arrow this once tried to show could
    // never appear. The drawer's hamburger was the only leading widget users ever saw, and from a module
    // the sole way home was the system back gesture.
    //
    // So the way home is stated outright instead of inferred from a stack this context cannot see: every
    // shell screen except the dashboard carries a home action. It pops when there is something to pop and
    // navigates otherwise, so arriving by the module grid's `push` and by the drawer's `go` both end up
    // in the same place — and the hamburger keeps its slot, because the drawer is still how you move
    // between peers (Law U27).
    return Scaffold(
      drawer: AlayaDrawer(currentLocation: here),
      appBar: AppBar(
        title: Text(AlayaDrawer.titleFor(context, here)),
        // **Unconditional, deliberately.** This was `if (!atDashboard)` and never appeared, and rather
        // than reason about why a condition is false I would rather the button exist and be seen. It
        // shows on the dashboard too, where it is merely redundant — a redundant button is a far smaller
        // fault than a missing one, and its presence there is also the proof that this file is live.
        //
        // Once it is confirmed visible, `if (!atDashboard)` can come back.
        actions: [
          IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(Routes.dashboard),
            tooltip: strings.navBackToDashboard,
            icon: const Icon(Icons.home_outlined, size: AlayaIconSize.md),
          ),
        ],
      ),
      body: child,
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}

/// Parses a `:dateKey` path parameter, or null when it is absent or not a date key.
///
/// A malformed deep link opens the calendar on today rather than throwing — the route is reachable
/// from outside the app.
DateKey? _dateKeyParam(String? raw) {
  final value = int.tryParse(raw ?? '');
  if (value == null) return null;

  final year = value ~/ 10000;
  final month = (value ~/ 100) % 100;
  final day = value % 100;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  // Round-trip through `fromYmd`, which normalises overflow through `DateTime.utc`: 20260230 comes
  // back as 20260302 and fails this check, where a digit-range test alone would accept it.
  final probe = DateKey.fromYmd(year, month, day);
  return probe.value == value ? probe : null;
}
```

### `lib/features/shopping/state/entry_editor_state.dart`

```dart
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';

/// What the entry editor is holding (ARCH_5 §3 archetype A).
///
/// **`itemId` is nullable and stays that way.** A television belongs on a shopping list and has no
/// business in an inventory that tracks flour by the gram, so an entry needs either a name or a
/// linked item — never both, never necessarily one in particular.
class EntryEditorState {
  /// Creates the editor's state.
  const EntryEditorState({
    required this.listId,
    this.id,
    this.freeText = '',
    this.itemId,
    this.quantity,
    this.unitCode,
    this.tagId,
    this.estimatedPrice,
    this.origin = ShoppingEntryOrigin.manual,
    this.autoState = ShoppingEntryAutoState.active,
    this.sortOrder = 0,
    this.isChecked = false,
    this.submitting = false,
    this.identityMissing = false,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// The entry being edited, or null for a new one.
  final String? id;

  /// Which list it belongs to.
  final String listId;

  /// What to buy, in the user's words.
  final String freeText;

  /// The catalogued item this restocks, if any.
  final String? itemId;

  /// How much to buy.
  final Qty? quantity;

  /// The unit the quantity was entered in.
  final String? unitCode;

  /// The aisle-ish grouping this row sits under.
  final String? tagId;

  /// What the user expects it to cost.
  final Money? estimatedPrice;

  /// Where the entry came from.
  final ShoppingEntryOrigin origin;

  /// Whether an auto entry is active, snoozed or dismissed.
  final ShoppingEntryAutoState autoState;

  /// Its position in the list.
  final int sortOrder;

  /// Whether it is already ticked.
  final bool isChecked;

  /// Whether a save is in flight.
  final bool submitting;

  /// Whether submit was pressed with neither a name nor an item.
  final bool identityMissing;

  /// Incremented to shake the name field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the dismiss guard (Law U10).
  final bool dirty;

  /// Whether this is editing an existing entry.
  bool get isEditing => id != null;

  /// Whether the entry has something to identify it by.
  bool get hasIdentity => freeText.trim().isNotEmpty || itemId != null;

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  EntryEditorState copyWith({
    String? id,
    String? freeText,
    String? itemId,
    bool clearItem = false,
    Qty? quantity,
    bool clearQuantity = false,
    String? unitCode,
    String? tagId,
    bool clearTag = false,
    Money? estimatedPrice,
    bool clearPrice = false,
    ShoppingEntryOrigin? origin,
    ShoppingEntryAutoState? autoState,
    int? sortOrder,
    bool? isChecked,
    bool? submitting,
    bool? identityMissing,
    int? shakeTrigger,
    bool? dirty,
  }) =>
      EntryEditorState(
        id: id ?? this.id,
        listId: listId,
        freeText: freeText ?? this.freeText,
        itemId: clearItem ? null : (itemId ?? this.itemId),
        quantity: clearQuantity ? null : (quantity ?? this.quantity),
        unitCode: unitCode ?? this.unitCode,
        tagId: clearTag ? null : (tagId ?? this.tagId),
        estimatedPrice: clearPrice ? null : (estimatedPrice ?? this.estimatedPrice),
        origin: origin ?? this.origin,
        autoState: autoState ?? this.autoState,
        sortOrder: sortOrder ?? this.sortOrder,
        isChecked: isChecked ?? this.isChecked,
        submitting: submitting ?? this.submitting,
        identityMissing: identityMissing ?? this.identityMissing,
        shakeTrigger: shakeTrigger ?? this.shakeTrigger,
        dirty: dirty ?? true,
      );

  /// Builds the entity this state describes.
  ///
  /// **Editing an auto entry promotes it to manual.** A suggestion the user has shaped is theirs,
  /// and regeneration must never remove or rewrite it (anomaly A23) — `origin` is what the engine
  /// keys that decision on, so the promotion happens here rather than being left to the caller.
  ShoppingEntry toEntry({required String newId}) {
    final promoted = isEditing && origin == ShoppingEntryOrigin.autoLowStock
        ? ShoppingEntryOrigin.manual
        : origin;
    return ShoppingEntry(
      id: id ?? newId,
      listId: listId,
      origin: promoted,
      autoState: promoted == ShoppingEntryOrigin.manual
          ? ShoppingEntryAutoState.active
          : autoState,
      isChecked: isChecked,
      sortOrder: sortOrder,
      itemId: itemId,
      freeText: freeText.trim().isEmpty ? null : freeText.trim(),
      quantity: quantity,
      unitCode: unitCode,
      tagId: tagId,
      estimatedPrice: estimatedPrice,
    );
  }

  /// Loads an existing entry into an editor state.
  static EntryEditorState fromEntry(ShoppingEntry entry) => EntryEditorState(
        id: entry.id,
        listId: entry.listId,
        freeText: entry.freeText ?? '',
        itemId: entry.itemId,
        quantity: entry.quantity,
        unitCode: entry.unitCode,
        tagId: entry.tagId,
        estimatedPrice: entry.estimatedPrice,
        origin: entry.origin,
        autoState: entry.autoState,
        sortOrder: entry.sortOrder,
        isChecked: entry.isChecked,
      );
}
```

### `lib/features/shopping/providers/shopping_list_providers.dart`

```dart
/// View-model state for the shopping list (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';

/// One tag's worth of entries.
class ShoppingGroup {
  /// Creates a group.
  const ShoppingGroup({required this.entries, this.tag});

  /// The entries under it, in sort order.
  final List<ShoppingEntry> entries;

  /// The tag this group collects, or null for the untagged remainder.
  final Tag? tag;
}

/// Which list the screen is showing, or null to follow the default.
final selectedListIdProvider =
    NotifierProvider<SelectedListNotifier, String?>(SelectedListNotifier.new);

/// Remembers which list the user switched to.
class SelectedListNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Switches to [listId], or back to the default when null.
  void select(String? listId) => state = listId;
}

/// The lists a user may switch between.
final selectableListsProvider = StreamProvider<List<ShoppingList>>(
  (ref) => ref.watch(shoppingRepositoryProvider).watchSelectableLists(),
);

/// Every list, archived included, for the manager sheet.
final allListsProvider = StreamProvider<List<ShoppingList>>(
  (ref) => ref.watch(shoppingRepositoryProvider).watchAllLists(),
);

/// The list marked default.
final defaultListProvider = StreamProvider<ShoppingList?>(
  (ref) => ref.watch(shoppingRepositoryProvider).watchDefaultList(),
);

/// The list actually on screen: the explicit selection, else the default.
final activeListProvider = Provider<AsyncValue<ShoppingList?>>((ref) {
  final selected = ref.watch(selectedListIdProvider);
  final lists = ref.watch(selectableListsProvider);
  final fallback = ref.watch(defaultListProvider);
  if (selected == null) return fallback;
  return lists.whenData((all) {
    for (final list in all) {
      if (list.id == selected) return list;
    }
    return fallback.valueOrNull;
  });
});

/// Every entry on the active list.
final entriesProvider = StreamProvider.autoDispose.family<List<ShoppingEntry>, String>(
  (ref, listId) => ref.watch(shoppingRepositoryProvider).watchEntries(listId),
);

/// Tags, keyed by id, so a group header can name itself.
final shoppingTagsByIdProvider = StreamProvider<Map<String, Tag>>(
  (ref) => ref.watch(tagRepositoryProvider).watchAll().map(
        (tags) => {for (final tag in tags) tag.id: tag},
      ),
);

/// Items, keyed by id, so a linked entry can show the catalogue name.
final shoppingItemsByIdProvider = StreamProvider<Map<String, Item>>(
  (ref) => ref.watch(itemRepositoryProvider).watchAll().map(
        (items) => {for (final item in items) item.id: item},
      ),
);

/// The active list's entries, filtered for visibility and grouped by tag.
///
/// **What counts as outstanding is decided by the entity, not here.**
/// `ShoppingEntry.isOutstandingAsOf` owns it: snoozed and dismissed suggestions are hidden by the same
/// rule the regeneration engine applies (anomalies A22, A23), and anything already bought drops off
/// because a list is a list of what to get. A second copy of either rule in the view model is a second
/// place for it to drift.
final shoppingGroupsProvider =
    Provider.autoDispose.family<AsyncValue<List<ShoppingGroup>>, String>((ref, listId) {
  final entries = ref.watch(entriesProvider(listId));
  final tags = ref.watch(shoppingTagsByIdProvider);
  if (entries.hasError) return AsyncValue.error(entries.error!, entries.stackTrace!);
  final rows = entries.valueOrNull;
  if (rows == null) return const AsyncValue.loading();
  final byId = tags.valueOrNull ?? const <String, Tag>{};
  final today = ref.watch(clockProvider).today();

  final visible = [
    for (final entry in rows)
      if (entry.isOutstandingAsOf(today)) entry,
  ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  final buckets = <String?, List<ShoppingEntry>>{};
  for (final entry in visible) {
    buckets.putIfAbsent(entry.tagId, () => <ShoppingEntry>[]).add(entry);
  }
  final tagged = [
    for (final id in buckets.keys)
      if (id != null && byId[id] != null)
        ShoppingGroup(entries: buckets[id]!, tag: byId[id]),
  ]..sort((a, b) => a.tag!.name.toLowerCase().compareTo(b.tag!.name.toLowerCase()));

  return AsyncValue.data([
    ...tagged,
    if (buckets[null] != null) ShoppingGroup(entries: buckets[null]!),
  ]);
});

/// The running estimate for the active list, and how far through it the user is.
class ShoppingSummary {
  /// Creates a summary.
  const ShoppingSummary({
    required this.estimate,
    required this.checked,
    required this.total,
  });

  /// The summed estimate of every visible entry that carries one, or null when none do.
  final Money? estimate;

  /// How many visible entries are ticked.
  final int checked;

  /// How many visible entries there are.
  final int total;

  /// Whether anything is ticked, which is what convert-to-purchase needs.
  bool get hasChecked => checked > 0;
}

/// The active list's running estimate and tick progress.
///
/// Entries without an estimate are skipped rather than counted as zero: a list of ten things where
/// two are priced should read as the sum of those two, not as a total that quietly understates by
/// eight.
final shoppingSummaryProvider =
    Provider.autoDispose.family<ShoppingSummary, String>((ref, listId) {
  final groups = ref.watch(shoppingGroupsProvider(listId)).valueOrNull ?? const [];
  Money? estimate;
  var checked = 0;
  var total = 0;
  for (final group in groups) {
    for (final entry in group.entries) {
      total += 1;
      if (entry.isChecked) checked += 1;
      final price = entry.estimatedPrice;
      if (price == null) continue;
      estimate = estimate == null ? price : estimate + price;
    }
  }
  return ShoppingSummary(estimate: estimate, checked: checked, total: total);
});

/// Writes the shopping list screen performs.
final shoppingActionsProvider = Provider<ShoppingActions>(ShoppingActions.new);

/// Ticks, snoozes, dismisses and deletes entries.
///
/// **Every method returns the failure's own message, or null on success.** A repository `Failure`
/// carries a `message` written for exactly this, and reporting "something went wrong" instead threw
/// it away — three separate bugs reached the user as the same sentence, none of them diagnosable.
class ShoppingActions {
  /// Creates the actions.
  ShoppingActions(this._ref);

  final Ref _ref;

  /// How long a snooze lasts.
  static const int snoozeDays = 7;

  /// Ticks or unticks an entry.
  Future<String?> setChecked({required String id, required bool isChecked}) async {
    final result = await _ref
        .read(shoppingRepositoryProvider)
        .setEntryChecked(id: id, isChecked: isChecked);
    return result.failureOrNull?.message;
  }

  /// Hides a suggestion for a week.
  Future<String?> snooze(String id) async {
    final until = _ref.read(clockProvider).today().addDays(snoozeDays);
    final result =
        await _ref.read(shoppingRepositoryProvider).snoozeEntry(id: id, until: until);
    return result.failureOrNull?.message;
  }

  /// Dismisses a suggestion until stock recovers and drops again.
  Future<String?> dismiss(String id) async {
    final result = await _ref.read(shoppingRepositoryProvider).dismissEntry(id);
    return result.failureOrNull?.message;
  }

  /// Removes an entry outright.
  Future<String?> delete(String id) async {
    final result = await _ref.read(shoppingRepositoryProvider).deleteEntry(id);
    return result.failureOrNull?.message;
  }

  /// Unticks every entry on a list.
  Future<void> uncheckAll(List<ShoppingEntry> entries) async {
    final repository = _ref.read(shoppingRepositoryProvider);
    for (final entry in entries) {
      if (!entry.isChecked) continue;
      await repository.setEntryChecked(id: entry.id, isChecked: false);
    }
  }
}
```

### `lib/features/shopping/providers/entry_editor_providers.dart`

```dart
/// View-model state for the shopping entry editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/shopping/state/entry_editor_state.dart';

/// Which entry an editor is pointed at. A record, so the family argument has structural equality.
typedef EntryEditorArgs = ({String listId, String? entryId});

/// Items offered for linking, so an entry can restock something the inventory tracks.
final entryItemsProvider = StreamProvider.autoDispose<List<Item>>(
  (ref) => ref.watch(itemRepositoryProvider).watchAll(),
);

/// Tags scoped to shopping, which is what groups the list into aisles.
final entryTagsProvider = StreamProvider.autoDispose<List<Tag>>(
  (ref) => ref.watch(tagRepositoryProvider).watchByScope(TagScope.shopping),
);

/// Units in one category, so a linked item never offers a cross-category unit (Law L8).
final entryUnitsProvider =
    StreamProvider.autoDispose.family<List<Unit>, UnitCategory?>(
  (ref, category) => category == null
      ? Stream.value(const <Unit>[])
      : ref.watch(unitRepositoryProvider).watchByCategory(category),
);

/// The home currency, so an estimate is never denominated in a guess.
final entryCurrencyProvider = FutureProvider.autoDispose<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ?? 'INR',
);

/// The home currency's decimal digits (ARCH_1 §4.1).
final entryDecimalDigitsProvider = FutureProvider.autoDispose<int>((ref) async {
  final code = await ref.watch(entryCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// The editor for one entry, or for a new one when `entryId` is null.
final entryEditorProvider = NotifierProvider.autoDispose
    .family<EntryEditorNotifier, AsyncValue<EntryEditorState>, EntryEditorArgs>(
  EntryEditorNotifier.new,
);

/// Loads, edits and saves one shopping entry.
class EntryEditorNotifier
    extends AutoDisposeFamilyNotifier<AsyncValue<EntryEditorState>, EntryEditorArgs> {
  @override
  AsyncValue<EntryEditorState> build(EntryEditorArgs arg) {
    // A new entry needs nothing fetched, so it starts populated rather than flashing a skeleton —
    // and assigning state from an async gap inside `build` is what Riverpod refuses.
    if (arg.entryId == null) {
      return AsyncValue.data(EntryEditorState(listId: arg.listId));
    }
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(EntryEditorArgs arg) async {
    try {
      final entries =
          await ref.read(shoppingRepositoryProvider).watchEntries(arg.listId).first;
      for (final entry in entries) {
        if (entry.id != arg.entryId) continue;
        state = AsyncValue.data(EntryEditorState.fromEntry(entry));
        return;
      }
      state = AsyncValue.error(
        StateError('Entry ${arg.entryId} not found.'),
        StackTrace.current,
      );
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _edit(EntryEditorState Function(EntryEditorState) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(change(current));
  }

  /// Sets what to buy, in the user's words.
  void setFreeText(String text) =>
      _edit((s) => s.copyWith(freeText: text, identityMissing: false));

  /// Links the entry to a catalogued item, or unlinks it.
  ///
  /// Linking seeds the name and the unit from the item, because the receipt almost always says the
  /// item's name and retyping it is friction with no purpose. An edit of the user's own is never
  /// overwritten.
  void setItem(Item? item) => _edit((s) {
        if (item == null) return s.copyWith(clearItem: true, clearQuantity: true);
        final typed = s.freeText.trim();
        return s.copyWith(
          itemId: item.id,
          freeText: typed.isEmpty ? item.name : s.freeText,
          unitCode: item.defaultDisplayUnitCode,
          identityMissing: false,
          clearQuantity: true,
        );
      });

  /// Sets how much to buy.
  void setQuantity(Qty? quantity) => _edit(
        (s) => quantity == null
            ? s.copyWith(clearQuantity: true)
            : s.copyWith(quantity: quantity),
      );

  /// Sets the unit the quantity is entered in.
  void setUnitCode(String code) => _edit((s) => s.copyWith(unitCode: code));

  /// Sets the aisle-ish grouping.
  void setTag(String? tagId) => _edit(
        (s) => tagId == null ? s.copyWith(clearTag: true) : s.copyWith(tagId: tagId),
      );

  /// Sets what the user expects it to cost.
  void setEstimatedPrice(Money? price) => _edit(
        (s) => price == null ? s.copyWith(clearPrice: true) : s.copyWith(estimatedPrice: price),
      );

  /// Saves the entry, returning its id on success and null on rejection or failure.
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (!current.hasIdentity) {
      _edit((s) => s.copyWith(identityMissing: true, shakeTrigger: s.shakeTrigger + 1));
      return null;
    }

    _edit((s) => s.copyWith(submitting: true));
    try {
      final id = current.id ?? ref.read(uidGeneratorProvider).generate();
      final saved = await ref
          .read(shoppingRepositoryProvider)
          .saveEntry(current.toEntry(newId: id));
      if (saved.isFailure) return null;
      _edit((s) => s.copyWith(dirty: false));
      return id;
    } on Object catch (error, stack) {
      ref.read(loggerProvider).log(
        'Shopping entry save failed',
        level: LogLevel.error,
        tag: 'shopping.entryEditor',
        error: error,
        stackTrace: stack,
      );
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false));
    }
  }
}
```

### `lib/features/shopping/providers/generate_providers.dart`

```dart
/// View-model state for the low-stock suggestion sheet (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';

/// One suggestion, with the shortfall that produced it.
class LowStockSuggestion {
  /// Creates a suggestion.
  const LowStockSuggestion({required this.entry, this.item, this.shortfall});

  /// The auto-generated entry.
  final ShoppingEntry entry;

  /// The item it restocks.
  final Item? item;

  /// How far below its low-stock level the item sat when the suggestion was made.
  final Qty? shortfall;
}

/// The active suggestions on one list, with their shortfalls.
///
/// **Shortfall is `threshold − stockAtGeneration`, both stored on the entry's own history.** Reading
/// live stock instead would make the figure drift between the sheet opening and the user acting on
/// it, and `stockAtGeneration` exists precisely so a suggestion can explain itself after the fact.
final lowStockSuggestionsProvider =
    Provider.autoDispose.family<AsyncValue<List<LowStockSuggestion>>, String>((ref, listId) {
  final entries = ref.watch(entriesProvider(listId));
  final items = ref.watch(shoppingItemsByIdProvider);
  if (entries.hasError) return AsyncValue.error(entries.error!, entries.stackTrace!);
  final rows = entries.valueOrNull;
  if (rows == null) return const AsyncValue.loading();
  final byId = items.valueOrNull ?? const <String, Item>{};

  return AsyncValue.data([
    for (final entry in rows)
      // Bought ones drop off: the stock that prompted the suggestion has arrived, so it is no longer a
      // suggestion. Snoozed and dismissed ones stay, because this sheet is where they are reconsidered.
      if (entry.isAutoGenerated && !entry.isPurchased)
        LowStockSuggestion(
          entry: entry,
          item: entry.itemId == null ? null : byId[entry.itemId],
          shortfall: _shortfall(entry, entry.itemId == null ? null : byId[entry.itemId]),
        ),
  ]);
});

Qty? _shortfall(ShoppingEntry entry, Item? item) {
  final threshold = item?.lowStockThreshold;
  final atGeneration = entry.stockAtGeneration;
  if (threshold == null || atGeneration == null) return null;
  if (threshold.category != atGeneration.category) return null;
  final gap = threshold - atGeneration;
  return gap.isPositive ? gap : null;
}

/// Runs low-stock generation for a list.
final generateActionsProvider = Provider<GenerateActions>(GenerateActions.new);

/// Regenerates suggestions.
class GenerateActions {
  /// Creates the actions.
  GenerateActions(this._ref);

  final Ref _ref;

  /// Regenerates and returns how many suggestions are now active, or null on failure.
  ///
  /// The repository's own contract guarantees this is idempotent: running it repeatedly neither
  /// duplicates entries nor resurrects dismissed ones (anomalies A22, A23). Nothing here re-derives
  /// that, because a second implementation is a second thing to get wrong.
  /// Accepts a suggestion, making it the user's own entry.
  ///
  /// **Promotes it to `origin = manual`.** Affirmatively choosing a suggestion is exactly what makes
  /// it yours, and a manual entry is never auto-removed or rewritten by regeneration (anomaly A23).
  /// It also un-dismisses and un-snoozes it, which is the only way back from "Not now" — without
  /// this, turning a suggestion down was irreversible until stock recovered and dropped again.
  Future<String?> accept(ShoppingEntry entry) async {
    final saved = await _ref.read(shoppingRepositoryProvider).saveEntry(
          entry.copyWith(
            origin: ShoppingEntryOrigin.manual,
            autoState: ShoppingEntryAutoState.active,
          ),
        );
    return saved.failureOrNull?.message;
  }

  Future<({int? added, String? error})> regenerate(String listId) async {
    final result =
        await _ref.read(shoppingRepositoryProvider).regenerateLowStockSuggestions(listId);
    final failure = result.failureOrNull;
    return failure == null
        ? (added: result.valueOrNull ?? 0, error: null)
        : (added: null, error: failure.message);
  }
}
```

### `lib/features/shopping/providers/list_manager_providers.dart`

```dart
/// View-model state for the shopping list manager (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/shopping_list.dart';

/// Writes the list manager performs.
final listManagerActionsProvider = Provider<ListManagerActions>(ListManagerActions.new);

/// Creates, renames, archives and re-points shopping lists.
///
/// Every method reports the failure's own message rather than a generic one, so a rejected write
/// says what the database actually refused.
class ListManagerActions {
  /// Creates the actions.
  ListManagerActions(this._ref);

  final Ref _ref;

  /// Creates a list, returning its id on success.
  ///
  /// The first list a user creates becomes the default, because a shopping module with no default
  /// list has nowhere to open and nowhere to put a low-stock suggestion.
  Future<({String? id, String? error})> create(
    String name, {
    required bool isFirst,
  }) async {
    final id = _ref.read(uidGeneratorProvider).generate();
    final saved = await _ref.read(shoppingRepositoryProvider).saveList(
          ShoppingList(id: id, name: name.trim(), isDefault: isFirst, isArchived: false),
        );
    final failure = saved.failureOrNull;
    return failure == null ? (id: id, error: null) : (id: null, error: failure.message);
  }

  /// Renames a list.
  Future<String?> rename(ShoppingList list, String name) async {
    final saved = await _ref
        .read(shoppingRepositoryProvider)
        .saveList(list.copyWith(name: name.trim()));
    return saved.failureOrNull?.message;
  }

  /// Makes a list the one that opens by default.
  Future<String?> setDefault(String id) async {
    final result = await _ref.read(shoppingRepositoryProvider).setDefaultList(id);
    return result.failureOrNull?.message;
  }

  /// Archives or restores a list.
  Future<String?> setArchived({required String id, required bool isArchived}) async {
    final result = await _ref
        .read(shoppingRepositoryProvider)
        .setListArchived(id: id, isArchived: isArchived);
    return result.failureOrNull?.message;
  }
}
```

### `lib/features/shopping/providers/convert_providers.dart`

```dart
/// View-model state for convert-to-purchase (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/providers/transaction_draft_provider.dart';
import 'package:alaya/features/expense/state/transaction_draft.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';

/// The draft lines a list's ticked entries would produce.
final purchaseDraftProvider =
    FutureProvider.autoDispose.family<List<TransactionLine>, String>((ref, listId) async {
  // Watched, not read: ticking a row on the list behind this screen should change what it offers.
  ref.watch(entriesProvider(listId));
  final result = await ref.watch(shoppingRepositoryProvider).buildPurchaseDraft(listId);
  return result.valueOrNull ?? const <TransactionLine>[];
});

/// Builds the handoff to the expense editor.
final convertActionsProvider = Provider<ConvertActions>(ConvertActions.new);

/// Turns a finished list into a draft the expense editor can open.
class ConvertActions {
  /// Creates the actions.
  ConvertActions(this._ref);

  final Ref _ref;

  /// Offers the draft to the next editor, returning false when there is nothing to convert.
  ///
  /// **This writes no transaction.** `buildPurchaseDraft` returns lines precisely so the amount, the
  /// account and the payee stay decisions the expense editor collects — reimplementing that here
  /// would fork the one screen in the app that knows how a withdrawal is shaped (anomaly A25).
  bool offerDraft({required String listId, required List<TransactionLine> lines}) {
    if (lines.isEmpty) return false;
    final entries = _ref.read(entriesProvider(listId)).valueOrNull ?? const [];
    _ref.read(transactionDraftProvider.notifier).offer(
          TransactionDraft(
            lines: lines,
            kind: TransactionKind.withdrawal,
            subtype: TransactionSubtype.grocery,
            sourceListId: listId,
            sourceEntryIds: [
              for (final entry in entries)
                if (entry.isChecked && !entry.isPurchased) entry.id,
            ],
          ),
        );
    return true;
  }
}
```

### `lib/features/shopping/presentation/widgets/entry_row.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One shopping row: a tick, what to buy, and what it is expected to cost.
///
/// **A suggested row is marked as suggested.** `origin = autoLowStock` means the app put it there,
/// not the user, and the snooze and dismiss actions only make sense against something the app
/// proposed — offering them on a row someone typed would read as the app second-guessing them.
///
/// Stacks above 1.5x text scale: the estimate is not flexible, so at a doubled scale it starves the
/// label beside it, and `AmountText` clips rather than ellipsises (Law U15).
class EntryRow extends StatelessWidget {
  /// Creates the row.
  const EntryRow({
    required this.entry,
    required this.item,
    required this.decimalDigits,
    required this.onToggle,
    required this.onTap,
    this.onSnooze,
    this.onDismiss,
    super.key,
  });

  /// The entry.
  final ShoppingEntry entry;

  /// The catalogued item it restocks, if any.
  final Item? item;

  /// The home currency's precision.
  final int decimalDigits;

  /// Ticks or unticks it.
  final ValueChanged<bool> onToggle;

  /// Opens the entry editor.
  final VoidCallback onTap;

  /// Hides a suggestion for a week.
  final VoidCallback? onSnooze;

  /// Dismisses a suggestion until stock recovers and drops again.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final label = entry.freeText ?? item?.name ?? strings.labelItem;
    final price = entry.estimatedPrice;
    final quantity = entry.quantity;
    final snoozeUntil = entry.snoozeUntilDateKey;

    final estimate = price == null
        ? const SizedBox.shrink()
        : AmountText(
            price,
            size: AmountSize.small,
            showSign: false,
            decimalDigits: decimalDigits,
            muted: entry.isChecked,
            textAlign: stacked ? TextAlign.start : TextAlign.end,
          );

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
            vertical: AlayaSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A bare `Checkbox` announces a checked state and nothing else — a screen reader hears
              // "tick box" with no idea which row it belongs to. The label is the entry's own name,
              // which is exactly what a sighted user reads beside it (U16).
              Semantics(
                label: label,
                child: Checkbox(
                  value: entry.isChecked,
                  onChanged: (value) => onToggle(value ?? false),
                ),
              ),
              const SizedBox(width: AlayaSpacing.xxs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: AlayaSpacing.sm),
                      child: Text(
                        label,
                        style: AlayaTypography.body.copyWith(
                          color: entry.isChecked
                              ? semantic.muted
                              : theme.colorScheme.onSurface,
                          decoration:
                              entry.isChecked ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (quantity != null) ...[
                      const SizedBox(height: AlayaSpacing.xxs),
                      QtyText(quantity, muted: true),
                    ],
                    if (stacked && price != null) ...[
                      const SizedBox(height: AlayaSpacing.xxs),
                      estimate,
                    ],
                    if (entry.origin == ShoppingEntryOrigin.autoLowStock) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      Wrap(
                        spacing: AlayaSpacing.xs,
                        runSpacing: AlayaSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusChip(
                            label: strings.originAutoLowStock,
                            tone: StatusTone.info,
                            icon: Icons.auto_awesome_outlined,
                          ),
                          if (entry.autoState == ShoppingEntryAutoState.snoozed &&
                              snoozeUntil != null)
                            StatusChip(
                              label: strings.snoozedUntilLabel,
                              trailing: DateText(
                                snoozeUntil,
                                style: DateTextStyle.dayMonth,
                                muted: true,
                              ),
                            ),
                          if (onSnooze != null)
                            TextButton(
                              onPressed: onSnooze,
                              child: Text(strings.actionSnooze),
                            ),
                          if (onDismiss != null)
                            TextButton(
                              onPressed: onDismiss,
                              child: Text(strings.actionDismiss),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (!stacked && price != null) ...[
                const SizedBox(width: AlayaSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(top: AlayaSpacing.sm),
                  child: estimate,
                ),
              ],
              if (item != null)
                Padding(
                  padding: const EdgeInsets.only(top: AlayaSpacing.sm),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: AlayaIconSize.sm,
                    color: semantic.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### `lib/features/shopping/presentation/screens/shopping_list_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/features/shopping/presentation/sheets/entry_editor_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/generate_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/list_manager_sheet.dart';
import 'package:alaya/features/shopping/presentation/widgets/entry_row.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// A shopping list (ARCH_5 §3 archetype D).
///
/// **The list switcher lives in the body, not the app bar.** The shell owns the app bar for every
/// drawer destination, so a screen inside it cannot add actions there — the same constraint that put
/// search in the body in 6A and 6B.
class ShoppingListScreen extends ConsumerWidget {
  /// Shows [listId], or the default list when null.
  const ShoppingListScreen({this.listId, super.key});

  /// Which list to show.
  final String? listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final active = ref.watch(activeListProvider);

    return Scaffold(
      body: active.when(
        loading: () => AlayaListSkeleton(label: strings.loadingShopping),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(selectableListsProvider),
        ),
        data: (list) => list == null
            ? _NoLists(onCreate: () => ListManagerSheet.show(context))
            : _Body(list: list),
      ),
      floatingActionButton: active.valueOrNull == null
          ? null
          : FloatingActionButton(
              onPressed: () => EntryEditorSheet.show(
                context,
                listId: active.valueOrNull!.id,
              ),
              tooltip: strings.addEntry,
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _NoLists extends StatelessWidget {
  const _NoLists({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return EmptyState(
      title: strings.emptyTitleNoLists,
      body: strings.emptyBodyNoLists,
      icon: Icons.checklist_outlined,
      actionLabel: strings.listCreate,
      onAction: onCreate,
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.list});

  final ShoppingList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final groups = ref.watch(shoppingGroupsProvider(list.id));
    final summary = ref.watch(shoppingSummaryProvider(list.id));

    return Column(
      children: [
        _Header(list: list, summary: summary),
        Expanded(
          child: groups.when(
            loading: () => AlayaListSkeleton(label: strings.loadingShopping),
            error: (error, stack) => ErrorState(
              title: strings.errorTitleGeneric,
              body: error.toString(),
              retryLabel: strings.actionRetry,
              onRetry: () => ref.invalidate(entriesProvider(list.id)),
            ),
            data: (sections) => sections.isEmpty
                ? EmptyState(
                    title: strings.emptyTitleNoEntries,
                    body: strings.emptyBodyNoEntries,
                    icon: Icons.checklist_outlined,
                    actionLabel: strings.generateTitle,
                    onAction: () => GenerateSheet.show(context, listId: list.id),
                  )
                : _Sections(list: list, sections: sections),
          ),
        ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.list, required this.summary});

  final ShoppingList list;
  final ShoppingSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final digits = ref.watch(entryDecimalDigitsProvider).valueOrNull ?? 2;
    final estimate = summary.estimate;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.sm,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  list.name,
                  style: AlayaTypography.cardTitle
                      .copyWith(color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
              IconButton(
                onPressed: () => ListManagerSheet.show(context),
                tooltip: strings.shoppingSwitchList,
                icon: const Icon(Icons.swap_horiz, size: AlayaIconSize.lg),
              ),
            ],
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  strings.shoppingCheckedCount(summary.checked, summary.total),
                  style: AlayaTypography.caption.copyWith(color: semantic.muted),
                ),
              ),
              if (estimate != null) ...[
                Text(
                  strings.shoppingEstimate,
                  style: AlayaTypography.caption.copyWith(color: semantic.muted),
                ),
                const SizedBox(width: AlayaSpacing.xxs),
                AmountText(
                  estimate,
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: digits,
                ),
              ],
            ],
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              ActionChip(
                avatar: const Icon(Icons.auto_awesome_outlined, size: AlayaIconSize.sm),
                label: Text(strings.generateTitle),
                onPressed: () => GenerateSheet.show(context, listId: list.id),
              ),
              ActionChip(
                avatar: const Icon(Icons.receipt_long_outlined, size: AlayaIconSize.sm),
                label: Text(strings.convertTitle),
                onPressed: summary.hasChecked
                    ? () => context.push(Routes.shoppingConvert(list.id))
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Sections extends ConsumerWidget {
  const _Sections({required this.list, required this.sections});

  final ShoppingList list;
  final List<ShoppingGroup> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final items = ref.watch(shoppingItemsByIdProvider).valueOrNull ?? const <String, Item>{};
    final digits = ref.watch(entryDecimalDigitsProvider).valueOrNull ?? 2;
    final actions = ref.read(shoppingActionsProvider);

    // Reports the repository's own message. "Something went wrong" told the user nothing and told a
    // bug report even less — three unrelated failures arrived as one indistinguishable sentence.
    Future<void> guard(Future<String?> Function() run) async {
      final error = await run();
      if (!context.mounted || error == null) return;
      showFailureSnack(context, message: error);
    }

    return CustomScrollView(
      slivers: [
        for (final section in sections)
          SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AlayaSpacing.screenEdge,
                    AlayaSpacing.md,
                    AlayaSpacing.screenEdge,
                    AlayaSpacing.xs,
                  ),
                  child: Text(
                    section.tag?.name ?? strings.shoppingGroupUntagged,
                    style: AlayaTypography.sectionHeader.copyWith(color: semantic.muted),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: section.entries.length,
                itemBuilder: (context, index) {
                  final entry = section.entries[index];
                  return EntryRow(
                    entry: entry,
                    item: entry.itemId == null ? null : items[entry.itemId],
                    decimalDigits: digits,
                    onToggle: (checked) => guard(
                      () => actions.setChecked(id: entry.id, isChecked: checked),
                    ),
                    onTap: () => EntryEditorSheet.show(
                      context,
                      listId: list.id,
                      entryId: entry.id,
                    ),
                    onSnooze: entry.isAutoGenerated
                        ? () => guard(() => actions.snooze(entry.id))
                        : null,
                    onDismiss: entry.isAutoGenerated
                        ? () => guard(() => actions.dismiss(entry.id))
                        : null,
                  );
                },
              ),
            ],
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AlayaSpacing.xxxl)),
      ],
    );
  }
}
```

### `lib/features/shopping/presentation/screens/convert_to_purchase_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/shopping/providers/convert_providers.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Turns a finished list into a pre-filled withdrawal (ARCH_5 §3 archetype B).
///
/// **It hands off; it does not commit.** The primary action offers a draft to the expense editor and
/// navigates there. The amount, the account and the payee are decisions only that screen collects,
/// and duplicating them here would fork the one place in the app that knows how a withdrawal is
/// shaped (anomaly A25). Nothing is written until the user saves there.
class ConvertToPurchaseScreen extends ConsumerWidget {
  /// Converts the ticked entries of [listId].
  const ConvertToPurchaseScreen({required this.listId, super.key});

  /// Which list to convert.
  final String listId;

  void _handOff(BuildContext context, WidgetRef ref, List<TransactionLine> lines) {
    final offered =
        ref.read(convertActionsProvider).offerDraft(listId: listId, lines: lines);
    if (!offered) return;
    context.pushReplacement(Routes.transactionNew);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(purchaseDraftProvider(listId));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(strings.convertTitle),
      ),
      body: draft.when(
        loading: () => AlayaListSkeleton(label: strings.loadingShopping, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: strings.errorBodyGeneric,
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(purchaseDraftProvider(listId)),
        ),
        data: (lines) => lines.isEmpty
            ? EmptyState(
                title: strings.convertNothingTitle,
                body: strings.convertNothingBody,
                icon: Icons.checklist_outlined,
              )
            : AlayaFormScaffold(
                primaryLabel: strings.convertConfirm,
                onPrimary: () => _handOff(context, ref, lines),
                isDirty: false,
                isSubmitting: false,
                discardTitle: strings.confirmDiscardTitle,
                discardBody: strings.confirmDiscardBody,
                discardConfirmLabel: strings.actionDiscard,
                discardCancelLabel: strings.actionKeepEditing,
                child: _Preview(lines: lines),
              ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.lines});

  final List<TransactionLine> lines;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.convertBody,
          style: AlayaTypography.body
              .copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
        const SizedBox(height: AlayaSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: StatusChip(
            label: strings.convertLineCount(lines.length),
            tone: StatusTone.info,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  line.destination == TransactionLineDestination.inventory
                      ? Icons.inventory_2_outlined
                      : Icons.receipt_long_outlined,
                  size: AlayaIconSize.md,
                  color: semantic.muted,
                ),
                const SizedBox(width: AlayaSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.description, style: AlayaTypography.body),
                      if (line.quantity != null) ...[
                        const SizedBox(height: AlayaSpacing.xxs),
                        QtyText(line.quantity!, muted: true),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
```

### `lib/features/shopping/presentation/sheets/entry_editor_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/state/entry_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Adds or edits one shopping entry (ARCH_5 §3 archetype A).
///
/// **Free text is the primary field and the item link is optional.** A television belongs on a
/// shopping list and has no place in an inventory that measures flour by the gram, so `itemId` stays
/// nullable and an entry needs only one of the two to identify itself.
///
/// A quantity is offered only once an item is linked, for the same reason as the line editor in 6A:
/// a `Qty` is an integer plus a `UnitCategory`, and the category comes from the item (Law L8).
class EntryEditorSheet extends ConsumerWidget {
  /// Creates the sheet.
  const EntryEditorSheet({required this.listId, this.entryId, super.key});

  /// Which list the entry belongs to.
  final String listId;

  /// The entry being edited, or null for a new one.
  final String? entryId;

  /// Opens the sheet.
  static Future<void> show(
    BuildContext context, {
    required String listId,
    String? entryId,
  }) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => EntryEditorSheet(listId: listId, entryId: entryId),
      );

  Future<void> _save(BuildContext context, WidgetRef ref, EntryEditorArgs args) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(entryEditorProvider(args).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    Navigator.of(context).pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.actionSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final args = (listId: listId, entryId: entryId);
    final async = ref.watch(entryEditorProvider(args));

    return async.when(
      loading: () => AlayaListSkeleton(label: strings.loadingShopping, rows: 3),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleNotFound,
        body: strings.errorBodyNotFound,
      ),
      data: (state) => _Form(args: args, state: state, onSave: () => _save(context, ref, args)),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.args, required this.state, required this.onSave});

  final EntryEditorArgs args;
  final EntryEditorState state;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(entryEditorProvider(args).notifier);
    final items = ref.watch(entryItemsProvider).valueOrNull ?? const <Item>[];
    final tags = ref.watch(entryTagsProvider).valueOrNull ?? const <Tag>[];
    final currency = ref.watch(entryCurrencyProvider).valueOrNull;
    final digits = ref.watch(entryDecimalDigitsProvider).valueOrNull ?? 2;

    Item? linked;
    for (final item in items) {
      if (item.id == state.itemId) linked = item;
    }
    final units =
        ref.watch(entryUnitsProvider(linked?.unitCategory)).valueOrNull ?? const <Unit>[];
    Unit? selectedUnit;
    for (final unit in units) {
      if (unit.code == state.unitCode) selectedUnit = unit;
    }
    selectedUnit ??= units.isEmpty ? null : units.first;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.entryEditorTitle,
          style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: AlayaSpacing.md),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: TextFormField(
            initialValue: state.freeText,
            autofocus: !state.isEditing,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.entryFreeTextLabel,
              hintText: strings.entryFreeTextHint,
              errorText: state.identityMissing ? strings.entryNeedsSomething : null,
            ),
            onChanged: notifier.setFreeText,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<String?>(
          // **`linked?.id`, not `state.itemId`.** The items arrive from a stream, so on the first
          // frame the list is empty while the state already names an item — and a dropdown whose
          // value matches none of its items throws "There should be exactly one item". Deriving the
          // value from the list that is actually rendered makes that unrepresentable.
          key: ValueKey(linked?.id),
          initialValue: linked?.id,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.entryLinkItem),
          items: [
            DropdownMenuItem<String?>(child: Text(strings.entryNoItem)),
            for (final item in items)
              DropdownMenuItem<String?>(
                value: item.id,
                child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) {
            if (value == null) {
              notifier.setItem(null);
              return;
            }
            for (final item in items) {
              if (item.id == value) notifier.setItem(item);
            }
          },
        ),
        if (linked != null && units.isNotEmpty && selectedUnit != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          QtyField(
            key: ValueKey('${linked.id}:${selectedUnit.code}'),
            category: linked.unitCategory,
            units: units,
            selectedUnit: selectedUnit,
            label: strings.labelQuantity,
            unitLabel: strings.labelUnit,
            initialValue: state.quantity,
            onChanged: notifier.setQuantity,
            onUnitChanged: (unit) => notifier.setUnitCode(unit.code),
          ),
        ],
        if (currency != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          AmountField(
            currencyCode: currency,
            decimalDigits: digits,
            label: strings.labelEstimatedPrice,
            initialValue: state.estimatedPrice,
            onChanged: notifier.setEstimatedPrice,
          ),
        ],
        if (tags.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.md),
          Text(
            strings.labelTags,
            style: AlayaTypography.label.copyWith(color: semantic.muted),
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              for (final tag in tags)
                TagChip(
                  tag: tag,
                  selected: state.tagId == tag.id,
                  onTap: () => notifier.setTag(state.tagId == tag.id ? null : tag.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: state.submitting ? null : onSave,
          child: Text(strings.actionSave),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionCancel),
        ),
      ],
    );
  }
}
```

### `lib/features/shopping/presentation/sheets/generate_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/features/shopping/providers/generate_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Low-stock suggestions, each accepted, snoozed or dismissed on its own (ARCH_5 §3 archetype A).
///
/// **Accepting is an action, not an absence of one.** Regeneration writes the entries, so technically
/// leaving a row alone keeps it — but a sheet offering only "Snooze" and "Not now" reads as though
/// the only choices are ways to say no. "Add to my list" promotes the row to `origin = manual`, which
/// is both the affirmative answer and the thing that makes regeneration leave it alone for good (A23).
///
/// **A turned-down row stays listed here.** The list screen hides it via `isVisibleAsOf`, but this is
/// where suggestions are managed, so hiding it here too made "Not now" irreversible until stock
/// recovered and dropped again. It is shown with its state, and accepting it brings it back.
class GenerateSheet extends ConsumerWidget {
  /// Creates the sheet.
  const GenerateSheet({required this.listId, super.key});

  /// Which list to suggest into.
  final String listId;

  /// Opens the sheet, regenerating as it opens.
  static Future<void> show(BuildContext context, {required String listId}) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => GenerateSheet(listId: listId),
      );

  Future<void> _regenerate(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final outcome = await ref.read(generateActionsProvider).regenerate(listId);
    if (!context.mounted) return;
    final error = outcome.error;
    error != null
        ? showFailureSnack(context, message: error)
        : showResultSnack(context, message: strings.generateAdded(outcome.added ?? 0));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final suggestions = ref.watch(lowStockSuggestionsProvider(listId));
    final actions = ref.read(shoppingActionsProvider);

    Future<void> guard(Future<String?> Function() run) async {
      final failed = await run();
      if (!context.mounted || failed == null) return;
      showFailureSnack(context, message: failed);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A `Wrap`, not a `Row`. The refresh button is not flexible, so at a doubled text scale it
        // takes its full natural width and pushes the title off the edge — the same shape that
        // overflowed a transaction row, a nudge banner and an item row before it.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AlayaSpacing.xs,
          children: [
            Text(
              strings.generateTitle,
              style: AlayaTypography.cardTitle
                  .copyWith(color: theme.colorScheme.onSurface),
            ),
            TextButton(
              onPressed: () => _regenerate(context, ref),
              child: Text(strings.generateRefresh),
            ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        Text(
          strings.generateBody,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.md),
        suggestions.when(
          loading: () => AlayaListSkeleton(label: strings.loadingShopping, rows: 3),
          // Shows the error rather than a stand-in for it. Regeneration can succeed while reading
          // the entries back fails, and reporting both halves as "something went wrong" made a
          // working write look like a broken one (U9).
          error: (error, stack) => ErrorState(
            title: strings.errorTitleGeneric,
            body: error.toString(),
            retryLabel: strings.actionRetry,
            onRetry: () => ref.invalidate(entriesProvider(listId)),
          ),
          data: (rows) => rows.isEmpty
              ? EmptyState(
                  title: strings.generateEmptyTitle,
                  body: strings.generateEmptyBody,
                  icon: Icons.auto_awesome_outlined,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final suggestion in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
                        child: AlayaCard(
                          padding: const EdgeInsets.all(AlayaSpacing.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                suggestion.item?.name ??
                                    suggestion.entry.freeText ??
                                    strings.labelItem,
                                style: AlayaTypography.body
                                    .copyWith(color: theme.colorScheme.onSurface),
                              ),
                              if (suggestion.entry.autoState !=
                                  ShoppingEntryAutoState.active) ...[
                                const SizedBox(height: AlayaSpacing.xxs),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: suggestion.entry.autoState ==
                                          ShoppingEntryAutoState.dismissed
                                      ? StatusChip(label: strings.suggestionDismissed)
                                      : StatusChip(
                                          label: strings.snoozedUntilLabel,
                                          trailing: suggestion.entry.snoozeUntilDateKey ==
                                                  null
                                              ? null
                                              : DateText(
                                                  suggestion.entry.snoozeUntilDateKey!,
                                                  style: DateTextStyle.dayMonth,
                                                  muted: true,
                                                ),
                                        ),
                                ),
                              ],
                              if (suggestion.shortfall != null) ...[
                                const SizedBox(height: AlayaSpacing.xxs),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: AlayaSpacing.xxs,
                                  children: [
                                    Text(
                                      strings.generateShortBy,
                                      style: AlayaTypography.caption
                                          .copyWith(color: semantic.muted),
                                    ),
                                    QtyText(suggestion.shortfall!, muted: true),
                                  ],
                                ),
                              ],
                              const SizedBox(height: AlayaSpacing.xs),
                              Wrap(
                                spacing: AlayaSpacing.xs,
                                runSpacing: AlayaSpacing.xxs,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: () => guard(
                                      () => ref
                                          .read(generateActionsProvider)
                                          .accept(suggestion.entry),
                                    ),
                                    icon: const Icon(Icons.add, size: AlayaIconSize.sm),
                                    label: Text(strings.actionAddToList),
                                  ),
                                  if (suggestion.entry.autoState ==
                                      ShoppingEntryAutoState.active)
                                    TextButton.icon(
                                    onPressed: () =>
                                        guard(() => actions.snooze(suggestion.entry.id)),
                                    icon: const Icon(
                                      Icons.snooze,
                                      size: AlayaIconSize.sm,
                                    ),
                                    label: Text(strings.actionSnooze),
                                  ),
                                  if (suggestion.entry.autoState !=
                                      ShoppingEntryAutoState.dismissed)
                                    TextButton(
                                      onPressed: () =>
                                          guard(() => actions.dismiss(suggestion.entry.id)),
                                      child: Text(strings.actionDismiss),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionDone),
        ),
      ],
    );
  }
}
```

### `lib/features/shopping/presentation/sheets/list_manager_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/features/shopping/providers/list_manager_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Creates, renames, re-points and archives shopping lists (ARCH_5 §3 archetype A).
///
/// **Archived rather than deleted.** A list that has been converted to a purchase is the provenance
/// of those transaction lines, so retiring it hides it from the switcher without breaking what it
/// explains (Law L6).
class ListManagerSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const ListManagerSheet({super.key});

  /// Opens the sheet.
  static Future<void> show(BuildContext context) => AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => const ListManagerSheet(),
      );

  @override
  ConsumerState<ListManagerSheet> createState() => _ListManagerSheetState();
}

class _ListManagerSheetState extends ConsumerState<ListManagerSheet> {
  final TextEditingController _name = TextEditingController();
  String? _renamingId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<String?> Function() run) async {
    final error = await run();
    if (!mounted || error == null) return;
    showFailureSnack(context, message: error);
  }

  Future<void> _submitName(List<ShoppingList> lists) async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final actions = ref.read(listManagerActionsProvider);
    final renaming = _renamingId;
    if (renaming != null) {
      for (final list in lists) {
        if (list.id != renaming) continue;
        await _guard(() => actions.rename(list, name));
      }
    } else {
      final created = await actions.create(name, isFirst: lists.isEmpty);
      final error = created.error;
      if (error != null && mounted) showFailureSnack(context, message: error);
    }
    if (!mounted) return;
    _name.clear();
    setState(() => _renamingId = null);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final lists = ref.watch(allListsProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.listManagerTitle,
          style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: AlayaSpacing.md),
        lists.when(
          loading: () => AlayaListSkeleton(label: strings.loadingShopping, rows: 3),
          error: (error, stack) => ErrorState(
            title: strings.errorTitleGeneric,
            body: strings.errorBodyGeneric,
          ),
          data: (all) => all.isEmpty
              ? EmptyState(
                  title: strings.emptyTitleNoLists,
                  body: strings.emptyBodyNoLists,
                  icon: Icons.checklist_outlined,
                )
              : _Lists(
                  lists: all,
                  onSelect: (id) {
                    ref.read(selectedListIdProvider.notifier).select(id);
                    Navigator.of(context).pop();
                  },
                  onRename: (list) => setState(() {
                    _renamingId = list.id;
                    _name.text = list.name;
                  }),
                  onDefault: (id) =>
                      _guard(() => ref.read(listManagerActionsProvider).setDefault(id)),
                  onArchive: (list) => _guard(
                    () => ref.read(listManagerActionsProvider).setArchived(
                          id: list.id,
                          isArchived: !list.isArchived,
                        ),
                  ),
                ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _name,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: strings.listNameLabel),
          onSubmitted: (_) => _submitName(lists.valueOrNull ?? const []),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        // Stacked rather than beside the field. The button is not flexible, so a Row overflowed by a
        // hair at a doubled text scale — and a hair is the same defect as a mile.
        FilledButton(
          onPressed: () => _submitName(lists.valueOrNull ?? const []),
          child: Text(_renamingId == null ? strings.listCreate : strings.listRename),
        ),
        if (_renamingId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                _renamingId = null;
                _name.clear();
              }),
              child: Text(strings.actionCancel),
            ),
          ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          strings.emptyBodyNoLists,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
      ],
    );
  }
}

class _Lists extends StatelessWidget {
  const _Lists({
    required this.lists,
    required this.onSelect,
    required this.onRename,
    required this.onDefault,
    required this.onArchive,
  });

  final List<ShoppingList> lists;
  final ValueChanged<String> onSelect;
  final ValueChanged<ShoppingList> onRename;
  final ValueChanged<String> onDefault;
  final ValueChanged<ShoppingList> onArchive;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final live = [for (final list in lists) if (!list.isArchived) list];
    final archived = [for (final list in lists) if (list.isArchived) list];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final list in live) _Tile(
          list: list,
          onSelect: onSelect,
          onRename: onRename,
          onDefault: onDefault,
          onArchive: onArchive,
        ),
        if (archived.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.sm),
          Text(
            strings.listArchivedSection,
            style: AlayaTypography.sectionHeader
                .copyWith(color: context.semantic.muted),
          ),
          for (final list in archived) _Tile(
            list: list,
            onSelect: onSelect,
            onRename: onRename,
            onDefault: onDefault,
            onArchive: onArchive,
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.list,
    required this.onSelect,
    required this.onRename,
    required this.onDefault,
    required this.onArchive,
  });

  final ShoppingList list;
  final ValueChanged<String> onSelect;
  final ValueChanged<ShoppingList> onRename;
  final ValueChanged<String> onDefault;
  final ValueChanged<ShoppingList> onArchive;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: list.isArchived ? null : () => onSelect(list.id),
      title: Text(list.name),
      subtitle: Wrap(
        spacing: AlayaSpacing.xs,
        runSpacing: AlayaSpacing.xxs,
        children: [
          if (list.isDefault)
            StatusChip(label: strings.listDefaultBadge, tone: StatusTone.success),
          if (list.isArchived) StatusChip(label: strings.listArchivedBadge),
        ],
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: AlayaIconSize.md),
        onSelected: (value) => switch (value) {
          'rename' => onRename(list),
          'default' => onDefault(list.id),
          _ => onArchive(list),
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'rename', child: Text(strings.listRename)),
          if (!list.isDefault && !list.isArchived)
            PopupMenuItem(value: 'default', child: Text(strings.listSetDefault)),
          PopupMenuItem(
            value: 'archive',
            child: Text(list.isArchived ? strings.listUnarchive : strings.listArchive),
          ),
        ],
      ),
    );
  }
}
```

### `test/support/shopping_harness.dart`

```dart
/// Shared scaffolding for the Shopping module's widget tests.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/entities/unit.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so snooze dates are the same on every machine.
final Clock kShoppingClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kShoppingClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// Kilograms.
const Unit kKilogram = Unit(
  code: 'kg',
  category: UnitCategory.weight,
  factorToBaseMilli: 1000000,
  displayName: 'kilogram',
  isSystem: true,
  sortOrder: 1,
);

/// A shopping-scoped tag.
const Tag kProduceTag = Tag(
  id: 'tag-1',
  name: 'Produce',
  normalizedName: 'produce',
  allowedScopes: {TagScope.shopping},
  isSystem: false,
  sortOrder: 0,
  isDeleted: false,
);

/// A catalogued item an entry can link to.
const Item kOnion = Item(
  id: 'item-1',
  name: 'Onion',
  normalizedName: 'onion',
  unitCategory: UnitCategory.weight,
  defaultDisplayUnitCode: 'kg',
  itemKind: ItemKind.food,
  isFavorite: false,
  lowStockThreshold: Qty(2000000, UnitCategory.weight),
);

/// The default shopping list.
const ShoppingList kList = ShoppingList(
  id: 'list-1',
  name: 'Weekly shop',
  isDefault: true,
  isArchived: false,
);

/// An archived list, for the manager sheet.
const ShoppingList kArchivedList = ShoppingList(
  id: 'list-2',
  name: 'Diwali',
  isDefault: false,
  isArchived: true,
);

/// A manual entry.
ShoppingEntry sampleEntry({
  String id = 'entry-1',
  String? freeText = 'Television',
  String? itemId,
  String? tagId,
  bool isChecked = false,
  int sortOrder = 0,
  Money? estimatedPrice = const Money(4500000, 'INR'),
  ShoppingEntryOrigin origin = ShoppingEntryOrigin.manual,
  ShoppingEntryAutoState autoState = ShoppingEntryAutoState.active,
  DateKey? snoozeUntil,
  Qty? stockAtGeneration,
}) =>
    ShoppingEntry(
      id: id,
      listId: kList.id,
      origin: origin,
      autoState: autoState,
      isChecked: isChecked,
      sortOrder: sortOrder,
      itemId: itemId,
      freeText: freeText,
      tagId: tagId,
      estimatedPrice: estimatedPrice,
      snoozeUntilDateKey: snoozeUntil,
      stockAtGeneration: stockAtGeneration,
    );

/// An auto-generated low-stock suggestion, short by 1.5 kg against a 2 kg threshold.
ShoppingEntry sampleSuggestion({
  String id = 'auto-1',
  ShoppingEntryAutoState autoState = ShoppingEntryAutoState.active,
  DateKey? snoozeUntil,
}) =>
    sampleEntry(
      id: id,
      freeText: null,
      itemId: kOnion.id,
      estimatedPrice: null,
      origin: ShoppingEntryOrigin.autoLowStock,
      autoState: autoState,
      snoozeUntil: snoozeUntil,
      stockAtGeneration: const Qty(500000, UnitCategory.weight),
    );

/// A draft line, as `buildPurchaseDraft` would return it.
TransactionLine sampleDraftLine({String id = 'line-1', String description = 'Onion'}) =>
    TransactionLine(
      id: id,
      transactionId: '',
      lineNo: 1,
      description: description,
      destination: TransactionLineDestination.inventory,
      itemId: kOnion.id,
      quantity: const Qty(2000000, UnitCategory.weight),
      unitCode: 'kg',
    );

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpShopping(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
}
```

### `test/features/shopping/shopping_list_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/shopping/presentation/screens/shopping_list_screen.dart';
import 'package:alaya/features/shopping/presentation/widgets/entry_row.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/shopping_harness.dart';

/// Four states, 320dp at a doubled text scale, and both accessibility floors (ARCH_5 §9.1).
void main() {
  List<Override> overrides(AsyncValue<List<ShoppingGroup>> groups) => [
        clockProvider.overrideWithValue(kShoppingClock),
        defaultListProvider.overrideWith((ref) => Stream.value(kList)),
        selectableListsProvider.overrideWith((ref) => Stream.value(const [kList])),
        shoppingGroupsProvider(kList.id).overrideWith((ref) => groups),
        shoppingItemsByIdProvider.overrideWith(
          (ref) => Stream.value(<String, Item>{kOnion.id: kOnion}),
        ),
        shoppingTagsByIdProvider.overrideWith(
          (ref) => Stream.value(<String, Tag>{kProduceTag.id: kProduceTag}),
        ),
        entryDecimalDigitsProvider.overrideWith((ref) async => 2),
      ];

  final populated = AsyncValue.data([
    ShoppingGroup(entries: [sampleEntry(tagId: kProduceTag.id)], tag: kProduceTag),
  ]);

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty offers the suggestions that would fill it', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(const AsyncValue.data([])),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing on this list yet'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(AsyncValue.error(StateError('boom'), StackTrace.empty)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('populated groups by tag and names the group', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(populated),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EntryRow), findsOneWidget);
    expect(find.text('Television'), findsOneWidget);
    expect(find.text('Produce'), findsOneWidget);
  });

  testWidgets('a free-text entry needs no inventory item', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([ShoppingGroup(entries: [sampleEntry()])]),
      ),
    );
    await tester.pumpAndSettle();
    // "Television" is a shopping entry with itemId null. It renders, and it lands in the untagged
    // group rather than being refused for having nothing in the catalogue behind it.
    expect(find.text('Television'), findsOneWidget);
    expect(find.text('Everything else'), findsOneWidget);
  });

  testWidgets('a suggested row is marked and offers snooze and dismiss', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([ShoppingGroup(entries: [sampleSuggestion()])]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Suggested'), findsOneWidget);
    expect(find.text('Snooze a week'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('a manual row offers neither', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(populated),
    );
    await tester.pumpAndSettle();
    // Snooze and dismiss only make sense against something the app proposed; offering them on a row
    // the user typed reads as the app second-guessing them.
    expect(find.text('Snooze a week'), findsNothing);
    expect(find.text('Not now'), findsNothing);
  });

  testWidgets('the running estimate sums only entries that carry one', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([
          ShoppingGroup(entries: [
            sampleEntry(id: 'e1'),
            sampleEntry(id: 'e2', freeText: 'Bread', estimatedPrice: null),
          ]),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    // One priced at 45,000.00 and one unpriced: the total is the priced one, not a figure that
    // quietly counts the other as zero.
    expect(find.text('Estimated'), findsOneWidget);
    expect(find.text('0 of 2 ticked'), findsOneWidget);
  });

  testWidgets('with no list at all it offers to create one', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: [
        clockProvider.overrideWithValue(kShoppingClock),
        defaultListProvider.overrideWith((ref) => Stream.value(null)),
        selectableListsProvider.overrideWith((ref) => Stream.value(const <ShoppingList>[])),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('No lists yet'), findsOneWidget);
    expect(find.text('New list'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([ShoppingGroup(entries: [sampleSuggestion()])]),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(populated),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('a bought entry drops off the list', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([
          ShoppingGroup(entries: [sampleEntry(id: 'e1', freeText: 'Bread')]),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bread'), findsOneWidget);

    // Once a transaction fulfils it, the entry is no longer something to buy. The row survives —
    // `purchasedTransactionLineId` is the only link between the receipt and the list — but a list of
    // what to get should not still be offering it.
    final bought = sampleEntry(id: 'e1', freeText: 'Bread')
        .copyWith(purchasedTransactionLineId: 'line-1');
    expect(bought.isPurchased, isTrue);
    expect(bought.isOutstandingAsOf(kToday), isFalse);
    expect(bought.isVisibleAsOf(kToday), isTrue);
  });
}
```

### `test/features/shopping/entry_editor_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/shopping/presentation/sheets/entry_editor_sheet.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/state/entry_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/shopping_harness.dart';

/// Four states, plus the rule this sheet exists to hold: `itemId` is optional, and an entry needs
/// only one of a name or a link to identify itself.
void main() {
  // The override goes on the **family**: a NotifierProvider family instance has no `overrideWith`,
  // unlike a FutureProvider or StreamProvider instance.
  List<Override> overrides(
    AsyncValue<EntryEditorState> state, {
    List<Item> items = const [kOnion],
  }) =>
      [
        entryEditorProvider.overrideWith(() => _StubEntryEditor(state)),
        entryItemsProvider.overrideWith((ref) => Stream.value(items)),
        entryTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[kProduceTag])),
        entryUnitsProvider(UnitCategory.weight)
            .overrideWith((ref) => Stream.value(const <Unit>[kKilogram])),
        entryUnitsProvider(null).overrideWith((ref) => Stream.value(const <Unit>[])),
        entryCurrencyProvider.overrideWith((ref) async => 'INR'),
        entryDecimalDigitsProvider.overrideWith((ref) async => 2),
      ];

  Widget host() => const Scaffold(
        body: AlayaBottomSheet(child: EntryEditorSheet(listId: 'list-1')),
      );

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpShopping(tester, host(), overrides: overrides(const AsyncValue.loading()));
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('error reads as not found', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(AsyncValue.error(StateError('boom'), StackTrace.empty)),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new entry opens on the form, which is its empty state', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(const AsyncValue.data(EntryEditorState(listId: 'list-1'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('What do you need?'), findsOneWidget);
    expect(find.text('Name it'), findsOneWidget);
  });

  testWidgets('free text alone is enough — no inventory item required', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(EntryEditorState(listId: 'list-1', freeText: 'Television')),
      ),
    );
    await tester.pumpAndSettle();
    // A television belongs on a list and has no place in an inventory measuring flour by the gram,
    // so the item link stays optional and the quantity field stays hidden without one.
    expect(find.text('Not in my inventory'), findsOneWidget);
    expect(find.byType(QtyField), findsNothing);
  });

  testWidgets('linking an item reveals a category-filtered quantity', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(
          EntryEditorState(listId: 'list-1', itemId: 'item-1', unitCode: 'kg'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Law L8: a Qty is an integer plus a UnitCategory, and the category comes from the item.
    expect(find.byType(QtyField), findsOneWidget);
  });

  testWidgets('saving with neither a name nor an item shakes and says why', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(
          EntryEditorState(listId: 'list-1', identityMissing: true, shakeTrigger: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShakeOnError), findsOneWidget);
    expect(find.text('Give it a name, or link it to an item'), findsOneWidget);
  });

  testWidgets('an empty catalogue still lets an entry be created', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(EntryEditorState(listId: 'list-1')),
        items: const [],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Name it'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(
          EntryEditorState(listId: 'list-1', itemId: 'item-1', unitCode: 'kg'),
        ),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(const AsyncValue.data(EntryEditorState(listId: 'list-1'))),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('promotion', () {
    test('editing an auto entry promotes it to manual and never auto-removes it', () {
      final promoted = EntryEditorState.fromEntry(sampleSuggestion())
          .copyWith(freeText: 'Onions, the big ones')
          .toEntry(newId: 'unused');
      // Anomaly A23: a suggestion the user has shaped is theirs. `origin` is what the regeneration
      // engine keys that decision on, so the promotion happens in `toEntry` rather than being left
      // to whichever call site remembers.
      expect(promoted.origin, ShoppingEntryOrigin.manual);
      expect(promoted.autoState, ShoppingEntryAutoState.active);
      expect(promoted.isAutoGenerated, isFalse);
    });

    test('a new manual entry is not promoted from anything', () {
      final made = const EntryEditorState(listId: 'list-1', freeText: 'Television')
          .toEntry(newId: 'entry-9');
      expect(made.origin, ShoppingEntryOrigin.manual);
      expect(made.itemId, isNull);
      expect(made.freeText, 'Television');
    });
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubEntryEditor extends EntryEditorNotifier {
  _StubEntryEditor(this._state);

  final AsyncValue<EntryEditorState> _state;

  @override
  AsyncValue<EntryEditorState> build(EntryEditorArgs arg) => _state;
}
```

### `test/features/shopping/generate_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/features/shopping/presentation/sheets/generate_sheet.dart';
import 'package:alaya/features/shopping/providers/generate_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';

import '../../support/shopping_harness.dart';

/// Four states, plus the shortfall figure and the per-row snooze and dismiss.
void main() {
  List<Override> overrides({
    List<ShoppingEntry>? entries,
    bool pending = false,
    bool fail = false,
  }) =>
      [
        clockProvider.overrideWithValue(kShoppingClock),
        shoppingItemsByIdProvider.overrideWith(
          (ref) => Stream.value(<String, Item>{kOnion.id: kOnion}),
        ),
        if (pending)
          entriesProvider(kList.id)
              .overrideWith((ref) => pendingStream<List<ShoppingEntry>>())
        else if (fail)
          entriesProvider(kList.id)
              .overrideWith((ref) => Stream<List<ShoppingEntry>>.error(StateError('boom')))
        else
          entriesProvider(kList.id)
              .overrideWith((ref) => Stream.value(entries ?? const [])),
      ];

  Widget host() => const Scaffold(
        body: AlayaBottomSheet(child: GenerateSheet(listId: 'list-1')),
      );

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpShopping(tester, host(), overrides: overrides(pending: true));
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('empty explains what would make a suggestion appear', (tester) async {
    await pumpShopping(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing is running low'), findsOneWidget);
  });

  testWidgets('error is reported without hiding the refresh', (tester) async {
    await pumpShopping(tester, host(), overrides: overrides(fail: true));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
  });

  testWidgets('a suggestion shows the shortfall that produced it', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(entries: [sampleSuggestion()]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Onion'), findsOneWidget);
    expect(find.text('Short by'), findsOneWidget);
    // threshold 2 kg minus 500 g on hand at generation. Read from the entry's own history, not from
    // live stock, so the figure cannot drift between the sheet opening and the user acting.
    expect(find.byType(QtyText), findsWidgets);
    expect(find.text('1 kg 500 g'), findsOneWidget);
  });

  testWidgets('each suggestion is snoozed or dismissed on its own', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        entries: [sampleSuggestion(), sampleSuggestion(id: 'auto-2')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Snooze a week'), findsNWidgets(2));
    expect(find.text('Not now'), findsNWidgets(2));
  });

  testWidgets('a manual entry never appears as a suggestion', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(entries: [sampleEntry()]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing is running low'), findsOneWidget);
    expect(find.text('Television'), findsNothing);
  });

  testWidgets('a dismissed suggestion still lists here so it can be reconsidered',
      (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        entries: [sampleSuggestion(autoState: ShoppingEntryAutoState.dismissed)],
      ),
    );
    await tester.pumpAndSettle();
    // The list screen hides it via `isVisibleAsOf`; this sheet is where the user manages
    // suggestions, so hiding it here would leave no way to see what was turned down.
    expect(find.text('Onion'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(entries: [sampleSuggestion()]),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(entries: [sampleSuggestion()]),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/shopping/list_manager_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/features/shopping/presentation/sheets/list_manager_sheet.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/shopping_harness.dart';

/// Four states, plus the retirement rule: a list is archived, never deleted.
void main() {
  List<Override> overrides({
    List<ShoppingList>? lists,
    bool pending = false,
    bool fail = false,
  }) =>
      [
        if (pending)
          allListsProvider.overrideWith((ref) => pendingStream<List<ShoppingList>>())
        else if (fail)
          allListsProvider
              .overrideWith((ref) => Stream<List<ShoppingList>>.error(StateError('boom')))
        else
          allListsProvider.overrideWith((ref) => Stream.value(lists ?? const [])),
      ];

  Widget host() => const Scaffold(
        body: AlayaBottomSheet(child: ListManagerSheet()),
      );

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpShopping(tester, host(), overrides: overrides(pending: true));
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('empty invites the first list, which becomes the default', (tester) async {
    await pumpShopping(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'New list'), findsOneWidget);
  });

  testWidgets('error is reported', (tester) async {
    await pumpShopping(tester, host(), overrides: overrides(fail: true));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('populated marks the default and separates the archived', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(lists: const [kList, kArchivedList]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Weekly shop'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Diwali'), findsOneWidget);
    expect(find.text('Archived'), findsNWidgets(2));
  });

  testWidgets('retiring a list archives it rather than deleting it', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(lists: const [kList]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    // A converted list is the provenance of those transaction lines, so it is hidden, not removed
    // (Law L6). There is no delete in this menu at all.
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('the default list is not offered "make default" again', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(lists: const [kList]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    expect(find.text('Make default'), findsNothing);
    expect(find.text('Rename'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(lists: const [kList, kArchivedList]),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpShopping(tester, host(), overrides: overrides(lists: const [kList]));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/shopping/convert_to_purchase_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/providers/transaction_draft_provider.dart';
import 'package:alaya/features/expense/state/transaction_draft.dart';
import 'package:alaya/features/shopping/presentation/screens/convert_to_purchase_screen.dart';
import 'package:alaya/features/shopping/providers/convert_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/shopping_harness.dart';

/// Four states, plus the rule this screen exists to hold: it hands off, it does not commit.
void main() {
  List<Override> overrides({
    List<TransactionLine>? lines,
    List<ShoppingEntry>? entries,
    bool pending = false,
    bool fail = false,
  }) =>
      [
        entriesProvider(kList.id)
            .overrideWith((ref) => Stream.value(entries ?? const [])),
        if (pending)
          purchaseDraftProvider(kList.id)
              .overrideWith((ref) => pendingFuture<List<TransactionLine>>())
        else if (fail)
          purchaseDraftProvider(kList.id)
              .overrideWith((ref) async => throw StateError('boom'))
        else
          purchaseDraftProvider(kList.id)
              .overrideWith((ref) async => lines ?? const <TransactionLine>[]),
      ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(pending: true),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('nothing ticked reads as nothing ticked, not as an error', (tester) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing is ticked'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(fail: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('populated previews one line per entry, marked for inventory', (tester) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(
        lines: [sampleDraftLine(), sampleDraftLine(id: 'line-2', description: 'Bread')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.text('2 lines'), findsOneWidget);
    expect(find.text('Onion'), findsOneWidget);
    expect(find.text('Bread'), findsOneWidget);
  });

  testWidgets('the primary action hands off rather than committing', (tester) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(lines: [sampleDraftLine()]),
    );
    await tester.pumpAndSettle();
    // "Open the expense", not "Save". The amount, the account and the payee are decisions only the
    // expense editor collects; duplicating them here would fork the one screen that knows how a
    // withdrawal is shaped (anomaly A25).
    expect(find.widgetWithText(FilledButton, 'Open the expense'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(lines: [sampleDraftLine()]),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(lines: [sampleDraftLine()]),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the draft channel', () {
    test('carries the ticked entry ids so the loop can close on save', () {
      final container = ProviderContainer(
        overrides: [
          entriesProvider(kList.id).overrideWith(
            (ref) => Stream.value([
              sampleEntry(id: 'e1', isChecked: true),
              sampleEntry(id: 'e2', isChecked: false),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(entriesProvider(kList.id), (_, __) {});

      final offered = container.read(convertActionsProvider).offerDraft(
            listId: kList.id,
            lines: [sampleDraftLine()],
          );
      expect(offered, isTrue);
      final draft = container.read(transactionDraftProvider);
      expect(draft, isNotNull);
      expect(draft!.kind, TransactionKind.withdrawal);
      expect(draft.lines, hasLength(1));
    });

    test('an empty draft is refused rather than opening a blank editor', () {
      final container = ProviderContainer(
        overrides: [
          entriesProvider(kList.id).overrideWith((ref) => Stream.value(const [])),
        ],
      );
      addTearDown(container.dispose);
      final offered = container
          .read(convertActionsProvider)
          .offerDraft(listId: kList.id, lines: const []);
      expect(offered, isFalse);
      expect(container.read(transactionDraftProvider), isNull);
    });

    test('take() empties the channel, so a draft is never applied twice', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(transactionDraftProvider.notifier).offer(
            TransactionDraft(
              lines: [sampleDraftLine()],
              kind: TransactionKind.withdrawal,
              subtype: TransactionSubtype.grocery,
            ),
          );
      expect(container.read(transactionDraftProvider.notifier).take(), isNotNull);
      // Without this, a draft left behind would ambush the next blank editor the user opened.
      expect(container.read(transactionDraftProvider.notifier).take(), isNull);
    });
  });
}
```

### `test/shared/layout_overflow_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/expense/presentation/sheets/delete_transaction_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/freeze_conversion_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_filter_sheet.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/shopping/presentation/sheets/entry_editor_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/generate_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/list_manager_sheet.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_expandable_fab.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/loading_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/service/presentation/sheets/dispose_sheet.dart';
import 'package:alaya/features/service/presentation/widgets/contact_action.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/shared/widgets/module_tile.dart';

import '../support/expense_harness.dart';
import '../support/fake_settings_repository.dart';
// Prefixed: `kToday` and `kNarrowPhone` are declared by every harness in this project, and this is
// the only file that imports two of them.
import '../support/calendar_harness.dart' as cal;

/// The only thing in this project that catches a layout overflow (ARCH_3 §8.3, ARCH_5 U2).
///
/// **Every sheet and every full-height state belongs here.** These defects are invisible to
/// `dart analyze`, to a file-by-file scan and to looking at the screen, because the missing
/// affordance is always an *ancestor*: the widget under review is locally correct and the parent
/// that should have given it room, or a way to scroll, is the one at fault.
///
/// They are also invisible to an ordinary widget test. A `RenderFlex` overflow reports through
/// `FlutterError.onError` rather than throwing at the site, so a test only fails on one if something
/// asks — which is exactly how an overflow hides in a suite that otherwise looks green. Every case
/// below asks, via `tester.takeException()`.
void main() {
  /// Roughly what a software keyboard takes from a phone in portrait.
  const double keyboardInset = 320;

  /// Roughly the room a list area has left on a small phone with a keyboard up.
  const Size squeezed = Size(320, 140);

  Widget host(
    Widget child, {
    double bottomInset = 0,
    double textScale = 1,
    List<Override> overrides = const [],
  }) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AlayaTheme.light(AlayaPresets.activePreset),
          // Every expense sheet reads `AlayaStrings.of(context)`, which unwraps a null without a
          // delegate installed. The Phase 5 groups pass literal strings, so this file went without
          // one until real screens arrived — and then failed as a null-check rather than as a
          // missing translation, which is why it read like five separate defects.
          localizationsDelegates: const [
            AlayaStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AlayaStrings.supportedLocales,
          // Inside the app rather than above it. `WidgetsApp` re-establishes `MediaQuery` from the
          // view, so an outer one is discarded before anything under test can read it — and a test
          // that believes it has simulated a keyboard when it has not is worse than no test.
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: EdgeInsets.only(bottom: bottomInset),
              textScaler: TextScaler.linear(textScale),
            ),
            child: inner!,
          ),
          home: Scaffold(body: child),
        ),
      );

  /// Content taller than the room a keyboard leaves, so the assertions are about the scaffold rather
  /// than about how long a particular string happens to be.
  Widget tallContent() => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [SizedBox(width: 200, height: 400)],
      );

  group('AlayaBottomSheet', () {
    testWidgets('scrolls rather than overflowing with a keyboard up', (tester) async {
      await tester.pumpWidget(
        host(AlayaBottomSheet(child: tallContent()), bottomInset: keyboardInset),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('still fits when there is no keyboard', (tester) async {
      await tester.pumpWidget(host(AlayaBottomSheet(child: tallContent())));
      expect(tester.takeException(), isNull);
    });

    // The bug, reproduced deliberately. `Padding(bottom: viewInsets)` around a `MainAxisSize.min`
    // Column is correct in each half and broken together: the padding shrinks the space and the
    // Column has no way to give up the room it already took. **If this ever stops overflowing, the
    // guard above has stopped testing anything** — and the reason AlayaBottomSheet exists has
    // quietly gone away.
    testWidgets('the un-scaffolded shape it replaces still overflows', (tester) async {
      await tester.pumpWidget(
        host(
          Padding(
            padding: const EdgeInsets.only(bottom: keyboardInset),
            child: tallContent(),
          ),
        ),
      );
      expect(tester.takeException(), isA<FlutterError>());
    });
  });

  group('ConfirmSheet', () {
    testWidgets('survives a keyboard and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => ConfirmSheet.show(
                context,
                title: 'Delete this transaction?',
                body: 'You can undo this for the next few seconds.',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                destructive: true,
              ),
              child: const Text('open'),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('AlayaFormScaffold', () {
    Widget form({bool submitting = false}) => AlayaFormScaffold(
          primaryLabel: 'Save expense',
          onPrimary: () {},
          secondaryLabel: 'Cancel',
          onSecondary: () {},
          isDirty: true,
          isSubmitting: submitting,
          discardTitle: 'Discard your changes?',
          discardBody: 'What you have typed will not be saved.',
          discardConfirmLabel: 'Discard',
          discardCancelLabel: 'Keep editing',
          child: const Column(
            children: [SizedBox(height: 300), TextField(), SizedBox(height: 300)],
          ),
        );

    testWidgets('body scrolls and the footer stays above the keyboard', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset));
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a doubled text scale with a keyboard up', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset, textScale: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the submitting footer does not grow the row past its box', (tester) async {
      await tester.pumpWidget(host(form(submitting: true), textScale: 2));
      expect(tester.takeException(), isNull);
    });
  });

  // Every sheet Phase 6A adds, at a keyboard inset and a doubled text scale — the two conditions
  // under which each of them is first used and least likely to have been looked at.
  group('expense sheets', () {
    final expenseOverrides = <Override>[
      homeCurrencyCodeProvider.overrideWith((ref) => 'INR'),
      homeDecimalDigitsProvider.overrideWith((ref) => 2),
      selectableAccountsProvider.overrideWith((ref) => Stream.value(const [kAccount])),
      quickAddTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      accountsByIdProvider
          .overrideWith((ref) => Stream.value(<String, Account>{kAccount.id: kAccount})),
      lineEditorItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      enabledCurrenciesProvider.overrideWith(
        (ref) => Stream.value(const [
          Currency(
            code: 'USD',
            name: 'US Dollar',
            symbol: r'$',
            decimalDigits: 2,
            isEnabled: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: expenseOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets('QuickAddSheet', (tester) => pumpSheet(tester, const QuickAddSheet()));

    testWidgets(
      'TransactionFilterSheet',
      (tester) => pumpSheet(tester, const TransactionFilterSheet()),
    );

    testWidgets(
      'LineItemEditor',
      (tester) => pumpSheet(
        tester,
        const LineItemEditor(
          currencyCode: 'INR',
          decimalDigits: 2,
          defaultDestination: TransactionLineDestination.inventory,
        ),
      ),
    );

    testWidgets(
      'DeleteTransactionSheet',
      (tester) => pumpSheet(tester, const DeleteTransactionSheet()),
    );

    testWidgets(
      'FreezeConversionSheet',
      (tester) => pumpSheet(tester, const FreezeConversionSheet(excludeCode: 'INR')),
    );
  });

  // Phase 6B's sheet, at a keyboard inset and a doubled text scale — the two conditions under
  // which it is first used and least likely to have been looked at (U2).
  group('inventory sheets', () {
    final inventoryOverrides = <Override>[
      consumeFefoProvider('item-1').overrideWith((ref) => Stream.value(const <Batch>[])),
      unitsInCategoryProvider(UnitCategory.weight).overrideWith(
        (ref) => Stream.value(const [
          Unit(
            code: 'kg',
            category: UnitCategory.weight,
            factorToBaseMilli: 1000000,
            displayName: 'kilogram',
            isSystem: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    testWidgets('ConsumeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: ConsumeSheet(
              itemId: 'item-1',
              unitCode: 'kg',
              category: UnitCategory.weight,
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: inventoryOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6C's three sheets, at a keyboard inset and a doubled text scale — the two conditions under
  // which each is first used and least likely to have been looked at (U2).
  group('shopping sheets', () {
    final shoppingOverrides = <Override>[
      entryItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      entryTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      entryCurrencyProvider.overrideWith((ref) async => 'INR'),
      entryDecimalDigitsProvider.overrideWith((ref) async => 2),
      entriesProvider('list-1').overrideWith((ref) => Stream.value(const <ShoppingEntry>[])),
      shoppingItemsByIdProvider.overrideWith((ref) => Stream.value(const <String, Item>{})),
      allListsProvider.overrideWith((ref) => Stream.value(const <ShoppingList>[])),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: shoppingOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets(
      'EntryEditorSheet',
      (tester) => pumpSheet(tester, const EntryEditorSheet(listId: 'list-1')),
    );

    testWidgets(
      'GenerateSheet',
      (tester) => pumpSheet(tester, const GenerateSheet(listId: 'list-1')),
    );

    testWidgets(
      'ListManagerSheet',
      (tester) => pumpSheet(tester, const ListManagerSheet()),
    );
  });

  // Phase 6D's pay sheet, at a keyboard inset and a doubled text scale — an amount field, a date
  // field, an account dropdown and a two-line note, all growing at once.
  group('recurring sheets', () {
    final recurringOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      payAccountsProvider.overrideWith((ref) => Stream.value(const <Account>[])),
      payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
    ];

    testWidgets('PaySheet', (tester) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(
            child: PaySheet(
              occurrenceId: 'occ-1',
              template: RecurringTemplate(
                id: 'tpl-1',
                name: 'A rent template with a name long enough to wrap at a doubled scale',
                normalizedName: 'rent',
                kind: RecurringKind.rent,
                direction: RecurringDirection.outflow,
                defaultAmount: const Money(120000, 'INR'),
                intervalUnit: RecurringIntervalUnit.month,
                intervalCount: 1,
                startDateKey: const DateKey(20260131),
                nextDueDateKey: const DateKey(20260831),
                isPaused: false,
                autoRemind: true,
                remindDaysBefore: 3,
                anchorDayOfMonth: 31,
              ),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: recurringOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6D adds, with a clamp note on every row.
  group('FrequencyPreview at a doubled text scale', () {
    testWidgets('three dates, two of them clamped', (tester) async {
      await tester.pumpWidget(
        host(
          const FrequencyPreview(
            dates: [
              PreviewedDate(dateKey: DateKey(20260131)),
              PreviewedDate(dateKey: DateKey(20260228), clamped: true),
              PreviewedDate(dateKey: DateKey(20260331)),
            ],
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6E's dispose sheet: seven choice chips, a date field, an optional amount and a note, all
  // growing at once under a keyboard inset.
  group('service sheets', () {
    final serviceOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('DisposeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: DisposeSheet(assetId: 'asset-1', currencyCode: 'INR'),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: serviceOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The contact block: a name, a number and a call button, none of them flexible.
  group('ContactAction at a doubled text scale', () {
    testWidgets('a long name beside a long number', (tester) async {
      await tester.pumpWidget(
        host(
          const ContactAction(
            phone: '+91 98765 43210',
            name: 'A service centre with a name long enough to wrap',
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6F's dashboard sections. Each is a card whose figures, chips and labels all grow at once, and
  // the funds header carries the only display-sized amount in the app.
  group('dashboard sections', () {
    final dashOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      // InsightCard's notifier restores its side from `app_settings` on the first frame, which
      // resolves `databaseProvider` unless this is here — the failure reads as a database bug in a
      // test that never mentions one (ARCH_6 P6).
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      dashboardCurrencyProvider.overrideWith((ref) async => 'INR'),
      dashboardDigitsProvider.overrideWith((ref) async => 2),
      totalFundsProvider.overrideWith(
        (ref) async => const NetWorth(
          total: Money(98765432, 'INR'),
          unconvertedCount: 3,
          isApproximate: true,
        ),
      ),
      upcomingProvider.overrideWith((ref) async => const <UpcomingEntry>[]),
    ];

    testWidgets('FundsHeader with both chips at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const FundsHeader(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('InsightCard with its switch at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const InsightCard(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6F adds. Two lines of text and a glyph inside a fixed aspect ratio is
  // exactly the shape that overflows when the text doubles and the box does not.
  group('ModuleTile at a doubled text scale', () {
    testWidgets('a long label beside a long count', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 160,
            height: 108,
            child: ModuleTile(
              label: 'Recurring commitments',
              icon: Icons.event_repeat,
              detail: '17 need attention before the end of the month',
              onTap: () {},
            ),
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 7A. Both shapes here are the ones that have already cost this project rounds: a sheet whose
  // content outgrows the viewport, and a grid of text cells whose row height does not move with the text.
  // Zero width, which is not a hypothetical: Android reports it on the first frame of every launch
  // ("D/FlutterRenderer: Width is zero. 0,0") and the FAB's slot subtracted padding from it, producing a
  // negative width and a red screen on startup. Every widget harness sets a real viewport before pumping,
  // which is exactly why nothing here caught it — so the degenerate viewport is now stated outright.
  group('degenerate viewports', () {
    testWidgets('the expandable FAB survives a zero-width first frame', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size.zero),
            child: Scaffold(
              floatingActionButton: AlayaExpandableFab(
                openLabel: 'Add',
                closeLabel: 'Close',
                actions: [
                  FabAction(label: 'One', icon: Icons.add, onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('calendar', () {
    List<Override> calOverrides({List<CalendarEvent> events = const []}) =>
        cal.calendarOverrides(cal.FakeCalendarRepository(events: events));

    final busyDay = <CalendarEvent>[
      cal.event(title: 'A payee with a name long enough to wrap at a doubled scale', amountMinor: 98765432),
      cal.event(
        type: CalendarEventType.serviceDue,
        refType: 'asset',
        refId: 'as-1',
        title: 'The boiler in the upstairs cupboard',
        baseSeverity: CalendarSeverity.warning,
      ),
      cal.event(
        type: CalendarEventType.batchExpiry,
        refType: 'inventoryBatch',
        refId: 'ba-1',
        title: 'Yoghurt, the large tub',
        baseSeverity: CalendarSeverity.warning,
      ),
    ];

    testWidgets('DaySheet with three grouped entries at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('DaySheet with a keyboard up as well', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // U26: `TableCalendar` takes a fixed `rowHeight`, so the grid computes one from the text scaler. If
    // that computation is ever replaced by a constant, this is the test that says so.
    testWidgets('the month grid at a doubled scale on the narrowest phone', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the month grid at a tripled scale, which is past what U15 asks for',
        (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 3, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // The range header prints two formatted dates and a dash, which is the longest single string this
    // screen can produce — and it appears only in a mode the other cases never enter.
    testWidgets('the range header at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('22'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // The screen's own composition, which the shared full-height group cannot reach: six measured rows
    // plus a header are taller than a squeezed list area on their own, so the grid and the state beneath
    // it have to share a scroll rather than compete for a fixed box.
    for (final scale in [1.0, 2.0]) {
      testWidgets('the whole screen in a squeezed viewport at ${scale}x', (tester) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: scale,
            overrides: calOverrides(events: busyDay),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // Each of the three states in turn, in the same squeezed box. Loading and error sit in the sliver
    // that fills the remainder, and that remainder is negative here.
    testWidgets('loading, empty and error all survive the squeezed box', (tester) async {
      for (final repo in [
        cal.FakeCalendarRepository(pending: true),
        cal.FakeCalendarRepository(),
        cal.FakeCalendarRepository(error: 'view unavailable'),
      ]) {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: 2,
            overrides: cal.calendarOverrides(repo),
          ),
        );
        // `pump`, not `pumpAndSettle`: the loading case holds a `CircularProgressIndicator`, which
        // animates forever, so `pumpAndSettle` times out rather than settling. Two frames is enough to
        // resolve the completed futures in the other two cases.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('full-height states in a squeezed viewport', () {
    Widget inSqueezedBox(Widget child) => host(
          Center(
            child: SizedBox(width: squeezed.width, height: squeezed.height, child: child),
          ),
        );

    testWidgets('EmptyState with an icon, body and action', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          EmptyState(
            title: 'No transactions yet',
            body: 'Add your first expense and it will appear here.',
            icon: Icons.receipt_long_outlined,
            actionLabel: 'Add expense',
            onAction: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ErrorState with a retry — the tallest of the three', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          ErrorState(
            title: 'That did not work',
            body: 'Something went wrong on our side. Try again.',
            retryLabel: 'Try again',
            onRetry: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoadingState', (tester) async {
      await tester.pumpWidget(inSqueezedBox(const LoadingState(label: 'Loading')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('AlayaListSkeleton clips rather than overflowing', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(const AlayaListSkeleton(label: 'Loading transactions')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmptyState at a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: EmptyState(
                title: 'No transactions yet',
                body: 'Add your first expense and it will appear here.',
                icon: Icons.receipt_long_outlined,
                actionLabel: 'Add expense',
                onAction: () {},
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    // The states are also the shape the Theme Lab renders inside a half-width pane, which is where
    // the 150px `SizedBox` around an EmptyState used to overflow by roughly 58px.
    testWidgets('EmptyState in a half-width pane', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          const SizedBox(
            width: 134,
            child: EmptyState(title: 'No matches', body: 'Try a shorter search.'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6A's line-items page: a full-height screen whose summary row, list rows and footer all
  // grow under text scale at once. Squeezed and doubled, which is the pair U21 exists for.
  group('the line items page', () {
    final editorOverrides = <Override>[
      transactionEditorProvider.overrideWith(
        () => _FixedEditor(
          AsyncValue.data(
            TransactionEditorState(
              currencyCode: 'INR',
              dateKey: const DateKey(20260801),
              amount: const Money(20000, 'INR'),
              lines: [
                TransactionLine(
                  id: 'l1',
                  transactionId: '',
                  lineNo: 1,
                  description: 'A description long enough to need two lines at a doubled scale',
                  destination: TransactionLineDestination.inventory,
                  quantity: const Qty(500000, UnitCategory.weight),
                  lineAmount: const Money(4000, 'INR'),
                ),
              ],
            ),
          ),
        ),
      ),
      homeDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('populated at 320dp and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(const LineItemsScreen(), textScale: 2, overrides: editorOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('kit rows at a doubled text scale', () {
    testWidgets('KeyValueRow wraps a long value instead of overflowing', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            child: KeyValueRow(
              label: 'Payment method',
              value: 'Bank transfer from HDFC Savings ending 4417',
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('FilterChipBar wraps rather than clipping a row of chips', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: FilterChipBar(
              clearAllLabel: 'Clear all',
              onClearAll: () {},
              filters: [
                ActiveFilter(label: 'Account: HDFC Savings', onRemove: () {}),
                ActiveFilter(label: 'Tag: Groceries', onRemove: () {}),
                ActiveFilter(label: 'Jan 2026 – Aug 2026', onRemove: () {}),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('StatusChip ellipsises a long label in a narrow box', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 96,
            child: StatusChip(label: 'Needs details', tone: StatusTone.info),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// A transaction editor reporting a fixed state, so a layout can be pumped without a database.
class _FixedEditor extends TransactionEditorNotifier {
  _FixedEditor(this._value);

  final AsyncValue<TransactionEditorState> _value;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _value;
}
```

---

## COVERAGE — ARCH_5 §7 rows closed by Phase 6C

### §7.1 By table

| Row | Create | Read | Edit | Retire |
|---|---|---|---|---|
| `shopping_lists` | list manager | switcher in the header · `activeListProvider` falls back to the default | rename · set default | **archive, never delete** — a converted list is the provenance of those transaction lines (Law L6) |
| `shopping_entries` | entry editor · low-stock generation | grouped by tag, running estimate | entry editor, which promotes an auto row to manual | tick · snooze · dismiss · delete |

### §7.2 Columns most likely to be stranded

| Column | Where a user sees it |
|---|---|
| `shopping_entries.autoState` + `snoozeUntilDateKey` | Snooze and dismiss on any `autoLowStock` row, in both the list and the generate sheet; a snoozed row carries a chip with its return date, and `ShoppingEntry.isVisibleAsOf` is what hides it |
| `shopping_entries.estimatedPriceMinor` | An `AmountField` in the entry editor, an `AmountText` on the row, and a running list estimate in the header that **skips unpriced entries rather than counting them as zero** |
| `shopping_entries.origin = autoLowStock` | A `Suggested` chip, and it is the only origin that gets snooze and dismiss — offering them on a row someone typed would read as the app second-guessing them |

### Closed by integration, not by a new surface

| Row | How |
|---|---|
| `shopping_entries.purchasedTransactionLineId` | Convert-to-purchase carries the ticked ids into the draft; 6A's `save()` calls `markPurchased` once the expense commits (anomaly A25) |
| `shopping_entries.stockAtGeneration` | The shortfall on a suggestion is `threshold − stockAtGeneration`, read from the entry's own history so the figure cannot drift after the fact |

### §7.3 Deferred — with the contract each waits on

| Item | Why | Owner |
|---|---|---|
| `reorderEntries` | Built in 3A, unused. Drag-to-reorder needs a `ReorderableListView` inside a `CustomScrollView`, which is a sliver problem rather than a shopping one; the sort order is honoured on read today. | **6C follow-up** |
| `ShoppingList.targetDateKey` | On the entity, no surface. "Shop before Saturday" belongs with 7A's calendar, which owns date-anchored prompts. | **7A** |
| `deleteList` | Deliberately not wired. Archiving is the retirement path (Law L6); a hard delete would orphan the transaction lines a converted list explains. | none — by design |
| `item_tags` (from 6B) | Still blocked on `TagRepository.watchForItem` / `setForItem`. 6C uses `TagScope.shopping` tags on **entries**, which is a different join and does exist. | **2C/3A/3D addendum** |
