import 'package:alaya/core/enums/money_enums.dart';

/// The rail money travelled on — `Cash`, `UPI`, `Card`, `Bank Transfer`, `Cheque`.
///
/// Metadata only: a payment method never holds a balance. That is an `Account`.
class PaymentMethod {
  /// Creates a payment method.
  const PaymentMethod({
    required this.id,
    required this.name,
    required this.kind,
    required this.isSystem,
    required this.sortOrder,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name as the user typed it.
  final String name;

  /// Which rail this represents.
  final PaymentMethodKind kind;

  /// Whether this method was seeded rather than user-created; system methods cannot be deleted.
  final bool isSystem;

  /// Manual ordering within pickers.
  final int sortOrder;

  /// True when the user is allowed to delete this method.
  bool get isDeletable => !isSystem;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  PaymentMethod copyWith({
    String? id,
    String? name,
    PaymentMethodKind? kind,
    bool? isSystem,
    int? sortOrder,
  }) {
    return PaymentMethod(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      isSystem: isSystem ?? this.isSystem,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PaymentMethod &&
          other.id == id &&
          other.name == name &&
          other.kind == kind &&
          other.isSystem == isSystem &&
          other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hashAll([id, name, kind, isSystem, sortOrder]);

  @override
  String toString() => 'PaymentMethod($id, $name)';
}