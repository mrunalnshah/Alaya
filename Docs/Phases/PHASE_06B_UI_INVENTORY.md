# PHASE 6B — The Inventory module UI

> **Regenerated 2026-08-02 from the canonical tree.** Every fix through the Phase 6C debugging
> pass is folded in; this document and the working tree are in sync, and regenerating from it
> reproduces the code that runs. Earlier revisions reintroduce defects listed in ARCH_6 §3.
>
> Files shared with other phase documents — `app_en.arb`, `routes.dart`, `app_router.dart`,
> `layout_overflow_test.dart`, and the Phase 6A editor files amended by 6B and 6C — carry
> **identical** content in every copy, so they may be applied in any order.


Two parts. **Part 0 repairs the expense-to-inventory path**, which was broken: a grocery line marked
for inventory produced no batch unless a catalogued `Item` already existed, and
`PurchaseFanOutService._planBatch` refuses a line without `itemId`. On a fresh install there was no
way to create an Item while itemising a receipt — the payee picker had inline creation, the item
picker did not — so the transaction saved, the snack said "Saved", and nothing ever reached the
inventory. The refusal was also swallowed, so nothing on screen explained it.

Part 0 files belong to Phase 6A and supersede their versions there. Part 1 is the Inventory module.

Apply in the order listed. `app_en.arb`, `routes.dart` and `app_router.dart` supersede their
Phase 6A versions; every other Part 1 file is new.

```
flutter gen-l10n
flutter analyze
flutter test
flutter test --update-goldens   # AlayaTimeline only
```

No new packages. Every import resolves against Phases 1A–6A.

---

## Part 0 — the expense-to-inventory path

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

### `lib/features/expense/presentation/screens/transaction_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/bill_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/deposit_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/electronics_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/grocery_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/household_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/other_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/transfer_form.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/account_picker.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// The full transaction editor (ARCH_5 §3 archetype B).
///
/// Routed **outside** the drawer shell, and led by a close button rather than a back arrow: an
/// editor is a task, and ✕ says "abandon" where ← says "go up". Both route through
/// `AlayaFormScaffold`'s unsaved-changes guard (Law U10).
///
/// **Sections group by decision, not by table.** "What and how much" precedes "where it came from",
/// and the sub-form that appears depends on the subtype — never a screen listing every column the
/// `transactions` row happens to have.
class TransactionEditorScreen extends ConsumerWidget {
  /// Edits [transactionId], or creates a new transaction when it is null.
  const TransactionEditorScreen({this.transactionId, super.key});

  /// The transaction being edited, or null for a new one.
  final String? transactionId;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(transactionEditorProvider(transactionId).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      // The reason, not a stand-in for it (U9).
      final why = ref.read(transactionEditorProvider(transactionId)).valueOrNull?.saveError;
      showFailureSnack(context, message: why ?? strings.errorBodyGeneric);
      return;
    }
    final after = ref.read(transactionEditorProvider(transactionId)).valueOrNull;
    final fanOutError = after?.fanOutError;
    // A line that asked to become recurring replaces this screen with the builder rather than popping,
    // so the draft it just offered is picked up on the next frame instead of going nowhere.
    // An asset the fan-out just created opens for the type and the warranty a receipt could not carry.
    // Checked before the recurring hand-off because a line cannot be both.
    final createdAsset = after?.createdAssetId;
    if (createdAsset != null) {
      // **The router is captured before the pop, not looked up inside the action.**
      //
      // A snack outlives the screen that showed it, so by the time the user taps its action this
      // `context` is a deactivated element — and `context.push` walks the ancestor tree to find the
      // router, which throws *"Looking up a deactivated widget's ancestor is unsafe"*. The `GoRouter`
      // itself survives the pop; holding a reference to it is what makes the action safe.
      //
      // The messenger is captured for the same reason: `ScaffoldMessenger.of` would fail too.
      final router = GoRouter.of(context);
      final target = Routes.assetEdit(createdAsset);
      if (context.canPop()) context.pop();
      if (!context.mounted) return;
      showResultSnack(
        context,
        message: strings.assetCreatedFromPurchase,
        actionLabel: strings.actionSetWarranty,
        onAction: () => router.push(target),
      );
      return;
    }
    if (after?.wantsTemplate ?? false) {
      context.pushReplacement(Routes.recurringNew);
      if (!context.mounted) return;
      showResultSnack(context, message: strings.recurringScheduleNext);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    // A half-succeeded write says which half. The transaction is saved either way; what failed is the
    // stock or asset a line asked for, and saying nothing is how a receipt silently fails to reach
    // the inventory (U9).
    fanOutError != null
        ? showFailureSnack(context, message: fanOutError)
        : showResultSnack(context, message: strings.actionSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(transactionEditorProvider(transactionId));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(
          transactionId == null ? strings.editorTitleNew : strings.editorTitleEdit,
        ),
      ),
      body: async.when(
        loading: () => AlayaListSkeleton(label: strings.loadingLabel, hasLeading: false),
        // "It may have been deleted" only when it actually is. Anything else is a load failure and
        // says so, with a retry — reporting both the same way is what made four different bugs
        // arrive as one indistinguishable symptom.
        error: (error, stack) => error is TransactionNotFound
            ? ErrorState(
                title: strings.errorTitleNotFound,
                body: strings.errorBodyNotFound,
              )
            : ErrorState(
                title: strings.errorTitleGeneric,
                body: error.toString(),
                retryLabel: strings.actionRetry,
                onRetry: () => ref.invalidate(transactionEditorProvider(transactionId)),
              ),
        data: (state) => AlayaFormScaffold(
          primaryLabel: _saveLabel(strings, state.kind),
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: _Form(editorId: transactionId, state: state),
        ),
      ),
    );
  }

  static String _saveLabel(AlayaStrings strings, TransactionKind kind) => switch (kind) {
        TransactionKind.deposit => strings.saveIncome,
        TransactionKind.transfer => strings.saveTransfer,
        TransactionKind.withdrawal => strings.saveExpense,
        TransactionKind.adjustmentIncrease => strings.saveIncome,
        TransactionKind.adjustmentDecrease => strings.saveExpense,
      };
}

class _Form extends ConsumerWidget {
  const _Form({required this.editorId, required this.state});

  final String? editorId;
  final TransactionEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts = ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[];
    final methods = ref.watch(editorPaymentMethodsProvider).valueOrNull ?? const <PaymentMethod>[];
    final tags = ref.watch(editorTagsProvider(state.kind)).valueOrNull ?? const <Tag>[];
    final localeTag = Localizations.localeOf(context).toString();

    Account? accountFor(String? id) {
      for (final account in accounts) {
        if (account.id == id) return account;
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<TransactionKind>(
          segments: [
            ButtonSegment(
              value: TransactionKind.withdrawal,
              label: Text(strings.kindWithdrawal),
            ),
            ButtonSegment(
              value: TransactionKind.deposit,
              label: Text(strings.kindDeposit),
            ),
            ButtonSegment(
              value: TransactionKind.transfer,
              label: Text(strings.kindTransfer),
            ),
          ],
          selected: {state.kind},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => notifier.setKind(selection.first),
        ),
        SectionHeader(
          label: strings.sectionWhatAndHowMuch,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: AmountField(
            currencyCode: state.currencyCode,
            decimalDigits: digits,
            label: strings.labelAmount,
            initialValue: state.amount,
            errorText: state.amountMissing ? strings.errorAmountInvalid : null,
            onChanged: notifier.setAmount,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.dateKey,
          label: strings.labelDate,
          formatted: (date) => DateFormat.yMMMd(localeTag).format(date.toUtcMidnight()),
          onChanged: notifier.setDate,
        ),
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<TransactionSubtype>(
          key: ValueKey(state.subtype),
          initialValue: state.subtype,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelSubtype),
          items: [
            for (final subtype in state.availableSubtypes)
              DropdownMenuItem(
                value: subtype,
                child: Text(TransactionRow.subtypeLabel(strings, subtype)),
              ),
          ],
          onChanged: (value) => value == null ? null : notifier.setSubtype(value),
        ),
        if (state.kind != TransactionKind.transfer) ...[
          SectionHeader(
            label: state.kind == TransactionKind.deposit
                ? strings.sectionWhereItCameFrom
                : strings.sectionWhereItWent,
            padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
          ),
          if (state.kind != TransactionKind.deposit)
            AccountPicker(
              accounts: accounts,
              selected: accountFor(state.fromAccountId),
              label: strings.labelAccount,
              hint: strings.hintSelectAccount,
              onChanged: (account) => notifier.setFromAccount(account.id),
            ),
          const SizedBox(height: AlayaSpacing.md),
          DropdownButtonFormField<String>(
            key: ValueKey(state.paymentMethodId),
            initialValue: state.paymentMethodId,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.labelPaymentMethod),
            items: [
              for (final method in methods)
                DropdownMenuItem(value: method.id, child: Text(method.name)),
            ],
            onChanged: notifier.setPaymentMethod,
          ),
          const SizedBox(height: AlayaSpacing.md),
        ],
        _SubtypeForm(editorId: editorId, state: state, decimalDigits: digits),
        if (tags.isNotEmpty) ...[
          SectionHeader(
            label: strings.labelTags,
            padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
          ),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              for (final tag in tags)
                TagChip(
                  tag: tag,
                  selected: state.tagIds.contains(tag.id),
                  onTap: () => notifier.toggleTag(tag.id),
                ),
            ],
          ),
        ],
        SectionHeader(
          label: strings.labelNote,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        TextFormField(
          initialValue: state.note,
          maxLines: 3,
          decoration: InputDecoration(hintText: strings.hintNote),
          onChanged: notifier.setNote,
        ),
      ],
    );
  }
}

class _SubtypeForm extends StatelessWidget {
  const _SubtypeForm({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
  });

  final String? editorId;
  final TransactionEditorState state;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    if (state.kind == TransactionKind.transfer ||
        state.subtype == TransactionSubtype.transferOut) {
      return TransferForm(editorId: editorId, state: state);
    }
    return switch (state.subtype) {
      TransactionSubtype.grocery => GroceryForm(
          editorId: editorId,
          state: state,
          decimalDigits: decimalDigits,
        ),
      TransactionSubtype.household => HouseholdForm(
          editorId: editorId,
          state: state,
          decimalDigits: decimalDigits,
        ),
      TransactionSubtype.electronics => ElectronicsForm(
          editorId: editorId,
          state: state,
          decimalDigits: decimalDigits,
        ),
      TransactionSubtype.bill => BillForm(editorId: editorId, state: state),
      TransactionSubtype.salaryIn ||
      TransactionSubtype.otherIn =>
        DepositForm(editorId: editorId, state: state),
      TransactionSubtype.transferSelf ||
      TransactionSubtype.transferOut =>
        TransferForm(editorId: editorId, state: state),
      TransactionSubtype.otherOut => OtherForm(
          editorId: editorId,
          state: state,
          decimalDigits: decimalDigits,
        ),
    };
  }
}
```

### `lib/features/expense/presentation/sheets/line_item_editor.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/qty_field.dart';

/// Items the line editor can attach a quantity to.
final lineEditorItemsProvider = StreamProvider.autoDispose<List<Item>>(
  (ref) => ref.watch(itemRepositoryProvider).watchAll(),
);

/// Units in the category of the currently chosen item.
final lineEditorUnitsProvider =
    StreamProvider.autoDispose.family<List<Unit>, UnitCategory?>(
  (ref, category) => category == null
      ? Stream.value(const <Unit>[])
      : ref.watch(unitRepositoryProvider).watchByCategory(category),
);

/// What [LineItemEditor] hands back: the line, and whether another should open straight away.
class LineItemDraft {
  /// Creates a result.
  const LineItemDraft({required this.line, this.addAnother = false});

  /// The line the user built.
  final TransactionLine line;

  /// Whether to reopen the editor blank once this one is stored.
  ///
  /// A grocery receipt is fifteen lines, and closing the sheet between each one made itemising an
  /// expense feel like fifteen separate tasks. The caller loops while this is true.
  final bool addAnother;
}

/// Edits one line of a transaction (ARCH_5 §3 archetype A).
///
/// **An Item can be created here, and that is what makes the receipt reach the inventory at all.**
/// `PurchaseFanOutService._planBatch` refuses a line without `itemId`, so without an inline create a
/// user on a fresh install itemises a grocery receipt, saves it, and nothing ever appears in the
/// inventory — the batch was never planned. The catalogue is discovered while typing the receipt,
/// exactly as a payee is.
///
/// **Quantity is offered only once an Item is chosen, and that is the schema talking rather than a
/// simplification.** A `Qty` is an integer plus a `UnitCategory`, and the category comes from the
/// Item — it is immutable per Item and cross-category conversion does not exist (Law L8). A free-text
/// line has no category, so a quantity on it would be a number whose meaning nothing records. It is
/// also exactly what the fan-out requires: `_planBatch` refuses a line without a catalogued item,
/// because a batch with a guessed quantity is stock the user never bought.
class LineItemEditor extends ConsumerStatefulWidget {
  /// Edits [line], or creates a new one when it is null.
  const LineItemEditor({
    required this.currencyCode,
    required this.decimalDigits,
    required this.defaultDestination,
    this.line,
    super.key,
  });

  /// The transaction's currency. A line cannot be denominated in another.
  final String currencyCode;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  /// What a new line should default to — inventory for a grocery or household purchase.
  final TransactionLineDestination defaultDestination;

  /// The line being edited, or null for a new one.
  final TransactionLine? line;

  /// Opens the sheet, resolving to the edited line or null.
  static Future<LineItemDraft?> show(
    BuildContext context, {
    required String currencyCode,
    required int decimalDigits,
    required TransactionLineDestination defaultDestination,
    TransactionLine? line,
  }) =>
      AlayaBottomSheet.show<LineItemDraft>(
        context: context,
        builder: (context) => LineItemEditor(
          currencyCode: currencyCode,
          decimalDigits: decimalDigits,
          defaultDestination: defaultDestination,
          line: line,
        ),
      );

  @override
  ConsumerState<LineItemEditor> createState() => _LineItemEditorState();
}

class _LineItemEditorState extends ConsumerState<LineItemEditor> {
  late final TextEditingController _description =
      TextEditingController(text: widget.line?.description ?? '');
  late TransactionLineDestination _destination =
      widget.line?.destination ?? widget.defaultDestination;
  late String? _itemId = widget.line?.itemId;
  late Qty? _quantity = widget.line?.quantity;
  /// The unit code the quantity is entered in.
  ///
  /// **Held as a code, seeded from the saved line.** `QtyField` formats its initial text against the
  /// `selectedUnit` it is handed, so a null here fell back to `units.first` — milligram — and a line
  /// saved as `50 kg` reopened as `50000000 mg`. The units list arrives asynchronously, so the code is
  /// what persists and the `Unit` is resolved from it on each build.
  late String? _unitCode = widget.line?.unitCode;
  late Money? _unitPrice = widget.line?.unitPrice;
  late Money? _lineAmount = widget.line?.lineAmount;
  bool _descriptionMissing = false;
  bool _creatingItem = false;
  UnitCategory _newItemCategory = UnitCategory.count;
  bool _createFailed = false;

