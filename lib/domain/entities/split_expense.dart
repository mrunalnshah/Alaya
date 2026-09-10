import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// One shared expense, and who fronted the money for it.
///
/// ## Two cases, and the nullable [transactionId] is what holds both
///
/// **You paid.** Cash left your account, so a `transactions` withdrawal for the *full* amount exists
/// and [transactionId] points at it. Recording only your own share would make the account balance
/// wrong on the day.
///
/// **Somebody else paid.** No money has left your account, so there is **no transaction at all**
/// until you settle — [transactionId] is null and [paidByPayeeId] names who covered it. Most
/// implementations of this feature model only the first case and bolt the second on afterwards.
///
/// ## What is deliberately absent
///
/// **No `myShare`, no `settled`, no `isSettled`.** Law L3 — no total is ever stored. Every one of
/// those is a sum over [shares] and settlements, and [SplitExpenseSummary] is where they arrive from
/// the view. `myShare` on this class would be the single most tempting field in the module and it
/// would drift the first time a share was edited.
class SplitExpense {
  /// Creates an expense.
  const SplitExpense({
    required this.id,
    required this.paidByPayeeId,
    required this.total,
    required this.dateKey,
    required this.splitMethod,
    this.shares = const [],
    this.groupId,
    this.transactionId,
    this.title,
    this.place,
    this.occasion,
    this.note,
    this.settleByDateKey,
    this.converted,
  });

  /// Row identifier.
  final String id;

  /// Who actually paid the bill.
  final String paidByPayeeId;

  /// What the whole bill came to.
  final Money total;

  /// The civil date the expense happened on.
  final DateKey dateKey;

  /// How the shares were specified.
  final SplitMethod splitMethod;

  /// Who owes what, in display order.
  final List<SplitShare> shares;

  /// The group this belongs to, or null for a one-off split with one person.
  final String? groupId;

  /// The transaction that moved your money, or null when somebody else paid.
  final String? transactionId;

  /// What it was — `Dinner at Olive`, `October rent`.
  final String? title;

  /// Where it happened.
  ///
  /// An analytics dimension rather than decoration: "what do we spend in Goa" is a question no split
  /// app answers, and it is answerable here because the column exists.
  final String? place;

  /// What the occasion was — `Diwali`, `Ravi's birthday`.
  final String? occasion;

  /// Free-form note.
  final String? note;

  /// An optional date to settle by, which feeds the calendar and the daily digest.
  final DateKey? settleByDateKey;

  /// The frozen home-currency conversion, or null when the expense was already in it.
  final SplitConversion? converted;

  /// `dateKey`'s month, for month-grouped reads.
  ///
  /// Derived here and stored on the row, because the schema's CHECK enforces
  /// `date_key / 100 = month_key` — the same arrangement `transactions` uses, where the database
  /// rejects a caller that gets it wrong rather than letting a row become invisible to monthly
  /// analytics.
  int get monthKey => dateKey.value ~/ 100;

  /// Whether the money for this has already left your account.
  ///
  /// True in the "you paid" case. The screens read this rather than testing `transactionId != null`
  /// directly, so the reason is named where it is used.
  bool get wasPaidByYou => transactionId != null;

  /// Whether any share is attached to a specific transaction line.
  bool get isItemised => shares.any((share) => share.transactionLineNo != null);

  /// What the shares add up to.
  Money get allocated => shares.fold(
    Money.zero(total.currencyCode),
    (sum, share) => sum + share.amount,
  );

  /// What the shares fail to account for — [total] minus [allocated].
  ///
  /// **Reported, never absorbed.** Percentages summing to 90% leave 10% here, and exact amounts that
  /// overshoot leave it negative. `transaction_lines` already surfaces "₹500 total, ₹480 of lines →
  /// unallocated ₹20" rather than adjusting a figure to make it balance (ARCH_2 §4.2); quietly
  /// rounding a shortfall onto the last participant charges somebody for a discrepancy nobody told
  /// them about.
  Money get unallocated => total - allocated;

  /// Whether the shares account for the total exactly.
  bool get isFullyAllocated => unallocated.isZero;

  /// The share belonging to [payeeId], or null when they are not on this expense.
  SplitShare? shareOf(String payeeId) {
    for (final share in shares) {
      if (share.payeeId == payeeId) return share;
    }
    return null;
  }
}

