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
final uidGeneratorProvider = Provider<UidGenerator>(
  (ref) => const Uuid7Generator(),
);

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
final secureKeyValueStoreProvider = Provider<SecureKeyValueStore>(
  (ref) => const FlutterSecureKeyValueStore(),
);

// ── DAOs ────────────────────────────────────────────────────────────────────────────────
//
// One per aggregate, each a thin `DatabaseAccessor` over the single connection. They are separate
// providers rather than getters on the database because `@DriftDatabase` here declares no `daos:`
// list, so there are no generated accessors to reach for.

/// The accounts DAO.
final accountDaoProvider = Provider<AccountDao>(
  (ref) => AccountDao(ref.watch(databaseProvider)),
);

/// The transactions DAO.
final transactionDaoProvider = Provider<TransactionDao>(
  (ref) => TransactionDao(ref.watch(databaseProvider)),
);

/// The transaction-lines DAO.
final transactionLineDaoProvider = Provider<TransactionLineDao>(
  (ref) => TransactionLineDao(ref.watch(databaseProvider)),
);

/// The payment-methods DAO.
final paymentMethodDaoProvider = Provider<PaymentMethodDao>(
  (ref) => PaymentMethodDao(ref.watch(databaseProvider)),
);

/// The payees DAO.
final payeeDaoProvider = Provider<PayeeDao>(
  (ref) => PayeeDao(ref.watch(databaseProvider)),
);

/// The tags DAO.
final tagDaoProvider = Provider<TagDao>(
  (ref) => TagDao(ref.watch(databaseProvider)),
);

/// The currencies and rates DAO.
final currencyDaoProvider = Provider<CurrencyDao>(
  (ref) => CurrencyDao(ref.watch(databaseProvider)),
);

/// The units DAO.
final unitDaoProvider = Provider<UnitDao>(
  (ref) => UnitDao(ref.watch(databaseProvider)),
);

/// The settings DAO.
final settingsDaoProvider = Provider<SettingsDao>(
  (ref) => SettingsDao(ref.watch(databaseProvider)),
);

/// The items DAO.
final itemDaoProvider = Provider<ItemDao>(
  (ref) => ItemDao(ref.watch(databaseProvider)),
);

/// The inventory-batches DAO.
final batchDaoProvider = Provider<BatchDao>(
  (ref) => BatchDao(ref.watch(databaseProvider)),
);

/// The stock-movements DAO.
final stockMovementDaoProvider = Provider<StockMovementDao>(
  (ref) => StockMovementDao(ref.watch(databaseProvider)),
);

/// The shopping-lists DAO.
final shoppingListDaoProvider = Provider<ShoppingListDao>(
  (ref) => ShoppingListDao(ref.watch(databaseProvider)),
);

/// The shopping-entries DAO.
final shoppingEntryDaoProvider = Provider<ShoppingEntryDao>(
  (ref) => ShoppingEntryDao(ref.watch(databaseProvider)),
);

/// The recurring-templates DAO.
final recurringTemplateDaoProvider = Provider<RecurringTemplateDao>(
  (ref) => RecurringTemplateDao(ref.watch(databaseProvider)),
);

/// The recurring-occurrences DAO.
final recurringOccurrenceDaoProvider = Provider<RecurringOccurrenceDao>(
  (ref) => RecurringOccurrenceDao(ref.watch(databaseProvider)),
);

/// The assets DAO.
final assetDaoProvider = Provider<AssetDao>(
  (ref) => AssetDao(ref.watch(databaseProvider)),
);

/// The service-records DAO.
final serviceRecordDaoProvider = Provider<ServiceRecordDao>(
  (ref) => ServiceRecordDao(ref.watch(databaseProvider)),
);

/// The notification-schedule DAO.
final notificationScheduleDaoProvider = Provider<NotificationScheduleDao>(
  (ref) => NotificationScheduleDao(ref.watch(databaseProvider)),
);

/// The backup-history DAO.
final backupHistoryDaoProvider = Provider<BackupHistoryDao>(
  (ref) => BackupHistoryDao(ref.watch(databaseProvider)),
);

/// The analytics-cache DAO.
final analyticsCacheDaoProvider = Provider<AnalyticsCacheDao>(
  (ref) => AnalyticsCacheDao(ref.watch(databaseProvider)),
);

/// The calendar DAO, over `v_calendar_events`.
final calendarDaoProvider = Provider<CalendarDao>(
  (ref) => CalendarDao(ref.watch(databaseProvider)),
);
