import 'package:alaya/core/money/money.dart';

/// One account's derived balance — opening balance plus the sum of its ledger legs.
///
/// Read-only by nature: no repository writes a balance, because no total is ever stored (Law L3).
/// It comes from `v_account_balances`, which is what makes a self-transfer net to zero by
/// construction rather than by arithmetic anyone has to get right (anomaly A02).
class AccountBalance {
  /// Creates a balance.
  const AccountBalance({
    required this.accountId,
    required this.balance,
  });

  /// The account this balance belongs to.
  final String accountId;

  /// The balance, in the account's own currency.
  ///
  /// Never sum these across accounts without converting first — they may be in different
  /// currencies (anomaly A34).
  final Money balance;

  /// True when the account is overdrawn.
  bool get isNegative => balance.isNegative;

  @override
  bool operator ==(Object other) =>
      other is AccountBalance && other.accountId == accountId && other.balance == balance;

  @override
  int get hashCode => Object.hash(accountId, balance);

  @override
  String toString() => 'AccountBalance($accountId: $balance)';
}