/// What one participant owes on one expense, and how that was decided.
///
/// **Both the input and the resolved amount are carried, deliberately.** Re-deriving shares from
/// their inputs on every read would re-run largest-remainder allocation and could hand the stray
/// paise to a different person than the one the user agreed with. [amount] is what they owe;
/// [inputKind] and [inputValue] are how it was arrived at, so the editor shows 40/30/30 rather than
/// three amounts.
class SplitShare {
  /// Creates a share.
  const SplitShare({
    required this.id,
    required this.splitExpenseId,
    required this.payeeId,
    required this.amount,
    required this.inputKind,
    this.inputValue,
    this.transactionLineNo,
  });

  /// Row identifier.
  final String id;

  /// The expense being split.
  final String splitExpenseId;

  /// Who owes this share.
  final String payeeId;

  /// The exact amount owed. Sums with its siblings to the expense's allocated total.
  final Money amount;

  /// How this share was specified.
  final ShareInputKind inputKind;

  /// The typed value behind [inputKind] — minor units for `exact`, basis points for `percent`, a
  /// weight for `shares`, and null for `equal`.
  final int? inputValue;

  /// The `transaction_lines.lineNo` this share is against, or null for a share of the whole expense.
  ///
  /// **This field is the itemised split** — the ₹400 dessert is one line with one participant while
  /// the ₹1,200 platter is one line split four ways, so each person's total becomes a sum over lines
  /// rather than a division of the bill. The feature Splitwise puts behind its paid tier.
  ///
  /// Only meaningful when the expense has a transaction, because the lines are the transaction's. The
  /// schema enforces the header half of that (`split_method <> 'perLine' OR transaction_id IS NOT
  /// NULL`); this direction spans two tables, which SQLite cannot express as a CHECK, so the
  /// repository upholds it.
  final int? transactionLineNo;
}

/// A frozen currency conversion, taken when an expense was recorded.
///
/// **A snapshot, never a live conversion (Law L9).** A holiday split in THB must keep the rate it was
/// entered at, or last March's trip re-prices itself every time the rate table updates.
class SplitConversion {
  /// Creates a conversion snapshot.
  const SplitConversion({
    required this.amount,
    required this.rate,
    required this.rateRaw,
    required this.dateKey,
  });

  /// The converted amount, in the home currency at the time.
  final Money amount;

  /// The rate used, as the display string it was shown with.
  final String rate;

  /// The rate exactly as fetched, before rounding, for audit.
  final String rateRaw;

  /// The civil date the rate was valid on.
  final DateKey dateKey;
}

/// Money that actually changed hands to settle a debt.
///
/// **Many settlements per debt, on purpose.** "Keep adding as they keep paying" is partial
/// settlement, and what remains outstanding is derived from these rows — never a decremented column
/// (Law L3).
///
/// [transactionId] is non-null whenever you are a party, because a settlement you are in moved your
/// money and must appear in your ledger. **That is what makes settling up real rather than a flag**:
/// Splitwise's "settle up" is a bookkeeping marker that cannot touch your bank, whereas here the
/// deposit or withdrawal is an ordinary transaction, so the split ledger and the account ledger
/// cannot diverge.
class SplitSettlement {
  /// Creates a settlement.
  const SplitSettlement({
    required this.id,
    required this.fromPayeeId,
    required this.toPayeeId,
    required this.amount,
    required this.dateKey,
    this.groupId,
    this.transactionId,
    this.paymentMethodId,
    this.note,
  });

  /// Row identifier.
  final String id;

  /// Who paid.
  final String fromPayeeId;

  /// Who was paid.
  final String toPayeeId;

  /// How much.
  final Money amount;

  /// The civil date the money moved.
  final DateKey dateKey;

  /// The group this settles within, or null for a one-off debt.
  final String? groupId;

  /// The transaction this wrote into your ledger. Non-null whenever you are a party.
  final String? transactionId;

  /// How the money travelled — UPI, cash, bank transfer.
  final String? paymentMethodId;

  /// Free-form note.
  final String? note;

  /// `dateKey`'s month, for month-grouped reads. See [SplitExpense.monthKey].
  int get monthKey => dateKey.value ~/ 100;

  /// Whether [payeeId] is either side of this settlement.
  bool involves(String payeeId) =>
      fromPayeeId == payeeId || toPayeeId == payeeId;
}
