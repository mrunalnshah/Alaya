import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/services/date_range_service.dart';

/// What is currently narrowing the transaction list.
///
/// Immutable, and every field is one the user can see as a chip. A filter the user cannot see is a
/// bug report waiting to happen: a list quietly constrained by a filter set on a previous visit is
/// indistinguishable from a list that lost its data (ARCH_5 §3 archetype C).
///
/// **There is deliberately no tag field.** No 3A contract exposes a tag-to-transactions reverse
/// lookup, so filtering by tag would mean one query per visible row. Recorded as an ARCH_5 §7.3 gap
/// owned by 7B, which builds the analytics read model that needs the same join.
class TransactionFilter {
  /// Creates a filter. The default is the last thirty days, unfiltered otherwise.
  const TransactionFilter({
    this.preset = DateRangePreset.last30Days,
    this.customRange,
    this.kinds = const <TransactionKind>{},
    this.subtypes = const <TransactionSubtype>{},
    this.accountId,
    this.payeeId,
    this.needsReviewOnly = false,
  });

  /// The reporting window, resolved against the clock by `DateRangeService`.
  final DateRangePreset preset;

  /// The window the user picked by hand. Only meaningful when [preset] is custom.
  final DateRange? customRange;

  /// Which kinds to show. Empty means all of them.
  final Set<TransactionKind> kinds;

  /// Which subtypes to show. Empty means all of them.
  final Set<TransactionSubtype> subtypes;

  /// Restrict to transactions touching this account on either side.
  final String? accountId;

  /// Restrict to one counterparty.
  final String? payeeId;

  /// Show only transactions still flagged as needing details.
  ///
  /// What the needs-review nudge switches on. Without it the banner would have nowhere real to
  /// send the user: widening the date window shows the flagged rows *somewhere* in the list rather
  /// than showing the user the work they were just told they had.
  final bool needsReviewOnly;

  /// Whether anything is narrowing the list beyond the default window.
  bool get isNarrowed =>
      preset != DateRangePreset.last30Days ||
      kinds.isNotEmpty ||
      subtypes.isNotEmpty ||
      accountId != null ||
      payeeId != null ||
      needsReviewOnly;

  /// True when [transaction] survives the non-date parts of this filter.
  ///
  /// The date window is applied by the query rather than here — `watchByDateRange` is indexed and
  /// re-filtering its output by date in Dart would be doing the work twice.
  bool admits({
    required TransactionKind kind,
    required TransactionSubtype subtype,
    required String? fromAccountId,
    required String? toAccountId,
    required String? transactionPayeeId,
    required bool needsReview,
  }) {
    if (needsReviewOnly && !needsReview) return false;
    if (kinds.isNotEmpty && !kinds.contains(kind)) return false;
    if (subtypes.isNotEmpty && !subtypes.contains(subtype)) return false;
    if (accountId != null &&
        fromAccountId != accountId &&
        toAccountId != accountId)
      return false;
    if (payeeId != null && transactionPayeeId != payeeId) return false;
    return true;
  }

  /// Returns a copy with the supplied changes.
  ///
  /// The nullable fields take an explicit `clear` flag rather than relying on a null argument, which
  /// would be indistinguishable from "leave it alone" and is the standard way a copyWith quietly
  /// refuses to let a user clear a filter.
  TransactionFilter copyWith({
    DateRangePreset? preset,
    DateRange? customRange,
    bool clearCustomRange = false,
    Set<TransactionKind>? kinds,
    Set<TransactionSubtype>? subtypes,
    String? accountId,
    bool clearAccount = false,
    String? payeeId,
    bool clearPayee = false,
    bool? needsReviewOnly,
  }) => TransactionFilter(
    preset: preset ?? this.preset,
    customRange: clearCustomRange ? null : (customRange ?? this.customRange),
    kinds: kinds ?? this.kinds,
    subtypes: subtypes ?? this.subtypes,
    accountId: clearAccount ? null : (accountId ?? this.accountId),
    payeeId: clearPayee ? null : (payeeId ?? this.payeeId),
    needsReviewOnly: needsReviewOnly ?? this.needsReviewOnly,
  );

  @override
  bool operator ==(Object other) =>
      other is TransactionFilter &&
      other.preset == preset &&
      other.customRange == customRange &&
      other.kinds.length == kinds.length &&
      other.kinds.containsAll(kinds) &&
      other.subtypes.length == subtypes.length &&
      other.subtypes.containsAll(subtypes) &&
      other.accountId == accountId &&
      other.payeeId == payeeId &&
      other.needsReviewOnly == needsReviewOnly;

  @override
  int get hashCode => Object.hash(
    preset,
    customRange,
    Object.hashAllUnordered(kinds),
    Object.hashAllUnordered(subtypes),
    accountId,
    payeeId,
    needsReviewOnly,
  );
}
