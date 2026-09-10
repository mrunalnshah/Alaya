import 'package:alaya/core/money/money.dart';

/// One debt as it was actually incurred: [fromPayeeId] owes [toPayeeId] this much.
///
/// **Here rather than inside `debt_simplifier.dart`, where it was declared.** Three things name this
/// type now — `SplitLedgerRepository.debtsIn` returns a list of them, `SplitBalanceService` groups them
/// by currency, and the settle-up screen renders what each transfer clears. A repository contract
/// importing a *service* to name its own return type is the wrong direction, and it is the fault
/// `SplitLedgerRepository` has carried a note about since session 3a.
///
/// The move is invisible to callers: `debt_simplifier.dart` re-exports this file, so every existing
/// `import '.../debt_simplifier.dart'` still resolves `DebtEdge`. New code should import this path.
///
/// **An edge, not a balance, and the distinction is load-bearing.** `DebtSimplifier` prefers transfers
/// along debts that genuinely exist, so it needs the pairs as they happened rather than one netted
/// figure per person. Handing it balances would silently disable its best tie-break — which is exactly
/// what `debtsIn` does today, and says so.
final class DebtEdge {
  /// Creates an edge.
  const DebtEdge({
    required this.fromPayeeId,
    required this.toPayeeId,
    required this.amount,
  });

  /// Who owes.
  final String fromPayeeId;

  /// Who is owed.
  final String toPayeeId;

  /// How much. Always positive — the direction is in the field names.
  final Money amount;
}
