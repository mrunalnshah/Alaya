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
import 'package:alaya/features/expense/state/split_draft.dart';
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
    .family<
      TransactionEditorNotifier,
      AsyncValue<TransactionEditorState>,
      String?
    >(
      TransactionEditorNotifier.new,
    );

/// Loads, edits and saves one transaction.
class TransactionEditorNotifier
    extends
        AutoDisposeFamilyNotifier<AsyncValue<TransactionEditorState>, String?> {
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
      final tags = await _firstOrEmpty(
        ref.read(tagRepositoryProvider).watchForTransaction(id),
      );
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
      fromAccountId: kind == TransactionKind.deposit
          ? null
          : s.fromAccountId ?? s.toAccountId,
      clearFromAccount: kind == TransactionKind.deposit,
      toAccountId: kind == TransactionKind.deposit
          ? s.toAccountId ?? s.fromAccountId
          : null,
      clearToAccount: kind == TransactionKind.withdrawal,
    );
  });

  /// Switches the visible sub-form.
  void setSubtype(TransactionSubtype subtype) =>
      _edit((s) => s.copyWith(subtype: subtype));

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
    (s) => id == null
        ? s.copyWith(clearFromAccount: true)
        : s.copyWith(fromAccountId: id),
  );

  /// Sets the destination account.
  void setToAccount(String? id) => _edit(
    (s) => id == null
        ? s.copyWith(clearToAccount: true)
        : s.copyWith(toAccountId: id),
  );

  /// Sets the rail the money travelled on.
  void setPaymentMethod(String? id) => _edit(
    (s) => id == null
        ? s.copyWith(clearPaymentMethod: true)
        : s.copyWith(paymentMethodId: id),
  );

  /// Replaces the split draft, or removes it when [draft] is null.
  ///
  /// Clearing `splitError` on every change is deliberate: a message from a previous save describes a
  /// draft the user has just replaced, and leaving it up is the defect `copyWith`'s own comment
  /// records — a stale reason outliving the thing it was about.
  void setSplit(SplitDraft? draft) => _edit(
    (s) => draft == null
        ? s.copyWith(clearSplit: true, splitError: null)
        : s.copyWith(split: draft, splitError: null),
  );

  /// Sets the counterparty.
  void setPayee(String? id) => _edit(
    (s) => id == null ? s.copyWith(clearPayee: true) : s.copyWith(payeeId: id),
  );

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
  }) => _edit(
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
      kind: toOwnAccount
          ? TransactionKind.transfer
          : TransactionKind.withdrawal,
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
      _edit(
        (s) =>
            s.copyWith(amountMissing: true, shakeTrigger: s.shakeTrigger + 1),
      );
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
      ref
          .read(loggerProvider)
          .log(
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
    final transaction = current.toTransaction(
      newId: id,
      occurredAtUtc: clock.now().toUtc(),
    );

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
      final account =
          current.fromAccountId ??
          current.toAccountId ??
          ref.read(resolvedBillAccountProvider(null));
      if (account == null) {
        _edit((s) => s.copyWith(accountMissing: true));
        return null;
      }
      final paid = await ref
          .read(recurringRepositoryProvider)
          .payOccurrence(
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
      final replaced = await repository.replaceLines(
        transactionId: id,
        lines: lines,
      );
      if (replaced.isFailure) {
        _edit((s) => s.copyWith(saveError: replaced.failureOrNull?.message));
        return null;
      }
    }

    final fanned = await _fanOut(
      transaction: transaction,
      lines: lines,
      state: current,
    );
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
      await ref
          .read(shoppingRepositoryProvider)
          .markPurchased(
            entryIds: current.sourceEntryIds,
            transactionId: id,
          );
    }
    // **The split, after everything else.** It needs the transaction id, which is why it cannot run
    // earlier; and it runs last so a split that fails never stops a batch or an asset from being
    // created. The transaction is committed either way — what failed is the debt a step asked for,
    // and `splitError` says so exactly as `fanOutError` does for stock (Law U9).
    final splitError = await _applySplit(current, transactionId: id);

    // `clearErrors` first so a previous attempt's message cannot outlive it, then the new one.
    _edit((s) => s.copyWith(dirty: false, clearErrors: true));
    _edit(
      (s) => s.copyWith(
        fanOutError: fanned.error,
        wantsTemplate: fanned.wantsTemplate,
        createdAssetId: fanned.createdAsset,
        splitError: splitError,
      ),
    );
    return id;
  }

  /// Writes the drafted split against a transaction that now exists, and returns why it could not.
  ///
  /// **Idempotent, because `_write` is.** That method's own doc records the rule: five writes, no
  /// outer transaction, and ARCH_4 §5.1 item 17 forbids one repository owning another's — so
  /// idempotency is the sanctioned answer, and every step has to supply its own half of it.
  ///
  /// Here that means looking up the split already attached to this transaction and reusing its id.
  /// Without it, a save that got this far and then threw would mint a second `SplitExpense` on the
  /// retry and the debt would double — the same defect the line-id comment above records, in a
  /// different table. A transaction carries at most one split, so `expenseForTransaction` is an exact
  /// answer rather than a heuristic.
  Future<String?> _applySplit(
    TransactionEditorState current, {
    required String transactionId,
  }) async {
    final draft = current.split;
    if (draft == null || !draft.isActive) return null;
    final amount = current.amount;
    if (amount == null) return null;

    final existing = await ref
        .read(splitLedgerRepositoryProvider)
        .expenseForTransaction(transactionId);

    final result = await ref
        .read(splitExpenseServiceProvider)
        .record(
          id: existing?.id,
          total: amount,
          paidByPayeeId: draft.paidByPayeeId,
          inputs: draft.inputs,
          method: draft.method,
          transactionId: transactionId,
          groupId: draft.groupId,
          // The note doubles as the split's title. A shared bill wants a name — "Dinner at Olive" —
          // and asking for one twice on the same screen is how a field gets left blank.
          title: current.note,
          on: current.dateKey,
          settleBy: draft.settleByDateKey,
        );
    return result.failureOrNull?.message;
  }

  /// Creates the batches, assets and template names the lines call for, and writes their ids back.
  ///
  /// **Reports whether anything was refused.** `_planBatch` rejects a line with no `itemId` or no
  /// quantity, and an earlier version dropped that failure on the floor — the transaction saved, the
  /// snack said so, and the stock never appeared in the inventory with nothing on screen to explain
  /// why. A write that half-succeeds must say which half (U9).
  Future<
    ({
      List<TransactionLine> lines,
      String? error,
      bool wantsTemplate,
      String? createdAsset,
    })
  >
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
    final planned = ref
        .read(purchaseFanOutServiceProvider)
        .planAll(
          lines: lines,
          transaction: transaction,
          newArtefactIds: [
            for (var i = 0; i < lines.length; i++) uids.generate(),
          ],
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
          final saved = await ref
              .read(assetRepositoryProvider)
              .save(
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
          ref
              .read(templateDraftProvider.notifier)
              .offer(
                TemplateDraft(
                  name:
                      plan.recurringTemplateName ?? updated[index].description,
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

  static TransactionSubtype _defaultSubtypeFor(TransactionKind kind) =>
      switch (kind) {
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
final editorTagsProvider = StreamProvider.autoDispose
    .family<List<Tag>, TransactionKind>(
      (ref, kind) => ref
          .watch(tagRepositoryProvider)
          .watchByScope(
            kind == TransactionKind.deposit
                ? TagScope.deposit
                : TagScope.withdrawal,
          ),
    );

/// The first event of [stream], or an empty list when it closes without emitting one.
Future<List<T>> _firstOrEmpty<T>(Stream<List<T>> stream) async {
  await for (final value in stream) {
    return value;
  }
  return <T>[];
}
