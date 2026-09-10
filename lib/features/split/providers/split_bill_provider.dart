/// Recording a split from the split module's own screen (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/text/split_placeholder_names.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/services/split/split_resolver.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// One participant as the bill screen holds them: a payee, or nobody yet.
typedef BillParticipant = ({String? payeeId, int? value, int? extra});

/// Saves a bill split from the split screen, optionally recording the expense too.
final splitBillProvider = NotifierProvider<SplitBill, AsyncValue<void>>(
  SplitBill.new,
);

/// Writes the split, the placeholders it needed, and the transaction when the user's money moved.
class SplitBill extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Records a bill, standing in for anybody who is still anonymous.
  ///
  /// **Unnamed participants become placeholder payees, and that is what lets a split save at the table.**
  /// `split_shares.payee_id` is `NOT NULL REFERENCES payees(id)`, so a debt has to be with somebody;
  /// refusing to save until every slot was named meant four contact records demanded at the moment
  /// everybody is standing up to leave. They are written as [PayeeKind.splitPlaceholder], so the row exists
  /// where balances need it and is filtered out of every list a contact belongs in.
  ///
  /// **[paidByPayeeId] defaults to the user and no longer forces them.** It used to be hardcoded to `self`,
  /// which made one arm of `v_split_balances` unreachable — that arm reports "I owe" only when the payer is
  /// somebody else, so "You owe" was structurally zero however many splits were saved. The schema, the
  /// service and the view all supported the other case; the only screen that writes never offered it.
  ///
  /// **The transaction comes first, and a failure between the two leaves the safe half.** An expense saved
  /// without its split is visible in the ledger and can be split again; a split saved against a transaction
  /// that does not exist is a debt for a payment nobody made.
  Future<bool> save({
    required Money total,
    required List<BillParticipant> participants,
    required SplitMethod method,
    required bool recordExpense,

    /// The split being replaced, or null for a new one.
    ///
    /// **`SplitExpenseService.record` has taken an id since it was written** — "supplied when re-saving an
    /// existing split, so an edit replaces rather than duplicates" — and no screen ever passed one. Editing
    /// needed no new domain code at all; it needed a caller.
    String? expenseId,
    String? paidByPayeeId,

    /// What the ledger row will say, composed by the screen.
    ///
    /// **Passed in rather than built here, because a note is a sentence and a sentence needs the ARB** — which
    /// needs a `BuildContext` this notifier does not have. The screen knows the words; this knows the writes.
    ///
    /// It lands on both the transaction and the split expense. A ledger row reading "₹5,000" with no payee and
    /// no note is the one an owner cannot identify a month later, and that row is the reason this exists.
    String? note,
    String? accountId,
    String? groupId,
    String? title,
    String? place,
    String? occasion,
    DateKey? on,
    DateKey? settleBy,
  }) async {
    state = const AsyncLoading<void>();
    final clock = ref.read(clockProvider);
    final date = on ?? clock.today();
    final self = await ref.read(splitSelfProvider.future);

    if (self == null) {
      state = AsyncError<void>(
        const BusinessRuleFailure(
          'Choose which person is you before splitting a bill.',
          rule: 'splitSelfPayeeUnset',
        ),
        StackTrace.current,
      );
      return false;
    }

    final payer = paidByPayeeId ?? self;

    final named = await _standInForEverybody(participants);
    if (named == null) {
      // `_standInForEverybody` has already put the repository's own sentence in `state`.
      return false;
    }

    String? transactionId;
    // **No transaction when somebody else paid, whatever the caller asked for.** No money left the user's
    // account, so a withdrawal would invent an outflow — and `SplitExpense.wasPaidByYou` reads
    // `transactionId != null`, so a stray one would make every screen claim they had paid. The screen
    // disables the switch as well; this is the backstop, because an invented outflow is invisible once
    // written.
    // **No new transaction when re-saving.** An edit that wrote another withdrawal would double the outflow
    // for one dinner, and the original is still in the ledger. Changing the amount of a recorded expense is
    // the expense editor's job; this screen edits the *split*.
    if (recordExpense &&
        accountId != null &&
        payer == self &&
        expenseId == null) {
      final uids = ref.read(uidGeneratorProvider);
      final created = await ref
          .read(transactionRepositoryProvider)
          .create(
            transaction: Transaction(
              id: uids.generate(),
              kind: TransactionKind.withdrawal,
              // **`otherOut`, not a guessed category.** The screen asks for a title, not a subtype, and
              // inventing one would put every shared dinner into whichever bucket seemed likeliest.
              subtype: TransactionSubtype.otherOut,
              occurredAtUtc: clock.now(),
              dateKey: date,
              // **The full bill, not the user's share.** Cash is cash: the whole amount left the account
              // whatever the split says. The share is derivable and the outflow is not, which is the
              // premise of the two analytics lenses.
              originalAmount: total,
              needsReview: false,
              fromAccountId: accountId,
              // The composed sentence when there is one, and the bare title otherwise — so a transaction is
              // never *less* legible than it was before this parameter existed.
              note: note ?? title,
            ),
          );
      if (created.isFailure) {
        state = AsyncError<void>(created.failureOrNull!, StackTrace.current);
        return false;
      }
      transactionId = created.valueOrNull!.id;
    }

    final result = await ref
        .read(splitExpenseServiceProvider)
        .record(
          id: expenseId,
          total: total,
          paidByPayeeId: payer,
          inputs: [
            for (var i = 0; i < named.length; i++)
              _inputFor(named[i], participants[i], method),
          ],
          method: method,
          transactionId: transactionId,
          groupId: groupId,
          title: title,
          place: place,
          occasion: occasion,
          // Carried onto the expense as well as the transaction: reopening a split from history shows the same
          // sentence the ledger row shows, rather than two descriptions of one evening.
          note: note,
          on: date,
          settleBy: settleBy,
        );

    final failure = result.failureOrNull;
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData(null);
    return true;
  }

  /// Resolves every participant to a payee id, creating a placeholder for anybody anonymous.
  ///
  /// Returns null when a row could not be created, having already reported why.
  ///
  /// **Numbered against every payee that exists, not against this split.** Two splits a week apart must not
  /// both produce a "Person 1" — two strangers sharing a row is a wrong balance nobody would think to
  /// check. `nextNames` continues past the highest already there, and a placeholder since renamed to "Ravi"
  /// does not free its number, because rows still reference it.
  Future<List<String>?> _standInForEverybody(
    List<BillParticipant> participants,
  ) async {
    final anonymous = <int>[
      for (var i = 0; i < participants.length; i++)
        if (participants[i].payeeId == null) i,
    ];
    if (anonymous.isEmpty) {
      return [for (final p in participants) p.payeeId!];
    }

    // **Every participant, placeholders included.** Numbering against the pickers list would reuse a number
    // already taken by a placeholder, and two shares would point at one row.
    final existing = await ref.read(splitParticipantsProvider.future);
    final names = SplitPlaceholderNames.nextNames(
      count: anonymous.length,
      existing: [for (final payee in existing) payee.name],
    );

    final uids = ref.read(uidGeneratorProvider);
    final normalizer = ref.read(normalizerProvider);
    final repository = ref.read(payeeRepositoryProvider);
    final resolved = [for (final p in participants) p.payeeId];

    for (var i = 0; i < anonymous.length; i++) {
      final saved = await repository.save(
        Payee(
          id: uids.generate(),
          name: names[i],
          normalizedName: normalizer.normalize(names[i]),
          // **`splitPlaceholder`, not `person`.** The row is real enough for a foreign key and invisible to
          // every list of contacts.
          kind: PayeeKind.splitPlaceholder,
        ),
      );
      final payee = saved.valueOrNull;
      if (payee == null) {
        state = AsyncError<void>(
          saved.failureOrNull ??
              const UnexpectedFailure('That person could not be added.'),
          StackTrace.current,
        );
        return null;
      }
      resolved[anonymous[i]] = payee.id;
    }
    return [for (final id in resolved) id!];
  }

  ShareInput _inputFor(
    String payeeId,
    BillParticipant participant,
    SplitMethod method,
  ) {
    // An extra wins over the method, and that is not a conflict: an extra says what somebody owes on top,
    // the method says how the rest divides.
    final extra = participant.extra;
    if (extra != null && extra > 0) return ShareInput.extra(payeeId, extra);
    return switch (method) {
      SplitMethod.equal => ShareInput.equal(payeeId),
      SplitMethod.shares => ShareInput.shares(payeeId, participant.value ?? 1),
      SplitMethod.percent => ShareInput.percent(
        payeeId,
        participant.value ?? 0,
      ),
      SplitMethod.exactAmounts => ShareInput.exact(
        payeeId,
        participant.value ?? 0,
      ),
      // Itemised splits come from a receipt's lines, which this screen does not have. Named so adding an
      // enum member breaks here rather than falling through — Law L13.
      SplitMethod.perLine => ShareInput.equal(payeeId),
    };
  }

  /// The message from the last failure, or null.
  String? get lastError {
    final error = state.error;
    return error is Failure ? error.message : null;
  }
}
