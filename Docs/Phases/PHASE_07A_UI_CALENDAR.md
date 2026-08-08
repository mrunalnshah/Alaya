# PHASE 7A — CalendarRepository & the Calendar UI

Nineteen files. `CalendarRepository` had been declared in Phase 3A and implemented by no phase, which left
`CalendarAggregator` without a provider and three of its methods unreachable (ARCH_4 §5.1 item 15). That is
closed first, because no screen can be built over a repository that does not exist.

## Dependency

```
flutter pub add table_calendar
```

Pinned for 7A by ARCH_1 §7 (`Calendar UI | table_calendar | resolver | 7A`).

## What is *not* in this document, and why

**`CalendarAggregator`.** Phase 4C already implements it in full — `severityFor` with ARCH_3 §6's per-type
table, `resolveSeverity`, `watchDays`, `groupByDay`, `worstSeverity`, and the three threshold constants.
Only its provider was missing. Rewriting it would be ARCH_6 P7, the shape that has already cost this
project rounds.

**`routes.dart`.** `Routes.calendar`, `Routes.calendarDayPattern`, `Routes.calendarDay` and
`Routes.pDateKey` all already exist. Nothing to add.

## Files carried here that other documents own

| File | Owner | Why it is here |
|---|---|---|
| `calendar_event.dart` | 3A | `severityAsOf` deleted, per ARCH_4 §5.1 item 14 |
| `calendar_dao.dart` | 2A or 2C | No calendar DAO existed; every repository in this codebase reads through one |
| `infrastructure_providers.dart` | 5 | Gains `calendarDaoProvider` |
| `repository_providers.dart` | 5 | Gains `calendarRepositoryProvider` |
| `service_providers.dart` | 5 | Gains `calendarAggregatorProvider` |
| `app_router.dart` | 5, 6A–6F | The `/calendar` placeholders replaced |
| `app_en.arb` | 5, 6A–6F | 20 keys and one placeholder block, 936 → 957 |
| `layout_overflow_test.dart` | 5, 6A–6F | A `calendar` group added |

`app_router.dart`, `app_en.arb` and `layout_overflow_test.dart` are each carried by seven documents and must
stay byte-identical in all of them (ARCH_6 §2), so this phase obliges a regeneration of PHASE_05 and
06A–06F alongside 3A and 2A. That is eight documents, and it is the largest single consequence of this
phase.

## Two things verified rather than assumed

`severityAsOf` was deleted only after confirming **zero callers** across all twenty phase documents; the
only other references are 4C's own doc comment asking for its removal and ARCH_4 §5.1 item 14.

Every companion name, required field, table accessor and foreign key in
`calendar_repository_impl_test.dart` was read out of `alaya_database.g.dart` — 24,807 lines — rather than
recalled, per ARCH_4 R22. That read found three things a fake could not have: foreign keys are enforced
from `beforeOpen`, so `currencies` and `units` must be seeded first; one `assets` row feeds two arms; and
`service_records`' arm carries no `status` filter where both `assets` arms do.

## One reasoned deviation from U2

`CalendarScreen`'s three full-height states sit in `SliverFillRemaining(hasScrollBody: false)` inside a
`CustomScrollView`, wrapped in a plain `Center` rather than in `ScrollSafeCenter`.

`ScrollSafeCenter` exists to scroll a centred state instead of overflowing it. The sliver plus the
enclosing scroll view already do exactly that — the sliver hands the state the remaining viewport as a
*minimum* and lets it grow past it, and the outer view scrolls. Nesting `ScrollSafeCenter`'s own
`SingleChildScrollView` inside that would put two vertical scrollables in one gesture arena, which is the
defect ARCH_6 P2 names from the other direction. The three squeezed-viewport cases in
`layout_overflow_test.dart` are what hold the guarantee U2 is actually asking for.

The screen was a `Column` with an `Expanded` tail until this was checked. At a tripled text scale the
grid's six measured rows plus its header exceed the viewport unaided, so the `Expanded` received a
negative box — P1's shape, and it would have shipped green because nothing asked the screen to render in a
short viewport. That is the gap the three new cases close.

## The one unverified surface

`table_calendar` is not in the lockfile and this session has no compiler, so its API could not be checked
against (ARCH_4 R22). It is confined to **`calendar_month_grid.dart`**: `headerVisible` is false and every
cell, the weekday row and the header are built from Alaya's own tokens through `calendarBuilders`, so the
package supplies page arithmetic and swipe animation and nothing a theme token would otherwise own. If its
API differs, one file changes rather than the phase.

---

## The repository layer

### `lib/domain/entities/calendar_event.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// What kind of thing a calendar entry represents (ARCH_3 §6).
///
/// Declared here rather than in `core/enums/` because these values are never stored: the
/// `v_calendar_events` view computes them, so Law L13's "renaming an enum value is a breaking
/// migration" does not apply.
enum CalendarEventType {
  /// A recorded transaction.
  transaction,

  /// A recurring obligation that is due.
  recurringDue,

  /// An inventory batch reaching its expiry.
  batchExpiry,

  /// An asset's warranty ending.
  warrantyEnd,

  /// An asset's next service falling due.
  serviceDue,

  /// A shopping list's target date.
  shoppingTarget,
}

/// How urgently a calendar entry should read.
enum CalendarSeverity {
  /// Informational — it happened, or it is simply scheduled.
  info,

  /// Approaching and worth attention.
  warning,

  /// Already past its date.
  danger,
}

/// One entry in the unified calendar feed.
///
/// Read-only: it comes from `v_calendar_events`, a `UNION ALL` view rather than a physical table,
/// so there is no synchronisation code to get wrong (anomaly A37).
class CalendarEvent {
  /// Creates a calendar entry.
  const CalendarEvent({
    required this.dateKey,
    required this.type,
    required this.refType,
    required this.refId,
    required this.title,
    required this.baseSeverity,
    this.amount,
  });

  /// The civil date this entry falls on.
  final DateKey dateKey;

  /// What kind of thing this is.
  final CalendarEventType type;

  /// Which kind of record [refId] names, e.g. `transaction`, `inventoryBatch`.
  final String refType;

  /// The owning record's id, for navigation.
  final String refId;

  /// What to show on the card.
  final String title;

  /// The static baseline severity the view emits.
  ///
  /// Resolve it through `CalendarAggregator.severityFor` before display. The view never consults the
  /// clock (ARCH_2 §12.2) and the escalation thresholds differ per type (ARCH_3 §6), so neither the
  /// view nor this entity can answer what an entry should look like today.
  final CalendarSeverity baseSeverity;

  /// The amount, where the entry has one — transactions and recurring dues do, expiries do not.
  final Money? amount;

  /// Days from [today] until this entry — negative once past.
  int daysAwayFrom(DateKey today) => dateKey.diffDays(today);

  /// True when this entry's date has already passed as of [today].
  bool isPast(DateKey today) => dateKey < today;

  @override
  bool operator ==(Object other) =>
      other is CalendarEvent &&
      other.dateKey == dateKey &&
      other.type == type &&
      other.refType == refType &&
      other.refId == refId &&
      other.title == title &&
      other.baseSeverity == baseSeverity &&
      other.amount == amount;

  @override
  int get hashCode =>
      Object.hashAll([dateKey, type, refType, refId, title, baseSeverity, amount]);

  @override
  String toString() => 'CalendarEvent(${type.name} $refId on ${dateKey.toIso()})';
}
```

### `lib/data/daos/calendar_dao.dart`

```dart
import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Reads `v_calendar_events`, the `UNION ALL` view behind the calendar (ARCH_3 §6).
///
/// **Every read is bounded.** Unbounded, the view scans seven tables; bounded on `date_key`, each arm
/// uses its own date index. There is deliberately no "all events" method for a caller to reach for.
///
/// The view emits `severity` as a static baseline and never consults the clock (ARCH_2 §12.2), so this
/// DAO returns rows unescalated. `CalendarAggregator` applies the per-type thresholds.
class CalendarDao extends DatabaseAccessor<AlayaDatabase> {
  /// Creates the DAO over [db].
  CalendarDao(super.db);

  /// Emits the rows falling in `[fromDateKey, toDateKey]`, inclusive.
  Stream<List<CalendarEventRow>> watchRange({
    required int fromDateKey,
    required int toDateKey,
  }) =>
      (select(attachedDatabase.vCalendarEvents)
            ..where((t) => t.dateKey.isBetweenValues(fromDateKey, toDateKey))
            ..orderBy([
              (t) => OrderingTerm.asc(t.dateKey),
              (t) => OrderingTerm.asc(t.eventType),
              (t) => OrderingTerm.asc(t.refId),
            ]))
          .watch();

  /// Reads the rows falling in `[fromDateKey, toDateKey]`, inclusive.
  Future<List<CalendarEventRow>> range({
    required int fromDateKey,
    required int toDateKey,
  }) =>
      (select(attachedDatabase.vCalendarEvents)
            ..where((t) => t.dateKey.isBetweenValues(fromDateKey, toDateKey))
            ..orderBy([
              (t) => OrderingTerm.asc(t.dateKey),
              (t) => OrderingTerm.asc(t.eventType),
              (t) => OrderingTerm.asc(t.refId),
            ]))
          .get();

  /// Reads the rows falling on exactly [dateKey].
  Future<List<CalendarEventRow>> forDay(int dateKey) =>
      range(fromDateKey: dateKey, toDateKey: dateKey);

  /// Counts rows per `date_key` across `[fromDateKey, toDateKey]`.
  ///
  /// Grouped in SQL rather than by materialising every row and counting in Dart: a month grid needs a
  /// dot per day, and a busy month is several hundred rows to discard.
  Future<Map<int, int>> countsByDate({
    required int fromDateKey,
    required int toDateKey,
  }) async {
    final view = attachedDatabase.vCalendarEvents;
    final total = countAll();
    final query = selectOnly(view)
      ..addColumns([view.dateKey, total])
      ..where(view.dateKey.isBetweenValues(fromDateKey, toDateKey))
      ..groupBy([view.dateKey]);

    final rows = await query.get();
    return {
      for (final row in rows) row.read(view.dateKey)!: row.read(total)!,
    };
  }
}
```

### `lib/data/repositories/calendar_repository_impl.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/calendar_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/repositories/calendar_repository.dart';

/// Reads the unified calendar feed from `v_calendar_events`.
///
/// Phase 3A declared [CalendarRepository] and no phase implemented it, which left
/// `CalendarAggregator` with no provider and three of its methods unreachable (ARCH_4 §5.1 item 15).
/// This closes that.
///
/// **Returns rows with their baseline severity, unescalated.** The escalation thresholds differ per
/// event type (ARCH_3 §6) and depend on the current date, so they belong in `CalendarAggregator` with
/// the injected `Clock` — not here, and not in the view (ARCH_2 §12.2).
class CalendarRepositoryImpl implements CalendarRepository {
  /// Creates the repository over [dao].
  const CalendarRepositoryImpl(this._dao);

  final CalendarDao _dao;

  @override
  Stream<List<CalendarEvent>> watchRange({
    required DateKey from,
    required DateKey to,
  }) =>
      _dao
          .watchRange(fromDateKey: from.value, toDateKey: to.value)
          .map((rows) => rows.map(_toEntity).toList());

  @override
  Future<List<CalendarEvent>> forDay(DateKey dateKey) async {
    final rows = await _dao.forDay(dateKey.value);
    return rows.map(_toEntity).toList();
  }

  @override
  Future<Map<DateKey, int>> countsByDate({
    required DateKey from,
    required DateKey to,
  }) async {
    final counts = await _dao.countsByDate(
      fromDateKey: from.value,
      toDateKey: to.value,
    );
    return {
      for (final entry in counts.entries) DateKey(entry.key): entry.value,
    };
  }

  /// Maps one view row onto the domain entity.
  ///
  /// `event_type` and `severity` decode by enum *name*, which Law L11 makes the schema contract: the
  /// view's arms emit the literals `'transaction'`, `'recurringDue'` and so on, and renaming a value
  /// in either enum is a breaking change to this view.
  CalendarEvent _toEntity(CalendarEventRow row) {
    final minor = row.amountMinor;
    final currency = row.currencyCode;

    return CalendarEvent(
      // `DateKey?`, not `int`: the view column carries `DateKeyConverter`, and drift types it nullable
      // because six of the seven arms select a nullable column. Every one of those arms filters
      // `IS NOT NULL`, and the transaction arm's `date_key` is NOT NULL, so a null here means the view
      // changed and throwing is the correct response.
      dateKey: row.dateKey!,
      type: CalendarEventType.values.byName(row.eventType),
      refType: row.refType,
      refId: row.refId,
      title: row.title,
      baseSeverity: CalendarSeverity.values.byName(row.severity),
      amount: minor != null && currency != null ? Money(minor, currency) : null,
    );
  }
}
```

### `lib/app/providers/infrastructure_providers.dart`

```dart
/// The bottom of the dependency graph: the database, the DAOs, and the ambient singletons.
///
/// **Hand-written, because `@riverpod` needs `riverpod_generator` and `drift_dev` is the only
/// codegen package this project may have (ARCH_1 §7.3).** A second one makes the whole project
/// unresolvable, so the annotation is not available at any price.
///
/// Providers rather than a service locator so that a widget test can override exactly one
/// dependency — `databaseProvider` with an in-memory database, `clockProvider` with a `FixedClock` —
/// without constructing the other forty.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/text/normalizer.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/account_dao.dart';
import 'package:alaya/data/daos/analytics_cache_dao.dart';
import 'package:alaya/data/daos/calendar_dao.dart';
import 'package:alaya/data/daos/asset_dao.dart';
import 'package:alaya/data/daos/backup_history_dao.dart';
import 'package:alaya/data/daos/batch_dao.dart';
import 'package:alaya/data/daos/currency_dao.dart';
import 'package:alaya/data/daos/item_dao.dart';
import 'package:alaya/data/daos/notification_schedule_dao.dart';
import 'package:alaya/data/daos/payee_dao.dart';
import 'package:alaya/data/daos/payment_method_dao.dart';
import 'package:alaya/data/daos/recurring_occurrence_dao.dart';
import 'package:alaya/data/daos/recurring_template_dao.dart';
import 'package:alaya/data/daos/service_record_dao.dart';
import 'package:alaya/data/daos/settings_dao.dart';
import 'package:alaya/data/daos/shopping_entry_dao.dart';
import 'package:alaya/data/daos/shopping_list_dao.dart';
import 'package:alaya/data/daos/stock_movement_dao.dart';
import 'package:alaya/data/daos/tag_dao.dart';
import 'package:alaya/data/daos/transaction_dao.dart';
import 'package:alaya/data/daos/transaction_line_dao.dart';
import 'package:alaya/data/daos/unit_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/security/secure_key_value_store.dart';


/// The open database.
///
/// **Overridden in `bootstrap` with the real connection** and in tests with
/// `AlayaDatabase(NativeDatabase.memory())`. It throws if read un-overridden, which is deliberate:
/// a provider that silently opened a second connection would violate L10's single-open-path rule and
/// the symptom would be a locked database rather than an error naming the cause.
final databaseProvider = Provider<AlayaDatabase>((ref) {
  throw StateError(
    'databaseProvider was not overridden. bootstrap() must supply the connection — see '
    'data/db/connection/open_database.dart, the only permitted open path (ARCH_1 L10).',
  );
});

/// The wall clock.
///
/// Every timestamp and every "today" in the app comes from here, which is what makes a date-sensitive
/// test reproducible instead of dependent on when it ran.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// The UUID v7 generator.
final uidGeneratorProvider = Provider<UidGenerator>((ref) => const Uuid7Generator());

/// The logger.
final loggerProvider = Provider<Logger>((ref) => const DeveloperLogger());

/// The text normaliser used for duplicate detection and search.
final normalizerProvider = Provider<Normalizer>((ref) => const Normalizer());

/// The HTTP client, configured for one job: a fire-and-forget rate fetch.
///
/// The timeouts are literal `Duration`s and not `AlayaDurations` values, deliberately. That scale is a
/// UI animation scale measured in tens of milliseconds; a network timeout is seconds, and borrowing an
/// animation token for one would be a category error rather than reuse.
///
/// They are short because `syncDailyRates` must never block a write (Law L11). A rate that arrives
/// late is worth nothing — the cached rate is already in use — so the call gives up quickly rather
/// than holding a connection open on a bad network.
final dioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
    ),
  ),
);

/// Secure key-value storage, for the app lock only.
///
/// Never the database (ARCH_3 §2.1) — that separation is what stops a restore from replacing the
/// user's PIN with the one from the backup.
final secureKeyValueStoreProvider =
    Provider<SecureKeyValueStore>((ref) => const FlutterSecureKeyValueStore());

// ── DAOs ────────────────────────────────────────────────────────────────────────────────
//
// One per aggregate, each a thin `DatabaseAccessor` over the single connection. They are separate
// providers rather than getters on the database because `@DriftDatabase` here declares no `daos:`
// list, so there are no generated accessors to reach for.

/// The accounts DAO.
final accountDaoProvider = Provider<AccountDao>((ref) => AccountDao(ref.watch(databaseProvider)));

/// The transactions DAO.
final transactionDaoProvider =
    Provider<TransactionDao>((ref) => TransactionDao(ref.watch(databaseProvider)));

/// The transaction-lines DAO.
final transactionLineDaoProvider =
    Provider<TransactionLineDao>((ref) => TransactionLineDao(ref.watch(databaseProvider)));

/// The payment-methods DAO.
final paymentMethodDaoProvider =
    Provider<PaymentMethodDao>((ref) => PaymentMethodDao(ref.watch(databaseProvider)));

/// The payees DAO.
final payeeDaoProvider = Provider<PayeeDao>((ref) => PayeeDao(ref.watch(databaseProvider)));

/// The tags DAO.
final tagDaoProvider = Provider<TagDao>((ref) => TagDao(ref.watch(databaseProvider)));

/// The currencies and rates DAO.
final currencyDaoProvider = Provider<CurrencyDao>((ref) => CurrencyDao(ref.watch(databaseProvider)));

/// The units DAO.
final unitDaoProvider = Provider<UnitDao>((ref) => UnitDao(ref.watch(databaseProvider)));

/// The settings DAO.
final settingsDaoProvider = Provider<SettingsDao>((ref) => SettingsDao(ref.watch(databaseProvider)));

/// The items DAO.
final itemDaoProvider = Provider<ItemDao>((ref) => ItemDao(ref.watch(databaseProvider)));

/// The inventory-batches DAO.
final batchDaoProvider = Provider<BatchDao>((ref) => BatchDao(ref.watch(databaseProvider)));

/// The stock-movements DAO.
final stockMovementDaoProvider =
    Provider<StockMovementDao>((ref) => StockMovementDao(ref.watch(databaseProvider)));

/// The shopping-lists DAO.
final shoppingListDaoProvider =
    Provider<ShoppingListDao>((ref) => ShoppingListDao(ref.watch(databaseProvider)));

/// The shopping-entries DAO.
final shoppingEntryDaoProvider =
    Provider<ShoppingEntryDao>((ref) => ShoppingEntryDao(ref.watch(databaseProvider)));

/// The recurring-templates DAO.
final recurringTemplateDaoProvider =
    Provider<RecurringTemplateDao>((ref) => RecurringTemplateDao(ref.watch(databaseProvider)));

/// The recurring-occurrences DAO.
final recurringOccurrenceDaoProvider =
    Provider<RecurringOccurrenceDao>((ref) => RecurringOccurrenceDao(ref.watch(databaseProvider)));

/// The assets DAO.
final assetDaoProvider = Provider<AssetDao>((ref) => AssetDao(ref.watch(databaseProvider)));

/// The service-records DAO.
final serviceRecordDaoProvider =
    Provider<ServiceRecordDao>((ref) => ServiceRecordDao(ref.watch(databaseProvider)));

/// The notification-schedule DAO.
final notificationScheduleDaoProvider =
    Provider<NotificationScheduleDao>((ref) => NotificationScheduleDao(ref.watch(databaseProvider)));

/// The backup-history DAO.
final backupHistoryDaoProvider =
    Provider<BackupHistoryDao>((ref) => BackupHistoryDao(ref.watch(databaseProvider)));

/// The analytics-cache DAO.
final analyticsCacheDaoProvider =
    Provider<AnalyticsCacheDao>((ref) => AnalyticsCacheDao(ref.watch(databaseProvider)));

/// The calendar DAO, over `v_calendar_events`.
final calendarDaoProvider =
    Provider<CalendarDao>((ref) => CalendarDao(ref.watch(databaseProvider)));
```

### `lib/app/providers/repository_providers.dart`

```dart
/// One provider per repository contract, typed as the **contract** and never the implementation.
///
/// Typing them as the interface is what makes the layering rule enforceable: a feature that declares
/// `ref.watch(accountRepositoryProvider)` receives an `AccountRepository` and cannot reach into
/// `AccountRepositoryImpl` for a method the contract does not expose.
///
/// **Two of Phase 3A's seventeen contracts have no implementation yet** — `CalendarRepository` and
/// `AnalyticsCacheRepository` — so they have no provider here. See `service_providers.dart` for what
/// that blocks and why stubbing them would be worse.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/data/repositories/calendar_repository_impl.dart';
import 'package:alaya/data/repositories/account_repository_impl.dart';
import 'package:alaya/data/repositories/asset_repository_impl.dart';
import 'package:alaya/data/repositories/batch_repository_impl.dart';
import 'package:alaya/data/repositories/currency_repository_impl.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/item_repository_impl.dart';
import 'package:alaya/data/repositories/payee_repository_impl.dart';
import 'package:alaya/data/repositories/payment_method_repository_impl.dart';
import 'package:alaya/data/repositories/recurring_repository_impl.dart';
import 'package:alaya/data/repositories/service_record_repository_impl.dart';
import 'package:alaya/data/repositories/settings_repository_impl.dart';
import 'package:alaya/data/repositories/shopping_repository_impl.dart';
import 'package:alaya/data/repositories/stock_repository_impl.dart';
import 'package:alaya/data/repositories/tag_repository_impl.dart';
import 'package:alaya/data/repositories/transaction_repository_impl.dart';
import 'package:alaya/data/repositories/unit_repository_impl.dart';
import 'package:alaya/domain/repositories/calendar_repository.dart';
import 'package:alaya/domain/repositories/account_repository.dart';
import 'package:alaya/domain/repositories/asset_repository.dart';
import 'package:alaya/domain/repositories/batch_repository.dart';
import 'package:alaya/domain/repositories/currency_repository.dart';
import 'package:alaya/domain/repositories/item_repository.dart';
import 'package:alaya/domain/repositories/payee_repository.dart';
import 'package:alaya/domain/repositories/payment_method_repository.dart';
import 'package:alaya/domain/repositories/recurring_repository.dart';
import 'package:alaya/domain/repositories/service_record_repository.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/repositories/shopping_repository.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';
import 'package:alaya/domain/repositories/tag_repository.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';
import 'package:alaya/domain/repositories/unit_repository.dart';


/// Resolves an item's unit category, with a per-instance cache.
///
/// A single provider rather than one per consumer, because three repositories need it and its whole
/// value is the cache: constructing it twice halves the hit rate for no reason.
final itemCategoryResolverProvider =
    Provider<ItemCategoryResolver>((ref) => ItemCategoryResolver(ref.watch(itemDaoProvider)));

/// Key-value app settings.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepositoryImpl(ref.watch(settingsDaoProvider), ref.watch(clockProvider)),
);

/// Currencies, rates and conversion.
///
/// Takes `CurrencyRateService` so `syncDailyRates` has one implementation. Phase 3B's
/// `DailyRateFetch` typedef is gone — the repository delegates rather than reimplementing the
/// once-daily check, which the earlier version omitted entirely.
final currencyRepositoryProvider = Provider<CurrencyRepository>(
  (ref) => CurrencyRepositoryImpl(
    ref.watch(currencyDaoProvider),
    ref.watch(clockProvider),
    ref.watch(settingsRepositoryProvider),
    rateService: ref.watch(currencyRateServiceProvider),
  ),
);

/// Units and conversion factors.
final unitRepositoryProvider = Provider<UnitRepository>(
  (ref) => UnitRepositoryImpl(ref.watch(unitDaoProvider), ref.watch(clockProvider)),
);

