import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/debt_edge.dart';

// **Re-exported, so moving `DebtEdge` breaks nothing.** Three files import it from here — a repository
// contract, a service and a screen — and a contract importing a service to name its own return type was
// the reason to move it. Callers keep working; new code should import `entities/debt_edge.dart`.
//
// This line is the whole migration. Delete it once no import of this file relies on it, which a
// project-wide grep for `debt_simplifier.dart` can decide and `tool/reachability.py` cannot.
export 'package:alaya/domain/entities/debt_edge.dart';

/// How much of one real debt a suggested transfer discharges.
final class ClearedDebt {
  /// Creates a discharge record.
  const ClearedDebt({required this.edge, required this.amount});

  /// The debt as it was incurred.
  final DebtEdge edge;

  /// How much of it this transfer settles. May be less than the edge's own amount.
  final Money amount;
}

/// One payment the plan suggests making.
final class SuggestedTransfer {
  /// Creates a suggested transfer.
  const SuggestedTransfer({
    required this.fromPayeeId,
    required this.toPayeeId,
    required this.amount,
    required this.clears,
  });

  /// Who pays.
  final String fromPayeeId;

  /// Who is paid.
  final String toPayeeId;

  /// How much.
  final Money amount;

  /// Which real debts this discharges, and by how much.
  ///
  /// **This is the sentence Splitwise makes its users work out for themselves.** Their forum has
  /// carried the same complaint for over a decade — *"why do I owe ₹100 to someone who never lent me
  /// money?"* — because a simplified transfer arrives with no provenance. Every transfer here can
  /// explain itself: *"₹450 to Ravi — this clears ₹300 you owe Priya and ₹150 you owe Amit."*
  final List<ClearedDebt> clears;

  /// True when this transfer settles a debt that genuinely exists between these two people.
  bool get isDirect =>
      clears.length == 1 &&
      clears.single.edge.fromPayeeId == fromPayeeId &&
      clears.single.edge.toPayeeId == toPayeeId;
}

/// A suggested way to settle up, and nothing more.
///
/// **Suggested, never applied.** The pairwise ledger is untouched, which is what makes this
/// materially different from Splitwise: their simplification rewrites the group's debt graph in
/// place, their own help centre then advises users to stop trusting the individual balances because
/// those may have been reshuffled, and turning it off does not cleanly reverse — payments already
/// made may no longer line up with the restored debts.
///
/// Accepting this plan records ordinary settlements, the same rows a manual settle-up writes. There
/// is no simplified state to get stuck in and no toggle to lock.
final class SettlementPlan {
  /// Creates a plan.
  const SettlementPlan({
    required this.transfers,
    required this.originalDebtCount,
    required this.wasPartitionedExactly,
  });

  /// A plan for nothing owed.
  const SettlementPlan.settled()
    : transfers = const [],
      originalDebtCount = 0,
      wasPartitionedExactly = true;

  /// The payments to make, in the order to make them.
  final List<SuggestedTransfer> transfers;

  /// How many real debts existed before simplifying — what the user would otherwise pay.
  final int originalDebtCount;

  /// Whether the minimum was proved rather than approached.
  ///
  /// True when the exact zero-sum partition ran; false when the group exceeded
  /// [DebtSimplifier.maxExactMembers] and the greedy fallback was used. A screen that claims
  /// "the fewest possible payments" should only say so when this is true.
  final bool wasPartitionedExactly;

  /// How many payments the plan saves.
  int get paymentsSaved => originalDebtCount - transfers.length;

  /// Whether simplifying is worth offering at all.
  bool get isImprovement => transfers.length < originalDebtCount;
}

