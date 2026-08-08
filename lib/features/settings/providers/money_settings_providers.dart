/// View-model state for the accounts, payment-method and payee branches (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';

/// Every account, archived ones included, so the branch can offer to un-archive.
final accountsSettingsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAllIncludingArchived(),
);

/// Every payment method.
final paymentMethodsSettingsProvider = StreamProvider<List<PaymentMethod>>(
  (ref) => ref.watch(paymentMethodRepositoryProvider).watchAll(),
);

/// Every payee.
final payeesSettingsProvider = StreamProvider<List<Payee>>(
  (ref) => ref.watch(payeeRepositoryProvider).watchAll(),
);

/// The home currency, as the default for a new account.
///
/// A new account in a currency the user never uses is a row they will edit before their first transaction, so
/// the default is the one currency they have already chosen (Law L9's setting, used as a hint rather than a rule).
final accountsHomeCurrencyProvider = FutureProvider<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      'INR',
);

/// One account being edited, or null for a new one.
final accountDraftProvider = FutureProvider.autoDispose
    .family<Account?, String?>((ref, id) async {
      if (id == null) return null;
      return ref.watch(accountRepositoryProvider).byId(id);
    });

/// Saves and archives accounts.
final accountEditorProvider =
    NotifierProvider<AccountEditorNotifier, AsyncValue<void>>(
      AccountEditorNotifier.new,
    );

/// Writes an account, reporting the repository's own message on failure.
class AccountEditorNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Creates or replaces [account], returning whether it was written.
  Future<bool> save({
    required String? id,
    required String name,
    required AccountKind kind,
    required String currencyCode,
    required int openingMinor,
    required DateKey openingDate,
    required bool includeInNetWorth,
    required bool isArchived,
    required int sortOrder,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(accountRepositoryProvider)
        .save(
          Account(
            id: id ?? ref.read(uidGeneratorProvider).generate(),
            name: name.trim(),
            normalizedName: ref.read(normalizerProvider).normalize(name),
            kind: kind,
            currencyCode: currencyCode,
            openingBalance: Money(openingMinor, currencyCode),
            openingBalanceDateKey: openingDate,
            isArchived: isArchived,
            includeInNetWorth: includeInNetWorth,
            sortOrder: sortOrder,
          ),
        );
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('save failed'),
        StackTrace.current,
      );
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }

  /// Archives or restores [id].
  ///
  /// **Archive, not delete.** ARCH_3 §4 keeps an archived account out of every picker while its history stays
  /// intact and its balance stays out of net worth if the user said so — deleting one would orphan every
  /// transaction that ever named it.
  Future<bool> setArchived({
    required String id,
    required bool isArchived,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(accountRepositoryProvider)
        .setArchived(id: id, isArchived: isArchived);
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('archive failed'),
        StackTrace.current,
      );
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}

/// Saves a payment method.
final paymentMethodEditorProvider =
    NotifierProvider<PaymentMethodEditorNotifier, AsyncValue<void>>(
      PaymentMethodEditorNotifier.new,
    );

/// Writes a payment method.
class PaymentMethodEditorNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Creates or replaces one, returning whether it was written.
  Future<bool> save({
    required String? id,
    required String name,
    required PaymentMethodKind kind,
    required int sortOrder,
    bool isSystem = false,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(paymentMethodRepositoryProvider)
        .save(
          PaymentMethod(
            id: id ?? ref.read(uidGeneratorProvider).generate(),
            name: name.trim(),
            kind: kind,
            isSystem: isSystem,
            sortOrder: sortOrder,
          ),
        );
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  /// Deletes [id].
  Future<bool> delete(String id) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(paymentMethodRepositoryProvider).delete(id);
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  bool _settle(Object? failure) {
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}

/// Saves a payee.
final payeeEditorProvider =
    NotifierProvider<PayeeEditorNotifier, AsyncValue<void>>(
      PayeeEditorNotifier.new,
    );

/// Writes a payee.
class PayeeEditorNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Creates or replaces one, returning whether it was written.
  Future<bool> save({
    required String? id,
    required String name,
    required PayeeKind kind,
    String? phone,
    String? note,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(payeeRepositoryProvider)
        .save(
          Payee(
            id: id ?? ref.read(uidGeneratorProvider).generate(),
            name: name.trim(),
            normalizedName: ref.read(normalizerProvider).normalize(name),
            kind: kind,
            phone: phone,
            note: note,
          ),
        );
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  /// Deletes [id].
  Future<bool> delete(String id) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(payeeRepositoryProvider).delete(id);
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  bool _settle(Object? failure) {
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}
