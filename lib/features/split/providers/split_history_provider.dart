/// Everything that has happened in the split module, newest first (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/domain/entities/split_read_models.dart';

/// How many entries the history tab reads.
///
/// **A page size, not a guess about how much history matters.** `v_split_activity` is a `UNION ALL` over
/// two tables that only grow, with no date bound — the one read in this module that gets slower every
/// month somebody keeps using it. Fifty is roughly a screen and a half of scrolling; the contract makes
/// `limit` required precisely so a screen has to say a number out loud rather than inherit one.
const int splitHistoryPageSize = 50;

/// Expenses and settlements interleaved, across every group and none.
///
/// **`groupId: null` was already supported and nothing used it.** `watchActivity` takes a nullable group
/// and the module only ever passed one, so a split filed under no group — which is most of them, since
/// the bill screen makes a group optional — appeared on no screen at all once it was saved. The feed
/// existed, the view existed, and the only reader narrowed it to a group.
///
/// **This is where an unnamed split lives.** A participant nobody has named has a placeholder payee and
/// therefore a real balance, but a split saved and settled in one sitting leaves no balance behind — and
/// without history there was no evidence it ever happened. A ledger of decisions is not the same thing
/// as a list of who currently owes what, and the module had only the second.
final splitHistoryProvider = StreamProvider<List<SplitActivityEntry>>(
  (ref) => ref
      .watch(splitLedgerRepositoryProvider)
      .watchActivity(limit: splitHistoryPageSize),
);

/// The same feed, restricted to one group.
///
/// Kept separate from [splitHistoryProvider] rather than folded into a family with a nullable argument:
/// `family<..., String?>` would give two provider instances that look interchangeable at the call site,
/// and "the whole feed" and "this group's feed" answer different questions on different screens.
final splitGroupHistoryProvider =
    StreamProvider.family<List<SplitActivityEntry>, String>(
      (ref, groupId) => ref
          .watch(splitLedgerRepositoryProvider)
          .watchActivity(groupId: groupId, limit: splitHistoryPageSize),
    );

/// One split, with its shares, for the detail sheet.
///
/// **A stream, unlike the settle-up plan.** A plan is a snapshot of a question asked once; an expense is a
/// record that can be edited from the sheet that shows it, and a stale total sitting behind an edit the user
/// just made is the kind of thing that makes people re-check the arithmetic by hand.
///
/// `autoDispose`, because one of these exists per expense ever opened. Without it, scrolling a year of
/// history and tapping through it would leave a subscription per row for the life of the app.
final splitExpenseProvider = StreamProvider.autoDispose
    .family<SplitExpense?, String>(
      (ref, id) =>
          ref.watch(splitLedgerRepositoryProvider).watchExpenseById(id),
    );
