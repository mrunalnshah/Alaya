import 'package:drift/drift.dart';

import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/converters/money_converter.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/domain/entities/split_read_models.dart';

/// Maps split rows to domain entities and back.
///
/// Uses `MoneyColumns` rather than a drift `TypeConverter` because `Money` spans two sibling columns
/// — an amount and the row's own `currencyCode` — which `money_converter.dart`'s class doc explains no
/// converter can do.
///
/// **The view mappers are where the nullability lives.** `SUM()` in SQL yields null, so every summed
/// column arrives as `int?` even where a join guarantees rows. Each one below states whether null
/// means zero or means *unknown*, because for `myShareMinor` those are different facts and collapsing
/// them would show ₹0 owed on a fresh install where the truth is "not configured yet".

// ── groups ────────────────────────────────────────────────────────────────────────────────

/// Maps group member rows.
extension SplitMemberMapper on SplitMemberRow {
  /// Maps this row to a domain entity.
  SplitMember toEntity() => SplitMember(
    id: id,
    groupId: groupId,
    payeeId: payeeId,
    defaultWeightBasisPoints: defaultWeightBasisPoints,
    sortOrder: sortOrder,
  );
}

/// Maps group header rows.
extension SplitGroupMapper on SplitGroupRow {
  /// Maps this row plus its already-loaded [members] to a domain entity.
  ///
  /// The members are passed in rather than fetched here, matching `RecipeMapper`: a mapper that
  /// queried would make every list row a database round trip, and this extension has no database to
  /// query with.
  SplitGroup toEntity({required List<SplitMember> members}) => SplitGroup(
    id: id,
    name: name,
    normalizedName: normalizedName,
    defaultSplitMethod: defaultSplitMethod,
    members: members,
    note: note,
    colorArgb: colorArgb,
    iconKey: iconKey,
    isArchived: isArchived,
    sortOrder: sortOrder,
  );
}

/// Builds the companion for [group].
SplitGroupsCompanion splitGroupToCompanion(
  SplitGroup group, {
  required int createdAt,
  required int updatedAt,
}) => SplitGroupsCompanion.insert(
  id: group.id,
  name: group.name,
  normalizedName: group.normalizedName,
  defaultSplitMethod: group.defaultSplitMethod,
  isArchived: group.isArchived,
  sortOrder: group.sortOrder,
  note: Value(group.note),
  colorArgb: Value(group.colorArgb),
  iconKey: Value(group.iconKey),
  createdAt: createdAt,
  updatedAt: updatedAt,
);

/// Builds the companion for [member].
SplitMembersCompanion splitMemberToCompanion(
  SplitMember member, {
  required int createdAt,
  required int updatedAt,
}) => SplitMembersCompanion.insert(
  id: member.id,
  groupId: member.groupId,
  payeeId: member.payeeId,
  sortOrder: member.sortOrder,
  defaultWeightBasisPoints: Value(member.defaultWeightBasisPoints),
  createdAt: createdAt,
  updatedAt: updatedAt,
);

// ── expenses ──────────────────────────────────────────────────────────────────────────────

/// Maps share rows.
extension SplitShareMapper on SplitShareRow {
  /// Maps this row to a domain entity.
  ///
  /// [currencyCode] comes from the parent expense, because a share row stores an amount and no
  /// currency — the same arrangement `RecipeIngredientMapper` has with `UnitCategory`, and for the
  /// same reason: the fact lives on the parent and a mapper must not invent one it cannot know.
  SplitShare toEntity({required String currencyCode}) => SplitShare(
    id: id,
    splitExpenseId: splitExpenseId,
    payeeId: payeeId,
    amount: MoneyColumns.read(shareAmountMinor, currencyCode),
    inputKind: inputKind,
    inputValue: inputValue,
    transactionLineNo: transactionLineNo,
  );
}

/// Maps expense header rows.
extension SplitExpenseMapper on SplitExpenseRow {
  /// Maps this row plus its already-loaded [shares] to a domain entity.
  SplitExpense toEntity({required List<SplitShare> shares}) => SplitExpense(
    id: id,
    paidByPayeeId: paidByPayeeId,
    total: MoneyColumns.read(totalAmountMinor, currencyCode),
    dateKey: dateKey,
    splitMethod: splitMethod,
    shares: shares,
    groupId: groupId,
    transactionId: transactionId,
    title: title,
    place: place,
    occasion: occasion,
    note: note,
    settleByDateKey: settleByDateKey,
    // `readNullable` throws on a half-populated pair rather than guessing, so a converted amount
    // without its currency surfaces here instead of as a wrong number on a dashboard.
    converted: _conversionOf(this),
  );
}