  Future<void> _createItem() async {
    final name = _description.text.trim();
    if (name.isEmpty) {
      setState(() => _descriptionMissing = true);
      return;
    }
    final item = Item(
      id: ref.read(uidGeneratorProvider).generate(),
      name: name,
      normalizedName: ref.read(normalizerProvider).normalize(name),
      unitCategory: _newItemCategory,
      defaultDisplayUnitCode: _newItemCategory.baseUnitCode,
      itemKind: ItemKind.generic,
      isFavorite: false,
    );
    final saved = await ref.read(itemRepositoryProvider).save(item);
    if (!mounted) return;
    final value = saved.valueOrNull;
    setState(() {
      _createFailed = value == null;
      if (value == null) return;
      _itemId = value.id;
      _creatingItem = false;
      _unitCode = value.defaultDisplayUnitCode;
      _quantity = null;
    });
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  void _submit({bool addAnother = false}) {
    final description = _description.text.trim();
    if (description.isEmpty) {
      setState(() => _descriptionMissing = true);
      return;
    }
    final existing = widget.line;
    final line = TransactionLine(
      id: existing?.id ?? ref.read(uidGeneratorProvider).generate(),
      transactionId: existing?.transactionId ?? '',
      lineNo: existing?.lineNo ?? 1,
      description: description,
      destination: _destination,
      itemId: _itemId,
      quantity: _quantity,
      unitCode: _unitCode ?? existing?.unitCode,
      unitPrice: _unitPrice,
      lineAmount: _lineAmount,
      createdBatchId: existing?.createdBatchId,
      createdAssetId: existing?.createdAssetId,
      createdRecurringTemplateId: existing?.createdRecurringTemplateId,
      note: existing?.note,
    );
    Navigator.of(context).pop(LineItemDraft(line: line, addAnother: addAnother));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final items = ref.watch(lineEditorItemsProvider).valueOrNull ?? const <Item>[];
    Item? selectedItem;
    for (final item in items) {
      if (item.id == _itemId) {
        selectedItem = item;
        break;
      }
    }
    final units =
        ref.watch(lineEditorUnitsProvider(selectedItem?.unitCategory)).valueOrNull ??
            const <Unit>[];
    Unit? selectedUnit;
    for (final unit in units) {
      if (unit.code == _unitCode) selectedUnit = unit;
    }
    // Prefer the item's own display unit over the first in the list: a catalogue entry measured in
    // kilograms should not open in milligrams just because that sorts first.
    if (selectedUnit == null) {
      for (final unit in units) {
        if (unit.code == selectedItem?.defaultDisplayUnitCode) selectedUnit = unit;
      }
    }
    selectedUnit ??= units.isEmpty ? null : units.first;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.lineDescription,
          style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _description,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: strings.lineDescription,
            errorText: _descriptionMissing ? strings.errorFieldRequired : null,
          ),
          onChanged: (_) {
            if (_descriptionMissing) setState(() => _descriptionMissing = false);
          },
        ),
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<TransactionLineDestination>(
          key: ValueKey(_destination),
          initialValue: _destination,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelCategory),
          items: [
            for (final destination in TransactionLineDestination.values)
              DropdownMenuItem(
                value: destination,
                child: Text(_destinationLabel(strings, destination)),
              ),
          ],
          onChanged: (value) =>
              value == null
                  ? null
                  : setState(() {
                      _destination = value;
                      // Cleared with the fields: a stale item link on an asset line would reach
                      // `_planBatch` and be refused, for a quantity the user was never shown.
                      if (value != TransactionLineDestination.inventory) {
                        _itemId = null;
                        _quantity = null;
                        _unitCode = null;
                        _creatingItem = false;
                      }
                    }),
        ),
        // **The label alone never said which was which.** "Add to inventory" and "Add to services"
        // are indistinguishable to anyone who has not read the schema, so an iPhone went to inventory,
        // was refused for want of a quantity, and appeared in neither place. The helper names a real
        // example of each: consumed versus kept is the whole distinction.
        Padding(
          padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
          child: Text(
            _destinationHelp(strings, _destination),
            style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // **Only inventory needs an item, a quantity and a unit.** A television has no grams and a
        // recurring line has no stock; offering the fields anyway invited an iPhone to be filed as
        // measured stock, which `_planBatch` then refused for want of a quantity. The whole block is
        // gated on the destination rather than each field being individually pointless.
        if (_destination == TransactionLineDestination.inventory) ...[
          if (_creatingItem)
            _NewItemRow(
              category: _newItemCategory,
              onCategoryChanged: (category) =>
                  setState(() => _newItemCategory = category),
              onCreate: _createItem,
              onCancel: () => setState(() => _creatingItem = false),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: items.isEmpty
                      ? Text(
                          strings.itemCreateHint,
                          style: AlayaTypography.caption
                              .copyWith(color: context.semantic.muted),
                        )
                      : DropdownButtonFormField<String>(
              // **`selectedItem?.id`, not `_itemId`.** The items arrive from a stream, so on the frame
              // right after an inline create the state already names the new item while the list has
              // not re-emitted it — and a dropdown holding a value none of its items carry throws
              // "There should be exactly one item", which is a red screen. Deriving the value from the
              // list being rendered makes the mismatch unrepresentable.
              key: ValueKey(selectedItem?.id),
              initialValue: selectedItem?.id,
              isExpanded: true,
              decoration: InputDecoration(labelText: strings.labelItem),
              items: [
                for (final item in items)
                  DropdownMenuItem(
                    value: item.id,
                    child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() {
                // **Picking an item fills the description.** The two are different columns — the
                // description is what the receipt said, `itemId` is what it stocks — but the receipt
                // almost always says the item's name, and making the user retype "onion" after
                // choosing Onion is friction with no purpose. An edit of their own is never
                // overwritten: the fill only happens while the field is empty or still holds the
                // previously-picked item's name.
                final previous = _nameOf(items, _itemId);
                _itemId = value;
                final picked = _nameOf(items, value);
                final typed = _description.text.trim();
                if (picked != null && (typed.isEmpty || typed == previous)) {
                  _description.text = picked;
                  _descriptionMissing = false;
                }
                // The category changed, so any unit and quantity chosen against the old one is now
                // meaningless rather than merely stale — Law L8 has no cross-category conversion.
                _unitCode = null;
                _quantity = null;
              }),
            ),
                ),
                const SizedBox(width: AlayaSpacing.xs),
                TextButton(
                  onPressed: () => setState(() => _creatingItem = true),
                  child: Text(strings.itemCreate),
                ),
              ],
            ),
          if (_createFailed) ...[
            const SizedBox(height: AlayaSpacing.xxs),
            Text(
              strings.errorBodyGeneric,
              style: AlayaTypography.caption.copyWith(color: context.semantic.danger),
            ),
          ],
          if (selectedItem != null && units.isNotEmpty && selectedUnit != null) ...[
            const SizedBox(height: AlayaSpacing.md),
            QtyField(
              key: ValueKey('${selectedItem.id}:${selectedUnit.code}'),
              category: selectedItem.unitCategory,
              units: units,
              selectedUnit: selectedUnit,
              label: strings.labelQuantity,
              unitLabel: strings.labelUnit,
              initialValue: _quantity,
              onChanged: (quantity) => _quantity = quantity,
              onUnitChanged: (unit) => setState(() => _unitCode = unit.code),
            ),
          ],
        ],
        const SizedBox(height: AlayaSpacing.md),
        AmountField(
          currencyCode: widget.currencyCode,
          decimalDigits: widget.decimalDigits,
          label: strings.lineUnitPrice,
          initialValue: _unitPrice,
          onChanged: (value) => _unitPrice = value,
        ),
        const SizedBox(height: AlayaSpacing.md),
        AmountField(
          currencyCode: widget.currencyCode,
          decimalDigits: widget.decimalDigits,
          label: strings.lineAmount,
          initialValue: _lineAmount,
          onChanged: (value) => _lineAmount = value,
        ),
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(onPressed: _submit, child: Text(strings.actionDone)),
        const SizedBox(height: AlayaSpacing.xs),
        // The bulk path. Itemising a receipt should not mean opening and closing this sheet once per
        // line, so this commits and reopens blank; the caller keeps looping while it is asked to.
        TextButton.icon(
          onPressed: () => _submit(addAnother: true),
          icon: const Icon(Icons.add, size: AlayaIconSize.sm),
          label: Text(strings.lineItemsSaveAndAnother),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionCancel),
        ),
      ],
    );
  }

  static String? _nameOf(List<Item> items, String? id) {
    if (id == null) return null;
    for (final item in items) {
      if (item.id == id) return item.name;
    }
    return null;
  }

  static String _categoryLabel(AlayaStrings strings, UnitCategory category) =>
      switch (category) {
        UnitCategory.weight => strings.unitCategoryWeight,
        UnitCategory.volume => strings.unitCategoryVolume,
        UnitCategory.count => strings.unitCategoryCount,
      };

  static String _destinationLabel(
    AlayaStrings strings,
    TransactionLineDestination destination,
  ) =>
      switch (destination) {
        TransactionLineDestination.none => strings.destinationNone,
        TransactionLineDestination.inventory => strings.destinationInventory,
        TransactionLineDestination.asset => strings.destinationAsset,
        TransactionLineDestination.recurring => strings.destinationRecurring,
      };

  static String _destinationHelp(
    AlayaStrings strings,
    TransactionLineDestination destination,
  ) =>
      switch (destination) {
        TransactionLineDestination.none => strings.destinationHelpNone,
        TransactionLineDestination.inventory => strings.destinationHelpInventory,
        TransactionLineDestination.asset => strings.destinationHelpAsset,
        TransactionLineDestination.recurring => strings.destinationHelpRecurring,
      };
}

class _NewItemRow extends StatelessWidget {
  const _NewItemRow({
    required this.category,
    required this.onCategoryChanged,
    required this.onCreate,
    required this.onCancel,
  });

  final UnitCategory category;
  final ValueChanged<UnitCategory> onCategoryChanged;
  final VoidCallback onCreate;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.itemCreateCategoryPrompt,
          style: AlayaTypography.label.copyWith(color: context.semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        SegmentedButton<UnitCategory>(
          segments: [
            for (final option in UnitCategory.values)
              ButtonSegment(
                value: option,
                label: Text(_LineItemEditorState._categoryLabel(strings, option)),
              ),
          ],
          selected: {category},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onCategoryChanged(selection.first),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Row(
          children: [
            Expanded(
              child: FilledButton(onPressed: onCreate, child: Text(strings.itemCreate)),
            ),
            const SizedBox(width: AlayaSpacing.xs),
            TextButton(onPressed: onCancel, child: Text(strings.actionCancel)),
          ],
        ),
      ],
    );
  }
}
```

## Part 1 — the Inventory module

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

### `lib/shared/widgets/alaya_timeline.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// How a timeline entry is toned.
enum TimelineTone {
  /// The default — a neutral event.
  neutral,

  /// Stock arriving.
  incoming,

  /// Stock leaving.
  outgoing,

  /// A correction, drawn muted and struck through.
  superseded,
}

/// One event on an [AlayaTimeline].
class AlayaTimelineEntry {
  /// Creates an entry.
  const AlayaTimelineEntry({
    required this.title,
    required this.trailing,
    this.subtitle,
    this.meta,
    this.icon,
    this.tone = TimelineTone.neutral,
    this.badge,
    this.onTap,
  });

  /// What happened.
  final String title;

  /// The figure, rendered by the caller so `Qty` still goes through `QtyText` (U7).
  final Widget trailing;

  /// When it happened, rendered by the caller so `DateKey` still goes through `DateText` (U7).
  final Widget? subtitle;

  /// A secondary line — a reason, a note.
  final String? meta;

  /// A glyph on the rail.
  final IconData? icon;

  /// How to tone the entry.
  final TimelineTone tone;

  /// A chip-like marker, e.g. "Reversed".
  final String? badge;

  /// Opens the entry.
  final VoidCallback? onTap;
}

/// A vertical event timeline (ARCH_5 §8), returned as a sliver.
///
/// **Takes a builder, not a list.** An earlier version took `List<AlayaTimelineEntry>`, and because
/// every entry holds constructed widgets — a `QtyText`, a `DateText` — a batch with a year of
/// consumption allocated the whole year's widgets on every rebuild. Rendering was virtualised;
/// construction was not, which is the half of U13 that a `SliverList` alone does not give you.
///
/// Place it inside a `CustomScrollView`.
class AlayaTimeline extends StatelessWidget {
  /// Creates the timeline.
  const AlayaTimeline({
    required this.itemCount,
    required this.itemBuilder,
    super.key,
  });

  /// How many events there are.
  final int itemCount;

  /// Builds the event at [index], newest first.
  final AlayaTimelineEntry Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) => SliverList.builder(
        itemCount: itemCount,
        itemBuilder: (context, index) => _Entry(
          entry: itemBuilder(context, index),
          isFirst: index == 0,
          isLast: index == itemCount - 1,
        ),
      );
}

class _Entry extends StatelessWidget {
  const _Entry({required this.entry, required this.isFirst, required this.isLast});

  final AlayaTimelineEntry entry;
  final bool isFirst;
  final bool isLast;

  Color _toneColour(AlayaSemanticColors semantic) => switch (entry.tone) {
        TimelineTone.neutral => semantic.muted,
        TimelineTone.incoming => semantic.success,
        TimelineTone.outgoing => semantic.danger,
        TimelineTone.superseded => semantic.muted,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final colour = _toneColour(semantic);
    final superseded = entry.tone == TimelineTone.superseded;

    // `IntrinsicHeight` is what lets the connector reach the next entry. The rail is a Column with an
    // `Expanded` segment, and a sliver child's Row has no height of its own — so without this the
    // Column is unbounded and `Expanded` throws rather than stretching.
    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.screenEdge,
        vertical: AlayaSpacing.xs,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Rail(colour: colour, icon: entry.icon, isFirst: isFirst, isLast: isLast),
            const SizedBox(width: AlayaSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // **Stacks above 1.5x (Law U21).** `trailing` is whatever the caller passes — an
                  // `AmountText`, a `QtyText` — and it is not flexible, so at a doubled text scale it
                  // takes its natural width and pushes the title off the rail. `Flexible` is the wrong
                  // fix: against a tight `Expanded` the two split evenly and the title truncates at
                  // scale 1, and a clipped figure is a wrong figure.
                  if (MediaQuery.textScalerOf(context).scale(1) >= 1.5) ...[
                    Text(
                      entry.title,
                      style: AlayaTypography.body.copyWith(
                        color: superseded ? semantic.muted : theme.colorScheme.onSurface,
                        decoration: superseded ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: AlayaSpacing.xxs),
                    Align(alignment: Alignment.centerLeft, child: entry.trailing),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            style: AlayaTypography.body.copyWith(
                              color: superseded ? semantic.muted : theme.colorScheme.onSurface,
                              decoration: superseded ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: AlayaSpacing.sm),
                        entry.trailing,
                      ],
                    ),
                  if (entry.subtitle != null) ...[
                    const SizedBox(height: AlayaSpacing.xxs),
                    entry.subtitle!,
                  ],
                  if (entry.meta != null) ...[
                    const SizedBox(height: AlayaSpacing.xxs),
                    Text(
                      entry.meta!,
                      style: AlayaTypography.caption.copyWith(color: semantic.muted),
                    ),
                  ],
                  if (entry.badge != null) ...[
                    const SizedBox(height: AlayaSpacing.xs),
                    _Badge(label: entry.badge!, colour: colour),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final onTap = entry.onTap;
    if (onTap == null) return body;
    return InkWell(onTap: onTap, child: body);
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.colour,
    required this.icon,
    required this.isFirst,
    required this.isLast,
  });

  final Color colour;
  final IconData? icon;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: AlayaIconSize.lg,
        child: Column(
          children: [
            _Line(colour: colour, visible: !isFirst, height: AlayaSpacing.xs),
            Icon(icon ?? Icons.circle, size: AlayaIconSize.sm, color: colour),
            if (!isLast) Expanded(child: _Line(colour: colour, visible: true)),
          ],
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line({required this.colour, required this.visible, this.height});

  final Color colour;
  final bool visible;
  final double? height;

  @override
  Widget build(BuildContext context) => Container(
        width: AlayaSpacing.xxs / 2,
        height: height,
        color: visible ? colour.withValues(alpha: 0.28) : Colors.transparent,
      );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.colour});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AlayaSpacing.xs,
          vertical: AlayaSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          borderRadius: AlayaRadii.borderXs,
        ),
        child: Text(
          label,
          style: AlayaTypography.overline.copyWith(color: colour),
        ),
      );
}
```

### `lib/features/inventory/state/inventory_filter.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';

/// The axis the catalogue groups by.
enum InventoryGroupBy {
  /// By `items.itemKind` — food, medicine, household.
  kind,

  /// Favourites first, everything else after.
  favourite,
}

/// What the inventory list is currently showing.
///
/// **Grouping is by `itemKind`, not by tag.** Archetype D asks for "the user's own axis — tag for
/// items", and `item_tags` is assigned to this phase in ARCH_5 §7.1 — but no contract in Phase 3A
/// reads or writes an item's tags. `TagRepository` exposes `watchForTransaction` and nothing
/// equivalent for items, and U19 forbids a feature declaring its own repository. `itemKind` is the
/// nearest axis that exists, is set by the user in the editor, and needs no new contract. The tag
/// axis is recorded as a deferral in the coverage table with the contract it waits on.
class InventoryFilter {
  /// Creates a filter.
  const InventoryFilter({
    this.groupBy = InventoryGroupBy.kind,
    this.favouritesOnly = false,
    this.lowStockOnly = false,
    this.kinds = const <ItemKind>{},
    this.query = '',
  });

  /// The grouping axis.
  final InventoryGroupBy groupBy;

  /// Whether only starred items are shown.
  final bool favouritesOnly;

  /// Whether only items below their low-stock level are shown.
  final bool lowStockOnly;

  /// Which kinds are shown; empty means all.
  final Set<ItemKind> kinds;

  /// The search term, already trimmed.
  final String query;

  /// Whether anything narrows the full catalogue.
  bool get isNarrowed =>
      favouritesOnly || lowStockOnly || kinds.isNotEmpty || groupBy != InventoryGroupBy.kind;

  /// Whether a search is running.
  bool get isSearching => query.isNotEmpty;

  /// Returns a copy with the supplied changes.
  InventoryFilter copyWith({
    InventoryGroupBy? groupBy,
    bool? favouritesOnly,
    bool? lowStockOnly,
    Set<ItemKind>? kinds,
    String? query,
  }) =>
      InventoryFilter(
        groupBy: groupBy ?? this.groupBy,
        favouritesOnly: favouritesOnly ?? this.favouritesOnly,
        lowStockOnly: lowStockOnly ?? this.lowStockOnly,
        kinds: kinds ?? this.kinds,
        query: query ?? this.query,
      );
}
```

### `lib/features/inventory/state/item_editor_state.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';

/// Why a save was refused, when it was refused for a reason worth naming.
enum ItemSaveIssue {
  /// A live item already has this name and this measure.
  duplicate,

  /// No units exist for the chosen measure, so the display unit would dangle.
  unitsMissing,

  /// The write failed for a reason the repository did not name.
  unknown,
}

/// Everything the item editor is holding (ARCH_5 §3 archetype B).
///
/// **`unitCategory` has no setter once [isEditing] is true.** Law L8 makes it immutable after
/// creation and there is no cross-category conversion, so changing it would reinterpret every batch
/// and movement already recorded against this item — 2 kg of flour silently becoming 2 litres. The
/// editor renders it read-only and says why rather than offering a control that must then be
/// refused.
class ItemEditorState {
  /// Creates the editor's state.
  const ItemEditorState({
    required this.unitCategory,
    required this.displayUnitCode,
    this.thresholdUnitCode,
    this.id,
    this.name = '',
    this.itemKind = ItemKind.generic,
    this.isFavorite = false,
    this.lowStockThreshold,
    this.expiryNotifyDays,
    this.notes,
    this.submitting = false,
    this.nameMissing = false,
    this.shakeTrigger = 0,
    this.dirty = false,
    this.issue,
    this.conflictItemId,
    this.similarInOtherMeasures = const <Item>[],
  });

  /// The item being edited, or null when this is a new one.
  final String? id;

  /// The name — the one required field (U11).
  final String name;

  /// How this item is measured. Immutable once saved (Law L8).
  final UnitCategory unitCategory;

  /// The unit this item's quantities are shown in.
  final String displayUnitCode;

