import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// What one person owes you, or you owe them, in one currency.
///
/// **Read-only: comes from `v_split_balances`, and no balance is stored (Law L3).**
///
/// That is the single most consequential line in this module. Splitwise stores balances and has to
/// reconcile them, and its own help centre ends up advising users to distrust the pairwise figures
/// after simplification reshuffles them. Here a balance cannot drift because there is nowhere for it
/// to drift from — it is a sum over shares and settlements, recomputed on every read.
///
/// **Per currency, never summed across.** Netting INR against USD without a rate produces a figure
/// nobody can reproduce, which is the same reason anomaly A34 made waste costs group by currency
/// rather than collapse into one number.
class SplitBalance {
  /// Creates a balance.
  const SplitBalance({
    required this.payeeId,
    required this.owedToMe,
    required this.iOwe,
    this.oldestUnsettledDateKey,
  });

  /// The counterparty.
  final String payeeId;

  /// Their share of expenses **you** paid.
  final Money owedToMe;

  /// Your share of expenses **they** paid.
  final Money iOwe;

  /// The earliest date of an expense contributing to this balance, or null when nothing is
  /// outstanding.
  ///
  /// **What the ageing nudge reads, and why the view can supply it.** The notification worth sending
  /// is not a due date — it is "Ravi has owed you ₹1,850 for three weeks", which needs a start date
  /// and today. The view provides the date; the day count is computed in Dart against the injected
  /// `Clock`, because ARCH_2 §12.2 forbids any view from referencing the current time and a view
  /// containing `now` cannot be asserted against a `FixedClock`.
  final DateKey? oldestUnsettledDateKey;

  /// Positive when they owe you, negative when you owe them.
  Money get net => owedToMe - iOwe;

  /// Whether anything is outstanding either way.
  bool get isSettled => net.isZero;

  /// Whether they owe you.
  bool get theyOweMe => net.isPositive;

  /// Whether you owe them.
  bool get iOweThem => net.isNegative;

  /// The outstanding amount, without its direction. What a row displays beside a name.
  Money get outstanding => net.abs();

  /// How many days [oldestUnsettledDateKey] is before [today], or null when nothing is outstanding.
  ///
  /// Takes [today] rather than reading a clock, so an ageing nudge is reproducible under a
  /// `FixedClock` — the rule `Batch.isExpired` and every view in this schema follow.
  int? ageInDays(DateKey today) {
    final since = oldestUnsettledDateKey;
    if (since == null || isSettled) return null;
    // `diffDays` is positive when the receiver is later, so `today.diffDays(since)` is the age. The
    // same direction `DateKeyLabels.headerLabel` uses — I reached for `differenceInDays` first, which
    // does not exist.
    return today.diffDays(since);
  }
}

/// One expense with its own allocation totals, from `v_split_expenses`.
///
/// The read-model twin of `SplitExpense`, in the same relationship `ItemStock` has to `Item`: the
/// entity mirrors the table and this carries what the view derives. Screens listing expenses read
/// this and never load the shares, which is the point — a list of forty expenses should not fetch
/// four hundred share rows to show four hundred totals.
class SplitExpenseSummary {
  /// Creates a summary.
  const SplitExpenseSummary({
    required this.splitExpenseId,
    required this.total,
    required this.allocated,
    required this.dateKey,
    required this.paidByPayeeId,
    required this.shareCount,
    this.groupId,
    this.transactionId,
    this.title,
    this.place,
    this.occasion,
    this.settleByDateKey,
    this.myShare,
  });

  /// The expense.
  final String splitExpenseId;

  /// What the whole bill came to.
  final Money total;

  /// What the shares add up to.
  final Money allocated;

  /// The civil date the expense happened on.
  final DateKey dateKey;

  /// Who paid.
  final String paidByPayeeId;

  /// How many people are on it.
  final int shareCount;

  /// The group, or null for a one-off.
  final String? groupId;

  /// The transaction that moved your money, or null when somebody else paid.
  final String? transactionId;

  /// What it was.
  final String? title;

  /// Where it happened.
  final String? place;

  /// What the occasion was.
  final String? occasion;

  /// An optional date to settle by.
  final DateKey? settleByDateKey;

  /// Your own share, or null when the self payee is not configured yet.
  ///
  /// **Null means "not configured", never "zero".** `split.selfPayeeId` is a setting with no value on
  /// a fresh install — there is no payee to point at until the user creates one — so the view yields
  /// null and a screen must say so rather than displaying ₹0 as though you owed nothing.
  final Money? myShare;

  /// What the shares fail to account for. See `SplitExpense.unallocated`.
  Money get unallocated => total - allocated;

  /// Whether the shares account for the total exactly.
  bool get isFullyAllocated => unallocated.isZero;

  /// Whether the money for this has already left your account.
  bool get wasPaidByYou => transactionId != null;
}

/// What kind of thing an activity entry is.
enum SplitActivityKind {
  /// A shared expense was recorded.
  expense,

  /// Money changed hands.
  settlement,
}

/// One line of a group's activity feed, from `v_split_activity`.
///
/// A `UNION ALL` view rather than an events table, for the same reason `v_calendar_events` is one: two
/// subsystems writing into a shared feed table is a synchronisation-bug factory, and a view has no
/// synchronisation code to get wrong (anomaly A37).
class SplitActivityEntry {
  /// Creates an entry.
  const SplitActivityEntry({
    required this.refId,
    required this.kind,
    required this.dateKey,
    required this.amount,
    required this.payeeId,
    this.groupId,
    this.label,
  });

  /// The expense or settlement id this refers to.
  final String refId;

  /// Which of the two it is.
  final SplitActivityKind kind;

  /// The civil date.
  final DateKey dateKey;

  /// The amount involved.
  final Money amount;

  /// Who paid — the payer for an expense, the sender for a settlement.
  final String payeeId;

  /// The group, or null for a one-off.
  final String? groupId;

  /// A title, occasion, place or note, whichever the row had.
  final String? label;
}

/// A balance old enough to be worth mentioning.
///
/// **Here rather than in `SplitBalanceService`, where it was first declared.** A screen reads this and
/// a screen has no business importing a service to name a type — the same fault
/// `SplitLedgerRepository` records about `DebtEdge` still living inside `debt_simplifier.dart`. A
/// value type that two layers pass around belongs with the other read models, which is where a
/// consumer looks for it.
///
/// It carries no clock and no threshold: [ageInDays] is already computed, because ARCH_2 §12.2 forbids
/// a view from consulting the current time and the comparison happens once, in the service, against an
/// injected `Clock`.
final class AgeingDebt {
  /// Creates an ageing debt.
  const AgeingDebt({required this.balance, required this.ageInDays});

  /// Who, and how much.
  final SplitBalance balance;

  /// How long the oldest contributing expense has been outstanding.
  final int ageInDays;
}