/// Finds the fewest payments that settle a set of debts.
///
/// Pure: edges in, a plan out. No repository, no clock, no Flutter.
///
/// ## The algorithm, and why each step is there
///
/// **1. Net.** Reduce the edges to one signed balance per person. Anyone at zero drops out.
///
/// **2. Partition into zero-sum subsets.** A subset whose balances sum to zero settles internally in
/// `size - 1` transfers, so maximising the number of such subsets minimises the total. This is the
/// step that beats greedy, and it earns its place: a brute-force search over every balance vector up
/// to five people found **no** case where greedy was beaten at three or four people, and 840 cases at
/// five. The smallest is `-6, -5, +2, +4, +5` — greedy needs four payments, but `{-6,+2,+4}` and
/// `{-5,+5}` are both zero-sum, so three suffice.
///
/// **3. Greedy within each subset.** Largest debtor to largest creditor, repeatedly.
///
/// **4. Prefer real debts on ties, which costs nothing — at both levels.** Within a subset that has no
/// proper zero-sum subset of its own — guaranteed by step 2's maximality — *every* greedy pairing
/// produces exactly `size - 1` transfers. Each transfer zeroes exactly one person, because zeroing two
/// at once would require `|debt| == credit`, which would itself be a zero-sum pair that step 2 would
/// have split off. So the count is fixed no matter who is paired with whom, and preferring a creditor
/// the debtor genuinely owes is free.
///
/// The same tie-break has to apply to the **choice of partition**, and omitting it was a real bug.
/// `a` owing `b` and `c` owing `d` can be grouped as `{a,b},{c,d}` or as `{a,d},{b,c}` — both are
/// zero-sum, both give two payments, and the second suggests two payments between people who have
/// never owed each other anything. Step 2 therefore scores each candidate group by how many real
/// debts lie inside it and prefers the higher score when counts tie.
///
/// Together, those two are the direct answer to *"she never lent me money"*.
final class DebtSimplifier {
  /// Creates the simplifier. Stateless.
  const DebtSimplifier();

  /// The largest group the exact partition runs on.
  ///
  /// Above this, step 2 is skipped and the plan reports `wasPartitionedExactly: false`.
  ///
  /// **Sixteen, measured rather than guessed.** The partition enumerates submasks, which costs about
  /// `3^n` steps: 4.8 million at 14 people, 43 million at 16, and 387 million at 18. A reference
  /// implementation in Python took 360 ms at 14 and 3.1 s at 16; Dart runs this kind of tight integer
  /// loop roughly 20–50 times faster, putting the worst case near 100 ms — acceptable for a button
  /// press, and comfortably beyond any real group. An earlier draft of the plan said 20; that would
  /// have been 3.5 billion steps and minutes of work.
  static const int maxExactMembers = 16;

  /// Plans the fewest payments that settle [debts].
  ///
  /// Every edge must be in the same currency. Netting across currencies without a rate would produce
  /// a figure nobody can reproduce, so a caller with a multi-currency group calls this once per
  /// currency — which is also how the settle-up screen should present it.
  ///
  /// Throws [CurrencyMismatchError] on mixed currencies and [ArgumentError] on a non-positive or
  /// self-directed edge.
  SettlementPlan plan(List<DebtEdge> debts) {
    final live = <DebtEdge>[];
    String? currency;
    for (final debt in debts) {
      if (debt.amount.isZero) continue;
      if (!debt.amount.isPositive) {
        throw ArgumentError.value(
          debt.amount.minor,
          'debts',
          'an edge amount must be positive — reverse the direction instead',
        );
      }
      if (debt.fromPayeeId == debt.toPayeeId) {
        throw ArgumentError.value(
          debt.fromPayeeId,
          'debts',
          'cannot owe yourself',
        );
      }
      currency ??= debt.amount.currencyCode;
      if (debt.amount.currencyCode != currency) {
        throw CurrencyMismatchError(currency, debt.amount.currencyCode);
      }
      live.add(debt);
    }
    if (live.isEmpty || currency == null) return const SettlementPlan.settled();

    // Step 1 — net. Insertion order is kept so the output is stable for a given input.
    final balances = <String, int>{};
    final order = <String>[];
    void touch(String id) {
      if (!balances.containsKey(id)) {
        balances[id] = 0;
        order.add(id);
      }
    }

    for (final debt in live) {
      touch(debt.fromPayeeId);
      touch(debt.toPayeeId);
      balances[debt.fromPayeeId] =
          balances[debt.fromPayeeId]! - debt.amount.minor;
      balances[debt.toPayeeId] = balances[debt.toPayeeId]! + debt.amount.minor;
    }
    final people = order.where((id) => balances[id] != 0).toList();
    if (people.isEmpty) {
      // Everything cancels out. Real: A owes B ₹100 and B owes A ₹100.
      return SettlementPlan(
        transfers: const [],
        originalDebtCount: live.length,
        wasPartitionedExactly: true,
      );
    }

    // Step 2 — partition.
    final exact = people.length <= maxExactMembers;
    final groups = exact
        ? _maximalZeroSumGroups(people, balances, live)
        : [people];

    // Steps 3 and 4 — greedy within each group, preferring debts that really exist.
    final owedBetween = <String, Map<String, int>>{};
    for (final debt in live) {
      (owedBetween[debt.fromPayeeId] ??= {}).update(
        debt.toPayeeId,
        (existing) => existing + debt.amount.minor,
        ifAbsent: () => debt.amount.minor,
      );
    }

    final outstanding = <String, List<_Outstanding>>{};
    for (final debt in live) {
      (outstanding[debt.fromPayeeId] ??= []).add(_Outstanding(debt));
    }
    for (final entries in outstanding.values) {
      entries.sort((a, b) {
        final byAmount = b.edge.amount.minor.compareTo(a.edge.amount.minor);
        return byAmount != 0
            ? byAmount
            : a.edge.toPayeeId.compareTo(b.edge.toPayeeId);
      });
    }

    final transfers = <SuggestedTransfer>[];
    for (final group in groups) {
      transfers.addAll(
        _settleGroup(
          group: group,
          balances: Map<String, int>.fromEntries(
            group.map((id) => MapEntry(id, balances[id]!)),
          ),
          owedBetween: owedBetween,
          outstanding: outstanding,
          currencyCode: currency,
        ),
      );
    }

    return SettlementPlan(
      transfers: transfers,
      originalDebtCount: live.length,
      wasPartitionedExactly: exact,
    );
  }

