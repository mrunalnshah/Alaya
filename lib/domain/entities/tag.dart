import 'package:alaya/core/enums/tag_scope.dart';

/// A free user-defined label, scoped by which modules may use it.
///
/// Distinct from a transaction's `subtype`, which is a closed enum because it changes the editor
/// form and must stay stable for analytics. Tags are open because nobody can enumerate what a user
/// in Ahmedabad, Osaka and Lisbon will call things — they are not redundant with each other
/// (ARCH_1 §3.1).
class Tag {
  /// Creates a tag.
  const Tag({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.allowedScopes,
    required this.isSystem,
    required this.sortOrder,
    required this.isDeleted,
    this.colorArgb,
    this.iconKey,
    this.parentTagId,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name as the user typed it.
  final String name;

  /// Normalised form used for identity matching only, never displayed.
  final String normalizedName;

  /// Which module pickers offer this tag.
  ///
  /// A set rather than six booleans: the six `allowedIn*` columns are one concept, and a set makes
  /// [isAllowedIn] a single containment check instead of a switch that can select the wrong
  /// column — the mistake that would put `Kitchen` in the deposit picker (ARCH_2 §14).
  final Set<TagScope> allowedScopes;

  /// Whether this tag was seeded; system tags cannot be deleted.
  final bool isSystem;

  /// Manual ordering within pickers.
  final int sortOrder;

  /// Whether this tag has been soft-deleted.
  ///
  /// Present on this entity alone among the 21, deliberately. A deleted tag keeps its links so
  /// history stays readable, and the UI renders it greyed with `(deleted)` (anomaly A36) — so the
  /// flag is genuinely display state here, not the persistence detail it is everywhere else.
  final bool isDeleted;

  /// Optional ARGB colour for the chip.
  final int? colorArgb;

  /// Optional icon identifier.
  final String? iconKey;

  /// Parent tag, permitting exactly one level of nesting (`Grocery > Vegetables`).
  final String? parentTagId;

  /// True when this tag is offered in [scope]'s picker.
  bool isAllowedIn(TagScope scope) => allowedScopes.contains(scope);

  /// True when this tag is nested under another.
  bool get isChild => parentTagId != null;

  /// True when the user is allowed to delete this tag.
  bool get isDeletable => !isSystem;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  Tag copyWith({
    String? id,
    String? name,
    String? normalizedName,
    Set<TagScope>? allowedScopes,
    bool? isSystem,
    int? sortOrder,
    bool? isDeleted,
    int? colorArgb,
    String? iconKey,
    String? parentTagId,
  }) {
    return Tag(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      allowedScopes: allowedScopes ?? this.allowedScopes,
      isSystem: isSystem ?? this.isSystem,
      sortOrder: sortOrder ?? this.sortOrder,
      isDeleted: isDeleted ?? this.isDeleted,
      colorArgb: colorArgb ?? this.colorArgb,
      iconKey: iconKey ?? this.iconKey,
      parentTagId: parentTagId ?? this.parentTagId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Tag &&
          other.id == id &&
          other.name == name &&
          other.normalizedName == normalizedName &&
          _sameScopes(other.allowedScopes) &&
          other.isSystem == isSystem &&
          other.sortOrder == sortOrder &&
          other.isDeleted == isDeleted &&
          other.colorArgb == colorArgb &&
          other.iconKey == iconKey &&
          other.parentTagId == parentTagId;

  bool _sameScopes(Set<TagScope> other) =>
      other.length == allowedScopes.length && other.containsAll(allowedScopes);

  @override
  int get hashCode => Object.hashAll([
    id, name, normalizedName,
    // Order-independent, so two equal sets built in different orders hash alike.
    Object.hashAllUnordered(allowedScopes),
    isSystem, sortOrder, isDeleted, colorArgb, iconKey, parentTagId,
  ]);

  @override
  String toString() => 'Tag($id, $name${isDeleted ? ' (deleted)' : ''})';
}