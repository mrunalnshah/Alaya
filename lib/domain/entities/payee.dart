import 'package:alaya/core/enums/money_enums.dart';

/// The counterparty on a transaction, used for both `From` on deposits and `To` on withdrawals.
class Payee {
  /// Creates a payee.
  const Payee({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.kind,
    this.phone,
    this.note,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name as the user typed it.
  final String name;

  /// Normalised form used for identity matching only, never displayed.
  final String normalizedName;

  /// What kind of counterparty this is.
  final PayeeKind kind;

  /// Optional contact number.
  final String? phone;

  /// Optional free-text note.
  final String? note;

  /// True when a phone number is recorded, so the UI can offer a tappable dial action.
  bool get hasPhone => phone != null && phone!.isNotEmpty;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  Payee copyWith({
    String? id,
    String? name,
    String? normalizedName,
    PayeeKind? kind,
    String? phone,
    String? note,
  }) {
    return Payee(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      kind: kind ?? this.kind,
      phone: phone ?? this.phone,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Payee &&
          other.id == id &&
          other.name == name &&
          other.normalizedName == normalizedName &&
          other.kind == kind &&
          other.phone == phone &&
          other.note == note;

  @override
  int get hashCode => Object.hashAll([id, name, normalizedName, kind, phone, note]);

  @override
  String toString() => 'Payee($id, $name)';
}