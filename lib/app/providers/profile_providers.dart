/// Who the user is, app-wide.
///
/// **This is not a split concept, and it was living inside one.** Every balance in the split module is
/// "what they owe *you*" or "what *you* owe them", so the module needed to know which payee the user is —
/// and the setting ended up named `split.selfPayeeId`, read through `SplitGroupRepository`, and asked for
/// on a split screen. All three placed a fact about the person using the app inside one feature of it.
///
/// The same fact answers questions nothing to do with splitting: what to call somebody on a dashboard,
/// whose name signs a shared summary, which participant to preselect anywhere a person is one of several.
/// So it belongs here, beside `clockProvider` and the home currency.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/domain/entities/payee.dart';

/// The `app_settings` key holding which payee the user is.
///
/// **Still prefixed `split.`, deliberately.** The name is wrong — this is a profile fact, not a split one
/// — and renaming it would orphan every install that already has a value, for no benefit a user can see.
/// `split.upiId` was renamed because its *meaning* was wrong; this one's meaning is right and only its
/// label is dated. Change it when something else forces a settings migration, not before.
const String selfPayeeIdKey = 'split.selfPayeeId';

/// The payee the user has claimed as themselves, or null when nobody has been claimed.
///
/// **Null means "not asked yet", never "nobody".** On a fresh install there is no payee to point at, so
/// anything reading this has to treat null as a setup step rather than as an absence of data — the
/// distinction the split screen's two empty states exist for.
final selfPayeeIdProvider = FutureProvider<String?>(
  (ref) => ref.watch(settingsRepositoryProvider).readValue(selfPayeeIdKey),
);

/// The user, as a payee row — or null before onboarding, or if the row was deleted.
///
/// **The second null is real and worth handling.** Nothing stops somebody deleting themselves from
/// Settings › Payees; the setting would then name a row that no longer exists, and every screen reading
/// this gets null rather than a crash.
final selfPayeeProvider = FutureProvider<Payee?>((ref) async {
  final id = await ref.watch(selfPayeeIdProvider.future);
  if (id == null) return null;
  return ref.watch(payeeRepositoryProvider).byId(id);
});

/// What to call the user, or null when they have not said.
///
/// **One source, no copy.** The obvious alternative — an `app_settings` row holding the name as text —
/// would drift the first time somebody renamed themselves under Payees, and nothing would say which of
/// the two was right. The name is the payee's `name`, read through the id.
final userDisplayNameProvider = FutureProvider<String?>(
  (ref) async => (await ref.watch(selfPayeeProvider.future))?.name,
);

/// Claims a payee as the user, creating them when the name is new.
final claimSelfProvider = NotifierProvider<ClaimSelf, AsyncValue<void>>(
  ClaimSelf.new,
);

/// Writes the user's identity: a payee, and the setting that points at it.
class ClaimSelf extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Claims whoever is called [name], creating them if nobody is.
  ///
  /// **An existing person with that name is reused rather than duplicated.** Somebody who added
  /// themselves under Payees before reaching this, or who reinstalls over a restored backup, should be
  /// claimed and not cloned — two "Ravi" rows where one is the user is the worst possible state for a
  /// module built on who owes whom.
  ///
  /// **Both writes, or the caller is told.** Creating the payee without pointing the setting at it leaves
  /// the app exactly as unconfigured as before, which is the half-finished state the old redirect to
  /// Settings used to produce.
  Future<bool> claim(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;

    state = const AsyncLoading<void>();
    final normalizer = ref.read(normalizerProvider);
    final normalized = normalizer.normalize(trimmed);
    final payees = ref.read(payeeRepositoryProvider);

    var id = <String?>[
      for (final payee in await payees.watchAll().first)
        if (payee.normalizedName == normalized &&
            payee.kind == PayeeKind.person)
          payee.id,
    ].firstOrNull;

    if (id == null) {
      final saved = await payees.save(
        Payee(
          id: ref.read(uidGeneratorProvider).generate(),
          name: trimmed,
          normalizedName: normalized,
          // `person`, never `merchant` — the default that made the split module unusable, because
          // `splitPeopleProvider` filters to persons and every list came back empty.
          kind: PayeeKind.person,
        ),
      );
      final payee = saved.valueOrNull;
      if (payee == null) {
        state = AsyncError<void>(
          saved.failureOrNull ??
              const UnexpectedFailure('That name could not be saved.'),
          StackTrace.current,
        );
        return false;
      }
      id = payee.id;
    }

    final written = await ref
        .read(settingsRepositoryProvider)
        .writeValue(key: selfPayeeIdKey, value: id, valueType: 'string');
    if (written.isFailure) {
      state = AsyncError<void>(
        written.failureOrNull ??
            const UnexpectedFailure('That name could not be saved.'),
        StackTrace.current,
      );
      return false;
    }

    // Everything downstream reads through `selfPayeeIdProvider`, so invalidating it is what makes the
    // rest of the app notice. Without this the value is correct in the database and stale in memory until
    // the next launch — which is how a setup step appears to have done nothing.
    ref.invalidate(selfPayeeIdProvider);
    state = const AsyncData(null);
    return true;
  }

  /// The message from the last failure, or null.
  ///
  /// Typed, not cast: an `as dynamic` to reach `message` would compile against anything and fail at
  /// runtime the first time a non-`Failure` landed in the error slot.
  String? get lastError {
    final error = state.error;
    return error is Failure ? error.message : null;
  }
}