  /// Splits [people] into as many zero-sum groups as possible, preferring groups that hold real
  /// debts.
  ///
  /// Subset dynamic programming: for each mask, try every submask containing the lowest set bit that
  /// itself sums to zero, and take the best count from the rest. `parts[mask]` is the most zero-sum
  /// groups that exactly cover `mask`, or -1 when the mask cannot be covered at all.
  ///
  /// **`edgesInside` is the tie-break, and leaving it out was a real shortfall.** Two people owing two
  /// other people the same amount can be partitioned as `{a,b}` and `{c,d}` — the pairs that actually
  /// transacted — or as `{a,d}` and `{b,c}`, which are equally zero-sum and produce two payments
  /// between people who have never owed each other anything. Both partitions give the same *count*, so
  /// counting alone cannot choose, and the submask enumeration happened to reach the wrong one first.
  ///
  /// Scoring each candidate group by how many real debts lie entirely inside it, and preferring the
  /// higher score when the counts tie, picks the partition that matches what people did. It is free:
  /// the count is already equal, which is the whole reason a tie-break is possible.
  List<List<String>> _maximalZeroSumGroups(
    List<String> people,
    Map<String, int> balances,
    List<DebtEdge> debts,
  ) {
    final n = people.length;
    final full = (1 << n) - 1;
    final index = <String, int>{
      for (var i = 0; i < n; i++) people[i]: i,
    };

    final sums = List<int>.filled(1 << n, 0);
    for (var mask = 1; mask <= full; mask++) {
      final low = mask & -mask;
      final at = low.bitLength - 1;
      sums[mask] = sums[mask ^ low] + balances[people[at]]!;
    }

    // How many real debts join this person to each other person. Built once so the mask sweep below
    // stays proportional to a person's degree rather than to the whole edge list.
    final degree = List<Map<int, int>>.generate(n, (_) => <int, int>{});
    for (final debt in debts) {
      final from = index[debt.fromPayeeId];
      final to = index[debt.toPayeeId];
      // A person whose net balance is zero is not in [people] and so has no index — their debts
      // cancelled out and cannot influence how the rest is grouped.
      if (from == null || to == null) continue;
      degree[from].update(to, (n) => n + 1, ifAbsent: () => 1);
      degree[to].update(from, (n) => n + 1, ifAbsent: () => 1);
    }

    final edgesInside = List<int>.filled(1 << n, 0);
    for (var mask = 1; mask <= full; mask++) {
      final low = mask & -mask;
      final at = low.bitLength - 1;
      final rest = mask ^ low;
      var added = 0;
      for (final entry in degree[at].entries) {
        if (rest >> entry.key & 1 == 1) added += entry.value;
      }
      edgesInside[mask] = edgesInside[rest] + added;
    }

    const unreachable = -1;
    final parts = List<int>.filled(1 << n, unreachable);
    final score = List<int>.filled(1 << n, -1);
    final chosen = List<int>.filled(1 << n, 0);
    parts[0] = 0;
    score[0] = 0;
    for (var mask = 1; mask <= full; mask++) {
      final low = mask & -mask;
      var best = unreachable;
      var bestScore = -1;
      var bestSub = 0;
      // Every submask of `mask` that contains its lowest bit, so each group is counted once.
      for (var sub = mask; sub != 0; sub = (sub - 1) & mask) {
        if (sub & low == 0) continue;
        if (sums[sub] != 0) continue;
        final rest = parts[mask ^ sub];
        if (rest == unreachable) continue;
        final candidate = rest + 1;
        final candidateScore = score[mask ^ sub] + edgesInside[sub];
        if (candidate > best ||
            (candidate == best && candidateScore > bestScore)) {
          best = candidate;
          bestScore = candidateScore;
          bestSub = sub;
        }
      }
      parts[mask] = best;
      score[mask] = bestScore;
      chosen[mask] = bestSub;
    }

    // The whole set always sums to zero, so it is always coverable — worst case as one group.
    final groups = <List<String>>[];
    var mask = full;
    while (mask != 0) {
      final sub = chosen[mask];
      if (sub == 0) {
        groups.add([
          for (var i = 0; i < n; i++)
            if (mask >> i & 1 == 1) people[i],
        ]);
        break;
      }
      groups.add([
        for (var i = 0; i < n; i++)
          if (sub >> i & 1 == 1) people[i],
      ]);
      mask ^= sub;
    }
    return groups;
  }