SplitConversion? _conversionOf(SplitExpenseRow row) {
  final amount = MoneyColumns.readNullable(
    row.convertedAmountMinor,
    row.convertedCurrencyCode,
  );
  final rate = row.conversionRate;
  final rateRaw = row.conversionRateRaw;
  final on = row.conversionDateKey;
  // All four move together or none does. A rate without an amount, or an amount without the date it
  // was valid on, is a snapshot that cannot be explained — and Law L9's whole point is that a frozen
  // conversion stays explainable years later.
  if (amount == null || rate == null || rateRaw == null || on == null) {
    return null;
  }
  return SplitConversion(
    amount: amount,
    rate: rate,
    rateRaw: rateRaw,
    dateKey: on,
  );
}

/// Builds the companion for [expense].
SplitExpensesCompanion splitExpenseToCompanion(
  SplitExpense expense, {
  required int createdAt,
  required int updatedAt,
}) => SplitExpensesCompanion.insert(
  id: expense.id,
  paidByPayeeId: expense.paidByPayeeId,
  totalAmountMinor: MoneyColumns.minorOf(expense.total),
  currencyCode: MoneyColumns.codeOf(expense.total),
  dateKey: expense.dateKey,
  // Derived on the entity, and the schema's `CHECK (date_key / 100 = month_key)` rejects a caller
  // that computes it differently — the same arrangement `transactions` uses.
  monthKey: expense.monthKey,
  splitMethod: expense.splitMethod,
  groupId: Value(expense.groupId),
  transactionId: Value(expense.transactionId),
  title: Value(expense.title),
  place: Value(expense.place),
  occasion: Value(expense.occasion),
  note: Value(expense.note),
  settleByDateKey: Value(expense.settleByDateKey),
  convertedAmountMinor: Value(
    MoneyColumns.minorOfNullable(expense.converted?.amount),
  ),
  convertedCurrencyCode: Value(
    MoneyColumns.codeOfNullable(expense.converted?.amount),
  ),
  conversionRate: Value(expense.converted?.rate),
  conversionRateRaw: Value(expense.converted?.rateRaw),
  conversionDateKey: Value(expense.converted?.dateKey),
  createdAt: createdAt,
  updatedAt: updatedAt,
);

/// Builds the companion for [share].
SplitSharesCompanion splitShareToCompanion(
  SplitShare share, {
  required int createdAt,
  required int updatedAt,
}) => SplitSharesCompanion.insert(
  id: share.id,
  splitExpenseId: share.splitExpenseId,
  payeeId: share.payeeId,
  shareAmountMinor: MoneyColumns.minorOf(share.amount),
  inputKind: share.inputKind,
  inputValue: Value(share.inputValue),
  transactionLineNo: Value(share.transactionLineNo),
  createdAt: createdAt,
  updatedAt: updatedAt,
);

// ── settlements ───────────────────────────────────────────────────────────────────────────

/// Maps settlement rows.
extension SplitSettlementMapper on SplitSettlementRow {
  /// Maps this row to a domain entity.
  SplitSettlement toEntity() => SplitSettlement(
    id: id,
    fromPayeeId: fromPayeeId,
    toPayeeId: toPayeeId,
    amount: MoneyColumns.read(amountMinor, currencyCode),
    dateKey: dateKey,
    groupId: groupId,
    transactionId: transactionId,
    paymentMethodId: paymentMethodId,
    note: note,
  );
}

/// Builds the companion for [settlement].
SplitSettlementsCompanion splitSettlementToCompanion(
  SplitSettlement settlement, {
  required int createdAt,
  required int updatedAt,
}) => SplitSettlementsCompanion.insert(
  id: settlement.id,
  fromPayeeId: settlement.fromPayeeId,
  toPayeeId: settlement.toPayeeId,
  amountMinor: MoneyColumns.minorOf(settlement.amount),
  currencyCode: MoneyColumns.codeOf(settlement.amount),
  dateKey: settlement.dateKey,
  monthKey: settlement.monthKey,
  groupId: Value(settlement.groupId),
  transactionId: Value(settlement.transactionId),
  paymentMethodId: Value(settlement.paymentMethodId),
  note: Value(settlement.note),
  createdAt: createdAt,
  updatedAt: updatedAt,
);

