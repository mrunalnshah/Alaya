/// View-model state for disposal (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/service/state/dispose_state.dart';

/// Which asset a dispose sheet is retiring, and the currency a recovery is entered in.
typedef DisposeArgs = ({String assetId, String currencyCode});

/// The dispose sheet for one asset.
final disposeProvider = NotifierProvider.autoDispose
    .family<DisposeNotifier, DisposeState, DisposeArgs>(
      DisposeNotifier.new,
    );

/// Holds the pending disposal and commits it.
///
/// **State is synchronous.** Everything the sheet needs arrives in the family argument from the screen
/// that already loaded the asset, so the reason picker is usable on the first frame rather than after a
/// spinner (ARCH_5 §5.2).
class DisposeNotifier
    extends AutoDisposeFamilyNotifier<DisposeState, DisposeArgs> {
  @override
  DisposeState build(DisposeArgs arg) => DisposeState(
    assetId: arg.assetId,
    currencyCode: arg.currencyCode,
    dateKey: ref.read(clockProvider).today(),
  );

  /// Sets why it is being retired.
  void setReason(AssetDisposalReason reason) =>
      state = state.copyWith(reason: reason, reasonMissing: false, dirty: true);

  /// Sets when.
  void setDate(DateKey date) =>
      state = state.copyWith(dateKey: date, dirty: true);

  /// Sets what the disposal recovered.
  void setAmount(Money? amount) => state = amount == null
      ? state.copyWith(clearAmount: true, dirty: true)
      : state.copyWith(amount: amount, dirty: true);

  /// Sets the note.
  void setNote(String note) => state = state.copyWith(note: note, dirty: true);

  /// Commits the disposal, returning the failure's own message or null on success.
  ///
  /// **`dispose` changes a status and records a reason. Nothing is deleted.** The purchase price stays
  /// on the row, so what the household spent on the thing still counts in every total after the thing
  /// itself has gone (anomaly A30, ARCH_3 §4.1).
  ///
  /// The amount is passed as minor units because that is what the contract takes; the currency is the
  /// asset's own, which is why the sheet is handed one rather than picking.
  Future<String?> commit() async {
    final reason = state.reason;
    if (reason == null) {
      state = state.copyWith(
        reasonMissing: true,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return 'reasonMissing';
    }

    state = state.copyWith(submitting: true, clearRejection: true);
    try {
      final result = await ref
          .read(assetRepositoryProvider)
          .dispose(
            assetId: state.assetId,
            reason: reason,
            dateKey: state.dateKey,
            amountMinor: state.amount?.minor,
            note: state.note,
          );
      final failure = result.failureOrNull;
      if (failure != null) {
        state = state.copyWith(rejection: failure.message);
        return failure.message;
      }
      return null;
    } on Object catch (error, stack) {
      ref
          .read(loggerProvider)
          .log(
            'Asset disposal failed',
            level: LogLevel.error,
            tag: 'service.dispose',
            error: error,
            stackTrace: stack,
          );
      state = state.copyWith(rejection: error.toString());
      return error.toString();
    } finally {
      state = state.copyWith(submitting: false);
    }
  }
}
