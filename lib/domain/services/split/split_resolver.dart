import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';

/// One participant's instruction for how much they owe.
final class ShareInput {
  /// Creates an input. Prefer the named constructors.
  const ShareInput({required this.payeeId, required this.kind, this.value});

  /// An equal share of the remainder.
  const ShareInput.equal(String payeeId)
    : this(payeeId: payeeId, kind: ShareInputKind.equal);

  /// A fixed [minorUnits] amount that is this person's entire share.
  const ShareInput.exact(String payeeId, int minorUnits)
    : this(payeeId: payeeId, kind: ShareInputKind.exact, value: minorUnits);

  /// [minorUnits] charged to this person **on top of** an equal share of the remainder.
  ///
  /// Their drinks, or their half of the taxi, or the amount somebody volunteered to cover.
  const ShareInput.extra(String payeeId, int minorUnits)
    : this(payeeId: payeeId, kind: ShareInputKind.extra, value: minorUnits);

  /// [basisPoints] of the total — 2500 is 25%.
  const ShareInput.percent(String payeeId, int basisPoints)
    : this(payeeId: payeeId, kind: ShareInputKind.percent, value: basisPoints);

  /// A [weight] against the other weighted participants.
  const ShareInput.shares(String payeeId, int weight)
    : this(payeeId: payeeId, kind: ShareInputKind.shares, value: weight);

  /// Who owes.
  final String payeeId;

  /// How their share was specified.
  final ShareInputKind kind;

  /// Minor units for [ShareInputKind.exact] and [ShareInputKind.extra], basis points for
  /// [ShareInputKind.percent], a weight for [ShareInputKind.shares], and null for
  /// [ShareInputKind.equal].
  final int? value;

  /// Whether this participant takes part in dividing the remainder.
  ///
  /// Everyone except [ShareInputKind.exact] and [ShareInputKind.percent], both of which name a whole
  /// share and are finished once named.
  bool get sharesRemainder =>
      kind == ShareInputKind.equal ||
      kind == ShareInputKind.shares ||
      kind == ShareInputKind.extra;

  /// This participant's weight in the remainder.
  ///
  /// One for [ShareInputKind.extra]: an extra says what somebody additionally owes, not how the rest
  /// is divided, so they take an ordinary share of it.
  int get weight => switch (kind) {
    ShareInputKind.shares => value ?? 0,
    ShareInputKind.equal || ShareInputKind.extra => 1,
    ShareInputKind.exact || ShareInputKind.percent => 0,
  };
}

/// One line of an itemised split, with its own participants.
final class SplitLine {
  /// Creates a line.
  const SplitLine({
    required this.lineNo,
    required this.amount,
    required this.inputs,
  });

  /// The `transaction_lines.lineNo` this line corresponds to.
  final int lineNo;

  /// What the line cost.
  final Money amount;

  /// Who is on the hook for it, and how.
  final List<ShareInput> inputs;
}

/// What one participant ends up owing.
final class ResolvedShare {
  /// Creates a resolved share.
  const ResolvedShare({
    required this.payeeId,
    required this.amount,
    required this.inputs,
    this.extra,
    this.fromRemainder,
  });

  /// Who owes.
  final String payeeId;

  /// The exact amount, after allocation. Sums with its siblings to the allocated total.
  final Money amount;

  /// The inputs that produced it — more than one when the split was itemised.
  final List<ShareInput> inputs;

  /// The part of [amount] charged to this person alone, when they had an extra.
  ///
  /// Carried so a screen can show *"₹1,150 + ₹400 drinks"* rather than a bare ₹1,550 that reads like
  /// arithmetic nobody can check. A total a person cannot decompose is one they argue with.
  final Money? extra;

  /// The part of [amount] that came from dividing the remainder.
  final Money? fromRemainder;
}

/// A resolved split, including what it failed to account for.
final class SplitResolution {
  /// Creates a resolution.
  const SplitResolution({
    required this.total,
    required this.shares,
    required this.allocated,
  });

  /// What was being split.
  final Money total;

  /// Each participant's share, in the order the inputs arrived.
  final List<ResolvedShare> shares;

  /// The sum of [shares].
  final Money allocated;

  /// What is left over — [total] minus [allocated].
  ///
  /// **Reported, never absorbed.** Percentages that sum to 90% leave 10% unallocated, and exact
  /// amounts that overshoot leave it negative. `transaction_lines` already surfaces "₹500 total,
  /// ₹480 of lines → unallocated ₹20" rather than adjusting one of them, and a split is the same
  /// problem: quietly rounding a shortfall onto the last participant is how somebody ends up paying
  /// for a discrepancy nobody told them about.
  Money get unallocated => total - allocated;

