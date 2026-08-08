import 'package:drift/drift.dart' show Value;

import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/entities/tag.dart';

/// Converts between `TagRow` and the domain `Tag` entity.
///
/// The six `allowedIn*` columns fold into one `Set<TagScope>` in both directions — the single
/// place that mapping happens, so a `Kitchen` tag can never end up allowed in the wrong picker
/// through a column mismatched in one direction but not the other (ARCH_2 §14).
extension TagMapper on TagRow {
  /// Maps this row to a domain entity.
  Tag toEntity() => Tag(
    id: id,
    name: name,
    normalizedName: normalizedName,
    allowedScopes: {
      if (allowedInDeposit) TagScope.deposit,
      if (allowedInWithdrawal) TagScope.withdrawal,
      if (allowedInInventory) TagScope.inventory,
      if (allowedInShopping) TagScope.shopping,
      if (allowedInRecurring) TagScope.recurring,
      if (allowedInService) TagScope.service,
    },
    isSystem: isSystem,
    sortOrder: sortOrder,
    isDeleted: deletedAt != null,
    colorArgb: colorArgb,
    iconKey: iconKey,
    parentTagId: parentTagId,
  );
}

/// Builds the companion for [tag].
///
/// [deletedAt] is threaded through explicitly rather than always `Value(null)`, because
/// [Tag.isDeleted] is real, writable state on this one entity (unlike every other repository in
/// this phase, which only ever soft-deletes via a dedicated method) — see the class doc on `Tag`.
TagsCompanion tagToCompanion(
    Tag tag, {
      required int createdAt,
      required int updatedAt,
      int? deletedAt,
    }) {
  return TagsCompanion.insert(
    id: tag.id,
    name: tag.name,
    normalizedName: tag.normalizedName,
    colorArgb: Value(tag.colorArgb),
    iconKey: Value(tag.iconKey),
    parentTagId: Value(tag.parentTagId),
    allowedInDeposit: tag.isAllowedIn(TagScope.deposit),
    allowedInWithdrawal: tag.isAllowedIn(TagScope.withdrawal),
    allowedInInventory: tag.isAllowedIn(TagScope.inventory),
    allowedInShopping: tag.isAllowedIn(TagScope.shopping),
    allowedInRecurring: tag.isAllowedIn(TagScope.recurring),
    allowedInService: tag.isAllowedIn(TagScope.service),
    isSystem: tag.isSystem,
    sortOrder: tag.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: Value(deletedAt),
  );
}