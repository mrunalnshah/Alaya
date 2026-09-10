/// One provider per repository contract, typed as the **contract** and never the implementation.
///
/// Typing them as the interface is what makes the layering rule enforceable: a feature that declares
/// `ref.watch(accountRepositoryProvider)` receives an `AccountRepository` and cannot reach into
/// `AccountRepositoryImpl` for a method the contract does not expose.
///
/// **All seventeen of Phase 3A's contracts now have an implementation.** `CalendarRepository` was the
/// last but one, wired in Phase 7A; `AnalyticsCacheRepository` was the last, wired here. The note
/// that used to stand in this paragraph — two contracts unimplemented, three engines unreachable — is
/// closed (ARCH_4 §5.1 item 15).
///
/// `analyticsPortProvider` sits with the repositories rather than with the engines despite not being
/// a repository, because it has a repository's shape exactly: a contract declared in `domain/`, one
/// implementation in `data/`, and a provider typed as the contract so no feature can reach past it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/data/repositories/analytics_cache_repository_impl.dart';
import 'package:alaya/data/repositories/analytics_port_impl.dart';
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
import 'package:alaya/data/repositories/unconverted_count.dart';
import 'package:alaya/data/repositories/unit_repository_impl.dart';
import 'package:alaya/domain/repositories/analytics_cache_repository.dart';
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
import 'package:alaya/data/repositories/recipe_repository_impl.dart';
import 'package:alaya/domain/repositories/recipe_repository.dart';
import 'package:alaya/domain/services/recipe_cook_service.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/repositories/shopping_repository.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';
import 'package:alaya/domain/repositories/tag_repository.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';
import 'package:alaya/domain/repositories/unit_repository.dart';
import 'package:alaya/domain/services/analytics/analytics_port.dart';
import 'package:alaya/data/repositories/split_group_repository_impl.dart';
import 'package:alaya/data/repositories/split_ledger_repository_impl.dart';
import 'package:alaya/domain/repositories/split_group_repository.dart';
import 'package:alaya/domain/repositories/split_ledger_repository.dart';

/// Resolves an item's unit category, with a per-instance cache.
///
/// A single provider rather than one per consumer, because three repositories need it and its whole
/// value is the cache: constructing it twice halves the hit rate for no reason.
final itemCategoryResolverProvider = Provider<ItemCategoryResolver>(
  (ref) => ItemCategoryResolver(ref.watch(itemDaoProvider)),
);

/// Key-value app settings.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepositoryImpl(
    ref.watch(settingsDaoProvider),
    ref.watch(clockProvider),
  ),
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
    // Phase 7B: `watchUnconvertedCount` was a `Stream.value(0)` stub until this arrived, so the
    // `+N unconverted` chip could never report anything (ARCH_3 §1.5, ARCH_5 §7.3).
    unconvertedCounter: ref.watch(unconvertedCounterProvider),
  ),
);

/// Counts the transactions no cached rate can convert, for the `+N unconverted` chip.
///
/// Not a repository, and not in `service_providers.dart` either: it is the collaborator
/// `CurrencyRepositoryImpl` delegates one method to, so it belongs beside the repository that owns
/// it. It takes `CurrencyRateService` for the same reason that service takes closures over the DAO —
/// depending on `currencyRepositoryProvider` from here would be a cycle.
final unconvertedCounterProvider = Provider<UnconvertedCounter>(
  (ref) => UnconvertedCounter(
    database: ref.watch(databaseProvider),
    rates: ref.watch(currencyRateServiceProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

/// Units and conversion factors.
final unitRepositoryProvider = Provider<UnitRepository>(
  (ref) =>
      UnitRepositoryImpl(ref.watch(unitDaoProvider), ref.watch(clockProvider)),
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
  (ref) => PayeeRepositoryImpl(
    ref.watch(payeeDaoProvider),
    ref.watch(clockProvider),
  ),
);

/// Tags.
final tagRepositoryProvider = Provider<TagRepository>(
  (ref) =>
      TagRepositoryImpl(ref.watch(tagDaoProvider), ref.watch(clockProvider)),
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
  (ref) =>
      ItemRepositoryImpl(ref.watch(itemDaoProvider), ref.watch(clockProvider)),
);

/// Recipes, their ingredients and their cook log.
final recipeRepositoryProvider = Provider<RecipeRepository>(
  (ref) => RecipeRepositoryImpl(
    ref.watch(recipeDaoProvider),
    ref.watch(itemDaoProvider),
    ref.watch(unitDaoProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// Cooking a recipe: deducts stock through the inventory module and records that it happened.
///
/// Depends on `StockRepository` rather than reimplementing consumption — FEFO ordering, the atomic
/// application and the shortfall refusal all already live there.
final recipeCookServiceProvider = Provider<RecipeCookService>(
  (ref) => RecipeCookService(
    recipes: ref.watch(recipeRepositoryProvider),
    stock: ref.watch(stockRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
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
  (ref) => AssetRepositoryImpl(
    ref.watch(assetDaoProvider),
    ref.watch(clockProvider),
  ),
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

/// Memoised analytics results. Phase 3A declared the contract and no phase implemented it until 7B
/// (ARCH_4 §5.1 item 15), which is why `analyticsCacheServiceProvider` could not exist.
///
/// The `Clock` is the impl's own, not the DAO's: `AnalyticsCacheDao` takes absolute millis so it
/// stays assertable under a `FixedClock`, and the contract takes a `Duration`.
final analyticsCacheRepositoryProvider = Provider<AnalyticsCacheRepository>(
  (ref) => AnalyticsCacheRepositoryImpl(
    ref.watch(analyticsCacheDaoProvider),
    ref.watch(clockProvider),
  ),
);

/// The raw aggregates behind ARCH_3 §5.1's twenty-four queries.
///
/// Typed as the **port**, so `AnalyticsService` cannot reach into the adapter for a query the
/// contract does not declare — and so a fake in a test substitutes without the service noticing
/// (ARCH_4 R19).
final analyticsPortProvider = Provider<AnalyticsPort>(
  (ref) =>
      AnalyticsPortImpl(ref.watch(databaseProvider), ref.watch(clockProvider)),
);

/// Split groups and their membership, plus which payee the user has claimed as themselves.
///
/// Takes `SettingsDao` for `split.selfPayeeId` — a setting rather than a flag on `payees`, so no two
/// rows can claim it and a table five other modules read stays untouched.
final splitGroupRepositoryProvider = Provider<SplitGroupRepository>(
  (ref) => SplitGroupRepositoryImpl(
    ref.watch(splitDaoProvider),
    ref.watch(settingsDaoProvider),
    ref.watch(clockProvider),
  ),
);

/// Shared expenses, settlements, and every balance derived from them.
///
/// Takes `AccountDao` so a settlement can be checked against the account it claims to have moved
/// through — the currency match in particular, which is Law L8's money-side twin. That is ordinary
/// cross-module DAO composition: `TransactionRepositoryImpl` holds six DAOs across three modules and
/// its own class doc calls it *"normal DAO composition, not a layering violation."*
final splitLedgerRepositoryProvider = Provider<SplitLedgerRepository>(
  (ref) => SplitLedgerRepositoryImpl(
    ref.watch(splitDaoProvider),
    ref.watch(splitViewDaoProvider),
    ref.watch(splitGroupRepositoryProvider),
    ref.watch(accountDaoProvider),
    ref.watch(clockProvider),
  ),
);