/// Accounts and balances.
final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepositoryImpl(
    ref.watch(accountDaoProvider),
    ref.watch(transactionDaoProvider),
    ref.watch(currencyRepositoryProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// Payment methods.
final paymentMethodRepositoryProvider = Provider<PaymentMethodRepository>(
  (ref) => PaymentMethodRepositoryImpl(
    ref.watch(paymentMethodDaoProvider),
    ref.watch(clockProvider),
  ),
);

/// Payees.
final payeeRepositoryProvider = Provider<PayeeRepository>(
  (ref) => PayeeRepositoryImpl(ref.watch(payeeDaoProvider), ref.watch(clockProvider)),
);

/// Tags.
final tagRepositoryProvider = Provider<TagRepository>(
  (ref) => TagRepositoryImpl(ref.watch(tagDaoProvider), ref.watch(clockProvider)),
);

/// Transactions, with their lines and stock side effects.
final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepositoryImpl(
    ref.watch(transactionDaoProvider),
    ref.watch(transactionLineDaoProvider),
    ref.watch(accountDaoProvider),
    ref.watch(unitDaoProvider),
    ref.watch(batchDaoProvider),
    ref.watch(stockMovementDaoProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(currencyRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// The item catalogue.
final itemRepositoryProvider = Provider<ItemRepository>(
  (ref) => ItemRepositoryImpl(ref.watch(itemDaoProvider), ref.watch(clockProvider)),
);

/// Inventory batches.
final batchRepositoryProvider = Provider<BatchRepository>(
  (ref) => BatchRepositoryImpl(
    ref.watch(batchDaoProvider),
    ref.watch(itemCategoryResolverProvider),
    ref.watch(clockProvider),
  ),
);

/// Stock levels and movements.
final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => StockRepositoryImpl(
    ref.watch(batchDaoProvider),
    ref.watch(stockMovementDaoProvider),
    ref.watch(itemCategoryResolverProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// Shopping lists and entries.
final shoppingRepositoryProvider = Provider<ShoppingRepository>(
  (ref) => ShoppingRepositoryImpl(
    ref.watch(shoppingListDaoProvider),
    ref.watch(shoppingEntryDaoProvider),
    ref.watch(itemDaoProvider),
    ref.watch(transactionLineDaoProvider),
    ref.watch(itemCategoryResolverProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// Recurring templates and occurrences.
final recurringRepositoryProvider = Provider<RecurringRepository>(
  (ref) => RecurringRepositoryImpl(
    ref.watch(recurringTemplateDaoProvider),
    ref.watch(recurringOccurrenceDaoProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// Assets.
final assetRepositoryProvider = Provider<AssetRepository>(
  (ref) => AssetRepositoryImpl(ref.watch(assetDaoProvider), ref.watch(clockProvider)),
);

/// Service records.
final serviceRecordRepositoryProvider = Provider<ServiceRecordRepository>(
  (ref) => ServiceRecordRepositoryImpl(
    ref.watch(serviceRecordDaoProvider),
    ref.watch(assetDaoProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// The calendar feed. Phase 3A declared the contract and no phase implemented it until 7A
/// (ARCH_4 §5.1 item 15), which is why `calendarAggregatorProvider` could not exist.
final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => CalendarRepositoryImpl(ref.watch(calendarDaoProvider)),
);
```

### `lib/app/providers/service_providers.dart`

```dart
/// One provider per engine.
///
/// The stateless engines are `const` and could in principle be constructed at each use site. They get
/// providers anyway so that every dependency in the app arrives the same way — a codebase where some
/// collaborators are injected and others are constructed inline is one where you cannot tell, from a
/// widget, what it actually depends on.
///
/// ## Three services have no provider, deliberately
///
/// | Service | Blocked on | Owner |
/// |---|---|---|
/// | `AnalyticsService` | `AnalyticsPort` is declared in `domain/` with no `data/` adapter | Phase 7B |
/// | `AnalyticsCacheService` | `AnalyticsCacheRepository` (Phase 3A) has no implementation | Phase 7B |
/// | `CalendarAggregator` | `CalendarRepository` (Phase 3A) has no implementation | Phase 7A |
///
/// Phase 3A declared seventeen repository contracts and Phases 3B–3D implemented fifteen. The two
/// outstanding are precisely the two these services need, which is not an oversight — the calendar
/// and analytics read models are 7A and 7B's work.
///
/// **Stubbing any of them would be worse than omitting them.** A port returning empty rows makes an
/// unfinished analytics screen look like a working one that found no data, and there is no way to
/// tell those apart from the UI. An absent provider is a compile error at the first use site, which
/// names the problem exactly where someone can act on it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/data/backup/backup_service.dart';
import 'package:alaya/data/backup/restore_service.dart';
import 'package:alaya/data/remote/currency_api_client.dart';
import 'package:alaya/data/repositories/mappers/rate_mappers.dart';
import 'package:alaya/data/security/app_lock_store.dart';
import 'package:alaya/data/security/pin_service.dart';
import 'package:alaya/data/security/recovery_code.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';
import 'package:alaya/domain/services/date_range_service.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/services/low_stock_suggestion_engine.dart';
import 'package:alaya/domain/services/purchase_fan_out_service.dart';
import 'package:alaya/domain/services/recurring_engine.dart';
import 'package:alaya/domain/services/stock_reconciler.dart';
import 'package:alaya/domain/services/unit_engine.dart';


// ── stateless engines ───────────────────────────────────────────────────────────────────

/// Unit conversion within a category.
final unitEngineProvider = Provider<UnitEngine>((ref) => const UnitEngine());

/// Date-range presets for filters and analytics.
final dateRangeServiceProvider = Provider<DateRangeService>((ref) => const DateRangeService());

/// Net worth and per-account balances.
final balanceServiceProvider = Provider<BalanceService>((ref) => const BalanceService());

/// FEFO consumption planning.
final inventoryConsumptionServiceProvider =
    Provider<InventoryConsumptionService>((ref) => const InventoryConsumptionService());

/// Cache-versus-ledger reconciliation and repair.
final stockReconcilerProvider = Provider<StockReconciler>((ref) => const StockReconciler());

/// Idempotent low-stock suggestion decisions.
final lowStockSuggestionEngineProvider =
    Provider<LowStockSuggestionEngine>((ref) => const LowStockSuggestionEngine());

/// Recurring schedule arithmetic — next due, materialisation, settlement.
final recurringEngineProvider = Provider<RecurringEngine>((ref) => const RecurringEngine());

// ── engines with dependencies ───────────────────────────────────────────────────────────

/// Turns a purchase line into a batch, an asset or a template.
final purchaseFanOutServiceProvider = Provider<PurchaseFanOutService>(
  (ref) => PurchaseFanOutService(normalizer: ref.watch(normalizerProvider)),
);

/// The exchange-rate HTTP client.
final currencyApiClientProvider = Provider<CurrencyApiClient>(
  (ref) => CurrencyApiClient(
    dio: ref.watch(dioProvider),
    logger: ref.watch(loggerProvider),
  ),
);

/// Rate lookup, cross-rate pivoting and the once-daily fetch.
///
/// Its four collaborators are closures over the DAO rather than the repository, which is what keeps
/// this out of a cycle: `CurrencyRepository` depends on this service, so a service depending on the
/// repository would not resolve.
final currencyRateServiceProvider = Provider<CurrencyRateService>((ref) {
  final dao = ref.watch(currencyDaoProvider);
  final client = ref.watch(currencyApiClientProvider);
  final clock = ref.watch(clockProvider);
  final uids = ref.watch(uidGeneratorProvider);
  return CurrencyRateService(
    loadTable: () async => RateMappers.tableFrom(
      rows: await dao.allRates(),
      decimalDigitsByCode: await dao.decimalDigitsByCode(),
    ),
    saveSnapshot: (snapshot) => dao.upsertRates(
      RateMappers.companionsFrom(snapshot: snapshot, uids: uids, clock: clock),
    ),
    fetchSnapshot: client.fetchLatest,
    // `newestRateDate` takes the base code; a snapshot is always USD-pivoted (ARCH_3 §1.2).
    newestCachedDate: () => dao.newestRateDate(RateTable.pivotCode),
    clock: clock,
  );
});

// ── security ────────────────────────────────────────────────────────────────────────────

/// Recovery-code generation and normalisation.
final recoveryCodeProvider = Provider<RecoveryCode>((ref) => RecoveryCode());

/// The app-lock secret store.
///
/// Reads and writes secure storage only, never the database — which is what makes a restore unable
/// to change the lock (ARCH_3 §2.1).
final appLockStoreProvider = Provider<AppLockStore>(
  (ref) => AppLockStore(storage: ref.watch(secureKeyValueStoreProvider)),
);

/// PIN verification, change, enable, disable and the failure throttle.
final pinServiceProvider = Provider<PinService>(
  (ref) => PinService(
    store: ref.watch(appLockStoreProvider),
    clock: ref.watch(clockProvider),
    recoveryCode: ref.watch(recoveryCodeProvider),
  ),
);

// ── backup ──────────────────────────────────────────────────────────────────────────────

/// Database export via `VACUUM INTO`.
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    database: ref.watch(databaseProvider),
    historyDao: ref.watch(backupHistoryDaoProvider),
    clock: ref.watch(clockProvider),
    uids: ref.watch(uidGeneratorProvider),
  ),
);

/// Merge and Replace restore.
final restoreServiceProvider = Provider<RestoreService>(
  (ref) => RestoreService(database: ref.watch(databaseProvider)),
);

/// The calendar aggregator, which applies ARCH_3 §6's per-type severity thresholds.
///
/// Stateless and `const`-constructible, but it takes a repository, so it gets a provider like every
/// other engine — no widget constructs it.
final calendarAggregatorProvider = Provider<CalendarAggregator>(
  (ref) => CalendarAggregator(ref.watch(calendarRepositoryProvider)),
);
```


## The calendar UI

### `lib/features/calendar/providers/calendar_providers.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';

/// Today, from the injected clock — the only source of "now" the calendar has.
final calendarTodayProvider = Provider<DateKey>(
  (ref) => ref.watch(clockProvider).today(),
);

/// The month the grid is showing, as its first day.
final focusedMonthProvider = NotifierProvider<FocusedMonthNotifier, DateKey>(
  FocusedMonthNotifier.new,
);

/// Holds the visible month and moves it a month at a time.
class FocusedMonthNotifier extends Notifier<DateKey> {
  @override
  DateKey build() {
    final today = ref.watch(calendarTodayProvider);
    return DateKey.fromYmd(today.year, today.month, 1);
  }

  /// Jumps to the month containing [day].
  void focus(DateKey day) => state = DateKey.fromYmd(day.year, day.month, 1);

  /// Moves [months] months from the current one, negative for backwards.
  void shift(int months) => state = shiftMonth(state, months);
}

/// The first of the month [months] away from [month], carried across year boundaries.
///
/// **`DateKey.fromYmd` validates, it does not normalise.** `month + 1` on December is 13 and `month - 1`
/// on January is 0, and both throw `ArgumentError` — which is why paging forward past December 2026 died
/// and the month had to be reached by swiping instead. Counting in absolute months and converting back
/// once removes the boundary entirely rather than special-casing it.
DateKey shiftMonth(DateKey month, int months) {
  final total = month.year * 12 + (month.month - 1) + months;
  return DateKey.fromYmd(total ~/ 12, total % 12 + 1, 1);
}

/// How far ahead recurring occurrences are created.
///
/// Two years, flat. A data-driven horizon — out to the furthest warranty or service the app knows about —
/// was considered and dropped: it needs a `max()` across four tables, and the only way to *see* a date
/// that far out is to browse to it, by which point a fixed two years has already covered anything a
/// household plans around.
const int recurringHorizonYears = 2;

/// Creates the recurring occurrence rows the calendar and the dashboard read, once per session.
///
/// **Without this the calendar cannot show a future bill at all.** `materialiseUpTo` was only ever called
/// with `clock.today()`, on the recurring list's mount (6D's coverage table: "lazy materialisation only"),
/// so no occurrence row existed past today and the `recurringDue` arm of `v_calendar_events` had nothing
/// future to return. Every other source stores its date outright — a warranty end, a service due, a batch
/// expiry — which is why recurring was the only one that could be silently absent.
///
/// Not `autoDispose`: this is a per-session job, and re-running it whenever the last calendar screen
/// closes would write on every navigation for no gain.
///
/// A failure does not block the read. The calendar then shows whatever rows exist, which is worse than
/// complete but far better than an empty month — and surfacing the failure properly needs the app-wide
/// notification channel that is 8B's work.
final recurringHorizonProvider = FutureProvider<int>((ref) async {
  final today = ref.watch(clockProvider).today();
  // `addDays`, not the same day two years on. On 29 February 2028 that reads
  // `fromYmd(2030, 2, 29)`, which is not a real date and throws — taking the calendar and the
  // dashboard's upcoming card down with it, on one day every four years.
  final horizon = today.addDays(365 * recurringHorizonYears);
  final result = await ref
      .watch(recurringRepositoryProvider)
      .materialiseUpTo(horizon);
  return result.fold((created) => created, (failure) => 0);
});

/// The visible month's events grouped by day, severity resolved against today.
///
/// Bounded to the month plus six days either side, which covers the leading and trailing cells a
/// month grid always shows without widening the range enough to lose the per-source indexes.
final calendarDaysProvider =
    StreamProvider.autoDispose.family<List<CalendarDay>, DateKey>((ref, month) async* {
  // The occurrences first, or the first frame of a future month shows every source except recurring.
  await ref.watch(recurringHorizonProvider.future);

  final today = ref.watch(calendarTodayProvider);
  final aggregator = ref.watch(calendarAggregatorProvider);

  final firstOfMonth = DateKey.fromYmd(month.year, month.month, 1);
  final firstOfNext = shiftMonth(firstOfMonth, 1);

  yield* aggregator.watchDays(
    from: firstOfMonth.addDays(-gridPadDays),
    to: firstOfNext.addDays(gridPadDays - 1),
    today: today,
  );
});

/// Days of overscan either side of the visible month, for the grid's leading and trailing cells.
const int gridPadDays = 6;

/// The visible month's days keyed by date, for O(1) lookup while building 42 cells.
final calendarDayIndexProvider =
    Provider.autoDispose.family<AsyncValue<Map<int, CalendarDay>>, DateKey>((ref, month) {
  return ref.watch(calendarDaysProvider(month)).whenData(
        (days) => {for (final day in days) day.date.value: day},
      );
});

/// One day's events, severity resolved — the day sheet's feed.
final dayEventsProvider = FutureProvider.autoDispose
    .family<List<CalendarEvent>, DateKey>((ref, dateKey) {
      final today = ref.watch(calendarTodayProvider);
      return ref
          .watch(calendarAggregatorProvider)
          .forDay(dateKey: dateKey, today: today);
    });

/// A closed span of days, as a provider key.
///
/// A record, so Riverpod's family caching compares by value: `(from: a, to: b)` twice is one provider.
typedef CalendarSpan = ({DateKey from, DateKey to});

/// Every entry inside [span], severity resolved, grouped-ready.
///
/// The span is whatever the user selected, so unlike `calendarDaysProvider` it is not month-shaped — but
/// it is still closed at both ends, which is the only thing the view's per-source indexes require.
final rangeEventsProvider = FutureProvider.autoDispose
    .family<List<CalendarEvent>, CalendarSpan>((ref, span) async {
      final today = ref.watch(calendarTodayProvider);
      final days = await ref
          .watch(calendarAggregatorProvider)
          .watchDays(from: span.from, to: span.to, today: today)
          .first;
      return [for (final day in days) ...day.events];
    });

/// The first of the month containing today.
///
/// The dashboard's grid must not follow `focusedMonthProvider`: browsing the calendar to December and
/// returning to the dashboard would have shown December there too. Keying the month feed by month rather
/// than reading ambient state is what makes two grids on two screens possible at all.
final currentMonthProvider = Provider<DateKey>((ref) {
  final today = ref.watch(calendarTodayProvider);
  return DateKey.fromYmd(today.year, today.month, 1);
});

/// What was spent and what came in across [span], from the transactions themselves.
///
/// **Not from the calendar feed.** `v_calendar_events` selects `original_amount_minor` as an unsigned
/// magnitude and no `kind`, so a deposit and a withdrawal are indistinguishable there. Adding `kind` to
/// the view would have meant a schema version bump and a migration for numbers a plain range read
/// already gives — so this reads `watchByDateRange` and splits by direction.
///
/// Transfers are excluded: money moving between your own accounts is neither spending nor income, and
/// counting it as both would double the totals of anyone who moves money to save it.
final spanTotalsProvider =
    StreamProvider.autoDispose.family<SpanTotals, CalendarSpan>((ref, span) {
  return ref
      .watch(transactionRepositoryProvider)
      .watchByDateRange(from: span.from, to: span.to)
      .map(SpanTotals.from);
});

/// Money in and money out over a span, in minor units.
class SpanTotals {
  /// Creates a total.
  const SpanTotals({required this.inMinor, required this.outMinor, required this.currencyCode});

  /// Sums [transactions] by direction.
  ///
  /// One currency only, and the first one seen names the result. Converting a mixed-currency span needs
  /// the frozen-rate path that belongs to analytics, and quietly adding minor units across currencies
  /// would produce a number that looks right and is not.
  factory SpanTotals.from(List<Transaction> transactions) {
    var inMinor = 0;
    var outMinor = 0;
    String? code;
    for (final tx in transactions) {
      code ??= tx.originalAmount.currencyCode;
      if (tx.originalAmount.currencyCode != code) continue;
      switch (tx.kind) {
        case TransactionKind.deposit:
        case TransactionKind.adjustmentIncrease:
          inMinor += tx.originalAmount.minor;
        case TransactionKind.withdrawal:
        case TransactionKind.adjustmentDecrease:
          outMinor += tx.originalAmount.minor;
        case TransactionKind.transfer:
          break;
      }
    }
    return SpanTotals(inMinor: inMinor, outMinor: outMinor, currencyCode: code ?? '');
  }

  /// Deposits and increases.
  final int inMinor;

  /// Withdrawals and decreases.
  final int outMinor;

  /// The currency both figures are in, empty when the span held nothing.
  final String currencyCode;

  /// Whether there is anything to show.
  bool get isEmpty => currencyCode.isEmpty;
}
```

### `lib/features/calendar/presentation/widgets/event_card.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// The wording and glyph for one [CalendarEventType].
extension CalendarEventTypeDisplay on CalendarEventType {
  /// The localised name of this event type.
  String labelOf(AlayaStrings strings) => switch (this) {
        CalendarEventType.transaction => strings.eventTypeTransaction,
        CalendarEventType.recurringDue => strings.eventTypeRecurringDue,
        CalendarEventType.batchExpiry => strings.eventTypeBatchExpiry,
        CalendarEventType.warrantyEnd => strings.eventTypeWarrantyEnd,
        CalendarEventType.serviceDue => strings.eventTypeServiceDue,
        CalendarEventType.shoppingTarget => strings.eventTypeShoppingTarget,
      };

  /// The glyph for this event type.
  IconData get icon => switch (this) {
        CalendarEventType.transaction => Icons.receipt_long_outlined,
        CalendarEventType.recurringDue => Icons.event_repeat,
        CalendarEventType.batchExpiry => Icons.inventory_2_outlined,
        CalendarEventType.warrantyEnd => Icons.verified_outlined,
        CalendarEventType.serviceDue => Icons.handyman_outlined,
        CalendarEventType.shoppingTarget => Icons.shopping_basket_outlined,
      };
}

/// The colour and wording for one [CalendarSeverity].
extension CalendarSeverityDisplay on CalendarSeverity {
  /// The chip tone matching this severity.
  StatusTone get tone => switch (this) {
        CalendarSeverity.info => StatusTone.info,
        CalendarSeverity.warning => StatusTone.warning,
        CalendarSeverity.danger => StatusTone.danger,
      };

  /// The localised severity word, or null where there is nothing to warn about.
  String? labelOrNull(AlayaStrings strings) => switch (this) {
        CalendarSeverity.info => null,
        CalendarSeverity.warning => strings.calendarSeverityWarning,
        CalendarSeverity.danger => strings.calendarSeverityDanger,
      };

  /// The colour for this severity's glyph.
  Color colorOf(AlayaSemanticColors semantic) => switch (this) {
        CalendarSeverity.info => semantic.muted,
        CalendarSeverity.warning => semantic.warning,
        CalendarSeverity.danger => semantic.danger,
      };
}

/// One calendar entry, severity-coloured and severity-labelled.
///
/// The severity word is not decoration beside the colour — it is the carrier. Colour alone fails a
/// colour-blind reader and fails in grayscale, so `warning` and `danger` always say so (Law U9).
class EventCard extends StatelessWidget {
  /// Creates a card for [event].
  const EventCard({
    required this.event,
    required this.onTap,
    this.decimalDigits = 2,
    this.showType = true,
    super.key,
  });

  /// The entry to render, with its severity already resolved by `CalendarAggregator`.
  final CalendarEvent event;

  /// Opens the underlying record.
  final VoidCallback? onTap;

  /// Minor-unit digits for the amount, from the household's currency.
  final int decimalDigits;

  /// Whether to name the event type on the card.
  ///
  /// False inside a list already grouped by type: the heading says "Transaction" and so did every card
  /// under it, which is noise on the screen and two matches for one finder in the tests.
  final bool showType;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final theme = Theme.of(context);
    final severityLabel = event.baseSeverity.labelOrNull(strings);
    final typeLabel = event.type.labelOf(strings);

    return AlayaCard(
      onTap: onTap,
      semanticsLabel: [
        event.title,
        typeLabel,
        if (severityLabel != null) severityLabel,
      ].join('. '),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            event.type.icon,
            size: AlayaIconSize.md,
            color: event.baseSeverity.colorOf(semantic),
          ),
          const SizedBox(width: AlayaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: AlayaTypography.body.copyWith(color: theme.colorScheme.onSurface),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AlayaSpacing.xxs),
                // Wrap, not Row: the type label and the severity chip both grow with text scale and
                // side by side one of them starves at 320dp (Law U21).
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (showType)
                      Text(
                        typeLabel,
                        style: AlayaTypography.caption.copyWith(color: semantic.muted),
                      ),
                    if (severityLabel != null)
                      StatusChip(label: severityLabel, tone: event.baseSeverity.tone),
                  ],
                ),
                if (event.amount != null) ...[
                  const SizedBox(height: AlayaSpacing.xxs),
                  // Under the text, not beside it (Law U21).
                  //
                  // Beside it, the amount was the Row's one inflexible child: it took its natural width
                  // first and left the `Expanded` column whatever remained. At a doubled scale on a 320dp
                  // card that remainder was about 64px, and `StatusChip` cannot shrink below its own
                  // label — so the chip overflowed by 124px. Making the amount `Flexible` only splits the
                  // starvation two ways; the fix is to stop competing for the same axis.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AmountText(
                      event.amount!,
                      size: AmountSize.small,
                      showSign: false,
                      decimalDigits: decimalDigits,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/calendar/presentation/widgets/calendar_event_list.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/widgets/event_card.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// The route for the record behind [event], or null where the feed cannot address it.
///
/// `v_calendar_events` carries `ref_type` and `ref_id` but not the parent id that three of the six
/// detail routes need — a batch route wants its item, a service record wants its asset, and a recurring
/// occurrence has no route of its own. Those land on the owning module instead. Closing it means a
/// `parent_ref_id` column on the view, which is a Phase 2A change.
String? calendarEventRoute(CalendarEvent event) => switch (event.refType) {
      'transaction' => Routes.transactionDetail(event.refId),
      'asset' => Routes.assetDetail(event.refId),
      'shoppingList' => Routes.shoppingList(event.refId),
      'inventoryBatch' => Routes.inventory,
      'serviceRecord' => Routes.services,
      'recurringOccurrence' => Routes.recurring,
      _ => null,
    };

/// Calendar entries under one heading per event type, each tappable through to its record.
///
/// Shared by the inline day section and the day sheet, because the same list rendered twice is a list
/// that will disagree with itself (ARCH_4 R25).
class CalendarEventList extends ConsumerWidget {
  /// Creates the list.
  const CalendarEventList({required this.events, this.onNavigate, super.key});

  /// The entries, with severity already resolved by `CalendarAggregator`.
  final List<CalendarEvent> events;

  /// Called just before navigating away — a sheet uses it to close itself first.
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final byType = <CalendarEventType, List<CalendarEvent>>{};
    for (final event in events) {
      (byType[event.type] ??= <CalendarEvent>[]).add(event);
    }

    // Declaration order rather than severity order: a reader scanning the same day twice should find
    // the same thing in the same place.
    final types = CalendarEventType.values.where(byType.containsKey).toList();

    return ListView.builder(
      shrinkWrap: true,
      itemCount: types.length,
      itemBuilder: (context, index) {
        final type = types[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(label: type.labelOf(strings)),
            for (final event in byType[type]!)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
                child: _Tappable(event: event, onNavigate: onNavigate),
              ),
          ],
        );
      },
    );
  }
}

/// An event card wired to its record, or inert where the feed cannot address one.
class _Tappable extends StatelessWidget {
  const _Tappable({required this.event, this.onNavigate});

  final CalendarEvent event;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final route = calendarEventRoute(event);
    return EventCard(
      event: event,
      // The type is already the heading above this card.
      showType: false,
      onTap: route == null
          ? null
          : () {
              onNavigate?.call();
              context.push(route);
            },
    );
  }
}
```

### `lib/features/calendar/presentation/widgets/calendar_month_grid.dart`

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';

/// The month grid, with one severity dot per day that has entries.
///
/// **This is the only file in the phase that imports `table_calendar`.** Every cell, the weekday row
/// and the header are built here from Alaya's own tokens through `calendarBuilders`, and
/// `headerVisible` is false — so the package supplies page arithmetic and swipe animation, and nothing
/// that a theme token would otherwise own. If the package's API differs from this, one file changes.
class CalendarMonthGrid extends StatelessWidget {
  /// Creates the grid for [month].
  const CalendarMonthGrid({
    required this.month,
    required this.today,
    required this.daysByKey,
    required this.onDaySelected,
    required this.onDayLongPressed,
    required this.onMonthChanged,
    this.lockedToMonth = false,
    this.selected,
    this.rangeStart,
    this.rangeEnd,
    super.key,
  });

  /// The visible month, as its first day.
  final DateKey month;

  /// Today, from the injected clock — never `DateTime.now()` (ARCH_2 §12.2).
  final DateKey today;

  /// The month's days that have entries, keyed by `DateKey.value`.
  final Map<int, CalendarDay> daysByKey;

  /// Called when a day cell is tapped.
  final ValueChanged<DateKey> onDaySelected;

  /// Called when a day cell is long-pressed, which is how a range begins.
  final ValueChanged<DateKey> onDayLongPressed;

  /// Called when the grid pages to another month.
  final ValueChanged<DateKey> onMonthChanged;

  /// Whether this grid shows [month] and nothing else.
  ///
  /// Turning the gesture off is not enough on its own — `firstDay` and `lastDay` still span years, so the
  /// underlying `PageView` keeps its neighbouring pages and any fling, keyboard scroll or accessibility
  /// scroll action can still reach them. Narrowing the bounds to this one month removes the pages
  /// themselves, which is what makes "static" true rather than merely discouraged.
  final bool lockedToMonth;

  /// The currently selected day, if any.
  final DateKey? selected;

  /// The first day of a selected range, if a range is being picked.
  final DateKey? rangeStart;

  /// The last day of a selected range. Null while only the start has been chosen.
  final DateKey? rangeEnd;

  /// How many years either side of the visible month the grid may page to.
  static const int _pagingYears = 5;

  /// The severity dot's diameter.
  static const double _dotSize = AlayaSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;

    // U26: the row height is measured from the current text scale, never fixed. A day cell holds a
    // number and a dot, and both grow when the reader doubles their text size while a constant
    // `rowHeight` would not — which is how a grid of text cells overflows at scale 2.
    final scaler = MediaQuery.textScalerOf(context);
    final numberHeight =
        scaler.scale(AlayaTypography.body.fontSize!) * AlayaTypography.body.height!;
    final rowHeight = math.max(
      AlayaSpacing.minTapTarget,
      numberHeight + AlayaSpacing.xxs + _dotSize + AlayaSpacing.xs,
    );
    final dowHeight = math.max(
      AlayaSpacing.md,
      scaler.scale(AlayaTypography.caption.fontSize!) * AlayaTypography.caption.height! +
          AlayaSpacing.xxs,
    );

    return TableCalendar<CalendarDay>(
      // Day zero of the following month is the last day of this one, and `DateTime.utc` normalises a
      // thirteenth month — unlike `DateKey.fromYmd`, which validates and would throw every December.
      firstDay: lockedToMonth
          ? DateTime.utc(month.year, month.month, 1)
          : DateTime.utc(today.year - _pagingYears, 1, 1),
      lastDay: lockedToMonth
          ? DateTime.utc(month.year, month.month + 1, 0)
          : DateTime.utc(today.year + _pagingYears, 12, 31),
      focusedDay: month.toUtcMidnight(),
      calendarFormat: CalendarFormat.month,
      availableCalendarFormats: const {CalendarFormat.month: ''},
      headerVisible: false,
      rowHeight: rowHeight,
      daysOfWeekHeight: dowHeight,
      startingDayOfWeek: StartingDayOfWeek.monday,
      availableGestures:
          lockedToMonth ? AvailableGestures.none : AvailableGestures.horizontalSwipe,
      selectedDayPredicate: (day) =>
          selected != null && DateKey.fromDateTime(day).value == selected!.value,
      onDaySelected: (day, _) => onDaySelected(DateKey.fromDateTime(day)),
      onDayLongPressed: (day, _) => onDayLongPressed(DateKey.fromDateTime(day)),
      onPageChanged: (day) => onMonthChanged(DateKey.fromDateTime(day)),
      calendarBuilders: CalendarBuilders<CalendarDay>(
        dowBuilder: (context, day) => Center(
          child: Text(
            _weekdayInitial(context, day),
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ),
        // Range highlighting is drawn here rather than through `rangeSelectionMode` and
        // `onRangeSelected`. The package's range mode toggles on a long-press — an invisible gesture —
        // and routes range cells to `rangeStartBuilder`/`withinRangeBuilder`/`rangeEndBuilder`, which
        // would bypass the four builders below and leave the cells unstyled. Owning the two dates and
        // decorating them in `defaultBuilder` keeps one cell widget responsible for every state, and
        // puts the control on a visible button instead of a gesture nobody discovers.
        defaultBuilder: (context, day, _) => _cell(day),
        outsideBuilder: (context, day, _) => _cell(day, outside: true),
        todayBuilder: (context, day, _) => _cell(day, isToday: true),
        selectedBuilder: (context, day, _) => _cell(day, isSelected: true),
      ),
    );
  }

  /// Builds one cell, resolving its range membership from the two dates this widget was given.
  Widget _cell(DateTime day, {bool outside = false, bool isToday = false, bool isSelected = false}) {
    final key = DateKey.fromDateTime(day);
    final start = rangeStart;
    final end = rangeEnd;
    final inRange = start != null && end != null && key.isWithin(start, end);

    return _Cell(
      day: day,
      entry: daysByKey[key.value],
      dotSize: _dotSize,
      outside: outside,
      isToday: isToday,
      isSelected: isSelected,
      inRange: inRange,
      isRangeEdge: (start != null && key == start) || (end != null && key == end),
    );
  }

  /// The single-letter weekday label for [day], in the active locale.
  static String _weekdayInitial(BuildContext context, DateTime day) {
    final symbols = MaterialLocalizations.of(context).narrowWeekdays;
    return symbols[day.weekday % DateTime.daysPerWeek];
  }
}

/// One day cell: its number, and one dot per entry up to three.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.entry,
    required this.dotSize,
    this.outside = false,
    this.isToday = false,
    this.isSelected = false,
    this.inRange = false,
    this.isRangeEdge = false,
  });

  final DateTime day;
  final CalendarDay? entry;
  final double dotSize;
  final bool outside;
  final bool isToday;
  final bool isSelected;
  final bool inRange;
  final bool isRangeEdge;

  /// The most dots a cell will draw, whatever the day holds.
  static const int _maxDots = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final count = entry?.events.length ?? 0;
    final severity = entry?.severity;

    // Colour AND count. A single dot in three hues fails a colour-blind reader and fails in grayscale,
    // and the dot is the grid's only severity signal — there is no room for a word in a 45dp cell
    // (Law U9). One dot per entry up to three gives a second, non-chromatic dimension: a busy day looks
    // busy before anyone resolves the hue, and the cell's semantics label says it outright for a reader
    // who resolves neither.
    final dotColour = switch (severity) {
      CalendarSeverity.danger => semantic.danger,
      CalendarSeverity.warning => semantic.warning,
      // Green for "there is something here, nothing is wrong". A stretch of `success`, which normally
      // means *done* — an ordinary transaction is neither good nor bad, merely present — but it is the
      // colour a calendar reader expects opposite red and amber, and inventing a fourth role for one
      // dot would be worse.
      CalendarSeverity.info => semantic.success,
      null => Colors.transparent,
    };

    final numberColour = outside
        ? semantic.muted
        : isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface;

    // **No `Semantics` here, and that is not an omission.** `table_calendar` labels every cell itself —
    // "Monday, August 10, 2026" — and excludes whatever its builders contribute, so a label added here
    // produces no node at all. Four rounds were spent asserting one that could never exist; the
    // semantics dump showed one node per cell, the package's own, with no children.
    //
    // U9 is still satisfied, by a different part of the screen. The dots are a visual affordance over
    // content that is already readable: tapping a day fills the section below with real text nodes, and
    // that section is the authoritative accessible reading of what a day holds. The grid navigates; the
    // section speaks.
    return DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : inRange
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                  : null,
          border: (isToday && !isSelected) || isRangeEdge
              ? Border.all(color: theme.colorScheme.primary)
              : null,
          borderRadius: AlayaRadii.borderSm,
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  // The day number, not a date. `DateText` renders a whole formatted date and cannot fit
                  // a grid cell — U7's "DateKey through DateText" governs displaying a date, and this is
                  // an axis label for one.
                  '${day.day}',
                  style: AlayaTypography.body.copyWith(color: numberColour),
                ),
                const SizedBox(height: AlayaSpacing.xxs),
                SizedBox(
                  height: dotSize,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < math.min(count, _maxDots); i++)
                        Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : AlayaSpacing.xxs / 2),
                          child: SizedBox(
                            width: dotSize,
                            height: dotSize,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dotColour,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}
```

### `lib/features/calendar/presentation/widgets/day_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_event_list.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/loading_state.dart';

/// One day's calendar entries, grouped by event type (ARCH_5 §3 archetype A).
class DaySheet extends ConsumerWidget {
  /// Creates the sheet for [dateKey].
  const DaySheet({required this.dateKey, super.key});

  /// Opens the sheet for [dateKey].
  static Future<void> show({
    required BuildContext context,
    required DateKey dateKey,
  }) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (_) => DaySheet(dateKey: dateKey),
      );

  /// The day being shown.
  final DateKey dateKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final events = ref.watch(dayEventsProvider(dateKey));

    // The box, not the screen. Two rounds were lost guessing at this arithmetic from `MediaQuery`:
    // first `sizeOf().height * 0.6`, which ignored the keyboard; then the same minus
    // `viewInsetsOf().bottom`, which reads **zero** here because `Scaffold` with
    // `resizeToAvoidBottomInset` consumes the inset — it shrinks the body and hands the body a
    // `MediaQuery` with the bottom inset already removed. The height I was subtracting had been
    // subtracted for me, and the box I was ignoring was the only honest number in the frame.
    //
    // `LayoutBuilder` reads that box directly, and `Flexible` gives the list whatever the header leaves
    // rather than a fraction anyone has to reason about. No arithmetic, so nothing to get wrong.
    return LayoutBuilder(
      builder: (context, constraints) {
        final header = <Widget>[
          DateText(dateKey, style: DateTextStyle.full),
          const SizedBox(height: AlayaSpacing.sm),
        ];

        final body = events.when(
          loading: () => LoadingState(label: strings.calendarLoadingDay),
          error: (error, stack) => ErrorState(
            title: strings.calendarDayErrorTitle,
            body: error.toString(),
            retryLabel: strings.calendarRetry,
            onRetry: () => ref.invalidate(dayEventsProvider(dateKey)),
          ),
          data: (list) => list.isEmpty
              ? EmptyState(
                  title: strings.calendarDayEmptyTitle,
                  body: strings.calendarDayEmptyBody,
                  icon: Icons.event_available_outlined,
                )
              : CalendarEventList(
                  events: list,
                  // Close the sheet before the push, or the record opens behind it.
                  onNavigate: () => Navigator.of(context).pop(),
                ),
        );

        // Unbounded is legitimate — a sheet host may let its content decide the height — and `Flexible`
        // asserts there, so it only appears when there is a box to divide.
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...header,
            if (constraints.hasBoundedHeight) Flexible(child: body) else body,
          ],
        );
      },
    );
  }
}
```

### `lib/features/calendar/presentation/screens/calendar_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_event_list.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_month_grid.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/loading_state.dart';

/// The calendar month view (ARCH_5 §3 archetype F).
///
/// **The section under the grid shows what is on the selected day, not how many days have something.**
/// A count is a fact about the month; the entries are the answer the reader came for. Selection starts on
/// today, so the screen says something useful before it is touched.
class CalendarScreen extends ConsumerStatefulWidget {
  /// Creates the screen, optionally opening [initialDay] on arrival.
  const CalendarScreen({this.initialDay, super.key});

  /// The day to select on arrival, when reached through `/calendar/:dateKey`.
  final DateKey? initialDay;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateKey? _selected;
  DateKey? _rangeStart;
  DateKey? _rangeEnd;
  bool _rangeMode = false;

  @override
  void initState() {
    super.initState();
    final day = widget.initialDay;
    if (day == null) return;
    // After the first frame: the month has to be focused before the grid builds, or the deep link lands
    // on today's page with another day selected.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(focusedMonthProvider.notifier).focus(day);
      setState(() => _selected = day);
    });
  }

  /// Handles a tap on [day] — the second tap of a range closes it, otherwise it starts a new one.
  void _tapDay(DateKey day) {
    setState(() {
      if (!_rangeMode) {
        _selected = day;
        return;
      }
      if (_rangeStart == null || _rangeEnd != null) {
        _rangeStart = day;
        _rangeEnd = null;
      } else if (day < _rangeStart!) {
        _rangeEnd = _rangeStart;
        _rangeStart = day;
      } else {
        _rangeEnd = day;
      }
    });
  }

  /// Starts a range at [day], or clears one already being picked.
  ///
  /// Long-press, not a button. A mode toggle in the header was a control that spent most of its life
  /// switched off, and the gesture belongs on the thing it acts upon: press a day to begin a span, tap
  /// the far end to close it, press again to go back to single days.
  void _longPressDay(DateKey day) => setState(() {
        if (_rangeMode) {
          _rangeMode = false;
          _rangeStart = null;
          _rangeEnd = null;
          _selected = day;
        } else {
          _rangeMode = true;
          _rangeStart = day;
          _rangeEnd = null;
        }
      });

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final month = ref.watch(focusedMonthProvider);
    final today = ref.watch(calendarTodayProvider);
    final index = ref.watch(calendarDayIndexProvider(month));
    final selected = _selected ?? today;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            children: [
              _MonthHeader(
                month: month,
                today: today,
                onShift: (months) => ref.read(focusedMonthProvider.notifier).shift(months),
                onToday: () {
                  ref.read(focusedMonthProvider.notifier).focus(today);
                  setState(() {
                    _selected = today;
                    _rangeStart = null;
                    _rangeEnd = null;
                  });
                },
              ),
              CalendarMonthGrid(
                month: month,
                today: today,
                daysByKey: index.valueOrNull ?? const <int, CalendarDay>{},
                selected: _rangeMode ? null : selected,
                rangeStart: _rangeStart,
                rangeEnd: _rangeEnd,
                onDaySelected: _tapDay,
                onDayLongPressed: _longPressDay,
                onMonthChanged: (day) => ref.read(focusedMonthProvider.notifier).focus(day),
              ),
              const Divider(height: AlayaSpacing.md),
              // The month feed's own loading and error states belong here, because the dots depend on it
              // and a reader who sees no dots deserves to know whether that means "nothing" or "not yet".
              index.when(
                loading: () => LoadingState(label: strings.calendarLoadingMonth),
                error: (error, stack) => ErrorState(
                  title: strings.calendarErrorTitle,
                  body: error.toString(),
                  retryLabel: strings.calendarRetry,
                  onRetry: () => ref.invalidate(calendarDaysProvider(month)),
                ),
                data: (_) => _rangeMode
                    ? _RangeSection(start: _rangeStart, end: _rangeEnd)
                    : _DaySection(day: selected),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The month label, a chevron either side, and the range toggle.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.today,
    required this.onShift,
    required this.onToday,
  });

  final DateKey month;
  final DateKey today;
  final ValueChanged<int> onShift;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final label = DateFormat.yMMMM(Localizations.localeOf(context).toLanguageTag())
        .format(month.toUtcMidnight());
    final onThisMonth = month == DateKey.fromYmd(today.year, today.month, 1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Row(
        children: [
          IconButton(
            onPressed: () => onShift(-1),
            tooltip: strings.calendarPreviousMonth,
            icon: const Icon(Icons.chevron_left, size: AlayaIconSize.md),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Between the label and the forward chevron, and only when it would do something. Sitting
          // *before* the chevron rather than after it means the three navigation controls stay together
          // and the reader's thumb does not have to travel past "next" to get "home".
          // `Visibility` with `maintainSize`, not a conditional child. Adding a child to this Row
          // shrinks the `Expanded` beside it, so the centred month label slid left the moment the
          // button appeared and slid back when it left — the heading twitching as you page through
          // months. Reserving the slot keeps the label centred on both kinds of month, and reserving it
          // via the button's own size means nothing has to hardcode 48dp.
          //
          // `maintainInteractivity` stays false, so the hidden button is neither tappable nor announced.
          Visibility(
            visible: !onThisMonth,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: IconButton(
              onPressed: onToday,
              tooltip: strings.calendarBackToToday,
              icon: const Icon(Icons.event_available_outlined, size: AlayaIconSize.md),
            ),
          ),
          IconButton(
            onPressed: () => onShift(1),
            tooltip: strings.calendarNextMonth,
            icon: const Icon(Icons.chevron_right, size: AlayaIconSize.md),
          ),
        ],
      ),
    );
  }
}

/// What is on one day.
class _DaySection extends ConsumerWidget {
  const _DaySection({required this.day});

  final DateKey day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    return _Section(
      heading: strings.calendarOnDay,
      dateLabel: DateFormat.yMMMMd(Localizations.localeOf(context).toLanguageTag())
          .format(day.toUtcMidnight()),
      events: ref.watch(dayEventsProvider(day)),
      totals: ref.watch(spanTotalsProvider((from: day, to: day))),
      emptyTitle: strings.calendarDayEmptyTitle,
      emptyBody: strings.calendarDayEmptyBody,
      onRetry: () => ref.invalidate(dayEventsProvider(day)),
    );
  }
}

/// What is inside a chosen span.
class _RangeSection extends ConsumerWidget {
  const _RangeSection({required this.start, required this.end});

  final DateKey? start;
  final DateKey? end;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final format = DateFormat.yMMMMd(locale);

    // No `start == null` branch: a range only exists because a long-press named its first day, so the
    // start is always set by the time this renders. A state that cannot be reached is a state that will
    // rot unnoticed.
    if (end == null) {
      return Padding(
        padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
        child: Text(
          strings.calendarRangePickEnd(format.format(start!.toUtcMidnight())),
          textAlign: TextAlign.center,
          style: AlayaTypography.body.copyWith(color: context.semantic.muted),
        ),
      );
    }

    final span = (from: start!, to: end!);
    return _Section(
      heading: strings.calendarInRange(start!.diffDays(end!).abs() + 1),
      dateLabel: '${format.format(start!.toUtcMidnight())} — '
          '${format.format(end!.toUtcMidnight())}',
      events: ref.watch(rangeEventsProvider(span)),
      totals: ref.watch(spanTotalsProvider(span)),
      emptyTitle: strings.calendarRangeEmptyTitle,
      emptyBody: strings.calendarRangeEmptyBody,
      onRetry: () => ref.invalidate(rangeEventsProvider(span)),
    );
  }
}

/// A heading, the span it covers, and the entries inside it — all four async states.
class _Section extends StatelessWidget {
  const _Section({
    required this.heading,
    required this.dateLabel,
    required this.events,
    required this.totals,
    required this.emptyTitle,
    required this.emptyBody,
    required this.onRetry,
  });

  final String heading;
  final String dateLabel;
  final AsyncValue<List<CalendarEvent>> events;

  /// What was spent and what came in over the same span.
  final AsyncValue<SpanTotals> totals;
  final String emptyTitle;
  final String emptyBody;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: AlayaTypography.label.copyWith(color: semantic.muted)),
          Text(
            dateLabel,
            style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
          ),
          // Between the heading and the entries, because it answers the same question at a glance that
          // reading every card would answer slowly. Absent when the span held no transactions at all,
          // rather than showing two zeroes that look like a finding.
          if (totals.valueOrNull?.isEmpty == false) _Totals(totals: totals.requireValue),
          const SizedBox(height: AlayaSpacing.xs),
          events.when(
            loading: () => LoadingState(label: strings.calendarLoadingDay),
            error: (error, stack) => ErrorState(
              title: strings.calendarDayErrorTitle,
              body: error.toString(),
              retryLabel: strings.calendarRetry,
              onRetry: onRetry,
            ),
            data: (list) => list.isEmpty
                ? EmptyState(
                    title: emptyTitle,
                    body: emptyBody,
                    icon: Icons.event_available_outlined,
                  )
                : CalendarEventList(events: list),
          ),
        ],
      ),
    );
  }
}

