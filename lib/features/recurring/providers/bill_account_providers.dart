/// Resolving which account a bill payment comes from, without asking (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/account.dart';

/// Accounts a payment may come from.
final billAccountsProvider = StreamProvider.autoDispose<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// The app-wide default account, if the user has set one.
final defaultAccountIdProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(settingsRepositoryProvider).readDefaultAccountId(),
);

/// The account a bill payment should use when the user has not chosen one.
///
/// **Three fallbacks, in order, none of which asks:** the template's own `defaultAccountId`, then the
/// app-wide default from settings, then the only selectable account if there is exactly one. Recording
/// a bill should be one tap, and every one of these is information the user has already given.
///
/// It stops at null rather than guessing between two accounts. A withdrawal attributed to the wrong
/// account is worse than one that asked, because nothing on screen would ever reveal it — whereas the
/// question is answered once and remembered on the template.
final resolvedBillAccountProvider = Provider.autoDispose
    .family<String?, String?>((ref, templateDefault) {
      if (templateDefault != null) return templateDefault;
      final appDefault = ref.watch(defaultAccountIdProvider).valueOrNull;
      if (appDefault != null) return appDefault;
      final accounts =
          ref.watch(billAccountsProvider).valueOrNull ?? const <Account>[];
      return accounts.length == 1 ? accounts.single.id : null;
    });
