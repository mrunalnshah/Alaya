import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/split/split_resolver.dart';

/// The split the transaction editor is holding, before anything is saved.
///
/// **A draft, not the entity.** A `SplitExpense` needs a transaction id, and there is no transaction
/// until the editor saves — so the editor carries the *instructions* and the service turns them into
/// shares afterwards. That ordering is forced and it is the safe one: an expense saved without its
/// split leaves a transaction the user can see and re-split, while the reverse would be a debt
/// against a payment that does not exist.
///
/// It rides the same save flow the purchase fan-out already uses: held in editor state, applied after
/// the transaction commits, and any failure surfaced through `splitError` exactly as `fanOutError`
/// reports a batch that could not be created.
class SplitDraft {
  /// Creates a draft.
  const SplitDraft({
    required this.paidByPayeeId,
    required this.method,
    this.inputs = const [],
    this.groupId,
    this.settleByDateKey,
  });

  /// Who fronted the money.
  ///
  /// The user themselves in the ordinary case — you paid, and the transaction being edited is that
  /// payment. Somebody else when the expense is being recorded on their behalf, in which case the
  /// editor is not the right entry point and the split module's own screen is.
  final String paidByPayeeId;

  /// How the shares were specified.
  final SplitMethod method;

  /// One instruction per participant.
  final List<ShareInput> inputs;

  /// The group this belongs to, or null for a one-off split.
  final String? groupId;

  /// An optional date to settle by, which feeds the calendar and the daily digest.
  ///
  /// **Typed, having been `Object?` since session 5b.** That was laziness — a way to avoid one import
  /// on a field nothing read yet — and it would have silently accepted anything the moment something
  /// did. It now feeds `v_calendar_events`' `splitSettleBy` arm and the `settlementDue` reminder, so a
  /// wrong type here would reach a notification.
  final DateKey? settleByDateKey;

  /// Whether anything is actually being split.
  bool get isActive => inputs.isNotEmpty;

  /// The people on this split.
  List<String> get payeeIds => [for (final input in inputs) input.payeeId];

  /// Resolves the draft against [total], or null when nothing is being split.
  ///
  /// **Called on every rebuild, deliberately.** The resolver is pure and cheap, and recomputing is
  /// what keeps the per-person amounts on screen equal to the ones that will be written — a cached
  /// resolution would be a second source for the same fact, which ARCH_M §6 forbids for exactly the
  /// reason it would show one number and save another.
  ///
  /// Returns null rather than throwing on a malformed draft: the resolver refuses things a user
  /// cannot cause (no participants, the same person twice, percent mixed with weights), and the
  /// editor's job is to make those unreachable rather than to catch them.
  SplitResolution? resolve(Money? total) {
    if (total == null || inputs.isEmpty) return null;
    try {
      return const SplitResolver().resolve(total: total, inputs: inputs);
    } on ArgumentError {
      return null;
    }
  }

  /// A copy with the supplied changes.
  SplitDraft copyWith({
    String? paidByPayeeId,
    SplitMethod? method,
    List<ShareInput>? inputs,
    String? groupId,
    bool clearGroup = false,
    DateKey? settleByDateKey,
    bool clearSettleBy = false,
  }) => SplitDraft(
    paidByPayeeId: paidByPayeeId ?? this.paidByPayeeId,
    method: method ?? this.method,
    inputs: inputs ?? this.inputs,
    groupId: clearGroup ? null : (groupId ?? this.groupId),
    settleByDateKey: clearSettleBy
        ? null
        : (settleByDateKey ?? this.settleByDateKey),
  );
}