  /// The unit the low-stock threshold is being *entered* in, which is not the display unit.
  ///
  /// Kept separately because typing a threshold in grams must not silently switch the item's whole
  /// display to grams — the stored `Qty` is milli-base either way, so the two choices are
  /// independent and conflating them surprises the user for no gain.
  final String? thresholdUnitCode;

  /// What sort of thing it is; also the catalogue's grouping axis.
  final ItemKind itemKind;

  /// Whether it is starred.
  final bool isFavorite;

  /// The level below which the `low` chip appears.
  final Qty? lowStockThreshold;

  /// Days of warning before a batch expires, consumed by Phase 8B.
  final int? expiryNotifyDays;

  /// Free notes.
  final String? notes;

  /// Whether a save is in flight.
  final bool submitting;

  /// Whether submit was pressed with an empty name.
  final bool nameMissing;

  /// Incremented to shake the name field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (U10).
  final bool dirty;

  /// Why the last save was refused, or null if it was not.
  final ItemSaveIssue? issue;

  /// The existing item this one collides with, so the editor can offer to open it.
  final String? conflictItemId;

  /// Items with this name under a different measure.
  ///
  /// Not a conflict — Law L8 makes `apple` by weight and `apple` by count two genuinely different
  /// things, and a household legitimately has both. Surfaced as a note so the catalogue does not
  /// fragment by accident, never as a block.
  final List<Item> similarInOtherMeasures;

  /// Whether this is editing an existing item rather than creating one.
  bool get isEditing => id != null;

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  ItemEditorState copyWith({
    String? id,
    String? name,
    String? displayUnitCode,
    String? thresholdUnitCode,
    ItemKind? itemKind,
    bool? isFavorite,
    Qty? lowStockThreshold,
    bool clearThreshold = false,
    int? expiryNotifyDays,
    bool clearNotifyDays = false,
    String? notes,
    bool? submitting,
    bool? nameMissing,
    int? shakeTrigger,
    bool? dirty,
    ItemSaveIssue? issue,
    bool clearIssue = false,
    String? conflictItemId,
    List<Item>? similarInOtherMeasures,
  }) =>
      ItemEditorState(
        id: id ?? this.id,
        name: name ?? this.name,
        unitCategory: unitCategory,
        displayUnitCode: displayUnitCode ?? this.displayUnitCode,
        thresholdUnitCode: thresholdUnitCode ?? this.thresholdUnitCode,
        itemKind: itemKind ?? this.itemKind,
        isFavorite: isFavorite ?? this.isFavorite,
        lowStockThreshold:
            clearThreshold ? null : (lowStockThreshold ?? this.lowStockThreshold),
        expiryNotifyDays:
            clearNotifyDays ? null : (expiryNotifyDays ?? this.expiryNotifyDays),
        notes: notes ?? this.notes,
        submitting: submitting ?? this.submitting,
        nameMissing: nameMissing ?? this.nameMissing,
        shakeTrigger: shakeTrigger ?? this.shakeTrigger,
        dirty: dirty ?? true,
        issue: clearIssue ? null : (issue ?? this.issue),
        conflictItemId: clearIssue ? null : (conflictItemId ?? this.conflictItemId),
        similarInOtherMeasures: similarInOtherMeasures ?? this.similarInOtherMeasures,
      );

  /// Builds the entity this state describes.
  Item toItem({required String newId, required String normalizedName}) => Item(
        id: id ?? newId,
        name: name.trim(),
        normalizedName: normalizedName,
        unitCategory: unitCategory,
        defaultDisplayUnitCode: displayUnitCode,
        itemKind: itemKind,
        isFavorite: isFavorite,
        lowStockThreshold: lowStockThreshold,
        expiryNotifyDays: expiryNotifyDays,
        notes: notes,
      );

  /// Loads an existing item into an editor state.
  static ItemEditorState fromItem(Item item) => ItemEditorState(
        id: item.id,
        name: item.name,
        unitCategory: item.unitCategory,
        displayUnitCode: item.defaultDisplayUnitCode,
        itemKind: item.itemKind,
        isFavorite: item.isFavorite,
        lowStockThreshold: item.lowStockThreshold,
        expiryNotifyDays: item.expiryNotifyDays,
        notes: item.notes,
      );
}
```

### `lib/features/inventory/state/batch_editor_state.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';

