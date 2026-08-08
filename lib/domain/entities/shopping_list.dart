import 'package:alaya/core/time/date_key.dart';

/// A shopping list. Multiple are supported, with one marked default so the app still feels like it
/// has just one.
class ShoppingList {
  /// Creates a list.
  const ShoppingList({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.isArchived,
    this.targetDateKey,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name.
  final String name;

  /// Whether quick-add writes to this list when the user chooses none.
  ///
  /// Carries no database-level uniqueness constraint — the repository keeps it single by clearing
  /// every other list's flag in the same transaction it sets this one.
  final bool isDefault;

  /// Retired but kept for history.
  final bool isArchived;

  /// Optional civil date the user intends to shop on; surfaces on the calendar.
  final DateKey? targetDateKey;

  /// True when this list may be chosen in a picker.
  bool get isSelectable => !isArchived;

  /// Days from [today] until the shopping date — negative once past, null if none is set.
  int? daysUntilTarget(DateKey today) => targetDateKey?.diffDays(today);

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  ShoppingList copyWith({
    String? id,
    String? name,
    bool? isDefault,
    bool? isArchived,
    DateKey? targetDateKey,
  }) {
    return ShoppingList(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      isArchived: isArchived ?? this.isArchived,
      targetDateKey: targetDateKey ?? this.targetDateKey,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShoppingList &&
          other.id == id &&
          other.name == name &&
          other.isDefault == isDefault &&
          other.isArchived == isArchived &&
          other.targetDateKey == targetDateKey;

  @override
  int get hashCode => Object.hashAll([id, name, isDefault, isArchived, targetDateKey]);

  @override
  String toString() => 'ShoppingList($id, $name)';
}