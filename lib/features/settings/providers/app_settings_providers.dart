/// View-model state for the currencies, appearance and security branches (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/entities/currency.dart';

/// Every currency, enabled or not.
final currenciesSettingsProvider = StreamProvider<List<Currency>>(
  (ref) => ref.watch(currencyRepositoryProvider).watchAll(),
);

/// The home currency's code, which cannot be disabled.
final homeCurrencyCodeProvider = FutureProvider<String?>(
  (ref) => ref.watch(settingsRepositoryProvider).readHomeCurrencyCode(),
);

/// Enables and disables currencies.
final currencyToggleProvider =
    NotifierProvider<CurrencyToggleNotifier, AsyncValue<void>>(
      CurrencyToggleNotifier.new,
    );

/// Writes a currency's enabled flag.
class CurrencyToggleNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Enables or disables [code].
  Future<bool> setEnabled({
    required String code,
    required bool isEnabled,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(currencyRepositoryProvider)
        .setEnabled(code: code, isEnabled: isEnabled);
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('toggle failed'),
        StackTrace.current,
      );
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}

/// How many rows are in the trash, for the Data branch's row.
///
/// Phase 8B. Reads `trashPortProvider`, which is app-level — a feature watching another feature's provider would
/// be the coupling ARCH_5 §8 keeps out of the settings tree.
final settingsTrashCountProvider = StreamProvider<int>(
  (ref) => ref.watch(trashPortProvider).watchCount(),
);

/// Whether a lock is configured, for the security branch.
final lockConfiguredProvider = FutureProvider<bool>(
  (ref) => ref.watch(pinServiceProvider).isEnabled,
);