/// Everything the batch editor is holding (ARCH_5 §3 archetype B).
///
/// A batch's quantity is editable only while creating. Once movements exist against it,
/// `remainingQuantity` is a derived cache (Law L3) reconciled from the movement ledger, so an editor
/// rewriting it would put the cache and the ledger into disagreement that only `recompute()` could
/// resolve. Editing therefore covers the metadata — expiry, purchase date, unit cost, location — and
/// quantity changes go through the consume and adjust paths, which append movements.
class BatchEditorState {
  /// Creates the editor's state.
  const BatchEditorState({
    required this.itemId,
    required this.unitCode,
    required this.purchasedDateKey,
    this.id,
    this.quantity,
    this.expiryDateKey,
    this.unitCost,
    this.storageLocation,
    this.note,
    this.origin = BatchOrigin.manual,
    this.submitting = false,
    this.quantityMissing = false,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// The batch being edited, or null when this is a new one.
  final String? id;

  /// Which item this batch belongs to.
  final String itemId;

  /// How much arrived — the one required field when creating (U11).
  final Qty? quantity;

  /// The unit the quantity was entered in.
  final String unitCode;

  /// When it was bought.
  final DateKey purchasedDateKey;

  /// When it expires, if it does.
  final DateKey? expiryDateKey;

  /// What one unit cost.
  final Money? unitCost;

  /// Where it is kept.
  final String? storageLocation;

  /// Free note.
  final String? note;

  /// Where this batch came from; preserved on edit so a fan-out batch stays attributed.
  final BatchOrigin origin;

  /// Whether a save is in flight.
  final bool submitting;

  /// Whether submit was pressed with no parseable quantity.
  final bool quantityMissing;

  /// Incremented to shake the quantity field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (U10).
  final bool dirty;

  /// Whether this is editing an existing batch rather than creating one.
  bool get isEditing => id != null;

  /// Whether the quantity field may be edited.
  bool get quantityEditable => !isEditing;

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  BatchEditorState copyWith({
    String? id,
    Qty? quantity,
    bool clearQuantity = false,
    String? unitCode,
    DateKey? purchasedDateKey,
    DateKey? expiryDateKey,
    bool clearExpiry = false,
    Money? unitCost,
    bool clearUnitCost = false,
    String? storageLocation,
    String? note,
    BatchOrigin? origin,
    bool? submitting,
    bool? quantityMissing,
    int? shakeTrigger,
    bool? dirty,
  }) =>
      BatchEditorState(
        id: id ?? this.id,
        itemId: itemId,
        quantity: clearQuantity ? null : (quantity ?? this.quantity),
        unitCode: unitCode ?? this.unitCode,
        purchasedDateKey: purchasedDateKey ?? this.purchasedDateKey,
        expiryDateKey: clearExpiry ? null : (expiryDateKey ?? this.expiryDateKey),
        unitCost: clearUnitCost ? null : (unitCost ?? this.unitCost),
        storageLocation: storageLocation ?? this.storageLocation,
        note: note ?? this.note,
        origin: origin ?? this.origin,
        submitting: submitting ?? this.submitting,
        quantityMissing: quantityMissing ?? this.quantityMissing,
        shakeTrigger: shakeTrigger ?? this.shakeTrigger,
        dirty: dirty ?? true,
      );

  /// Builds the entity this state describes.
  ///
  /// [remaining] is the existing remaining quantity when editing; a new batch starts full.
  Batch toBatch({required String newId, required Qty resolvedQuantity, Qty? remaining}) => Batch(
        id: id ?? newId,
        itemId: itemId,
        initialQuantity: resolvedQuantity,
        remainingQuantity: remaining ?? resolvedQuantity,
        unitCodeAtPurchase: unitCode,
        purchasedDateKey: purchasedDateKey,
        origin: origin,
        expiryDateKey: expiryDateKey,
        unitCost: unitCost,
        storageLocation: storageLocation,
        note: note,
      );

  /// Loads an existing batch into an editor state.
  static BatchEditorState fromBatch(Batch batch) => BatchEditorState(
        id: batch.id,
        itemId: batch.itemId,
        quantity: batch.initialQuantity,
        unitCode: batch.unitCodeAtPurchase,
        purchasedDateKey: batch.purchasedDateKey,
        expiryDateKey: batch.expiryDateKey,
        unitCost: batch.unitCost,
        storageLocation: batch.storageLocation,
        note: batch.note,
        origin: batch.origin,
      );
}
```

### `lib/features/inventory/state/consume_state.dart`

```dart
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/domain/entities/batch.dart';

/// One batch the pending consume will draw from, and how much.
class ConsumePlanLeg {
  /// Creates a leg.
  const ConsumePlanLeg({required this.batch, required this.quantity});

  /// The batch drawn from.
  final Batch batch;

  /// How much comes out of it.
  final Qty quantity;
}

/// What the consume sheet is holding (ARCH_5 §3 archetype A).
class ConsumeState {
  /// Creates the sheet's state.
  const ConsumeState({
    required this.itemId,
    required this.unitCode,
    this.quantity,
    this.kind = StockMovementKind.consume,
    this.overrideBatchId,
    this.reason,
    this.submitting = false,
    this.quantityMissing = false,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// Which item is being drawn down.
  final String itemId;

  /// The unit the quantity was entered in.
  final String unitCode;

  /// How much — the one required field (U11).
  final Qty? quantity;

  /// Used, thrown away, or expired. Three kinds, not one with a reason string, because 7B's waste
  /// insight aggregates on `stock_movements.kind` and cannot read prose.
  final StockMovementKind kind;

  /// The batch the user picked instead of letting FEFO choose.
  final String? overrideBatchId;

  /// Why, for waste and expiry.
  final String? reason;

  /// Whether a commit is in flight.
  final bool submitting;

  /// Whether commit was pressed with no parseable quantity.
  final bool quantityMissing;

  /// Incremented to shake the quantity field.
  final int shakeTrigger;

  /// Whether any optional field was touched, for the dismiss guard (U10).
  final bool dirty;

  /// Whether the user has overridden the FEFO choice.
  bool get isOverridden => overrideBatchId != null;

  /// Returns a copy with the supplied changes.
  ConsumeState copyWith({
    Qty? quantity,
    bool clearQuantity = false,
    String? unitCode,
    StockMovementKind? kind,
    String? overrideBatchId,
    bool clearOverride = false,
    String? reason,
    bool? submitting,
    bool? quantityMissing,
    int? shakeTrigger,
    bool? dirty,
  }) =>
      ConsumeState(
        itemId: itemId,
        unitCode: unitCode ?? this.unitCode,
        quantity: clearQuantity ? null : (quantity ?? this.quantity),
        kind: kind ?? this.kind,
        overrideBatchId: clearOverride ? null : (overrideBatchId ?? this.overrideBatchId),
        reason: reason ?? this.reason,
        submitting: submitting ?? this.submitting,
        quantityMissing: quantityMissing ?? this.quantityMissing,
        shakeTrigger: shakeTrigger ?? this.shakeTrigger,
        dirty: dirty ?? this.dirty,
      );

  /// Which batches this consume will touch, oldest expiry first.
  ///
  /// **Computed here so the sheet can say "spans 3 batches" before committing**, not after. The
  /// repository's `consume()` does the authoritative allocation and returns the draws it actually
  /// made; this is the preview that lets the user see a multi-batch write coming. The two agree
  /// because both walk the same FEFO ordering from `watchByItemFefo`.
  ///
  /// An override collapses the plan to a single leg, clamped to what that batch holds.
  List<ConsumePlanLeg> planAgainst(List<Batch> fefo) {
    final wanted = quantity;
    if (wanted == null || !wanted.isPositive) return const [];

    final override = overrideBatchId;
    if (override != null) {
      for (final batch in fefo) {
        if (batch.id != override) continue;
        final take = wanted <= batch.remainingQuantity ? wanted : batch.remainingQuantity;
        return take.isPositive ? [ConsumePlanLeg(batch: batch, quantity: take)] : const [];
      }
      return const [];
    }

    final legs = <ConsumePlanLeg>[];
    var outstanding = wanted;
    for (final batch in fefo) {
      if (!outstanding.isPositive) break;
      if (!batch.hasStock) continue;
      final take =
          outstanding <= batch.remainingQuantity ? outstanding : batch.remainingQuantity;
      legs.add(ConsumePlanLeg(batch: batch, quantity: take));
      outstanding -= take;
    }
    return legs;
  }

  /// How much of [quantity] the batches cannot cover.
  Qty? shortfallAgainst(List<Batch> fefo) {
    final wanted = quantity;
    if (wanted == null) return null;
    var covered = Qty(0, wanted.category);
    for (final leg in planAgainst(fefo)) {
      covered += leg.quantity;
    }
    final missing = wanted - covered;
    return missing.isPositive ? missing : null;
  }
}
```

### `lib/features/inventory/providers/inventory_list_providers.dart`

```dart
/// View-model state for the inventory catalogue (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/state/inventory_filter.dart';

/// One section of the catalogue.
class InventoryGroup {
  /// Creates a group.
  const InventoryGroup({required this.items, this.kind, this.isFavourites = false});

  /// The items in it, already sorted by name.
  final List<Item> items;

  /// Which kind this group collects, or null for the favourites group.
  final ItemKind? kind;

  /// Whether this is the favourites group.
  final bool isFavourites;
}

/// The catalogue's current filter.
final inventoryFilterProvider =
    NotifierProvider<InventoryFilterNotifier, InventoryFilter>(InventoryFilterNotifier.new);

/// Drives the search field, group-by chips and filter toggles.
class InventoryFilterNotifier extends Notifier<InventoryFilter> {
  @override
  InventoryFilter build() => const InventoryFilter();

  /// Sets the search term.
  void setQuery(String query) => state = state.copyWith(query: query.trim());

  /// Switches the grouping axis.
  void setGroupBy(InventoryGroupBy groupBy) => state = state.copyWith(groupBy: groupBy);

  /// Shows only starred items.
  void toggleFavouritesOnly() =>
      state = state.copyWith(favouritesOnly: !state.favouritesOnly);

  /// Shows only items below their low-stock level.
  void toggleLowStockOnly() => state = state.copyWith(lowStockOnly: !state.lowStockOnly);

  /// Adds or removes a kind.
  void toggleKind(ItemKind kind) {
    final next = {...state.kinds};
    if (next.contains(kind)) {
      next.remove(kind);
    } else {
      next.add(kind);
    }
    state = state.copyWith(kinds: next);
  }

  /// Clears everything back to the full catalogue.
  void clear() => state = InventoryFilter(query: state.query);
}

/// Every item in the catalogue.
final itemsProvider = StreamProvider<List<Item>>(
  (ref) => ref.watch(itemRepositoryProvider).watchAll(),
);

/// Stock on hand for every item, keyed by item id.
///
/// `ItemStock.totalRemaining` is the summed mixed-unit figure the row shows — the sum lives in the
/// domain rather than being re-added in the widget, which is what keeps ARCH_1 §5.4's arithmetic in
/// one place instead of two.
final itemStocksProvider = StreamProvider<Map<String, ItemStock>>(
  (ref) => ref.watch(itemRepositoryProvider).watchAllStock().map(
        (stocks) => {for (final stock in stocks) stock.itemId: stock},
      ),
);

/// Every unit, keyed by code, so a row can name the unit a quantity is shown in.
final unitsByCodeProvider = StreamProvider<Map<String, Unit>>(
  (ref) => ref.watch(unitRepositoryProvider).watchAll().map(
        (units) => {for (final unit in units) unit.code: unit},
      ),
);

/// The catalogue, filtered, searched and grouped.
///
/// A `Provider` over the two streams rather than a third stream: grouping is pure, and doing it here
/// means the screen watches one thing and gets all four states from it.
final inventoryGroupsProvider = Provider<AsyncValue<List<InventoryGroup>>>((ref) {
  final items = ref.watch(itemsProvider);
  final stocks = ref.watch(itemStocksProvider);
  final filter = ref.watch(inventoryFilterProvider);

  if (items.hasError) return AsyncValue.error(items.error!, items.stackTrace!);
  if (stocks.hasError) return AsyncValue.error(stocks.error!, stocks.stackTrace!);
  final all = items.valueOrNull;
  final byId = stocks.valueOrNull;
  if (all == null || byId == null) return const AsyncValue.loading();

  final term = filter.query.toLowerCase();
  final visible = [
    for (final item in all)
      if (_admits(item, byId[item.id], filter, term)) item,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  if (filter.groupBy == InventoryGroupBy.favourite) {
    final starred = [for (final item in visible) if (item.isFavorite) item];
    final rest = [for (final item in visible) if (!item.isFavorite) item];
    return AsyncValue.data([
      if (starred.isNotEmpty) InventoryGroup(items: starred, isFavourites: true),
      if (rest.isNotEmpty) InventoryGroup(items: rest),
    ]);
  }

  final buckets = <ItemKind, List<Item>>{};
  for (final item in visible) {
    buckets.putIfAbsent(item.itemKind, () => <Item>[]).add(item);
  }
  return AsyncValue.data([
    for (final kind in ItemKind.values)
      if (buckets[kind] != null) InventoryGroup(items: buckets[kind]!, kind: kind),
  ]);
});

/// How many items are below their low-stock level, for the filter chip's count.
final lowStockCountProvider = Provider<int>((ref) {
  final stocks = ref.watch(itemStocksProvider).valueOrNull;
  if (stocks == null) return 0;
  return stocks.values.where((stock) => stock.isLowStock).length;
});

bool _admits(Item item, ItemStock? stock, InventoryFilter filter, String term) {
  if (filter.favouritesOnly && !item.isFavorite) return false;
  if (filter.lowStockOnly && !(stock?.isLowStock ?? false)) return false;
  if (filter.kinds.isNotEmpty && !filter.kinds.contains(item.itemKind)) return false;
  if (term.isEmpty) return true;
  return item.normalizedName.contains(term) || item.name.toLowerCase().contains(term);
}
```

### `lib/features/inventory/providers/item_detail_providers.dart`

```dart
/// View-model state for one item (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/providers/inventory_list_providers.dart';

/// The item, or null when it has been deleted.
/// **Derived from the catalogue stream, not a one-shot `byId`.** A `FutureProvider` reads once and
/// then serves its cache, and `autoDispose` does not help — the detail screen stays mounted beneath
/// the editor, so it kept showing the pre-edit item until the app was restarted. `watchAll()` re-emits
/// on every write, so selecting one item out of it makes the screen live and needs no `watchById` on
/// the contract.
final itemByIdProvider = Provider.autoDispose.family<AsyncValue<Item?>, String>((ref, id) {
  return ref.watch(itemsProvider).whenData((all) {
    for (final item in all) {
      if (item.id == id) return item;
    }
    return null;
  });
});

/// Stock on hand for one item — the hero figure.
final itemStockProvider = StreamProvider.autoDispose.family<ItemStock?, String>(
  (ref, id) => ref.watch(itemRepositoryProvider).watchStockOf(id),
);

/// This item's batches, oldest expiry first, which is also the order a consume draws them.
final itemBatchesProvider = StreamProvider.autoDispose.family<List<Batch>, String>(
  (ref, id) => ref.watch(batchRepositoryProvider).watchByItemFefo(id),
);

/// Every unit, keyed by code.
final detailUnitsByCodeProvider = StreamProvider.autoDispose<Map<String, Unit>>(
  (ref) => ref.watch(unitRepositoryProvider).watchAll().map(
        (units) => {for (final unit in units) unit.code: unit},
      ),
);

/// Writes an item detail screen can perform.
final itemActionsProvider = Provider<ItemActions>(ItemActions.new);

/// Deletes and stars items.
class ItemActions {
  /// Creates the actions.
  ItemActions(this._ref);

  final Ref _ref;

  /// Deletes the item, cascade-soft-deleting its batches.
  ///
  /// **The movement history is left untouched.** Batches carry `deletedAt` and go with the item, but
  /// `stock_movements` is append-only (Law L6) — what was already used genuinely happened, and
  /// erasing it would change last month's waste figures because a container was tidied away today.
  Future<bool> delete(String id) async {
    final result = await _ref.read(itemRepositoryProvider).delete(id);
    return !result.isFailure;
  }

  /// Stars or unstars the item.
  Future<bool> toggleFavourite(Item item) async {
    final result = await _ref.read(itemRepositoryProvider).setFavorite(
          id: item.id,
          isFavorite: !item.isFavorite,
        );
    return !result.isFailure;
  }

  /// Deletes one batch, leaving its movements in place for the same reason.
  Future<bool> deleteBatch(String batchId) async {
    final result = await _ref.read(batchRepositoryProvider).delete(batchId);
    return !result.isFailure;
  }
}
```

### `lib/features/inventory/providers/item_editor_providers.dart`

```dart
/// View-model state for the item editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/state/item_editor_state.dart';

/// The units available in one category.
///
/// Category-filtered, always. Law L8 says cross-category conversion does not exist, so offering
/// `ml` for an item measured by weight would present a choice the domain cannot honour.
final unitsInCategoryProvider =
    StreamProvider.autoDispose.family<List<Unit>, UnitCategory>(
  (ref, category) => ref.watch(unitRepositoryProvider).watchByCategory(category),
);

/// The editor for one item, or for a new one when the argument is null.
final itemEditorProvider = NotifierProvider.autoDispose
    .family<ItemEditorNotifier, AsyncValue<ItemEditorState>, String?>(
  ItemEditorNotifier.new,
);

/// Loads, edits and saves one item.
class ItemEditorNotifier
    extends AutoDisposeFamilyNotifier<AsyncValue<ItemEditorState>, String?> {
  @override
  AsyncValue<ItemEditorState> build(String? arg) {
    // **A new item starts populated, not loading.** `_load` assigned `state` with no `await` before
    // it, which means it ran *during* `build` — Riverpod refuses that, the assignment was lost or
    // threw, and the screen sat on its skeleton with no form and no error. There is also nothing to
    // fetch for a blank item, so pretending to load was wrong twice over.
    if (arg == null) {
      return const AsyncValue.data(
        ItemEditorState(unitCategory: UnitCategory.count, displayUnitCode: 'pc'),
      );
    }
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(String id) async {
    try {
      final item = await ref.read(itemRepositoryProvider).byId(id);
      if (item == null) {
        state = AsyncValue.error(StateError('Item $id not found.'), StackTrace.current);
        return;
      }
      state = AsyncValue.data(ItemEditorState.fromItem(item));
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _edit(ItemEditorState Function(ItemEditorState) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(change(current));
  }

  /// Sets the name.
  void setName(String name) =>
      _edit((s) => s.copyWith(name: name, nameMissing: false, clearIssue: true));

  /// Sets how this item is measured, and resets the display unit to that category's base.
  ///
  /// **Only callable while creating.** Law L8 makes the category immutable once saved, so the editor
  /// hides the control on edit and this method refuses the change rather than trusting it not to be
  /// called — a guard on the state is worth more than a guard on the widget.
  void setCategory(UnitCategory category, String baseUnitCode) => _edit(
        (s) => s.isEditing
            ? s
            : ItemEditorState(
                id: s.id,
                name: s.name,
                unitCategory: category,
                displayUnitCode: baseUnitCode,
                thresholdUnitCode: baseUnitCode,
                itemKind: s.itemKind,
                isFavorite: s.isFavorite,
                expiryNotifyDays: s.expiryNotifyDays,
                notes: s.notes,
                dirty: true,
              ),
      );

  /// Sets the unit quantities are displayed in.
  void setDisplayUnit(Unit unit) => _edit((s) => s.copyWith(displayUnitCode: unit.code));

  /// Sets the unit the low-stock threshold is being entered in.
  void setThresholdUnit(Unit unit) =>
      _edit((s) => s.copyWith(thresholdUnitCode: unit.code));

  /// Sets what sort of thing this is.
  void setKind(ItemKind kind) => _edit((s) => s.copyWith(itemKind: kind));

  /// Stars or unstars it.
  void toggleFavourite() => _edit((s) => s.copyWith(isFavorite: !s.isFavorite));

  /// Sets the level below which the `low` chip appears.
  void setThreshold(Qty? threshold) => _edit(
        (s) => threshold == null
            ? s.copyWith(clearThreshold: true)
            : s.copyWith(lowStockThreshold: threshold),
      );

  /// Sets how many days of expiry warning Phase 8B should give.
  void setExpiryNotifyDays(int? days) => _edit(
        (s) => days == null
            ? s.copyWith(clearNotifyDays: true)
            : s.copyWith(expiryNotifyDays: days),
      );

  /// Sets the free notes.
  void setNotes(String notes) => _edit((s) => s.copyWith(notes: notes));

  /// Saves the item, returning its id on success and null on rejection or failure.
  ///
  /// **Every refusal is named before the database gets a chance to refuse it.** `items` carries a
  /// partial unique index on `(normalized_name, unit_category)` and `default_display_unit_code`
  /// references `units`, so a blind write can fail two ways that look identical to the user. Checking
  /// first turns "something went wrong" into a sentence they can act on — and the duplicate case
  /// hands back the id of the item they already have, so the editor can offer to open it.
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.name.trim().isEmpty) {
      _edit((s) => s.copyWith(nameMissing: true, shakeTrigger: s.shakeTrigger + 1));
      return null;
    }

    _edit((s) => s.copyWith(submitting: true, clearIssue: true));
    try {
      final repository = ref.read(itemRepositoryProvider);
      final normalized = ref.read(normalizerProvider).normalize(current.name.trim());

      final clash = await repository.findByIdentity(
        normalizedName: normalized,
        unitCategory: current.unitCategory,
      );
      if (clash != null && clash.id != current.id) {
        _edit(
          (s) => s.copyWith(issue: ItemSaveIssue.duplicate, conflictItemId: clash.id),
        );
        return null;
      }

      // The display unit is a foreign key. Resolving it against the units that actually exist keeps a
      // thinly-seeded category from failing as an opaque constraint error.
      final units =
          await ref.read(unitRepositoryProvider).watchByCategory(current.unitCategory).first;
      if (units.isEmpty) {
        _edit((s) => s.copyWith(issue: ItemSaveIssue.unitsMissing));
        return null;
      }
      final displayUnit = units.any((unit) => unit.code == current.displayUnitCode)
          ? current.displayUnitCode
          : units.first.code;

      final id = current.id ?? ref.read(uidGeneratorProvider).generate();
      final saved = await repository.save(
        current.copyWith(displayUnitCode: displayUnit).toItem(
              newId: id,
              normalizedName: normalized,
            ),
      );
      if (saved.isFailure) {
        _edit((s) => s.copyWith(issue: ItemSaveIssue.unknown));
        return null;
      }
      _edit((s) => s.copyWith(dirty: false));
      return id;
    } on Object catch (error, stack) {
      ref.read(loggerProvider).log(
        'Item save failed',
        level: LogLevel.error,
        tag: 'inventory.itemEditor',
        error: error,
        stackTrace: stack,
      );
      _edit((s) => s.copyWith(issue: ItemSaveIssue.unknown));
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false));
    }
  }

  /// Looks up items sharing this name under a different measure, for the informational note.
  Future<void> refreshSimilar() async {
    final current = state.valueOrNull;
    if (current == null || current.name.trim().isEmpty) return;
    final similar = await ref.read(itemRepositoryProvider).findSimilar(
          name: current.name.trim(),
          unitCategory: current.unitCategory,
        );
    _edit(
      (s) => s.copyWith(
        similarInOtherMeasures: [
          for (final item in similar)
            if (item.id != current.id && item.unitCategory != current.unitCategory) item,
        ],
        dirty: s.dirty,
      ),
    );
  }
}
```

### `lib/features/inventory/providers/batch_editor_providers.dart`

```dart
/// View-model state for the batch editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/features/inventory/state/batch_editor_state.dart';

/// Which batch an editor is pointed at. A record, so the family argument has structural equality.
typedef BatchEditorArgs = ({String itemId, String? batchId});

/// The home currency, so a unit cost is never denominated in a guess.
final batchCurrencyProvider = FutureProvider.autoDispose<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ?? 'INR',
);

/// The home currency's decimal digits, so no cost hardcodes 2 (ARCH_1 §4.1).
final batchDecimalDigitsProvider = FutureProvider.autoDispose<int>((ref) async {
  final code = await ref.watch(batchCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// The item a batch belongs to, so the editor knows its immutable category.
final batchOwnerProvider = FutureProvider.autoDispose.family<Item?, String>(
  (ref, itemId) => ref.watch(itemRepositoryProvider).byId(itemId),
);

/// The editor for one batch, or for a new one when `batchId` is null.
final batchEditorProvider = NotifierProvider.autoDispose
    .family<BatchEditorNotifier, AsyncValue<BatchEditorState>, BatchEditorArgs>(
  BatchEditorNotifier.new,
);

/// Loads, edits and saves one batch.
class BatchEditorNotifier
    extends AutoDisposeFamilyNotifier<AsyncValue<BatchEditorState>, BatchEditorArgs> {
  @override
  AsyncValue<BatchEditorState> build(BatchEditorArgs arg) {
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(BatchEditorArgs arg) async {
    try {
      final batchId = arg.batchId;
      if (batchId != null) {
        final batch = await ref.read(batchRepositoryProvider).byId(batchId);
        if (batch == null) {
          state = AsyncValue.error(
            StateError('Batch $batchId not found.'),
            StackTrace.current,
          );
          return;
        }
        state = AsyncValue.data(BatchEditorState.fromBatch(batch));
        return;
      }
      final item = await ref.read(itemRepositoryProvider).byId(arg.itemId);
      if (item == null) {
        state = AsyncValue.error(
          StateError('Item ${arg.itemId} not found.'),
          StackTrace.current,
        );
        return;
      }
      state = AsyncValue.data(
        BatchEditorState(
          itemId: arg.itemId,
          unitCode: item.defaultDisplayUnitCode,
          purchasedDateKey: ref.read(clockProvider).today(),
        ),
      );
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _edit(BatchEditorState Function(BatchEditorState) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(change(current));
  }

  /// Sets how much arrived.
  void setQuantity(Qty? quantity) => _edit(
        (s) => quantity == null
            ? s.copyWith(clearQuantity: true)
            : s.copyWith(quantity: quantity, quantityMissing: false),
      );

  /// Sets the unit the quantity was entered in.
  void setUnitCode(String code) => _edit((s) => s.copyWith(unitCode: code));

  /// Sets when it was bought.
  void setPurchased(DateKey date) => _edit((s) => s.copyWith(purchasedDateKey: date));

  /// Sets when it expires, or clears the expiry.
  void setExpiry(DateKey? date) => _edit(
        (s) => date == null ? s.copyWith(clearExpiry: true) : s.copyWith(expiryDateKey: date),
      );

  /// Sets what one unit cost.
  void setUnitCost(Money? cost) => _edit(
        (s) => cost == null ? s.copyWith(clearUnitCost: true) : s.copyWith(unitCost: cost),
      );

  /// Sets where it is kept.
  void setStorageLocation(String location) =>
      _edit((s) => s.copyWith(storageLocation: location));

  /// Sets the free note.
  void setNote(String note) => _edit((s) => s.copyWith(note: note));

  /// Saves the batch, returning its id on success and null on rejection or failure.
  ///
  /// A new batch goes through `create`; an existing one through `updateMetadata`, which is the only
  /// path that does not touch `remainingQuantity`. That split is Law L3: the remaining figure is a
  /// cache reconciled from `stock_movements`, and an editor that rewrote it would leave the cache
  /// and the ledger disagreeing with no movement to explain the difference.
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    final quantity = current.quantity;
    if (quantity == null || !quantity.isPositive) {
      _edit((s) => s.copyWith(quantityMissing: true, shakeTrigger: s.shakeTrigger + 1));
      return null;
    }

    _edit((s) => s.copyWith(submitting: true));
    final repository = ref.read(batchRepositoryProvider);
    final id = current.id ?? ref.read(uidGeneratorProvider).generate();

    if (current.isEditing) {
      final existing = await repository.byId(id);
      if (existing == null) {
        _edit((s) => s.copyWith(submitting: false));
        return null;
      }
      final updated = await repository.updateMetadata(
        current.toBatch(
          newId: id,
          resolvedQuantity: existing.initialQuantity,
          remaining: existing.remainingQuantity,
        ),
      );
      if (updated.isFailure) {
        _edit((s) => s.copyWith(submitting: false));
        return null;
      }
    } else {
      final created =
          await repository.create(current.toBatch(newId: id, resolvedQuantity: quantity));
      if (created.isFailure) {
        _edit((s) => s.copyWith(submitting: false));
        return null;
      }
    }
    _edit((s) => s.copyWith(submitting: false, dirty: false));
    return id;
  }
}
```

### `lib/features/inventory/providers/consume_providers.dart`

```dart
/// View-model state for the consume sheet (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/features/inventory/state/consume_state.dart';

/// The batches a consume may draw from, oldest expiry first.
final consumeFefoProvider = StreamProvider.autoDispose.family<List<Batch>, String>(
  (ref, itemId) => ref.watch(batchRepositoryProvider).watchByItemFefo(itemId).map(
        (batches) => [for (final batch in batches) if (batch.hasStock) batch],
      ),
);

/// Which item a consume sheet is drawing down, and in what unit.
typedef ConsumeArgs = ({String itemId, String unitCode});

/// The consume sheet for one item.
final consumeProvider = NotifierProvider.autoDispose
    .family<ConsumeNotifier, ConsumeState, ConsumeArgs>(ConsumeNotifier.new);

/// Holds the pending consume and commits it.
///
/// **State is synchronous, not an `AsyncValue`.** A capture sheet must accept its first keystroke on
/// its first frame (§5.2), and everything this notifier needs — the item and its unit — arrives in
/// the family argument from the screen that already loaded them. The asynchronous surface belongs to
/// [consumeFefoProvider], which the sheet watches separately for its four states.
class ConsumeNotifier extends AutoDisposeFamilyNotifier<ConsumeState, ConsumeArgs> {
  @override
  ConsumeState build(ConsumeArgs arg) =>
      ConsumeState(itemId: arg.itemId, unitCode: arg.unitCode);

  /// Sets how much is leaving.
  void setQuantity(Qty? quantity) => state = quantity == null
      ? state.copyWith(clearQuantity: true)
      : state.copyWith(quantity: quantity, quantityMissing: false);

  /// Records the unit the field is entering quantities in.
  ///
  /// `QtyField`'s unit picker is controlled, so without this the user taps `g`, the number is
  /// re-parsed against the new factor, and the picker snaps back to `kg`.
  void setUnitCode(String code) => state = state.copyWith(unitCode: code, dirty: true);

  /// Switches between used, thrown away and expired.
  void setKind(StockMovementKind kind) => state = state.copyWith(kind: kind, dirty: true);

  /// Overrides the FEFO choice with a specific batch.
  void setBatch(String? batchId) => state = batchId == null
      ? state.copyWith(clearOverride: true, dirty: true)
      : state.copyWith(overrideBatchId: batchId, dirty: true);

  /// Sets why, for waste and expiry.
  void setReason(String reason) => state = state.copyWith(reason: reason, dirty: true);

  /// Commits the consume, returning how many movements it wrote.
  ///
  /// **Two paths, deliberately.** Without an override this calls `consume`, which allocates across
  /// batches FEFO inside one transaction (Law L14) and returns the draws it made — so a consume that
  /// spans three batches writes three movements and the caller learns the real count rather than the
  /// predicted one. With an override it calls `consumeFromBatch`, a single movement against the
  /// batch the user named.
  ///
  /// Returns null when the form was rejected or the write failed.
  Future<int?> commit() async {
    final quantity = state.quantity;
    if (quantity == null || !quantity.isPositive) {
      state = state.copyWith(quantityMissing: true, shakeTrigger: state.shakeTrigger + 1);
      return null;
    }

    state = state.copyWith(submitting: true);
    final repository = ref.read(stockRepositoryProvider);
    final override = state.overrideBatchId;

    if (override != null) {
      final result = await repository.consumeFromBatch(
        batchId: override,
        quantity: quantity,
        kind: state.kind,
        reason: state.reason,
      );
      state = state.copyWith(submitting: false);
      return result.isFailure ? null : 1;
    }

    final result = await repository.consume(
      itemId: state.itemId,
      quantity: quantity,
      kind: state.kind,
      reason: state.reason,
    );
    state = state.copyWith(submitting: false);
    return result.valueOrNull?.length;
  }
}
```

### `lib/features/inventory/providers/batch_history_providers.dart`

```dart
/// View-model state for one batch's movement history (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/stock_movement.dart';

/// The batch the history belongs to.
final historyBatchProvider = FutureProvider.autoDispose.family<Batch?, String>(
  (ref, batchId) => ref.watch(batchRepositoryProvider).byId(batchId),
);

/// Every movement against one batch, newest first.
final batchMovementsProvider =
    StreamProvider.autoDispose.family<List<StockMovement>, String>(
  (ref, batchId) => ref.watch(stockRepositoryProvider).watchForBatch(batchId),
);

/// Which movement ids have already been reversed by a later movement.
///
/// **Derived from the ledger rather than stored on the row.** `stock_movements` is append-only
/// (Law L6): a reversal is a new row pointing back with `reversesMovementId`, and the row it
/// corrects is never rewritten. Reading the set of reversed ids out of the same stream is what lets
/// the timeline strike through the original without either row lying about the other.
final reversedMovementIdsProvider =
    Provider.autoDispose.family<Set<String>, String>((ref, batchId) {
  final movements = ref.watch(batchMovementsProvider(batchId)).valueOrNull;
  if (movements == null) return const <String>{};
  return {
    for (final movement in movements)
      if (movement.reversesMovementId != null) movement.reversesMovementId!,
  };
});

/// Writes the history screen can perform.
final movementActionsProvider = Provider<MovementActions>(MovementActions.new);

/// Reverses movements.
class MovementActions {
  /// Creates the actions.
  MovementActions(this._ref);

  final Ref _ref;

  /// Appends an opposite movement, correcting [movementId] without erasing it.
  Future<bool> reverse(String movementId, {String? reason}) async {
    final result =
        await _ref.read(stockRepositoryProvider).reverse(movementId: movementId, reason: reason);
    return !result.isFailure;
  }
}
```

### `lib/features/inventory/presentation/widgets/item_row.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One catalogue row: identity, the number that matters, and a chip when abnormal (§3 archetype D).
///
/// **The figure is the summed mixed-unit total** — `4 kg 450 g`, not a batch count and not the
/// largest batch. `ItemStock.totalRemaining` is already the sum, so the row renders it through
/// `QtyText` and never adds anything itself (ARCH_1 §5.4, U7). Individual batches with their
/// expiries live one tap down on the detail screen.
///
/// The row stacks above roughly 1.5x text scale. A quantity like `4 kg 450 g` takes its full natural
/// width when it is not flexible, which starves the name beside it; the same shape overflowed a
/// transaction row and a nudge banner in Phase 6A, and clipping a quantity is as misleading as
/// clipping an amount (U15).
class ItemRow extends StatelessWidget {
  /// Creates the row.
  const ItemRow({
    required this.item,
    required this.stock,
    required this.today,
    required this.onTap,
    this.onToggleFavourite,
    super.key,
  });

  /// The item.
  final Item item;

  /// Its stock on hand, or null while the stock stream is still catching up.
  final ItemStock? stock;

  /// Today, for expiry comparisons.
  final DateKey today;

  /// Opens the detail screen.
  final VoidCallback onTap;

  /// Stars or unstars the item.
  final VoidCallback? onToggleFavourite;

  static IconData _glyphFor(ItemKind kind) => switch (kind) {
        ItemKind.food => Icons.restaurant_outlined,
        ItemKind.medicine => Icons.medication_outlined,
        ItemKind.beauty => Icons.spa_outlined,
        ItemKind.household => Icons.cleaning_services_outlined,
        ItemKind.generic || ItemKind.other => Icons.inventory_2_outlined,
      };

  List<Widget> _chips(BuildContext context, AlayaStrings strings) {
    final current = stock;
    if (current == null) return const [];
    final chips = <Widget>[];
    if (current.isOutOfStock) {
      chips.add(StatusChip(label: strings.outOfStockLabel));
    } else if (current.isLowStock) {
      chips.add(StatusChip(label: strings.lowStockLabel, tone: StatusTone.warning));
    }
    final days = current.daysUntilNearestExpiry(today);
    if (days != null && !current.isOutOfStock) {
      if (days < 0) {
        chips.add(StatusChip(label: strings.expiredLabel, tone: StatusTone.danger));
      } else if (days <= _soonDays) {
        chips.add(StatusChip(label: strings.expiringSoonLabel, tone: StatusTone.warning));
      }
    }
    return chips;
  }

  static const int _soonDays = 7;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final current = stock;
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final chips = _chips(context, strings);

    final quantity = current == null
        ? const SizedBox.shrink()
        : QtyText(
            current.totalRemaining,
            muted: current.isOutOfStock,
            textAlign: stacked ? TextAlign.start : TextAlign.end,
          );

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
            vertical: AlayaSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _glyphFor(item.itemKind),
                size: AlayaIconSize.lg,
                color: semantic.muted,
              ),
              const SizedBox(width: AlayaSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: AlayaTypography.body
                          .copyWith(color: theme.colorScheme.onSurface),
                    ),
                    if (current != null && current.batchCount > 0) ...[
                      const SizedBox(height: AlayaSpacing.xxs),
                      Text(
                        strings.itemBatchCount(current.batchCount),
                        style: AlayaTypography.caption.copyWith(color: semantic.muted),
                      ),
                    ],
                    if (stacked) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      quantity,
                    ],
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      Wrap(
                        spacing: AlayaSpacing.xs,
                        runSpacing: AlayaSpacing.xs,
                        children: chips,
                      ),
                    ],
                  ],
                ),
              ),
              if (!stacked) ...[
                const SizedBox(width: AlayaSpacing.sm),
                quantity,
              ],
              if (onToggleFavourite != null)
                IconButton(
                  onPressed: onToggleFavourite,
                  tooltip: item.isFavorite
                      ? strings.actionUnfavourite
                      : strings.actionFavourite,
                  icon: Icon(
                    item.isFavorite ? Icons.star : Icons.star_outline,
                    size: AlayaIconSize.md,
                    color: item.isFavorite ? semantic.warning : semantic.muted,
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

### `lib/features/inventory/presentation/widgets/batch_card.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One batch on the item detail screen: what is left, when it expires, where it came from.
///
/// **`origin == detached` gets a chip that explains itself.** A batch becomes detached when the
/// purchase that created it is deleted — the stock is genuinely still in the cupboard, so it is not
/// removed, but its receipt is gone and the cost figure behind it can no longer be traced. Without
/// the chip the user sees a batch with no source and assumes the app lost it.
class BatchCard extends StatelessWidget {
  /// Creates the card.
  const BatchCard({
    required this.batch,
    required this.today,
    required this.onTap,
    this.onHistory,
    super.key,
  });

  /// The batch.
  final Batch batch;

  /// Today, for expiry wording.
  final DateKey today;

  /// Opens the batch editor.
  final VoidCallback onTap;

  /// Opens the movement history.
  final VoidCallback? onHistory;

  static String _originLabel(AlayaStrings strings, BatchOrigin origin) => switch (origin) {
        BatchOrigin.purchase => strings.batchOriginPurchase,
        BatchOrigin.manual => strings.batchOriginManual,
        BatchOrigin.imported => strings.batchOriginImported,
        BatchOrigin.adjustment => strings.batchOriginAdjustment,
        BatchOrigin.detached => strings.statusDetached,
      };

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final days = batch.daysUntilExpiry(today);
    final location = batch.storageLocation;

    return AlayaCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AlayaSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: QtyText(batch.remainingQuantity, muted: batch.isExhausted),
              ),
              if (onHistory != null)
                IconButton(
                  onPressed: onHistory,
                  tooltip: strings.actionViewHistory,
                  icon: const Icon(Icons.history, size: AlayaIconSize.md),
                ),
            ],
          ),
          if (days != null) ...[
            const SizedBox(height: AlayaSpacing.xxs),
            Text(
              days < 0 ? strings.expiredDaysAgo(-days) : strings.expiresInDays(days),
              style: AlayaTypography.caption.copyWith(
                color: days < 0 ? semantic.danger : semantic.muted,
              ),
            ),
          ],
          const SizedBox(height: AlayaSpacing.xxs),
          DateText(batch.purchasedDateKey, style: DateTextStyle.medium, muted: true),
          if (location != null && location.isNotEmpty) ...[
            const SizedBox(height: AlayaSpacing.xxs),
            Text(
              location,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ],
          const SizedBox(height: AlayaSpacing.xs),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              StatusChip(
                label: _originLabel(strings, batch.origin),
                tone: batch.origin == BatchOrigin.detached
                    ? StatusTone.warning
                    : StatusTone.neutral,
                icon: batch.origin == BatchOrigin.detached ? Icons.link_off : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/inventory/presentation/screens/inventory_list_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/features/inventory/presentation/widgets/item_row.dart';
import 'package:alaya/features/inventory/providers/inventory_list_providers.dart';
import 'package:alaya/features/inventory/providers/item_detail_providers.dart';
import 'package:alaya/features/inventory/state/inventory_filter.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_search_field.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';

/// The inventory catalogue (ARCH_5 §3 archetype D).
///
/// **Search is a pinned field, not an app-bar icon.** A catalogue is searched constantly, and the
/// shell above owns the app bar anyway, so the field lives in the body where it is always visible.
///
/// Grouped by `items.itemKind`. Archetype D calls for the tag axis and ARCH_5 §7.1 assigns
/// `item_tags` to this phase, but no Phase 3A contract reads or writes an item's tags — see
/// `InventoryFilter`'s doc comment and the coverage table. The group-by control already carries two
/// axes, so adding the tag axis later is a third entry rather than a restructure.
class InventoryListScreen extends ConsumerWidget {
  /// Creates the screen.
  const InventoryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final groups = ref.watch(inventoryGroupsProvider);
    final filter = ref.watch(inventoryFilterProvider);

    return Scaffold(
      body: Column(
        children: [
          const _Toolbar(),
          const _ActiveFilters(),
          Expanded(
            child: groups.when(
              loading: () => AlayaListSkeleton(label: strings.loadingInventory),
              error: (error, stack) => ErrorState(
                title: strings.errorTitleGeneric,
                body: strings.errorBodyGeneric,
                retryLabel: strings.actionRetry,
                onRetry: () => ref.invalidate(itemsProvider),
              ),
              data: (sections) => sections.isEmpty
                  ? _Empty(isSearching: filter.isSearching || filter.isNarrowed)
                  : _Sections(sections: sections),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.itemNew),
        tooltip: strings.addItem,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final notifier = ref.read(inventoryFilterProvider.notifier);
    final filter = ref.watch(inventoryFilterProvider);
    final lowCount = ref.watch(lowStockCountProvider);

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
          AlayaSearchField(
            onChanged: notifier.setQuery,
            clearLabel: strings.actionClearSearch,
            hintText: strings.hintSearchItems,
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              FilterChip(
                label: Text(strings.filterFavouritesOnly),
                selected: filter.favouritesOnly,
                onSelected: (_) => notifier.toggleFavouritesOnly(),
              ),
              FilterChip(
                label: Text(
                  lowCount > 0
                      ? strings.lowStockWithCount(lowCount)
                      : strings.lowStockLabel,
                ),
                selected: filter.lowStockOnly,
                onSelected: (_) => notifier.toggleLowStockOnly(),
              ),
              FilterChip(
                label: Text(strings.groupByFavourites),
                selected: filter.groupBy == InventoryGroupBy.favourite,
                onSelected: (selected) => notifier.setGroupBy(
                  selected ? InventoryGroupBy.favourite : InventoryGroupBy.kind,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final filter = ref.watch(inventoryFilterProvider);
    final notifier = ref.read(inventoryFilterProvider.notifier);
    if (!filter.isNarrowed) return const SizedBox.shrink();

    return FilterChipBar(
      clearAllLabel: strings.filterReset,
      onClearAll: notifier.clear,
      filters: [
        if (filter.favouritesOnly)
          ActiveFilter(
            label: strings.filterFavouritesOnly,
            onRemove: notifier.toggleFavouritesOnly,
          ),
        if (filter.lowStockOnly)
          ActiveFilter(label: strings.lowStockLabel, onRemove: notifier.toggleLowStockOnly),
        if (filter.groupBy == InventoryGroupBy.favourite)
          ActiveFilter(
            label: strings.groupByFavourites,
            onRemove: () => notifier.setGroupBy(InventoryGroupBy.kind),
          ),
        for (final kind in filter.kinds)
          ActiveFilter(
            label: ItemKindLabel.of(strings, kind),
            onRemove: () => notifier.toggleKind(kind),
          ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.isSearching});

  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    if (isSearching) {
      return EmptyState(
        title: strings.emptyTitleNoResults,
        body: strings.emptyBodyNoResults,
        icon: Icons.search_off_outlined,
      );
    }
    return EmptyState(
      title: strings.emptyTitleNoItems,
      body: strings.emptyBodyNoItems,
      icon: Icons.inventory_2_outlined,
      actionLabel: strings.addItem,
      onAction: () => context.push(Routes.itemNew),
    );
  }
}

class _Sections extends ConsumerWidget {
  const _Sections({required this.sections});

  final List<InventoryGroup> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final stocks = ref.watch(itemStocksProvider).valueOrNull ?? const {};
    final today = ref.watch(clockProvider).today();

    return CustomScrollView(
      slivers: [
        for (final section in sections)
          SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: _GroupHeader(
                  label: section.isFavourites
                      ? strings.inventoryGroupFavourites
                      : section.kind == null
                          ? strings.inventoryGroupUntagged
                          : ItemKindLabel.of(strings, section.kind!),
                ),
              ),
              SliverList.builder(
                itemCount: section.items.length,
                itemBuilder: (context, index) {
                  final item = section.items[index];
                  return ItemRow(
                    item: item,
                    stock: stocks[item.id],
                    today: today,
                    onTap: () => context.push(Routes.itemDetail(item.id)),
                    onToggleFavourite: () async {
                      final ok =
                          await ref.read(itemActionsProvider).toggleFavourite(item);
                      if (!context.mounted || ok) return;
                      showFailureSnack(context, message: strings.errorBodyGeneric);
                    },
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

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.md,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
      ),
      child: Text(
        label,
        style: AlayaTypography.sectionHeader.copyWith(color: semantic.muted),
      ),
    );
  }
}

/// Resolves an [ItemKind] to its ARB label, so no screen in this feature writes the words.
abstract final class ItemKindLabel {
  /// The label for [kind].
  static String of(AlayaStrings strings, ItemKind kind) => switch (kind) {
        ItemKind.generic => strings.itemKindGeneric,
        ItemKind.food => strings.itemKindFood,
        ItemKind.medicine => strings.itemKindMedicine,
        ItemKind.beauty => strings.itemKindBeauty,
        ItemKind.household => strings.itemKindHousehold,
        ItemKind.other => strings.itemKindOther,
      };
}
```

### `lib/features/inventory/presentation/screens/item_detail_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/presentation/widgets/batch_card.dart';
import 'package:alaya/features/inventory/providers/item_detail_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One item in full (ARCH_5 §3 archetype E), routed outside the drawer shell (U18).
///
/// **The hero is the summed mixed-unit total.** That is the question someone opens this screen with —
/// "how much flour do I have" — and the answer is `4 kg 450 g`, one figure across every batch
/// (ARCH_1 §5.4). The batches that make it up are listed underneath with their expiries, because
/// every operation acts on a batch even though the headline is a sum.
class ItemDetailScreen extends ConsumerWidget {
  /// Shows the item with [itemId].
  const ItemDetailScreen({required this.itemId, super.key});

  /// Which item to show.
  final String itemId;

  Future<void> _delete(BuildContext context, WidgetRef ref, int batchCount) async {
    final strings = AlayaStrings.of(context);
    // Consequential rather than reversible (§5.5): `ItemRepository.delete` cascades to the batches
    // and there is no restore path in the 3A contract, so the sheet names what goes with it.
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.confirmDeleteItemTitle,
      body: strings.confirmDeleteItemBody(batchCount),
      confirmLabel: strings.actionDeleteItem,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(itemActionsProvider).delete(itemId);
    if (!context.mounted) return;
    if (!ok) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.itemDeleted);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(itemByIdProvider(itemId));

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.navInventory),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.itemEdit(itemId)),
            tooltip: strings.actionEdit,
            icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.lg),
          ),
        ],
      ),
      body: async.when(
        loading: () => AlayaListSkeleton(label: strings.loadingInventory, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: strings.errorBodyGeneric,
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(itemByIdProvider(itemId)),
        ),
        data: (item) => item == null
            ? EmptyState(
                title: strings.errorTitleNotFound,
                body: strings.errorBodyNotFound,
                icon: Icons.search_off_outlined,
              )
            : _Body(item: item, onDelete: (count) => _delete(context, ref, count)),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.item, required this.onDelete});

  final Item item;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final today = ref.watch(clockProvider).today();
    final stock = ref.watch(itemStockProvider(item.id)).valueOrNull;
    final batches = ref.watch(itemBatchesProvider(item.id));
    final units = ref.watch(detailUnitsByCodeProvider).valueOrNull ?? const {};
    final threshold = item.lowStockThreshold;
    final notifyDays = item.expiryNotifyDays;

    // `CustomScrollView`, not `ListView(children: [...])`. The batch list is fed by a repository
    // stream, and U13 admits no row-count exemption — a well-stocked item genuinely has dozens of
    // batches, so it is a `SliverList.builder` and the fixed sections around it are adapters.
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
          padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
          child: AlayaCard(
            tier: 2,
            padding: const EdgeInsets.all(AlayaSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: AlayaTypography.cardTitle
                            .copyWith(color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                    if (item.isFavorite)
                      Icon(Icons.star, size: AlayaIconSize.md, color: semantic.warning),
                  ],
                ),
                const SizedBox(height: AlayaSpacing.sm),
                if (stock != null)
                  QtyText(stock.totalRemaining)
                else
                  Text(
                    strings.loadingLabel,
                    style: AlayaTypography.caption.copyWith(color: semantic.muted),
                  ),
                if (stock != null) ...[
                  const SizedBox(height: AlayaSpacing.sm),
                  Wrap(
                    spacing: AlayaSpacing.xs,
                    runSpacing: AlayaSpacing.xs,
                    children: [
                      if (stock.isOutOfStock)
                        StatusChip(label: strings.outOfStockLabel)
                      else if (stock.isLowStock)
                        StatusChip(label: strings.lowStockLabel, tone: StatusTone.warning),
                      if (stock.hasExpiredStock(today))
                        StatusChip(label: strings.expiredLabel, tone: StatusTone.danger),
                    ],
                  ),
                ],
              ],
            ),
          ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: (stock?.isOutOfStock ?? true)
                      ? null
                      : () => ConsumeSheet.show(
                            context,
                            itemId: item.id,
                            unitCode: item.defaultDisplayUnitCode,
                            category: item.unitCategory,
                          ),
                  icon: const Icon(Icons.remove_circle_outline, size: AlayaIconSize.md),
                  label: Text(strings.actionConsume),
                ),
              ),
              const SizedBox(width: AlayaSpacing.xs),
              IconButton.filledTonal(
                onPressed: () => context.push(Routes.batchNew(item.id)),
                tooltip: strings.actionAddBatch,
                icon: const Icon(Icons.add, size: AlayaIconSize.md),
              ),
            ],
          ),
          ),
        ),
        SliverList.list(
          children: [
        SectionHeader(label: strings.detailSectionDetails),
        KeyValueRow(
          label: strings.labelItemKind,
          value: ItemKindLabel.of(strings, item.itemKind),
        ),
        KeyValueRow(
          label: strings.labelDisplayUnit,
          value: units[item.defaultDisplayUnitCode]?.displayName,
        ),
        KeyValueRow(
          label: strings.labelLowStockThreshold,
          valueWidget: threshold == null ? null : QtyText(threshold, muted: true),
        ),
        KeyValueRow(
          label: strings.labelExpiryNotifyDays,
          value: notifyDays == null ? null : strings.daysCount(notifyDays),
        ),
        KeyValueRow(
          label: strings.labelNearestExpiry,
          valueWidget: stock?.nearestExpiry == null
              ? null
              : DateText(stock!.nearestExpiry!, style: DateTextStyle.medium),
        ),
        KeyValueRow(label: strings.labelNote, value: item.notes),
        SectionHeader(label: strings.detailSectionBatches),
          ],
        ),
        batches.when(
          loading: () => SliverToBoxAdapter(
            child: AlayaListSkeleton(label: strings.loadingInventory, rows: 2),
          ),
          error: (error, stack) => SliverToBoxAdapter(
            child: ErrorState(
              title: strings.errorTitleGeneric,
              body: strings.errorBodyGeneric,
            ),
          ),
          data: (rows) => rows.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AlayaSpacing.screenEdge,
                      vertical: AlayaSpacing.xs,
                    ),
                    child: Text(
                      strings.emptyBodyNoBatches,
                      style: AlayaTypography.caption.copyWith(color: semantic.muted),
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AlayaSpacing.screenEdge,
                  ),
                  sliver: SliverList.separated(
                    itemCount: rows.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AlayaSpacing.xs),
                    itemBuilder: (context, index) {
                      final batch = rows[index];
                      return BatchCard(
                        batch: batch,
                        today: today,
                        onTap: () => context.push(Routes.batchEdit(item.id, batch.id)),
                        onHistory: () =>
                            context.push(Routes.batchHistory(item.id, batch.id)),
                      );
                    },
                  ),
                ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AlayaSpacing.screenEdge,
              AlayaSpacing.xxl,
              AlayaSpacing.screenEdge,
              AlayaSpacing.xxxl,
            ),
            child: TextButton(
              onPressed: () => onDelete(_batchCountOf(batches)),
              style: TextButton.styleFrom(foregroundColor: semantic.danger),
              child: Text(strings.actionDeleteItem),
            ),
          ),
        ),
      ],
    );
  }

  static int _batchCountOf(AsyncValue<List<Batch>> batches) =>
      batches.valueOrNull?.length ?? 0;
}
```

### `lib/features/inventory/presentation/screens/item_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/item_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';
import 'package:alaya/shared/widgets/unit_picker.dart';

