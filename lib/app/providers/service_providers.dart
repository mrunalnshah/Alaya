/// One provider per engine.
///
/// The stateless engines are `const` and could in principle be constructed at each use site. They get
/// providers anyway so that every dependency in the app arrives the same way — a codebase where some
/// collaborators are injected and others are constructed inline is one where you cannot tell, from a
/// widget, what it actually depends on.
///
/// ## Every engine now has a provider
///
/// Three did not, for five phases. `CalendarAggregator` was blocked on `CalendarRepository` and was
/// wired in 7A; `AnalyticsService` was blocked on an `AnalyticsPort` adapter and `AnalyticsCacheService`
/// on `AnalyticsCacheRepository`, and both are wired here (ARCH_4 §5.1 item 15).
///
/// **The decision to omit them rather than stub them was the right one, and it is worth keeping the
/// reasoning after the fact.** A port returning empty rows makes an unfinished analytics screen
/// indistinguishable from a working one that found no data — there is no way to tell those apart from
/// the UI, and no test that would have failed. An absent provider is a compile error at the first use
/// site, which names the problem where someone can act on it. Phase 6F's insight card is the proof:
/// its spending side shipped as an honest inline empty state naming what it waited for, rather than
/// as a chart of zeroes.
///
/// `analyticsServiceProvider` is the one `FutureProvider` among the engines, because `AnalyticsService`
/// takes a **loaded** `RateTable` rather than the service that loads it. That is ARCH_3 §1.5's design
/// working as intended: conversion is synchronous so a month of data costs one table load instead of
/// two cache round trips per amount, and somebody has to await the load. Here it is a provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_auth/local_auth.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/data/backup/backup_service.dart';
import 'package:alaya/data/backup/restore_service.dart';
import 'package:alaya/data/remote/currency_api_client.dart';
import 'package:alaya/data/repositories/mappers/rate_mappers.dart';
import 'package:alaya/data/security/app_lock_store.dart';
import 'package:alaya/data/backup/erase_service.dart';
import 'package:alaya/data/attachments/attachment_store.dart';
import 'package:alaya/data/backup/restore_service.dart';
import 'package:alaya/data/backup/share_backup_transfer.dart';
import 'package:alaya/data/reminders/local_notification_scheduler.dart';
import 'package:alaya/data/support/ads_and_billing.dart';
import 'package:alaya/data/trash/trash_adapter.dart';
import 'package:alaya/data/security/local_auth_biometric_gate.dart';
import 'package:alaya/data/security/pin_service.dart';
import 'package:alaya/data/security/recovery_code.dart';
import 'package:alaya/domain/services/analytics/analytics_cache_service.dart';
import 'package:alaya/domain/services/analytics/analytics_service.dart';
import 'package:alaya/domain/services/attachments/attachment_port.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/domain/services/lock/app_lock.dart';
import 'package:alaya/domain/services/lock/biometric_gate.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';
import 'package:alaya/domain/services/support/support_port.dart';
import 'package:alaya/domain/services/trash/trash_port.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';
import 'package:alaya/domain/services/date_range_service.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/services/low_stock_suggestion_engine.dart';
import 'package:alaya/domain/services/purchase_fan_out_service.dart';
import 'package:alaya/domain/services/recurring_engine.dart';
import 'package:alaya/domain/services/stock_reconciler.dart';
import 'package:alaya/domain/services/unit_engine.dart';
import 'package:alaya/domain/services/split/settlement_service.dart';
import 'package:alaya/domain/services/split/split_balance_service.dart';
import 'package:alaya/domain/services/split/split_expense_service.dart';

// ── stateless engines ───────────────────────────────────────────────────────────────────

/// Unit conversion within a category.
final unitEngineProvider = Provider<UnitEngine>((ref) => const UnitEngine());

/// Date-range presets for filters and analytics.
final dateRangeServiceProvider = Provider<DateRangeService>(
  (ref) => const DateRangeService(),
);

/// Net worth and per-account balances.
final balanceServiceProvider = Provider<BalanceService>(
  (ref) => const BalanceService(),
);

/// FEFO consumption planning.
final inventoryConsumptionServiceProvider =
    Provider<InventoryConsumptionService>(
      (ref) => const InventoryConsumptionService(),
    );

/// Cache-versus-ledger reconciliation and repair.
final stockReconcilerProvider = Provider<StockReconciler>(
  (ref) => const StockReconciler(),
);

/// Idempotent low-stock suggestion decisions.
final lowStockSuggestionEngineProvider = Provider<LowStockSuggestionEngine>(
  (ref) => const LowStockSuggestionEngine(),
);

/// Recurring schedule arithmetic — next due, materialisation, settlement.
final recurringEngineProvider = Provider<RecurringEngine>(
  (ref) => const RecurringEngine(),
);

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
final pinServiceProvider = Provider<AppLock>(
  (ref) => PinService(
    store: ref.watch(appLockStoreProvider),
    clock: ref.watch(clockProvider),
    recoveryCode: ref.watch(recoveryCodeProvider),
  ),
);

/// The biometric shortcut on the lock screen (ARCH_3 §2.2).
///
/// Typed as the **contract**, so no feature can reach `local_auth` — and so a widget test substitutes a
/// fake instead of needing a platform channel, which is the reason the contract exists.
final biometricGateProvider = Provider<BiometricGate>(
  (ref) => LocalAuthBiometricGate(LocalAuthentication()),
);