// ── views ─────────────────────────────────────────────────────────────────────────────────
//
// **A view column keeps the type converter of the table column it selects.** `v_split_expenses`
// selects `split_expenses.date_key` straight through, so it arrives as a `DateKey` rather than an
// `int` — and wrapping it in `DateKey(...)` here was four compile errors, because the converter had
// already run.
//
// That is not in tension with `SplitViewDao` passing plain ints to `isBetweenValues`: drift's
// comparison operators work on a column's **SQL** type even with a converter attached, while reading
// a row yields the **Dart** type. `recipe_dao.dart` records the same asymmetry from the other side,
// where it forced `date_key_filters.dart` into existence.

/// Maps `v_split_expenses` rows.
extension SplitExpenseSummaryMapper on SplitExpenseSummaryRow {
  /// Maps this row to a read model.
  SplitExpenseSummary toEntity() => SplitExpenseSummary(
    splitExpenseId: splitExpenseId,
    total: MoneyColumns.read(totalAmountMinor, currencyCode),
    // `COALESCE(..., 0)` in the view means this is never null in practice, but drift types a summed
    // column nullable regardless. Zero is the honest default here: no shares means nothing allocated.
    allocated: MoneyColumns.read(allocatedMinor ?? 0, currencyCode),
    dateKey: dateKey,
    paidByPayeeId: paidByPayeeId,
    shareCount: shareCount ?? 0,
    groupId: groupId,
    transactionId: transactionId,
    title: title,
    place: place,
    occasion: occasion,
    settleByDateKey: settleByDateKey,
    // **Null is passed through, not defaulted, and this is the one place that matters.** The view's
    // self-share subquery joins `app_settings` on `split.selfPayeeId`; with no such setting the join
    // finds nothing and the column is null. `?? 0` here would render "your share: ₹0" on a fresh
    // install, which reads as "you owe nothing" when the truth is that the app does not yet know who
    // you are.
    myShare: myShareMinor == null
        ? null
        : MoneyColumns.read(myShareMinor!, currencyCode),
  );
}

/// Maps `v_split_balances` rows.
extension SplitBalanceMapper on SplitBalanceRow {
  /// Maps this row to a read model.
  ///
  /// The summed columns default to zero: a counterparty who appears in the view has at least one
  /// contributing row, so a null side means "nothing on that side", which zero says exactly.
  SplitBalance toEntity() => SplitBalance(
    payeeId: payeeId,
    owedToMe: MoneyColumns.read(owedToMeMinor ?? 0, currencyCode),
    iOwe: MoneyColumns.read(iOweMinor ?? 0, currencyCode),
    // `MIN(date_key)` over rows that may all be settlements, which carry NULL there. Null means
    // nothing dated is outstanding, and `SplitBalance.ageInDays` already returns null for it.
    oldestUnsettledDateKey: oldestUnsettledDateKey,
  );
}

/// Maps `v_split_group_balances` rows.
extension SplitGroupBalanceMapper on SplitGroupBalanceRow {
  /// Maps this row to a read model.
  ///
  /// The group view carries no oldest-unsettled date: ageing is a property of a debt with a person,
  /// not of a debt within a group, and a group-scoped date would double-count somebody who owes you
  /// through two groups.
  SplitBalance toEntity() => SplitBalance(
    payeeId: payeeId,
    owedToMe: MoneyColumns.read(owedToMeMinor ?? 0, currencyCode),
    iOwe: MoneyColumns.read(iOweMinor ?? 0, currencyCode),
  );
}

/// Maps `v_split_activity` rows.
extension SplitActivityMapper on SplitActivityRow {
  /// Maps this row to a read model.
  SplitActivityEntry toEntity() => SplitActivityEntry(
    refId: refId,
    kind: activityKind == 'settlement'
        ? SplitActivityKind.settlement
        : SplitActivityKind.expense,
    dateKey: dateKey,
    amount: MoneyColumns.read(amountMinor, currencyCode),
    payeeId: payeeId,
    groupId: groupId,
    label: label,
  );
}
