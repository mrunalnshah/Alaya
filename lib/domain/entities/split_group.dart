import 'package:alaya/core/enums/split_enums.dart';

/// A recurring cast of people, with enough context to make a split findable later — `Goa trip`,
/// `Flat 402`, `Sunday football`.
///
/// **A label, not an account.** Nobody else logs in, nothing syncs, and no group belongs to anybody
/// but the one user (ARCH_4 §2.3's "no multi-user" stands). A group exists so a cast of people is
/// entered once and a split can be filed under something recognisable.
///
/// Occasion and place live on [SplitExpense], not here: one group has many occasions, and pinning
/// them to the group would make `Goa trip` and `Goa trip day 2` two groups.
class SplitGroup {
  /// Creates a group.
  const SplitGroup({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.defaultSplitMethod,
    this.members = const [],
    this.note,
    this.colorArgb,
    this.iconKey,
    this.isArchived = false,
    this.sortOrder = 0,
  });

  /// Row identifier.
  final String id;

  /// Display name.
  final String name;

  /// Casefolded, accent-stripped name for search and duplicate detection.
  ///
  /// Carried on the entity rather than computed in the repository, matching `Item`, `Payee`, `Recipe`
  /// and every other named row. The caller builds it with `Normalizer`, so one implementation decides
  /// what "the same name" means everywhere.
  final String normalizedName;

  /// Which split method this group offers first.
  ///
  /// Flatmates who always split rent 40/30/30 should not re-choose "by shares" every month.
  final SplitMethod defaultSplitMethod;

  /// The members, in display order.
  final List<SplitMember> members;

  /// Free-form note.
  final String? note;

  /// Optional ARGB colour.
  final int? colorArgb;

  /// Optional icon identifier.
  final String? iconKey;

  /// Retired but historical. Archived groups stay in totals and leave the pickers — the distinction
  /// from soft delete that ARCH_3 §4 exists to preserve.
  final bool isArchived;

  /// Manual ordering within pickers.
  final int sortOrder;

  /// Whether any member carries a weight of their own.
  ///
  /// What the editor checks before offering "by shares" as a starting point: a group where everybody
  /// splits equally has nothing to prefill.
  bool get hasDefaultWeights =>
      members.any((member) => member.defaultWeightBasisPoints != null);

  /// The members' default weights, or null when they do not all have one.
  ///
  /// Null rather than a partial map, because a split resolved from three weights and one absent one
  /// would silently treat the fourth person as weightless — which is a real instruction ("she did not
  /// eat") and must never be inferred from a missing value.
  Map<String, int>? get defaultWeightsByPayee {
    if (members.isEmpty) return null;
    final weights = <String, int>{};
    for (final member in members) {
      final weight = member.defaultWeightBasisPoints;
      if (weight == null) return null;
      weights[member.payeeId] = weight;
    }
    return weights;
  }
}

/// One person's standing membership of a [SplitGroup].
///
/// **People are payees.** That table already carries `kind ∈ {person, merchant, …}` with a phone and
/// a note, so a second `people` concept would be a second vocabulary for one thing — the duplication
/// ARCH_1 §3.1 spent three tables avoiding.
class SplitMember {
  /// Creates a membership.
  const SplitMember({
    required this.id,
    required this.groupId,
    required this.payeeId,
    this.defaultWeightBasisPoints,
    this.sortOrder = 0,
  });

  /// Row identifier.
  final String id;

  /// The group.
  final String groupId;

  /// The person, as a payee id.
  final String payeeId;

  /// This member's default weight within the group, in basis points, or null for an equal share.
  ///
  /// Basis points rather than a percentage so the stored value is an integer and Law L1 is never at
  /// risk. Nullable because most groups split equally, and storing `3333` three times would invite
  /// the question of why they do not sum to 10,000.
  final int? defaultWeightBasisPoints;

  /// Manual ordering within the group.
  final int sortOrder;
}