/// The item editor (ARCH_5 §3 archetype B), routed outside the drawer shell (U18).
///
/// **`unitCategory` is a control while creating and a read-only row while editing.** Law L8 makes it
/// immutable after creation, and the row says why rather than leaving the user to discover that a
/// disabled dropdown exists: every batch and movement already recorded is stored in that measure, and
/// there is no conversion between weight, volume and count. Offering the control and then refusing
/// the change would be worse than not offering it.
class ItemEditorScreen extends ConsumerWidget {
  /// Edits [itemId], or creates a new item when it is null.
  const ItemEditorScreen({this.itemId, super.key});

  /// The item being edited, or null for a new one.
  final String? itemId;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(itemEditorProvider(itemId).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.actionSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(itemEditorProvider(itemId));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(itemId == null ? strings.editorTitleNew : strings.editorTitleEdit),
      ),
      body: async.when(
        loading: () => AlayaListSkeleton(label: strings.loadingLabel, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleNotFound,
          body: strings.errorBodyNotFound,
        ),
        data: (state) => AlayaFormScaffold(
          primaryLabel: strings.saveItem,
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: _Form(editorId: itemId, state: state),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.editorId, required this.state});

  final String? editorId;
  final ItemEditorState state;

  static String _categoryLabel(AlayaStrings strings, UnitCategory category) =>
      switch (category) {
        UnitCategory.weight => strings.unitCategoryWeight,
        UnitCategory.volume => strings.unitCategoryVolume,
        UnitCategory.count => strings.unitCategoryCount,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(itemEditorProvider(editorId).notifier);
    final units =
        ref.watch(unitsInCategoryProvider(state.unitCategory)).valueOrNull ?? const <Unit>[];
    Unit? selected;
    Unit? thresholdUnit;
    for (final unit in units) {
      if (unit.code == state.displayUnitCode) selected = unit;
      if (unit.code == state.thresholdUnitCode) thresholdUnit = unit;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.issue != null) ...[
          _IssueBanner(state: state),
          const SizedBox(height: AlayaSpacing.md),
        ],
        SectionHeader(
          label: strings.sectionWhatItIs,
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
        ),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: TextFormField(
            initialValue: state.name,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.labelItem,
              errorText: state.nameMissing ? strings.errorFieldRequired : null,
            ),
            onChanged: notifier.setName,
            onEditingComplete: notifier.refreshSimilar,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<ItemKind>(
          key: ValueKey(state.itemKind),
          initialValue: state.itemKind,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelItemKind),
          items: [
            for (final kind in ItemKind.values)
              DropdownMenuItem(value: kind, child: Text(ItemKindLabel.of(strings, kind))),
          ],
          onChanged: (value) => value == null ? null : notifier.setKind(value),
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (state.isEditing) ...[
          KeyValueRow(
            label: strings.labelCategory,
            value: strings.unitCategoryLocked(_categoryLabel(strings, state.unitCategory)),
            icon: Icons.lock_outline,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
            child: Text(
              strings.unitCategoryLockedHelp,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ),
        ] else
          DropdownButtonFormField<UnitCategory>(
            key: ValueKey(state.unitCategory),
            initialValue: state.unitCategory,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.labelCategory),
            items: [
              for (final category in UnitCategory.values)
                DropdownMenuItem(
                  value: category,
                  child: Text(_categoryLabel(strings, category)),
                ),
            ],
            onChanged: (value) => value == null
                ? null
                : notifier.setCategory(value, value.baseUnitCode),
          ),
        if (state.similarInOtherMeasures.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.itemSimilarNote,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],
        const SizedBox(height: AlayaSpacing.md),
        UnitPicker(
          category: state.unitCategory,
          units: units,
          selected: selected,
          label: strings.labelDisplayUnit,
          onChanged: notifier.setDisplayUnit,
        ),
        SectionHeader(
          label: strings.sectionStockRules,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        if (units.isNotEmpty)
          QtyField(
            category: state.unitCategory,
            units: units,
            selectedUnit: thresholdUnit ?? selected ?? units.first,
            label: strings.labelLowStockThreshold,
            unitLabel: strings.labelUnit,
            initialValue: state.lowStockThreshold,
            onChanged: notifier.setThreshold,
            onUnitChanged: notifier.setThresholdUnit,
          ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.expiryNotifyDays?.toString(),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: strings.labelExpiryNotifyDays,
            helperText: strings.expiryNotifyDaysHelp,
          ),
          onChanged: (raw) => notifier.setExpiryNotifyDays(int.tryParse(raw.trim())),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        SwitchListTile(
          value: state.isFavorite,
          contentPadding: EdgeInsets.zero,
          title: Text(strings.labelFavourite),
          secondary: Icon(
            state.isFavorite ? Icons.star : Icons.star_outline,
            size: AlayaIconSize.md,
            color: state.isFavorite ? semantic.warning : semantic.muted,
          ),
          onChanged: (_) => notifier.toggleFavourite(),
        ),
        SectionHeader(
          label: strings.labelNote,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        TextFormField(
          initialValue: state.notes,
          maxLines: 3,
          decoration: InputDecoration(hintText: strings.hintNote),
          onChanged: notifier.setNotes,
        ),
      ],
    );
  }
}

