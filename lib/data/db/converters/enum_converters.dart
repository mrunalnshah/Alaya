import 'package:drift/drift.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/enums/safe_enum_converter.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';

/// Bridges Phase 1A's [SafeEnumConverter] into drift's [TypeConverter], so every enum column
/// in the schema stores `Enum.name` as `TEXT` and degrades an unrecognised value to a declared
/// fallback instead of throwing (Law L13).
///
/// Drift's own `textEnum()` column type is deliberately **not** used: it throws on a value
/// that matches no current member, which would make a database written by a newer build
/// unreadable by an older one. L13 requires the opposite behaviour.
///
/// Choosing a fallback is a real decision, not a formality — it is the value the app will show
/// for a row it cannot interpret. Two principles applied throughout below: prefer the member
/// that **understates** rather than overstates (money and stock), and never pick a member whose
/// meaning is "already handled" (`paid`, `disposed`, `dismissed`), because silently marking an
/// obligation settled is the one failure a user cannot detect.
abstract class SafeEnumTypeConverter<T extends Enum> extends TypeConverter<T, String> {
  /// Creates the converter.
  const SafeEnumTypeConverter();

  /// The Phase 1A converter holding this enum's members and its fallback.
  SafeEnumConverter<T> get delegate;

  @override
  T fromSql(String fromDb) => delegate.fromSql(fromDb);

  @override
  String toSql(T value) => delegate.toSql(value);
}

// ── Money ────────────────────────────────────────────────────────────────────────────────

/// Stores [TransactionKind]. Falls back to [TransactionKind.withdrawal]: it is the only choice
/// that understates available funds, and an unreadable `kind` must never inflate a balance.
final class TransactionKindConverter extends SafeEnumTypeConverter<TransactionKind> {
  /// Creates the converter.
  const TransactionKindConverter();

  @override
  SafeEnumConverter<TransactionKind> get delegate =>
      const SafeEnumConverter(TransactionKind.values, TransactionKind.withdrawal);
}

/// Stores [TransactionSubtype]. Falls back to [TransactionSubtype.otherOut], the catch-all
/// outflow bucket.
final class TransactionSubtypeConverter extends SafeEnumTypeConverter<TransactionSubtype> {
  /// Creates the converter.
  const TransactionSubtypeConverter();

  @override
  SafeEnumConverter<TransactionSubtype> get delegate =>
      const SafeEnumConverter(TransactionSubtype.values, TransactionSubtype.otherOut);
}

/// Stores [AccountKind]. Falls back to [AccountKind.other].
final class AccountKindConverter extends SafeEnumTypeConverter<AccountKind> {
  /// Creates the converter.
  const AccountKindConverter();

  @override
  SafeEnumConverter<AccountKind> get delegate =>
      const SafeEnumConverter(AccountKind.values, AccountKind.other);
}

/// Stores [PaymentMethodKind]. Falls back to [PaymentMethodKind.other].
final class PaymentMethodKindConverter extends SafeEnumTypeConverter<PaymentMethodKind> {
  /// Creates the converter.
  const PaymentMethodKindConverter();

  @override
  SafeEnumConverter<PaymentMethodKind> get delegate =>
      const SafeEnumConverter(PaymentMethodKind.values, PaymentMethodKind.other);
}

/// Stores [PayeeKind]. Falls back to [PayeeKind.other].
final class PayeeKindConverter extends SafeEnumTypeConverter<PayeeKind> {
  /// Creates the converter.
  const PayeeKindConverter();

  @override
  SafeEnumConverter<PayeeKind> get delegate =>
      const SafeEnumConverter(PayeeKind.values, PayeeKind.other);
}

/// Stores [TransactionLineDestination]. Falls back to [TransactionLineDestination.none] —
/// claiming a line produced no artefact is safe, whereas claiming it produced one would send
/// the fan-out service looking for a batch or asset that does not exist.
final class TransactionLineDestinationConverter
    extends SafeEnumTypeConverter<TransactionLineDestination> {
  /// Creates the converter.
  const TransactionLineDestinationConverter();

  @override
  SafeEnumConverter<TransactionLineDestination> get delegate => const SafeEnumConverter(
    TransactionLineDestination.values,
    TransactionLineDestination.none,
  );
}

// ── Quantity ─────────────────────────────────────────────────────────────────────────────