/// What went out and what came in over the section's span.
class _Totals extends StatelessWidget {
  const _Totals({required this.totals});

  final SpanTotals totals;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);

    // `Wrap`, so the two figures stack instead of overflowing once the text scales (Law U21).
    return Padding(
      padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
      child: Wrap(
        spacing: AlayaSpacing.md,
        runSpacing: AlayaSpacing.xxs,
        children: [
          _Figure(
            label: strings.calendarTotalOut,
            minor: totals.outMinor,
            currencyCode: totals.currencyCode,
            kind: TransactionKind.withdrawal,
          ),
          _Figure(
            label: strings.calendarTotalIn,
            minor: totals.inMinor,
            currencyCode: totals.currencyCode,
            kind: TransactionKind.deposit,
          ),
        ],
      ),
    );
  }
}

/// One labelled figure.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.minor,
    required this.currencyCode,
    required this.kind,
  });

  final String label;
  final int minor;
  final String currencyCode;

  /// Which direction this figure runs. `AmountText` derives its colour from this rather than taking a
  /// colour, so the expense red here is the same red every other amount in the app uses.
  final TransactionKind kind;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AlayaTypography.label.copyWith(color: context.semantic.muted)),
          AmountText(
            Money(minor, currencyCode),
            size: AmountSize.small,
            showSign: false,
            kind: kind,
          ),
        ],
      );
}
```


## Wiring

### `lib/app/router/app_router.dart`

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/placeholder_screen.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_detail_screen.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_editor_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_editor_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_history_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_detail_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_editor_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/occurrence_history_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_builder_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_editor_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/service_editor_screen.dart';
import 'package:alaya/features/settings/presentation/theme_lab_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/convert_to_purchase_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/shopping_list_screen.dart';
import 'package:alaya/shared/widgets/alaya_drawer.dart';

/// Whether the app is currently locked, consulted on every navigation.
typedef LockGate = bool Function();

/// The app's `go_router` configuration — hand-written, per ARCH_1 §7.3.
///
/// **The nine drawer destinations sit inside the shell; every detail and editor route sits outside
/// it** (U18). `AppBar` resolves its leading slot by checking `hasDrawer` *before* `canPop`, so a
/// detail screen rendered inside the drawer shell gets a hamburger where a back arrow belongs.
///
/// Literal-path segments are declared before their parameterised siblings, because go_router walks
/// its route list in order and `:itemId` would otherwise swallow the word `new`.
abstract final class AppRouter {
  /// Builds the router.
  static GoRouter build({
    LockGate? isLocked,
    String initialLocation = Routes.initial,
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    final locked = isLocked ?? () => false;
    return GoRouter(
      initialLocation: initialLocation,
      navigatorKey: navigatorKey,
      debugLogDiagnostics: false,
      redirect: (context, state) {
        final atLock = state.matchedLocation == Routes.lock;
        if (locked() && !atLock) return Routes.lock;
        if (!locked() && atLock) return Routes.dashboard;
        return null;
      },
      routes: [
        GoRoute(
          path: Routes.lock,
          builder: (context, state) =>
              const PlaceholderScreen(owningPhase: 'Phase 8A'),
        ),
        ShellRoute(
          // No `location` passed: `_ShellScaffold` reads it from the router, because the state handed to a
          // pathless `ShellRoute`'s builder reports `/` for every screen inside it.
          builder: (context, state, child) => _ShellScaffold(child: child),
          routes: [
            GoRoute(
              path: Routes.dashboard,
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(
              path: Routes.expenses,
              builder: (context, state) => const TransactionListScreen(),
            ),
            GoRoute(
              path: Routes.inventory,
              builder: (context, state) => const InventoryListScreen(),
            ),
            GoRoute(
              path: Routes.shopping,
              builder: (context, state) => const ShoppingListScreen(),
            ),
            GoRoute(
              path: Routes.recurring,
              builder: (context, state) => const TemplateListScreen(),
            ),
            GoRoute(
              path: Routes.services,
              builder: (context, state) => const AssetListScreen(),
            ),
            GoRoute(
              path: Routes.calendar,
              builder: (context, state) => const CalendarScreen(),
              routes: [
                // A sub-route rather than a sibling detail route: a day is a view of the month, so it
                // keeps the drawer shell and the month stays behind it (Law U27).
                GoRoute(
                  path: ':${Routes.pDateKey}',
                  builder: (context, state) => CalendarScreen(
                    initialDay: _dateKeyParam(
                      state.pathParameters[Routes.pDateKey],
                    ),
                  ),
                ),
              ],
            ),
            _destination(Routes.insights, 'Phase 7B'),
            _destination(Routes.settings, 'Phase 8A'),
          ],
        ),
        GoRoute(
          path: Routes.transactionNew,
          builder: (context, state) => const TransactionEditorScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesNew,
          builder: (context, state) => const LineItemsScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesPattern,
          builder: (context, state) => LineItemsScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionEditPattern,
          builder: (context, state) => TransactionEditorScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionDetailPattern,
          builder: (context, state) => TransactionDetailScreen(
            transactionId: state.pathParameters[Routes.pTransactionId]!,
          ),
        ),
        GoRoute(
          path: Routes.itemNew,
          builder: (context, state) => const ItemEditorScreen(),
        ),
        GoRoute(
          path: Routes.batchNewPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchHistoryPattern,
          builder: (context, state) => BatchHistoryScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchEditPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId],
          ),
        ),
        GoRoute(
          path: Routes.itemEditPattern,
          builder: (context, state) => ItemEditorScreen(
            itemId: state.pathParameters[Routes.pItemId],
          ),
        ),
        GoRoute(
          path: Routes.itemDetailPattern,
          builder: (context, state) => ItemDetailScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingConvertPattern,
          builder: (context, state) => ConvertToPurchaseScreen(
            listId: state.pathParameters[Routes.pListId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingListPattern,
          builder: (context, state) => ShoppingListScreen(
            listId: state.pathParameters[Routes.pListId],
          ),
        ),
        GoRoute(
          path: Routes.recurringNew,
          builder: (context, state) => const TemplateBuilderScreen(),
        ),
        GoRoute(
          path: Routes.recurringHistoryPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.recurringEditPattern,
          builder: (context, state) => TemplateBuilderScreen(
            templateId: state.pathParameters[Routes.pTemplateId],
          ),
        ),
        GoRoute(
          path: Routes.recurringDetailPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.assetNew,
          builder: (context, state) => const AssetEditorScreen(),
        ),
        GoRoute(
          path: Routes.serviceNewPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.serviceEditPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
            recordId: state.pathParameters[Routes.pRecordId],
          ),
        ),
        GoRoute(
          path: Routes.assetEditPattern,
          builder: (context, state) => AssetEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId],
          ),
        ),
        GoRoute(
          path: Routes.assetDetailPattern,
          builder: (context, state) => AssetDetailScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.themeLab,
          builder: (context, state) => _DetailScaffold(
            title: AlayaStrings.of(context).navThemeLab,
            child: const ThemeLabScreen(),
          ),
        ),
      ],
    );
  }

  /// A top-level drawer destination, rendered inside the shell.
  static GoRoute _destination(String path, String owningPhase) => GoRoute(
    path: path,
    builder: (context, state) => PlaceholderScreen(owningPhase: owningPhase),
  );

  /// A detail route, rendered outside the shell so it gets a back arrow rather than a hamburger.
  static GoRoute _detail(String pattern, String owningPhase) => GoRoute(
    path: pattern,
    builder: (context, state) => _DetailScaffold(
      title: AlayaDrawer.titleFor(context, state.uri.path),
      child: PlaceholderScreen(owningPhase: owningPhase),
    ),
  );
}

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // `AppBar` resolves its implied leading by checking `hasDrawer` **before** `canPop`, so a shell that
    // owns a drawer can never show a back arrow no matter how it was reached. That is fine for a drawer
    // destination switched into as a peer, and wrong for one pushed as a drill-down — and both happen
    // here: the drawer `go`es, the dashboard's module grid `push`es.
    //
    // So the slot is stated rather than implied. Pushed: a back arrow that pops the shell's own navigator
    // (`context.pop`, not `Navigator.maybePop`, which from above the shell navigator would target the root
    // one and do nothing). Switched into: null, which lets the hamburger be implied as before.
    //
    // The drawer stays attached either way, so the edge swipe still opens it on a pushed screen.
    final strings = AlayaStrings.of(context);

    // **Read from the router, not from the builder's `state`.** `ShellRoute` declares no `path`, so the
    // `GoRouterState` handed to its builder describes the *shell's* match rather than the leaf's — and a
    // pathless route's `matchedLocation` is its parent's, which here is `/`. Every screen inside the shell
    // therefore looked like the dashboard: `atDashboard` was permanently true so the home action never
    // rendered, `AlayaDrawer` highlighted Dashboard wherever you were, and `titleFor` named it too.
    //
    // `currentConfiguration` is the delegate's live `RouteMatchList`, so its `uri` is the leaf location no
    // matter which builder asks.
    final here = GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;

    // **`context.canPop()` cannot answer this question from here.** This widget is the `ShellRoute`
    // builder, so its context sits *above* the shell's own `Navigator`; `canPop` resolves against the
    // root navigator, which only ever holds the shell itself. It therefore returns false however the
    // screen was reached, `leading` was always null, and the back arrow this once tried to show could
    // never appear. The drawer's hamburger was the only leading widget users ever saw, and from a module
    // the sole way home was the system back gesture.
    //
    // So the way home is stated outright instead of inferred from a stack this context cannot see: every
    // shell screen except the dashboard carries a home action. It pops when there is something to pop and
    // navigates otherwise, so arriving by the module grid's `push` and by the drawer's `go` both end up
    // in the same place — and the hamburger keeps its slot, because the drawer is still how you move
    // between peers (Law U27).
    return Scaffold(
      drawer: AlayaDrawer(currentLocation: here),
      appBar: AppBar(
        title: Text(AlayaDrawer.titleFor(context, here)),
        // **Unconditional, deliberately.** This was `if (!atDashboard)` and never appeared, and rather
        // than reason about why a condition is false I would rather the button exist and be seen. It
        // shows on the dashboard too, where it is merely redundant — a redundant button is a far smaller
        // fault than a missing one, and its presence there is also the proof that this file is live.
        //
        // Once it is confirmed visible, `if (!atDashboard)` can come back.
        actions: [
          IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(Routes.dashboard),
            tooltip: strings.navBackToDashboard,
            icon: const Icon(Icons.home_outlined, size: AlayaIconSize.md),
          ),
        ],
      ),
      body: child,
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}

/// Parses a `:dateKey` path parameter, or null when it is absent or not a date key.
///
/// A malformed deep link opens the calendar on today rather than throwing — the route is reachable
/// from outside the app.
DateKey? _dateKeyParam(String? raw) {
  final value = int.tryParse(raw ?? '');
  if (value == null) return null;

  final year = value ~/ 10000;
  final month = (value ~/ 100) % 100;
  final day = value % 100;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  // Round-trip through `fromYmd`, which normalises overflow through `DateTime.utc`: 20260230 comes
  // back as 20260302 and fails this check, where a digit-range test alone would accept it.
  final probe = DateKey.fromYmd(year, month, day);
  return probe.value == value ? probe : null;
}
```

