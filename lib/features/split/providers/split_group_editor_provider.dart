/// Saving one split group (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/text/normalizer.dart';
import 'package:alaya/domain/entities/split_group.dart';

/// Runs a group save and holds why it failed.
///
/// `AsyncValue<void>` rather than a bool, so the reason survives to the screen. A save refused for a
/// duplicate name and one refused for a member listed twice are different problems, and reporting both
/// as "something went wrong" is what makes a form unfixable (Law U9).
final splitGroupEditorProvider =
    NotifierProvider<SplitGroupEditor, AsyncValue<void>>(
      SplitGroupEditor.new,
    );

/// Validates and saves a group.
class SplitGroupEditor extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Saves the group, returning whether it committed.
  ///
  /// **Member ids are minted here, not in the screen.** A membership row's id has no meaning outside
  /// its row, and generating one per rebuild would make every keystroke look like a different member
  /// list to `saveGroup`'s delete-then-insert. Existing members keep theirs so an edit updates rather
  /// than replaces.
  Future<bool> save({
    String? id,
    required String name,
    required SplitMethod defaultSplitMethod,
    required List<({String payeeId, int? weightBasisPoints, String? memberId})>
    members,
    bool isArchived = false,
    int sortOrder = 0,
    String? note,
  }) async {
    state = const AsyncLoading<void>();
    final uids = ref.read(uidGeneratorProvider);
    final groupId = id ?? uids.generate();

    final result = await ref
        .read(splitGroupRepositoryProvider)
        .save(
          SplitGroup(
            id: groupId,
            name: name.trim(),
            // Built with `Normalizer`, so one implementation decides what "the same name" means
            // everywhere — the same reason every named entity carries a normalized form rather than
            // letting each repository invent one.
            normalizedName: const Normalizer().normalize(name),
            defaultSplitMethod: defaultSplitMethod,
            isArchived: isArchived,
            sortOrder: sortOrder,
            note: note,
            members: [
              for (var i = 0; i < members.length; i++)
                SplitMember(
                  id: members[i].memberId ?? uids.generate(),
                  groupId: groupId,
                  payeeId: members[i].payeeId,
                  defaultWeightBasisPoints: members[i].weightBasisPoints,
                  sortOrder: i,
                ),
            ],
          ),
        );

    final failure = result.failureOrNull;
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData(null);
    return true;
  }

  /// Archives or unarchives a group.
  Future<bool> setArchived({
    required String id,
    required bool isArchived,
  }) async {
    final result = await ref
        .read(splitGroupRepositoryProvider)
        .setArchived(id: id, isArchived: isArchived);
    final failure = result.failureOrNull;
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    return true;
  }

  /// Deletes a group, which the repository refuses while expenses reference it.
  Future<bool> delete(String id) async {
    final result = await ref.read(splitGroupRepositoryProvider).delete(id);
    final failure = result.failureOrNull;
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    return true;
  }

  /// The message from the last failure, or null.
  ///
  /// **Typed, not cast.** `Failure.message` is the sentence the repository wrote — *"This group has 3
  /// expense(s). Archive it instead"* names both the problem and the remedy — and an `as dynamic` to
  /// reach it would compile against anything and fail at runtime the first time a non-`Failure` landed
  /// in the error slot.
  String? get lastError {
    final error = state.error;
    return error is Failure ? error.message : null;
  }
}