  /// Greedy settlement within one group, preferring creditors the debtor genuinely owes.
  List<SuggestedTransfer> _settleGroup({
    required List<String> group,
    required Map<String, int> balances,
    required Map<String, Map<String, int>> owedBetween,
    required Map<String, List<_Outstanding>> outstanding,
    required String currencyCode,
  }) {
    final working = Map<String, int>.of(balances);
    final transfers = <SuggestedTransfer>[];

    while (true) {
      String? debtor;
      String? creditor;
      for (final id in group) {
        final value = working[id]!;
        if (value < 0 && (debtor == null || value < working[debtor]!))
          debtor = id;
      }
      if (debtor == null) break;

      // Among creditors, prefer one this debtor really owes. Free, because every pairing in a group
      // with no proper zero-sum subset yields the same number of transfers — see the class doc.
      final directly = owedBetween[debtor] ?? const <String, int>{};
      for (final id in group) {
        final value = working[id]!;
        if (value <= 0) continue;
        if (creditor == null) {
          creditor = id;
          continue;
        }
        final currentIsDirect = directly.containsKey(creditor);
        final candidateIsDirect = directly.containsKey(id);
        if (candidateIsDirect != currentIsDirect) {
          if (candidateIsDirect) creditor = id;
          continue;
        }
        if (value > working[creditor]!) creditor = id;
      }
      if (creditor == null) break;

      final amount = -working[debtor]! < working[creditor]!
          ? -working[debtor]!
          : working[creditor]!;
      if (amount <= 0) break;

      working[debtor] = working[debtor]! + amount;
      working[creditor] = working[creditor]! - amount;

      transfers.add(
        SuggestedTransfer(
          fromPayeeId: debtor,
          toPayeeId: creditor,
          amount: Money(amount, currencyCode),
          clears: _attribute(
            debtor: debtor,
            amountMinor: amount,
            outstanding: outstanding,
            currencyCode: currencyCode,
          ),
        ),
      );
    }
    return transfers;
  }

  /// Charges [amountMinor] against the debtor's own real debts, largest first.
  ///
  /// This is what lets a transfer explain itself. The debts are consumed as they are attributed, so
  /// two transfers by the same person never claim to clear the same debt twice.
  List<ClearedDebt> _attribute({
    required String debtor,
    required int amountMinor,
    required Map<String, List<_Outstanding>> outstanding,
    required String currencyCode,
  }) {
    final cleared = <ClearedDebt>[];
    var left = amountMinor;
    for (final entry in outstanding[debtor] ?? const <_Outstanding>[]) {
      if (left <= 0) break;
      if (entry.remaining <= 0) continue;
      final taken = entry.remaining < left ? entry.remaining : left;
      entry.remaining -= taken;
      left -= taken;
      cleared.add(
        ClearedDebt(edge: entry.edge, amount: Money(taken, currencyCode)),
      );
    }
    return cleared;
  }
}

/// A real debt with however much of it is still unattributed.
final class _Outstanding {
  _Outstanding(this.edge) : remaining = edge.amount.minor;

  final DebtEdge edge;
  int remaining;
}
