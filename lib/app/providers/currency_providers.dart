/// The home currency, and the precision every amount is rendered at.
///
/// **App-level, not expense-level.** Both providers below lived in
/// `features/expense/providers/transaction_list_providers.dart`, which meant the split module, the
/// analytics cards and anything else needing a decimal precision had to import a *transaction list* to
/// get one. The split module very nearly declared its own instead — which would have been two sources
/// for one fact, and the reason JPY renders with 0 digits in some places and 2 in others.
///
/// Nothing about a home currency is about a list of transactions. It belongs beside `clockProvider`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';

/// The code the app reports in, defaulting to INR before onboarding has run.
final homeCurrencyCodeProvider = FutureProvider<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      'INR',
);

/// The home currency's decimal digits, so no amount hardcodes 2 (ARCH_1 §4.1).
///
/// JPY is 0 and the rest are 2, which is exactly why the figure is read from the `currencies` row
/// rather than assumed at each call site.
final homeDecimalDigitsProvider = FutureProvider<int>((ref) async {
  final code = await ref.watch(homeCurrencyCodeProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});