/// Stores [UnitCategory]. Falls back to [UnitCategory.count], the only category the formatter
/// never decomposes into a big/small unit pair, so a misread category cannot render a
/// nonsensical `"4 kg 450 g"` for something that was never a weight.
final class UnitCategoryConverter extends SafeEnumTypeConverter<UnitCategory> {
  /// Creates the converter.
  const UnitCategoryConverter();

  @override
  SafeEnumConverter<UnitCategory> get delegate =>
      const SafeEnumConverter(UnitCategory.values, UnitCategory.count);
}

// ── Inventory ────────────────────────────────────────────────────────────────────────────

/// Stores [ItemKind]. Falls back to [ItemKind.generic], the declared "no classification" value.
final class ItemKindConverter extends SafeEnumTypeConverter<ItemKind> {
  /// Creates the converter.
  const ItemKindConverter();

  @override
  SafeEnumConverter<ItemKind> get delegate =>
      const SafeEnumConverter(ItemKind.values, ItemKind.generic);
}

/// Stores [BatchOrigin]. Falls back to [BatchOrigin.manual] — a neutral provenance that claims
/// no link to a transaction, so nothing downstream tries to follow a source that isn't there.
final class BatchOriginConverter extends SafeEnumTypeConverter<BatchOrigin> {
  /// Creates the converter.
  const BatchOriginConverter();

  @override
  SafeEnumConverter<BatchOrigin> get delegate =>
      const SafeEnumConverter(BatchOrigin.values, BatchOrigin.manual);
}

/// Stores [StockMovementKind]. Falls back to [StockMovementKind.adjustOut].
///
/// This fallback is the most consequential in the schema, because an unreadable movement kind
/// means the *direction* of a stock change is unknown. `adjustOut` is chosen for two reasons:
/// it understates stock (the user re-adds food rather than trusting food they do not have), and
/// it is not `waste` or `expired`, so the food-waste analytics in ARCH_3 §5.1 query 14 stay
/// honest rather than absorbing unclassifiable rows.
final class StockMovementKindConverter extends SafeEnumTypeConverter<StockMovementKind> {
  /// Creates the converter.
  const StockMovementKindConverter();

  @override
  SafeEnumConverter<StockMovementKind> get delegate =>
      const SafeEnumConverter(StockMovementKind.values, StockMovementKind.adjustOut);
}

// ── Shopping ─────────────────────────────────────────────────────────────────────────────

/// Stores [ShoppingEntryOrigin]. Falls back to [ShoppingEntryOrigin.manual], which the
/// suggestion engine never auto-removes — losing a user's own entry is worse than keeping a
/// stale generated one.
final class ShoppingEntryOriginConverter extends SafeEnumTypeConverter<ShoppingEntryOrigin> {
  /// Creates the converter.
  const ShoppingEntryOriginConverter();

  @override
  SafeEnumConverter<ShoppingEntryOrigin> get delegate =>
      const SafeEnumConverter(ShoppingEntryOrigin.values, ShoppingEntryOrigin.manual);
}

/// Stores [ShoppingEntryAutoState]. Falls back to [ShoppingEntryAutoState.active] — a visible
/// entry the user can dismiss, rather than a hidden one they cannot discover.
final class ShoppingEntryAutoStateConverter
    extends SafeEnumTypeConverter<ShoppingEntryAutoState> {
  /// Creates the converter.
  const ShoppingEntryAutoStateConverter();

  @override
  SafeEnumConverter<ShoppingEntryAutoState> get delegate => const SafeEnumConverter(
    ShoppingEntryAutoState.values,
    ShoppingEntryAutoState.active,
  );
}

// ── Recurring ────────────────────────────────────────────────────────────────────────────

/// Stores [RecurringKind]. Falls back to [RecurringKind.other].
final class RecurringKindConverter extends SafeEnumTypeConverter<RecurringKind> {
  /// Creates the converter.
  const RecurringKindConverter();

  @override
  SafeEnumConverter<RecurringKind> get delegate =>
      const SafeEnumConverter(RecurringKind.values, RecurringKind.other);
}

/// Stores [RecurringDirection]. Falls back to [RecurringDirection.outflow]: presenting an
/// unreadable obligation as something owed is safer than presenting it as income.
final class RecurringDirectionConverter extends SafeEnumTypeConverter<RecurringDirection> {
  /// Creates the converter.
  const RecurringDirectionConverter();

  @override
  SafeEnumConverter<RecurringDirection> get delegate =>
      const SafeEnumConverter(RecurringDirection.values, RecurringDirection.outflow);
}