### `lib/app/l10n/app_en.arb`

```json
{
  "@@locale": "en",
  "appName": "Alaya",
  "@appName": {
    "description": "The app's name, shown in the drawer header."
  },
  "navDashboard": "Dashboard",
  "navExpenses": "Expenses",
  "navInventory": "Inventory",
  "navShopping": "Shopping",
  "navRecurring": "Recurring",
  "navServices": "Services",
  "navCalendar": "Calendar",
  "navInsights": "Insights",
  "navSettings": "Settings",
  "navThemeLab": "Theme Lab",
  "actionSave": "Save",
  "@actionSave": {
    "description": "Commits an edit. Active voice, and the same word appears in the resulting confirmation."
  },
  "actionSaved": "Saved",
  "actionCancel": "Cancel",
  "actionDelete": "Delete",
  "actionDeleted": "Deleted",
  "actionUndo": "Undo",
  "actionRetry": "Try again",
  "actionAdd": "Add",
  "actionEdit": "Edit",
  "actionDone": "Done",
  "actionClose": "Close",
  "actionSelect": "Select",
  "actionClear": "Clear",
  "actionClearAll": "Clear all",
  "actionSearch": "Search",
  "actionConfirm": "Confirm",
  "actionDiscard": "Discard",
  "actionKeepEditing": "Keep editing",
  "actionRemoveTag": "Remove tag",
  "@actionRemoveTag": {
    "description": "Accessibility label for the dismiss affordance on a removable tag chip."
  },
  "actionClearSearch": "Clear search",
  "@actionClearSearch": {
    "description": "Accessibility label for the clear button inside AlayaSearchField."
  },
  "addExpense": "Add expense",
  "addIncome": "Add income",
  "addTransfer": "Add transfer",
  "addItem": "Add item",
  "addToShoppingList": "Add to shopping list",
  "dateToday": "Today",
  "@dateToday": {
    "description": "DateText.relative, when the date is the clock's today. Sentence case; it can begin a row."
  },
  "dateYesterday": "Yesterday",
  "dateTomorrow": "Tomorrow",
  "emptyTitleNoTransactions": "No transactions yet",
  "emptyBodyNoTransactions": "Add your first expense and it will appear here.",
  "@emptyBodyNoTransactions": {
    "description": "An empty screen is an invitation to act, so this names the action rather than describing the emptiness."
  },
  "emptyTitleNoItems": "Nothing in your inventory",
  "emptyBodyNoItems": "Add an item to start tracking what you have at home.",
  "emptyTitleNoShopping": "Your list is empty",
  "emptyBodyNoShopping": "Add something, or let Alaya suggest items you are low on.",
  "emptyTitleNoRecurring": "No recurring bills",
  "emptyBodyNoRecurring": "Set up a bill or subscription and Alaya will remind you when it is due.",
  "emptyTitleNoResults": "No matches",
  "emptyBodyNoResults": "Try a shorter search, or check the spelling.",
  "loadingLabel": "Loading",
  "loadingTransactions": "Loading transactions",
  "errorTitleGeneric": "That did not work",
  "@errorTitleGeneric": {
    "description": "Errors do not apologise and are never vague. This pairs with a specific body message."
  },
  "errorBodyGeneric": "Something went wrong on our side. Try again.",
  "errorTitleNotFound": "Not found",
  "errorBodyNotFound": "This item may have been deleted.",
  "errorBodyNoConnection": "You are offline. Alaya works offline, but rates will not refresh.",
  "errorFieldRequired": "This is required",
  "errorAmountInvalid": "Enter an amount",
  "errorAmountZero": "Enter an amount greater than zero",
  "errorAmountInvalidCharacter": "Digits only",
  "errorAmountNegativeNotAllowed": "Enter a positive amount",
  "errorAmountTooManyDecimals": "Too many decimal places",
  "errorAmountTooLarge": "That amount is too large",
  "errorQuantityTooLarge": "That quantity is too large",
  "errorQuantityInvalid": "Enter a quantity",
  "errorQuantityInvalidCharacter": "Digits only",
  "errorQuantityNegativeNotAllowed": "Enter a positive quantity",
  "errorQuantityTooPrecise": "Too precise for this unit",
  "@errorQuantityTooPrecise": {
    "description": "The typed quantity is finer than the chosen unit can express exactly. Shown rather than rounded, because rounding a quantity silently changes what the user recorded."
  },
  "errorDateInvalid": "Choose a date",
  "confirmDeleteTitle": "Delete this?",
  "confirmDeleteBody": "You can undo this for the next few seconds.",
  "confirmDiscardTitle": "Discard your changes?",
  "confirmDiscardBody": "What you have typed will not be saved.",
  "labelAmount": "Amount",
  "labelQuantity": "Quantity",
  "labelUnit": "Unit",
  "labelDate": "Date",
  "labelAccount": "Account",
  "labelPaymentMethod": "Payment method",
  "labelPayee": "Payee",
  "labelCategory": "Category",
  "labelTags": "Tags",
  "labelNote": "Note",
  "labelFrom": "From",
  "labelTo": "To",
  "labelItem": "Item",
  "labelExpiry": "Expiry",
  "labelTotal": "Total",
  "hintSelectAccount": "Choose an account",
  "hintSelectUnit": "Choose a unit",
  "hintSelectTags": "Choose tags",
  "hintSelectDate": "Choose a date",
  "hintSearchItems": "Search items",
  "hintNote": "Add a note",
  "amountUnconverted": "{count, plural, =1{1 amount not converted} other{{count} amounts not converted}}",
  "@amountUnconverted": {
    "description": "The chip beside a total when some amounts had no exchange rate. Surfaced rather than hidden, because a total missing a row is otherwise indistinguishable from a complete one.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "amountApproximate": "Approximate rate",
  "@amountApproximate": {
    "description": "Shown when a conversion used the nearest earlier rate rather than the exact date's."
  },
  "tagCountMore": "+{count}",
  "@tagCountMore": {
    "description": "Overflow indicator when a row cannot show every tag.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "statusNeedsReview": "Needs details",
  "@statusNeedsReview": {
    "description": "StatusChip on a transaction saved by quick-add. Names what is missing, not that a flag is set."
  },
  "statusUnallocated": "Unallocated",
  "@statusUnallocated": {
    "description": "StatusChip label when a transaction's lines do not sum to its amount. The figure is a separate AmountText (U7); never auto-balanced (anomaly A11)."
  },
  "statusDetached": "Receipt deleted",
  "@statusDetached": {
    "description": "StatusChip on a batch whose source transaction was deleted. The food did not un-exist."
  },
  "statusApproximate": "Approximate",
  "lowStockLabel": "Low",
  "expiringSoonLabel": "Expiring soon",
  "expiredLabel": "Expired",
  "overdueLabel": "Overdue",
  "dueTodayLabel": "Due today",
  "paidLabel": "Paid",
  "skippedLabel": "Skipped",
  "kindDeposit": "Money in",
  "kindWithdrawal": "Money out",
  "kindTransfer": "Transfer",
  "kindAdjustmentIncrease": "Correction up",
  "kindAdjustmentDecrease": "Correction down",
  "subtypeGrocery": "Groceries",
  "subtypeHousehold": "Household",
  "subtypeElectronics": "Electronics",
  "subtypeBill": "Bill",
  "subtypeTransferSelf": "Between my accounts",
  "subtypeTransferOut": "Sent to someone",
  "subtypeSalaryIn": "Salary",
  "subtypeOtherIn": "Other income",
  "subtypeOtherOut": "Other spending",
  "needsReviewBanner": "{count, plural, =1{1 transaction needs details} other{{count} transactions need details}}",
  "@needsReviewBanner": {
    "description": "Surfaces transactions.needsReview. Quick-add saves an amount and nothing else by design; without this row that deliberate shortcut becomes silent data rot.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "needsReviewAction": "Review",
  "filterTitle": "Filter",
  "filterDateRange": "Date range",
  "filterKind": "Type",
  "filterSubtype": "Category",
  "filterApply": "Show results",
  "filterReset": "Reset",
  "filterChipAccount": "Account: {name}",
  "@filterChipAccount": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipPayee": "Payee: {name}",
  "@filterChipPayee": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipRange": "{label}",
  "@filterChipRange": {
    "placeholders": {
      "label": {
        "type": "String"
      }
    }
  },
  "rangeToday": "Today",
  "rangeLast7Days": "Last 7 days",
  "rangeLast30Days": "Last 30 days",
  "rangeThisMonth": "This month",
  "rangeLastMonth": "Last month",
  "rangeThisYear": "This year",
  "rangeAllTime": "All time",
  "rangeCustom": "Custom",
  "searchTransactionsHint": "Search notes",
  "transactionDeleted": "Transaction deleted",
  "quickAddTitle": "Quick add",
  "quickAddMoneyIn": "Money in",
  "quickAddMoneyOut": "Money out",
  "quickAddSave": "Save",
  "actionAddDetails": "Add details",
  "editorTitleNew": "New transaction",
  "editorTitleEdit": "Edit transaction",
  "sectionWhatAndHowMuch": "What and how much",
  "sectionWhereItCameFrom": "Where it came from",
  "sectionWhereItWent": "Where it went",
  "sectionWhatYouBought": "What you bought",
  "sectionWarranty": "Warranty",
  "sectionSchedule": "Schedule",
  "transferOwnAccount": "To my own account",
  "transferSomeoneElse": "To someone else",
  "transferOwnAccountHelp": "Moves money between your accounts. Your total does not change.",
  "transferSomeoneElseHelp": "Money leaves your accounts. This is a withdrawal.",
  "alsoAddToInventory": "Also add to inventory",
  "destinationNone": "Just an expense",
  "destinationInventory": "Save to Inventory",
  "destinationAsset": "Save to Services",
  "destinationRecurring": "Save to Recurring",
  "lineAdd": "Add item",
  "lineDescription": "Item",
  "lineUnitPrice": "Unit price",
  "lineAmount": "Line total",
  "lineCreatedLink": "Created: {name}",
  "@lineCreatedLink": {
    "description": "Surfaces transaction_lines.created*Id — the artefact this line produced, tappable through to it.",
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "payeeCreate": "New payee “{name}”",
  "@payeeCreate": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "saveExpense": "Save expense",
  "saveIncome": "Save income",
  "saveTransfer": "Save transfer",
  "detailSectionLines": "Items",
  "detailSectionDetails": "Details",
  "actionFreezeConversion": "Show in another currency",
  "frozenConversionNote": "Frozen on {date} at {rate}",
  "@frozenConversionNote": {
    "description": "Surfaces transactions.converted*/conversionRateRaw. A separate artefact that is never recomputed (Law L9).",
    "placeholders": {
      "date": {
        "type": "String"
      },
      "rate": {
        "type": "String"
      }
    }
  },
  "deleteReasonHint": "Why? (optional)",
  "actionDeleteTransaction": "Delete transaction",
  "labelSubtype": "Category",
  "labelKind": "Type",
  "themeLabTitle": "Theme Lab",
  "themeLabSubtitle": "Every token, component and semantic colour, light and dark.",
  "themeLabSectionSpacing": "Spacing",
  "themeLabSectionRadii": "Radii",
  "themeLabSectionTypography": "Typography",
  "themeLabSectionElevation": "Elevation",
  "themeLabSectionSemantic": "Semantic colours",
  "themeLabSectionSurfaces": "Surface tiers",
  "themeLabSectionComponents": "Components",
  "themeLabSectionPalettes": "Palettes",
  "themeLabLight": "Light",
  "themeLabDark": "Dark",
  "semanticIncome": "Income",
  "semanticExpense": "Expense",
  "semanticTransfer": "Transfer",
  "semanticWarning": "Warning",
  "semanticDanger": "Danger",
  "semanticSuccess": "Success",
  "semanticMuted": "Muted",
  "drawerSectionMoney": "Money",
  "drawerSectionHome": "Home",
  "drawerSectionMore": "More",
  "inventoryGroupFavourites": "Favourites",
  "@inventoryGroupFavourites": {
    "description": "Phase 6B — inventory."
  },
  "inventoryGroupUntagged": "Everything else",
  "@inventoryGroupUntagged": {
    "description": "Phase 6B — inventory."
  },
  "itemKindGeneric": "General",
  "@itemKindGeneric": {
    "description": "Phase 6B — inventory."
  },
  "itemKindFood": "Food",
  "@itemKindFood": {
    "description": "Phase 6B — inventory."
  },
  "itemKindMedicine": "Medicine",
  "@itemKindMedicine": {
    "description": "Phase 6B — inventory."
  },
  "itemKindBeauty": "Beauty",
  "@itemKindBeauty": {
    "description": "Phase 6B — inventory."
  },
  "itemKindHousehold": "Household",
  "@itemKindHousehold": {
    "description": "Phase 6B — inventory."
  },
  "itemKindOther": "Other",
  "@itemKindOther": {
    "description": "Phase 6B — inventory."
  },
  "filterFavouritesOnly": "Favourites only",
  "@filterFavouritesOnly": {
    "description": "Phase 6B — inventory."
  },
  "actionFavourite": "Add to favourites",
  "@actionFavourite": {
    "description": "Phase 6B — inventory."
  },
  "actionUnfavourite": "Remove from favourites",
  "@actionUnfavourite": {
    "description": "Phase 6B — inventory."
  },
  "outOfStockLabel": "Out of stock",
  "@outOfStockLabel": {
    "description": "Phase 6B — inventory."
  },
  "itemBatchCount": "{count, plural, =1{1 batch} other{{count} batches}}",
  "@itemBatchCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "loadingInventory": "Loading inventory",
  "@loadingInventory": {
    "description": "Phase 6B — inventory."
  },
  "detailSectionBatches": "Batches",
  "@detailSectionBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginPurchase": "From a purchase",
  "@batchOriginPurchase": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginManual": "Added by hand",
  "@batchOriginManual": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginImported": "Imported",
  "@batchOriginImported": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginAdjustment": "From an adjustment",
  "@batchOriginAdjustment": {
    "description": "Phase 6B — inventory."
  },
  "labelPurchased": "Purchased",
  "@labelPurchased": {
    "description": "Phase 6B — inventory."
  },
  "labelStorageLocation": "Stored in",
  "@labelStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "labelUnitCost": "Unit cost",
  "@labelUnitCost": {
    "description": "Phase 6B — inventory."
  },
  "labelInitial": "Bought",
  "@labelInitial": {
    "description": "Phase 6B — inventory."
  },
  "labelNearestExpiry": "Nearest expiry",
  "@labelNearestExpiry": {
    "description": "Phase 6B — inventory."
  },
  "labelDisplayUnit": "Shown in",
  "@labelDisplayUnit": {
    "description": "Phase 6B — inventory."
  },
  "labelItemKind": "Kind",
  "@labelItemKind": {
    "description": "Phase 6B — inventory."
  },
  "labelLowStockThreshold": "Low-stock level",
  "@labelLowStockThreshold": {
    "description": "Phase 6B — inventory."
  },
  "labelExpiryNotifyDays": "Warn before expiry",
  "@labelExpiryNotifyDays": {
    "description": "Phase 6B — inventory."
  },
  "actionConsume": "Use some",
  "@actionConsume": {
    "description": "Phase 6B — inventory."
  },
  "actionAddBatch": "Add a batch",
  "@actionAddBatch": {
    "description": "Phase 6B — inventory."
  },
  "actionViewHistory": "Movement history",
  "@actionViewHistory": {
    "description": "Phase 6B — inventory."
  },
  "actionDeleteItem": "Delete item",
  "@actionDeleteItem": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemTitle": "Delete this item?",
  "@confirmDeleteItemTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemBody": "Its {count, plural, =1{1 batch} other{{count} batches}} go with it. The movement history stays, so what you already used is still recorded.",
  "@confirmDeleteItemBody": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "itemDeleted": "Item deleted",
  "@itemDeleted": {
    "description": "Phase 6B — inventory."
  },
  "expiresInDays": "{days, plural, =0{Expires today} =1{Expires tomorrow} other{Expires in {days} days}}",
  "@expiresInDays": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "expiredDaysAgo": "{days, plural, =1{Expired yesterday} other{Expired {days} days ago}}",
  "@expiredDaysAgo": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "sectionWhatItIs": "What it is",
  "@sectionWhatItIs": {
    "description": "Phase 6B — inventory."
  },
  "sectionStockRules": "Stock rules",
  "@sectionStockRules": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryWeight": "Weight",
  "@unitCategoryWeight": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryVolume": "Volume",
  "@unitCategoryVolume": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryCount": "Count",
  "@unitCategoryCount": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryLocked": "Measured in {category}",
  "@unitCategoryLocked": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "category": {}
    }
  },
  "unitCategoryLockedHelp": "This cannot change. Every batch and movement already recorded is stored in this measure, and there is no conversion between weight, volume and count.",
  "@unitCategoryLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "expiryNotifyDaysHelp": "Days of warning before a batch expires.",
  "@expiryNotifyDaysHelp": {
    "description": "Phase 6B — inventory."
  },
  "labelFavourite": "Favourite",
  "@labelFavourite": {
    "description": "Phase 6B — inventory."
  },
  "saveItem": "Save item",
  "@saveItem": {
    "description": "Phase 6B — inventory."
  },
  "sectionHowMuch": "How much",
  "@sectionHowMuch": {
    "description": "Phase 6B — inventory."
  },
  "sectionBatchDetails": "Batch details",
  "@sectionBatchDetails": {
    "description": "Phase 6B — inventory."
  },
  "saveBatch": "Save batch",
  "@saveBatch": {
    "description": "Phase 6B — inventory."
  },
  "batchSaved": "Batch saved",
  "@batchSaved": {
    "description": "Phase 6B — inventory."
  },
  "hintStorageLocation": "Freezer, pantry, bathroom shelf…",
  "@hintStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "consumeTitle": "Use stock",
  "@consumeTitle": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindConsume": "Used",
  "@consumeKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindWaste": "Thrown away",
  "@consumeKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindExpired": "Expired",
  "@consumeKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "consumeRecorded": "Recorded",
  "@consumeRecorded": {
    "description": "Phase 6B — inventory."
  },
  "consumeFromLabel": "Taking from",
  "@consumeFromLabel": {
    "description": "Phase 6B — inventory."
  },
  "consumeFefoNote": "Oldest expiry first.",
  "@consumeFefoNote": {
    "description": "Phase 6B — inventory."
  },
  "consumeSpansBatches": "{count, plural, =1{Takes all of 1 batch} other{Spans {count} batches, writing {count} movements}}",
  "@consumeSpansBatches": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "consumeOverAvailable": "More than you have on hand",
  "@consumeOverAvailable": {
    "description": "Phase 6B — inventory."
  },
  "historyTitle": "Movement history",
  "@historyTitle": {
    "description": "Phase 6B — inventory."
  },
  "movementKindOpeningIn": "Opening stock",
  "@movementKindOpeningIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindPurchaseIn": "Bought",
  "@movementKindPurchaseIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindManualIn": "Added by hand",
  "@movementKindManualIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindConsume": "Used",
  "@movementKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "movementKindWaste": "Thrown away",
  "@movementKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "movementKindExpired": "Expired",
  "@movementKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustIn": "Adjusted up",
  "@movementKindAdjustIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustOut": "Adjusted down",
  "@movementKindAdjustOut": {
    "description": "Phase 6B — inventory."
  },
  "movementReversed": "Reversed",
  "@movementReversed": {
    "description": "Phase 6B — inventory."
  },
  "movementIsReversal": "Reverses an earlier movement",
  "@movementIsReversal": {
    "description": "Phase 6B — inventory."
  },
  "actionReverse": "Reverse",
  "@actionReverse": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseTitle": "Reverse this movement?",
  "@confirmReverseTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseBody": "An opposite movement is appended. Nothing is erased — both entries stay in the history.",
  "@confirmReverseBody": {
    "description": "Phase 6B — inventory."
  },
  "movementReversedSnack": "Movement reversed",
  "@movementReversedSnack": {
    "description": "Phase 6B — inventory."
  },
  "emptyTitleNoMovements": "Nothing recorded yet",
  "@emptyTitleNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoMovements": "Using, wasting or adjusting this batch will show up here.",
  "@emptyBodyNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoBatches": "Add a batch and it will appear here with its expiry.",
  "@emptyBodyNoBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchQuantityLockedHelp": "How much is left is worked out from the movement history. Use, waste or adjust the batch to change it.",
  "@batchQuantityLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "daysCount": "{days, plural, =1{1 day} other{{days} days}}",
  "@daysCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "groupByFavourites": "Group favourites first",
  "@groupByFavourites": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitUsed": "Record as used",
  "@consumeCommitUsed": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitWaste": "Record as thrown away",
  "@consumeCommitWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitExpired": "Record as expired",
  "@consumeCommitExpired": {
    "description": "Phase 6B — inventory."
  },
  "lowStockWithCount": "Low · {count}",
  "@lowStockWithCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "actionDeleteBatch": "Delete batch",
  "@actionDeleteBatch": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchTitle": "Delete this batch?",
  "@confirmDeleteBatchTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchBody": "The stock it still holds disappears from your on-hand total. What you already used stays in the movement history.",
  "@confirmDeleteBatchBody": {
    "description": "Phase 6B — inventory."
  },
  "batchDeleted": "Batch deleted",
  "@batchDeleted": {
    "description": "Phase 6B — inventory."
  },
  "itemCreate": "New item",
  "@itemCreate": {
    "description": "Creates a catalogued item inline while itemising a receipt."
  },
  "itemCreateHint": "No items yet — create one so this line becomes stock.",
  "@itemCreateHint": {
    "description": "Shown in the line editor when the item catalogue is empty."
  },
  "itemCreateCategoryPrompt": "How is it measured? This cannot change later.",
  "@itemCreateCategoryPrompt": {
    "description": "Prompt for unitCategory on inline creation; immutable after create (Law L8)."
  },
  "itemDuplicateBody": "You already have this item, measured the same way. Open the one you have instead of adding a second.",
  "@itemDuplicateBody": {
    "description": "Shown when an item with the same normalized name and unit category exists."
  },
  "itemUnitsMissingBody": "No units are set up for this measure yet. Pick a different measure, or add units in Settings first.",
  "@itemUnitsMissingBody": {
    "description": "Shown when the chosen UnitCategory has no rows in units."
  },
  "itemSimilarNote": "You also have this name under a different measure. That is fine — weight, volume and count never convert into each other.",
  "@itemSimilarNote": {
    "description": "Informational note, never a block: Law L8 makes same-name/different-category distinct items."
  },
  "actionOpenExisting": "Open the one I have",
  "@actionOpenExisting": {
    "description": "Opens the existing item a duplicate collides with."
  },
  "shoppingEstimate": "Estimated",
  "@shoppingEstimate": {
    "description": "Running total of estimated prices on a shopping list."
  },
  "shoppingSwitchList": "Switch list",
  "@shoppingSwitchList": {
    "description": "Opens the list manager from the app bar."
  },
  "shoppingCheckedCount": "{checked} of {total} ticked",
  "@shoppingCheckedCount": {
    "description": "Progress line above a shopping list.",
    "placeholders": {
      "checked": {},
      "total": {}
    }
  },
  "emptyTitleNoEntries": "Nothing on this list yet",
  "@emptyTitleNoEntries": {
    "description": "Shopping list empty state."
  },
  "emptyBodyNoEntries": "Add what you need, or pull in suggestions from what is running low.",
  "@emptyBodyNoEntries": {
    "description": "Shopping list empty state body."
  },
  "addEntry": "Add",
  "@addEntry": {
    "description": "Adds one entry to a shopping list."
  },
  "shoppingGroupUntagged": "Everything else",
  "@shoppingGroupUntagged": {
    "description": "Header for entries with no tag."
  },
  "actionUncheckAll": "Untick everything",
  "@actionUncheckAll": {
    "description": "Clears every tick on a shopping list."
  },
  "entryEditorTitle": "What do you need?",
  "@entryEditorTitle": {
    "description": "Entry editor sheet title."
  },
  "entryFreeTextLabel": "Name it",
  "@entryFreeTextLabel": {
    "description": "Free-text label for a shopping entry."
  },
  "entryFreeTextHint": "Television, birthday card, light bulbs…",
  "@entryFreeTextHint": {
    "description": "Hint showing that an entry need not be an inventory item."
  },
  "entryLinkItem": "Link to an item",
  "@entryLinkItem": {
    "description": "Optional link from a shopping entry to a catalogued item."
  },
  "entryNoItem": "Not in my inventory",
  "@entryNoItem": {
    "description": "Dropdown option leaving itemId null."
  },
  "labelEstimatedPrice": "Estimated price",
  "@labelEstimatedPrice": {
    "description": "Optional per-entry price estimate."
  },
  "entryNeedsSomething": "Give it a name, or link it to an item",
  "@entryNeedsSomething": {
    "description": "Rejection when neither freeText nor itemId is set."
  },
  "originAutoLowStock": "Suggested",
  "@originAutoLowStock": {
    "description": "Chip marking an auto-generated low-stock entry."
  },
  "originPromoted": "Yours now",
  "@originPromoted": {
    "description": "Chip shown once an auto entry has been edited into a manual one."
  },
  "actionSnooze": "Snooze a week",
  "@actionSnooze": {
    "description": "Hides an auto suggestion until a later date."
  },
  "actionDismiss": "Not now",
  "@actionDismiss": {
    "description": "Dismisses an auto suggestion until stock recovers and drops again."
  },
  "snoozedUntilLabel": "Snoozed until",
  "@snoozedUntilLabel": {
    "description": "Precedes a DateText on a snoozed entry."
  },
  "generateTitle": "Running low",
  "@generateTitle": {
    "description": "Low-stock suggestion sheet title."
  },
  "generateBody": "These are below the level you set. Add the ones you want.",
  "@generateBody": {
    "description": "Low-stock suggestion sheet body."
  },
  "generateShortBy": "Short by",
  "@generateShortBy": {
    "description": "Precedes a QtyText giving threshold minus stock on hand."
  },
  "generateRefresh": "Check again",
  "@generateRefresh": {
    "description": "Re-runs low-stock generation."
  },
  "generateEmptyTitle": "Nothing is running low",
  "@generateEmptyTitle": {
    "description": "Generate sheet empty state."
  },
  "generateEmptyBody": "Set a low-stock level on an item and it will show up here when it drops.",
  "@generateEmptyBody": {
    "description": "Generate sheet empty state body."
  },
  "generateAdded": "{count, plural, =1{1 suggestion added} other{{count} suggestions added}}",
  "@generateAdded": {
    "description": "Result snack after regeneration.",
    "placeholders": {
      "count": {}
    }
  },
  "convertTitle": "Turn into a purchase",
  "@convertTitle": {
    "description": "Convert-to-purchase screen title."
  },
  "convertBody": "Each ticked entry becomes one line, marked for inventory. You confirm the amount and account next.",
  "@convertBody": {
    "description": "Explains the handoff to the expense editor."
  },
  "convertConfirm": "Open the expense",
  "@convertConfirm": {
    "description": "Primary action; hands off to the 6A editor."
  },
  "convertNothingTitle": "Nothing is ticked",
  "@convertNothingTitle": {
    "description": "Convert screen empty state."
  },
  "convertNothingBody": "Tick what you actually bought, then come back.",
  "@convertNothingBody": {
    "description": "Convert screen empty state body."
  },
  "convertLineCount": "{count, plural, =1{1 line} other{{count} lines}}",
  "@convertLineCount": {
    "description": "How many lines the draft will carry.",
    "placeholders": {
      "count": {}
    }
  },
  "listManagerTitle": "Your lists",
  "@listManagerTitle": {
    "description": "List manager sheet title."
  },
  "listNameLabel": "List name",
  "@listNameLabel": {
    "description": "Field label when creating or renaming a list."
  },
  "listCreate": "New list",
  "@listCreate": {
    "description": "Creates a shopping list."
  },
  "listRename": "Rename",
  "@listRename": {
    "description": "Renames a shopping list."
  },
  "listSetDefault": "Make default",
  "@listSetDefault": {
    "description": "Marks a list as the one that opens by default."
  },
  "listDefaultBadge": "Default",
  "@listDefaultBadge": {
    "description": "Chip on the default list."
  },
  "listArchive": "Archive",
  "@listArchive": {
    "description": "Archives a shopping list."
  },
  "listUnarchive": "Restore",
  "@listUnarchive": {
    "description": "Un-archives a shopping list."
  },
  "listArchivedBadge": "Archived",
  "@listArchivedBadge": {
    "description": "Chip on an archived list."
  },
  "listArchivedSection": "Archived",
  "@listArchivedSection": {
    "description": "Section header for archived lists."
  },
  "emptyTitleNoLists": "No lists yet",
  "@emptyTitleNoLists": {
    "description": "List manager empty state."
  },
  "emptyBodyNoLists": "Create one and it becomes your default.",
  "@emptyBodyNoLists": {
    "description": "List manager empty state body."
  },
  "loadingShopping": "Loading your list",
  "@loadingShopping": {
    "description": "Skeleton label for shopping surfaces."
  },
  "actionAddToList": "Add to my list",
  "@actionAddToList": {
    "description": "Accepts a low-stock suggestion, promoting it to origin=manual so regeneration leaves it alone."
  },
  "suggestionDismissed": "Turned down",
  "@suggestionDismissed": {
    "description": "Chip on a dismissed suggestion; it stays listed so it can be accepted later."
  },
  "lineItemsTitle": "What you bought",
  "@lineItemsTitle": {
    "description": "Title of the dedicated line-items page."
  },
  "lineItemsManage": "Add or edit items",
  "@lineItemsManage": {
    "description": "Opens the line-items page from the transaction editor."
  },
  "lineItemsAdd": "Add an item",
  "@lineItemsAdd": {
    "description": "Adds one line from the line-items page."
  },
  "lineItemsSaveAndAnother": "Save & add another",
  "@lineItemsSaveAndAnother": {
    "description": "Commits the line and reopens the editor blank, so a receipt is entered without leaving the sheet."
  },
  "lineItemsCount": "{count, plural, =0{No items yet} =1{1 item} other{{count} items}}",
  "@lineItemsCount": {
    "description": "Running count on the line-items page.",
    "placeholders": {
      "count": {}
    }
  },
  "emptyTitleNoLineItems": "Nothing itemised yet",
  "@emptyTitleNoLineItems": {
    "description": "Line-items page empty state."
  },
  "emptyBodyNoLineItems": "Add what was on the receipt. Anything you leave out still counts toward the total.",
  "@emptyBodyNoLineItems": {
    "description": "Line-items page empty state body."
  },
  "actionRemove": "Remove",
  "@actionRemove": {
    "description": "Removes one line from a transaction."
  },
  "lineRemoved": "Item removed",
  "@lineRemoved": {
    "description": "Snack after removing a line."
  },
  "lineItemsAllocated": "Itemised",
  "@lineItemsAllocated": {
    "description": "Precedes the summed line total on the line-items page."
  },
  "recurringOutflow": "Going out",
  "@recurringOutflow": {
    "description": "Group header for outflow templates."
  },
  "recurringInflow": "Coming in",
  "@recurringInflow": {
    "description": "Group header for inflow templates — salary reads as income, not a negative bill."
  },
  "recurringNextDue": "Next",
  "@recurringNextDue": {
    "description": "Precedes a DateText giving the next due date."
  },
  "recurringOverdue": "Overdue",
  "@recurringOverdue": {
    "description": "Chip on an occurrence past its due date. Derived from the clock, never stored."
  },
  "recurringPaused": "Paused",
  "@recurringPaused": {
    "description": "Chip on a paused template."
  },
  "recurringDueToday": "Due today",
  "@recurringDueToday": {
    "description": "Chip when the next occurrence falls today."
  },
  "emptyTitleNoTemplates": "Nothing recurring yet",
  "@emptyTitleNoTemplates": {
    "description": "Template list empty state."
  },
  "emptyBodyNoTemplates": "Add a bill, a subscription or a salary and it will appear here when it is next due.",
  "@emptyBodyNoTemplates": {
    "description": "Template list empty state body."
  },
  "addTemplate": "Add",
  "@addTemplate": {
    "description": "Adds a recurring template."
  },
  "actionPause": "Pause",
  "@actionPause": {
    "description": "Pauses a template."
  },
  "actionResume": "Resume",
  "@actionResume": {
    "description": "Resumes a paused template."
  },
  "loadingRecurring": "Loading your schedule",
  "@loadingRecurring": {
    "description": "Skeleton label for recurring surfaces."
  },
  "builderSectionWhat": "What it is",
  "@builderSectionWhat": {
    "description": "First section of the template builder."
  },
  "builderSectionWhen": "How often",
  "@builderSectionWhen": {
    "description": "Frequency section of the template builder."
  },
  "builderSectionDefaults": "Defaults",
  "@builderSectionDefaults": {
    "description": "Amount and account section of the template builder."
  },
  "labelTemplateName": "Name",
  "@labelTemplateName": {
    "description": "Template name field."
  },
  "labelRecurringKind": "Kind",
  "@labelRecurringKind": {
    "description": "Bill, subscription, rent or salary."
  },
  "labelDirection": "Direction",
  "@labelDirection": {
    "description": "Whether money goes out or comes in."
  },
  "directionOutflow": "Money out",
  "@directionOutflow": {
    "description": "RecurringDirection.outflow."
  },
  "directionInflow": "Money in",
  "@directionInflow": {
    "description": "RecurringDirection.inflow."
  },
  "kindBill": "Bill",
  "@kindBill": {
    "description": "RecurringKind.bill."
  },
  "kindSubscription": "Subscription",
  "@kindSubscription": {
    "description": "RecurringKind.subscription."
  },
  "kindRent": "Rent",
  "@kindRent": {
    "description": "RecurringKind.rent."
  },
  "kindSalary": "Salary",
  "@kindSalary": {
    "description": "RecurringKind.salary."
  },
  "labelEvery": "Every",
  "@labelEvery": {
    "description": "Precedes the interval count and unit."
  },
  "unitDay": "{count, plural, =1{day} other{days}}",
  "@unitDay": {
    "description": "RecurringIntervalUnit.day.",
    "placeholders": {
      "count": {}
    }
  },
  "unitWeek": "{count, plural, =1{week} other{weeks}}",
  "@unitWeek": {
    "description": "RecurringIntervalUnit.week.",
    "placeholders": {
      "count": {}
    }
  },
  "unitMonth": "{count, plural, =1{month} other{months}}",
  "@unitMonth": {
    "description": "RecurringIntervalUnit.month.",
    "placeholders": {
      "count": {}
    }
  },
  "unitYear": "{count, plural, =1{year} other{years}}",
  "@unitYear": {
    "description": "RecurringIntervalUnit.year.",
    "placeholders": {
      "count": {}
    }
  },
  "labelAnchorDay": "On day of the month",
  "@labelAnchorDay": {
    "description": "anchorDayOfMonth. Stored once, clamped at render (anomaly A13)."
  },
  "anchorDayHelp": "Kept as you set it. Anchored on the 31st, a short month falls on its last day and the next long month returns to the 31st.",
  "@anchorDayHelp": {
    "description": "Explains that the anchor never walks backwards."
  },
  "labelStartDate": "Starts",
  "@labelStartDate": {
    "description": "startDateKey."
  },
  "labelEndDate": "Ends",
  "@labelEndDate": {
    "description": "endDateKey, optional."
  },
  "labelDefaultAmount": "Usual amount",
  "@labelDefaultAmount": {
    "description": "defaultAmount — a default, not a fixed figure."
  },
  "labelRemindBefore": "Remind me",
  "@labelRemindBefore": {
    "description": "remindDaysBefore."
  },
  "saveTemplate": "Save",
  "@saveTemplate": {
    "description": "Commits the template."
  },
  "previewTitle": "Next three",
  "@previewTitle": {
    "description": "Header of the frequency preview."
  },
  "previewEmpty": "Set a start date to see when this lands.",
  "@previewEmpty": {
    "description": "Frequency preview with nothing to show."
  },
  "previewClamped": "Shortened to fit the month",
  "@previewClamped": {
    "description": "Marks a previewed date the anchor could not reach."
  },
  "payTitle": "Record this payment",
  "@payTitle": {
    "description": "Pay sheet title."
  },
  "payTitleInflow": "Record this receipt",
  "@payTitleInflow": {
    "description": "Pay sheet title for an inflow."
  },
  "labelActualAmount": "Amount actually paid",
  "@labelActualAmount": {
    "description": "The real figure, which may differ from the default."
  },
  "labelActualAmountInflow": "Amount actually received",
  "@labelActualAmountInflow": {
    "description": "Inflow wording for the same field."
  },
  "payUsualWas": "Usually",
  "@payUsualWas": {
    "description": "Precedes the default amount when the actual differs from it."
  },
  "labelPaidOn": "Paid on",
  "@labelPaidOn": {
    "description": "paidDateKey."
  },
  "payCommit": "Record it",
  "@payCommit": {
    "description": "Commits the payment and creates the transaction."
  },
  "payRecorded": "Recorded",
  "@payRecorded": {
    "description": "Result snack after paying."
  },
  "payNeedsAccount": "Choose which account it came from",
  "@payNeedsAccount": {
    "description": "Rejection when no account is selected."
  },
  "payUndoTitle": "Undo this payment?",
  "@payUndoTitle": {
    "description": "Confirmation before undoing."
  },
  "payUndoBody": "The obligation goes back to due and the transaction it created is deleted. Anything that transaction produced — stock, an asset — goes with it.",
  "@payUndoBody": {
    "description": "Says exactly what undo reverses, in the order it happens (ARCH_5 §5.4)."
  },
  "payUndone": "Payment undone",
  "@payUndone": {
    "description": "Result snack after undoing."
  },
  "actionSkip": "Skip this one",
  "@actionSkip": {
    "description": "Marks an occurrence deliberately skipped."
  },
  "occurrenceSkipped": "Skipped",
  "@occurrenceSkipped": {
    "description": "Chip on a skipped occurrence, and the snack after skipping."
  },
  "historyRecurringTitle": "Payment history",
  "@historyRecurringTitle": {
    "description": "Occurrence history screen title."
  },
  "historyDefaultVsActual": "Differed from the usual amount",
  "@historyDefaultVsActual": {
    "description": "Badge when paidAmount != defaultAmount."
  },
  "emptyTitleNoOccurrences": "Nothing due yet",
  "@emptyTitleNoOccurrences": {
    "description": "Occurrence history empty state."
  },
  "emptyBodyNoOccurrences": "Occurrences appear as their due dates arrive. Nothing is ever paid for you.",
  "@emptyBodyNoOccurrences": {
    "description": "Empty state body, stating anomaly A14 plainly."
  },
  "statusDue": "Due",
  "@statusDue": {
    "description": "RecurringOccurrenceStatus.due."
  },
  "statusPaid": "Paid",
  "@statusPaid": {
    "description": "RecurringOccurrenceStatus.paid."
  },
  "statusDismissed": "Dismissed",
  "@statusDismissed": {
    "description": "RecurringOccurrenceStatus.dismissed."
  },
  "kindServiceFee": "Service fee",
  "@kindServiceFee": {
    "description": "RecurringKind.serviceFee — a recurring charge tied to an asset."
  },
  "kindOther": "Something else",
  "@kindOther": {
    "description": "RecurringKind.other — anything the named kinds do not cover."
  },
  "billDueSection": "Due now",
  "@billDueSection": {
    "description": "Header above the recurring bills a payment can settle."
  },
  "billSetUpAction": "Set up a recurring bill",
  "@billSetUpAction": {
    "description": "Opens the template builder from the bill form."
  },
  "billNothingDue": "Nothing is due right now.",
  "@billNothingDue": {
    "description": "Shown in the bill form when no occurrence is outstanding."
  },
  "recurringScheduleNext": "Saved. Now set how often it repeats.",
  "@recurringScheduleNext": {
    "description": "Snack after a line asked to become recurring."
  },
  "recurringNotYetDue": "Not due yet",
  "@recurringNotYetDue": {
    "description": "Chip when the next occurrence has not materialised."
  },
  "billSettlesLabel": "Settling",
  "@billSettlesLabel": {
    "description": "Precedes the recurring bill this payment will settle."
  },
  "billSettleNone": "Not a recurring bill",
  "@billSettleNone": {
    "description": "Option that leaves the payment unlinked to any template."
  },
  "billSettleHelp": "Pick one and the amount below becomes what you actually paid. Saving records it once.",
  "@billSettleHelp": {
    "description": "Explains that the editor is the single write path for a bill payment."
  },
  "billAmountBecomesPaid": "This amount is what gets recorded",
  "@billAmountBecomesPaid": {
    "description": "Helper under the amount when a bill is selected."
  },
  "billAccountAuto": "Paid from",
  "@billAccountAuto": {
    "description": "Precedes the account resolved automatically for a bill payment."
  },
  "billAccountAskOnce": "Which account does this come from? Alaya remembers it on the bill.",
  "@billAccountAskOnce": {
    "description": "Shown only when no template default, no app default and more than one account exist."
  },
  "assetGroupAppliance": "Appliances",
  "@assetGroupAppliance": {
    "description": "AssetType.appliance group header."
  },
  "assetGroupElectronics": "Electronics",
  "@assetGroupElectronics": {
    "description": "AssetType.electronics."
  },
  "assetGroupVehicle": "Vehicles",
  "@assetGroupVehicle": {
    "description": "AssetType.vehicle."
  },
  "assetGroupFurniture": "Furniture",
  "@assetGroupFurniture": {
    "description": "AssetType.furniture."
  },
  "assetGroupProperty": "Property",
  "@assetGroupProperty": {
    "description": "AssetType.property."
  },
  "assetGroupServiceProvider": "People",
  "@assetGroupServiceProvider": {
    "description": "AssetType.serviceProvider — a maid or gardener lives here, not in a second system."
  },
  "assetGroupSubscription": "Subscriptions",
  "@assetGroupSubscription": {
    "description": "AssetType.subscription."
  },
  "assetGroupOther": "Other",
  "@assetGroupOther": {
    "description": "AssetType.other."
  },
  "assetUnderWarranty": "In warranty",
  "@assetUnderWarranty": {
    "description": "Chip when warrantyEndDateKey is still ahead."
  },
  "assetWarrantyEnding": "Warranty ending",
  "@assetWarrantyEnding": {
    "description": "Chip when the warranty ends soon."
  },
  "assetWarrantyExpired": "Out of warranty",
  "@assetWarrantyExpired": {
    "description": "Chip when the warranty has passed."
  },
  "assetServiceDue": "Service due",
  "@assetServiceDue": {
    "description": "Chip when nextServiceDueDateKey has passed."
  },
  "assetServiceSoon": "Service soon",
  "@assetServiceSoon": {
    "description": "Chip when a service is close."
  },
  "assetDisposedChip": "Disposed",
  "@assetDisposedChip": {
    "description": "Chip on a disposed asset."
  },
  "assetUnderRepair": "Being repaired",
  "@assetUnderRepair": {
    "description": "AssetStatus.underRepair."
  },
  "filterShowDisposed": "Include disposed",
  "@filterShowDisposed": {
    "description": "Filter that brings disposed assets back into the list."
  },
  "emptyTitleNoAssets": "Nothing tracked yet",
  "@emptyTitleNoAssets": {
    "description": "Asset list empty state."
  },
  "emptyBodyNoAssets": "Add an appliance, a vehicle, or the person who helps around the house — they all live here.",
  "@emptyBodyNoAssets": {
    "description": "Asset list empty state body, stating the serviceProvider case plainly."
  },
  "addAsset": "Add",
  "@addAsset": {
    "description": "Adds an asset."
  },
  "loadingAssets": "Loading your things",
  "@loadingAssets": {
    "description": "Skeleton label for service surfaces."
  },
  "assetSectionIdentity": "Details",
  "@assetSectionIdentity": {
    "description": "Identity section on the detail screen."
  },
  "assetSectionWarranty": "Warranty",
  "@assetSectionWarranty": {
    "description": "Warranty section."
  },
  "assetSectionContact": "Contact",
  "@assetSectionContact": {
    "description": "Contact block."
  },
  "assetSectionService": "Service history",
  "@assetSectionService": {
    "description": "Service records section."
  },
  "assetSectionSalary": "Salary history",
  "@assetSectionSalary": {
    "description": "Service records section for a serviceProvider."
  },
  "assetLifetimeCost": "Spent on service so far",
  "@assetLifetimeCost": {
    "description": "Sum of every service record cost."
  },
  "assetLifetimeSalary": "Paid so far",
  "@assetLifetimeSalary": {
    "description": "The same figure for a serviceProvider."
  },
  "labelBrand": "Brand",
  "@labelBrand": {
    "description": "assets.brand."
  },
  "labelModelNo": "Model",
  "@labelModelNo": {
    "description": "assets.modelNo."
  },
  "labelSerialNo": "Serial",
  "@labelSerialNo": {
    "description": "assets.serialNo."
  },
  "labelPurchasePrice": "Bought for",
  "@labelPurchasePrice": {
    "description": "assets.purchasePrice."
  },
  "labelWarrantyStart": "Warranty from",
  "@labelWarrantyStart": {
    "description": "assets.warrantyStartDateKey."
  },
  "labelWarrantyEnd": "Warranty until",
  "@labelWarrantyEnd": {
    "description": "assets.warrantyEndDateKey."
  },
  "labelWarrantyProvider": "Covered by",
  "@labelWarrantyProvider": {
    "description": "assets.warrantyProvider."
  },
  "labelServiceInterval": "Service every",
  "@labelServiceInterval": {
    "description": "assets.serviceIntervalDays."
  },
  "labelNextService": "Next service",
  "@labelNextService": {
    "description": "assets.nextServiceDueDateKey."
  },
  "labelContactName": "Name",
  "@labelContactName": {
    "description": "assets.primaryContactName."
  },
  "labelContactPhone": "Phone",
  "@labelContactPhone": {
    "description": "assets.primaryContactPhone."
  },
  "labelLocation": "Kept in",
  "@labelLocation": {
    "description": "assets.location."
  },
  "actionCall": "Call",
  "@actionCall": {
    "description": "Dials primaryContactPhone."
  },
  "callFailed": "No app on this phone can place that call.",
  "@callFailed": {
    "description": "Shown when the tel: intent finds no handler."
  },
  "actionAddService": "Record a service",
  "@actionAddService": {
    "description": "Adds a service record."
  },
  "actionAddSalary": "Record a payment",
  "@actionAddSalary": {
    "description": "The same action for a serviceProvider."
  },
  "actionDispose": "Dispose of it",
  "@actionDispose": {
    "description": "Opens the dispose sheet."
  },
  "actionUndispose": "Bring it back",
  "@actionUndispose": {
    "description": "Reverses a disposal."
  },
  "assetLinkedRecurring": "Paid on a schedule",
  "@assetLinkedRecurring": {
    "description": "Chip when linkedRecurringTemplateId is set."
  },
  "emptyBodyNoServices": "Nothing recorded against this yet.",
  "@emptyBodyNoServices": {
    "description": "Empty service history."
  },
  "labelAssetName": "What is it?",
  "@labelAssetName": {
    "description": "assets.name."
  },
  "labelAssetType": "Kind",
  "@labelAssetType": {
    "description": "assets.type."
  },
  "assetTypeHelpPerson": "A person you pay regularly belongs here too — their payments become service records.",
  "@assetTypeHelpPerson": {
    "description": "Explains AssetType.serviceProvider when it is chosen."
  },
  "saveAsset": "Save",
  "@saveAsset": {
    "description": "Commits an asset."
  },
  "serviceIntervalHelp": "Days between services. The next due date moves on each time you record one.",
  "@serviceIntervalHelp": {
    "description": "Explains serviceIntervalDays."
  },
  "labelServiceType": "What happened",
  "@labelServiceType": {
    "description": "service_records.type."
  },
  "serviceTypeService": "Serviced",
  "@serviceTypeService": {
    "description": "ServiceRecordType.service."
  },
  "serviceTypeRepair": "Repaired",
  "@serviceTypeRepair": {
    "description": "ServiceRecordType.repair."
  },
  "serviceTypeMaintenance": "Maintenance",
  "@serviceTypeMaintenance": {
    "description": "ServiceRecordType.maintenance."
  },
  "serviceTypeInspection": "Inspection",
  "@serviceTypeInspection": {
    "description": "ServiceRecordType.inspection."
  },
  "serviceTypeSalaryPaid": "Salary paid",
  "@serviceTypeSalaryPaid": {
    "description": "ServiceRecordType.salaryPaid — the maid case."
  },
  "serviceTypeOther": "Something else",
  "@serviceTypeOther": {
    "description": "ServiceRecordType.other."
  },
  "labelProviderName": "Who did it",
  "@labelProviderName": {
    "description": "service_records.providerName."
  },
  "labelProviderPhone": "Their number",
  "@labelProviderPhone": {
    "description": "service_records.providerPhone."
  },
  "labelServiceDate": "When",
  "@labelServiceDate": {
    "description": "service_records.serviceDateKey."
  },
  "labelServiceCost": "Cost",
  "@labelServiceCost": {
    "description": "service_records.cost."
  },
  "labelNextDue": "Next one due",
  "@labelNextDue": {
    "description": "service_records.nextDueDateKey."
  },
  "alsoRecordAsExpense": "Also record it as an expense",
  "@alsoRecordAsExpense": {
    "description": "The alsoRecordAsExpense toggle."
  },
  "alsoRecordHelp": "Writes a withdrawal for the cost as well, so it shows in your ledger.",
  "@alsoRecordHelp": {
    "description": "Explains what the toggle writes."
  },
  "alsoRecordNeedsAccount": "Choose which account it comes from",
  "@alsoRecordNeedsAccount": {
    "description": "Rejection when the toggle is on with no account."
  },
  "alsoRecordNeedsCost": "Add a cost first",
  "@alsoRecordNeedsCost": {
    "description": "Rejection when the toggle is on with no cost."
  },
  "saveService": "Save",
  "@saveService": {
    "description": "Commits a service record."
  },
  "disposeTitle": "What happened to it?",
  "@disposeTitle": {
    "description": "Dispose sheet title."
  },
  "disposeBody": "It stays in your records either way — what you spent on it still counts. This just stops it appearing as something you own.",
  "@disposeBody": {
    "description": "States anomaly A30 plainly: an asset is never deleted."
  },
  "disposeReasonSold": "Sold it",
  "@disposeReasonSold": {
    "description": "AssetDisposalReason.sold."
  },
  "disposeReasonExpired": "Wore out",
  "@disposeReasonExpired": {
    "description": "AssetDisposalReason.expired."
  },
  "disposeReasonDamaged": "Broke",
  "@disposeReasonDamaged": {
    "description": "AssetDisposalReason.damaged."
  },
  "disposeReasonGifted": "Gave it away",
  "@disposeReasonGifted": {
    "description": "AssetDisposalReason.gifted."
  },
  "disposeReasonLost": "Lost it",
  "@disposeReasonLost": {
    "description": "AssetDisposalReason.lost."
  },
  "disposeReasonReplaced": "Replaced it",
  "@disposeReasonReplaced": {
    "description": "AssetDisposalReason.replaced."
  },
  "disposeReasonOther": "Something else",
  "@disposeReasonOther": {
    "description": "AssetDisposalReason.other."
  },
  "labelDisposalAmount": "Got back",
  "@labelDisposalAmount": {
    "description": "assets.disposalAmount — what the disposal recovered."
  },
  "labelDisposalDate": "When",
  "@labelDisposalDate": {
    "description": "assets.disposedAtDateKey."
  },
  "disposeCommit": "Record it",
  "@disposeCommit": {
    "description": "Commits the disposal."
  },
  "disposeDone": "Recorded",
  "@disposeDone": {
    "description": "Snack after disposing."
  },
  "undisposeDone": "Back in your list",
  "@undisposeDone": {
    "description": "Snack after un-disposing."
  },
  "disposeNeedsReason": "Pick what happened",
  "@disposeNeedsReason": {
    "description": "Rejection when no reason is chosen."
  },
  "hintSearchAssets": "Search your things and people",
  "@hintSearchAssets": {
    "description": "Search hint on the asset list."
  },
  "errorWarrantyBackwards": "The warranty cannot end before it starts",
  "@errorWarrantyBackwards": {
    "description": "Field error when warrantyEndDateKey precedes warrantyStartDateKey."
  },
  "sectionMoney": "Money",
  "@sectionMoney": {
    "description": "Header above the cost and expense controls on the service editor."
  },
  "assetCreatedFromPurchase": "Saved. Now say what it is and how long it is covered.",
  "@assetCreatedFromPurchase": {
    "description": "Snack after a purchase line created an asset."
  },
  "destinationHelpNone": "Recorded as spending and nothing else.",
  "@destinationHelpNone": {
    "description": "Explains destination none."
  },
  "destinationHelpInventory": "Groceries, refills, anything measured and consumed. Needs an item and a quantity, and creates stock you can run down.",
  "@destinationHelpInventory": {
    "description": "Explains destination inventory."
  },
  "destinationHelpAsset": "A phone, a fridge, a chair. Creates something you own, with its own warranty and service history.",
  "@destinationHelpAsset": {
    "description": "Explains destination asset."
  },
  "destinationHelpRecurring": "Sets up a schedule so this comes back every month.",
  "@destinationHelpRecurring": {
    "description": "Explains destination recurring."
  },
  "assetSameNameNote": "You already have one called this. That is fine — this will be a separate one, with its own warranty and service history.",
  "@assetSameNameNote": {
    "description": "Informational note when an asset name repeats. Never a block: five iPhones are five assets."
  },
  "@destinationNone": {
    "description": "No artefact. Recorded as spending and nothing else."
  },
  "@destinationInventory": {
    "description": "Creates stock. Names the Inventory module, matching navInventory."
  },
  "@destinationAsset": {
    "description": "Creates an asset. Names the Services module, matching navServices."
  },
  "@destinationRecurring": {
    "description": "Hands off to the template builder. Matches navRecurring."
  },
  "actionSetWarranty": "Set the warranty",
  "@actionSetWarranty": {
    "description": "Snack action opening the asset a purchase line created."
  },
  "labelPaymentMethodOptional": "How you paid (optional)",
  "@labelPaymentMethodOptional": {
    "description": "Optional payment method on the service editor. Travels to the expense, never onto the record."
  },
  "dashboardTitle": "Home",
  "@dashboardTitle": {
    "description": "Dashboard screen title."
  },
  "fundsAvailable": "Total available funds",
  "@fundsAvailable": {
    "description": "Label above the one headline figure on the dashboard."
  },
  "fundsUnconverted": "{count, plural, =1{1 balance not converted} other{{count} balances not converted}}",
  "@fundsUnconverted": {
    "description": "Chip when BalanceService could not convert some accounts. Excluded from the headline, never summed (anomaly A34).",
    "placeholders": {
      "count": {}
    }
  },
  "fundsApproximate": "Rate is older than today",
  "@fundsApproximate": {
    "description": "Chip when the conversion used the most recent rate on or before today."
  },
  "fundsWhyExcluded": "Balances Alaya has no rate for are left out rather than guessed at.",
  "@fundsWhyExcluded": {
    "description": "Explains why the headline may be lower than the sum of every account."
  },
  "rangeLast30": "Last 30 days",
  "@rangeLast30": {
    "description": "Range label. Always stated, never implied (anomaly A33)."
  },
  "rangeMoneyIn": "In",
  "@rangeMoneyIn": {
    "description": "Deposits over the labelled range."
  },
  "rangeMoneyOut": "Out",
  "@rangeMoneyOut": {
    "description": "Withdrawals over the labelled range."
  },
  "rangeNothingYet": "Nothing yet",
  "@rangeNothingYet": {
    "description": "Shown in place of a figure when a range holds no transactions."
  },
  "rangeExcluded": "{count, plural, =1{1 left out} other{{count} left out}}",
  "@rangeExcluded": {
    "description": "Chip when transactions in a foreign currency could not be converted into the range total.",
    "placeholders": {
      "count": {}
    }
  },
  "insightUpcoming": "Coming up",
  "@insightUpcoming": {
    "description": "The calendar side of the switchable insight card."
  },
  "insightSpending": "Where it went",
  "@insightSpending": {
    "description": "The analytics side of the switchable insight card."
  },
  "insightSwitchLabel": "Show",
  "@insightSwitchLabel": {
    "description": "Semantics label for the insight card switch."
  },
  "insightNothingUpcoming": "Nothing needs attention in the next fortnight.",
  "@insightNothingUpcoming": {
    "description": "Empty state for the upcoming side."
  },
  "insightAnalyticsPending": "Spending breakdowns arrive with the analytics module.",
  "@insightAnalyticsPending": {
    "description": "Honest empty state: AnalyticsService has no data adapter until Phase 7B (ARCH_4 §5.1 item 15)."
  },
  "insightBillDue": "Bill due",
  "@insightBillDue": {
    "description": "Upcoming row for a recurring occurrence."
  },
  "insightServiceDue": "Service due",
  "@insightServiceDue": {
    "description": "Upcoming row for an asset needing service."
  },
  "insightWarrantyEnding": "Warranty ending",
  "@insightWarrantyEnding": {
    "description": "Upcoming row for an expiring warranty."
  },
  "insightBatchExpiring": "Expiring",
  "@insightBatchExpiring": {
    "description": "Upcoming row for a batch past or near its expiry."
  },
  "moduleGridTitle": "Where to next",
  "@moduleGridTitle": {
    "description": "Header above the navigation tiles."
  },
  "moduleExpenses": "{count, plural, =0{none this month} =1{1 this month} other{{count} this month}}",
  "@moduleExpenses": {
    "description": "Live number on the Expenses tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleInventory": "{count, plural, =0{nothing tracked} =1{1 running low} other{{count} running low}}",
  "@moduleInventory": {
    "description": "Live number on the Inventory tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleShopping": "{count, plural, =0{list is clear} =1{1 to buy} other{{count} to buy}}",
  "@moduleShopping": {
    "description": "Live number on the Shopping tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleRecurring": "{count, plural, =0{all settled} =1{1 due} other{{count} due}}",
  "@moduleRecurring": {
    "description": "Live number on the Recurring tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleServices": "{count, plural, =0{nothing needs doing} =1{1 needs attention} other{{count} need attention}}",
  "@moduleServices": {
    "description": "Live number on the Services tile.",
    "placeholders": {
      "count": {}
    }
  },
  "fabAddIncome": "Money in",
  "@fabAddIncome": {
    "description": "FAB action opening the editor as a deposit."
  },
  "fabAddItem": "New item",
  "@fabAddItem": {
    "description": "FAB action opening the item editor."
  },
  "loadingDashboard": "Adding it up",
  "@loadingDashboard": {
    "description": "Skeleton label for the dashboard."
  },
  "fabOpenLabel": "Add something",
  "@fabOpenLabel": {
    "description": "Semantics label for the closed expandable FAB."
  },
  "fabCloseLabel": "Close",
  "@fabCloseLabel": {
    "description": "Semantics label for the open expandable FAB."
  },
  "eventTypeTransaction": "Transaction",
  "eventTypeRecurringDue": "Recurring bill",
  "eventTypeBatchExpiry": "Expiring",
  "eventTypeWarrantyEnd": "Warranty ending",
  "eventTypeServiceDue": "Service due",
  "eventTypeShoppingTarget": "Shopping target",
  "calendarSeverityWarning": "Needs attention",
  "calendarSeverityDanger": "Past its date",
  "calendarLoadingDay": "Loading this day…",
  "calendarDayErrorTitle": "Could not load this day",
  "calendarDayEmptyTitle": "Nothing on this day",
  "calendarDayEmptyBody": "No transactions, bills, expiries or services fall here.",
  "calendarRetry": "Try again",
  "calendarLoadingMonth": "Loading this month…",
  "calendarErrorTitle": "Could not load the calendar",
  "calendarPreviousMonth": "Previous month",
  "calendarNextMonth": "Next month",
  "calendarOnDay": "On this day",
  "calendarRangeOn": "Select a range",
  "calendarRangeOff": "Stop selecting a range",
  "calendarRangePickEnd": "From {start} — tap another day to finish.",
  "calendarInRange": "{count, plural, =1{1 day} other{{count} days}}",
  "calendarRangeEmptyTitle": "Nothing in these days",
  "calendarRangeEmptyBody": "No transactions, bills, expiries or services fall inside the range.",
  "@calendarRangePickEnd": {
    "description": "Prompt after the range start is chosen.",
    "placeholders": {
      "start": {
        "type": "String"
      }
    }
  },
  "@calendarInRange": {
    "description": "How many days the chosen range spans.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "calendarBackToToday": "Back to this month",
  "calendarTotalOut": "Spent",
  "calendarTotalIn": "Received",
  "dashboardOpenCalendar": "Open calendar",
  "dashboardCalendarSemantics": "{month} at a glance. Opens the calendar.",
  "@dashboardCalendarSemantics": {
    "description": "Screen-reader label for the dashboard month card where days are too narrow to tap.",
    "placeholders": {
      "month": {
        "type": "String"
      }
    }
  },
  "navBackToDashboard": "Back to dashboard"
}
```