class _IssueBanner extends ConsumerWidget {
  const _IssueBanner({required this.state});

  final ItemEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final conflictId = state.conflictItemId;

    final message = switch (state.issue) {
      ItemSaveIssue.duplicate => strings.itemDuplicateBody,
      ItemSaveIssue.unitsMissing => strings.itemUnitsMissingBody,
      ItemSaveIssue.unknown || null => strings.errorBodyGeneric,
    };

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: AlayaIconSize.md, color: semantic.danger),
          const SizedBox(width: AlayaSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: AlayaTypography.body
                      .copyWith(color: Theme.of(context).colorScheme.onSurface),
                ),
                // The duplicate case is the only one with somewhere useful to go: the item they
                // already have. Offering to open it beats making them back out and search for it.
                if (state.issue == ItemSaveIssue.duplicate && conflictId != null) ...[
                  const SizedBox(height: AlayaSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () =>
                          context.pushReplacement(Routes.itemDetail(conflictId)),
                      child: Text(strings.actionOpenExisting),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/inventory/presentation/screens/batch_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/providers/batch_editor_providers.dart';
import 'package:alaya/features/inventory/providers/item_detail_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/batch_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// The batch editor (ARCH_5 §3 archetype B), routed outside the drawer shell (U18).
///
/// **Quantity is a field while creating and a read-only row while editing.** `remainingQuantity` is
/// the one cache the Laws permit (L3), reconciled from `stock_movements`; rewriting it from a form
/// would leave the cache and the ledger disagreeing with no movement to account for the difference.
/// Changing how much is left goes through the consume and adjust paths, which append movements.
class BatchEditorScreen extends ConsumerWidget {
  /// Edits [batchId] of [itemId], or adds a batch when [batchId] is null.
  const BatchEditorScreen({required this.itemId, this.batchId, super.key});

  /// Which item the batch belongs to.
  final String itemId;

  /// The batch being edited, or null for a new one.
  final String? batchId;

  BatchEditorArgs get _args => (itemId: itemId, batchId: batchId);

  Future<void> _delete(BuildContext context, WidgetRef ref, String id) async {
    final strings = AlayaStrings.of(context);
    // Consequential, not reversible (§5.5): `BatchRepository.delete` soft-deletes and the 3A
    // contract offers no restore, so the sheet names what leaves the on-hand total — and what does
    // not, because the movements stay (Law L6).
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.confirmDeleteBatchTitle,
      body: strings.confirmDeleteBatchBody,
      confirmLabel: strings.actionDeleteBatch,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(itemActionsProvider).deleteBatch(id);
    if (!context.mounted) return;
    if (!ok) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.batchDeleted);
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(batchEditorProvider(_args).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.batchSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(batchEditorProvider(_args));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(batchId == null ? strings.actionAddBatch : strings.editorTitleEdit),
      ),
      body: async.when(
        loading: () => AlayaListSkeleton(label: strings.loadingLabel, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleNotFound,
          body: strings.errorBodyNotFound,
        ),
        data: (state) => AlayaFormScaffold(
          primaryLabel: strings.saveBatch,
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Form(args: _args, state: state),
              if (state.isEditing) ...[
                const SizedBox(height: AlayaSpacing.xxl),
                TextButton(
                  onPressed: () => _delete(context, ref, state.id!),
                  style: TextButton.styleFrom(
                    foregroundColor: context.semantic.danger,
                  ),
                  child: Text(strings.actionDeleteBatch),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.args, required this.state});

  final BatchEditorArgs args;
  final BatchEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(batchEditorProvider(args).notifier);
    final item = ref.watch(batchOwnerProvider(state.itemId)).valueOrNull;
    final currency = ref.watch(batchCurrencyProvider).valueOrNull;
    final digits = ref.watch(batchDecimalDigitsProvider).valueOrNull ?? 2;
    final units = item == null
        ? const <Unit>[]
        : ref.watch(unitsInCategoryProvider(item.unitCategory)).valueOrNull ?? const <Unit>[];
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) => DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    Unit? selected;
    for (final unit in units) {
      if (unit.code == state.unitCode) selected = unit;
    }
    final quantity = state.quantity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: strings.sectionHowMuch,
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
        ),
        if (!state.quantityEditable)
          KeyValueRow(
            label: strings.labelInitial,
            valueWidget: quantity == null ? null : QtyText(quantity),
            icon: Icons.lock_outline,
          )
        else if (item != null && units.isNotEmpty)
          ShakeOnError(
            trigger: state.shakeTrigger,
            child: QtyField(
              category: item.unitCategory,
              units: units,
              selectedUnit: selected ?? units.first,
              label: strings.labelQuantity,
              unitLabel: strings.labelUnit,
              initialValue: quantity,
              errorText: state.quantityMissing ? strings.errorQuantityInvalid : null,
              onChanged: notifier.setQuantity,
              onUnitChanged: (unit) => notifier.setUnitCode(unit.code),
            ),
          ),
        if (!state.quantityEditable)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
            child: Text(
              strings.batchQuantityLockedHelp,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ),
        SectionHeader(
          label: strings.sectionBatchDetails,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        DatePickerField(
          value: state.purchasedDateKey,
          formatted: format,
          label: strings.labelPurchased,
          hint: strings.hintSelectDate,
          onChanged: notifier.setPurchased,
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.expiryDateKey,
          formatted: format,
          label: strings.labelExpiry,
          hint: strings.hintSelectDate,
          onChanged: notifier.setExpiry,
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (currency != null)
          AmountField(
            currencyCode: currency,
            decimalDigits: digits,
            label: strings.labelUnitCost,
            initialValue: state.unitCost,
            onChanged: notifier.setUnitCost,
          ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.storageLocation,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: strings.labelStorageLocation,
            hintText: strings.hintStorageLocation,
          ),
          onChanged: notifier.setStorageLocation,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.note,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: strings.labelNote,
            hintText: strings.hintNote,
          ),
          onChanged: notifier.setNote,
        ),
      ],
    );
  }
}
```

### `lib/features/inventory/presentation/sheets/consume_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/consume_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Takes stock off an item (ARCH_5 §3 archetype A).
///
/// **FEFO is pre-selected and named, not silent.** The sheet says which batch it will draw from and
/// offers the alternatives as chips, because "use some flour" and "use the jar that expires on
/// Tuesday" are the same gesture to the user and completely different rows in the ledger.
///
/// **A consume that spans batches says so before committing.** The preview walks the same FEFO
/// ordering the repository does and reports how many movements the write will append, so a user who
/// takes 3 kg from three 1 kg jars is told three entries are coming rather than discovering it in the
/// history afterwards.
///
/// Used, thrown away and expired are three distinct `StockMovementKind`s rather than one kind with a
/// reason, because Phase 7B's waste insight aggregates on the column and cannot read prose.
class ConsumeSheet extends ConsumerWidget {
  /// Creates the sheet.
  const ConsumeSheet({
    required this.itemId,
    required this.unitCode,
    required this.category,
    super.key,
  });

  /// Which item is being drawn down.
  final String itemId;

  /// The unit the quantity field starts in.
  final String unitCode;

  /// The item's measure, so the unit picker never offers a cross-category unit (Law L8).
  final UnitCategory category;

