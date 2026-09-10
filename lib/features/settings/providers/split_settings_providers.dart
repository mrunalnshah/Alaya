/// Writing the split module's two settings (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/features/split/providers/split_summary_provider.dart';

/// Saves who the user is, and how people can pay them.
final splitSettingsProvider = NotifierProvider<SplitSettings, AsyncValue<void>>(
  SplitSettings.new,
);

/// Writes `split.selfPayeeId` and `split.paymentHandle`.
class SplitSettings extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Claims [payeeId] as the user.
  ///
  /// **Invalidating `splitSelfProvider` is not optional.** It is a `FutureProvider` over a one-shot
  /// read — the setting changes once, during setup, so a stream would be machinery for an event that
  /// happens a single time — and without the invalidation every balance screen keeps the null it was
  /// built with until the app restarts. The user would set the value, see no change, and reasonably
  /// conclude it did not work.
  Future<bool> setSelf(String payeeId) async {
    final result = await ref
        .read(splitGroupRepositoryProvider)
        .setSelfPayeeId(payeeId);
    if (result.isFailure) {
      state = AsyncError<void>(result.failureOrNull!, StackTrace.current);
      return false;
    }
    ref.invalidate(splitSelfProvider);
    return true;
  }

  /// Sets or clears how people can pay the user.
  ///
  /// **Free text, and deliberately unvalidated.** The field used to be a UPI id, which meant the app
  /// implicitly assumed India; it now holds whatever a user anywhere writes — a PayPal link, an IBAN,
  /// a Venmo handle, "cash is fine". Any validation would be a guess about which country somebody is
  /// in, and a wrong guess would reject a perfectly good answer.
  ///
  /// An empty string removes the row rather than storing a blank, so `SplitSummaryBuilder` sees null
  /// and omits the line instead of writing a label with nothing after it.
  Future<bool> setPaymentHandle(String value) async {
    final settings = ref.read(settingsRepositoryProvider);
    final trimmed = value.trim();
    final result = trimmed.isEmpty
        ? await settings.remove(splitPaymentHandleKey)
        : await settings.writeValue(
            key: splitPaymentHandleKey,
            value: trimmed,
            valueType: 'string',
          );
    if (result.isFailure) {
      state = AsyncError<void>(result.failureOrNull!, StackTrace.current);
      return false;
    }
    ref.invalidate(splitPaymentHandleProvider);
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
