import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/domain/repositories/split_ledger_repository.dart';
import 'package:alaya/domain/services/split/debt_simplifier.dart';

/// One currency's worth of a settle-up plan.
///
/// **Plans are per currency and never merged.** Netting INR against USD without a rate produces a
/// figure nobody can reproduce, and anomaly A34 already settled that money groups by currency rather
/// than collapsing. A group that spent in two currencies gets two plans, which is also how a person
/// would settle it.
final class CurrencyPlan {
  /// Creates a plan for one currency.
  const CurrencyPlan({required this.currencyCode, required this.plan});

  /// The currency.
  final String currencyCode;

  /// What to pay, and to whom.
  final SettlementPlan plan;
}

/// Answers "who owes what" and "what is the shortest way to settle it".
///
/// **Every figure here is derived (Law L3).** The service adds two things the views cannot: a *date
/// comparison*, because ARCH_2 §12.2 forbids any view from consulting the current time, and the
/// simplification, because that is a graph algorithm rather than a query.
final class SplitBalanceService {
  /// Creates the service.
  const SplitBalanceService({
    required SplitLedgerRepository ledger,
    required Clock clock,
    DebtSimplifier simplifier = const DebtSimplifier(),
  }) : _ledger = ledger,
       _clock = clock,
       _simplifier = simplifier;

  final SplitLedgerRepository _ledger;
  final Clock _clock;
  final DebtSimplifier _simplifier;

  /// How old a debt has to be before the daily digest mentions it, by default.
  ///
  /// **Fourteen days, and the number is a judgement rather than a finding.** Short enough that a
  /// forgotten dinner surfaces while both people still remember it; long enough that splitting a bill
  /// on Friday does not produce a notification the following Tuesday. Overridable, because the right
  /// answer differs between flatmates settling monthly and a trip that ends on Sunday.
  static const int defaultAgeingThresholdDays = 14;

  /// Balances outstanding with somebody, oldest first.
  ///
  /// **The nudge nobody else sends.** A due-date reminder is what the competition offers, and it needs
  /// a date somebody remembered to set. This needs nothing: the balance view already carries the oldest
  /// contributing expense, so *"Ravi has owed you ₹1,850 for three weeks"* falls out of data that
  /// exists whether or not anyone planned ahead.
  ///
  /// The day count is computed here against [Clock] rather than in SQL, because a view containing
  /// `now` could not be asserted against a `FixedClock` — the same rule `CalendarAggregator` follows
  /// for severity escalation.
  Future<List<AgeingDebt>> ageingDebts({
    int thresholdDays = defaultAgeingThresholdDays,
  }) async {
    final today = _clock.today();
    final balances = await _ledger.watchBalances().first;

    final ageing = <AgeingDebt>[];
    for (final balance in balances) {
      final age = balance.ageInDays(today);
      if (age == null || age < thresholdDays) continue;
      ageing.add(AgeingDebt(balance: balance, ageInDays: age));
    }
    ageing.sort((a, b) => b.ageInDays.compareTo(a.ageInDays));
    return ageing;
  }

  /// The single largest outstanding amount, in each direction, across every currency.
  ///
  /// What a dashboard card shows. Returned as two separate figures rather than one net total, because
  /// **"you are owed ₹4,000 and you owe ₹3,900" is not the same story as "you are up ₹100"** — and per
  /// decision 1 neither figure is spendable until it arrives, so a single net number would invite
  /// exactly the reading the card exists to avoid.
  Future<Map<String, ({Money owedToMe, Money iOwe})>> totals() async {
    final balances = await _ledger.watchBalances().first;
    final byCurrency = <String, ({Money owedToMe, Money iOwe})>{};
    for (final balance in balances) {
      final code = balance.net.currencyCode;
      final running =
          byCurrency[code] ??
          (owedToMe: Money.zero(code), iOwe: Money.zero(code));
      byCurrency[code] = balance.theyOweMe
          ? (
              owedToMe: running.owedToMe + balance.outstanding,
              iOwe: running.iOwe,
            )
          : (
              owedToMe: running.owedToMe,
              iOwe: running.iOwe + balance.outstanding,
            );
    }
    return byCurrency;
  }

  /// The fewest payments that settle [groupId], one plan per currency.
  ///
  /// **Suggested, never applied.** The pairwise ledger is untouched — Splitwise rewrites the debt graph
  /// in place, then has to advise users that the individual balances may have been reshuffled, and
  /// turning it off does not cleanly reverse. Accepting one of these plans records ordinary
  /// settlements, the same rows a manual settle-up writes, so there is no simplified state to get
  /// stuck in.
  ///
  /// Edges are grouped by currency here rather than in the repository: `debtsIn` returns what the
  /// group owes in every currency it has spent in, and `DebtSimplifier.plan` refuses a mixed list
  /// outright — which is the correct refusal, and the reason the grouping has to happen somewhere
  /// visible.
  ///
  /// Plans that suggest nothing are dropped, so an empty list means settled up.
  Future<List<CurrencyPlan>> settleUpPlans(String groupId) async {
    final edges = await _ledger.debtsIn(groupId);
    if (edges.isEmpty) return const [];

    final byCurrency = <String, List<DebtEdge>>{};
    for (final edge in edges) {
      byCurrency.putIfAbsent(edge.amount.currencyCode, () => []).add(edge);
    }

    final plans = <CurrencyPlan>[];
    for (final entry in byCurrency.entries) {
      final plan = _simplifier.plan(entry.value);
      if (plan.transfers.isEmpty) continue;
      plans.add(CurrencyPlan(currencyCode: entry.key, plan: plan));
    }
    // Most payments saved first: a plan that turns six transfers into two is the one worth showing at
    // the top, and a plan that saves nothing has already been dropped.
    plans.sort(
      (a, b) => b.plan.paymentsSaved.compareTo(a.plan.paymentsSaved),
    );
    return plans;
  }

  /// Whether simplifying [groupId] would help at all.
  ///
  /// What a screen checks before offering the button. Cheaper to ask than to render a plan that turns
  /// three payments into three payments, which is the state most small groups are in.
  Future<bool> canSimplify(String groupId) async {
    final plans = await settleUpPlans(groupId);
    return plans.any((p) => p.plan.isImprovement);
  }

  /// One counterparty's outstanding balances, across every currency.
  Stream<List<SplitBalance>> watchBalanceWith(String payeeId) =>
      _ledger.watchBalanceWith(payeeId);

  /// Every outstanding balance, for a list screen.
  Stream<List<SplitBalance>> watchBalances() => _ledger.watchBalances();

  /// [today], for a caller that wants to compute ageing itself without reaching for a clock.
  DateKey get today => _clock.today();
}
