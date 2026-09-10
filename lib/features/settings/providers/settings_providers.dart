/// View-model state for the settings tree (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';

/// What the user has typed into the settings search field.
final settingsQueryProvider = NotifierProvider<SettingsQueryNotifier, String>(
  SettingsQueryNotifier.new,
);

/// Holds the settings search term.
class SettingsQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  /// Records [query].
  void set(String query) => state = query;
}

/// How many accounts exist, archived ones included.
///
/// **Archived included, unlike the pickers.** This row is the way to *reach* an archived account and
/// un-archive it, so a count that hid them would make the branch look emptier than the screen behind it —
/// and an archived account the user cannot find is one they will recreate by hand.
final settingsAccountCountProvider = StreamProvider<int>(
  (ref) => ref
      .watch(accountRepositoryProvider)
      .watchAllIncludingArchived()
      .map((accounts) => accounts.length),
);

/// How many payment methods exist.
final settingsPaymentMethodCountProvider = StreamProvider<int>(
  (ref) => ref
      .watch(paymentMethodRepositoryProvider)
      .watchAll()
      .map((rows) => rows.length),
);

/// How many payees the branch will show.
///
/// **Counts what [isContactPayee] admits, which is what the list shows.** This used to count every row the
/// repository had, while the branch it labels filtered out `PayeeKind.splitPlaceholder`. Both were correct
/// for what they read and they disagreed by the number of unnamed split participants: the row said *3
/// payees* above a screen listing one.
///
/// **Still a `StreamProvider<int>`, deliberately.** The first fix made it a `Provider<AsyncValue<int>>`
/// reading `payeesSettingsProvider`, which shares the source but changes the type — and every test harness
/// that overrides this with a stream stopped compiling. A shared *predicate* fixes the disagreement without
/// touching the shape, which is what an override is written against.
final settingsPayeeCountProvider = StreamProvider<int>(
  (ref) => ref
      .watch(payeeRepositoryProvider)
      .watchAll()
      .map((rows) => rows.where(isContactPayee).length),
);

/// How many tags exist.
final settingsTagCountProvider = StreamProvider<int>(
  (ref) =>
      ref.watch(tagRepositoryProvider).watchAll().map((rows) => rows.length),
);

/// How many units exist.
final settingsUnitCountProvider = StreamProvider<int>(
  (ref) =>
      ref.watch(unitRepositoryProvider).watchAll().map((rows) => rows.length),
);

/// How many currencies are enabled, and how many exist.
final settingsCurrencyCountProvider =
    StreamProvider<({int enabled, int total})>((ref) {
      final repository = ref.watch(currencyRepositoryProvider);
      return repository.watchAll().asyncMap((all) async {
        final enabled = await repository.watchEnabled().first;
        return (enabled: enabled.length, total: all.length);
      });
    });
