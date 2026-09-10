import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/split_group.dart';

/// Groups and their membership.
///
/// **Split from [SplitLedgerRepository] on purpose.** Groups are reference data — a cast of people
/// with a name — while expenses and settlements are the ledger. One contract covering both would run
/// to twenty methods and would put "rename a group" beside "record a settlement", which are not the
/// same kind of operation and are not read by the same screens.
///
/// People themselves are `payees` and belong to `PayeeRepository`. This contract deals only in payee
/// ids, so a group can never become a second place a person's name is stored.
abstract interface class SplitGroupRepository {
  /// Every group with its members, in sort order. Archived groups included.
  Stream<List<SplitGroup>> watchAll();

  /// Groups that are not archived — what a picker offers.
  Stream<List<SplitGroup>> watchActive();

  /// One group with its members, or null if it does not exist.
  Stream<SplitGroup?> watchById(String id);

  /// Fetches one group with its members.
  Future<SplitGroup?> byId(String id);

  /// Groups [payeeId] is a member of.
  ///
  /// The reverse lookup a person's detail screen shows — *"you split with Ravi in 3 groups"*. Backed
  /// by `idx_split_member`.
  Stream<List<SplitGroup>> watchForPayee(String payeeId);

  /// Inserts or replaces [group] and its whole member list, atomically.
  ///
  /// Rejects a duplicate normalized name against a live group (`idx_split_groups_name`), a member list
  /// with the same payee twice, and a weight outside 0–10,000 basis points.
  Future<Result<SplitGroup, Failure>> save(SplitGroup group);

  /// Archives or unarchives.
  ///
  /// Archiving is not deleting: an archived group keeps its expenses and stays in totals, and only
  /// leaves the pickers (ARCH_3 §4).
  Future<Result<void, Failure>> setArchived({
    required String id,
    required bool isArchived,
  });

  /// Soft-deletes the group and its memberships.
  ///
  /// **Refuses while the group still has expenses.** Deleting a group whose expenses reference it
  /// would leave those expenses filed under a group nothing can name, and the balances they feed would
  /// keep counting. Archive it instead, which is what the refusal says.
  Future<Result<void, Failure>> delete(String id);

  /// The payee id the user has claimed as themselves, or null when unset.
  ///
  /// Read from `app_settings` under `split.selfPayeeId` rather than a flag on `payees`, so no two rows
  /// can claim it and a table five other modules read stays untouched.
  ///
  /// **Null means "not configured", never "nobody".** On a fresh install there is no payee to point at
  /// until the user creates one, and every balance view yields a null own-share until this is set — a
  /// screen must say so rather than showing zero as though nothing were owed.
  Future<String?> selfPayeeId();

  /// Claims [payeeId] as the user.
  Future<Result<void, Failure>> setSelfPayeeId(String payeeId);
}