/// Erasing everything — the last resort behind "I have forgotten both" (ARCH_3 §2.2).
///
/// Takes its seeder from the database rather than as an argument, so a re-seed after an erase cannot
/// differ from the install it is restoring.
final eraseServiceProvider = Provider<EraseService>(
  (ref) => EraseService(
    database: ref.watch(databaseProvider),
    lockStore: ref.watch(appLockStoreProvider),
  ),
);

/// Exporting a backup and erasing everything, behind one contract.
///
/// One port for both because ARCH_3 §2.2's forgot-both path offers the export *and then* erases, and the
/// two halves of that conversation should not come from different subsystems.
final dataTransferPortProvider = Provider<DataTransferPort>(
  (ref) => ShareBackupTransfer(
    backup: ref.watch(backupServiceProvider),
    erase: ref.watch(eraseServiceProvider),
    restore: ref.watch(restoreServiceProvider),
    history: ref.watch(backupHistoryDaoProvider),
    database: ref.watch(databaseProvider),
    attachments: ref.watch(attachmentPortProvider),
  ),
);

/// Attaching, viewing and deleting files (ARCH_5 §7's `attachments` row).
///
/// Typed as the contract, so no feature can reach `file_picker` — and so a widget test substitutes a fake instead
/// of needing a platform channel.
final attachmentPortProvider = Provider<AttachmentPort>(
  (ref) => AttachmentStore(
    database: ref.watch(databaseProvider),
    uids: ref.watch(uidGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// The trash, and the one hard delete in the codebase (ARCH_3 §4.2).
final trashPortProvider = Provider<TrashPort>(
  (ref) => TrashAdapter(
    database: ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// One daily digest, inexactly scheduled (ARCH_3 §7).
final reminderPortProvider = Provider<ReminderPort>(
  (ref) => LocalNotificationScheduler(
    plugin: FlutterLocalNotificationsPlugin(),
    database: ref.watch(databaseProvider),
    scheduleDao: ref.watch(notificationScheduleDaoProvider),
    calendar: ref.watch(calendarAggregatorProvider),
    settings: ref.watch(settingsRepositoryProvider),
    uids: ref.watch(uidGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Rewarded ads and the one-time tip.
///
/// **Constructing this initialises nothing.** `AdsAndBilling` brings the SDKs up only when `initialise()` is
/// called, which the Support screen does in `initState` and nothing else does at all — so watching this provider
/// from anywhere would still make no ad call.
final supportPortProvider = Provider<SupportPort>((ref) => AdsAndBilling());

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

// ── analytics ───────────────────────────────────────────────────────────────────────────

/// The home currency every converted analytics figure is expressed in.
///
/// `'INR'` is a data fallback for a setting Phase 1C's seed always writes, not a user-visible string,
/// so Law U5 does not reach it. It is named rather than inlined because three files now need the same
/// answer and three literals is how they start disagreeing.
const String analyticsFallbackHomeCurrencyCode = 'INR';

/// Memoisation for analytics results slower than roughly 200 ms (ARCH_3 §5.2).
final analyticsCacheServiceProvider = Provider<AnalyticsCacheService>(
  (ref) => AnalyticsCacheService(ref.watch(analyticsCacheRepositoryProvider)),
);

/// ARCH_3 §5.1's twenty-four queries, over the SQL adapter and a loaded rate table.
///
/// **A `FutureProvider`, because the `RateTable` has to be in hand before the service is built.**
/// Every conversion in `AnalyticsService` is synchronous by design (ARCH_3 §1.5) — that is what makes
/// converting a month of transactions one table load rather than a thousand — so the awaiting happens
/// once, here, instead of per amount.
///
/// Re-created when the rate cache is written, because `CurrencyRateService.table()` is watched rather
/// than read: a rate arriving must change the figures it feeds, not just the unconverted count beside
/// them.
final analyticsServiceProvider = FutureProvider<AnalyticsService>((ref) async {
  final rates = await ref.watch(currencyRateServiceProvider).table();
  final home =
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      analyticsFallbackHomeCurrencyCode;
  return AnalyticsService(
    port: ref.watch(analyticsPortProvider),
    rates: rates,
    homeCurrencyCode: home,
  );
});

/// Turning split instructions into stored shares.
///
/// Holds `SplitResolver` by default rather than taking one per call: the resolver is stateless and
/// `const`, and threading it through every call site would be a parameter that never varies.
final splitExpenseServiceProvider = Provider<SplitExpenseService>(
  (ref) => SplitExpenseService(
    ledger: ref.watch(splitLedgerRepositoryProvider),
    uids: ref.watch(uidGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Recording money that changed hands to settle a split debt.
///
/// **The one write in this module whose failure a user could not see**, which is why it goes through a
/// single repository call that writes the settlement and its transaction in one database transaction.
/// Splitwise's "settle up" is a marker it cannot back with anything; here the deposit or withdrawal is
/// an ordinary `transactions` row, so the two ledgers cannot diverge.
final settlementServiceProvider = Provider<SettlementService>(
  (ref) => SettlementService(
    ledger: ref.watch(splitLedgerRepositoryProvider),
    groups: ref.watch(splitGroupRepositoryProvider),
    uids: ref.watch(uidGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Who owes what, how long they have owed it, and the shortest way to settle up.
///
/// Takes `Clock` because the balance views cannot: ARCH_2 §12.2 forbids any view from consulting the
/// current time, so the ageing that the daily digest reads — *"owed for three weeks"* — is computed
/// here against an injected clock and stays reproducible under a `FixedClock`.
final splitBalanceServiceProvider = Provider<SplitBalanceService>(
  (ref) => SplitBalanceService(
    ledger: ref.watch(splitLedgerRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);
