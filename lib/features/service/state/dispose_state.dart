import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// What the dispose sheet is holding (ARCH_5 §3 archetype A).
///
/// **Disposal is a status change plus a reason, never a delete.** The ₹45,000 spent on a television
/// stays in every total after it goes to the tip, because the money left the house whether or not the
/// object is still in it (anomaly A30, ARCH_3 §4.1). That is why there is a reason picker here and no
/// delete anywhere in the module.
class DisposeState {
  /// Creates the sheet's state.
  const DisposeState({
    required this.assetId,
    required this.currencyCode,
    required this.dateKey,
    this.reason,
    this.amount,
    this.note,
    this.submitting = false,
    this.reasonMissing = false,
    this.rejection,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// Which asset is being retired.
  final String assetId;

  /// The currency a recovered amount is entered in.
  final String currencyCode;

  /// Why. The one required field (U11).
  final AssetDisposalReason? reason;

  /// When it happened.
  final DateKey dateKey;

  /// What the disposal recovered, if anything.
  ///
  /// Optional because most disposals recover nothing — a broken kettle is thrown away, not sold — and
  /// requiring a zero would make the common case extra typing.
  final Money? amount;

  /// Anything worth saying about it.
  final String? note;

  /// Whether a commit is in flight.
  final bool submitting;

  /// Whether commit was pressed with no reason chosen.
  final bool reasonMissing;

  /// The repository's own message when it rejected the write.
  final String? rejection;

  /// Incremented to shake the reason picker.
  final int shakeTrigger;

  /// Whether anything optional was touched, for the dismiss guard (Law U10).
  final bool dirty;

  /// Returns a copy with the supplied changes.
  DisposeState copyWith({
    AssetDisposalReason? reason,
    DateKey? dateKey,
    Money? amount,
    bool clearAmount = false,
    String? note,
    bool? submitting,
    bool? reasonMissing,
    String? rejection,
    bool clearRejection = false,
    int? shakeTrigger,
    bool? dirty,
  }) => DisposeState(
    assetId: assetId,
    currencyCode: currencyCode,
    reason: reason ?? this.reason,
    dateKey: dateKey ?? this.dateKey,
    amount: clearAmount ? null : (amount ?? this.amount),
    note: note ?? this.note,
    submitting: submitting ?? this.submitting,
    reasonMissing: reasonMissing ?? this.reasonMissing,
    rejection: clearRejection ? null : (rejection ?? this.rejection),
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? this.dirty,
  );
}
