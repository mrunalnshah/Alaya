/// View-model state for the analytics drill-down (ARCH_5 U19).
///
/// **Every axis here is answerable from what `TransactionRepository` already exposes.** Four come
/// from fields the `Transaction` entity carries, so the window's indexed query does the narrowing and
/// the predicate runs over a page of rows rather than the table. `item` needs one extra stream and
/// gets it. `tag` has no arm at all — see `drill_down_spec.dart` for the missing read and its owner.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/features/analytics/providers/analytics_providers.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';

/// The transaction ids whose lines reference one item.
///
/// Only the `item` arm needs this. A line-level read cannot be folded into the predicate below,
/// because a `Transaction` does not know what its lines bought — so the ids are gathered once and the
/// windowed list is filtered against the set.
final drillDownItemTransactionIdsProvider = StreamProvider.autoDispose
    .family<Set<String>, String>((ref, itemId) {
      return ref
          .watch(transactionRepositoryProvider)
          .watchLinesForItem(itemId)
          .map((lines) => {for (final line in lines) line.transactionId});
    });

/// The transactions behind one analytics slice, newest first.
///
/// **The window comes from the analytics screen, not from the route** (ARCH_5 §5.7). A reader who set
/// the range to "this year" and tapped a slice expects this year's transactions; putting the dates in
/// the path would have made the two disagree the moment either changed.
///
/// Withdrawals only, matching every spend query in the adapter: a drill-down that showed the deposits
/// too would not add up to the slice it came from.
final drillDownTransactionsProvider = StreamProvider.autoDispose
    .family<List<Transaction>, DrillDownSpec>((ref, spec) {
      final window = ref.watch(analyticsWindowProvider);
      final rows = ref
          .watch(transactionRepositoryProvider)
          .watchByDateRange(from: window.from, to: window.to);

      if (spec.kind == DrillDownKind.item) {
        final ids = ref.watch(drillDownItemTransactionIdsProvider(spec.value));
        // Until the id set resolves the list stays loading rather than briefly showing every
        // transaction in the window — a flash of the unfiltered ledger reads as a broken filter.
        return ids.when(
          loading: Stream<List<Transaction>>.empty,
          error: (error, stack) =>
              Stream<List<Transaction>>.error(error, stack),
          data: (set) => rows.map(
            (all) => [
              for (final row in all)
                if (row.kind == TransactionKind.withdrawal &&
                    set.contains(row.id))
                  row,
            ],
          ),
        );
      }

      return rows.map(
        (all) => [
          for (final row in all)
            if (row.kind == TransactionKind.withdrawal && _admits(spec, row))
              row,
        ],
      );
    });

bool _admits(DrillDownSpec spec, Transaction row) => switch (spec.kind) {
  DrillDownKind.subtype => row.subtype.name == spec.value,
  DrillDownKind.paymentMethod => row.paymentMethodId == spec.value,
  DrillDownKind.payee => row.payeeId == spec.value,
  DrillDownKind.recurring =>
    spec.value == _recurringValue
        ? row.recurringTemplateId != null
        : row.recurringTemplateId == null,
  // Handled above, before the predicate: an item cannot be judged from the transaction alone.
  DrillDownKind.item => false,
};

/// The `recurring` side of query 18's split, spelled as the adapter's SQL spells it.
const String _recurringValue = 'recurring';

/// One day's transactions in a drill-down, for archetype C's sticky date header.
class DrillDownDayGroup {
  /// Creates a day group.
  const DrillDownDayGroup({required this.date, required this.transactions});

  /// The civil date these share.
  final DateKey date;

  /// The transactions on [date], newest first.
  final List<Transaction> transactions;
}

/// The drill-down's transactions grouped into days, newest day first.
///
/// **Grouped by day because archetype C requires it**: a finance ledger without date grouping is
/// unreadable past twenty rows (ARCH_5 §3 C). The same shape 6A's `transactionDaysProvider` produces,
/// deliberately — a drill-down that grouped differently from the ledger it drills into would read as
/// a different screen.
final drillDownDaysProvider = Provider.autoDispose
    .family<AsyncValue<List<DrillDownDayGroup>>, DrillDownSpec>((ref, spec) {
      return ref
          .watch(drillDownTransactionsProvider(spec))
          .whenData(_groupByDay);
    });

List<DrillDownDayGroup> _groupByDay(List<Transaction> rows) {
  final groups = <int, List<Transaction>>{};
  for (final row in rows) {
    groups.putIfAbsent(row.dateKey.value, () => <Transaction>[]).add(row);
  }
  final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final date in dates)
      DrillDownDayGroup(date: DateKey(date), transactions: groups[date]!),
  ];
}

/// What the drill-down totals to, **per currency**, so its header can be checked against the slice it
/// came from.
///
/// **Per currency and not one figure** (anomaly A34). These are `originalAmount`s, each in whatever
/// currency it was recorded in, and folding them into a single int would add rupees to yen — which is
/// the defect this project has a whole anomaly number for. Converting instead would need the rate table
/// and would still disagree with the slice above by whatever the slice excluded, so the honest answer is
/// one subtotal per currency, which for almost every household is one line.
final drillDownTotalsProvider = Provider.autoDispose
    .family<AsyncValue<Map<String, int>>, DrillDownSpec>((ref, spec) {
      return ref.watch(drillDownTransactionsProvider(spec)).whenData((rows) {
        final byCurrency = <String, int>{};
        for (final row in rows) {
          byCurrency.update(
            row.originalAmount.currencyCode,
            (minor) => minor + row.originalAmount.minor,
            ifAbsent: () => row.originalAmount.minor,
          );
        }
        return byCurrency;
      });
    });

/// The label for one drill-down, resolved from the id the route carried.
///
/// **Resolved rather than passed.** `go_router`'s `extra` does not survive a deep link or a process
/// death, so a label carried that way would render blank on the one path where the route is reached
/// from outside the app. Returns null for the kinds whose label is an ARB string rather than data —
/// `subtype` and `recurring` — which the screen localises itself (Law U5).
final drillDownLabelProvider = FutureProvider.autoDispose
    .family<String?, DrillDownSpec>((ref, spec) async {
      switch (spec.kind) {
        case DrillDownKind.subtype:
        case DrillDownKind.recurring:
          return null;
        case DrillDownKind.payee:
          final payee = await ref
              .watch(payeeRepositoryProvider)
              .byId(spec.value);
          return payee?.name;
        case DrillDownKind.item:
          final item = await ref.watch(itemRepositoryProvider).byId(spec.value);
          return item?.name;
        case DrillDownKind.paymentMethod:
          final method = await ref
              .watch(paymentMethodRepositoryProvider)
              .byId(spec.value);
          return method?.name;
      }
    });