## Tests

### `test/support/calendar_harness.dart`

```dart
/// Shared scaffolding for the Calendar's widget tests.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/repositories/calendar_repository.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every derived date is the same on every machine.
final Clock kCalendarClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kCalendarClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// Builds one event, defaulting to a transaction on today.
CalendarEvent event({
  DateKey date = kToday,
  CalendarEventType type = CalendarEventType.transaction,
  String refType = 'transaction',
  String refId = 'tx-1',
  String title = 'Groceries',
  CalendarSeverity baseSeverity = CalendarSeverity.info,
  int? amountMinor,
}) =>
    CalendarEvent(
      dateKey: date,
      type: type,
      refType: refType,
      refId: refId,
      title: title,
      baseSeverity: baseSeverity,
      amount: amountMinor == null ? null : Money(amountMinor, 'INR'),
    );

/// A [CalendarRepository] that answers from a list, or stalls, or fails.
///
/// The **repository** is the seam rather than the aggregator, deliberately: overriding
/// `calendarAggregatorProvider` would stub out ARCH_3 §6's per-type severity table, which is the one
/// piece of calendar logic worth testing through rather than around.
class FakeCalendarRepository implements CalendarRepository {
  /// Creates a repository over [events].
  FakeCalendarRepository({
    this.events = const <CalendarEvent>[],
    this.pending = false,
    this.error,
  });

  /// What every read returns.
  final List<CalendarEvent> events;

  /// When true, reads never complete — the loading branch.
  final bool pending;

  /// When set, reads fail with it — the error branch.
  final Object? error;

  /// Every range this repository was asked for, so a test can assert the query stayed bounded.
  final List<({DateKey from, DateKey to})> rangesRequested = [];

  @override
  Stream<List<CalendarEvent>> watchRange({required DateKey from, required DateKey to}) {
    rangesRequested.add((from: from, to: to));
    if (pending) return pendingStream<List<CalendarEvent>>();
    if (error != null) return Stream<List<CalendarEvent>>.error(error!);
    return Stream.value(
      events.where((e) => e.dateKey.isWithin(from, to)).toList(),
    );
  }

  @override
  Future<List<CalendarEvent>> forDay(DateKey dateKey) {
    if (pending) return pendingFuture<List<CalendarEvent>>();
    if (error != null) return Future<List<CalendarEvent>>.error(error!);
    return Future.value(events.where((e) => e.dateKey == dateKey).toList());
  }

  @override
  Future<Map<DateKey, int>> countsByDate({required DateKey from, required DateKey to}) {
    if (pending) return pendingFuture<Map<DateKey, int>>();
    if (error != null) return Future<Map<DateKey, int>>.error(error!);
    final counts = <DateKey, int>{};
    for (final e in events.where((e) => e.dateKey.isWithin(from, to))) {
      counts[e.dateKey] = (counts[e.dateKey] ?? 0) + 1;
    }
    return Future.value(counts);
  }
}

/// Overrides every provider the calendar reads, including the ones read during `build`.
///
/// `calendarTodayProvider` reads the clock and `focusedMonthProvider` reads that, so the clock alone
/// fixes which month opens. Without the repository override, `calendarAggregatorProvider` resolves
/// `calendarDaoProvider` and then `databaseProvider`, which throws by design (ARCH_6 P17).
List<Override> calendarOverrides(FakeCalendarRepository repository) => [
      clockProvider.overrideWithValue(kCalendarClock),
      calendarRepositoryProvider.overrideWithValue(repository),
      // The month feed awaits this before it subscribes, and unstubbed it resolves
      // `recurringRepositoryProvider` and then `databaseProvider`, which throws by design (L10). The
      // symptom is a screen that renders *nothing* — every finder misses and `rangesRequested` stays
      // empty, because the stream provider never reached its second line.
      //
      // The horizon provider is the seam rather than the repository beneath it: a test does not care how
      // occurrence rows come to exist, only that they do, and faking a whole `RecurringRepository` to say
      // "already done" would be a lot of surface for one integer. The dashboard harness overrides
      // `upcomingProvider` for the same reason rather than the four repositories under it.
      recurringHorizonProvider.overrideWith((ref) async => 0),
    ];

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpCalendar(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}
```

