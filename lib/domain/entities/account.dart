import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// A container that holds money and has a balance — `Cash in hand`, `HDFC Savings`.
///
/// Distinct from a `PaymentMethod` (the rail money travelled on) and a `Payee` (the counterparty).
/// Collapsing those three into one list is anomaly A01, and it is what makes "Total Available
/// Funds" unanswerable.
class Account {
  /// Creates an account.
  const Account({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.kind,
    required this.currencyCode,
    required this.openingBalance,
    required this.openingBalanceDateKey,
    required this.isArchived,
    required this.includeInNetWorth,
    required this.sortOrder,
    this.colorArgb,
    this.iconKey,
  });

  /// Identifier, UUIDv7.
  final String id;

  /// Display name as the user typed it.
  final String name;

  /// Normalised form used for identity matching only, never displayed.
  final String normalizedName;

  /// What kind of container this is.
  final AccountKind kind;

  /// The single currency this account is denominated in.
  final String currencyCode;

  /// Balance already present when tracking began (anomaly A03).
  final Money openingBalance;

  /// The civil date [openingBalance] was true on.
  final DateKey openingBalanceDateKey;

  /// Retired but historical.
  ///
  /// An archived account still counts toward totals and net worth — it has only left the pickers.
  /// That is the distinction from deletion which ARCH_3 §4 exists to preserve: a closed bank
  /// account with ₹0 is archived, a duplicate transaction is deleted.
  final bool isArchived;

  /// Whether this account contributes to the net-worth headline.
  final bool includeInNetWorth;

  /// Manual ordering within pickers.
  final int sortOrder;

  /// Optional ARGB colour.
  final int? colorArgb;

  /// Optional icon identifier.
  final String? iconKey;

  /// True when this account may be chosen in a picker.
  bool get isSelectable => !isArchived;

  /// A copy with the given fields replaced. See [Currency.copyWith] on clearing nullables.
  Account copyWith({
    String? id,
    String? name,
    String? normalizedName,
    AccountKind? kind,
    String? currencyCode,
    Money? openingBalance,
    DateKey? openingBalanceDateKey,
    bool? isArchived,
    bool? includeInNetWorth,
    int? sortOrder,
    int? colorArgb,
    String? iconKey,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      kind: kind ?? this.kind,
      currencyCode: currencyCode ?? this.currencyCode,
      openingBalance: openingBalance ?? this.openingBalance,
      openingBalanceDateKey: openingBalanceDateKey ?? this.openingBalanceDateKey,
      isArchived: isArchived ?? this.isArchived,
      includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
      sortOrder: sortOrder ?? this.sortOrder,
      colorArgb: colorArgb ?? this.colorArgb,
      iconKey: iconKey ?? this.iconKey,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Account &&
          other.id == id &&
          other.name == name &&
          other.normalizedName == normalizedName &&
          other.kind == kind &&
          other.currencyCode == currencyCode &&
          other.openingBalance == openingBalance &&
          other.openingBalanceDateKey == openingBalanceDateKey &&
          other.isArchived == isArchived &&
          other.includeInNetWorth == includeInNetWorth &&
          other.sortOrder == sortOrder &&
          other.colorArgb == colorArgb &&
          other.iconKey == iconKey;

  @override
  int get hashCode => Object.hashAll([
    id, name, normalizedName, kind, currencyCode, openingBalance,
    openingBalanceDateKey, isArchived, includeInNetWorth, sortOrder, colorArgb, iconKey,
  ]);

  @override
  String toString() => 'Account($id, $name)';
}