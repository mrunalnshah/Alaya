/// View-model state for the funds header (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/account_balance.dart';
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