### `test/data/calendar_repository_impl_test.dart`

```dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/calendar_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/calendar_repository_impl.dart';
import 'package:alaya/domain/entities/calendar_event.dart';

void main() {
  late AlayaDatabase db;
  late CalendarRepositoryImpl repository;

  const anchor = DateKey(20260810);
  const before = DateKey(20260801);
  const after = DateKey(20260831);
  const outside = DateKey(20261115);
  const stamp = 1786000000000;

  setUp(() async {
    db = AlayaDatabase(NativeDatabase.memory());
    repository = CalendarRepositoryImpl(CalendarDao(db));

    // Foreign keys are enforced from `beforeOpen` (Phase 1C), so the referenced rows come first.
    await db.into(db.currencies).insert(
          CurrenciesCompanion.insert(
            code: 'INR',
            name: 'Indian Rupee',
            symbol: '₹',
            decimalDigits: 2,
            isEnabled: true,
            sortOrder: 0,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            id: 'ac-1',
            name: 'Everyday',
            normalizedName: 'everyday',
            kind: AccountKind.bank,
            currencyCode: 'INR',
            openingBalanceMinor: 0,
            openingBalanceDateKey: before,
            isArchived: false,
            includeInNetWorth: true,
            sortOrder: 0,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await db.into(db.units).insert(
          UnitsCompanion.insert(
            code: 'pc',
            category: UnitCategory.count,
            factorToBaseMilli: 1000,
            displayName: 'piece',
            isSystem: true,
            sortOrder: 0,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
  });

  tearDown(() => db.close());

  /// Seeds one row per `UNION ALL` arm, all on [anchor].
  Future<void> seedEveryArm({DateKey on = anchor}) async {
    await db.into(db.payees).insert(
          PayeesCompanion.insert(
            id: 'pay-1',
            name: 'Corner Shop',
            normalizedName: 'corner shop',
            kind: PayeeKind.merchant,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: 'tx-1',
            kind: TransactionKind.withdrawal,
            subtype: TransactionSubtype.grocery,
            occurredAt: stamp,
            dateKey: on,
            monthKey: on.monthKey,
            originalAmountMinor: 45900,
            originalCurrencyCode: 'INR',
            needsReview: false,
            createdAt: stamp,
            updatedAt: stamp,
            payeeId: const Value('pay-1'),
            // `transactions` carries a CHECK constraint the companion's required-field list does not
            // mention: a withdrawal must name `from_account_id` and leave `to_account_id` null. Reading
            // the generated companion tells you what is NOT NULL; it does not tell you what the table
            // considers a coherent row. Eleven tests failed on the same insert for want of this line.
            fromAccountId: const Value('ac-1'),
          ),
        );

    await db.into(db.items).insert(
          ItemsCompanion.insert(
            id: 'it-1',
            name: 'Yoghurt',
            normalizedName: 'yoghurt',
            unitCategory: UnitCategory.count,
            defaultDisplayUnitCode: 'pc',
            itemKind: ItemKind.food,
            isFavorite: false,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await db.into(db.inventoryBatches).insert(
          InventoryBatchesCompanion.insert(
            id: 'ba-1',
            itemId: 'it-1',
            initialQuantityMilli: 4000,
            remainingQuantityMilli: 4000,
            unitCodeAtPurchase: 'pc',
            purchasedDateKey: before,
            origin: BatchOrigin.purchase,
            createdAt: stamp,
            updatedAt: stamp,
            expiryDateKey: Value(on),
          ),
        );

    // One asset feeds two arms: warrantyEnd, and the asset-sourced half of serviceDue.
    await db.into(db.assets).insert(
          AssetsCompanion.insert(
            id: 'as-1',
            name: 'Boiler',
            normalizedName: 'boiler',
            type: AssetType.appliance,
            status: AssetStatus.active,
            createdAt: stamp,
            updatedAt: stamp,
            warrantyEndDateKey: Value(on),
            nextServiceDueDateKey: Value(on),
          ),
        );
    await db.into(db.serviceRecords).insert(
          ServiceRecordsCompanion.insert(
            id: 'sr-1',
            assetId: 'as-1',
            serviceDateKey: before,
            type: ServiceRecordType.service,
            createdAt: stamp,
            updatedAt: stamp,
            nextDueDateKey: Value(on),
          ),
        );

    await db.into(db.recurringTemplates).insert(
          RecurringTemplatesCompanion.insert(
            id: 'rt-1',
            name: 'Broadband',
            normalizedName: 'broadband',
            kind: RecurringKind.bill,
            direction: RecurringDirection.outflow,
            defaultAmountMinor: 89900,
            currencyCode: 'INR',
            intervalUnit: RecurringIntervalUnit.month,
            intervalCount: 1,
            startDateKey: before,
            nextDueDateKey: on,
            isPaused: false,
            autoRemind: false,
            remindDaysBefore: 0,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await db.into(db.recurringOccurrences).insert(
          RecurringOccurrencesCompanion.insert(
            id: 'ro-1',
            templateId: 'rt-1',
            dueDateKey: on,
            status: RecurringOccurrenceStatus.due,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );

    await db.into(db.shoppingLists).insert(
          ShoppingListsCompanion.insert(
            id: 'sl-1',
            name: 'Weekly shop',
            isDefault: false,
            isArchived: false,
            createdAt: stamp,
            updatedAt: stamp,
            targetDateKey: Value(on),
          ),
        );
  }

  /// Adds one row well outside the tested range, so a range assertion can fail.
  Future<void> seedOutside() => db.into(db.shoppingLists).insert(
        ShoppingListsCompanion.insert(
          id: 'sl-far',
          name: 'November',
          isDefault: false,
          isArchived: false,
          createdAt: stamp,
          updatedAt: stamp,
          targetDateKey: const Value(outside),
        ),
      );

  group('CalendarRepositoryImpl', () {
    // The point of the view, and the one thing no fake can prove: seven arms, six event types, and the
    // two serviceDue sources both arriving.
    test('every UNION arm reaches the feed', () async {
      await seedEveryArm();

      final events = await repository.forDay(anchor);

      expect(events, hasLength(7));
      expect(
        events.map((e) => e.type).toSet(),
        CalendarEventType.values.toSet(),
      );
      expect(
        events.where((e) => e.type == CalendarEventType.serviceDue).map((e) => e.refType).toSet(),
        {'asset', 'serviceRecord'},
      );
    });

    test('event_type and severity decode by enum name (Law L11)', () async {
      await seedEveryArm();

      final events = await repository.forDay(anchor);
      final byType = {for (final e in events) e.type: e};

      expect(byType[CalendarEventType.transaction]!.baseSeverity, CalendarSeverity.info);
      expect(byType[CalendarEventType.shoppingTarget]!.baseSeverity, CalendarSeverity.info);
      expect(byType[CalendarEventType.recurringDue]!.baseSeverity, CalendarSeverity.warning);
      expect(byType[CalendarEventType.batchExpiry]!.baseSeverity, CalendarSeverity.warning);
      expect(byType[CalendarEventType.warrantyEnd]!.baseSeverity, CalendarSeverity.warning);
    });

    test('an amount arrives as Money where the arm has one, and null where it does not', () async {
      await seedEveryArm();

      final events = await repository.forDay(anchor);
      final byType = {for (final e in events) e.type: e};

      expect(byType[CalendarEventType.transaction]!.amount, const Money(45900, 'INR'));
      expect(byType[CalendarEventType.recurringDue]!.amount, const Money(89900, 'INR'));
      // Expiries and warranties have no money attached, and a zero would read as free rather than absent.
      expect(byType[CalendarEventType.batchExpiry]!.amount, isNull);
      expect(byType[CalendarEventType.warrantyEnd]!.amount, isNull);
    });

    test('the transaction title falls back through the view COALESCE chain', () async {
      await seedEveryArm();

      final events = await repository.forDay(anchor);
      final transaction =
          events.firstWhere((e) => e.type == CalendarEventType.transaction);

      // The payee is joined, so its name wins over the note and the subtype.
      expect(transaction.title, 'Corner Shop');
      expect(transaction.title, isNotEmpty);
    });

    test('a range excludes what falls outside it', () async {
      await seedEveryArm();
      await seedOutside();

      final events = await repository.watchRange(from: before, to: after).first;

      expect(events, hasLength(7));
      expect(events.every((e) => e.dateKey == anchor), isTrue);
    });

    test('countsByDate groups per day, not per row', () async {
      await seedEveryArm();

      final counts = await repository.countsByDate(from: before, to: after);

      expect(counts, {anchor: 7});
    });

    test('an empty range is empty rather than an error', () async {
      final events = await repository.watchRange(from: before, to: after).first;

      expect(events, isEmpty);
      expect(await repository.countsByDate(from: before, to: after), isEmpty);
    });

    test('a soft-deleted transaction leaves the feed', () async {
      await seedEveryArm();
      await db.customStatement(
        'UPDATE transactions SET deleted_at = ? WHERE id = ?',
        [stamp, 'tx-1'],
      );

      final events = await repository.forDay(anchor);

      expect(events, hasLength(6));
      expect(events.any((e) => e.type == CalendarEventType.transaction), isFalse);
    });

    test('a fully consumed batch leaves the feed', () async {
      await seedEveryArm();
      await db.customStatement(
        'UPDATE inventory_batches SET remaining_quantity_milli = 0 WHERE id = ?',
        ['ba-1'],
      );

      final events = await repository.forDay(anchor);

      expect(events.any((e) => e.type == CalendarEventType.batchExpiry), isFalse);
    });

    test('a paid occurrence leaves the feed — only due rows are calendar entries', () async {
      await seedEveryArm();
      await db.customStatement(
        "UPDATE recurring_occurrences SET status = 'paid' WHERE id = ?",
        ['ro-1'],
      );

      final events = await repository.forDay(anchor);

      expect(events.any((e) => e.type == CalendarEventType.recurringDue), isFalse);
    });

    test('an archived shopping list leaves the feed', () async {
      await seedEveryArm();
      await db.customStatement(
        'UPDATE shopping_lists SET is_archived = 1 WHERE id = ?',
        ['sl-1'],
      );

      final events = await repository.forDay(anchor);

      expect(events.any((e) => e.type == CalendarEventType.shoppingTarget), isFalse);
    });

    test('a disposed asset takes both of its arms with it', () async {
      await seedEveryArm();
      await db.customStatement(
        "UPDATE assets SET status = 'disposed' WHERE id = ?",
        ['as-1'],
      );

      final events = await repository.forDay(anchor);

      expect(events.any((e) => e.type == CalendarEventType.warrantyEnd), isFalse);
      // The service record's own arm has no status filter, so it survives its asset's disposal.
      expect(
        events.where((e) => e.type == CalendarEventType.serviceDue).map((e) => e.refType),
        ['serviceRecord'],
      );
    });
  });

}
```