  /// Opens the sheet.
  static Future<void> show(
    BuildContext context, {
    required String itemId,
    required String unitCode,
    required UnitCategory category,
  }) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => ConsumeSheet(
          itemId: itemId,
          unitCode: unitCode,
          category: category,
        ),
      );

  static String _kindChipLabel(AlayaStrings strings, StockMovementKind kind) => switch (kind) {
        StockMovementKind.waste => strings.consumeKindWaste,
        StockMovementKind.expired => strings.consumeKindExpired,
        _ => strings.consumeKindConsume,
      };

  static String _commitLabel(AlayaStrings strings, StockMovementKind kind) => switch (kind) {
        StockMovementKind.waste => strings.consumeCommitWaste,
        StockMovementKind.expired => strings.consumeCommitExpired,
        _ => strings.consumeCommitUsed,
      };

  Future<void> _commit(BuildContext context, WidgetRef ref, ConsumeArgs args) async {
    final strings = AlayaStrings.of(context);
    final written = await ref.read(consumeProvider(args).notifier).commit();
    if (!context.mounted) return;
    if (written == null) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    Navigator.of(context).pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.consumeRecorded);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final args = (itemId: itemId, unitCode: unitCode);
    final state = ref.watch(consumeProvider(args));
    final notifier = ref.read(consumeProvider(args).notifier);
    final fefo = ref.watch(consumeFefoProvider(itemId));
    final units = ref.watch(unitsInCategoryProvider(category)).valueOrNull ?? const <Unit>[];

    Unit? selected;
    for (final unit in units) {
      if (unit.code == state.unitCode) selected = unit;
    }

    final batches = fefo.valueOrNull ?? const <Batch>[];
    final plan = state.planAgainst(batches);
    final shortfall = state.shortfallAgainst(batches);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.consumeTitle,
          style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (units.isNotEmpty)
          ShakeOnError(
            trigger: state.shakeTrigger,
            child: QtyField(
              category: category,
              units: units,
              selectedUnit: selected ?? units.first,
              label: strings.labelQuantity,
              unitLabel: strings.labelUnit,
              initialValue: state.quantity,
              errorText: state.quantityMissing
                  ? strings.errorQuantityInvalid
                  : shortfall != null
                      ? strings.consumeOverAvailable
                      : null,
              onChanged: notifier.setQuantity,
              onUnitChanged: (unit) => notifier.setUnitCode(unit.code),
            ),
          ),
        const SizedBox(height: AlayaSpacing.md),
        // **Chips above 1.5x, a segmented button below it.** `SegmentedButton` lays its segments out
        // in a Row that cannot wrap, so three labels at a doubled text scale overflow 320dp by about
        // 50px. A `Wrap` of `ChoiceChip`s is the same choice with the same semantics and reflows
        // instead of clipping (Law U15).
        if (MediaQuery.textScalerOf(context).scale(1) >= 1.5)
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              for (final option in const [
                StockMovementKind.consume,
                StockMovementKind.waste,
                StockMovementKind.expired,
              ])
                ChoiceChip(
                  selected: state.kind == option,
                  onSelected: (_) => notifier.setKind(option),
                  label: Text(_kindChipLabel(strings, option)),
                ),
            ],
          )
        else
          SegmentedButton<StockMovementKind>(
            segments: [
              ButtonSegment(
                value: StockMovementKind.consume,
                label: Text(strings.consumeKindConsume),
              ),
              ButtonSegment(
                value: StockMovementKind.waste,
                label: Text(strings.consumeKindWaste),
              ),
              ButtonSegment(
                value: StockMovementKind.expired,
                label: Text(strings.consumeKindExpired),
              ),
            ],
            selected: {state.kind},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => notifier.setKind(selection.first),
          ),
        const SizedBox(height: AlayaSpacing.md),
        _BatchChips(
          batches: batches,
          state: state,
          plan: plan,
          onPick: notifier.setBatch,
        ),
        if (plan.length > 1 || (plan.length == 1 && !state.isOverridden)) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(
              label: strings.consumeSpansBatches(plan.length),
              tone: plan.length > 1 ? StatusTone.info : StatusTone.neutral,
            ),
          ),
        ],
        if (state.kind != StockMovementKind.consume) ...[
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.reason,
            decoration: InputDecoration(
              labelText: strings.labelNote,
              hintText: strings.deleteReasonHint,
            ),
            onChanged: notifier.setReason,
          ),
        ],
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          // Blocked rather than warned (§5.5): the repository would refuse a draw larger than the
          // batches hold, and a button that fails on press teaches the user the app is unreliable.
          onPressed: state.submitting || shortfall != null
              ? null
              : () => _commit(context, ref, args),
          // States the action rather than "Record" (U14), and does it from one ARB key per kind so no
          // separator glyph is glued on in code.
          child: Text(_commitLabel(strings, state.kind)),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionCancel),
        ),
        if (fefo.hasError)
          Padding(
            padding: const EdgeInsets.only(top: AlayaSpacing.xs),
            child: Text(
              strings.errorBodyGeneric,
              style: AlayaTypography.caption.copyWith(color: semantic.danger),
            ),
          ),
      ],
    );
  }
}

class _BatchChips extends StatelessWidget {
  const _BatchChips({
    required this.batches,
    required this.state,
    required this.plan,
    required this.onPick,
  });

  final List<Batch> batches;
  final ConsumeState state;
  final List<ConsumePlanLeg> plan;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    if (batches.isEmpty) return const SizedBox.shrink();

    final fefoId = plan.isEmpty ? batches.first.id : plan.first.batch.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.consumeFromLabel,
          style: AlayaTypography.label.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final batch in batches)
              ChoiceChip(
                selected: state.isOverridden
                    ? state.overrideBatchId == batch.id
                    : batch.id == fefoId,
                onSelected: (_) =>
                    onPick(state.overrideBatchId == batch.id ? null : batch.id),
                label: _BatchChipLabel(batch: batch),
              ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        Text(
          strings.consumeFefoNote,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
      ],
    );
  }
}

class _BatchChipLabel extends StatelessWidget {
  const _BatchChipLabel({required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final expiry = batch.expiryDateKey;
    // A `Wrap`, not a `Row`. A chip constrains its label, and at a doubled text scale a quantity plus
    // a date is about 50px wider than the chip allows — the last overflow left in this sheet after the
    // segmented button was fixed (Law U21).
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AlayaSpacing.xxs,
      children: [
        QtyText(batch.remainingQuantity),
        if (expiry != null)
          DateText(expiry, style: DateTextStyle.dayMonth, muted: true),
      ],
    );
  }
}
```

### `lib/features/inventory/presentation/screens/batch_history_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/features/inventory/providers/batch_history_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';

/// One batch's movement timeline (ARCH_5 §3 archetype C), routed outside the drawer shell (U18).
///
/// **Nothing here can be edited, only reversed.** `stock_movements` is append-only (Law L6): a
/// correction is a new movement pointing back at the one it undoes, and the timeline strikes the
/// original through rather than removing it. Both rows stay, which is the only way the remaining
/// quantity a batch reports can be reconciled against the reasons it changed.
class BatchHistoryScreen extends ConsumerWidget {
  /// Shows the history of [batchId], which belongs to [itemId].
  const BatchHistoryScreen({required this.itemId, required this.batchId, super.key});

  /// The owning item, carried so the route stays hierarchical.
  final String itemId;

  /// Which batch's movements to show.
  final String batchId;

  static String _kindLabel(AlayaStrings strings, StockMovementKind kind) => switch (kind) {
        StockMovementKind.openingIn => strings.movementKindOpeningIn,
        StockMovementKind.purchaseIn => strings.movementKindPurchaseIn,
        StockMovementKind.manualIn => strings.movementKindManualIn,
        StockMovementKind.consume => strings.movementKindConsume,
        StockMovementKind.waste => strings.movementKindWaste,
        StockMovementKind.expired => strings.movementKindExpired,
        StockMovementKind.adjustIn => strings.movementKindAdjustIn,
        StockMovementKind.adjustOut => strings.movementKindAdjustOut,
      };

  Future<void> _reverse(BuildContext context, WidgetRef ref, String movementId) async {
    final strings = AlayaStrings.of(context);
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.confirmReverseTitle,
      body: strings.confirmReverseBody,
      confirmLabel: strings.actionReverse,
      cancelLabel: strings.actionCancel,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(movementActionsProvider).reverse(movementId);
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.movementReversedSnack)
        : showFailureSnack(context, message: strings.errorBodyGeneric);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final movements = ref.watch(batchMovementsProvider(batchId));
    final reversed = ref.watch(reversedMovementIdsProvider(batchId));

    return Scaffold(
      appBar: AppBar(title: Text(strings.historyTitle)),
      body: movements.when(
        loading: () => AlayaListSkeleton(label: strings.loadingInventory),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: strings.errorBodyGeneric,
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(batchMovementsProvider(batchId)),
        ),
        data: (rows) => rows.isEmpty
            ? EmptyState(
                title: strings.emptyTitleNoMovements,
                body: strings.emptyBodyNoMovements,
                icon: Icons.history,
              )
            : CustomScrollView(
                slivers: [
                  AlayaTimeline(
                    itemCount: rows.length,
                    itemBuilder: (context, index) => _entryFor(
                      context: context,
                      ref: ref,
                      strings: strings,
                      movement: rows[index],
                      isReversed: reversed.contains(rows[index].id),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AlayaSpacing.xxxl),
                  ),
                ],
              ),
      ),
    );
  }

  AlayaTimelineEntry _entryFor({
    required BuildContext context,
    required WidgetRef ref,
    required AlayaStrings strings,
    required StockMovement movement,
    required bool isReversed,
  }) {
    final isReversal = movement.reversesMovementId != null;
    final tone = isReversed
        ? TimelineTone.superseded
        : movement.isIncoming
            ? TimelineTone.incoming
            : TimelineTone.outgoing;

    return AlayaTimelineEntry(
      title: _kindLabel(strings, movement.kind),
      trailing: QtyText(movement.quantity, muted: isReversed),
      subtitle: DateText(movement.dateKey, style: DateTextStyle.medium, muted: true),
      meta: movement.reason ?? movement.note,
      icon: movement.isIncoming ? Icons.south_west : Icons.north_east,
      tone: tone,
      badge: isReversed
          ? strings.movementReversed
          : isReversal
              ? strings.movementIsReversal
              : null,
      onTap: isReversed || isReversal
          ? null
          : () => _reverse(context, ref, movement.id),
    );
  }
}
```

### `test/support/inventory_harness.dart`

```dart
/// Shared scaffolding for the Inventory module's widget tests.
///
/// Overrides the feature's view-model providers rather than faking every repository: a widget test's
/// job is the widget — four states, a doubled text scale, the tap-target floor (ARCH_5 §9.1).
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
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/entities/unit.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so relative dates are the same on every machine.
final Clock kInventoryClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kInventoryClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// Grams.
const Unit kGram = Unit(
  code: 'g',
  category: UnitCategory.weight,
  factorToBaseMilli: 1000,
  displayName: 'gram',
  isSystem: true,
  sortOrder: 0,
);

/// Kilograms.
const Unit kKilogram = Unit(
  code: 'kg',
  category: UnitCategory.weight,
  factorToBaseMilli: 1000000,
  displayName: 'kilogram',
  isSystem: true,
  sortOrder: 1,
);

/// A sample item measured by weight.
const Item kItem = Item(
  id: 'item-1',
  name: 'Atta',
  normalizedName: 'atta',
  unitCategory: UnitCategory.weight,
  defaultDisplayUnitCode: 'kg',
  itemKind: ItemKind.food,
  isFavorite: true,
);

/// The mixed-unit total ARCH_1 §5.4 uses as its worked example: 250 + 2000 + 1500 + 700 = 4 kg 450 g.
const Qty kFourKilo450 = Qty(4450000, UnitCategory.weight);

/// Stock on hand for [kItem].
const ItemStock kStock = ItemStock(
  itemId: 'item-1',
  totalRemaining: kFourKilo450,
  batchCount: 4,
  isLowStock: false,
  nearestExpiry: DateKey(20260810),
);

/// A sample batch.
Batch sampleBatch({
  String id = 'batch-1',
  int remainingMilli = 2000000,
  BatchOrigin origin = BatchOrigin.purchase,
  DateKey? expiry = const DateKey(20260810),
  String? location = 'Pantry',
}) =>
    Batch(
      id: id,
      itemId: kItem.id,
      initialQuantity: const Qty(2000000, UnitCategory.weight),
      remainingQuantity: Qty(remainingMilli, UnitCategory.weight),
      unitCodeAtPurchase: 'kg',
      purchasedDateKey: const DateKey(20260715),
      origin: origin,
      expiryDateKey: expiry,
      unitCost: const Money(4500, 'INR'),
      storageLocation: location,
    );

