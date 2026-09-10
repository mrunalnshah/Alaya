/// The split module's analytics surfaces (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// One counterparty's share of the shared spending in the window.
typedef SplitPartner = ({String payeeId, Money total, int expenseCount});

/// What a window of shared expenses cost, from both sides.
///
/// **Two lenses on the same rows, and the reason this module can offer them at all.** [outflow] is what
/// left the user's account — the full bill on every expense they paid. [myShare] is what they actually
/// consumed. Splitwise knows the second and nothing about a bank account; a bank app knows the first and
/// nothing about the split. Both come from one set of rows here, which no competitor can do.
///
/// [recovered] is what came back through settlements, so `outflow - myShare - recovered` is money still
/// out with somebody. That is the figure a person actually feels, and it is derived rather than stored
/// (Law L3).
typedef SplitLenses = ({
  Money outflow,
  Money myShare,
  Money recovered,
  int expenseCount,
  int skippedForeignCount,
});

/// The two lenses over the analytics window.
///
/// Watches `analyticsWindowProvider` like every other surface on that screen, so changing the range chip
/// recomputes this with the rest — a card resolving its own window is how two figures on one screen come
/// to describe different months.
final splitLensesProvider = FutureProvider<SplitLenses?>((ref) async {
  final window = ref.watch(analyticsWindowProvider);
  final self = await ref.watch(splitSelfProvider.future);
  // Null, not an empty result. With nobody claimed as the user there is no "my share" to compute, and a
  // card showing ₹0 would read as "you consumed nothing" rather than "the module is not set up".
  if (self == null) return null;

  final code = await ref.watch(analyticsCurrencyProvider.future);
  final ledger = ref.watch(splitLedgerRepositoryProvider);
  final expenses = await ledger
      .watchExpenses(from: window.from, to: window.to)
      .first;
  final settlements = await ledger
      .watchSettlements(from: window.from, to: window.to)
      .first;

  var outflow = Money.zero(code);
  var mine = Money.zero(code);
  var recovered = Money.zero(code);
  var counted = 0;
  var skipped = 0;

  for (final expense in expenses) {
    // **Foreign-currency rows are counted, not converted.** A travel split carries a frozen conversion
    // on the entity (Law L9), but `SplitExpenseSummary` reports the original — and adding a THB total to
    // a rupee one produces a figure nobody can reproduce, which anomaly A34 settled. The card shows the
    // skipped count rather than quietly answering a different question.
    if (expense.total.currencyCode != code) {
      skipped++;
      continue;
    }
    counted++;
    if (expense.wasPaidByYou) outflow += expense.total;
    final share = expense.myShare;
    if (share != null) mine += share;
  }

  for (final settlement in settlements) {
    if (settlement.amount.currencyCode != code) continue;
    // Money arriving, not money sent onward — the two directions answer different questions and summing
    // them would net a repayment against a debt paid.
    if (settlement.toPayeeId == self) recovered += settlement.amount;
  }

  return (
    outflow: outflow,
    myShare: mine,
    recovered: recovered,
    expenseCount: counted,
    skippedForeignCount: skipped,
  );
});

/// Who the user shares expenses with most, by that person's share of the bills in the window.
///
/// **Counts the other person's share, not the bill.** "You split with Ravi most" should mean Ravi is on
/// the most of your money — his share of what you paid — rather than the totals of dinners he happened
/// to attend.
///
/// Loads each expense's shares, which is a read per row and the reason this provider is not on the
/// dashboard. On an analytics screen the window is bounded and the section is lazy: `SliverList` does not
/// build a card until somebody scrolls to it, which is the same protection ARCH_4 R7 gives the other
/// twenty-two.
final splitPartnersProvider = FutureProvider<List<SplitPartner>>((ref) async {
  final window = ref.watch(analyticsWindowProvider);
  final self = await ref.watch(splitSelfProvider.future);
  if (self == null) return const [];

  final code = await ref.watch(analyticsCurrencyProvider.future);
  final ledger = ref.watch(splitLedgerRepositoryProvider);
  final summaries = await ledger
      .watchExpenses(from: window.from, to: window.to)
      .first;

  final totals = <String, ({int minor, int count})>{};
  for (final summary in summaries) {
    if (summary.total.currencyCode != code) continue;
    final expense = await ledger.expenseById(summary.splitExpenseId);
    if (expense == null) continue;
    for (final share in expense.shares) {
      if (share.payeeId == self) continue;
      final running = totals[share.payeeId] ?? (minor: 0, count: 0);
      totals[share.payeeId] = (
        minor: running.minor + share.amount.minor,
        count: running.count + 1,
      );
    }
  }

  return [
    for (final entry in totals.entries)
      (
        payeeId: entry.key,
        total: Money(entry.value.minor, code),
        expenseCount: entry.value.count,
      ),
  ]..sort((a, b) => b.total.minor.compareTo(a.total.minor));
});

/// Shared spending by occasion.
///
/// **The dimension no competitor has**, and it exists only because `split_expenses` carries `occasion`
/// and `place` as columns rather than folding them into a note. *"What did Diwali cost us"* and *"what do
/// we spend in Goa"* are questions a split app is uniquely placed to answer, and none of them do.
final splitOccasionProvider =
    FutureProvider<List<({String label, Money total})>>(
      (ref) => _byDimension(ref, (e) => e.occasion),
    );

/// The same, by place.
final splitPlaceProvider = FutureProvider<List<({String label, Money total})>>(
  (ref) => _byDimension(ref, (e) => e.place),
);

Future<List<({String label, Money total})>> _byDimension(
  Ref ref,
  String? Function(SplitExpenseSummary) pick,
) async {
  final window = ref.watch(analyticsWindowProvider);
  final code = await ref.watch(analyticsCurrencyProvider.future);
  final rows = await ref
      .watch(splitLedgerRepositoryProvider)
      .watchExpenses(from: window.from, to: window.to)
      .first;

  final totals = <String, int>{};
  for (final row in rows) {
    if (row.total.currencyCode != code) continue;
    final label = pick(row)?.trim();
    // A blank dimension is dropped rather than bucketed as "Other". Most expenses carry neither field,
    // so an "Other" slice would dominate every chart and say nothing at all.
    if (label == null || label.isEmpty) continue;
    totals[label] = (totals[label] ?? 0) + row.total.minor;
  }

  return [
    for (final entry in totals.entries)
      (label: entry.key, total: Money(entry.value, code)),
  ]..sort((a, b) => b.total.minor.compareTo(a.total.minor));
}