  /// Whether the shares account for the total exactly.
  bool get isExact => unallocated.isZero;

  /// Whether the shares add up to more than the total.
  bool get isOverAllocated => unallocated.isNegative;
}

/// Turns split instructions into exact amounts.
///
/// Pure: money and instructions in, money out. No repository, no clock, no Flutter.
///
/// **A mismatch is a state, not a failure.** The editor shows live amounts as the user types, so a
/// resolver that threw on percentages totalling 90% would be unusable — the user is *mid-edit*. The
/// resolution carries [SplitResolution.unallocated] and the screen decides what to say about it.
/// `ArgumentError` is reserved for things a user cannot cause: no participants, a duplicate
/// participant, a negative weight.
///
/// ## The order of operations, and why it is this one
///
/// 1. **Exact amounts** come off the total first. "Priya owes exactly ₹500" is a fact, not a share,
///    and she takes no part in what follows.
/// 2. **Extras** come off next, and the person who owes one **stays in** for step 4. That single
///    difference is what lets one bill say "Ravi's drinks were ₹400" and "I'll cover ₹2,000" — the
///    same operation from two directions, and the thing the first version of this class could not
///    express at all.
/// 3. **Percentages** apply to the **total**, not to the remainder. A user who says "Priya covers
///    25%" means a quarter of the bill; making it a quarter of what is left would silently change
///    the number they typed.
/// 4. **Weights** — `equal`, `shares`, and anyone carrying an extra — divide **whatever remains**.
///
/// Mixing `percent` with weights in one split is refused. Both are proportional and the combination
/// has no single defensible reading; being told so beats getting a number nobody can explain.
final class SplitResolver {
  /// Creates the resolver. Stateless.
  const SplitResolver();

  /// Resolves [inputs] against [total].
  SplitResolution resolve({
    required Money total,
    required List<ShareInput> inputs,
  }) {
    if (inputs.isEmpty) {
      throw ArgumentError.value(inputs, 'inputs', 'must not be empty');
    }
    final seen = <String>{};
    for (final input in inputs) {
      if (!seen.add(input.payeeId)) {
        throw ArgumentError.value(
          input.payeeId,
          'inputs',
          'appears twice — one participant has one share per split',
        );
      }
      final value = input.value;
      if (value != null && value < 0) {
        throw ArgumentError.value(
          value,
          'inputs',
          'an amount, percentage or weight must not be negative',
        );
      }
    }

    final hasPercent = inputs.any((i) => i.kind == ShareInputKind.percent);
    final hasWeights = inputs.any((i) => i.sharesRemainder);
    if (hasPercent && hasWeights) {
      throw ArgumentError.value(
        inputs,
        'inputs',
        'mixes percent with weights — both are proportional and the combination has no single '
            'reading. Use one or the other, or exact amounts alongside either.',
      );
    }

    final code = total.currencyCode;
    final own = <String, Money>{
      for (final i in inputs) i.payeeId: Money.zero(code),
    };
    final extras = <String, Money>{};
    final fromRest = <String, Money>{};
    var claimed = 0;

    // Step 1 — exact amounts, taken as given.
    for (final input in inputs) {
      if (input.kind != ShareInputKind.exact) continue;
      final minor = input.value ?? 0;
      own[input.payeeId] = Money(minor, code);
      claimed += minor;
    }

    // Step 2 — extras, charged to one person and still leaving them in the division below.
    for (final input in inputs) {
      if (input.kind != ShareInputKind.extra) continue;
      final minor = input.value ?? 0;
      final amount = Money(minor, code);
      extras[input.payeeId] = amount;
      own[input.payeeId] = amount;
      claimed += minor;
    }

    // Step 3 — percentages, of the total.
    final percentInputs = inputs
        .where((i) => i.kind == ShareInputKind.percent)
        .toList();
    if (percentInputs.isNotEmpty) {
      var basisPoints = 0;
      for (final input in percentInputs) {
        basisPoints += input.value ?? 0;
      }
      if (basisPoints > 0 && basisPoints <= 10000) {
        // Allocated against a notional 10,000 basis points, with the unassigned share as the last
        // weight, so the parts stay exact and the shortfall surfaces as `unallocated` rather than
        // being spread across whoever happens to be listed.
        final weights = [
          for (final input in percentInputs) input.value ?? 0,
          if (basisPoints < 10000) 10000 - basisPoints,
        ];
        final parts = total.allocate(weights);
        for (var i = 0; i < percentInputs.length; i++) {
          own[percentInputs[i].payeeId] = parts[i];
          claimed += parts[i].minor;
        }
      } else if (basisPoints > 10000) {
        // **Over 100%, and allocation is the wrong tool.** `allocate` divides by the *sum* of the
        // weights it is given, so 70% and 70% would come back as 50% and 50% — renormalising the
        // overshoot away and reporting a perfectly balanced split. That is the clamping this
        // resolver exists not to do, and a test caught it.
        final magnitude = total.isNegative ? -total.minor : total.minor;
        for (final input in percentInputs) {
          final share = (magnitude * (input.value ?? 0) + 5000) ~/ 10000;
          final signed = total.isNegative ? -share : share;
          own[input.payeeId] = Money(signed, code);
          claimed += signed;
        }
      }
    }

    // Step 4 — weights, over what is left. Anyone with an extra is here too, at weight one.
    final weighted = inputs.where((i) => i.sharesRemainder).toList();
    if (weighted.isNotEmpty) {
      final remaining = Money(total.minor - claimed, code);
      var weightTotal = 0;
      final weights = <int>[];
      for (final input in weighted) {
        weights.add(input.weight);
        weightTotal += input.weight;
      }
      // **Only divided when it points the same way as the total.** Exact amounts and extras that
      // overshoot leave a negative remainder, and allocating that would hand somebody a negative
      // share — which reads as being *owed* money by a bill they are paying. They stay at zero and
      // the overshoot surfaces in `unallocated`, so nothing is hidden. The sign comparison rather
      // than `isPositive` is what keeps a refund split working.
      final sameDirection = remaining.isNegative == total.isNegative;
      if (weightTotal > 0 && !remaining.isZero && sameDirection) {
        final parts = remaining.allocate(weights);
        for (var i = 0; i < weighted.length; i++) {
          final id = weighted[i].payeeId;
          fromRest[id] = parts[i];
          own[id] = (own[id] ?? Money.zero(code)) + parts[i];
        }
      }
    }

    var allocated = Money.zero(code);
    final shares = <ResolvedShare>[];
    for (final input in inputs) {
      final amount = own[input.payeeId]!;
      shares.add(
        ResolvedShare(
          payeeId: input.payeeId,
          amount: amount,
          inputs: [input],
          extra: extras[input.payeeId],
          fromRemainder: fromRest[input.payeeId],
        ),
      );
      allocated += amount;
    }
    return SplitResolution(total: total, shares: shares, allocated: allocated);
  }

