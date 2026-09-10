/// View-model state for the funds header (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/account_balance.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/services/balance_service.dart';

/// The home currency every figure on the dashboard is expressed in.
final dashboardCurrencyProvider = FutureProvider<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      'INR',
);

/// The home currency's decimal precision (ARCH_1 §4.1).
final dashboardDigitsProvider = FutureProvider<int>((ref) async {
  final code = await ref.watch(dashboardCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// Every account, so a balance can be paired with its net-worth flag.
final dashboardAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAllIncludingArchived(),
);

/// Per-account balances, straight from `v_account_ledger`.
final dashboardBalancesProvider = StreamProvider<List<AccountBalance>>(
  (ref) => ref.watch(accountRepositoryProvider).watchBalances(),
);

/// Total available funds — the one headline figure on the dashboard.
///
/// **`BalanceService.totalInHome` and nothing else.** `AccountRepository.watchTotalInHomeCurrency` was a
/// second answer to the same question and is dropped by this phase (ARCH_4 §5.1 item 13); two sources is
/// how a dashboard starts disagreeing with itself.
///
/// **A self-transfer nets to zero here by construction.** The balances come from `v_account_ledger`,
/// which counts a transfer once against each side — so moving money between your own accounts leaves the
/// sum untouched. If this figure ever moves on a transfer, the view is being bypassed, not the maths.
///
/// **Unconvertible balances are excluded, never guessed at** (anomaly A34). `NetWorth` carries the count
/// so the header can say so rather than quietly under-reporting.
final totalFundsProvider = FutureProvider<NetWorth>((ref) async {
  final accounts = await ref.watch(dashboardAccountsProvider.future);
  final balances = await ref.watch(dashboardBalancesProvider.future);
  final code = await ref.watch(dashboardCurrencyProvider.future);

  final flags = <String, bool>{
    for (final account in accounts) account.id: account.includeInNetWorth,
  };
  return ref
      .watch(balanceServiceProvider)
      .totalInHome(
        balances: [
          for (final balance in balances)
            AccountBalanceInput(
              accountId: balance.accountId,
              balance: balance.balance,
              // An account excluded from net worth is excluded here too. A loan you are servicing is
              // real money owed and belongs in the ledger, but it is not money you can spend today.
              includeInNetWorth: flags[balance.accountId] ?? true,
            ),
        ],
        rates: ref.watch(currencyRateServiceProvider),
        homeCurrencyCode: code,
        asOf: ref.watch(clockProvider).today(),
      );
});

/// One account, as the breakdown shows it.
///
/// Carries the converted figure **and** the original, because a total that was converted cannot be
/// explained by a list of raw balances — they would not add up to the number the user tapped. Showing
/// both is what `BalanceService.convertOne` was built for; its doc comment says so, and until now
/// nothing called it.
class FundsRow {
  /// Creates a row.
  const FundsRow({
    required this.account,
    required this.original,
    required this.converted,
    required this.quality,
    required this.countsToward,
  });

  /// The account.
  final Account account;

  /// Its balance in its own currency.
  final Money original;

  /// The same balance in the home currency, or null when no rate could be found.
  ///
  /// **Null is displayed as null, never as zero** (anomaly A34). An account whose currency has no rate is
  /// excluded from the headline figure, and the row says so rather than contributing a silent nothing.
  final Money? converted;

  /// How trustworthy the conversion is.
  final RateQuality quality;

  /// Whether this account is part of the headline total.
  ///
  /// False for anything flagged out of net worth — a loan is real money owed but not money you can spend
  /// today. The row still appears, greyed, because a breakdown that omits accounts is a breakdown nobody
  /// can reconcile against their own bank.
  final bool countsToward;
}

/// Every account with its balance, for the sheet behind the headline figure.
///
/// **Composed from the providers the header already uses**, so the sheet and the total cannot disagree.
/// A second query for the same numbers is how a dashboard starts contradicting itself — the same reason
/// `watchTotalInHomeCurrency` was dropped in Phase 4 (ARCH_4 §5.1 item 13).
///
/// Sorted by converted magnitude, largest first: somebody opening this wants to know where the money is,
/// and alphabetical ordering answers a question nobody asked.
final fundsBreakdownProvider = FutureProvider<List<FundsRow>>((ref) async {
  final accounts = await ref.watch(dashboardAccountsProvider.future);
  final balances = await ref.watch(dashboardBalancesProvider.future);
  final code = await ref.watch(dashboardCurrencyProvider.future);
  final table = await ref.watch(currencyRateServiceProvider).table();
  final service = ref.watch(balanceServiceProvider);
  final asOf = ref.watch(clockProvider).today();

  final byId = {for (final account in accounts) account.id: account};
  final rows = <FundsRow>[];
  for (final balance in balances) {
    final account = byId[balance.accountId];
    if (account == null) continue;
    final result = service.convertOne(
      balance: balance.balance,
      table: table,
      homeCurrencyCode: code,
      asOf: asOf,
    );
    rows.add(
      FundsRow(
        account: account,
        original: balance.balance,
        converted: result.converted,
        quality: result.quality,
        countsToward: account.includeInNetWorth,
      ),
    );
  }
  rows.sort((a, b) {
    // The field is `minor`. I used a longer name from memory that has never existed — `Money`'s own doc
    // comment states it, and reading the declaration would have cost ten seconds against two rounds.
    final left = a.converted?.minor ?? 0;
    final right = b.converted?.minor ?? 0;
    return right.compareTo(left);
  });
  return rows;
});
