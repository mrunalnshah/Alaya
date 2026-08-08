/// View-model providers for the transaction list (ARCH_5 U19).
///
/// **Not one repository or engine provider here.** Every dependency is watched from
/// `app/providers/`, which is what stops one repository acquiring three providers and
/// `ItemCategoryResolver` — which caches — being constructed once per feature.
library;

import 'package:alaya/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/services/date_range_service.dart';
import 'package:alaya/features/expense/state/transaction_filter.dart';

/// The list's active filter.
///
/// A plain `Notifier` rather than a family: there is one transaction list, and giving it a family
/// argument it never varies over would create a second instance the first time a caller passed a
/// different key.
final transactionFilterProvider =
    NotifierProvider<TransactionFilterNotifier, TransactionFilter>(
      TransactionFilterNotifier.new,
    );

/// Mutates the transaction list's filter.
class TransactionFilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() => const TransactionFilter();

  /// Sets the reporting window to a named preset, dropping any hand-picked range.
  void setPreset(DateRangePreset preset) =>
      state = state.copyWith(preset: preset, clearCustomRange: true);

  /// Sets a hand-picked window.
  void setCustomRange(DateRange range) => state = state.copyWith(
    preset: DateRangePreset.custom,
    customRange: range,
  );

  /// Adds or removes a kind from the filter.
  void toggleKind(TransactionKind kind) {
    final next = {...state.kinds};
    if (next.contains(kind)) {
      next.remove(kind);
    } else {
      next.add(kind);
    }
    state = state.copyWith(kinds: next);
  }

  /// Adds or removes a subtype from the filter.
  void toggleSubtype(TransactionSubtype subtype) {
    final next = {...state.subtypes};
    if (next.contains(subtype)) {
      next.remove(subtype);
    } else {
      next.add(subtype);
    }
    state = state.copyWith(subtypes: next);
  }

  /// Restricts to one account, or clears the restriction when [accountId] is null.
  void setAccount(String? accountId) => state = accountId == null
      ? state.copyWith(clearAccount: true)
      : state.copyWith(accountId: accountId);

  /// Restricts to one payee, or clears the restriction when [payeeId] is null.
  void setPayee(String? payeeId) => state = payeeId == null
      ? state.copyWith(clearPayee: true)
      : state.copyWith(payeeId: payeeId);

  /// Shows only the transactions the needs-review nudge is counting.
  ///
  /// Widens the window to all time at the same time: a flagged transaction from six weeks ago is
  /// exactly the one the nudge exists to surface, and leaving the default thirty-day window on
  /// would hide it behind the very count that pointed at it.
  void showNeedsReviewOnly() => state = state.copyWith(
    needsReviewOnly: true,
    preset: DateRangePreset.allTime,
    clearCustomRange: true,
  );

  /// Stops restricting to flagged transactions.
  void clearNeedsReviewOnly() => state = state.copyWith(needsReviewOnly: false);

  /// Returns to the default window with nothing else narrowed.
  void clear() => state = const TransactionFilter();
}

/// The date window the current filter resolves to.
///
/// Resolved through `DateRangeService` against the injected clock, never `DateTime.now()`, so a
/// date-sensitive widget test is reproducible.
final transactionRangeProvider = Provider<DateRange>((ref) {
  final filter = ref.watch(transactionFilterProvider);
  final service = ref.watch(dateRangeServiceProvider);
  final today = ref.watch(clockProvider).today();
  if (filter.preset == DateRangePreset.custom) {
    return filter.customRange ?? (from: DateRangeService.earliest, to: today);
  }
  return service.resolve(filter.preset, today) ??
      (from: DateRangeService.earliest, to: today);
});

/// The filtered transactions, newest first.
///
/// The date window is applied by the indexed query; the rest is applied in Dart, because those
/// predicates are over a page of rows rather than the whole table.
final filteredTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final filter = ref.watch(transactionFilterProvider);
  final range = ref.watch(transactionRangeProvider);
  return ref
      .watch(transactionRepositoryProvider)
      .watchByDateRange(from: range.from, to: range.to)
      .map(
        (rows) => rows
            .where(
              (t) => filter.admits(
                kind: t.kind,
                subtype: t.subtype,
                fromAccountId: t.fromAccountId,
                toAccountId: t.toAccountId,
                transactionPayeeId: t.payeeId,
                needsReview: t.needsReview,
              ),
            )
            .toList(),
      );
});

/// One day's transactions, for a sticky header.
class TransactionDayGroup {
  /// Creates a day group.
  const TransactionDayGroup({required this.date, required this.transactions});

  /// The civil date these share.
  final DateKey date;

  /// The transactions on [date], newest first.
  final List<Transaction> transactions;
}

/// The filtered transactions grouped into days, newest day first.
final transactionDaysProvider = Provider<AsyncValue<List<TransactionDayGroup>>>(
  (ref) => ref.watch(filteredTransactionsProvider).whenData(_groupByDay),
);

List<TransactionDayGroup> _groupByDay(List<Transaction> rows) {
  final groups = <int, List<Transaction>>{};
  for (final row in rows) {
    groups.putIfAbsent(row.dateKey.value, () => <Transaction>[]).add(row);
  }
  final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final date in dates)
      TransactionDayGroup(date: DateKey(date), transactions: groups[date]!),
  ];
}

/// How many transactions still need details, for the nudge.
final needsReviewCountProvider = StreamProvider<int>(
  (ref) => ref.watch(transactionRepositoryProvider).watchNeedsReviewCount(),
);

/// Accounts by id, so a row can name one without a query per row.
final accountsByIdProvider = StreamProvider<Map<String, Account>>(
  (ref) => ref
      .watch(accountRepositoryProvider)
      .watchAllIncludingArchived()
      .map((rows) => {for (final row in rows) row.id: row}),
);

/// Selectable accounts in sort order, for a picker or a chip row.
final selectableAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// Payees by id, so a row can name one without a query per row.
final payeesByIdProvider = StreamProvider<Map<String, Payee>>(
  (ref) => ref
      .watch(payeeRepositoryProvider)
      .watchAll()
      .map((rows) => {for (final row in rows) row.id: row}),
);

/// The home currency's code, defaulting to INR before onboarding has run.
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