/// A sample movement.
StockMovement sampleMovement({
  String id = 'mv-1',
  StockMovementKind kind = StockMovementKind.consume,
  String? reverses,
  String? reason,
}) =>
    StockMovement(
      id: id,
      batchId: 'batch-1',
      itemId: kItem.id,
      kind: kind,
      quantity: const Qty(500000, UnitCategory.weight),
      occurredAtUtc: DateTime.utc(2026, 8, 1, 4),
      dateKey: kToday,
      reason: reason,
      reversesMovementId: reverses,
    );

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
///
/// The `MediaQuery` sits inside `MaterialApp.builder` because `WidgetsApp` re-establishes it from the
/// view, so an outer override never reaches the widget under test.
Future<void> pumpInventory(
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

### `test/features/inventory/inventory_list_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/widgets/item_row.dart';
import 'package:alaya/features/inventory/providers/inventory_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/inventory_harness.dart';

/// Four states, 320dp at a doubled text scale, and both accessibility floors (ARCH_5 §9.1).
void main() {
  List<Override> overrides(AsyncValue<List<InventoryGroup>> groups) => [
        clockProvider.overrideWithValue(kInventoryClock),
        inventoryGroupsProvider.overrideWith((ref) => groups),
        itemStocksProvider.overrideWith(
          (ref) => Stream.value(<String, ItemStock>{kItem.id: kStock}),
        ),
        lowStockCountProvider.overrideWith((ref) => 0),
      ];

  final populated = AsyncValue.data([
    InventoryGroup(items: const [kItem], kind: kItem.itemKind),
  ]);

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty invites the user to add rather than reporting emptiness', (tester) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(const AsyncValue.data([])),
    );
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Add item'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(AsyncValue.error(StateError('boom'), StackTrace.empty)),
    );
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('populated renders a row showing the summed mixed-unit total', (tester) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(populated),
    );
    expect(find.byType(ItemRow), findsOneWidget);
    expect(find.text('Atta'), findsOneWidget);
    // ARCH_1 §5.4's worked example: 250 + 2000 + 1500 + 700 grams is 4 kg 450 g, not 2 kg 450 g.
    expect(find.text('4 kg 450 g'), findsOneWidget);
  });

  testWidgets('the group header names the kind, not the table', (tester) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(populated),
    );
    expect(find.text('Food'), findsOneWidget);
  });

  testWidgets('search is a pinned field, never an app-bar icon', (tester) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(populated),
    );
    expect(find.text('Search items'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.search)),
      findsNothing,
    );
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(populated),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpInventory(
      tester,
      const InventoryListScreen(),
      overrides: overrides(populated),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/inventory/item_detail_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/presentation/screens/item_detail_screen.dart';
import 'package:alaya/features/inventory/presentation/widgets/batch_card.dart';
import 'package:alaya/features/inventory/providers/item_detail_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';

import '../../support/inventory_harness.dart';

/// Four states, plus the two rules this screen exists to demonstrate: the hero is the summed total,
/// and a detached batch explains itself.
void main() {
  const id = 'item-1';

  List<Override> overrides({
    Item? item = kItem,
    List<Batch> batches = const [],
    bool pendingItem = false,
    bool failItem = false,
  }) =>
      [
        clockProvider.overrideWithValue(kInventoryClock),
        // `itemByIdProvider` is a synchronous `Provider<AsyncValue<Item?>>` derived from the
        // catalogue stream, so each state is handed over directly rather than as a Future.
        if (pendingItem)
          itemByIdProvider(id).overrideWith((ref) => const AsyncValue.loading())
        else if (failItem)
          itemByIdProvider(id).overrideWith(
            (ref) => AsyncValue.error(StateError('boom'), StackTrace.empty),
          )
        else
          itemByIdProvider(id).overrideWith((ref) => AsyncValue.data(item)),
        itemStockProvider(id).overrideWith((ref) => Stream.value(kStock)),
        itemBatchesProvider(id).overrideWith((ref) => Stream.value(batches)),
        detailUnitsByCodeProvider.overrideWith(
          (ref) => Stream.value(<String, Unit>{'kg': kKilogram, 'g': kGram}),
        ),
      ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(pendingItem: true),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('a missing item reads as not found, not as a crash', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(item: null),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Not found'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(failItem: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('the hero is the summed mixed-unit total across every batch', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(batches: [sampleBatch()]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Atta'), findsOneWidget);
    expect(find.text('4 kg 450 g'), findsOneWidget);
    expect(find.byType(BatchCard), findsOneWidget);
  });

  testWidgets('a null value hides its row rather than rendering a dash', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(batches: [sampleBatch()]),
    );
    await tester.pumpAndSettle();
    // kItem has no notes and no low-stock threshold, so neither row exists at all.
    expect(find.text('Note'), findsNothing);
    expect(find.text('Low-stock level'), findsNothing);
    expect(find.byType(KeyValueRow), findsWidgets);
  });

  testWidgets('a detached batch says the receipt is gone', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(
        batches: [sampleBatch(origin: BatchOrigin.detached)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Receipt deleted'), findsOneWidget);
  });

  testWidgets('the destructive action is present and is not a filled button', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(batches: [sampleBatch()]),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Delete item'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Delete item'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Delete item'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(batches: [sampleBatch()]),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpInventory(
      tester,
      const ItemDetailScreen(itemId: id),
      overrides: overrides(batches: [sampleBatch()]),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/inventory/item_editor_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/presentation/screens/item_editor_screen.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/item_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';

import '../../support/inventory_harness.dart';

/// Four states, plus the Law this screen exists to enforce: `unitCategory` is read-only on edit.
void main() {
  ItemEditorState seed({String? id}) => ItemEditorState(
        id: id,
        name: id == null ? '' : 'Atta',
        unitCategory: UnitCategory.weight,
        displayUnitCode: 'kg',
      );

  // The override goes on the **family**, not on an instance of it: a NotifierProvider family
  // instance has no `overrideWith`, unlike a FutureProvider or StreamProvider instance.
  List<Override> overrides(AsyncValue<ItemEditorState> state) => [
        itemEditorProvider.overrideWith(() => _StubEditor(state)),
        unitsInCategoryProvider(UnitCategory.weight)
            .overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
      ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('error reads as not found rather than as a blank form', (tester) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(AsyncValue.error(StateError('boom'), StackTrace.empty)),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new item opens on the form, which is its empty state', (tester) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save item'), findsOneWidget);
  });

  testWidgets('creating offers the measure as a control', (tester) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(find.byType(DropdownButtonFormField<UnitCategory>), findsOneWidget);
    expect(find.byType(KeyValueRow), findsNothing);
  });

  testWidgets('editing locks the measure and says why', (tester) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(itemId: 'item-1'),
      overrides: [
        itemEditorProvider.overrideWith(() => _StubEditor(AsyncValue.data(seed(id: 'item-1')))),
        unitsInCategoryProvider(UnitCategory.weight)
            .overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
      ],
    );
    // Law L8: no control at all, not a disabled one — and the reason is on screen, because a lock
    // without an explanation reads as a bug.
    expect(find.byType(DropdownButtonFormField<UnitCategory>), findsNothing);
    expect(find.text('Measured in Weight'), findsOneWidget);
    expect(
      find.textContaining('no conversion between weight, volume and count'),
      findsOneWidget,
    );
  });

  testWidgets('the commit lives in the footer, never in the app bar', (tester) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(TextButton, 'Save item'),
      ),
      findsNothing,
    );
    expect(find.byType(CloseButton), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpInventory(
      tester,
      const ItemEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubEditor extends ItemEditorNotifier {
  _StubEditor(this._state);

  final AsyncValue<ItemEditorState> _state;

  @override
  AsyncValue<ItemEditorState> build(String? arg) => _state;
}
```

### `test/features/inventory/batch_editor_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_editor_screen.dart';
import 'package:alaya/features/inventory/providers/batch_editor_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/batch_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_field.dart';

import '../../support/inventory_harness.dart';

/// Four states, plus Law L3: an existing batch's quantity is a derived cache, not a form field.
void main() {
  BatchEditorState seed({String? id}) => BatchEditorState(
        id: id,
        itemId: kItem.id,
        unitCode: 'kg',
        purchasedDateKey: kToday,
        quantity: id == null ? null : const Qty(2000000, UnitCategory.weight),
      );

  List<Override> overrides(AsyncValue<BatchEditorState> state) => [
        batchEditorProvider.overrideWith(() => _StubBatchEditor(state)),
        batchOwnerProvider(kItem.id).overrideWith((ref) async => kItem),
        batchCurrencyProvider.overrideWith((ref) async => 'INR'),
        batchDecimalDigitsProvider.overrideWith((ref) async => 2),
        unitsInCategoryProvider(UnitCategory.weight)
            .overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
      ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('error reads as not found', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(AsyncValue.error(StateError('boom'), StackTrace.empty)),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('adding a batch opens on the form with every §7.2 field', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(AsyncValue.data(seed())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.byType(QtyField), findsOneWidget);
    expect(find.text('Expiry'), findsOneWidget);
    expect(find.text('Purchased'), findsOneWidget);
    expect(find.text('Unit cost'), findsOneWidget);
    expect(find.text('Stored in'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save batch'), findsOneWidget);
  });

  testWidgets('editing locks the quantity and says the ledger owns it', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id, batchId: 'batch-1'),
      overrides: overrides(AsyncValue.data(seed(id: 'batch-1'))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(QtyField), findsNothing);
    expect(find.byType(KeyValueRow), findsOneWidget);
    expect(
      find.textContaining('worked out from the movement history'),
      findsOneWidget,
    );
  });

  testWidgets('editing offers a retire path; adding does not', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id, batchId: 'batch-1'),
      overrides: overrides(AsyncValue.data(seed(id: 'batch-1'))),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Delete batch'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Delete batch'), findsNothing);

    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(AsyncValue.data(seed())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete batch'), findsNothing);
  });

  testWidgets('the commit lives in the footer', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(AsyncValue.data(seed())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CloseButton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(TextButton, 'Save batch'),
      ),
      findsNothing,
    );
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(AsyncValue.data(seed())),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpInventory(
      tester,
      BatchEditorScreen(itemId: kItem.id),
      overrides: overrides(AsyncValue.data(seed())),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}

/// A notifier reporting a fixed state.
class _StubBatchEditor extends BatchEditorNotifier {
  _StubBatchEditor(this._state);

  final AsyncValue<BatchEditorState> _state;

  @override
  AsyncValue<BatchEditorState> build(BatchEditorArgs arg) => _state;
}
```

### `test/features/inventory/consume_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/consume_state.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/inventory_harness.dart';

/// The capture path's contract: one required field, FEFO named and overridable, and a multi-batch
/// draw declared before it is committed.
void main() {
  List<Override> overrides({List<Batch> fefo = const []}) => [
        consumeFefoProvider(kItem.id).overrideWith((ref) => Stream.value(fefo)),
        unitsInCategoryProvider(UnitCategory.weight)
            .overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
      ];

  Widget host() => Scaffold(
        body: AlayaBottomSheet(
          child: ConsumeSheet(
            itemId: kItem.id,
            unitCode: 'kg',
            category: UnitCategory.weight,
          ),
        ),
      );

  testWidgets('renders with exactly one required field', (tester) async {
    await pumpInventory(tester, host(), overrides: overrides());
    expect(find.byType(QtyField), findsOneWidget);
    expect(find.text('Use stock'), findsOneWidget);
  });

  testWidgets('offers used, thrown away and expired as three distinct kinds', (tester) async {
    await pumpInventory(tester, host(), overrides: overrides());
    // Three `StockMovementKind`s, not one kind plus a reason string: Phase 7B's waste insight
    // aggregates on the column and cannot read prose.
    expect(find.text('Used'), findsOneWidget);
    expect(find.text('Thrown away'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
  });

  testWidgets('an empty batch list simply omits the chip row', (tester) async {
    await pumpInventory(tester, host(), overrides: overrides());
    expect(find.text('Taking from'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FEFO names the batch it will draw from and offers the rest', (tester) async {
    await pumpInventory(
      tester,
      host(),
      overrides: overrides(
        fefo: [
          sampleBatch(id: 'b1', expiry: const DateKey(20260805)),
          sampleBatch(id: 'b2', expiry: const DateKey(20260901)),
        ],
      ),
    );
    expect(find.text('Taking from'), findsOneWidget);
    expect(find.text('Oldest expiry first.'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
  });

  testWidgets('committing with no quantity shakes and says why', (tester) async {
    await pumpInventory(tester, host(), overrides: overrides(fefo: [sampleBatch()]));
    final before = tester.widget<ShakeOnError>(find.byType(ShakeOnError)).trigger;

    await tester.tap(find.text('Record as used'));
    await tester.pump();

    final after = tester.widget<ShakeOnError>(find.byType(ShakeOnError)).trigger;
    expect(after, greaterThan(before));
    expect(find.text('Enter a quantity'), findsOneWidget);
  });

  testWidgets('a draw spanning batches is declared before it is committed', (tester) async {
    // Three 1 kg jars and a 2.5 kg draw: the plan crosses three batches, so three movements will be
    // appended and the sheet must say so up front rather than in the history afterwards.
    final container = ProviderContainer(
      overrides: [
        unitsInCategoryProvider(UnitCategory.weight)
            .overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
      ],
    );
    addTearDown(container.dispose);

    const state = ConsumeState(
      itemId: 'item-1',
      unitCode: 'kg',
      quantity: Qty(2500000, UnitCategory.weight),
    );
    final jars = [
      sampleBatch(id: 'b1', remainingMilli: 1000000),
      sampleBatch(id: 'b2', remainingMilli: 1000000),
      sampleBatch(id: 'b3', remainingMilli: 1000000),
    ];

    final plan = state.planAgainst(jars);
    expect(plan, hasLength(3));
    expect(plan.last.quantity, const Qty(500000, UnitCategory.weight));
    expect(state.shortfallAgainst(jars), isNull);
  });

  testWidgets('a draw larger than the shelf reports a shortfall', (tester) async {
    const state = ConsumeState(
      itemId: 'item-1',
      unitCode: 'kg',
      quantity: Qty(5000000, UnitCategory.weight),
    );
    final jars = [sampleBatch(id: 'b1', remainingMilli: 1000000)];
    expect(state.shortfallAgainst(jars), const Qty(4000000, UnitCategory.weight));
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      host(),
      overrides: overrides(fefo: [sampleBatch()]),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target floor', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpInventory(tester, host(), overrides: overrides(fefo: [sampleBatch()]));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('loading leaves the required field usable', (tester) async {
    await pumpInventory(
      tester,
      host(),
      overrides: [
        consumeFefoProvider(kItem.id).overrideWith((ref) => pendingStream<List<Batch>>()),
        unitsInCategoryProvider(UnitCategory.weight)
            .overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
      ],
    );
    // A capture sheet takes its first keystroke on its first frame (§5.2): the batch list is still
    // arriving, and the quantity field is already there.
    expect(find.byType(QtyField), findsOneWidget);
    expect(find.text('Taking from'), findsNothing);
  });

  testWidgets('a failed batch stream says so without blocking capture', (tester) async {
    await pumpInventory(
      tester,
      host(),
      overrides: [
        consumeFefoProvider(kItem.id)
            .overrideWith((ref) => Stream<List<Batch>>.error(StateError('boom'))),
        unitsInCategoryProvider(UnitCategory.weight)
            .overrideWith((ref) => Stream.value(<Unit>[kKilogram, kGram])),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong on our side. Try again.'), findsOneWidget);
    expect(find.byType(QtyField), findsOneWidget);
  });

  testWidgets('every target is labelled', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpInventory(tester, host(), overrides: overrides(fefo: [sampleBatch()]));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/inventory/batch_history_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_history_screen.dart';
import 'package:alaya/features/inventory/providers/batch_history_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/inventory_harness.dart';

/// Four states, plus the append-only rule: a reversal marks the original rather than removing it.
void main() {
  const batchId = 'batch-1';

  List<Override> overrides({
    List<StockMovement>? movements,
    bool pending = false,
    bool fail = false,
  }) =>
      [
        if (pending)
          batchMovementsProvider(batchId)
              .overrideWith((ref) => pendingStream<List<StockMovement>>())
        else if (fail)
          batchMovementsProvider(batchId)
              .overrideWith((ref) => Stream.error(StateError('boom')))
        else
          batchMovementsProvider(batchId)
              .overrideWith((ref) => Stream.value(movements ?? const [])),
      ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(pending: true),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('empty explains what will appear here', (tester) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing recorded yet'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(fail: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('populated renders a timeline naming each movement kind', (tester) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(
        movements: [
          sampleMovement(id: 'mv-2', kind: StockMovementKind.waste, reason: 'Mouldy'),
          sampleMovement(kind: StockMovementKind.purchaseIn),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaTimeline), findsOneWidget);
    expect(find.text('Thrown away'), findsOneWidget);
    expect(find.text('Bought'), findsOneWidget);
    expect(find.text('Mouldy'), findsOneWidget);
  });

  testWidgets('a reversed movement is marked, and both rows stay', (tester) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(
        movements: [
          sampleMovement(id: 'mv-2', kind: StockMovementKind.adjustIn, reverses: 'mv-1'),
          sampleMovement(),
        ],
      ),
    );
    await tester.pumpAndSettle();
    // `stock_movements` is append-only (Law L6): the correction points back, the original is struck
    // through, and neither is erased.
    expect(find.text('Reversed'), findsOneWidget);
    expect(find.text('Reverses an earlier movement'), findsOneWidget);
    expect(find.text('Used'), findsOneWidget);
    expect(find.text('Adjusted up'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(
        movements: [
          sampleMovement(id: 'mv-2', kind: StockMovementKind.waste, reason: 'Left out overnight'),
          sampleMovement(),
        ],
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpInventory(
      tester,
      const BatchHistoryScreen(itemId: 'item-1', batchId: batchId),
      overrides: overrides(movements: [sampleMovement()]),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/shared/golden/timeline_golden_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/qty_text.dart';

/// Goldens for the one shared widget Phase 6B adds (ARCH_5 §9.2), light and dark.
void main() {
  final entries = [
    const AlayaTimelineEntry(
      title: 'Thrown away',
      trailing: QtyText(Qty(500000, UnitCategory.weight)),
      subtitle: DateText(DateKey(20260801), style: DateTextStyle.medium, muted: true),
      meta: 'Mouldy',
      icon: Icons.north_east,
      tone: TimelineTone.outgoing,
      badge: 'Reversed',
    ),
    const AlayaTimelineEntry(
      title: 'Used',
      trailing: QtyText(Qty(250000, UnitCategory.weight)),
      subtitle: DateText(DateKey(20260729), style: DateTextStyle.medium, muted: true),
      icon: Icons.north_east,
      tone: TimelineTone.superseded,
    ),
    const AlayaTimelineEntry(
      title: 'Bought',
      trailing: QtyText(Qty(2000000, UnitCategory.weight)),
      subtitle: DateText(DateKey(20260715), style: DateTextStyle.medium, muted: true),
      icon: Icons.south_west,
      tone: TimelineTone.incoming,
    ),
  ];

  Future<void> pumpTimeline(WidgetTester tester, {required bool dark}) async {
    tester.view.physicalSize = const Size(360, 400) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark
            ? AlayaTheme.dark(AlayaPresets.activePreset)
            : AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              AlayaTimeline(
                itemCount: entries.length,
                itemBuilder: (context, index) => entries[index],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AlayaTimeline', () {
    testWidgets('light', (tester) async {
      await pumpTimeline(tester, dark: false);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/alaya_timeline.light.png'),
      );
    });

    testWidgets('dark', (tester) async {
      await pumpTimeline(tester, dark: true);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/alaya_timeline.dark.png'),
      );
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

## COVERAGE — ARCH_5 §7 rows closed by Phase 6B

### §7.1 By table

| Row | Create | Read | Edit | Retire |
|---|---|---|---|---|
| `items` | item editor | catalogue list · item detail | item editor | `ItemActions.delete` — `ConfirmSheet` naming the batches that go with it |
| `inventory_batches` | batch editor | item detail batch list | batch editor *(metadata only — L3)* | batch editor's destructive action |
| `stock_movements` | consume sheet — used · thrown away · expired | batch history timeline | — *(append-only, L6)* | `MovementActions.reverse`, appended not erased |

### §7.2 Columns most likely to be stranded

| Column | Where a user sees it |
|---|---|
| `items.expiryNotifyDays` | Item editor field with a helper line; item detail `KeyValueRow` as "7 days" |
| `items.isFavorite` | Star on the catalogue row, a switch in the editor, a favourites-only filter chip, and a favourites-first grouping |
| `items.lowStockThresholdMilli` | Item editor `QtyField`; the `Low` chip on the row and the hero; a counted `Low · 3` filter chip |
| `inventory_batches.origin = detached` | `StatusChip` on the batch card reading **"Receipt deleted"**, warning-toned with a broken-link glyph |
| `inventory_batches.storageLocation` | Batch editor field; batch card metadata line |
| `stock_movements.reversesMovementId` | Timeline badge — the reversal reads "Reverses an earlier movement", the original is struck through and badged "Reversed" |
| `stock_movements.kind = waste \| expired` | Three segments in the consume sheet, three `StockMovementKind`s, three commit labels |

### §7.3 Deferred — with the contract each waits on

| Row | Why it cannot close in 6B | Owner |
|---|---|---|
| `item_tags` | **The table exists; the contract does not.** `ItemTags(itemId, tagId, createdAt)` is in `lib/data/db/tables/tag_tables.dart`, so this is a three-layer addition and not a migration: `TagDao.watchForItem` + `setItemTags` mirroring the existing `watchForTransaction` + `setTransactionTags`; `TagRepositoryImpl` forwarding them; `TagRepository.watchForItem(String itemId)` and `setForItem({required String itemId, required List<String> tagIds})` on the contract. U19 forbids a feature layer declaring it, so it cannot be done from inside 6B. Once landed, the UI is a `TagPicker` in the item editor, chips on `ItemRow`, and a third `InventoryGroupBy.tag` — the group-by control already carries two axes for exactly this reason. | **2C/3A/3D addendum**, then 6B follow-up |
| Grouping the catalogue by tag | Same missing contract. Grouping is by `items.itemKind` — a real axis on the entity, set by the user in the editor. | as above |
| `ItemRepository.findByIdentity` / `findSimilar` | Built in Phase 3A, surfaced nowhere. These are the duplicate guards: the item editor and the line editor's inline create should both warn "you already have Atta measured by weight" before writing a second row. The inline create in Part 0 makes this more pressing, not less. | **6B follow-up** |
| Adjust up / down (`adjustIn`, `adjustOut`) | `StockRepository.addStock` exists and is unused here. The consume sheet covers the three outward kinds it was specified for; a stock-correction path is a fourth capture surface with its own reconciliation story. | **6B follow-up or 8A** alongside `recompute()` |
| `BatchRepository.watchReconciliation` / `recompute` | The L3 cache-repair surface. It belongs with the diagnostics screen, not the catalogue. | **8A** |