/// Stores [RecurringIntervalUnit]. Falls back to [RecurringIntervalUnit.month], by far the most
/// common real interval, so a misread row lands on the most probable schedule and the user can
/// see and correct it on the template screen.
final class RecurringIntervalUnitConverter extends SafeEnumTypeConverter<RecurringIntervalUnit> {
  /// Creates the converter.
  const RecurringIntervalUnitConverter();

  @override
  SafeEnumConverter<RecurringIntervalUnit> get delegate => const SafeEnumConverter(
    RecurringIntervalUnit.values,
    RecurringIntervalUnit.month,
  );
}

/// Stores [RecurringOccurrenceStatus]. Falls back to [RecurringOccurrenceStatus.due], never
/// `paid` — silently reporting a bill as settled is the one degradation a user cannot notice
/// until it costs them a late fee.
final class RecurringOccurrenceStatusConverter
    extends SafeEnumTypeConverter<RecurringOccurrenceStatus> {
  /// Creates the converter.
  const RecurringOccurrenceStatusConverter();

  @override
  SafeEnumConverter<RecurringOccurrenceStatus> get delegate => const SafeEnumConverter(
    RecurringOccurrenceStatus.values,
    RecurringOccurrenceStatus.due,
  );
}

// ── Service ──────────────────────────────────────────────────────────────────────────────

/// Stores [AssetType]. Falls back to [AssetType.other].
final class AssetTypeConverter extends SafeEnumTypeConverter<AssetType> {
  /// Creates the converter.
  const AssetTypeConverter();

  @override
  SafeEnumConverter<AssetType> get delegate =>
      const SafeEnumConverter(AssetType.values, AssetType.other);
}

/// Stores [AssetStatus]. Falls back to [AssetStatus.active], never `disposed` — an asset must
/// never disappear from the user's list because one column could not be read.
final class AssetStatusConverter extends SafeEnumTypeConverter<AssetStatus> {
  /// Creates the converter.
  const AssetStatusConverter();

  @override
  SafeEnumConverter<AssetStatus> get delegate =>
      const SafeEnumConverter(AssetStatus.values, AssetStatus.active);
}

/// Stores [AssetDisposalReason]. Falls back to [AssetDisposalReason.other].
final class AssetDisposalReasonConverter extends SafeEnumTypeConverter<AssetDisposalReason> {
  /// Creates the converter.
  const AssetDisposalReasonConverter();

  @override
  SafeEnumConverter<AssetDisposalReason> get delegate =>
      const SafeEnumConverter(AssetDisposalReason.values, AssetDisposalReason.other);
}

/// Stores [ServiceRecordType]. Falls back to [ServiceRecordType.other].
final class ServiceRecordTypeConverter extends SafeEnumTypeConverter<ServiceRecordType> {
  /// Creates the converter.
  const ServiceRecordTypeConverter();

  @override
  SafeEnumConverter<ServiceRecordType> get delegate =>
      const SafeEnumConverter(ServiceRecordType.values, ServiceRecordType.other);
}

// ── Ops ──────────────────────────────────────────────────────────────────────────────────

/// Stores [NotificationKind]. Falls back to [NotificationKind.expiry]. Low stakes: these rows
/// are transient scheduling records, rebuilt by the daily job in Phase 8B.
final class NotificationKindConverter extends SafeEnumTypeConverter<NotificationKind> {
  /// Creates the converter.
  const NotificationKindConverter();

  @override
  SafeEnumConverter<NotificationKind> get delegate =>
      const SafeEnumConverter(NotificationKind.values, NotificationKind.expiry);
}

/// Stores [NotificationStatus]. Falls back to [NotificationStatus.cancelled], so a row whose
/// state cannot be read is never re-fired at the user.
final class NotificationStatusConverter extends SafeEnumTypeConverter<NotificationStatus> {
  /// Creates the converter.
  const NotificationStatusConverter();

  @override
  SafeEnumConverter<NotificationStatus> get delegate =>
      const SafeEnumConverter(NotificationStatus.values, NotificationStatus.cancelled);
}

/// Stores [BackupKind]. Falls back to [BackupKind.manual].
final class BackupKindConverter extends SafeEnumTypeConverter<BackupKind> {
  /// Creates the converter.
  const BackupKindConverter();

  @override
  SafeEnumConverter<BackupKind> get delegate =>
      const SafeEnumConverter(BackupKind.values, BackupKind.manual);
}
