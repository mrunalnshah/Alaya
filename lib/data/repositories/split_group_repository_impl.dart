import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/settings_dao.dart';
import 'package:alaya/data/daos/split_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/mappers/split_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/domain/repositories/split_group_repository.dart';

/// `SplitGroupRepository` backed by [SplitDao].
///
/// Its own work beyond mapping is the refusals: a duplicate group name, a member listed twice, a
/// weight outside range, and — the one that matters — a delete while expenses still reference the
/// group.
final class SplitGroupRepositoryImpl implements SplitGroupRepository {
  /// Creates the repository.
  const SplitGroupRepositoryImpl(this._dao, this._settings, this._clock);

  final SplitDao _dao;
  final SettingsDao _settings;
  final Clock _clock;

  /// The `app_settings` key holding the payee the user has claimed as themselves.
  ///
  /// A setting rather than a flag on `payees`, so no two rows can claim it and a table five other
  /// modules read stays untouched.
  static const String selfPayeeSettingKey = 'split.selfPayeeId';

  Future<List<SplitMember>> _membersOf(String groupId) async {
    final rows = await _dao.watchMembers(groupId).first;
    return [for (final row in rows) row.toEntity()];
  }

  Future<SplitGroup> _assemble(SplitGroupRow row) async =>
      row.toEntity(members: await _membersOf(row.id));

  /// Assembles many groups with one membership query rather than one per group.
  ///
  /// The pattern `RecipeRepositoryImpl._assembleAll` uses: a list screen showing "4 people" per row
  /// would otherwise issue a query per visible row on every rebuild of a virtualised list.
  Future<List<SplitGroup>> _assembleAll(List<SplitGroupRow> rows) async {
    if (rows.isEmpty) return const [];
    final memberRows = await _dao.watchMembersForAll([
      for (final r in rows) r.id,
    ]).first;
    final byGroup = <String, List<SplitMember>>{};
    for (final row in memberRows) {
      byGroup.putIfAbsent(row.groupId, () => []).add(row.toEntity());
    }
    return [
      for (final row in rows)
        row.toEntity(members: byGroup[row.id] ?? const []),
    ];
  }

  @override
  Stream<List<SplitGroup>> watchAll() =>
      _dao.watchGroups().asyncMap(_assembleAll);

  @override
  Stream<List<SplitGroup>> watchActive() =>
      _dao.watchActiveGroups().asyncMap(_assembleAll);

  @override
  Stream<SplitGroup?> watchById(String id) => _dao
      .watchGroupById(id)
      .asyncMap((row) async => row == null ? null : _assemble(row));

  @override
  Future<SplitGroup?> byId(String id) async {
    final row = await _dao.groupById(id);
    return row == null ? null : _assemble(row);
  }

  @override
  Stream<List<SplitGroup>> watchForPayee(String payeeId) =>
      _dao.watchGroupsForPayee(payeeId).asyncMap(_assembleAll);

  @override
  Future<Result<SplitGroup, Failure>> save(SplitGroup group) async {
    if (group.name.trim().isEmpty) {
      return const Result.failure(
        ValidationFailure('A group needs a name.', field: 'name'),
      );
    }

    final seen = <String>{};
    for (final member in group.members) {
      if (!seen.add(member.payeeId)) {
        return const Result.failure(
          BusinessRuleFailure(
            'Somebody is listed twice in this group.',
            rule: 'splitDuplicateMember',
          ),
        );
      }
      final weight = member.defaultWeightBasisPoints;
      // Basis points, so 10,000 is the whole. A weight above it is meaningless and a negative one
      // would make the resolver throw — better to refuse it here, where the message can name the
      // group, than to let it reach `SplitResolver` as an `ArgumentError`.
      if (weight != null && (weight < 0 || weight > 10000)) {
        return const Result.failure(
          ValidationFailure(
            'A share must be between 0% and 100%.',
            field: 'defaultWeightBasisPoints',
          ),
        );
      }
    }

    final existing = await _dao.groupById(group.id);

    // **Checked before the write, not caught after it**, which is how `AccountRepositoryImpl` and
    // `ItemRepositoryImpl` handle their own uniqueness. Catching the index violation instead would
    // report *any* throw as a duplicate name — a disk error, a foreign-key failure, a bug in the
    // mapper — all wearing the same message. My first version did exactly that.
    //
    // Only on insert. A rename that collides is caught the same way, because `byNormalizedName`
    // returns the other group and its id differs.
    final duplicate = await _dao.byNormalizedName(group.normalizedName);
    if (duplicate != null && duplicate.id != group.id) {
      return Result.failure(
        ConflictFailure('A group named "${group.name}" already exists.'),
      );
    }

    try {
      final stamps = WriteTimestamps.resolve(
        existingCreatedAt: existing?.createdAt,
        clock: _clock,
      );
      final now = stamps.updatedAt;

      await _dao.saveGroup(
        nowUtcMillis: now,
        group: splitGroupToCompanion(
          group,
          createdAt: stamps.createdAt,
          updatedAt: now,
        ),
        members: [
          for (var i = 0; i < group.members.length; i++)
            splitMemberToCompanion(
              // The list's own order is authoritative, so a reorder in the editor is saved without
              // the UI having to renumber anything — the same treatment recipe ingredients get.
              SplitMember(
                id: group.members[i].id,
                groupId: group.id,
                payeeId: group.members[i].payeeId,
                defaultWeightBasisPoints:
                    group.members[i].defaultWeightBasisPoints,
                sortOrder: i,
              ),
              createdAt: now,
              updatedAt: now,
            ),
        ],
      );
      final saved = await byId(group.id);
      return saved == null
          ? const Result.failure(
              UnexpectedFailure('That group could not be saved.'),
            )
          : Result.ok(saved);
    } on Object catch (error) {
      // Whatever reaches here is genuinely unexplained, which is why `UnexpectedFailure` is the only
      // failure in this hierarchy that carries a `cause` — the others name a rule or a field the code
      // already understands, so there is nothing unaccounted for to attach.
      return Result.failure(
        UnexpectedFailure('That group could not be saved.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> setArchived({
    required String id,
    required bool isArchived,
  }) async {
    try {
      await _dao.setGroupArchived(
        id: id,
        isArchived: isArchived,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That group could not be updated.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    // **Refused while expenses reference the group**, and the message says what to do instead.
    // Cascading would delete a shared history because a label was tidied away, and every balance
    // those expenses feed would vanish with them. Archiving is the operation the user actually wants
    // and it is one tap away.
    final expenses = await _dao.expenseCountInGroup(id);
    if (expenses > 0) {
      return Result.failure(
        BusinessRuleFailure(
          'This group has $expenses expense(s). Archive it instead — its history stays and it '
          'leaves the pickers.',
          rule: 'splitGroupHasExpenses',
        ),
      );
    }
    try {
      await _dao.softDeleteGroup(id: id, nowUtcMillis: _clock.nowUtcMillis());
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That group could not be deleted.', cause: error),
      );
    }
  }

  @override
  Future<String?> selfPayeeId() => _settings.readValue(selfPayeeSettingKey);

  @override
  Future<Result<void, Failure>> setSelfPayeeId(String payeeId) async {
    try {
      await _settings.writeValue(
        key: selfPayeeSettingKey,
        value: payeeId,
        valueType: 'string',
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That could not be saved.', cause: error),
      );
    }
  }
}
