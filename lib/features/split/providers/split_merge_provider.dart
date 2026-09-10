/// Putting a name to an unnamed split participant (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// Resolves a placeholder into a real person, either way round.
final splitNamePlaceholderProvider =
    NotifierProvider<SplitNamePlaceholder, AsyncValue<void>>(
      SplitNamePlaceholder.new,
    );

/// The two answers to *"who is this?"*, and they are different operations.
///
/// **"Somebody you know" is a merge; "a new name" is a rename.** Both look like typing a name into a box,
/// and only one of them can be done with an `UPDATE payees SET name`. If Ravi already exists, renaming the
/// placeholder to "Ravi" leaves two Ravis — he ends up with two balances, and settling one leaves the other
/// outstanding with no explanation on screen.
class SplitNamePlaceholder extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Says this placeholder was somebody the app already knows.
  ///
  /// Every share, settlement, membership and paid-by reference moves to [payeeId] and the placeholder is
  /// retired — in one database transaction, because a half-moved identity is two debts where there should
  /// be one.
  Future<bool> mergeInto({
    required String placeholderPayeeId,
    required String payeeId,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(splitLedgerRepositoryProvider)
        .mergePlaceholder(
          placeholderPayeeId: placeholderPayeeId,
          payeeId: payeeId,
        );
    return _settle(result.failureOrNull);
  }

  /// Says this placeholder was somebody new, called [name].
  ///
  /// **Writes `kind: person` as well as the name**, which is what takes the row out of the placeholder set
  /// and into every list a contact belongs in. Renaming alone left it hidden — the user did the right thing
  /// and the app appeared to ignore them.
  Future<bool> rename({
    required Payee placeholder,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;

    state = const AsyncLoading<void>();
    final result = await ref
        .read(payeeRepositoryProvider)
        .save(
          Payee(
            id: placeholder.id,
            name: trimmed,
            normalizedName: ref.read(normalizerProvider).normalize(trimmed),
            kind: PayeeKind.person,
            phone: placeholder.phone,
            note: placeholder.note,
          ),
        );
    return _settle(result.failureOrNull);
  }

  bool _settle(Failure? failure) {
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    // **Balances are invalidated explicitly after a merge.** `watchBalances` is a stream over
    // `v_split_balances`, which drift re-runs when a table it reads is written — and a merge writes through
    // a transaction touching `payees`, which the view *joins* rather than selects from. Relying on the
    // dependency being noticed is the kind of assumption that shows up as a screen that did not change.
    ref.invalidate(splitBalancesProvider);
    state = const AsyncData(null);
    return true;
  }

  /// The message from the last failure, or null.
  String? get lastError {
    final error = state.error;
    return error is Failure ? error.message : null;
  }
}