  /// Resolves an itemised split: each line divided among its own participants, then summed per
  /// person.
  ///
  /// [total] is the expense's own total, which is **not** assumed to equal the sum of the lines —
  /// `transactions.originalAmountMinor` is the source of truth and lines are optional detail
  /// (ARCH_2 §4.2). Anything the lines do not cover, and anything a line's own shares do not cover,
  /// both land in [SplitResolution.unallocated].
  SplitResolution resolvePerLine({
    required Money total,
    required List<SplitLine> lines,
  }) {
    if (lines.isEmpty) {
      throw ArgumentError.value(lines, 'lines', 'must not be empty');
    }

    final amounts = <String, Money>{};
    final inputsByPayee = <String, List<ShareInput>>{};
    final order = <String>[];

    for (final line in lines) {
      if (line.amount.currencyCode != total.currencyCode) {
        throw ArgumentError.value(
          line.lineNo,
          'lines',
          'line ${line.lineNo} is in ${line.amount.currencyCode}, not ${total.currencyCode}',
        );
      }
      final resolved = resolve(total: line.amount, inputs: line.inputs);
      for (final share in resolved.shares) {
        if (!inputsByPayee.containsKey(share.payeeId)) {
          inputsByPayee[share.payeeId] = [];
          amounts[share.payeeId] = Money.zero(total.currencyCode);
          order.add(share.payeeId);
        }
        amounts[share.payeeId] = amounts[share.payeeId]! + share.amount;
        inputsByPayee[share.payeeId]!.addAll(share.inputs);
      }
    }

    var allocated = Money.zero(total.currencyCode);
    final shares = <ResolvedShare>[];
    for (final payeeId in order) {
      final amount = amounts[payeeId]!;
      shares.add(
        ResolvedShare(
          payeeId: payeeId,
          amount: amount,
          inputs: inputsByPayee[payeeId]!,
        ),
      );
      allocated += amount;
    }
    return SplitResolution(total: total, shares: shares, allocated: allocated);
  }
}
