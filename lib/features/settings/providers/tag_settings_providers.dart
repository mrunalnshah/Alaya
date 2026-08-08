/// View-model state for the tags branch (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/domain/entities/tag.dart';

/// Every tag, deleted ones excluded.
final tagsSettingsProvider = StreamProvider<List<Tag>>(
  (ref) => ref.watch(tagRepositoryProvider).watchAll(),
);

/// The tags arranged as one level of parents with their children.
///
/// **One level, and the flattening is deliberate rather than a limitation.** ARCH_2 gives `tags.parentTagId`
/// no depth limit, but a tree deeper than one level cannot be shown in a picker without either indenting past
/// the width of a phone or hiding rows behind a disclosure nobody opens. A tag that is a child of a child is
/// rendered here as a child of its **top-most** ancestor, so it is reachable and grouped rather than lost.
final tagTreeProvider = Provider<List<({Tag parent, List<Tag> children})>>((
  ref,
) {
  final tags = ref.watch(tagsSettingsProvider).valueOrNull ?? const <Tag>[];
  final byId = {for (final tag in tags) tag.id: tag};

  String rootOf(Tag tag) {
    var current = tag;
    // Bounded by the number of tags, so a parent cycle written by a bad import cannot hang the screen. A cycle
    // is not supposed to be possible, and a UI that trusts that is a UI that freezes when it turns out to be.
    for (var hops = 0; hops < tags.length; hops++) {
      final parentId = current.parentTagId;
      if (parentId == null) return current.id;
      final parent = byId[parentId];
      if (parent == null) return current.id;
      current = parent;
    }
    return current.id;
  }

  final roots = [
    for (final tag in tags)
      if (tag.parentTagId == null) tag,
  ];
  final children = <String, List<Tag>>{};
  for (final tag in tags) {
    if (tag.parentTagId == null) continue;
    children.putIfAbsent(rootOf(tag), () => <Tag>[]).add(tag);
  }
  return [
    for (final root in roots)
      (parent: root, children: children[root.id] ?? const <Tag>[]),
  ];
});

/// One tag being edited, or null for a new one.
final tagDraftProvider = FutureProvider.autoDispose.family<Tag?, String?>((
  ref,
  id,
) async {
  if (id == null) return null;
  return ref.watch(tagRepositoryProvider).byId(id);
});

/// The tags that may be chosen as a parent for [id].
///
/// Excludes the tag itself and anything already beneath it, so the picker cannot be used to build a cycle —
/// the check belongs where the choice is offered, not in an error after the fact.
final tagParentChoicesProvider = Provider.family<List<Tag>, String?>((ref, id) {
  final tags = ref.watch(tagsSettingsProvider).valueOrNull ?? const <Tag>[];
  if (id == null)
    return [
      for (final tag in tags)
        if (tag.parentTagId == null) tag,
    ];
  final descendants = <String>{id};
  var grew = true;
  while (grew) {
    grew = false;
    for (final tag in tags) {
      final parentId = tag.parentTagId;
      if (parentId != null &&
          descendants.contains(parentId) &&
          descendants.add(tag.id)) {
        grew = true;
      }
    }
  }
  return [
    for (final tag in tags)
      if (!descendants.contains(tag.id)) tag,
  ];
});

/// Saves and deletes tags.
final tagEditorProvider = NotifierProvider<TagEditorNotifier, AsyncValue<void>>(
  TagEditorNotifier.new,
);

/// Writes a tag.
class TagEditorNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Creates or replaces a tag, returning whether it was written.
  Future<bool> save({
    required String? id,
    required String name,
    required Set<TagScope> allowedScopes,
    required int sortOrder,
    String? parentTagId,
    int? colorArgb,
    bool isSystem = false,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(tagRepositoryProvider)
        .save(
          Tag(
            id: id ?? ref.read(uidGeneratorProvider).generate(),
            name: name.trim(),
            normalizedName: ref.read(normalizerProvider).normalize(name),
            allowedScopes: allowedScopes,
            isSystem: isSystem,
            sortOrder: sortOrder,
            isDeleted: false,
            parentTagId: parentTagId,
            colorArgb: colorArgb,
          ),
        );
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  /// Deletes [id].
  ///
  /// `delete`, which the repository implements as the soft delete ARCH_3 §4 requires — the row keeps its
  /// history and leaves every picker. A tag hard-removed would orphan the `transaction_tags` rows naming it.
  Future<bool> delete(String id) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(tagRepositoryProvider).delete(id);
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  bool _settle(Object? failure) {
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}
