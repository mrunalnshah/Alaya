import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// Why a payment was refused, when it was refused for a reason worth naming.
enum PayIssue {
  /// No amount, or a non-positive one.
  amountMissing,

  /// No account chosen, and the template had no default.
  accountMissing,

  /// The write failed for a reason the repository named.
  rejected,
}

/// What the pay sheet is holding (ARCH_5 §3 archetype A).
///
/// **The default and the actual are two different figures and both are kept.** A bill quoted at
/// ₹1,200 that arrives at ₹1,247 is the normal case, not an error — the sheet pre-fills the default so
/// the common path is one tap, and stores what was actually paid so the history can show the gap.
class PayState {
  /// Creates the sheet's state.
  const PayState({
    required this.occurrenceId,
    required this.defaultAmount,
    required this.paidOn,
    this.amount,
    this.accountId,
    this.paymentMethodId,
    this.note,
    this.submitting = false,
    this.issue,
    this.rejection,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// Which occurrence is being settled.
  final String occurrenceId;

  /// What the template says it usually is.
  final Money defaultAmount;

  /// What is actually being paid, pre-filled from [defaultAmount].
  final Money? amount;

  /// When.
  final DateKey paidOn;

  /// Which account it came from, or goes into.
  final String? accountId;

  /// How it was paid.
  final String? paymentMethodId;

  /// Free note.
  final String? note;

  /// Whether a commit is in flight.
  final bool submitting;

  /// Why the last commit was refused, or null if it was not.
  final PayIssue? issue;

  /// The repository's own message when it rejected the write.
  final String? rejection;

  /// Incremented to shake the offending field.
  final int shakeTrigger;

  /// Whether anything was touched, for the dismiss guard (Law U10).
  final bool dirty;

  /// Whether the actual figure differs from the usual one, which is what the history highlights.
  bool get differsFromDefault {
    final actual = amount;
    return actual != null && actual != defaultAmount;
  }

  /// Returns a copy with the supplied changes.
  ///
  /// `issue` and `rejection` survive an unrelated `copyWith` — a bare assignment lets the
  /// `submitting: false` in a `finally` erase the reason before the sheet reads it (ARCH_4 R31).
  PayState copyWith({
    Money? amount,
    DateKey? paidOn,
    String? accountId,
    String? paymentMethodId,
    String? note,
    bool? submitting,
    PayIssue? issue,
    String? rejection,
    bool clearIssue = false,
    int? shakeTrigger,
    bool? dirty,
  }) => PayState(
    occurrenceId: occurrenceId,
    defaultAmount: defaultAmount,
    amount: amount ?? this.amount,
    paidOn: paidOn ?? this.paidOn,
    accountId: accountId ?? this.accountId,
    paymentMethodId: paymentMethodId ?? this.paymentMethodId,
    note: note ?? this.note,
    submitting: submitting ?? this.submitting,
    issue: clearIssue ? null : (issue ?? this.issue),
    rejection: clearIssue ? null : (rejection ?? this.rejection),
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? this.dirty,
  );
}