### `test/features/calendar/event_card_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/widgets/event_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

import '../../support/calendar_harness.dart';

void main() {
  group('EventCard', () {
    testWidgets('names the event type, so the glyph is never the only clue', (tester) async {
      await pumpCalendar(
        tester,
        EventCard(event: event(type: CalendarEventType.batchExpiry), onTap: () {}),
      );

      expect(find.text('Expiring'), findsOneWidget);
    });

    // The point of the card. A dot and a colour fail a colour-blind reader and fail in grayscale, so
    // anything above `info` says what it is in words (Law U9).
    testWidgets('a warning carries the severity in words, not only in colour', (tester) async {
      await pumpCalendar(
        tester,
        EventCard(
          event: event(
            type: CalendarEventType.warrantyEnd,
            baseSeverity: CalendarSeverity.warning,
          ),
          onTap: () {},
        ),
      );

      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.byType(StatusChip), findsOneWidget);
    });

    testWidgets('a danger says so too', (tester) async {
      await pumpCalendar(
        tester,
        EventCard(
          event: event(
            type: CalendarEventType.batchExpiry,
            baseSeverity: CalendarSeverity.danger,
          ),
          onTap: () {},
        ),
      );

      expect(find.text('Past its date'), findsOneWidget);
    });

    testWidgets('info carries no chip — there is nothing to warn about', (tester) async {
      await pumpCalendar(
        tester,
        EventCard(event: event(), onTap: () {}),
      );

      expect(find.byType(StatusChip), findsNothing);
      expect(find.text('Needs attention'), findsNothing);
      expect(find.text('Past its date'), findsNothing);
    });

    testWidgets('an amount renders through AmountText, never as a string', (tester) async {
      await pumpCalendar(
        tester,
        EventCard(event: event(amountMinor: 123456), onTap: () {}),
      );

      expect(find.byType(AmountText), findsOneWidget);
    });

    testWidgets('an entry with no amount shows none', (tester) async {
      await pumpCalendar(
        tester,
        EventCard(event: event(type: CalendarEventType.warrantyEnd), onTap: () {}),
      );

      expect(find.byType(AmountText), findsNothing);
    });

    testWidgets('a null onTap leaves the card inert rather than dead-tappable', (tester) async {
      await pumpCalendar(tester, EventCard(event: event(), onTap: null));

      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Groceries'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives 320dp at a doubled text scale', (tester) async {
      await pumpCalendar(
        tester,
        EventCard(
          event: event(
            title: 'A warranty with a name long enough to wrap twice over at this scale',
            type: CalendarEventType.warrantyEnd,
            baseSeverity: CalendarSeverity.warning,
            amountMinor: 98765432,
          ),
          onTap: () {},
        ),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
```

### `test/features/calendar/day_sheet_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/router/routes.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_event_list.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/calendar/presentation/widgets/event_card.dart';
import 'package:alaya/shared/widgets/section_header.dart';

import '../../support/calendar_harness.dart';

void main() {
  // `calendarEventRoute` and the grouped list moved to `calendar_event_list.dart` when the screen
  // started rendering the same list inline. They are exercised here because the sheet is still their
  // only widget host; if a list-specific suite ever earns its own file, these move with it.
  group('calendarEventRoute', () {
    test('deep-links the three types whose ref_id addresses a record', () {
      expect(
        calendarEventRoute(event(refType: 'transaction', refId: 'tx-9')),
        Routes.transactionDetail('tx-9'),
      );
      expect(
        calendarEventRoute(event(refType: 'asset', refId: 'as-2')),
        Routes.assetDetail('as-2'),
      );
      expect(
        calendarEventRoute(event(refType: 'shoppingList', refId: 'sl-3')),
        Routes.shoppingList('sl-3'),
      );
    });

    // Not an oversight and not a fallback chosen for convenience: `v_calendar_events` carries no parent
    // id, and `batchEdit` needs an item, `serviceEdit` needs an asset, and a recurring occurrence has no
    // route at all. Asserted so the day it gains one, this test is what says so.
    test('falls back to the owning module where the feed carries no parent id', () {
      expect(calendarEventRoute(event(refType: 'inventoryBatch')), Routes.inventory);
      expect(calendarEventRoute(event(refType: 'serviceRecord')), Routes.services);
      expect(calendarEventRoute(event(refType: 'recurringOccurrence')), Routes.recurring);
    });

    test('an unknown ref_type resolves to nothing rather than to somewhere wrong', () {
      expect(calendarEventRoute(event(refType: 'somethingNewInPhase9')), isNull);
    });
  });

  group('DaySheet', () {
    testWidgets('loading says so', (tester) async {
      final repo = FakeCalendarRepository(pending: true);
      await pumpCalendar(
        tester,
        const DaySheet(dateKey: kToday),
        overrides: calendarOverrides(repo),
      );

      expect(find.text('Loading this day…'), findsOneWidget);
    });

    testWidgets('empty is an answer, not a blank', (tester) async {
      await pumpCalendar(
        tester,
        const DaySheet(dateKey: kToday),
        overrides: calendarOverrides(FakeCalendarRepository()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing on this day'), findsOneWidget);
    });

    testWidgets('a failed read shows its reason and offers a retry', (tester) async {
      await pumpCalendar(
        tester,
        const DaySheet(dateKey: kToday),
        overrides: calendarOverrides(FakeCalendarRepository(error: 'view unavailable')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load this day'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('populated groups by type, one heading each', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(refId: 'tx-1', title: 'Groceries'),
          event(refId: 'tx-2', title: 'Fuel'),
          event(
            type: CalendarEventType.batchExpiry,
            refType: 'inventoryBatch',
            refId: 'ba-1',
            title: 'Milk',
          ),
        ],
      );
      await pumpCalendar(
        tester,
        const DaySheet(dateKey: kToday),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EventCard), findsNWidgets(3));

      // Read the headings off the widgets rather than searching for their text. `SectionHeader`
      // upper-cases for display and keeps the original in `semanticsLabel`, so `find.text('Transaction')`
      // tests SectionHeader's presentation choice instead of this sheet's grouping. Order matters too:
      // enum declaration order, so a reader scanning twice finds the same thing in the same place.
      final headings = tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((h) => h.label)
          .toList();
      expect(headings, ['Transaction', 'Expiring']);
    });

    // The aggregator escalates, not the view and not the card: a batch three days out is a warning by
    // ARCH_3 §6, and the view handed it the static `warning` baseline with no notion of today.
    testWidgets('severity is resolved through the aggregator, against the fixed clock',
        (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(
            date: kToday.addDays(-1),
            type: CalendarEventType.batchExpiry,
            refType: 'inventoryBatch',
            refId: 'ba-past',
            title: 'Yoghurt',
            baseSeverity: CalendarSeverity.warning,
          ),
        ],
      );
      await pumpCalendar(
        tester,
        DaySheet(dateKey: kToday.addDays(-1)),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      // Past its date, and `batchExpiry` is the only type §6 lets reach danger.
      expect(find.text('Past its date'), findsOneWidget);
    });

    testWidgets('survives 320dp at a doubled text scale', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(title: 'A payee with a name long enough to wrap at a doubled scale'),
          event(
            type: CalendarEventType.serviceDue,
            refType: 'asset',
            refId: 'as-1',
            title: 'The boiler in the upstairs cupboard',
            baseSeverity: CalendarSeverity.warning,
          ),
        ],
      );
      await pumpCalendar(
        tester,
        const DaySheet(dateKey: kToday),
        overrides: calendarOverrides(repo),
        textScale: 2,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
```

### `test/features/calendar/calendar_screen_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_month_grid.dart';

import '../../support/calendar_harness.dart';

void main() {
  group('CalendarScreen', () {
    testWidgets('loading: the grid is there before the feed is', (tester) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository(pending: true)),
      );

      // A month of empty cells is still a usable month, so loading reports beneath the grid rather
      // than in place of it.
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
      expect(find.text('Loading this month…'), findsOneWidget);
    });

    testWidgets('empty: the selected day says so, and the grid still stands', (tester) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository()),
      );
      await tester.pumpAndSettle();

      // There is no month-level empty state any longer. "Nothing this month" was a fact about the
      // month; the day section answers the question the reader actually asked, and an empty month is
      // simply an empty day plus a grid with no dots.
      expect(find.text('Nothing on this day'), findsOneWidget);
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
    });

    testWidgets('error: the reason shows and the grid survives it', (tester) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository(error: 'view unavailable')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load the calendar'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
    });

    testWidgets('populated: the section shows what is on the selected day', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(refId: 'tx-1', title: 'Groceries'),
          event(refId: 'tx-2', title: 'Fuel'),
          event(date: kToday.addDays(3), refId: 'tx-3', title: 'Rent'),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      // The entries themselves, not a count of days. Selection starts on today, so both of today's
      // entries show and the one three days out does not — a count could not tell the reader either.
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Fuel'), findsOneWidget);
      expect(find.text('Rent'), findsNothing);
    });

    testWidgets('the section names the day it is showing', (tester) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository(events: [event()])),
      );
      await tester.pumpAndSettle();

      expect(find.text('On this day'), findsOneWidget);
      expect(find.text('August 1, 2026'), findsOneWidget);
    });

    testWidgets('tapping a day moves the section to it', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(refId: 'tx-1', title: 'Groceries'),
          event(date: const DateKey(20260812), refId: 'tx-2', title: 'Broadband'),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsOneWidget);

      // A two-digit day, because single digits appear twice in a month grid — once for this month and
      // once as an adjacent month's outside cell.
      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();

      expect(find.text('Broadband'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
    });

    // What the semantics tree actually contains, verified by dumping it rather than guessed at.
    // `table_calendar` owns each cell's node and labels it with the full date, excluding anything its
    // builders add — so the grid speaks dates, and the section below speaks contents. Both halves are
    // asserted here because either one silently changing would leave a screen-reader user with a grid
    // they can navigate and nothing to navigate towards.
    testWidgets('the grid speaks dates and the section speaks contents', (tester) async {
      // Disposed inline, not via `addTearDown`. `_verifySemanticsHandlesWereDisposed` runs inside
      // `_runTestBody`, before tear-downs execute, so a handle released in one is still open when the
      // check looks — the test then fails having asserted everything it meant to.
      final handle = tester.ensureSemantics();

      final repo = FakeCalendarRepository(
        events: [
          event(refId: 'tx-1', title: 'Groceries'),
          event(refId: 'tx-2', title: 'Fuel'),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      // The package's own cell label. If a future version drops it, the grid goes mute and this fails.
      expect(find.bySemanticsLabel('Saturday, August 1, 2026'), findsOneWidget);

      // And the day's contents, which is the part that carries what the dots only hint at.
      expect(find.bySemanticsLabel('On this day'), findsOneWidget);
      expect(find.bySemanticsLabel('August 1, 2026'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Fuel'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('a range shows every entry across the span', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(date: const DateKey(20260810), refId: 'tx-1', title: 'Groceries'),
          event(date: const DateKey(20260812), refId: 'tx-2', title: 'Broadband'),
          event(date: const DateKey(20260820), refId: 'tx-3', title: 'Outside it'),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      // Long-press starts the range on the day pressed — there is no mode button and no intermediate
      // "pick a start" step, because the gesture already named one.
      await tester.longPress(find.text('10'));
      await tester.pumpAndSettle();
      expect(find.text('From August 10, 2026 — tap another day to finish.'), findsOneWidget);

      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();

      expect(find.text('3 days'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Broadband'), findsOneWidget);
      expect(find.text('Outside it'), findsNothing);
    });

    testWidgets('a range picked backwards reads the same as one picked forwards', (tester) async {
      final repo = FakeCalendarRepository(
        events: [event(date: const DateKey(20260812), refId: 'tx-1', title: 'Broadband')],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();

      expect(find.text('6 days'), findsOneWidget);
      expect(find.text('Broadband'), findsOneWidget);
    });

    testWidgets('opens on the clock\'s month, never on the wall clock', (tester) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository()),
      );
      await tester.pumpAndSettle();

      expect(find.text('August 2026'), findsOneWidget);
    });

    testWidgets('the chevrons move a month at a time', (tester) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous month'));
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('July 2026'), findsOneWidget);
    });

    // The whole reason `CalendarRepository.watchRange` is the only read: unbounded, the view scans seven
    // tables. A regression here is silent — the screen looks identical and the query stops using indexes.
    // December to January, in both directions. `DateKey.fromYmd` throws on month 13 and month 0, so
    // this boundary was a crash rather than a wrong answer — paging forward from December 2026 died and
    // the month could only be reached by swiping.
    testWidgets('paging crosses the year boundary in both directions', (tester) async {
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(FakeCalendarRepository()),
      );
      await tester.pumpAndSettle();

      // August 2026 forward to January 2027.
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byTooltip('Next month'));
        await tester.pumpAndSettle();
      }
      expect(find.text('January 2027'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // And back over the same boundary.
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('December 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every read is bounded to the month plus its overscan', (tester) async {
      final repo = FakeCalendarRepository();
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      expect(repo.rangesRequested, isNotEmpty);
      for (final range in repo.rangesRequested) {
        expect(range.from, DateKey(20260801).addDays(-gridPadDaysForTest));
        expect(range.to, DateKey(20260901).addDays(gridPadDaysForTest - 1));
        expect(range.to.diffDays(range.from), lessThan(45));
      }
    });

    testWidgets('a deep link opens that day\'s month and its sheet', (tester) async {
      final repo = FakeCalendarRepository(
        events: [event(date: const DateKey(20261115), refId: 'tx-nov', title: 'Fireworks')],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(initialDay: DateKey(20261115)),
        overrides: calendarOverrides(repo),
      );
      await tester.pumpAndSettle();

      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('Fireworks'), findsOneWidget);
    });

    // U26. `TableCalendar` takes a fixed `rowHeight`, and a grid of text cells with a fixed row height
    // is the exact shape that overflowed twenty-six tests in Phase 6F.
    testWidgets('survives 320dp at a doubled text scale', (tester) async {
      final repo = FakeCalendarRepository(
        events: [
          event(refId: 'tx-1'),
          event(
            date: kToday.addDays(2),
            type: CalendarEventType.batchExpiry,
            refType: 'inventoryBatch',
            refId: 'ba-1',
            baseSeverity: CalendarSeverity.warning,
          ),
        ],
      );
      await pumpCalendar(
        tester,
        const CalendarScreen(),
        overrides: calendarOverrides(repo),
        textScale: 2,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(CalendarMonthGrid), findsOneWidget);
    });
  });
}

