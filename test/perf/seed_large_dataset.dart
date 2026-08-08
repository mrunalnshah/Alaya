import 'dart:math';

import 'package:drift/drift.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Seeds a database with enough rows to make performance problems visible.
///
/// **Not a test — a fixture builder.** The perf gate asks for 50,000 transactions and a 5,000-row list, and
/// neither number is reachable by hand. Run it against a real device database before profiling, with
/// `dart run test/perf/seed_large_dataset.dart`.
///
/// **Deterministic by construction.** A fixed `Random(seed)` and a fixed clock mean two runs produce byte-identical
/// data, so a regression between two profiling sessions is a code change rather than a different dataset. It is the
/// same reasoning `SeedData` uses for the shipped seed.
///
/// **The distribution matters more than the count.** 50,000 transactions all on one day would make the calendar
/// pathological and the ledger trivial; all in distinct months would do the reverse. This spreads them over three
/// years with a weekday bias, because that is the shape a real ledger has and therefore the shape whose queries
/// need to be fast.
class LargeDatasetSeeder {
  /// Creates a seeder.
  const LargeDatasetSeeder({
    required this.database,
    required this.uids,
    required this.clock,
  });

  /// The database to fill.
  final AlayaDatabase database;

  /// Where ids come from. A `SequentialUidGenerator` keeps runs comparable.
  final UidGenerator uids;

  /// The clock the dates are measured back from.
  final Clock clock;

  /// How many transactions the perf gate asks for.
  static const int transactionCount = 50000;

  /// Over how many days they are spread.
  static const int spreadDays = 365 * 3;

  /// The fixed seed, so two runs produce identical data.
  static const int randomSeed = 20260808;

  /// The subtypes a withdrawal can honestly carry.
  ///
  /// Transfers are excluded: they need a counterpart account and a matching row, and a seeder that emitted
  /// half a transfer would leave the ledger unbalanced in a way no screen can display.
  static const List<TransactionSubtype> _spendingSubtypes = [
    TransactionSubtype.grocery,
    TransactionSubtype.household,
    TransactionSubtype.electronics,
    TransactionSubtype.bill,
  ];

  /// Inserts [transactionCount] transactions, batched.
  ///
  /// **One batch per thousand rows, not one for all fifty.** Drift builds the whole statement in memory before
  /// sending it, and a single fifty-thousand-row batch is both slow to assemble and capable of exhausting a
  /// device's memory — which would make the seeder itself the thing being measured.
  Future<void> run({void Function(int done)? onProgress}) async {
    final random = Random(randomSeed);
    final today = clock.today();
    final accounts = await database.select(database.accounts).get();
    if (accounts.isEmpty) {
      throw StateError(
        'Seed the database first — LargeDatasetSeeder adds transactions to existing accounts.',
      );
    }

    const chunk = 1000;
    for (var start = 0; start < transactionCount; start += chunk) {
      await database.batch((batch) {
        for (var i = start; i < start + chunk && i < transactionCount; i++) {
          final daysAgo = random.nextInt(spreadDays);
          final on = today.addDays(-daysAgo);
          final account = accounts[random.nextInt(accounts.length)];
          final isDeposit = random.nextInt(10) == 0;
          final now = clock.nowUtcMillis();
          batch.insert(
            database.transactions,
            TransactionsCompanion.insert(
              id: uids.generate(),
              kind: isDeposit
                  ? TransactionKind.deposit
                  : TransactionKind.withdrawal,
              // `salaryIn`, and the withdrawal side picks from the four that are actually spending. Picking
              // from `values` at random — which this did — would have produced deposits filed as `grocery` and
              // transfers with no counterpart account, giving the analytics a dataset it cannot reconcile.
              subtype: isDeposit
                  ? TransactionSubtype.salaryIn
                  : _spendingSubtypes[random.nextInt(_spendingSubtypes.length)],
              // **`occurredAt`, `dateKey` and `monthKey` are all written, and all three are derived from the
              // same instant.** The schema stores the civil date twice on purpose — `dateKey` for a day query,
              // `monthKey` for a month rollup — and a seeder that let them disagree would produce a dataset on
              // which the analytics are fast and wrong.
              occurredAt: on.toUtcMidnight().millisecondsSinceEpoch,
              dateKey: on,
              monthKey: on.value ~/ 100,
              // 5 to 5,000 major units, in minor. Wide enough to exercise formatting and column widths at both
              // ends, which a uniform amount would not.
              originalAmountMinor: 500 + random.nextInt(499500),
              originalCurrencyCode: account.currencyCode,
              // A withdrawal leaves an account; a deposit arrives in one. Both nullable, and which one is set is
              // what `TransactionKind` means — filling the wrong one produces rows the ledger cannot read.
              fromAccountId: Value(isDeposit ? null : account.id),
              toAccountId: Value(isDeposit ? account.id : null),
              needsReview: false,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      });
      onProgress?.call(min(start + chunk, transactionCount));
    }
  }
}