/// Mirrors `gridPadDays`, so a change to the overscan has to be made deliberately in two places.
const int gridPadDaysForTest = 6;
```

### `test/shared/layout_overflow_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/expense/presentation/sheets/delete_transaction_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/freeze_conversion_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_filter_sheet.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/shopping/presentation/sheets/entry_editor_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/generate_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/list_manager_sheet.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_expandable_fab.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/loading_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/service/presentation/sheets/dispose_sheet.dart';
import 'package:alaya/features/service/presentation/widgets/contact_action.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/shared/widgets/module_tile.dart';

import '../support/expense_harness.dart';
import '../support/fake_settings_repository.dart';
// Prefixed: `kToday` and `kNarrowPhone` are declared by every harness in this project, and this is
// the only file that imports two of them.
import '../support/calendar_harness.dart' as cal;

/// The only thing in this project that catches a layout overflow (ARCH_3 §8.3, ARCH_5 U2).
///
/// **Every sheet and every full-height state belongs here.** These defects are invisible to
/// `dart analyze`, to a file-by-file scan and to looking at the screen, because the missing
/// affordance is always an *ancestor*: the widget under review is locally correct and the parent
/// that should have given it room, or a way to scroll, is the one at fault.
///
/// They are also invisible to an ordinary widget test. A `RenderFlex` overflow reports through
/// `FlutterError.onError` rather than throwing at the site, so a test only fails on one if something
/// asks — which is exactly how an overflow hides in a suite that otherwise looks green. Every case
/// below asks, via `tester.takeException()`.
void main() {
  /// Roughly what a software keyboard takes from a phone in portrait.
  const double keyboardInset = 320;

  /// Roughly the room a list area has left on a small phone with a keyboard up.
  const Size squeezed = Size(320, 140);

  Widget host(
    Widget child, {
    double bottomInset = 0,
    double textScale = 1,
    List<Override> overrides = const [],
  }) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AlayaTheme.light(AlayaPresets.activePreset),
          // Every expense sheet reads `AlayaStrings.of(context)`, which unwraps a null without a
          // delegate installed. The Phase 5 groups pass literal strings, so this file went without
          // one until real screens arrived — and then failed as a null-check rather than as a
          // missing translation, which is why it read like five separate defects.
          localizationsDelegates: const [
            AlayaStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AlayaStrings.supportedLocales,
          // Inside the app rather than above it. `WidgetsApp` re-establishes `MediaQuery` from the
          // view, so an outer one is discarded before anything under test can read it — and a test
          // that believes it has simulated a keyboard when it has not is worse than no test.
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: EdgeInsets.only(bottom: bottomInset),
              textScaler: TextScaler.linear(textScale),
            ),
            child: inner!,
          ),
          home: Scaffold(body: child),
        ),
      );

  /// Content taller than the room a keyboard leaves, so the assertions are about the scaffold rather
  /// than about how long a particular string happens to be.
  Widget tallContent() => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [SizedBox(width: 200, height: 400)],
      );

  group('AlayaBottomSheet', () {
    testWidgets('scrolls rather than overflowing with a keyboard up', (tester) async {
      await tester.pumpWidget(
        host(AlayaBottomSheet(child: tallContent()), bottomInset: keyboardInset),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('still fits when there is no keyboard', (tester) async {
      await tester.pumpWidget(host(AlayaBottomSheet(child: tallContent())));
      expect(tester.takeException(), isNull);
    });

    // The bug, reproduced deliberately. `Padding(bottom: viewInsets)` around a `MainAxisSize.min`
    // Column is correct in each half and broken together: the padding shrinks the space and the
    // Column has no way to give up the room it already took. **If this ever stops overflowing, the
    // guard above has stopped testing anything** — and the reason AlayaBottomSheet exists has
    // quietly gone away.
    testWidgets('the un-scaffolded shape it replaces still overflows', (tester) async {
      await tester.pumpWidget(
        host(
          Padding(
            padding: const EdgeInsets.only(bottom: keyboardInset),
            child: tallContent(),
          ),
        ),
      );
      expect(tester.takeException(), isA<FlutterError>());
    });
  });

  group('ConfirmSheet', () {
    testWidgets('survives a keyboard and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => ConfirmSheet.show(
                context,
                title: 'Delete this transaction?',
                body: 'You can undo this for the next few seconds.',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                destructive: true,
              ),
              child: const Text('open'),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('AlayaFormScaffold', () {
    Widget form({bool submitting = false}) => AlayaFormScaffold(
          primaryLabel: 'Save expense',
          onPrimary: () {},
          secondaryLabel: 'Cancel',
          onSecondary: () {},
          isDirty: true,
          isSubmitting: submitting,
          discardTitle: 'Discard your changes?',
          discardBody: 'What you have typed will not be saved.',
          discardConfirmLabel: 'Discard',
          discardCancelLabel: 'Keep editing',
          child: const Column(
            children: [SizedBox(height: 300), TextField(), SizedBox(height: 300)],
          ),
        );

    testWidgets('body scrolls and the footer stays above the keyboard', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset));
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a doubled text scale with a keyboard up', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset, textScale: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the submitting footer does not grow the row past its box', (tester) async {
      await tester.pumpWidget(host(form(submitting: true), textScale: 2));
      expect(tester.takeException(), isNull);
    });
  });

  // Every sheet Phase 6A adds, at a keyboard inset and a doubled text scale — the two conditions
  // under which each of them is first used and least likely to have been looked at.
  group('expense sheets', () {
    final expenseOverrides = <Override>[
      homeCurrencyCodeProvider.overrideWith((ref) => 'INR'),
      homeDecimalDigitsProvider.overrideWith((ref) => 2),
      selectableAccountsProvider.overrideWith((ref) => Stream.value(const [kAccount])),
      quickAddTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      accountsByIdProvider
          .overrideWith((ref) => Stream.value(<String, Account>{kAccount.id: kAccount})),
      lineEditorItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      enabledCurrenciesProvider.overrideWith(
        (ref) => Stream.value(const [
          Currency(
            code: 'USD',
            name: 'US Dollar',
            symbol: r'$',
            decimalDigits: 2,
            isEnabled: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: expenseOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets('QuickAddSheet', (tester) => pumpSheet(tester, const QuickAddSheet()));

    testWidgets(
      'TransactionFilterSheet',
      (tester) => pumpSheet(tester, const TransactionFilterSheet()),
    );

    testWidgets(
      'LineItemEditor',
      (tester) => pumpSheet(
        tester,
        const LineItemEditor(
          currencyCode: 'INR',
          decimalDigits: 2,
          defaultDestination: TransactionLineDestination.inventory,
        ),
      ),
    );

    testWidgets(
      'DeleteTransactionSheet',
      (tester) => pumpSheet(tester, const DeleteTransactionSheet()),
    );

    testWidgets(
      'FreezeConversionSheet',
      (tester) => pumpSheet(tester, const FreezeConversionSheet(excludeCode: 'INR')),
    );
  });

  // Phase 6B's sheet, at a keyboard inset and a doubled text scale — the two conditions under
  // which it is first used and least likely to have been looked at (U2).
  group('inventory sheets', () {
    final inventoryOverrides = <Override>[
      consumeFefoProvider('item-1').overrideWith((ref) => Stream.value(const <Batch>[])),
      unitsInCategoryProvider(UnitCategory.weight).overrideWith(
        (ref) => Stream.value(const [
          Unit(
            code: 'kg',
            category: UnitCategory.weight,
            factorToBaseMilli: 1000000,
            displayName: 'kilogram',
            isSystem: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    testWidgets('ConsumeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: ConsumeSheet(
              itemId: 'item-1',
              unitCode: 'kg',
              category: UnitCategory.weight,
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: inventoryOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6C's three sheets, at a keyboard inset and a doubled text scale — the two conditions under
  // which each is first used and least likely to have been looked at (U2).
  group('shopping sheets', () {
    final shoppingOverrides = <Override>[
      entryItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      entryTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      entryCurrencyProvider.overrideWith((ref) async => 'INR'),
      entryDecimalDigitsProvider.overrideWith((ref) async => 2),
      entriesProvider('list-1').overrideWith((ref) => Stream.value(const <ShoppingEntry>[])),
      shoppingItemsByIdProvider.overrideWith((ref) => Stream.value(const <String, Item>{})),
      allListsProvider.overrideWith((ref) => Stream.value(const <ShoppingList>[])),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: shoppingOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets(
      'EntryEditorSheet',
      (tester) => pumpSheet(tester, const EntryEditorSheet(listId: 'list-1')),
    );

    testWidgets(
      'GenerateSheet',
      (tester) => pumpSheet(tester, const GenerateSheet(listId: 'list-1')),
    );

    testWidgets(
      'ListManagerSheet',
      (tester) => pumpSheet(tester, const ListManagerSheet()),
    );
  });

  // Phase 6D's pay sheet, at a keyboard inset and a doubled text scale — an amount field, a date
  // field, an account dropdown and a two-line note, all growing at once.
  group('recurring sheets', () {
    final recurringOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      payAccountsProvider.overrideWith((ref) => Stream.value(const <Account>[])),
      payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
    ];

    testWidgets('PaySheet', (tester) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(
            child: PaySheet(
              occurrenceId: 'occ-1',
              template: RecurringTemplate(
                id: 'tpl-1',
                name: 'A rent template with a name long enough to wrap at a doubled scale',
                normalizedName: 'rent',
                kind: RecurringKind.rent,
                direction: RecurringDirection.outflow,
                defaultAmount: const Money(120000, 'INR'),
                intervalUnit: RecurringIntervalUnit.month,
                intervalCount: 1,
                startDateKey: const DateKey(20260131),
                nextDueDateKey: const DateKey(20260831),
                isPaused: false,
                autoRemind: true,
                remindDaysBefore: 3,
                anchorDayOfMonth: 31,
              ),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: recurringOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6D adds, with a clamp note on every row.
  group('FrequencyPreview at a doubled text scale', () {
    testWidgets('three dates, two of them clamped', (tester) async {
      await tester.pumpWidget(
        host(
          const FrequencyPreview(
            dates: [
              PreviewedDate(dateKey: DateKey(20260131)),
              PreviewedDate(dateKey: DateKey(20260228), clamped: true),
              PreviewedDate(dateKey: DateKey(20260331)),
            ],
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6E's dispose sheet: seven choice chips, a date field, an optional amount and a note, all
  // growing at once under a keyboard inset.
  group('service sheets', () {
    final serviceOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('DisposeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: DisposeSheet(assetId: 'asset-1', currencyCode: 'INR'),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: serviceOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The contact block: a name, a number and a call button, none of them flexible.
  group('ContactAction at a doubled text scale', () {
    testWidgets('a long name beside a long number', (tester) async {
      await tester.pumpWidget(
        host(
          const ContactAction(
            phone: '+91 98765 43210',
            name: 'A service centre with a name long enough to wrap',
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6F's dashboard sections. Each is a card whose figures, chips and labels all grow at once, and
  // the funds header carries the only display-sized amount in the app.
  group('dashboard sections', () {
    final dashOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      // InsightCard's notifier restores its side from `app_settings` on the first frame, which
      // resolves `databaseProvider` unless this is here — the failure reads as a database bug in a
      // test that never mentions one (ARCH_6 P6).
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      dashboardCurrencyProvider.overrideWith((ref) async => 'INR'),
      dashboardDigitsProvider.overrideWith((ref) async => 2),
      totalFundsProvider.overrideWith(
        (ref) async => const NetWorth(
          total: Money(98765432, 'INR'),
          unconvertedCount: 3,
          isApproximate: true,
        ),
      ),
      upcomingProvider.overrideWith((ref) async => const <UpcomingEntry>[]),
    ];

    testWidgets('FundsHeader with both chips at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const FundsHeader(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('InsightCard with its switch at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const InsightCard(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6F adds. Two lines of text and a glyph inside a fixed aspect ratio is
  // exactly the shape that overflows when the text doubles and the box does not.
  group('ModuleTile at a doubled text scale', () {
    testWidgets('a long label beside a long count', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 160,
            height: 108,
            child: ModuleTile(
              label: 'Recurring commitments',
              icon: Icons.event_repeat,
              detail: '17 need attention before the end of the month',
              onTap: () {},
            ),
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 7A. Both shapes here are the ones that have already cost this project rounds: a sheet whose
  // content outgrows the viewport, and a grid of text cells whose row height does not move with the text.
  // Zero width, which is not a hypothetical: Android reports it on the first frame of every launch
  // ("D/FlutterRenderer: Width is zero. 0,0") and the FAB's slot subtracted padding from it, producing a
  // negative width and a red screen on startup. Every widget harness sets a real viewport before pumping,
  // which is exactly why nothing here caught it — so the degenerate viewport is now stated outright.
  group('degenerate viewports', () {
    testWidgets('the expandable FAB survives a zero-width first frame', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size.zero),
            child: Scaffold(
              floatingActionButton: AlayaExpandableFab(
                openLabel: 'Add',
                closeLabel: 'Close',
                actions: [
                  FabAction(label: 'One', icon: Icons.add, onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('calendar', () {
    List<Override> calOverrides({List<CalendarEvent> events = const []}) =>
        cal.calendarOverrides(cal.FakeCalendarRepository(events: events));

    final busyDay = <CalendarEvent>[
      cal.event(title: 'A payee with a name long enough to wrap at a doubled scale', amountMinor: 98765432),
      cal.event(
        type: CalendarEventType.serviceDue,
        refType: 'asset',
        refId: 'as-1',
        title: 'The boiler in the upstairs cupboard',
        baseSeverity: CalendarSeverity.warning,
      ),
      cal.event(
        type: CalendarEventType.batchExpiry,
        refType: 'inventoryBatch',
        refId: 'ba-1',
        title: 'Yoghurt, the large tub',
        baseSeverity: CalendarSeverity.warning,
      ),
    ];

    testWidgets('DaySheet with three grouped entries at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('DaySheet with a keyboard up as well', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // U26: `TableCalendar` takes a fixed `rowHeight`, so the grid computes one from the text scaler. If
    // that computation is ever replaced by a constant, this is the test that says so.
    testWidgets('the month grid at a doubled scale on the narrowest phone', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the month grid at a tripled scale, which is past what U15 asks for',
        (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 3, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // The range header prints two formatted dates and a dash, which is the longest single string this
    // screen can produce — and it appears only in a mode the other cases never enter.
    testWidgets('the range header at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('22'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // The screen's own composition, which the shared full-height group cannot reach: six measured rows
    // plus a header are taller than a squeezed list area on their own, so the grid and the state beneath
    // it have to share a scroll rather than compete for a fixed box.
    for (final scale in [1.0, 2.0]) {
      testWidgets('the whole screen in a squeezed viewport at ${scale}x', (tester) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: scale,
            overrides: calOverrides(events: busyDay),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // Each of the three states in turn, in the same squeezed box. Loading and error sit in the sliver
    // that fills the remainder, and that remainder is negative here.
    testWidgets('loading, empty and error all survive the squeezed box', (tester) async {
      for (final repo in [
        cal.FakeCalendarRepository(pending: true),
        cal.FakeCalendarRepository(),
        cal.FakeCalendarRepository(error: 'view unavailable'),
      ]) {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: 2,
            overrides: cal.calendarOverrides(repo),
          ),
        );
        // `pump`, not `pumpAndSettle`: the loading case holds a `CircularProgressIndicator`, which
        // animates forever, so `pumpAndSettle` times out rather than settling. Two frames is enough to
        // resolve the completed futures in the other two cases.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('full-height states in a squeezed viewport', () {
    Widget inSqueezedBox(Widget child) => host(
          Center(
            child: SizedBox(width: squeezed.width, height: squeezed.height, child: child),
          ),
        );

    testWidgets('EmptyState with an icon, body and action', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          EmptyState(
            title: 'No transactions yet',
            body: 'Add your first expense and it will appear here.',
            icon: Icons.receipt_long_outlined,
            actionLabel: 'Add expense',
            onAction: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ErrorState with a retry — the tallest of the three', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          ErrorState(
            title: 'That did not work',
            body: 'Something went wrong on our side. Try again.',
            retryLabel: 'Try again',
            onRetry: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoadingState', (tester) async {
      await tester.pumpWidget(inSqueezedBox(const LoadingState(label: 'Loading')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('AlayaListSkeleton clips rather than overflowing', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(const AlayaListSkeleton(label: 'Loading transactions')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmptyState at a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: EmptyState(
                title: 'No transactions yet',
                body: 'Add your first expense and it will appear here.',
                icon: Icons.receipt_long_outlined,
                actionLabel: 'Add expense',
                onAction: () {},
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    // The states are also the shape the Theme Lab renders inside a half-width pane, which is where
    // the 150px `SizedBox` around an EmptyState used to overflow by roughly 58px.
    testWidgets('EmptyState in a half-width pane', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          const SizedBox(
            width: 134,
            child: EmptyState(title: 'No matches', body: 'Try a shorter search.'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6A's line-items page: a full-height screen whose summary row, list rows and footer all
  // grow under text scale at once. Squeezed and doubled, which is the pair U21 exists for.
  group('the line items page', () {
    final editorOverrides = <Override>[
      transactionEditorProvider.overrideWith(
        () => _FixedEditor(
          AsyncValue.data(
            TransactionEditorState(
              currencyCode: 'INR',
              dateKey: const DateKey(20260801),
              amount: const Money(20000, 'INR'),
              lines: [
                TransactionLine(
                  id: 'l1',
                  transactionId: '',
                  lineNo: 1,
                  description: 'A description long enough to need two lines at a doubled scale',
                  destination: TransactionLineDestination.inventory,
                  quantity: const Qty(500000, UnitCategory.weight),
                  lineAmount: const Money(4000, 'INR'),
                ),
              ],
            ),
          ),
        ),
      ),
      homeDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('populated at 320dp and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(const LineItemsScreen(), textScale: 2, overrides: editorOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('kit rows at a doubled text scale', () {
    testWidgets('KeyValueRow wraps a long value instead of overflowing', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            child: KeyValueRow(
              label: 'Payment method',
              value: 'Bank transfer from HDFC Savings ending 4417',
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('FilterChipBar wraps rather than clipping a row of chips', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: FilterChipBar(
              clearAllLabel: 'Clear all',
              onClearAll: () {},
              filters: [
                ActiveFilter(label: 'Account: HDFC Savings', onRemove: () {}),
                ActiveFilter(label: 'Tag: Groceries', onRemove: () {}),
                ActiveFilter(label: 'Jan 2026 – Aug 2026', onRemove: () {}),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('StatusChip ellipsises a long label in a narrow box', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 96,
            child: StatusChip(label: 'Needs details', tone: StatusTone.info),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// A transaction editor reporting a fixed state, so a layout can be pumped without a database.
class _FixedEditor extends TransactionEditorNotifier {
  _FixedEditor(this._value);

  final AsyncValue<TransactionEditorState> _value;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _value;
}
```

---

## COVERAGE — ARCH_5 §7 rows closed

| Row | Status |
|---|---|
| **Implements `CalendarRepository`** | **Closed.** Impl over `v_calendar_events`, a DAO, and the two missing providers |
| `v_calendar_events` surfaces — `transaction` | **Closed.** Deep-links to `Routes.transactionDetail` |
| `v_calendar_events` surfaces — `recurringDue` | **Closed** for display; navigates to `/recurring` |
| `v_calendar_events` surfaces — `batchExpiry` | **Closed** for display; navigates to `/inventory` |
| `v_calendar_events` surfaces — `warrantyEnd` | **Closed.** Deep-links to `Routes.assetDetail` |
| `v_calendar_events` surfaces — `serviceDue` | **Closed.** Asset-sourced rows deep-link; record-sourced rows navigate to `/services` |
| `v_calendar_events` surfaces — `shoppingTarget` | **Closed.** Deep-links to `Routes.shoppingList` |

Archetypes: CalendarMonth is **F**, DaySheet is **A**. Both implement loading, empty, error and populated.

### Three types cannot deep-link, and the cause is the view

`v_calendar_events` emits `ref_type` and `ref_id` but not the **parent** id that three detail routes
require: `batchEdit(itemId, batchId)` wants the item, `serviceEdit(assetId, recordId)` wants the asset, and
a recurring **occurrence** has no route at all — only `recurringDetail(templateId)` exists. Those three land
on the owning module list, which is honest behaviour rather than a dead tap, but it is not "tappable
through to its record" as the task specifies.

Closing it means a `parent_ref_id` column on the view plus one field on `CalendarEvent` — a Phase 2A change.
7B will want the same column for the same reason, so it is worth doing once.

### Deferred, with reasons

| Item | Why |
|---|---|
| `ARCH_5 §9.1` / `§9.2` sign-off | Both require a green run. `flutter pub add table_calendar && flutter test` is the gate; `calendar_month_grid.dart`'s `TableCalendar` parameter list and `CalendarBuilders` signatures are the two things most likely to fail first |
| Index-use proof | Every read is bounded and `countsByDate` groups in SQL, but nothing proves the planner picks `idx_batch_expiry` or `idx_occ_due`. That needs `EXPLAIN QUERY PLAN` against a table large enough for the planner to care — a performance test, and 8B's work |
| `countsByDate` unused by this phase | The grid needs severity-coloured dots, and severity is per-type and post-escalation, so only `watchDays` can supply them. Not dead code — it is the cheaper read for ranges wider than a month, which 7B wants — but it closes no row here |

### Laws applied beyond the U1–U20 the task named

ARCH_5 §1 as attached declares through **U25**, and the post-6F amendments add U26–U28. Two bore directly
on this phase and were applied: **U26** — `calendar_month_grid.dart` measures `rowHeight` from
`MediaQuery.textScalerOf` rather than taking `TableCalendar`'s fixed default, because a grid of text cells
with a constant row height is the exact shape that failed twenty-six tests in Phase 6F. **U27** — the day
route is a sub-route of `/calendar` rather than a sibling detail route, so a day keeps the drawer shell and
the month stays behind it.

§0 of ARCH_5 and the PROMPTS preamble both still say "U1–U20". That mismatch is now three phases old.
