# PHASE 8A — PART 2: the settings tree

Part 1 is `PHASE_08A_SETTINGS_LOCK.md`. **The split is editorial, not functional** — both parts must be applied
together, because `app_router.dart` names all twelve 8A screens and will not compile until every one exists.

Part 1 delivered the domain ports, `EraseService`, the router gates and `refreshListenable`, persisted theme
(ARCH_4 §5.1 item 23), onboarding, the lock/PIN/recovery trio, the settings tree, and accounts. **All nine
CRITICAL requirements are satisfied there.**

This part delivers the remaining branches, and owns the phase's shared artefacts:

| | |
|---|---|
| tags | the `allowedIn*` scoping matrix, one level of nesting — **closes two §7.2 rows** |
| units | a user unit with an integer factor, and the "make it a new item" escape when there is none |
| payment methods, payees | archetype D with capture sheets |
| currencies | enable and disable, with the home currency protected |
| appearance | palette and theme mode, already persisted by Part 1's providers |
| security | change or remove the PIN, the auto-lock delay, the ten-failure auto-erase |
| data, about | export, trash, version |
| `app_en.arb` | carried whole, with this phase's keys |
| tests | four states per screen (§9.1), goldens where §9.2 asks |
| `layout_overflow_test.dart` | carried whole, with every new sheet and full-height state |
| COVERAGE | the ARCH_5 §7 rows the phase closes |

---

## Tags — the scoping matrix

`tags.allowedIn*` is what stops "Kitchen" appearing in the deposit editor's tag picker, so **every row states its
scopes as chips**. A scope only visible after opening the editor is one nobody notices is wrong.

**A tag with no scopes at all is called out rather than silently listed.** It cannot appear anywhere in the app,
which makes it invisible everywhere except this screen — exactly the dead row somebody would hunt for in the
pickers before thinking to come here.

**One level of nesting, and a grandchild is grouped under its top-most ancestor.** ARCH_2 sets no depth limit,
but a deeper tree cannot be shown in a picker without indenting past the width of a phone; flattening keeps a
grandchild reachable instead of lost. The root walk is **bounded by the tag count**, so a parent cycle written by
a bad import cannot hang the screen — a cycle should be impossible, and a UI that trusts that is a UI that
freezes when it turns out not to be.

`tagParentChoicesProvider` excludes a tag and everything beneath it, so the parent picker cannot be used to build
a cycle in the first place — the check belongs where the choice is offered, not in an error afterwards.

The repository's method is `delete`, which it implements as ARCH_3 §4's soft delete; I had written `softDelete`
from memory and the contract corrected me.

### `lib/features/settings/providers/tag_settings_providers.dart`

```dart
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
final tagTreeProvider = Provider<List<({Tag parent, List<Tag> children})>>((ref) {
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

  final roots = [for (final tag in tags) if (tag.parentTagId == null) tag];
  final children = <String, List<Tag>>{};
  for (final tag in tags) {
    if (tag.parentTagId == null) continue;
    children.putIfAbsent(rootOf(tag), () => <Tag>[]).add(tag);
  }
  return [
    for (final root in roots) (parent: root, children: children[root.id] ?? const <Tag>[]),
  ];
});

/// One tag being edited, or null for a new one.
final tagDraftProvider = FutureProvider.autoDispose.family<Tag?, String?>((ref, id) async {
  if (id == null) return null;
  return ref.watch(tagRepositoryProvider).byId(id);
});

/// The tags that may be chosen as a parent for [id].
///
/// Excludes the tag itself and anything already beneath it, so the picker cannot be used to build a cycle —
/// the check belongs where the choice is offered, not in an error after the fact.
final tagParentChoicesProvider =
    Provider.family<List<Tag>, String?>((ref, id) {
  final tags = ref.watch(tagsSettingsProvider).valueOrNull ?? const <Tag>[];
  if (id == null) return [for (final tag in tags) if (tag.parentTagId == null) tag];
  final descendants = <String>{id};
  var grew = true;
  while (grew) {
    grew = false;
    for (final tag in tags) {
      final parentId = tag.parentTagId;
      if (parentId != null && descendants.contains(parentId) && descendants.add(tag.id)) {
        grew = true;
      }
    }
  }
  return [for (final tag in tags) if (!descendants.contains(tag.id)) tag];
});

/// Saves and deletes tags.
final tagEditorProvider =
    NotifierProvider<TagEditorNotifier, AsyncValue<void>>(TagEditorNotifier.new);

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
    final result = await ref.read(tagRepositoryProvider).save(
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
```

### `lib/features/settings/presentation/widgets/tag_scope_labels.dart`

```dart
import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/core/enums/tag_scope.dart';

/// The name of each place a tag may be offered.
///
/// **One switch, shared by the list and the editor**, so a scope cannot be called one thing on the row and
/// another in the matrix that sets it. Exhaustive over [TagScope] without a `default`, so adding a seventh
/// picker to the app fails to compile here instead of shipping a chip with no label.
String tagScopeLabel(AlayaStrings strings, TagScope scope) => switch (scope) {
      TagScope.deposit => strings.tagScopeDeposit,
      TagScope.withdrawal => strings.tagScopeWithdrawal,
      TagScope.inventory => strings.tagScopeInventory,
      TagScope.shopping => strings.tagScopeShopping,
      TagScope.recurring => strings.tagScopeRecurring,
      TagScope.service => strings.tagScopeService,
    };

/// What each scope actually controls, for the editor's matrix.
///
/// The help line matters more here than anywhere else in Settings: "Withdrawal" tells the reader nothing about
/// *why* unticking it would make a tag vanish from the screen they use most.
String tagScopeHelp(AlayaStrings strings, TagScope scope) => switch (scope) {
      TagScope.deposit => strings.tagScopeDepositHelp,
      TagScope.withdrawal => strings.tagScopeWithdrawalHelp,
      TagScope.inventory => strings.tagScopeInventoryHelp,
      TagScope.shopping => strings.tagScopeShoppingHelp,
      TagScope.recurring => strings.tagScopeRecurringHelp,
      TagScope.service => strings.tagScopeServiceHelp,
    };
```

### `lib/features/settings/presentation/screens/tags_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/settings/presentation/widgets/tag_scope_labels.dart';
import 'package:alaya/features/settings/providers/tag_settings_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Settings › Tags (ARCH_5 §3 archetype D, outside the shell).
///
/// **The scoping matrix is the point of this screen, not decoration on it.** `tags.allowedIn*` is what stops
/// "Kitchen" appearing in the deposit editor's tag picker — a tag scoped to inventory only has no business being
/// offered when somebody records their salary. Every row therefore states its scopes as chips, because a scope
/// that is only visible after opening the editor is one nobody will notice is wrong.
///
/// **A tag with no scopes at all is called out**, not silently listed. It cannot appear anywhere in the app, so
/// it is invisible everywhere except this screen — exactly the kind of dead row a user would spend time hunting
/// for in the pickers before thinking to come here.
///
/// **One level of nesting, and a child is grouped under its top-most ancestor.** ARCH_2 sets no depth limit, but
/// a deeper tree cannot be shown in a picker without indenting past the width of a phone. Flattening keeps a
/// grandchild reachable rather than lost.
class TagsSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const TagsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final tags = ref.watch(tagsSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsTags)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.tagNew),
        tooltip: strings.tagsAdd,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
      body: tags.when(
        loading: () => AlayaListSkeleton(label: strings.tagsLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(tagsSettingsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return EmptyState(
              title: strings.tagsEmptyTitle,
              body: strings.tagsEmptyBody,
              icon: Icons.sell_outlined,
              actionLabel: strings.tagsAdd,
              onAction: () => context.push(Routes.tagNew),
            );
          }
          final tree = ref.watch(tagTreeProvider);
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
            itemCount: tree.length,
            itemBuilder: (context, index) {
              final branch = tree[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TagRow(tag: branch.parent),
                  for (final child in branch.children) _TagRow(tag: child, nested: true),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// One tag: its colour, its name, and where it is allowed to appear.
class _TagRow extends StatelessWidget {
  const _TagRow({required this.tag, this.nested = false});

  final Tag tag;
  final bool nested;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final theme = Theme.of(context);
    final scopes = tag.allowedScopes;

    return ListTile(
      contentPadding: EdgeInsets.only(
        // Indented once and no further, which is the visible half of the one-level rule.
        left: AlayaSpacing.screenEdge + (nested ? AlayaSpacing.lg : 0),
        right: AlayaSpacing.screenEdge,
      ),
      leading: Container(
        width: AlayaSpacing.md,
        height: AlayaSpacing.md,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tag.colorArgb == null
              ? theme.colorScheme.outlineVariant
              : Color(tag.colorArgb!),
        ),
      ),
      title: Row(
        children: [
          Expanded(child: Text(tag.name, style: AlayaTypography.cardTitle)),
          if (tag.isSystem) ...[
            const SizedBox(width: AlayaSpacing.xs),
            // A system tag can be re-scoped and recoloured but not deleted, and saying so on the row saves the
            // trip into an editor whose delete button is missing for no stated reason.
            StatusChip(label: strings.tagsSystemChip, tone: StatusTone.neutral),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
        child: scopes.isEmpty
            ? Text(
                strings.tagsNoScopesWarning,
                style: AlayaTypography.caption.copyWith(color: semantic.warning),
              )
            : Wrap(
                spacing: AlayaSpacing.xxs,
                runSpacing: AlayaSpacing.xxs,
                children: [
                  for (final scope in TagScope.values)
                    if (scopes.contains(scope))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AlayaSpacing.xs,
                          vertical: AlayaSpacing.xxs / 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: AlayaRadii.borderSm,
                        ),
                        child: Text(
                          tagScopeLabel(strings, scope),
                          style: AlayaTypography.overline.copyWith(color: semantic.muted),
                        ),
                      ),
                ],
              ),
      ),
      onTap: () => context.push(Routes.tagEdit(tag.id)),
    );
  }
}
```

## The tag editor — where the two §7.2 rows close

**Six switches, each with a line saying what unticking it would do.** "Withdrawal" on its own tells the reader
nothing about *why* a tag would vanish from the screen they use most, and a matrix nobody understands is a matrix
nobody sets correctly.

**A tag scoped nowhere is warned about, not forbidden.** ARCH_2 permits an empty scope set, and somebody may well
want to park a tag they are not using — inventing a constraint the schema does not have would be worse than
saying plainly that the tag will appear nowhere. A **new** tag starts scoped to the two money pickers rather than
to nothing, because somebody adding a tag almost always means to use it on a transaction and an empty default
would make their first act invisible.

**The parent picker is pre-filtered, so a cycle cannot be built.** `tagParentChoicesProvider` excludes the tag
and everything beneath it; the constraint lives where the choice is offered rather than in an error afterwards.

**The colour swatches come from the live palette, and the stored value is a frozen `int`.** `colorArgb` is a
column, so a tag coloured under one preset keeps that colour if the user later switches palettes. Storing a
palette *role* would follow the theme, but the schema stores an int and inventing a second encoding in the UI
would put two meanings in one column. The swatch reads at 24dp and is touchable at 48 (Law U3).

**The delete confirmation says what survives.** A soft delete is not what "delete" usually promises: the
transactions that carried the tag keep their history, and only the tag leaves the pickers (ARCH_3 §4). System
tags have no delete button at all.

`Color.toARGB32()` is used rather than the deprecated `.value` — ARCH_1 §7 pins Flutter 3.44.x, well past the
3.27 that introduced it. Worth checking rather than assuming, since the two differ silently by deprecation
warning rather than by failure.

### `lib/features/settings/presentation/screens/tag_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/settings/presentation/widgets/tag_scope_labels.dart';
import 'package:alaya/features/settings/providers/tag_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Creating or editing one tag (ARCH_5 §3 archetype B).
///
/// **This is where `tags.allowedIn*` and `tags.parentTagId` are actually set**, and the two §7.2 rows they
/// represent close here. The matrix is six switches with a line each saying what unticking one would do, because
/// "Withdrawal" on its own tells the reader nothing about *why* a tag would vanish from the screen they use most.
///
/// **A tag scoped nowhere is warned about, not forbidden.** ARCH_2 permits an empty scope set and somebody may
/// well want to park a tag they are not using; inventing a constraint the schema does not have would be worse
/// than saying plainly that the tag will not appear anywhere.
class TagEditorScreen extends ConsumerStatefulWidget {
  /// Creates the editor. [tagId] null means a new tag.
  const TagEditorScreen({this.tagId, super.key});

  /// The tag being edited, or null for a new one.
  final String? tagId;

  @override
  ConsumerState<TagEditorScreen> createState() => _TagEditorScreenState();
}

class _TagEditorScreenState extends ConsumerState<TagEditorScreen> {
  final _name = TextEditingController();
  Set<TagScope> _scopes = {};
  String? _parentId;
  int? _colorArgb;
  int _sortOrder = 0;
  bool _isSystem = false;
  bool _dirty = false;
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _adopt(Tag? tag) {
    if (_loaded) return;
    _loaded = true;
    if (tag == null) {
      // A new tag starts scoped to the two money pickers rather than to nothing. Somebody adding a tag almost
      // always means to use it on a transaction, and an empty set would make their first act invisible.
      _scopes = {TagScope.deposit, TagScope.withdrawal};
      return;
    }
    _name.text = tag.name;
    _scopes = {...tag.allowedScopes};
    _parentId = tag.parentTagId;
    _colorArgb = tag.colorArgb;
    _sortOrder = tag.sortOrder;
    _isSystem = tag.isSystem;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(tagDraftProvider(widget.tagId));
    final editing = ref.watch(tagEditorProvider);

    return draft.when(
      loading: () => _shell(strings, const SizedBox.shrink()),
      error: (error, stack) => _shell(
        strings,
        ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(tagDraftProvider(widget.tagId)),
        ),
      ),
      data: (tag) {
        if (widget.tagId != null && tag == null) {
          return _shell(
            strings,
            ErrorState(
              title: strings.tagsMissingTitle,
              body: strings.tagsMissingBody,
              retryLabel: strings.actionBack,
              onRetry: () => context.pop(),
            ),
          );
        }
        _adopt(tag);
        final parents = ref.watch(tagParentChoicesProvider(widget.tagId));
        final theme = Theme.of(context);
        final swatches = <int>[
          theme.colorScheme.primary.toARGB32(),
          theme.colorScheme.secondary.toARGB32(),
          theme.colorScheme.tertiary.toARGB32(),
          theme.colorScheme.primaryContainer.toARGB32(),
          theme.colorScheme.secondaryContainer.toARGB32(),
          theme.colorScheme.tertiaryContainer.toARGB32(),
        ];

        return _shell(
          strings,
          AlayaFormScaffold(
            primaryLabel: strings.tagEditorSave,
            onPrimary: _name.text.trim().isEmpty || editing.isLoading ? null : () => _save(tag),
            isDirty: _dirty,
            isSubmitting: editing.isLoading,
            discardTitle: strings.confirmDiscardTitle,
            discardBody: strings.confirmDiscardBody,
            discardConfirmLabel: strings.actionDiscard,
            discardCancelLabel: strings.actionKeepEditing,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  autofocus: tag == null,
                  decoration: InputDecoration(labelText: strings.tagNameLabel),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: AlayaSpacing.lg),
                SectionHeader(label: strings.tagColourHeader),
                const SizedBox(height: AlayaSpacing.xxs),
                // **The swatches come from the live palette; the stored value is a frozen int.** `colorArgb` is
                // a column, so a tag coloured under one preset keeps that colour if the user later switches
                // palettes. Storing a palette *role* would follow the theme, but the schema stores an int and
                // inventing a second encoding in the UI would put two meanings in one column.
                Text(
                  strings.tagColourHelp,
                  style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
                ),
                const SizedBox(height: AlayaSpacing.xs),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    _Swatch(
                      color: theme.colorScheme.outlineVariant,
                      selected: _colorArgb == null,
                      semanticLabel: strings.tagColourNone,
                      onTap: () => setState(() {
                        _colorArgb = null;
                        _dirty = true;
                      }),
                    ),
                    for (final argb in swatches)
                      _Swatch(
                        color: Color(argb),
                        selected: _colorArgb == argb,
                        semanticLabel: strings.tagColourSwatch,
                        onTap: () => setState(() {
                          _colorArgb = argb;
                          _dirty = true;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: AlayaSpacing.lg),
                SectionHeader(label: strings.tagParentHeader),
                const SizedBox(height: AlayaSpacing.xxs),
                Text(
                  strings.tagParentHelp,
                  style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
                ),
                const SizedBox(height: AlayaSpacing.xs),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    ChoiceChip(
                      label: Text(strings.tagParentNone, style: AlayaTypography.button),
                      selected: _parentId == null,
                      onSelected: (_) => setState(() {
                        _parentId = null;
                        _dirty = true;
                      }),
                    ),
                    // Already filtered to exclude this tag and everything beneath it, so the picker cannot build
                    // a cycle — the constraint lives where the choice is made.
                    for (final parent in parents)
                      ChoiceChip(
                        label: Text(parent.name, style: AlayaTypography.button),
                        selected: parent.id == _parentId,
                        onSelected: (_) => setState(() {
                          _parentId = parent.id;
                          _dirty = true;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: AlayaSpacing.lg),
                SectionHeader(label: strings.tagScopesHeader),
                const SizedBox(height: AlayaSpacing.xxs),
                Text(
                  strings.tagScopesHelp,
                  style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
                ),
                if (_scopes.isEmpty) ...[
                  const SizedBox(height: AlayaSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AlayaSpacing.md),
                    decoration: BoxDecoration(
                      color: context.semantic.warning.withValues(alpha: 0.12),
                      borderRadius: AlayaRadii.borderMd,
                    ),
                    child: Text(
                      strings.tagsNoScopesWarning,
                      style: AlayaTypography.bodyEmphasis,
                    ),
                  ),
                ],
                const SizedBox(height: AlayaSpacing.xs),
                for (final scope in TagScope.values)
                  SwitchListTile(
                    value: _scopes.contains(scope),
                    contentPadding: EdgeInsets.zero,
                    title: Text(tagScopeLabel(strings, scope), style: AlayaTypography.body),
                    subtitle: Text(
                      tagScopeHelp(strings, scope),
                      style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
                    ),
                    onChanged: (on) => setState(() {
                      final next = {..._scopes};
                      if (on) {
                        next.add(scope);
                      } else {
                        next.remove(scope);
                      }
                      _scopes = next;
                      _dirty = true;
                    }),
                  ),
                if (tag != null && !_isSystem) ...[
                  const SizedBox(height: AlayaSpacing.xl),
                  OutlinedButton(
                    onPressed: editing.isLoading ? null : () => _delete(tag),
                    style: OutlinedButton.styleFrom(foregroundColor: context.semantic.danger),
                    child: Text(strings.tagsDelete, style: AlayaTypography.button),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  Text(
                    strings.tagsDeleteHelp,
                    style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
                  ),
                ],
                if (editing.hasError) ...[
                  const SizedBox(height: AlayaSpacing.md),
                  Text(
                    editing.error.toString(),
                    style: AlayaTypography.body.copyWith(color: context.semantic.danger),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _shell(AlayaStrings strings, Widget body) => Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: Text(
            widget.tagId == null ? strings.tagEditorTitle : strings.tagEditorEditTitle,
          ),
        ),
        body: body,
      );

  Future<void> _save(Tag? existing) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(tagEditorProvider.notifier).save(
          id: existing?.id,
          name: _name.text,
          allowedScopes: _scopes,
          sortOrder: _sortOrder,
          parentTagId: _parentId,
          colorArgb: _colorArgb,
          isSystem: _isSystem,
        );
    if (!mounted || !saved) return;
    showResultSnack(context, message: strings.tagsSaved);
    context.pop();
  }

  Future<void> _delete(Tag tag) async {
    final strings = AlayaStrings.of(context);
    // The body says what survives, because a soft delete is not what "delete" usually promises: the transactions
    // that carried this tag keep their history, and only the tag leaves the pickers (ARCH_3 §4).
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.tagsDeleteConfirmTitle,
      body: strings.tagsDeleteConfirmBody,
      confirmLabel: strings.tagsDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final ok = await ref.read(tagEditorProvider.notifier).delete(tag.id);
    if (!mounted || !ok) return;
    showResultSnack(context, message: strings.tagsDeleted);
    context.pop();
  }
}

/// One colour choice.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AlayaSpacing.minTapTarget),
        // A full tap target around a small dot: the swatch reads at 24dp and is touchable at 48 (Law U3).
        child: SizedBox(
          width: AlayaSpacing.minTapTarget,
          height: AlayaSpacing.minTapTarget,
          child: Center(
            child: Container(
              width: AlayaSpacing.xl,
              height: AlayaSpacing.xl,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: theme.colorScheme.onSurface, width: 3)
                    : null,
              ),
              child: selected
                  ? Icon(Icons.check, size: AlayaIconSize.sm, color: theme.colorScheme.surface)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
```

## Units — and the escape when there is no factor

**The screen never shows a stored factor.** `factorToBaseMilli` counts *thousandths* of the base unit, so a
kilogram is 1,000,000 — technically the value and useless to read. Rows say what the unit **is**: *1 kg =
1,000 g*. The division happens in one helper, and `milliPerBaseUnit` is named rather than inlined, because
**that constant is the whole of ARCH_4 R18** — three separate sites had divided by 1,000 instead of by the
unit's factor, which valued two kilos of potatoes at a hundred thousand rupees.

The editor asks for **base units and multiplies once**, so nobody — user or later maintainer — has to think in
thousandths. It accepts decimals (a tablespoon is 14.79 ml), because the column's milli-precision can express
them and refusing would push a legitimate unit into the "make it an item" path it does not belong in. A
resulting factor of zero or less is **guarded, not trusted**: it would convert every quantity in that unit to
nothing, silently, and divide the inventory valuation by zero.

**Grouping is by category because the categories cannot change.** ARCH_1 §5.3 fixes them at three and Law L8
makes cross-category conversion inexpressible — weight, volume and count are not a filter the user chose, they
are the shape of the data, and grouping says so without a sentence. §5.3's rule is also stated at the foot of
the list, where somebody about to add a unit reads it *before* trying rather than as a refusal afterwards.

### `lib/features/settings/providers/unit_settings_providers.dart`

```dart
/// View-model state for the units branch (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Every unit, system ones included.
final unitsSettingsProvider = StreamProvider<List<Unit>>(
  (ref) => ref.watch(unitRepositoryProvider).watchAll(),
);

/// One unit being edited, or null for a new one.
final unitDraftProvider = FutureProvider.autoDispose.family<Unit?, String?>((ref, code) async {
  if (code == null) return null;
  return ref.watch(unitRepositoryProvider).byCode(code);
});

/// How many base-milli units one base unit is.
///
/// **The whole of ARCH_4 R18 lives in this number.** `factorToBaseMilli` counts *thousandths* of the base
/// unit, so a kilogram is 1,000,000 and not 1,000 — and R18 was three separate sites that divided by 1,000
/// instead of by the unit's factor, which valued two kilos of potatoes at a hundred thousand rupees. The
/// editor asks the user for base units and multiplies here, in one place, rather than asking anybody to
/// think in thousandths.
const int milliPerBaseUnit = 1000;

/// Saves and deletes units.
final unitEditorProvider =
    NotifierProvider<UnitEditorNotifier, AsyncValue<void>>(UnitEditorNotifier.new);

/// Writes a unit.
class UnitEditorNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Creates or replaces a unit from a factor expressed in **base units**.
  ///
  /// [baseUnitsPerUnit] is what the user typed — 1000 for a kilogram, 12 for a dozen, 14.79 for a
  /// tablespoon. It is multiplied by [milliPerBaseUnit] and rounded here, so no screen has to know that the
  /// column counts thousandths.
  Future<bool> save({
    required String code,
    required String displayName,
    required UnitCategory category,
    required double baseUnitsPerUnit,
    required int sortOrder,
    bool isSystem = false,
  }) async {
    state = const AsyncLoading<void>();
    final factor = (baseUnitsPerUnit * milliPerBaseUnit).round();
    if (factor <= 0) {
      // Guarded rather than trusted: a zero factor would make every quantity in that unit convert to nothing,
      // silently, and a division by it would take out the inventory valuation.
      state = AsyncError<void>(
        const _ZeroFactor(),
        StackTrace.current,
      );
      return false;
    }
    final result = await ref.read(unitRepositoryProvider).save(
          Unit(
            code: code.trim(),
            category: category,
            factorToBaseMilli: factor,
            displayName: displayName.trim(),
            isSystem: isSystem,
            sortOrder: sortOrder,
          ),
        );
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  /// Deletes [code].
  Future<bool> delete(String code) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(unitRepositoryProvider).delete(code);
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

/// Signals a factor of zero or less, so the screen can say so in its own words (Law U5).
class _ZeroFactor implements Exception {
  const _ZeroFactor();

  @override
  String toString() => 'factorMustBePositive';
}
```

### `lib/features/settings/presentation/widgets/unit_labels.dart`

```dart
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/settings/providers/unit_settings_providers.dart';

/// The name of each quantity category.
///
/// Exhaustive without a `default`, so ARCH_1 §5.3's promise that there is never a fourth category is enforced
/// by the compiler here as well as by the enum.
String unitCategoryLabel(AlayaStrings strings, UnitCategory category) => switch (category) {
      UnitCategory.weight => strings.unitCategoryWeight,
      UnitCategory.volume => strings.unitCategoryVolume,
      UnitCategory.count => strings.unitCategoryCount,
    };

/// How many base units one [unit] is, formatted for reading.
///
/// **Divides by [milliPerBaseUnit], which is the one arithmetic ARCH_4 R18 was about.** The column counts
/// thousandths of the base unit, so a kilogram is stored as 1,000,000 and shown as 1,000 g. Trailing zeros are
/// dropped, so a tablespoon reads *14.79 ml* rather than *14.790*.
String unitBaseAmountLabel(Unit unit) {
  final base = unit.factorToBaseMilli / milliPerBaseUnit;
  final formatter = base == base.roundToDouble()
      ? NumberFormat.decimalPattern()
      : NumberFormat('#,##0.###');
  return formatter.format(base);
}

/// The plural name of a category's base unit — "grams", "millilitres", "pieces".
///
/// The *name*, not the code, because the editor's question reads "How many grams is one kilogram?" and a
/// question phrased with `g` in it asks the user to decode an abbreviation before they can answer.
String unitBaseUnitName(AlayaStrings strings, UnitCategory category) => switch (category) {
      UnitCategory.weight => strings.unitBaseGrams,
      UnitCategory.volume => strings.unitBaseMillilitres,
      UnitCategory.count => strings.unitBasePieces,
    };
```

### `lib/features/settings/presentation/screens/units_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/settings/presentation/widgets/unit_labels.dart';
import 'package:alaya/features/settings/providers/unit_settings_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Settings › Units (ARCH_5 §3 archetype D, outside the shell).
///
/// **Grouped by category, because the categories are the one thing here that can never change.** ARCH_1 §5.3
/// fixes them at three and Law L8 makes cross-category conversion inexpressible, so weight, volume and count
/// are not a filter the user chose — they are the shape of the data, and grouping says so without a sentence.
///
/// Each row states what one of the unit **is**, in its category's base unit: *1 kg = 1,000 g*. A factor shown
/// as `1000000` would be technically the stored value and useless to read.
class UnitsSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const UnitsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final units = ref.watch(unitsSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsUnits)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.unitNew),
        tooltip: strings.unitsAdd,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
      body: units.when(
        loading: () => AlayaListSkeleton(label: strings.unitsLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(unitsSettingsProvider),
        ),
        data: (rows) {
          // Reachable only after somebody deletes every user unit *and* the seed's, which the seeder makes
          // unlikely — but a list screen with no empty state is a list screen that renders a blank rectangle.
          if (rows.isEmpty) {
            return EmptyState(
              title: strings.unitsEmptyTitle,
              body: strings.unitsEmptyBody,
              icon: Icons.straighten_outlined,
              actionLabel: strings.unitsAdd,
              onAction: () => context.push(Routes.unitNew),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
            children: [
              for (final category in UnitCategory.values) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: AlayaSpacing.lg,
                    bottom: AlayaSpacing.xs,
                  ),
                  child: SectionHeader(label: unitCategoryLabel(strings, category)),
                ),
                for (final unit in rows.where((row) => row.category == category))
                  _UnitRow(unit: unit),
              ],
              const SizedBox(height: AlayaSpacing.lg),
              // The rule from ARCH_1 §5.3, stated where somebody about to add a unit will read it — not only
              // as a refusal after they have tried.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
                child: Text(
                  strings.unitsCategoriesFixedNote,
                  style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One unit, stated as what it equals.
class _UnitRow extends StatelessWidget {
  const _UnitRow({required this.unit});

  final Unit unit;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return ListTile(
      title: Row(
        children: [
          Expanded(
            child: Text(
              strings.unitsRowTitle(unit.displayName, unit.code),
              style: AlayaTypography.cardTitle,
            ),
          ),
          if (unit.isSystem) ...[
            const SizedBox(width: AlayaSpacing.xs),
            StatusChip(label: strings.unitsSystemChip, tone: StatusTone.neutral),
          ],
        ],
      ),
      subtitle: Text(
        // `1 kg = 1,000 g`, assembled from the stored thousandths so the reader never meets them.
        strings.unitsEquals(
          unit.code,
          unitBaseAmountLabel(unit),
          unit.category.baseUnitCode,
        ),
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
      onTap: () => context.push(Routes.unitEdit(unit.code)),
    );
  }
}
```

## The escape, and where it goes

**A unit has to be the same amount every time.** A "packet" is not, so it cannot have a factor, so it cannot be
a unit. `UnitCategory`'s doc comment has said since Phase 1A that *"if an amount can't be expressed in one of
these, the correct action is a new Item, never a new category"* — this screen is where that rule finally meets a
person.

Three things make it a refusal worth having rather than a wall:

**It is offered beside the factor field, not thrown back after a failed save.** Somebody with a packet in mind
meets the path before typing a number they will have to defend.

**It explains in terms of what would break, not by quoting the rule.** Alaya could not add two packets together
or work out what one cost. That is the actual consequence, and it is what makes the alternative obviously
better rather than merely mandated.

**The offer goes somewhere.** `Routes.itemNew` exists, so *Create an item instead* is one tap into the item
editor — an offer that dead-ended would be worse than no offer.

The panel replaces the form entirely rather than sitting under it, because leaving the fields visible invites
somebody to type a number they have just been told does not exist. And there is a way back, for anybody who
realises on reading it that they *can* state an amount.

Two smaller decisions: the **code is fixed once the unit exists**, because it is the primary key (ARCH_2 §2);
and the **category is fixed too**, because changing it after quantities exist would reinterpret every one of
them — the same rule as an account's currency, for the same reason. The factor field accepts exactly three
decimals, which is what the milli-precision column holds; a fourth would be silently rounded away at save.

`_ZeroFactor` stringifies to a key rather than a sentence, so the notifier owns the decision and the screen owns
the words (Law U5).

### `lib/features/settings/presentation/screens/unit_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/settings/presentation/widgets/unit_labels.dart';
import 'package:alaya/features/settings/providers/unit_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Creating or editing one unit (ARCH_5 §3 archetype B).
///
/// **The escape is the point of this screen as much as the form is.** A unit has to be the same amount every
/// time; a "packet" is not, so it cannot have a factor, so it cannot be a unit. `UnitCategory`'s own doc has
/// said since Phase 1A that *"if an amount can't be expressed in one of these, the correct action is a new
/// Item, never a new category"* — this screen is where that rule finally meets a person, and it is offered
/// beside the factor field rather than thrown back as a validation error after they have tried.
///
/// **The question is asked in base units, never in the stored thousandths.** "How many grams is one
/// kilogram?" — 1,000 — and `UnitEditorNotifier` multiplies once. Asking for 1,000,000 would be asking the
/// user to reproduce the arithmetic ARCH_4 R18 got wrong three times.
class UnitEditorScreen extends ConsumerStatefulWidget {
  /// Creates the editor. [unitCode] null means a new unit.
  const UnitEditorScreen({this.unitCode, super.key});

  /// The unit being edited, or null for a new one.
  final String? unitCode;

  @override
  ConsumerState<UnitEditorScreen> createState() => _UnitEditorScreenState();
}

class _UnitEditorScreenState extends ConsumerState<UnitEditorScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  UnitCategory _category = UnitCategory.weight;
  int _sortOrder = 0;
  bool _isSystem = false;
  bool _dirty = false;
  bool _loaded = false;

  /// Whether the user has said the amount varies.
  ///
  /// Local rather than in the notifier: it is a state of the conversation, not of the unit — nothing about it
  /// is ever saved, and a provider holding it would survive a route the user has left.
  bool _varies = false;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _adopt(Unit? unit) {
    if (_loaded) return;
    _loaded = true;
    if (unit == null) return;
    _code.text = unit.code;
    _name.text = unit.displayName;
    _category = unit.category;
    _amount.text = unitBaseAmountLabel(unit).replaceAll(',', '');
    _sortOrder = unit.sortOrder;
    _isSystem = unit.isSystem;
  }

  double? get _baseAmount => double.tryParse(_amount.text.trim());

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(unitDraftProvider(widget.unitCode));
    final editing = ref.watch(unitEditorProvider);

    return draft.when(
      loading: () => _shell(strings, const SizedBox.shrink()),
      error: (error, stack) => _shell(
        strings,
        ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(unitDraftProvider(widget.unitCode)),
        ),
      ),
      data: (unit) {
        if (widget.unitCode != null && unit == null) {
          return _shell(
            strings,
            ErrorState(
              title: strings.unitsMissingTitle,
              body: strings.unitsMissingBody,
              retryLabel: strings.actionBack,
              onRetry: () => context.pop(),
            ),
          );
        }
        _adopt(unit);

        // The escape replaces the form entirely. Leaving the fields visible underneath would invite somebody
        // to type a number they have just been told does not exist.
        if (_varies) return _shell(strings, _VariesPanel(onBack: () => setState(() => _varies = false)));

        final amount = _baseAmount;
        final canSave = _code.text.trim().isNotEmpty &&
            _name.text.trim().isNotEmpty &&
            amount != null &&
            amount > 0;

        return _shell(
          strings,
          AlayaFormScaffold(
            primaryLabel: strings.unitEditorSave,
            onPrimary: canSave && !editing.isLoading ? () => _save(unit) : null,
            isDirty: _dirty,
            isSubmitting: editing.isLoading,
            discardTitle: strings.confirmDiscardTitle,
            discardBody: strings.confirmDiscardBody,
            discardConfirmLabel: strings.actionDiscard,
            discardCancelLabel: strings.actionKeepEditing,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  autofocus: unit == null,
                  decoration: InputDecoration(labelText: strings.unitNameLabel),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: AlayaSpacing.md),
                TextField(
                  controller: _code,
                  // The code is a primary key (ARCH_2 §2), so it is fixed once anything references it.
                  enabled: unit == null,
                  decoration: InputDecoration(
                    labelText: strings.unitCodeLabel,
                    helperText: unit == null ? strings.unitCodeHelp : strings.unitCodeLockedHelp,
                  ),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: AlayaSpacing.lg),
                SectionHeader(label: strings.unitCategoryHeader),
                const SizedBox(height: AlayaSpacing.xxs),
                Text(
                  unit == null
                      ? strings.unitCategoryNewHelp
                      : strings.unitCategoryLockedHelp,
                  style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
                ),
                const SizedBox(height: AlayaSpacing.xs),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    for (final category in UnitCategory.values)
                      ChoiceChip(
                        label: Text(
                          unitCategoryLabel(strings, category),
                          style: AlayaTypography.button,
                        ),
                        selected: category == _category,
                        // Changing a unit's category after quantities exist would reinterpret every one of
                        // them, so it is offered only while the unit is new — the same rule as an account's
                        // currency, for the same reason.
                        onSelected: unit == null
                            ? (_) => setState(() {
                                  _category = category;
                                  _dirty = true;
                                })
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: AlayaSpacing.lg),
                SectionHeader(label: strings.unitFactorHeader),
                const SizedBox(height: AlayaSpacing.xs),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    // Three decimals, which is exactly what the milli-precision column can hold. Allowing a
                    // fourth would silently round it away at save.
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                  ],
                  decoration: InputDecoration(
                    labelText: strings.unitFactorQuestion(
                      unitBaseUnitName(strings, _category),
                      _name.text.trim().isEmpty ? strings.unitFactorThisUnit : _name.text.trim(),
                    ),
                    helperText: strings.unitFactorHelp(unitBaseUnitName(strings, _category)),
                  ),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: AlayaSpacing.xs),
                // Offered, not withheld until failure. This is the path for a "packet" or a "bunch", and a
                // user who has that in mind should meet it before typing a number they will have to defend.
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _varies = true),
                    icon: const Icon(Icons.help_outline, size: AlayaIconSize.md),
                    label: Text(strings.unitFactorVaries, style: AlayaTypography.button),
                  ),
                ),
                if (unit != null && !_isSystem) ...[
                  const SizedBox(height: AlayaSpacing.xl),
                  OutlinedButton(
                    onPressed: editing.isLoading ? null : () => _delete(unit),
                    style: OutlinedButton.styleFrom(foregroundColor: context.semantic.danger),
                    child: Text(strings.unitsDelete, style: AlayaTypography.button),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  Text(
                    strings.unitsDeleteHelp,
                    style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
                  ),
                ],
                if (editing.hasError) ...[
                  const SizedBox(height: AlayaSpacing.md),
                  Text(
                    // `_ZeroFactor` stringifies to a key rather than a sentence, so the screen owns the words
                    // (Law U5) while the notifier owns the decision.
                    editing.error.toString() == 'factorMustBePositive'
                        ? strings.unitFactorMustBePositive
                        : editing.error.toString(),
                    style: AlayaTypography.body.copyWith(color: context.semantic.danger),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _shell(AlayaStrings strings, Widget body) => Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: Text(
            widget.unitCode == null ? strings.unitEditorTitle : strings.unitEditorEditTitle,
          ),
        ),
        body: body,
      );

  Future<void> _save(Unit? existing) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(unitEditorProvider.notifier).save(
          code: _code.text,
          displayName: _name.text,
          category: _category,
          baseUnitsPerUnit: _baseAmount!,
          sortOrder: existing?.sortOrder ?? _sortOrder,
          isSystem: _isSystem,
        );
    if (!mounted || !saved) return;
    showResultSnack(context, message: strings.unitsSaved);
    context.pop();
  }

  Future<void> _delete(Unit unit) async {
    final strings = AlayaStrings.of(context);
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.unitsDeleteConfirmTitle,
      // Says what breaks rather than only what goes: a batch bought in this unit keeps its quantity, and
      // deleting the unit is what makes that quantity unreadable — the R18 failure from the other direction.
      body: strings.unitsDeleteConfirmBody,
      confirmLabel: strings.unitsDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final ok = await ref.read(unitEditorProvider.notifier).delete(unit.code);
    if (!mounted || !ok) return;
    showResultSnack(context, message: strings.unitsDeleted);
    context.pop();
  }
}

/// The explanation, and the offer.
///
/// **A refusal with somewhere to go.** ARCH_1 §5.3 says the answer to an unmeasurable amount is a new Item, and
/// this panel says why in terms of what would break — Alaya could not add two packets together or work out what
/// one cost — rather than quoting the rule. Then it offers the thing that does work, one tap away.
class _VariesPanel extends StatelessWidget {
  const _VariesPanel({required this.onBack});

  /// Returns to the form, for somebody who realises they can state a number after all.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AlayaSpacing.md),
            decoration: BoxDecoration(
              color: semantic.warning.withValues(alpha: 0.12),
              borderRadius: AlayaRadii.borderMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(strings.unitVariesTitle, style: AlayaTypography.bodyEmphasis),
                const SizedBox(height: AlayaSpacing.xs),
                Text(strings.unitVariesWhy, style: AlayaTypography.body),
              ],
            ),
          ),
          const SizedBox(height: AlayaSpacing.lg),
          Text(strings.unitVariesInsteadTitle, style: AlayaTypography.bodyEmphasis),
          const SizedBox(height: AlayaSpacing.xs),
          Text(strings.unitVariesInsteadBody, style: AlayaTypography.body),
          const SizedBox(height: AlayaSpacing.lg),
          FilledButton.icon(
            // Straight to the item editor — the offer is only an offer if it goes somewhere.
            onPressed: () => context.push(Routes.itemNew),
            icon: const Icon(Icons.add, size: AlayaIconSize.md),
            label: Text(strings.unitVariesCreateItem, style: AlayaTypography.button),
          ),
          const SizedBox(height: AlayaSpacing.xs),
          TextButton(
            onPressed: onBack,
            child: Text(strings.unitVariesBack, style: AlayaTypography.button),
          ),
        ],
      ),
    );
  }
}
```

## Payment methods — archetype D over a capture sheet

**Edited in a sheet, not a route.** A payment method is a name and a kind — two fields — and archetype A exists
for exactly that: one required field, keyboard already up, commit as soon as it parses. A full-screen editor
would cost a navigation each way for less work than the transition takes.

`isSystem` is **preserved rather than defaulted** on save, because renaming a seeded method must not quietly
turn it into a user-created one that can then be deleted. The chip on the row says which it is, so nobody goes
hunting for a delete button that is deliberately absent.

### `lib/features/settings/presentation/screens/payment_methods_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/features/settings/presentation/sheets/payment_method_sheet.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Settings › Payment methods (ARCH_5 §3 archetype D, outside the shell).
///
/// **Edited in a sheet, not a route.** A payment method is a name and a kind — two fields — and archetype A
/// exists for exactly that: one required field, the keyboard already up, commit as soon as it parses. A
/// full-screen editor for two fields would cost a navigation each way for less work than the transition.
class PaymentMethodsSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const PaymentMethodsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final methods = ref.watch(paymentMethodsSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsPaymentMethods)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => PaymentMethodSheet.show(context, existing: null, nextSortOrder: 0),
        tooltip: strings.paymentMethodsAdd,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
      body: methods.when(
        loading: () => AlayaListSkeleton(label: strings.paymentMethodsLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(paymentMethodsSettingsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return EmptyState(
              title: strings.paymentMethodsEmptyTitle,
              body: strings.paymentMethodsEmptyBody,
              icon: Icons.credit_card_outlined,
              actionLabel: strings.paymentMethodsAdd,
              onAction: () =>
                  PaymentMethodSheet.show(context, existing: null, nextSortOrder: 0),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
            itemCount: rows.length,
            itemBuilder: (context, index) => _MethodRow(
              method: rows[index],
              nextSortOrder: rows.length,
            ),
          );
        },
      ),
    );
  }
}

class _MethodRow extends ConsumerWidget {
  const _MethodRow({required this.method, required this.nextSortOrder});

  final PaymentMethod method;
  final int nextSortOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return ListTile(
      leading: Icon(_icon(method.kind), size: AlayaIconSize.lg, color: semantic.muted),
      title: Text(method.name, style: AlayaTypography.cardTitle),
      subtitle: Text(
        paymentMethodKindLabel(strings, method.kind),
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
      trailing: method.isSystem
          // A system method is renameable but not removable, and the chip says so before the user goes looking
          // for a delete that is not there.
          ? StatusChip(label: strings.paymentMethodsSystemChip, tone: StatusTone.neutral)
          : IconButton(
              onPressed: () => _delete(context, ref, strings),
              tooltip: strings.paymentMethodsDelete,
              icon: Icon(Icons.delete_outline, size: AlayaIconSize.md, color: semantic.danger),
            ),
      onTap: () =>
          PaymentMethodSheet.show(context, existing: method, nextSortOrder: nextSortOrder),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, AlayaStrings strings) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.paymentMethodsDeleteConfirmTitle,
      // Says what survives: a transaction that used this method keeps its record of having done so.
      body: strings.paymentMethodsDeleteConfirmBody,
      confirmLabel: strings.paymentMethodsDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(paymentMethodEditorProvider.notifier).delete(method.id);
    if (!context.mounted) return;
    if (ok) {
      showResultSnack(context, message: strings.paymentMethodsDeleted);
    } else {
      showFailureSnack(context, message: strings.paymentMethodsDeleteFailed);
    }
  }

  IconData _icon(PaymentMethodKind kind) => switch (kind) {
        PaymentMethodKind.cash => Icons.payments_outlined,
        PaymentMethodKind.upi => Icons.qr_code_2_outlined,
        PaymentMethodKind.bankTransfer => Icons.account_balance_outlined,
        PaymentMethodKind.card => Icons.credit_card_outlined,
        PaymentMethodKind.cheque => Icons.receipt_long_outlined,
        PaymentMethodKind.wallet => Icons.account_balance_wallet_outlined,
        PaymentMethodKind.other => Icons.more_horiz,
      };
}

/// The name of each payment-method kind.
///
/// Exhaustive without a `default`, so a seventh kind fails to compile here rather than rendering blank.
String paymentMethodKindLabel(AlayaStrings strings, PaymentMethodKind kind) => switch (kind) {
      PaymentMethodKind.cash => strings.paymentKindCash,
      PaymentMethodKind.upi => strings.paymentKindUpi,
      PaymentMethodKind.bankTransfer => strings.paymentKindBankTransfer,
      PaymentMethodKind.card => strings.paymentKindCard,
      PaymentMethodKind.cheque => strings.paymentKindCheque,
      PaymentMethodKind.wallet => strings.paymentKindWallet,
      PaymentMethodKind.other => strings.paymentKindOther,
    };
```

### `lib/features/settings/presentation/sheets/payment_method_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/features/settings/presentation/screens/payment_methods_settings_screen.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Naming a payment method (ARCH_5 §3 archetype A).
///
/// One required field with the keyboard already up, the kind as chips rather than a picker, and a full-width
/// commit enabled the moment the name parses.
class PaymentMethodSheet extends ConsumerStatefulWidget {
  /// Creates the sheet. Prefer [show].
  const PaymentMethodSheet({required this.existing, required this.nextSortOrder, super.key});

  /// The method being renamed, or null for a new one.
  final PaymentMethod? existing;

  /// The sort order a new method takes.
  final int nextSortOrder;

  /// Shows the sheet.
  static Future<void> show(
    BuildContext context, {
    required PaymentMethod? existing,
    required int nextSortOrder,
  }) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) =>
            PaymentMethodSheet(existing: existing, nextSortOrder: nextSortOrder),
      );

  @override
  ConsumerState<PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends ConsumerState<PaymentMethodSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late PaymentMethodKind _kind = widget.existing?.kind ?? PaymentMethodKind.cash;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final editing = ref.watch(paymentMethodEditorProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.existing == null
              ? strings.paymentMethodsAdd
              : strings.paymentMethodsEditTitle,
          style: AlayaTypography.sectionHeader,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(labelText: strings.paymentMethodNameLabel),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AlayaSpacing.md),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final kind in PaymentMethodKind.values)
              ChoiceChip(
                label: Text(paymentMethodKindLabel(strings, kind), style: AlayaTypography.button),
                selected: kind == _kind,
                onSelected: (_) => setState(() => _kind = kind),
              ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed:
              _name.text.trim().isEmpty || editing.isLoading ? null : () => _save(strings),
          child: Text(strings.paymentMethodsSave, style: AlayaTypography.button),
        ),
      ],
    );
  }

  Future<void> _save(AlayaStrings strings) async {
    final ok = await ref.read(paymentMethodEditorProvider.notifier).save(
          id: widget.existing?.id,
          name: _name.text,
          kind: _kind,
          sortOrder: widget.existing?.sortOrder ?? widget.nextSortOrder,
          // Preserved rather than defaulted: renaming a seeded method must not quietly turn it into a
          // user-created one that can then be deleted.
          isSystem: widget.existing?.isSystem ?? false,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.paymentMethodsSaved)
        : showFailureSnack(context, message: strings.paymentMethodsSaveFailed);
  }
}
```

## Payees — the one branch that grows without bound

**The only settings branch with a search field.** Every other list here is fixed by the app's shape — five
account kinds, six payment methods, three unit categories — while payees accumulate one per shop the user ever
names. A hundred rows is normal, and scanning fails.

It matches on **`normalizedName`**, so "cafe" finds "Café" — the same normaliser the repository used when it
stored the row, rather than a second rule that would quietly disagree with it.

**Two distinct empty states.** Nothing at all, and nothing matching: the second names the search, because "no
payees" in front of a list the user can see is a lie. The phone field is marked optional, since an unmarked
second field reads as required and is the commonest reason a two-field sheet feels like a form. An empty phone
saves as `null` rather than `''`, so nothing downstream has to know about both.

### `lib/features/settings/presentation/screens/payees_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/settings/presentation/sheets/payee_sheet.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_search_field.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// Settings › Payees (ARCH_5 §3 archetype D, outside the shell).
///
/// **The only settings branch with a search field, because it is the only one that grows without bound.** Every
/// other list here is fixed by the app's shape — five account kinds, six payment methods, three unit categories
/// — while payees accumulate one per shop the user ever names. A hundred rows is normal, and scanning fails.
class PayeesSettingsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const PayeesSettingsScreen({super.key});

  @override
  ConsumerState<PayeesSettingsScreen> createState() => _PayeesSettingsScreenState();
}

class _PayeesSettingsScreenState extends ConsumerState<PayeesSettingsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final payees = ref.watch(payeesSettingsProvider);
    final query = _query.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsPayees)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => PayeeSheet.show(context, existing: null),
        tooltip: strings.payeesAdd,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AlayaSpacing.screenEdge,
              AlayaSpacing.sm,
              AlayaSpacing.screenEdge,
              AlayaSpacing.xs,
            ),
            child: AlayaSearchField(
              hintText: strings.payeesSearchHint,
              clearLabel: strings.actionClear,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: payees.when(
              loading: () => AlayaListSkeleton(label: strings.payeesLoading),
              error: (error, stack) => ErrorState(
                title: strings.errorTitleGeneric,
                body: error.toString(),
                retryLabel: strings.actionRetry,
                onRetry: () => ref.invalidate(payeesSettingsProvider),
              ),
              data: (rows) {
                final matching = query.isEmpty
                    ? rows
                    // Matched on `normalizedName`, so "cafe" finds "Café" — the same normaliser the repository
                    // used when it stored the row, rather than a second rule that would disagree with it.
                    : [for (final row in rows) if (row.normalizedName.contains(query)) row];
                if (rows.isEmpty) {
                  return EmptyState(
                    title: strings.payeesEmptyTitle,
                    body: strings.payeesEmptyBody,
                    icon: Icons.storefront_outlined,
                    actionLabel: strings.payeesAdd,
                    onAction: () => PayeeSheet.show(context, existing: null),
                  );
                }
                // Two distinct empties: nothing at all, and nothing matching. The second names the search,
                // because "no payees" in front of a list the user can see is a lie.
                if (matching.isEmpty) {
                  return EmptyState(
                    title: strings.payeesNoMatchTitle,
                    body: strings.payeesNoMatchBody,
                    icon: Icons.search_off_outlined,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
                  itemCount: matching.length,
                  itemBuilder: (context, index) => _PayeeRow(payee: matching[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PayeeRow extends ConsumerWidget {
  const _PayeeRow({required this.payee});

  final Payee payee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final detail = [
      payeeKindLabel(strings, payee.kind),
      if (payee.phone != null && payee.phone!.isNotEmpty) payee.phone!,
    ].join(' · ');

    return ListTile(
      leading: Icon(Icons.storefront_outlined, size: AlayaIconSize.lg, color: semantic.muted),
      title: Text(payee.name, style: AlayaTypography.cardTitle),
      subtitle: Text(
        detail,
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
      trailing: IconButton(
        onPressed: () => _delete(context, ref, strings),
        tooltip: strings.payeesDelete,
        icon: Icon(Icons.delete_outline, size: AlayaIconSize.md, color: semantic.danger),
      ),
      onTap: () => PayeeSheet.show(context, existing: payee),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, AlayaStrings strings) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.payeesDeleteConfirmTitle,
      body: strings.payeesDeleteConfirmBody,
      confirmLabel: strings.payeesDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(payeeEditorProvider.notifier).delete(payee.id);
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.payeesDeleted)
        : showFailureSnack(context, message: strings.payeesDeleteFailed);
  }
}

/// The name of each payee kind.
String payeeKindLabel(AlayaStrings strings, PayeeKind kind) => switch (kind) {
      PayeeKind.person => strings.payeeKindPerson,
      PayeeKind.merchant => strings.payeeKindMerchant,
      PayeeKind.employer => strings.payeeKindEmployer,
      PayeeKind.utility => strings.payeeKindUtility,
      PayeeKind.other => strings.payeeKindOther,
    };
```

### `lib/features/settings/presentation/sheets/payee_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/settings/presentation/screens/payees_settings_screen.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Naming a payee (ARCH_5 §3 archetype A).
class PayeeSheet extends ConsumerStatefulWidget {
  /// Creates the sheet. Prefer [show].
  const PayeeSheet({required this.existing, super.key});

  /// The payee being edited, or null for a new one.
  final Payee? existing;

  /// Shows the sheet.
  static Future<void> show(BuildContext context, {required Payee? existing}) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => PayeeSheet(existing: existing),
      );

  @override
  ConsumerState<PayeeSheet> createState() => _PayeeSheetState();
}

class _PayeeSheetState extends ConsumerState<PayeeSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.existing?.phone ?? '');
  late PayeeKind _kind = widget.existing?.kind ?? PayeeKind.merchant;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final editing = ref.watch(payeeEditorProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.existing == null ? strings.payeesAdd : strings.payeesEditTitle,
          style: AlayaTypography.sectionHeader,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(labelText: strings.payeeNameLabel),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // Optional, and marked as such. A payee is usually a shop name and nothing else; an unmarked second
        // field reads as required and is the commonest reason a two-field sheet feels like a form.
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: strings.payeePhoneOptionalLabel),
        ),
        const SizedBox(height: AlayaSpacing.md),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final kind in PayeeKind.values)
              ChoiceChip(
                label: Text(payeeKindLabel(strings, kind), style: AlayaTypography.button),
                selected: kind == _kind,
                onSelected: (_) => setState(() => _kind = kind),
              ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed:
              _name.text.trim().isEmpty || editing.isLoading ? null : () => _save(strings),
          child: Text(strings.payeesSave, style: AlayaTypography.button),
        ),
      ],
    );
  }

  Future<void> _save(AlayaStrings strings) async {
    final phone = _phone.text.trim();
    final ok = await ref.read(payeeEditorProvider.notifier).save(
          id: widget.existing?.id,
          name: _name.text,
          kind: _kind,
          // Empty becomes null rather than an empty string, so a "has a phone number" test anywhere else does
          // not have to know about both.
          phone: phone.isEmpty ? null : phone,
          note: widget.existing?.note,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.payeesSaved)
        : showFailureSnack(context, message: strings.payeesSaveFailed);
  }
}
```

## Currencies — toggles only

**Nothing here creates a currency.** The list is the ISO set the seeder installed, and a user-invented currency
would have no rate source, so every amount in it would be permanently unconvertible (ARCH_3 §1). Disabling is
what keeps the pickers short.

**The home currency's switch is disabled rather than hidden.** Law L9 makes it the unit every total is aggregated
into, so disabling it would leave the dashboard with no currency to add up in — and a switch that is *missing*
looks like a rendering fault, while one that is present and inert with a reason beside it is an explanation.

**There is no empty state, and that is not an omission:** `currencies` is seeded by Phase 1C and nothing in the
app can delete a row from it, so an empty list is unreachable rather than merely unlikely. Said in the file so
the next reader does not add one.

### `lib/features/settings/providers/app_settings_providers.dart`

```dart
/// View-model state for the currencies, appearance and security branches (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/entities/currency.dart';

/// Every currency, enabled or not.
final currenciesSettingsProvider = StreamProvider<List<Currency>>(
  (ref) => ref.watch(currencyRepositoryProvider).watchAll(),
);

/// The home currency's code, which cannot be disabled.
final homeCurrencyCodeProvider = FutureProvider<String?>(
  (ref) => ref.watch(settingsRepositoryProvider).readHomeCurrencyCode(),
);

/// Enables and disables currencies.
final currencyToggleProvider =
    NotifierProvider<CurrencyToggleNotifier, AsyncValue<void>>(CurrencyToggleNotifier.new);

/// Writes a currency's enabled flag.
class CurrencyToggleNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Enables or disables [code].
  Future<bool> setEnabled({required String code, required bool isEnabled}) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(currencyRepositoryProvider)
        .setEnabled(code: code, isEnabled: isEnabled);
    if (result.isFailure) {
      state = AsyncError<void>(result.failureOrNull ?? StateError('toggle failed'), StackTrace.current);
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}

/// Whether a lock is configured, for the security branch.
final lockConfiguredProvider = FutureProvider<bool>(
  (ref) => ref.watch(pinServiceProvider).isEnabled,
);
```

### `lib/features/settings/presentation/screens/currencies_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/features/settings/providers/app_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// Settings › Currencies (ARCH_5 §3 archetype D, outside the shell).
///
/// **Enabling and disabling only — nothing here creates a currency.** The list is the ISO set the seeder
/// installed, and a user-invented currency would have no rate source, so every amount in it would be
/// permanently unconvertible (ARCH_3 §1). Disabling is what keeps the pickers short.
///
/// **The home currency cannot be disabled, and the switch says why rather than vanishing.** Law L9 makes it the
/// unit every total is aggregated into; disabling it would leave the dashboard with no currency to add up in.
class CurrenciesSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const CurrenciesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final currencies = ref.watch(currenciesSettingsProvider);
    final home = ref.watch(homeCurrencyCodeProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsCurrencies)),
      body: currencies.when(
        loading: () => AlayaListSkeleton(label: strings.currenciesLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(currenciesSettingsProvider),
        ),
        // No empty state, and that is not an omission: `currencies` is seeded by Phase 1C and nothing in the
        // app can delete a row from it, so an empty list is unreachable rather than merely unlikely.
        data: (rows) => ListView.builder(
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
          itemCount: rows.length,
          itemBuilder: (context, index) => _CurrencyRow(
            currency: rows[index],
            isHome: rows[index].code == home,
          ),
        ),
      ),
    );
  }
}

class _CurrencyRow extends ConsumerWidget {
  const _CurrencyRow({required this.currency, required this.isHome});

  final Currency currency;
  final bool isHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return SwitchListTile(
      value: currency.isEnabled || isHome,
      // Disabled rather than hidden: a switch that is missing looks like a rendering fault, while one that is
      // present and inert with a reason beside it is an explanation (ARCH_5 §10).
      onChanged: isHome ? null : (value) => _toggle(context, ref, strings, value: value),
      // **No chip, and no leading icon.** A `SwitchListTile` reserves room for the switch, so `secondary`
      // plus a chip left the title 172dp — enough to overflow by 2.8px at scale 1 and far worse at two.
      // Both were redundant anyway: every row here is a currency, so an icon says nothing, and the
      // subtitle states in words what the chip said as a badge (Law U17 — words, never only a badge).
      title: Text(
        strings.currenciesRowTitle(currency.code, currency.name),
        style: AlayaTypography.cardTitle,
      ),
      subtitle: Text(
        isHome
            ? strings.currenciesHomeLocked
            : strings.currenciesRowSubtitle(currency.symbol, currency.decimalDigits),
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings, {
    required bool value,
  }) async {
    final ok = await ref
        .read(currencyToggleProvider.notifier)
        .setEnabled(code: currency.code, isEnabled: value);
    if (!context.mounted || ok) return;
    showFailureSnack(context, message: strings.currenciesToggleFailed);
  }
}
```

## Appearance — the visible half of item 23

Part 1 turned both theme providers into persisted `Notifier`s; this is where a person changes them. Each writes
to `app_settings` on selection, so a choice survives a restart — which as bare `StateProvider`s it did not.

**No Save button, deliberately.** A theme is its own preview: the whole tree rethemes on the frame a swatch is
tapped, so a commit would ask the user to confirm something they can already see.

Each palette row previews itself in **its own** colours rather than the active theme's, or five rows would render
identically. And the swatches use `primary`, `accent` and `surfaceRaised` — **the three fields `AlayaColorSet`
actually declares.** I first wrote `secondary`/`tertiary` from Material's vocabulary, which Alaya's palette type
does not use; checking the class caught it. That is exactly the sort of thing that compiles in one's head and not
in the analyzer.

### `lib/features/settings/presentation/screens/appearance_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/app.dart';
import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Settings › Appearance (ARCH_5 §3 archetype D, outside the shell).
///
/// **This is the visible half of ARCH_4 §5.1 item 23.** Part 1 turned `activePaletteProvider` and
/// `themeModeProvider` into persisted `Notifier`s; this is where a person changes them. Both write to
/// `app_settings` on selection, so a choice survives a restart — which as bare `StateProvider`s it did not.
///
/// **No Save button, deliberately.** A theme is its own preview: the whole tree rethemes on the frame the swatch
/// is tapped, so a commit would ask the user to confirm something they can already see. Archetype D has no
/// commit for the same reason.
class AppearanceSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final palette = ref.watch(activePaletteProvider);
    final mode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsAppearance)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AlayaSpacing.screenEdge,
              AlayaSpacing.lg,
              AlayaSpacing.screenEdge,
              AlayaSpacing.xs,
            ),
            child: SectionHeader(label: strings.appearanceModeHeader),
          ),
          for (final option in ThemeMode.values)
            RadioListTile<ThemeMode>(
              value: option,
              groupValue: mode,
              onChanged: (next) {
                if (next == null) return;
                ref.read(themeModeProvider.notifier).use(next);
              },
              title: Text(_modeLabel(strings, option), style: AlayaTypography.body),
              subtitle: option == ThemeMode.system
                  ? Text(
                      strings.appearanceModeSystemHelp,
                      style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
                    )
                  : null,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AlayaSpacing.screenEdge,
              AlayaSpacing.lg,
              AlayaSpacing.screenEdge,
              AlayaSpacing.xs,
            ),
            child: SectionHeader(label: strings.appearancePaletteHeader),
          ),
          for (final preset in AlayaPresets.all)
            _PaletteRow(
              palette: preset,
              selected: preset.name == palette.name,
              onTap: () => ref.read(activePaletteProvider.notifier).use(preset),
            ),
          const SizedBox(height: AlayaSpacing.lg),
          ListTile(
            leading: Icon(Icons.science_outlined,
                size: AlayaIconSize.lg, color: context.semantic.muted),
            title: Text(strings.navThemeLab, style: AlayaTypography.cardTitle),
            subtitle: Text(
              strings.appearanceThemeLabHelp,
              style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
            ),
            trailing: Icon(Icons.chevron_right,
                size: AlayaIconSize.md, color: context.semantic.muted),
            onTap: () => context.push(Routes.themeLab),
          ),
        ],
      ),
    );
  }

  String _modeLabel(AlayaStrings strings, ThemeMode mode) => switch (mode) {
        ThemeMode.system => strings.appearanceModeSystem,
        ThemeMode.light => strings.appearanceModeLight,
        ThemeMode.dark => strings.appearanceModeDark,
      };
}

/// One palette, previewed by its own colours rather than described.
class _PaletteRow extends StatelessWidget {
  const _PaletteRow({required this.palette, required this.selected, required this.onTap});

  final AlayaPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The swatches are drawn from the palette being offered, not from the active theme — a row previewing
    // itself in the *current* palette's colours would render five identical rows.
    //
    // `primary`, `accent` and `surfaceRaised`, because those are the three `AlayaColorSet` actually declares.
    // Material's `secondary`/`tertiary` vocabulary does not appear in Alaya's palette type, and reaching for it
    // from memory is how a preview ends up compiling against the wrong colour system.
    final set = Theme.of(context).brightness == Brightness.dark ? palette.dark : palette.light;
    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final colour in [set.primary, set.accent, set.surfaceRaised])
            Padding(
              padding: const EdgeInsets.only(right: AlayaSpacing.xxs),
              child: Container(
                width: AlayaSpacing.md,
                height: AlayaSpacing.xl,
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: AlayaRadii.borderSm,
                ),
              ),
            ),
        ],
      ),
      title: Text(palette.name, style: AlayaTypography.cardTitle),
      subtitle: Text(
        palette.description,
        style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
      ),
      trailing: selected
          ? Icon(Icons.check_circle, size: AlayaIconSize.md, color: set.primary)
          : null,
      onTap: onTap,
    );
  }
}
```

## Security — the honest paragraph first

**ARCH_3 §2.5 sits at the top of the screen, not the bottom.** Somebody deciding whether to turn a lock on should
read that it stops a person holding the unlocked phone and encrypts nothing *before* the switch, not after. And
there is no padlock glyph here for the same reason there is none on the lock screen.

**Auto-erase defaults off, and turning it on costs a confirmation that names the number.** "After 10 failed
attempts everything on this device is deleted" is the sentence somebody needs to have read — a generic *are you
sure?* would not earn consent to a setting that destroys a household's records. Ten wrong attempts from a child
mashing digits is the scenario, and it is why this is not a default.

Three smaller decisions:

**The PIN rows render nothing until secure storage answers.** A row saying *no PIN set* for one frame to somebody
who has one would be alarming for exactly the wrong reason.

**Removing a PIN routes to the flow that can ask for it.** `PinService.disable` requires the current PIN, so
collecting one on a settings row would either duplicate the keypad or skip the check.

**The auto-lock delay is stated, not configurable.** `autoLockDelay` is a constant in this phase, and a picker
writing a setting nothing reads would be the dead control §10 objects to. `autoLockDelaySettingKey` is reserved,
so 8B can make it real without a migration.

`danger` appears exactly once on this screen — on the one setting that destroys data (§2.4: a state colour, never
emphasis).

### `lib/features/settings/presentation/screens/security_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';
import 'package:alaya/features/settings/providers/app_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Settings › Security (ARCH_5 §3 archetype D, outside the shell).
///
/// **The honest paragraph is at the top, not the bottom.** ARCH_3 §2.5: this PIN stops someone who picks up the
/// unlocked phone, and it does not encrypt anything. Somebody deciding whether to turn a lock on should read that
/// before the switch, not after — and there is no padlock glyph on this screen for the same reason there is none
/// on the lock screen.
///
/// **Auto-erase is off unless the user turns it on, and turning it on costs a confirmation that says what it
/// does** (ARCH_3 §2.3). Ten wrong attempts from a child mashing digits would otherwise destroy a household's
/// entire financial history, which is not a default anybody would choose knowingly.
class SecuritySettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final configured = ref.watch(lockConfiguredProvider).valueOrNull;
    final autoErase = ref.watch(autoEraseEnabledProvider).valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsSecurity)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
        children: [
          Padding(
            padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
            child: Container(
              padding: const EdgeInsets.all(AlayaSpacing.md),
              decoration: BoxDecoration(
                // `muted`, not `info`: AlayaSemanticColors declares income, expense, transfer, warning,
                // danger, success and muted — there is no `info` tone, and this panel is explanatory
                // rather than a state (ARCH_5 §2.4).
                color: semantic.muted.withValues(alpha: 0.12),
                borderRadius: AlayaRadii.borderMd,
              ),
              child: Text(strings.lockHonestBody, style: AlayaTypography.body),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
            child: SectionHeader(label: strings.securityPinHeader),
          ),
          // Null while secure storage answers, so neither branch is guessed. A row that said "no PIN set" for one
          // frame to somebody who has one would be alarming for exactly the wrong reason.
          if (configured == null)
            ListTile(
              title: Text(
                strings.securityChecking,
                style: AlayaTypography.body.copyWith(color: semantic.muted),
              ),
            )
          else if (!configured)
            ListTile(
              leading: Icon(Icons.pin_outlined, size: AlayaIconSize.lg, color: semantic.muted),
              title: Text(strings.securitySetPin, style: AlayaTypography.cardTitle),
              subtitle: Text(
                strings.securitySetPinHelp,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              trailing: Icon(Icons.chevron_right, size: AlayaIconSize.md, color: semantic.muted),
              onTap: () => context.push(Routes.settingsPin),
            )
          else ...[
            ListTile(
              leading: Icon(Icons.pin_outlined, size: AlayaIconSize.lg, color: semantic.muted),
              title: Text(strings.securityChangePin, style: AlayaTypography.cardTitle),
              trailing: Icon(Icons.chevron_right, size: AlayaIconSize.md, color: semantic.muted),
              onTap: () => context.push(Routes.settingsPin),
            ),
            ListTile(
              leading: Icon(Icons.lock_open_outlined,
                  size: AlayaIconSize.lg, color: semantic.muted),
              title: Text(strings.securityRemovePin, style: AlayaTypography.cardTitle),
              subtitle: Text(
                strings.securityRemovePinHelp,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              onTap: () => _removePin(context, ref, strings),
            ),
            const SizedBox(height: AlayaSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
              child: SectionHeader(label: strings.securityAutoLockHeader),
            ),
            ListTile(
              leading: Icon(Icons.timer_outlined, size: AlayaIconSize.lg, color: semantic.muted),
              title: Text(strings.securityAutoLockTitle, style: AlayaTypography.cardTitle),
              // Stated rather than configurable in this phase: `autoLockDelay` is a constant, and offering a
              // picker that wrote a setting nothing reads would be the dead control §10 objects to. The key is
              // reserved (`autoLockDelaySettingKey`) so 8B can make it real without a migration.
              subtitle: Text(
                strings.securityAutoLockBody(autoLockDelay.inSeconds),
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ),
            const SizedBox(height: AlayaSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
              child: SectionHeader(label: strings.securityAutoEraseHeader),
            ),
            SwitchListTile(
              value: autoErase,
              onChanged: (value) => _setAutoErase(context, ref, strings, value: value),
              title: Text(strings.securityAutoEraseTitle, style: AlayaTypography.body),
              subtitle: Text(
                strings.securityAutoEraseBody(autoEraseFailureThreshold),
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              secondary: Icon(
                Icons.delete_forever_outlined,
                size: AlayaIconSize.lg,
                // The one place on this screen `danger` is used, because it is the one setting that destroys
                // data (ARCH_5 §2.4 — a state colour, never emphasis).
                color: autoErase ? semantic.danger : semantic.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _removePin(BuildContext context, WidgetRef ref, AlayaStrings strings) async {
    // Removing a lock needs the PIN, which `PinService.disable` enforces — so this sends the user to the flow
    // that can ask for it rather than collecting a PIN on a settings row.
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.securityRemovePinConfirmTitle,
      body: strings.securityRemovePinConfirmBody,
      confirmLabel: strings.actionContinue,
      cancelLabel: strings.actionCancel,
    );
    if (!confirmed || !context.mounted) return;
    await context.push(Routes.settingsPin);
    if (!context.mounted) return;
    // Re-read on return: the flow may have removed the lock, and this screen's rows are the only thing that
    // would still claim otherwise.
    ref.invalidate(lockConfiguredProvider);
    await ref.read(lockPhaseProvider.notifier).refresh();
  }

  Future<void> _setAutoErase(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings, {
    required bool value,
  }) async {
    if (value) {
      // **The scary confirm, and it names the number.** "After 10 failed attempts everything on this device is
      // deleted" is the sentence somebody needs to have read; a generic "are you sure?" would not earn consent
      // to a setting that destroys a household's records.
      final confirmed = await ConfirmSheet.show(
        context,
        title: strings.securityAutoEraseConfirmTitle,
        body: strings.securityAutoEraseConfirmBody(autoEraseFailureThreshold),
        confirmLabel: strings.securityAutoEraseConfirmAction,
        cancelLabel: strings.actionCancel,
        destructive: true,
      );
      if (!confirmed || !context.mounted) return;
    }
    final result = await ref.read(settingsRepositoryProvider).writeValue(
          key: autoEraseSettingKey,
          value: value ? 'true' : 'false',
          valueType: 'string',
        );
    if (!context.mounted) return;
    if (result.isFailure) {
      showFailureSnack(context, message: strings.securityAutoEraseFailed);
      return;
    }
    ref.invalidate(autoEraseEnabledProvider);
    showResultSnack(
      context,
      message: value ? strings.securityAutoEraseOn : strings.securityAutoEraseOff,
    );
  }
}
```

## Data, and About — the last two

**Data exports only, in this phase.** ARCH_4 §5.1 and ARCH_5 §8 give the full Backup and Restore screens to 8B;
what belongs here now is the one action two of 8A's own flows already perform, so the setting and the security
prompts share a path rather than growing two. §3.4's warning is on the row *and* in the confirmation, because the
share sheet is where data leaves the device and the warning should be the last thing read rather than the first
thing scrolled past. The result snack **names the file** — a backup the user cannot identify later is one they
will not trust when they need it.

**Restore is stated as not-yet-here rather than offered and broken.** It needs the Storage Access Framework picker
and a merge strategy, both 8B's. A row opening a file browser that led nowhere would be worse than one saying when
it arrives (§10).

**About carries no version number, and that is a dependency decision rather than an oversight.** Reading one at
runtime needs `package_info_plus`, which ARCH_1 §7 does not pin — adding a package so one row can show a string is
the opposite of §7.4's discipline. A hard-coded constant would be worse: wrong from the first release that forgot
to update it, which misleads more than saying nothing. The licence page is Flutter's own `showLicensePage`, which
enumerates every dependency from the build rather than from a hand-maintained list.

### `lib/features/settings/presentation/screens/data_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Settings › Data (ARCH_5 §3 archetype D, outside the shell).
///
/// **Export only, in this phase.** ARCH_4 §5.1 and ARCH_5 §8 give the full Backup and Restore screens to 8B; what
/// belongs here now is the one action two of 8A's own flows already perform — a share of the database file — so
/// that the setting and the security prompts use the same path rather than two.
///
/// **ARCH_3 §3.4's warning is on the button every time**, not once in a help page: the file is a plaintext copy
/// of every balance the user has, and anyone who receives it can read it.
class DataSettingsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const DataSettingsScreen({super.key});

  @override
  ConsumerState<DataSettingsScreen> createState() => _DataSettingsScreenState();
}

class _DataSettingsScreenState extends ConsumerState<DataSettingsScreen> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsData)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AlayaSpacing.screenEdge,
              AlayaSpacing.lg,
              AlayaSpacing.screenEdge,
              AlayaSpacing.xs,
            ),
            child: SectionHeader(label: strings.dataBackupHeader),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
            child: Container(
              padding: const EdgeInsets.all(AlayaSpacing.md),
              decoration: BoxDecoration(
                color: semantic.warning.withValues(alpha: 0.12),
                borderRadius: AlayaRadii.borderMd,
              ),
              child: Text(strings.backupNotEncryptedWarning, style: AlayaTypography.bodyEmphasis),
            ),
          ),
          ListTile(
            leading: Icon(Icons.ios_share_outlined,
                size: AlayaIconSize.lg, color: semantic.muted),
            title: Text(strings.dataExportTitle, style: AlayaTypography.cardTitle),
            subtitle: Text(
              strings.dataExportBody,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            enabled: !_working,
            onTap: () => _export(strings),
          ),
          const SizedBox(height: AlayaSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
            child: SectionHeader(label: strings.dataRestoreHeader),
          ),
          // **Stated as not-yet-here rather than offered and broken.** A restore needs the Storage Access
          // Framework picker and a merge strategy, both of which are 8B's — and a row that opened a file browser
          // leading nowhere would be worse than a row that says when it arrives (ARCH_5 §10).
          ListTile(
            leading: Icon(Icons.settings_backup_restore_outlined,
                size: AlayaIconSize.lg, color: semantic.muted),
            title: Text(strings.dataRestoreTitle, style: AlayaTypography.cardTitle),
            subtitle: Text(
              strings.dataRestorePending,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            enabled: false,
          ),
        ],
      ),
    );
  }

  Future<void> _export(AlayaStrings strings) async {
    // Confirmed before it runs, because the share sheet is where the data leaves the device and the warning has
    // to be the last thing read rather than the first thing scrolled past.
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.dataExportConfirmTitle,
      body: strings.backupNotEncryptedWarning,
      confirmLabel: strings.dataExportConfirmAction,
      cancelLabel: strings.actionCancel,
    );
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    final result = await ref.read(dataTransferPortProvider).exportAndShare();
    if (!mounted) return;
    setState(() => _working = false);
    final artefact = result.valueOrNull;
    if (artefact == null) {
      showFailureSnack(
        context,
        message: result.failureOrNull?.message ?? strings.dataExportFailed,
      );
      return;
    }
    // Names the file, because a backup the user cannot identify later is one they will not trust when they need
    // it (ARCH_3 §3.4).
    showResultSnack(context, message: strings.dataExportDone(artefact.fileName));
  }
}
```

### `lib/features/settings/presentation/screens/about_settings_screen.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Settings › About (ARCH_5 §3 archetype D, outside the shell).
///
/// **No version number, and that is a dependency decision rather than an oversight.** Reading one at runtime needs
/// `package_info_plus`, which ARCH_1 §7 does not pin — and adding a package so that one row can show a string
/// would be the opposite of §7.4's discipline. A hard-coded constant would be worse: it would be wrong from the
/// first release that forgot to update it, which is more misleading than saying nothing.
///
/// The licence page is Flutter's own `showLicensePage`, which enumerates every dependency's licence from the
/// build rather than from a list somebody has to maintain by hand.
class AboutSettingsScreen extends StatelessWidget {
  /// Creates the screen.
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsAbout)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
        children: [
          Padding(
            padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(strings.appName, style: AlayaTypography.screenTitle),
                const SizedBox(height: AlayaSpacing.xs),
                Text(strings.aboutTagline, style: AlayaTypography.body),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
            child: SectionHeader(label: strings.aboutHowItWorksHeader),
          ),
          Padding(
            padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The same threat model the lock screen states, in the place somebody comes looking for it. Saying
                // it in two places is not duplication — one is a decision point and the other is where a question
                // gets answered.
                Text(strings.aboutOfflineBody, style: AlayaTypography.body),
                const SizedBox(height: AlayaSpacing.sm),
                Text(strings.aboutStorageBody, style: AlayaTypography.body),
              ],
            ),
          ),
          ListTile(
            leading: Icon(Icons.description_outlined,
                size: AlayaIconSize.lg, color: semantic.muted),
            title: Text(strings.aboutLicences, style: AlayaTypography.cardTitle),
            subtitle: Text(
              strings.aboutLicencesHelp,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            trailing: Icon(Icons.chevron_right, size: AlayaIconSize.md, color: semantic.muted),
            onTap: () => showLicensePage(
              context: context,
              applicationName: strings.appName,
            ),
          ),
        ],
      ),
    );
  }
}
```

## `app_en.arb`

**995 message keys, up from 696.** The 299 additions were not written from memory — they were extracted from the
call sites, which is the only way to guarantee both directions: no key referenced that does not exist, and no key
added that nothing uses. Verified as exactly 299, with **no missing and no surplus**, and every `strings.*` in
both documents resolving.

The extraction caught four things memory would not have:

**`unitCategoryWeight`, `unitCategoryVolume`, `unitCategoryCount` and `unitCategoryLockedHelp` already existed**
from Phase 6B. I would have added parallel keys for all four.

**`discardTitle`, `discardBody`, `discardConfirm` were keys I had invented.** The established ones are
`confirmDiscardTitle`, `confirmDiscardBody` and `actionDiscard`, which is what 6A's editors pass. Renamed at every
call site in both documents.

**The discard cancel label is `actionKeepEditing`, not `actionCancel`.** That is what 6A uses, and *Keep editing*
is better copy in a discard prompt than *Cancel*, which reads as cancelling the discard.

**Two placeholder arities were wrong** in my first pass — a regex counting trailing commas made `unitsEquals` look
like four arguments and `unitFactorQuestion` like three. Read from the call sites instead, then asserted against
them: 21 parameterised keys, all matching.

Descriptions are on 51 of the 299 (17%), which is lower than the file's 70% average and deliberate: a description
belongs where the *reason* is not evident from the string, and `accountKindCash: "Cash"` has no reason to
document. Where they do appear they carry the argument — Law U9's insistence on the repository's own message,
anomaly A03's balance-and-date pair, ARCH_1 §5.3's answer to an unmeasurable amount.

Two strings deserve singling out. **`lockHonestBody`** is ARCH_3 §2.5 and the most important string in the app:
it says the PIN stops someone holding the unlocked phone and does **not** encrypt anything. **`unitVariesWhy`**
explains ARCH_1 §5.3 by consequence rather than by quoting the rule — *Alaya could not add two packets together
or work out what one cost* — which is what makes the alternative obviously better instead of merely mandated.

### `lib/app/l10n/app_en.arb`

```json
{
  "@@locale": "en",
  "appName": "Alaya",
  "@appName": {
    "description": "The app's name, shown in the drawer header."
  },
  "navDashboard": "Dashboard",
  "navExpenses": "Expenses",
  "navInventory": "Inventory",
  "navShopping": "Shopping",
  "navRecurring": "Recurring",
  "navServices": "Services",
  "navCalendar": "Calendar",
  "navInsights": "Insights",
  "navSettings": "Settings",
  "navThemeLab": "Theme Lab",
  "actionSave": "Save",
  "@actionSave": {
    "description": "Commits an edit. Active voice, and the same word appears in the resulting confirmation."
  },
  "actionSaved": "Saved",
  "actionCancel": "Cancel",
  "actionDelete": "Delete",
  "actionDeleted": "Deleted",
  "actionUndo": "Undo",
  "actionRetry": "Try again",
  "actionAdd": "Add",
  "actionEdit": "Edit",
  "actionDone": "Done",
  "actionClose": "Close",
  "actionSelect": "Select",
  "actionClear": "Clear",
  "actionClearAll": "Clear all",
  "actionSearch": "Search",
  "actionConfirm": "Confirm",
  "actionDiscard": "Discard",
  "actionKeepEditing": "Keep editing",
  "actionRemoveTag": "Remove tag",
  "@actionRemoveTag": {
    "description": "Accessibility label for the dismiss affordance on a removable tag chip."
  },
  "actionClearSearch": "Clear search",
  "@actionClearSearch": {
    "description": "Accessibility label for the clear button inside AlayaSearchField."
  },
  "addExpense": "Add expense",
  "addIncome": "Add income",
  "addTransfer": "Add transfer",
  "addItem": "Add item",
  "addToShoppingList": "Add to shopping list",
  "dateToday": "Today",
  "@dateToday": {
    "description": "DateText.relative, when the date is the clock's today. Sentence case; it can begin a row."
  },
  "dateYesterday": "Yesterday",
  "dateTomorrow": "Tomorrow",
  "emptyTitleNoTransactions": "No transactions yet",
  "emptyBodyNoTransactions": "Add your first expense and it will appear here.",
  "@emptyBodyNoTransactions": {
    "description": "An empty screen is an invitation to act, so this names the action rather than describing the emptiness."
  },
  "emptyTitleNoItems": "Nothing in your inventory",
  "emptyBodyNoItems": "Add an item to start tracking what you have at home.",
  "emptyTitleNoShopping": "Your list is empty",
  "emptyBodyNoShopping": "Add something, or let Alaya suggest items you are low on.",
  "emptyTitleNoRecurring": "No recurring bills",
  "emptyBodyNoRecurring": "Set up a bill or subscription and Alaya will remind you when it is due.",
  "emptyTitleNoResults": "No matches",
  "emptyBodyNoResults": "Try a shorter search, or check the spelling.",
  "loadingLabel": "Loading",
  "loadingTransactions": "Loading transactions",
  "errorTitleGeneric": "That did not work",
  "@errorTitleGeneric": {
    "description": "Errors do not apologise and are never vague. This pairs with a specific body message."
  },
  "errorBodyGeneric": "Something went wrong on our side. Try again.",
  "errorTitleNotFound": "Not found",
  "errorBodyNotFound": "This item may have been deleted.",
  "errorBodyNoConnection": "You are offline. Alaya works offline, but rates will not refresh.",
  "errorFieldRequired": "This is required",
  "errorAmountInvalid": "Enter an amount",
  "errorAmountZero": "Enter an amount greater than zero",
  "errorAmountInvalidCharacter": "Digits only",
  "errorAmountNegativeNotAllowed": "Enter a positive amount",
  "errorAmountTooManyDecimals": "Too many decimal places",
  "errorAmountTooLarge": "That amount is too large",
  "errorQuantityTooLarge": "That quantity is too large",
  "errorQuantityInvalid": "Enter a quantity",
  "errorQuantityInvalidCharacter": "Digits only",
  "errorQuantityNegativeNotAllowed": "Enter a positive quantity",
  "errorQuantityTooPrecise": "Too precise for this unit",
  "@errorQuantityTooPrecise": {
    "description": "The typed quantity is finer than the chosen unit can express exactly. Shown rather than rounded, because rounding a quantity silently changes what the user recorded."
  },
  "errorDateInvalid": "Choose a date",
  "confirmDeleteTitle": "Delete this?",
  "confirmDeleteBody": "You can undo this for the next few seconds.",
  "confirmDiscardTitle": "Discard your changes?",
  "confirmDiscardBody": "What you have typed will not be saved.",
  "labelAmount": "Amount",
  "labelQuantity": "Quantity",
  "labelUnit": "Unit",
  "labelDate": "Date",
  "labelAccount": "Account",
  "labelPaymentMethod": "Payment method",
  "labelPayee": "Payee",
  "labelCategory": "Category",
  "labelTags": "Tags",
  "labelNote": "Note",
  "labelFrom": "From",
  "labelTo": "To",
  "labelItem": "Item",
  "labelExpiry": "Expiry",
  "labelTotal": "Total",
  "hintSelectAccount": "Choose an account",
  "hintSelectUnit": "Choose a unit",
  "hintSelectTags": "Choose tags",
  "hintSelectDate": "Choose a date",
  "hintSearchItems": "Search items",
  "hintNote": "Add a note",
  "amountUnconverted": "{count, plural, =1{1 amount not converted} other{{count} amounts not converted}}",
  "@amountUnconverted": {
    "description": "The chip beside a total when some amounts had no exchange rate. Surfaced rather than hidden, because a total missing a row is otherwise indistinguishable from a complete one.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "amountApproximate": "Approximate rate",
  "@amountApproximate": {
    "description": "Shown when a conversion used the nearest earlier rate rather than the exact date's."
  },
  "tagCountMore": "+{count}",
  "@tagCountMore": {
    "description": "Overflow indicator when a row cannot show every tag.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "statusNeedsReview": "Needs details",
  "@statusNeedsReview": {
    "description": "StatusChip on a transaction saved by quick-add. Names what is missing, not that a flag is set."
  },
  "statusUnallocated": "Unallocated",
  "@statusUnallocated": {
    "description": "StatusChip label when a transaction's lines do not sum to its amount. The figure is a separate AmountText (U7); never auto-balanced (anomaly A11)."
  },
  "statusDetached": "Receipt deleted",
  "@statusDetached": {
    "description": "StatusChip on a batch whose source transaction was deleted. The food did not un-exist."
  },
  "statusApproximate": "Approximate",
  "lowStockLabel": "Low",
  "expiringSoonLabel": "Expiring soon",
  "expiredLabel": "Expired",
  "overdueLabel": "Overdue",
  "dueTodayLabel": "Due today",
  "paidLabel": "Paid",
  "skippedLabel": "Skipped",
  "kindDeposit": "Money in",
  "kindWithdrawal": "Money out",
  "kindTransfer": "Transfer",
  "kindAdjustmentIncrease": "Correction up",
  "kindAdjustmentDecrease": "Correction down",
  "subtypeGrocery": "Groceries",
  "subtypeHousehold": "Household",
  "subtypeElectronics": "Electronics",
  "subtypeBill": "Bill",
  "subtypeTransferSelf": "Between my accounts",
  "subtypeTransferOut": "Sent to someone",
  "subtypeSalaryIn": "Salary",
  "subtypeOtherIn": "Other income",
  "subtypeOtherOut": "Other spending",
  "needsReviewBanner": "{count, plural, =1{1 transaction needs details} other{{count} transactions need details}}",
  "@needsReviewBanner": {
    "description": "Surfaces transactions.needsReview. Quick-add saves an amount and nothing else by design; without this row that deliberate shortcut becomes silent data rot.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "needsReviewAction": "Review",
  "filterTitle": "Filter",
  "filterDateRange": "Date range",
  "filterKind": "Type",
  "filterSubtype": "Category",
  "filterApply": "Show results",
  "filterReset": "Reset",
  "filterChipAccount": "Account: {name}",
  "@filterChipAccount": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipPayee": "Payee: {name}",
  "@filterChipPayee": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipRange": "{label}",
  "@filterChipRange": {
    "placeholders": {
      "label": {
        "type": "String"
      }
    }
  },
  "rangeToday": "Today",
  "rangeLast7Days": "Last 7 days",
  "rangeLast30Days": "Last 30 days",
  "rangeThisMonth": "This month",
  "rangeLastMonth": "Last month",
  "rangeThisYear": "This year",
  "rangeAllTime": "All time",
  "rangeCustom": "Custom",
  "searchTransactionsHint": "Search notes",
  "transactionDeleted": "Transaction deleted",
  "quickAddTitle": "Quick add",
  "quickAddMoneyIn": "Money in",
  "quickAddMoneyOut": "Money out",
  "quickAddSave": "Save",
  "actionAddDetails": "Add details",
  "editorTitleNew": "New transaction",
  "editorTitleEdit": "Edit transaction",
  "sectionWhatAndHowMuch": "What and how much",
  "sectionWhereItCameFrom": "Where it came from",
  "sectionWhereItWent": "Where it went",
  "sectionWhatYouBought": "What you bought",
  "sectionWarranty": "Warranty",
  "sectionSchedule": "Schedule",
  "transferOwnAccount": "To my own account",
  "transferSomeoneElse": "To someone else",
  "transferOwnAccountHelp": "Moves money between your accounts. Your total does not change.",
  "transferSomeoneElseHelp": "Money leaves your accounts. This is a withdrawal.",
  "alsoAddToInventory": "Also add to inventory",
  "destinationNone": "Just an expense",
  "destinationInventory": "Save to Inventory",
  "destinationAsset": "Save to Services",
  "destinationRecurring": "Save to Recurring",
  "lineAdd": "Add item",
  "lineDescription": "Item",
  "lineUnitPrice": "Unit price",
  "lineAmount": "Line total",
  "lineCreatedLink": "Created: {name}",
  "@lineCreatedLink": {
    "description": "Surfaces transaction_lines.created*Id — the artefact this line produced, tappable through to it.",
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "payeeCreate": "New payee “{name}”",
  "@payeeCreate": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "saveExpense": "Save expense",
  "saveIncome": "Save income",
  "saveTransfer": "Save transfer",
  "detailSectionLines": "Items",
  "detailSectionDetails": "Details",
  "actionFreezeConversion": "Show in another currency",
  "frozenConversionNote": "Frozen on {date} at {rate}",
  "@frozenConversionNote": {
    "description": "Surfaces transactions.converted*/conversionRateRaw. A separate artefact that is never recomputed (Law L9).",
    "placeholders": {
      "date": {
        "type": "String"
      },
      "rate": {
        "type": "String"
      }
    }
  },
  "deleteReasonHint": "Why? (optional)",
  "actionDeleteTransaction": "Delete transaction",
  "labelSubtype": "Category",
  "labelKind": "Type",
  "themeLabTitle": "Theme Lab",
  "themeLabSubtitle": "Every token, component and semantic colour, light and dark.",
  "themeLabSectionSpacing": "Spacing",
  "themeLabSectionRadii": "Radii",
  "themeLabSectionTypography": "Typography",
  "themeLabSectionElevation": "Elevation",
  "themeLabSectionSemantic": "Semantic colours",
  "themeLabSectionSurfaces": "Surface tiers",
  "themeLabSectionComponents": "Components",
  "themeLabSectionPalettes": "Palettes",
  "themeLabLight": "Light",
  "themeLabDark": "Dark",
  "semanticIncome": "Income",
  "semanticExpense": "Expense",
  "semanticTransfer": "Transfer",
  "semanticWarning": "Warning",
  "semanticDanger": "Danger",
  "semanticSuccess": "Success",
  "semanticMuted": "Muted",
  "drawerSectionMoney": "Money",
  "drawerSectionHome": "Home",
  "drawerSectionMore": "More",
  "inventoryGroupFavourites": "Favourites",
  "@inventoryGroupFavourites": {
    "description": "Phase 6B — inventory."
  },
  "inventoryGroupUntagged": "Everything else",
  "@inventoryGroupUntagged": {
    "description": "Phase 6B — inventory."
  },
  "itemKindGeneric": "General",
  "@itemKindGeneric": {
    "description": "Phase 6B — inventory."
  },
  "itemKindFood": "Food",
  "@itemKindFood": {
    "description": "Phase 6B — inventory."
  },
  "itemKindMedicine": "Medicine",
  "@itemKindMedicine": {
    "description": "Phase 6B — inventory."
  },
  "itemKindBeauty": "Beauty",
  "@itemKindBeauty": {
    "description": "Phase 6B — inventory."
  },
  "itemKindHousehold": "Household",
  "@itemKindHousehold": {
    "description": "Phase 6B — inventory."
  },
  "itemKindOther": "Other",
  "@itemKindOther": {
    "description": "Phase 6B — inventory."
  },
  "filterFavouritesOnly": "Favourites only",
  "@filterFavouritesOnly": {
    "description": "Phase 6B — inventory."
  },
  "actionFavourite": "Add to favourites",
  "@actionFavourite": {
    "description": "Phase 6B — inventory."
  },
  "actionUnfavourite": "Remove from favourites",
  "@actionUnfavourite": {
    "description": "Phase 6B — inventory."
  },
  "outOfStockLabel": "Out of stock",
  "@outOfStockLabel": {
    "description": "Phase 6B — inventory."
  },
  "itemBatchCount": "{count, plural, =1{1 batch} other{{count} batches}}",
  "@itemBatchCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "loadingInventory": "Loading inventory",
  "@loadingInventory": {
    "description": "Phase 6B — inventory."
  },
  "detailSectionBatches": "Batches",
  "@detailSectionBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginPurchase": "From a purchase",
  "@batchOriginPurchase": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginManual": "Added by hand",
  "@batchOriginManual": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginImported": "Imported",
  "@batchOriginImported": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginAdjustment": "From an adjustment",
  "@batchOriginAdjustment": {
    "description": "Phase 6B — inventory."
  },
  "labelPurchased": "Purchased",
  "@labelPurchased": {
    "description": "Phase 6B — inventory."
  },
  "labelStorageLocation": "Stored in",
  "@labelStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "labelUnitCost": "Unit cost",
  "@labelUnitCost": {
    "description": "Phase 6B — inventory."
  },
  "labelInitial": "Bought",
  "@labelInitial": {
    "description": "Phase 6B — inventory."
  },
  "labelNearestExpiry": "Nearest expiry",
  "@labelNearestExpiry": {
    "description": "Phase 6B — inventory."
  },
  "labelDisplayUnit": "Shown in",
  "@labelDisplayUnit": {
    "description": "Phase 6B — inventory."
  },
  "labelItemKind": "Kind",
  "@labelItemKind": {
    "description": "Phase 6B — inventory."
  },
  "labelLowStockThreshold": "Low-stock level",
  "@labelLowStockThreshold": {
    "description": "Phase 6B — inventory."
  },
  "labelExpiryNotifyDays": "Warn before expiry",
  "@labelExpiryNotifyDays": {
    "description": "Phase 6B — inventory."
  },
  "actionConsume": "Use some",
  "@actionConsume": {
    "description": "Phase 6B — inventory."
  },
  "actionAddBatch": "Add a batch",
  "@actionAddBatch": {
    "description": "Phase 6B — inventory."
  },
  "actionViewHistory": "Movement history",
  "@actionViewHistory": {
    "description": "Phase 6B — inventory."
  },
  "actionDeleteItem": "Delete item",
  "@actionDeleteItem": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemTitle": "Delete this item?",
  "@confirmDeleteItemTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemBody": "Its {count, plural, =1{1 batch} other{{count} batches}} go with it. The movement history stays, so what you already used is still recorded.",
  "@confirmDeleteItemBody": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "itemDeleted": "Item deleted",
  "@itemDeleted": {
    "description": "Phase 6B — inventory."
  },
  "expiresInDays": "{days, plural, =0{Expires today} =1{Expires tomorrow} other{Expires in {days} days}}",
  "@expiresInDays": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "expiredDaysAgo": "{days, plural, =1{Expired yesterday} other{Expired {days} days ago}}",
  "@expiredDaysAgo": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "sectionWhatItIs": "What it is",
  "@sectionWhatItIs": {
    "description": "Phase 6B — inventory."
  },
  "sectionStockRules": "Stock rules",
  "@sectionStockRules": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryWeight": "Weight",
  "@unitCategoryWeight": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryVolume": "Volume",
  "@unitCategoryVolume": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryCount": "Count",
  "@unitCategoryCount": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryLocked": "Measured in {category}",
  "@unitCategoryLocked": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "category": {}
    }
  },
  "unitCategoryLockedHelp": "This cannot change. Every batch and movement already recorded is stored in this measure, and there is no conversion between weight, volume and count.",
  "@unitCategoryLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "expiryNotifyDaysHelp": "Days of warning before a batch expires.",
  "@expiryNotifyDaysHelp": {
    "description": "Phase 6B — inventory."
  },
  "labelFavourite": "Favourite",
  "@labelFavourite": {
    "description": "Phase 6B — inventory."
  },
  "saveItem": "Save item",
  "@saveItem": {
    "description": "Phase 6B — inventory."
  },
  "sectionHowMuch": "How much",
  "@sectionHowMuch": {
    "description": "Phase 6B — inventory."
  },
  "sectionBatchDetails": "Batch details",
  "@sectionBatchDetails": {
    "description": "Phase 6B — inventory."
  },
  "saveBatch": "Save batch",
  "@saveBatch": {
    "description": "Phase 6B — inventory."
  },
  "batchSaved": "Batch saved",
  "@batchSaved": {
    "description": "Phase 6B — inventory."
  },
  "hintStorageLocation": "Freezer, pantry, bathroom shelf…",
  "@hintStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "consumeTitle": "Use stock",
  "@consumeTitle": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindConsume": "Used",
  "@consumeKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindWaste": "Thrown away",
  "@consumeKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindExpired": "Expired",
  "@consumeKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "consumeRecorded": "Recorded",
  "@consumeRecorded": {
    "description": "Phase 6B — inventory."
  },
  "consumeFromLabel": "Taking from",
  "@consumeFromLabel": {
    "description": "Phase 6B — inventory."
  },
  "consumeFefoNote": "Oldest expiry first.",
  "@consumeFefoNote": {
    "description": "Phase 6B — inventory."
  },
  "consumeSpansBatches": "{count, plural, =1{Takes all of 1 batch} other{Spans {count} batches, writing {count} movements}}",
  "@consumeSpansBatches": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "consumeOverAvailable": "More than you have on hand",
  "@consumeOverAvailable": {
    "description": "Phase 6B — inventory."
  },
  "historyTitle": "Movement history",
  "@historyTitle": {
    "description": "Phase 6B — inventory."
  },
  "movementKindOpeningIn": "Opening stock",
  "@movementKindOpeningIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindPurchaseIn": "Bought",
  "@movementKindPurchaseIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindManualIn": "Added by hand",
  "@movementKindManualIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindConsume": "Used",
  "@movementKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "movementKindWaste": "Thrown away",
  "@movementKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "movementKindExpired": "Expired",
  "@movementKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustIn": "Adjusted up",
  "@movementKindAdjustIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustOut": "Adjusted down",
  "@movementKindAdjustOut": {
    "description": "Phase 6B — inventory."
  },
  "movementReversed": "Reversed",
  "@movementReversed": {
    "description": "Phase 6B — inventory."
  },
  "movementIsReversal": "Reverses an earlier movement",
  "@movementIsReversal": {
    "description": "Phase 6B — inventory."
  },
  "actionReverse": "Reverse",
  "@actionReverse": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseTitle": "Reverse this movement?",
  "@confirmReverseTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseBody": "An opposite movement is appended. Nothing is erased — both entries stay in the history.",
  "@confirmReverseBody": {
    "description": "Phase 6B — inventory."
  },
  "movementReversedSnack": "Movement reversed",
  "@movementReversedSnack": {
    "description": "Phase 6B — inventory."
  },
  "emptyTitleNoMovements": "Nothing recorded yet",
  "@emptyTitleNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoMovements": "Using, wasting or adjusting this batch will show up here.",
  "@emptyBodyNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoBatches": "Add a batch and it will appear here with its expiry.",
  "@emptyBodyNoBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchQuantityLockedHelp": "How much is left is worked out from the movement history. Use, waste or adjust the batch to change it.",
  "@batchQuantityLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "daysCount": "{days, plural, =1{1 day} other{{days} days}}",
  "@daysCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "groupByFavourites": "Group favourites first",
  "@groupByFavourites": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitUsed": "Record as used",
  "@consumeCommitUsed": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitWaste": "Record as thrown away",
  "@consumeCommitWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitExpired": "Record as expired",
  "@consumeCommitExpired": {
    "description": "Phase 6B — inventory."
  },
  "lowStockWithCount": "Low · {count}",
  "@lowStockWithCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "actionDeleteBatch": "Delete batch",
  "@actionDeleteBatch": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchTitle": "Delete this batch?",
  "@confirmDeleteBatchTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchBody": "The stock it still holds disappears from your on-hand total. What you already used stays in the movement history.",
  "@confirmDeleteBatchBody": {
    "description": "Phase 6B — inventory."
  },
  "batchDeleted": "Batch deleted",
  "@batchDeleted": {
    "description": "Phase 6B — inventory."
  },
  "itemCreate": "New item",
  "@itemCreate": {
    "description": "Creates a catalogued item inline while itemising a receipt."
  },
  "itemCreateHint": "No items yet — create one so this line becomes stock.",
  "@itemCreateHint": {
    "description": "Shown in the line editor when the item catalogue is empty."
  },
  "itemCreateCategoryPrompt": "How is it measured? This cannot change later.",
  "@itemCreateCategoryPrompt": {
    "description": "Prompt for unitCategory on inline creation; immutable after create (Law L8)."
  },
  "itemDuplicateBody": "You already have this item, measured the same way. Open the one you have instead of adding a second.",
  "@itemDuplicateBody": {
    "description": "Shown when an item with the same normalized name and unit category exists."
  },
  "itemUnitsMissingBody": "No units are set up for this measure yet. Pick a different measure, or add units in Settings first.",
  "@itemUnitsMissingBody": {
    "description": "Shown when the chosen UnitCategory has no rows in units."
  },
  "itemSimilarNote": "You also have this name under a different measure. That is fine — weight, volume and count never convert into each other.",
  "@itemSimilarNote": {
    "description": "Informational note, never a block: Law L8 makes same-name/different-category distinct items."
  },
  "actionOpenExisting": "Open the one I have",
  "@actionOpenExisting": {
    "description": "Opens the existing item a duplicate collides with."
  },
  "shoppingEstimate": "Estimated",
  "@shoppingEstimate": {
    "description": "Running total of estimated prices on a shopping list."
  },
  "shoppingSwitchList": "Switch list",
  "@shoppingSwitchList": {
    "description": "Opens the list manager from the app bar."
  },
  "shoppingCheckedCount": "{checked} of {total} ticked",
  "@shoppingCheckedCount": {
    "description": "Progress line above a shopping list.",
    "placeholders": {
      "checked": {},
      "total": {}
    }
  },
  "emptyTitleNoEntries": "Nothing on this list yet",
  "@emptyTitleNoEntries": {
    "description": "Shopping list empty state."
  },
  "emptyBodyNoEntries": "Add what you need, or pull in suggestions from what is running low.",
  "@emptyBodyNoEntries": {
    "description": "Shopping list empty state body."
  },
  "addEntry": "Add",
  "@addEntry": {
    "description": "Adds one entry to a shopping list."
  },
  "shoppingGroupUntagged": "Everything else",
  "@shoppingGroupUntagged": {
    "description": "Header for entries with no tag."
  },
  "actionUncheckAll": "Untick everything",
  "@actionUncheckAll": {
    "description": "Clears every tick on a shopping list."
  },
  "entryEditorTitle": "What do you need?",
  "@entryEditorTitle": {
    "description": "Entry editor sheet title."
  },
  "entryFreeTextLabel": "Name it",
  "@entryFreeTextLabel": {
    "description": "Free-text label for a shopping entry."
  },
  "entryFreeTextHint": "Television, birthday card, light bulbs…",
  "@entryFreeTextHint": {
    "description": "Hint showing that an entry need not be an inventory item."
  },
  "entryLinkItem": "Link to an item",
  "@entryLinkItem": {
    "description": "Optional link from a shopping entry to a catalogued item."
  },
  "entryNoItem": "Not in my inventory",
  "@entryNoItem": {
    "description": "Dropdown option leaving itemId null."
  },
  "labelEstimatedPrice": "Estimated price",
  "@labelEstimatedPrice": {
    "description": "Optional per-entry price estimate."
  },
  "entryNeedsSomething": "Give it a name, or link it to an item",
  "@entryNeedsSomething": {
    "description": "Rejection when neither freeText nor itemId is set."
  },
  "originAutoLowStock": "Suggested",
  "@originAutoLowStock": {
    "description": "Chip marking an auto-generated low-stock entry."
  },
  "originPromoted": "Yours now",
  "@originPromoted": {
    "description": "Chip shown once an auto entry has been edited into a manual one."
  },
  "actionSnooze": "Snooze a week",
  "@actionSnooze": {
    "description": "Hides an auto suggestion until a later date."
  },
  "actionDismiss": "Not now",
  "@actionDismiss": {
    "description": "Dismisses an auto suggestion until stock recovers and drops again."
  },
  "snoozedUntilLabel": "Snoozed until",
  "@snoozedUntilLabel": {
    "description": "Precedes a DateText on a snoozed entry."
  },
  "generateTitle": "Running low",
  "@generateTitle": {
    "description": "Low-stock suggestion sheet title."
  },
  "generateBody": "These are below the level you set. Add the ones you want.",
  "@generateBody": {
    "description": "Low-stock suggestion sheet body."
  },
  "generateShortBy": "Short by",
  "@generateShortBy": {
    "description": "Precedes a QtyText giving threshold minus stock on hand."
  },
  "generateRefresh": "Check again",
  "@generateRefresh": {
    "description": "Re-runs low-stock generation."
  },
  "generateEmptyTitle": "Nothing is running low",
  "@generateEmptyTitle": {
    "description": "Generate sheet empty state."
  },
  "generateEmptyBody": "Set a low-stock level on an item and it will show up here when it drops.",
  "@generateEmptyBody": {
    "description": "Generate sheet empty state body."
  },
  "generateAdded": "{count, plural, =1{1 suggestion added} other{{count} suggestions added}}",
  "@generateAdded": {
    "description": "Result snack after regeneration.",
    "placeholders": {
      "count": {}
    }
  },
  "convertTitle": "Turn into a purchase",
  "@convertTitle": {
    "description": "Convert-to-purchase screen title."
  },
  "convertBody": "Each ticked entry becomes one line, marked for inventory. You confirm the amount and account next.",
  "@convertBody": {
    "description": "Explains the handoff to the expense editor."
  },
  "convertConfirm": "Open the expense",
  "@convertConfirm": {
    "description": "Primary action; hands off to the 6A editor."
  },
  "convertNothingTitle": "Nothing is ticked",
  "@convertNothingTitle": {
    "description": "Convert screen empty state."
  },
  "convertNothingBody": "Tick what you actually bought, then come back.",
  "@convertNothingBody": {
    "description": "Convert screen empty state body."
  },
  "convertLineCount": "{count, plural, =1{1 line} other{{count} lines}}",
  "@convertLineCount": {
    "description": "How many lines the draft will carry.",
    "placeholders": {
      "count": {}
    }
  },
  "listManagerTitle": "Your lists",
  "@listManagerTitle": {
    "description": "List manager sheet title."
  },
  "listNameLabel": "List name",
  "@listNameLabel": {
    "description": "Field label when creating or renaming a list."
  },
  "listCreate": "New list",
  "@listCreate": {
    "description": "Creates a shopping list."
  },
  "listRename": "Rename",
  "@listRename": {
    "description": "Renames a shopping list."
  },
  "listSetDefault": "Make default",
  "@listSetDefault": {
    "description": "Marks a list as the one that opens by default."
  },
  "listDefaultBadge": "Default",
  "@listDefaultBadge": {
    "description": "Chip on the default list."
  },
  "listArchive": "Archive",
  "@listArchive": {
    "description": "Archives a shopping list."
  },
  "listUnarchive": "Restore",
  "@listUnarchive": {
    "description": "Un-archives a shopping list."
  },
  "listArchivedBadge": "Archived",
  "@listArchivedBadge": {
    "description": "Chip on an archived list."
  },
  "listArchivedSection": "Archived",
  "@listArchivedSection": {
    "description": "Section header for archived lists."
  },
  "emptyTitleNoLists": "No lists yet",
  "@emptyTitleNoLists": {
    "description": "List manager empty state."
  },
  "emptyBodyNoLists": "Create one and it becomes your default.",
  "@emptyBodyNoLists": {
    "description": "List manager empty state body."
  },
  "loadingShopping": "Loading your list",
  "@loadingShopping": {
    "description": "Skeleton label for shopping surfaces."
  },
  "actionAddToList": "Add to my list",
  "@actionAddToList": {
    "description": "Accepts a low-stock suggestion, promoting it to origin=manual so regeneration leaves it alone."
  },
  "suggestionDismissed": "Turned down",
  "@suggestionDismissed": {
    "description": "Chip on a dismissed suggestion; it stays listed so it can be accepted later."
  },
  "lineItemsTitle": "What you bought",
  "@lineItemsTitle": {
    "description": "Title of the dedicated line-items page."
  },
  "lineItemsManage": "Add or edit items",
  "@lineItemsManage": {
    "description": "Opens the line-items page from the transaction editor."
  },
  "lineItemsAdd": "Add an item",
  "@lineItemsAdd": {
    "description": "Adds one line from the line-items page."
  },
  "lineItemsSaveAndAnother": "Save & add another",
  "@lineItemsSaveAndAnother": {
    "description": "Commits the line and reopens the editor blank, so a receipt is entered without leaving the sheet."
  },
  "lineItemsCount": "{count, plural, =0{No items yet} =1{1 item} other{{count} items}}",
  "@lineItemsCount": {
    "description": "Running count on the line-items page.",
    "placeholders": {
      "count": {}
    }
  },
  "emptyTitleNoLineItems": "Nothing itemised yet",
  "@emptyTitleNoLineItems": {
    "description": "Line-items page empty state."
  },
  "emptyBodyNoLineItems": "Add what was on the receipt. Anything you leave out still counts toward the total.",
  "@emptyBodyNoLineItems": {
    "description": "Line-items page empty state body."
  },
  "actionRemove": "Remove",
  "@actionRemove": {
    "description": "Removes one line from a transaction."
  },
  "lineRemoved": "Item removed",
  "@lineRemoved": {
    "description": "Snack after removing a line."
  },
  "lineItemsAllocated": "Itemised",
  "@lineItemsAllocated": {
    "description": "Precedes the summed line total on the line-items page."
  },
  "recurringOutflow": "Going out",
  "@recurringOutflow": {
    "description": "Group header for outflow templates."
  },
  "recurringInflow": "Coming in",
  "@recurringInflow": {
    "description": "Group header for inflow templates — salary reads as income, not a negative bill."
  },
  "recurringNextDue": "Next",
  "@recurringNextDue": {
    "description": "Precedes a DateText giving the next due date."
  },
  "recurringOverdue": "Overdue",
  "@recurringOverdue": {
    "description": "Chip on an occurrence past its due date. Derived from the clock, never stored."
  },
  "recurringPaused": "Paused",
  "@recurringPaused": {
    "description": "Chip on a paused template."
  },
  "recurringDueToday": "Due today",
  "@recurringDueToday": {
    "description": "Chip when the next occurrence falls today."
  },
  "emptyTitleNoTemplates": "Nothing recurring yet",
  "@emptyTitleNoTemplates": {
    "description": "Template list empty state."
  },
  "emptyBodyNoTemplates": "Add a bill, a subscription or a salary and it will appear here when it is next due.",
  "@emptyBodyNoTemplates": {
    "description": "Template list empty state body."
  },
  "addTemplate": "Add",
  "@addTemplate": {
    "description": "Adds a recurring template."
  },
  "actionPause": "Pause",
  "@actionPause": {
    "description": "Pauses a template."
  },
  "actionResume": "Resume",
  "@actionResume": {
    "description": "Resumes a paused template."
  },
  "loadingRecurring": "Loading your schedule",
  "@loadingRecurring": {
    "description": "Skeleton label for recurring surfaces."
  },
  "builderSectionWhat": "What it is",
  "@builderSectionWhat": {
    "description": "First section of the template builder."
  },
  "builderSectionWhen": "How often",
  "@builderSectionWhen": {
    "description": "Frequency section of the template builder."
  },
  "builderSectionDefaults": "Defaults",
  "@builderSectionDefaults": {
    "description": "Amount and account section of the template builder."
  },
  "labelTemplateName": "Name",
  "@labelTemplateName": {
    "description": "Template name field."
  },
  "labelRecurringKind": "Kind",
  "@labelRecurringKind": {
    "description": "Bill, subscription, rent or salary."
  },
  "labelDirection": "Direction",
  "@labelDirection": {
    "description": "Whether money goes out or comes in."
  },
  "directionOutflow": "Money out",
  "@directionOutflow": {
    "description": "RecurringDirection.outflow."
  },
  "directionInflow": "Money in",
  "@directionInflow": {
    "description": "RecurringDirection.inflow."
  },
  "kindBill": "Bill",
  "@kindBill": {
    "description": "RecurringKind.bill."
  },
  "kindSubscription": "Subscription",
  "@kindSubscription": {
    "description": "RecurringKind.subscription."
  },
  "kindRent": "Rent",
  "@kindRent": {
    "description": "RecurringKind.rent."
  },
  "kindSalary": "Salary",
  "@kindSalary": {
    "description": "RecurringKind.salary."
  },
  "labelEvery": "Every",
  "@labelEvery": {
    "description": "Precedes the interval count and unit."
  },
  "unitDay": "{count, plural, =1{day} other{days}}",
  "@unitDay": {
    "description": "RecurringIntervalUnit.day.",
    "placeholders": {
      "count": {}
    }
  },
  "unitWeek": "{count, plural, =1{week} other{weeks}}",
  "@unitWeek": {
    "description": "RecurringIntervalUnit.week.",
    "placeholders": {
      "count": {}
    }
  },
  "unitMonth": "{count, plural, =1{month} other{months}}",
  "@unitMonth": {
    "description": "RecurringIntervalUnit.month.",
    "placeholders": {
      "count": {}
    }
  },
  "unitYear": "{count, plural, =1{year} other{years}}",
  "@unitYear": {
    "description": "RecurringIntervalUnit.year.",
    "placeholders": {
      "count": {}
    }
  },
  "labelAnchorDay": "On day of the month",
  "@labelAnchorDay": {
    "description": "anchorDayOfMonth. Stored once, clamped at render (anomaly A13)."
  },
  "anchorDayHelp": "Kept as you set it. Anchored on the 31st, a short month falls on its last day and the next long month returns to the 31st.",
  "@anchorDayHelp": {
    "description": "Explains that the anchor never walks backwards."
  },
  "labelStartDate": "Starts",
  "@labelStartDate": {
    "description": "startDateKey."
  },
  "labelEndDate": "Ends",
  "@labelEndDate": {
    "description": "endDateKey, optional."
  },
  "labelDefaultAmount": "Usual amount",
  "@labelDefaultAmount": {
    "description": "defaultAmount — a default, not a fixed figure."
  },
  "labelRemindBefore": "Remind me",
  "@labelRemindBefore": {
    "description": "remindDaysBefore."
  },
  "saveTemplate": "Save",
  "@saveTemplate": {
    "description": "Commits the template."
  },
  "previewTitle": "Next three",
  "@previewTitle": {
    "description": "Header of the frequency preview."
  },
  "previewEmpty": "Set a start date to see when this lands.",
  "@previewEmpty": {
    "description": "Frequency preview with nothing to show."
  },
  "previewClamped": "Shortened to fit the month",
  "@previewClamped": {
    "description": "Marks a previewed date the anchor could not reach."
  },
  "payTitle": "Record this payment",
  "@payTitle": {
    "description": "Pay sheet title."
  },
  "payTitleInflow": "Record this receipt",
  "@payTitleInflow": {
    "description": "Pay sheet title for an inflow."
  },
  "labelActualAmount": "Amount actually paid",
  "@labelActualAmount": {
    "description": "The real figure, which may differ from the default."
  },
  "labelActualAmountInflow": "Amount actually received",
  "@labelActualAmountInflow": {
    "description": "Inflow wording for the same field."
  },
  "payUsualWas": "Usually",
  "@payUsualWas": {
    "description": "Precedes the default amount when the actual differs from it."
  },
  "labelPaidOn": "Paid on",
  "@labelPaidOn": {
    "description": "paidDateKey."
  },
  "payCommit": "Record it",
  "@payCommit": {
    "description": "Commits the payment and creates the transaction."
  },
  "payRecorded": "Recorded",
  "@payRecorded": {
    "description": "Result snack after paying."
  },
  "payNeedsAccount": "Choose which account it came from",
  "@payNeedsAccount": {
    "description": "Rejection when no account is selected."
  },
  "payUndoTitle": "Undo this payment?",
  "@payUndoTitle": {
    "description": "Confirmation before undoing."
  },
  "payUndoBody": "The obligation goes back to due and the transaction it created is deleted. Anything that transaction produced — stock, an asset — goes with it.",
  "@payUndoBody": {
    "description": "Says exactly what undo reverses, in the order it happens (ARCH_5 §5.4)."
  },
  "payUndone": "Payment undone",
  "@payUndone": {
    "description": "Result snack after undoing."
  },
  "actionSkip": "Skip this one",
  "@actionSkip": {
    "description": "Marks an occurrence deliberately skipped."
  },
  "occurrenceSkipped": "Skipped",
  "@occurrenceSkipped": {
    "description": "Chip on a skipped occurrence, and the snack after skipping."
  },
  "historyRecurringTitle": "Payment history",
  "@historyRecurringTitle": {
    "description": "Occurrence history screen title."
  },
  "historyDefaultVsActual": "Differed from the usual amount",
  "@historyDefaultVsActual": {
    "description": "Badge when paidAmount != defaultAmount."
  },
  "emptyTitleNoOccurrences": "Nothing due yet",
  "@emptyTitleNoOccurrences": {
    "description": "Occurrence history empty state."
  },
  "emptyBodyNoOccurrences": "Occurrences appear as their due dates arrive. Nothing is ever paid for you.",
  "@emptyBodyNoOccurrences": {
    "description": "Empty state body, stating anomaly A14 plainly."
  },
  "statusDue": "Due",
  "@statusDue": {
    "description": "RecurringOccurrenceStatus.due."
  },
  "statusPaid": "Paid",
  "@statusPaid": {
    "description": "RecurringOccurrenceStatus.paid."
  },
  "statusDismissed": "Dismissed",
  "@statusDismissed": {
    "description": "RecurringOccurrenceStatus.dismissed."
  },
  "kindServiceFee": "Service fee",
  "@kindServiceFee": {
    "description": "RecurringKind.serviceFee — a recurring charge tied to an asset."
  },
  "kindOther": "Something else",
  "@kindOther": {
    "description": "RecurringKind.other — anything the named kinds do not cover."
  },
  "billDueSection": "Due now",
  "@billDueSection": {
    "description": "Header above the recurring bills a payment can settle."
  },
  "billSetUpAction": "Set up a recurring bill",
  "@billSetUpAction": {
    "description": "Opens the template builder from the bill form."
  },
  "billNothingDue": "Nothing is due right now.",
  "@billNothingDue": {
    "description": "Shown in the bill form when no occurrence is outstanding."
  },
  "recurringScheduleNext": "Saved. Now set how often it repeats.",
  "@recurringScheduleNext": {
    "description": "Snack after a line asked to become recurring."
  },
  "recurringNotYetDue": "Not due yet",
  "@recurringNotYetDue": {
    "description": "Chip when the next occurrence has not materialised."
  },
  "billSettlesLabel": "Settling",
  "@billSettlesLabel": {
    "description": "Precedes the recurring bill this payment will settle."
  },
  "billSettleNone": "Not a recurring bill",
  "@billSettleNone": {
    "description": "Option that leaves the payment unlinked to any template."
  },
  "billSettleHelp": "Pick one and the amount below becomes what you actually paid. Saving records it once.",
  "@billSettleHelp": {
    "description": "Explains that the editor is the single write path for a bill payment."
  },
  "billAmountBecomesPaid": "This amount is what gets recorded",
  "@billAmountBecomesPaid": {
    "description": "Helper under the amount when a bill is selected."
  },
  "billAccountAuto": "Paid from",
  "@billAccountAuto": {
    "description": "Precedes the account resolved automatically for a bill payment."
  },
  "billAccountAskOnce": "Which account does this come from? Alaya remembers it on the bill.",
  "@billAccountAskOnce": {
    "description": "Shown only when no template default, no app default and more than one account exist."
  },
  "assetGroupAppliance": "Appliances",
  "@assetGroupAppliance": {
    "description": "AssetType.appliance group header."
  },
  "assetGroupElectronics": "Electronics",
  "@assetGroupElectronics": {
    "description": "AssetType.electronics."
  },
  "assetGroupVehicle": "Vehicles",
  "@assetGroupVehicle": {
    "description": "AssetType.vehicle."
  },
  "assetGroupFurniture": "Furniture",
  "@assetGroupFurniture": {
    "description": "AssetType.furniture."
  },
  "assetGroupProperty": "Property",
  "@assetGroupProperty": {
    "description": "AssetType.property."
  },
  "assetGroupServiceProvider": "People",
  "@assetGroupServiceProvider": {
    "description": "AssetType.serviceProvider — a maid or gardener lives here, not in a second system."
  },
  "assetGroupSubscription": "Subscriptions",
  "@assetGroupSubscription": {
    "description": "AssetType.subscription."
  },
  "assetGroupOther": "Other",
  "@assetGroupOther": {
    "description": "AssetType.other."
  },
  "assetUnderWarranty": "In warranty",
  "@assetUnderWarranty": {
    "description": "Chip when warrantyEndDateKey is still ahead."
  },
  "assetWarrantyEnding": "Warranty ending",
  "@assetWarrantyEnding": {
    "description": "Chip when the warranty ends soon."
  },
  "assetWarrantyExpired": "Out of warranty",
  "@assetWarrantyExpired": {
    "description": "Chip when the warranty has passed."
  },
  "assetServiceDue": "Service due",
  "@assetServiceDue": {
    "description": "Chip when nextServiceDueDateKey has passed."
  },
  "assetServiceSoon": "Service soon",
  "@assetServiceSoon": {
    "description": "Chip when a service is close."
  },
  "assetDisposedChip": "Disposed",
  "@assetDisposedChip": {
    "description": "Chip on a disposed asset."
  },
  "assetUnderRepair": "Being repaired",
  "@assetUnderRepair": {
    "description": "AssetStatus.underRepair."
  },
  "filterShowDisposed": "Include disposed",
  "@filterShowDisposed": {
    "description": "Filter that brings disposed assets back into the list."
  },
  "emptyTitleNoAssets": "Nothing tracked yet",
  "@emptyTitleNoAssets": {
    "description": "Asset list empty state."
  },
  "emptyBodyNoAssets": "Add an appliance, a vehicle, or the person who helps around the house — they all live here.",
  "@emptyBodyNoAssets": {
    "description": "Asset list empty state body, stating the serviceProvider case plainly."
  },
  "addAsset": "Add",
  "@addAsset": {
    "description": "Adds an asset."
  },
  "loadingAssets": "Loading your things",
  "@loadingAssets": {
    "description": "Skeleton label for service surfaces."
  },
  "assetSectionIdentity": "Details",
  "@assetSectionIdentity": {
    "description": "Identity section on the detail screen."
  },
  "assetSectionWarranty": "Warranty",
  "@assetSectionWarranty": {
    "description": "Warranty section."
  },
  "assetSectionContact": "Contact",
  "@assetSectionContact": {
    "description": "Contact block."
  },
  "assetSectionService": "Service history",
  "@assetSectionService": {
    "description": "Service records section."
  },
  "assetSectionSalary": "Salary history",
  "@assetSectionSalary": {
    "description": "Service records section for a serviceProvider."
  },
  "assetLifetimeCost": "Spent on service so far",
  "@assetLifetimeCost": {
    "description": "Sum of every service record cost."
  },
  "assetLifetimeSalary": "Paid so far",
  "@assetLifetimeSalary": {
    "description": "The same figure for a serviceProvider."
  },
  "labelBrand": "Brand",
  "@labelBrand": {
    "description": "assets.brand."
  },
  "labelModelNo": "Model",
  "@labelModelNo": {
    "description": "assets.modelNo."
  },
  "labelSerialNo": "Serial",
  "@labelSerialNo": {
    "description": "assets.serialNo."
  },
  "labelPurchasePrice": "Bought for",
  "@labelPurchasePrice": {
    "description": "assets.purchasePrice."
  },
  "labelWarrantyStart": "Warranty from",
  "@labelWarrantyStart": {
    "description": "assets.warrantyStartDateKey."
  },
  "labelWarrantyEnd": "Warranty until",
  "@labelWarrantyEnd": {
    "description": "assets.warrantyEndDateKey."
  },
  "labelWarrantyProvider": "Covered by",
  "@labelWarrantyProvider": {
    "description": "assets.warrantyProvider."
  },
  "labelServiceInterval": "Service every",
  "@labelServiceInterval": {
    "description": "assets.serviceIntervalDays."
  },
  "labelNextService": "Next service",
  "@labelNextService": {
    "description": "assets.nextServiceDueDateKey."
  },
  "labelContactName": "Name",
  "@labelContactName": {
    "description": "assets.primaryContactName."
  },
  "labelContactPhone": "Phone",
  "@labelContactPhone": {
    "description": "assets.primaryContactPhone."
  },
  "labelLocation": "Kept in",
  "@labelLocation": {
    "description": "assets.location."
  },
  "actionCall": "Call",
  "@actionCall": {
    "description": "Dials primaryContactPhone."
  },
  "callFailed": "No app on this phone can place that call.",
  "@callFailed": {
    "description": "Shown when the tel: intent finds no handler."
  },
  "actionAddService": "Record a service",
  "@actionAddService": {
    "description": "Adds a service record."
  },
  "actionAddSalary": "Record a payment",
  "@actionAddSalary": {
    "description": "The same action for a serviceProvider."
  },
  "actionDispose": "Dispose of it",
  "@actionDispose": {
    "description": "Opens the dispose sheet."
  },
  "actionUndispose": "Bring it back",
  "@actionUndispose": {
    "description": "Reverses a disposal."
  },
  "assetLinkedRecurring": "Paid on a schedule",
  "@assetLinkedRecurring": {
    "description": "Chip when linkedRecurringTemplateId is set."
  },
  "emptyBodyNoServices": "Nothing recorded against this yet.",
  "@emptyBodyNoServices": {
    "description": "Empty service history."
  },
  "labelAssetName": "What is it?",
  "@labelAssetName": {
    "description": "assets.name."
  },
  "labelAssetType": "Kind",
  "@labelAssetType": {
    "description": "assets.type."
  },
  "assetTypeHelpPerson": "A person you pay regularly belongs here too — their payments become service records.",
  "@assetTypeHelpPerson": {
    "description": "Explains AssetType.serviceProvider when it is chosen."
  },
  "saveAsset": "Save",
  "@saveAsset": {
    "description": "Commits an asset."
  },
  "serviceIntervalHelp": "Days between services. The next due date moves on each time you record one.",
  "@serviceIntervalHelp": {
    "description": "Explains serviceIntervalDays."
  },
  "labelServiceType": "What happened",
  "@labelServiceType": {
    "description": "service_records.type."
  },
  "serviceTypeService": "Serviced",
  "@serviceTypeService": {
    "description": "ServiceRecordType.service."
  },
  "serviceTypeRepair": "Repaired",
  "@serviceTypeRepair": {
    "description": "ServiceRecordType.repair."
  },
  "serviceTypeMaintenance": "Maintenance",
  "@serviceTypeMaintenance": {
    "description": "ServiceRecordType.maintenance."
  },
  "serviceTypeInspection": "Inspection",
  "@serviceTypeInspection": {
    "description": "ServiceRecordType.inspection."
  },
  "serviceTypeSalaryPaid": "Salary paid",
  "@serviceTypeSalaryPaid": {
    "description": "ServiceRecordType.salaryPaid — the maid case."
  },
  "serviceTypeOther": "Something else",
  "@serviceTypeOther": {
    "description": "ServiceRecordType.other."
  },
  "labelProviderName": "Who did it",
  "@labelProviderName": {
    "description": "service_records.providerName."
  },
  "labelProviderPhone": "Their number",
  "@labelProviderPhone": {
    "description": "service_records.providerPhone."
  },
  "labelServiceDate": "When",
  "@labelServiceDate": {
    "description": "service_records.serviceDateKey."
  },
  "labelServiceCost": "Cost",
  "@labelServiceCost": {
    "description": "service_records.cost."
  },
  "labelNextDue": "Next one due",
  "@labelNextDue": {
    "description": "service_records.nextDueDateKey."
  },
  "alsoRecordAsExpense": "Also record it as an expense",
  "@alsoRecordAsExpense": {
    "description": "The alsoRecordAsExpense toggle."
  },
  "alsoRecordHelp": "Writes a withdrawal for the cost as well, so it shows in your ledger.",
  "@alsoRecordHelp": {
    "description": "Explains what the toggle writes."
  },
  "alsoRecordNeedsAccount": "Choose which account it comes from",
  "@alsoRecordNeedsAccount": {
    "description": "Rejection when the toggle is on with no account."
  },
  "alsoRecordNeedsCost": "Add a cost first",
  "@alsoRecordNeedsCost": {
    "description": "Rejection when the toggle is on with no cost."
  },
  "saveService": "Save",
  "@saveService": {
    "description": "Commits a service record."
  },
  "disposeTitle": "What happened to it?",
  "@disposeTitle": {
    "description": "Dispose sheet title."
  },
  "disposeBody": "It stays in your records either way — what you spent on it still counts. This just stops it appearing as something you own.",
  "@disposeBody": {
    "description": "States anomaly A30 plainly: an asset is never deleted."
  },
  "disposeReasonSold": "Sold it",
  "@disposeReasonSold": {
    "description": "AssetDisposalReason.sold."
  },
  "disposeReasonExpired": "Wore out",
  "@disposeReasonExpired": {
    "description": "AssetDisposalReason.expired."
  },
  "disposeReasonDamaged": "Broke",
  "@disposeReasonDamaged": {
    "description": "AssetDisposalReason.damaged."
  },
  "disposeReasonGifted": "Gave it away",
  "@disposeReasonGifted": {
    "description": "AssetDisposalReason.gifted."
  },
  "disposeReasonLost": "Lost it",
  "@disposeReasonLost": {
    "description": "AssetDisposalReason.lost."
  },
  "disposeReasonReplaced": "Replaced it",
  "@disposeReasonReplaced": {
    "description": "AssetDisposalReason.replaced."
  },
  "disposeReasonOther": "Something else",
  "@disposeReasonOther": {
    "description": "AssetDisposalReason.other."
  },
  "labelDisposalAmount": "Got back",
  "@labelDisposalAmount": {
    "description": "assets.disposalAmount — what the disposal recovered."
  },
  "labelDisposalDate": "When",
  "@labelDisposalDate": {
    "description": "assets.disposedAtDateKey."
  },
  "disposeCommit": "Record it",
  "@disposeCommit": {
    "description": "Commits the disposal."
  },
  "disposeDone": "Recorded",
  "@disposeDone": {
    "description": "Snack after disposing."
  },
  "undisposeDone": "Back in your list",
  "@undisposeDone": {
    "description": "Snack after un-disposing."
  },
  "disposeNeedsReason": "Pick what happened",
  "@disposeNeedsReason": {
    "description": "Rejection when no reason is chosen."
  },
  "hintSearchAssets": "Search your things and people",
  "@hintSearchAssets": {
    "description": "Search hint on the asset list."
  },
  "errorWarrantyBackwards": "The warranty cannot end before it starts",
  "@errorWarrantyBackwards": {
    "description": "Field error when warrantyEndDateKey precedes warrantyStartDateKey."
  },
  "sectionMoney": "Money",
  "@sectionMoney": {
    "description": "Header above the cost and expense controls on the service editor."
  },
  "assetCreatedFromPurchase": "Saved. Now say what it is and how long it is covered.",
  "@assetCreatedFromPurchase": {
    "description": "Snack after a purchase line created an asset."
  },
  "destinationHelpNone": "Recorded as spending and nothing else.",
  "@destinationHelpNone": {
    "description": "Explains destination none."
  },
  "destinationHelpInventory": "Groceries, refills, anything measured and consumed. Needs an item and a quantity, and creates stock you can run down.",
  "@destinationHelpInventory": {
    "description": "Explains destination inventory."
  },
  "destinationHelpAsset": "A phone, a fridge, a chair. Creates something you own, with its own warranty and service history.",
  "@destinationHelpAsset": {
    "description": "Explains destination asset."
  },
  "destinationHelpRecurring": "Sets up a schedule so this comes back every month.",
  "@destinationHelpRecurring": {
    "description": "Explains destination recurring."
  },
  "assetSameNameNote": "You already have one called this. That is fine — this will be a separate one, with its own warranty and service history.",
  "@assetSameNameNote": {
    "description": "Informational note when an asset name repeats. Never a block: five iPhones are five assets."
  },
  "@destinationNone": {
    "description": "No artefact. Recorded as spending and nothing else."
  },
  "@destinationInventory": {
    "description": "Creates stock. Names the Inventory module, matching navInventory."
  },
  "@destinationAsset": {
    "description": "Creates an asset. Names the Services module, matching navServices."
  },
  "@destinationRecurring": {
    "description": "Hands off to the template builder. Matches navRecurring."
  },
  "actionSetWarranty": "Set the warranty",
  "@actionSetWarranty": {
    "description": "Snack action opening the asset a purchase line created."
  },
  "labelPaymentMethodOptional": "How you paid (optional)",
  "@labelPaymentMethodOptional": {
    "description": "Optional payment method on the service editor. Travels to the expense, never onto the record."
  },
  "dashboardTitle": "Home",
  "@dashboardTitle": {
    "description": "Dashboard screen title."
  },
  "fundsAvailable": "Total available funds",
  "@fundsAvailable": {
    "description": "Label above the one headline figure on the dashboard."
  },
  "fundsUnconverted": "{count, plural, =1{1 balance not converted} other{{count} balances not converted}}",
  "@fundsUnconverted": {
    "description": "Chip when BalanceService could not convert some accounts. Excluded from the headline, never summed (anomaly A34).",
    "placeholders": {
      "count": {}
    }
  },
  "fundsApproximate": "Rate is older than today",
  "@fundsApproximate": {
    "description": "Chip when the conversion used the most recent rate on or before today."
  },
  "fundsWhyExcluded": "Balances Alaya has no rate for are left out rather than guessed at.",
  "@fundsWhyExcluded": {
    "description": "Explains why the headline may be lower than the sum of every account."
  },
  "rangeLast30": "Last 30 days",
  "@rangeLast30": {
    "description": "Range label. Always stated, never implied (anomaly A33)."
  },
  "rangeMoneyIn": "In",
  "@rangeMoneyIn": {
    "description": "Deposits over the labelled range."
  },
  "rangeMoneyOut": "Out",
  "@rangeMoneyOut": {
    "description": "Withdrawals over the labelled range."
  },
  "rangeNothingYet": "Nothing yet",
  "@rangeNothingYet": {
    "description": "Shown in place of a figure when a range holds no transactions."
  },
  "rangeExcluded": "{count, plural, =1{1 left out} other{{count} left out}}",
  "@rangeExcluded": {
    "description": "Chip when transactions in a foreign currency could not be converted into the range total.",
    "placeholders": {
      "count": {}
    }
  },
  "insightUpcoming": "Coming up",
  "@insightUpcoming": {
    "description": "The calendar side of the switchable insight card."
  },
  "insightSpending": "Where it went",
  "@insightSpending": {
    "description": "The analytics side of the switchable insight card."
  },
  "insightSwitchLabel": "Show",
  "@insightSwitchLabel": {
    "description": "Semantics label for the insight card switch."
  },
  "insightNothingUpcoming": "Nothing needs attention in the next fortnight.",
  "@insightNothingUpcoming": {
    "description": "Empty state for the upcoming side."
  },
  "insightBillDue": "Bill due",
  "@insightBillDue": {
    "description": "Upcoming row for a recurring occurrence."
  },
  "insightServiceDue": "Service due",
  "@insightServiceDue": {
    "description": "Upcoming row for an asset needing service."
  },
  "insightWarrantyEnding": "Warranty ending",
  "@insightWarrantyEnding": {
    "description": "Upcoming row for an expiring warranty."
  },
  "insightBatchExpiring": "Expiring",
  "@insightBatchExpiring": {
    "description": "Upcoming row for a batch past or near its expiry."
  },
  "moduleGridTitle": "Where to next",
  "@moduleGridTitle": {
    "description": "Header above the navigation tiles."
  },
  "moduleExpenses": "{count, plural, =0{none this month} =1{1 this month} other{{count} this month}}",
  "@moduleExpenses": {
    "description": "Live number on the Expenses tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleInventory": "{count, plural, =0{nothing tracked} =1{1 running low} other{{count} running low}}",
  "@moduleInventory": {
    "description": "Live number on the Inventory tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleShopping": "{count, plural, =0{list is clear} =1{1 to buy} other{{count} to buy}}",
  "@moduleShopping": {
    "description": "Live number on the Shopping tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleRecurring": "{count, plural, =0{all settled} =1{1 due} other{{count} due}}",
  "@moduleRecurring": {
    "description": "Live number on the Recurring tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleServices": "{count, plural, =0{nothing needs doing} =1{1 needs attention} other{{count} need attention}}",
  "@moduleServices": {
    "description": "Live number on the Services tile.",
    "placeholders": {
      "count": {}
    }
  },
  "fabAddIncome": "Money in",
  "@fabAddIncome": {
    "description": "FAB action opening the editor as a deposit."
  },
  "fabAddItem": "New item",
  "@fabAddItem": {
    "description": "FAB action opening the item editor."
  },
  "loadingDashboard": "Adding it up",
  "@loadingDashboard": {
    "description": "Skeleton label for the dashboard."
  },
  "fabOpenLabel": "Add something",
  "@fabOpenLabel": {
    "description": "Semantics label for the closed expandable FAB."
  },
  "fabCloseLabel": "Close",
  "@fabCloseLabel": {
    "description": "Semantics label for the open expandable FAB."
  },
  "eventTypeTransaction": "Transaction",
  "eventTypeRecurringDue": "Recurring bill",
  "eventTypeBatchExpiry": "Expiring",
  "eventTypeWarrantyEnd": "Warranty ending",
  "eventTypeServiceDue": "Service due",
  "eventTypeShoppingTarget": "Shopping target",
  "calendarSeverityWarning": "Needs attention",
  "calendarSeverityDanger": "Past its date",
  "calendarLoadingDay": "Loading this day…",
  "calendarDayErrorTitle": "Could not load this day",
  "calendarDayEmptyTitle": "Nothing on this day",
  "calendarDayEmptyBody": "No transactions, bills, expiries or services fall here.",
  "calendarRetry": "Try again",
  "calendarLoadingMonth": "Loading this month…",
  "calendarErrorTitle": "Could not load the calendar",
  "calendarPreviousMonth": "Previous month",
  "calendarNextMonth": "Next month",
  "calendarOnDay": "On this day",
  "calendarRangeOn": "Select a range",
  "calendarRangeOff": "Stop selecting a range",
  "calendarRangePickEnd": "From {start} — tap another day to finish.",
  "calendarInRange": "{count, plural, =1{1 day} other{{count} days}}",
  "calendarRangeEmptyTitle": "Nothing in these days",
  "calendarRangeEmptyBody": "No transactions, bills, expiries or services fall inside the range.",
  "@calendarRangePickEnd": {
    "description": "Prompt after the range start is chosen.",
    "placeholders": {
      "start": {
        "type": "String"
      }
    }
  },
  "@calendarInRange": {
    "description": "How many days the chosen range spans.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "calendarBackToToday": "Back to this month",
  "calendarTotalOut": "Spent",
  "calendarTotalIn": "Received",
  "dashboardOpenCalendar": "Open calendar",
  "dashboardCalendarSemantics": "{month} at a glance. Opens the calendar.",
  "@dashboardCalendarSemantics": {
    "description": "Screen-reader label for the dashboard month card where days are too narrow to tap.",
    "placeholders": {
      "month": {
        "type": "String"
      }
    }
  },
  "navBackToDashboard": "Back to dashboard",
  "chartLoading": "Working it out…",
  "@chartLoading": {
    "description": "Shown in a ChartCard while its figure computes. A line rather than a spinner: a card about to hold a chart reads as slow behind one (ARCH_5 §5.2)."
  },
  "chartApproximate": "{count, plural, =1{1 figure is indicative} other{{count} figures are indicative}}",
  "@chartApproximate": {
    "description": "How many of a series' data points converted against a rate from a different day (ARCH_3 §1.3). Says what it means rather than naming the rate quality.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "chartUnconverted": "{count, plural, =1{1 amount left out} other{{count} amounts left out}}",
  "@chartUnconverted": {
    "description": "How many amounts had no usable rate and are excluded from the figure, never counted as zero (anomaly A15).",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsTotalSpent": "Spent",
  "@analyticsTotalSpent": {
    "description": "Label above the analytics screen's one displayAmount."
  },
  "analyticsRangeLabel": "Reporting window",
  "@analyticsRangeLabel": {
    "description": "Semantics label for the range chip row."
  },
  "analyticsComparisonUp": "{percent} more than the window before",
  "@analyticsComparisonUp": {
    "description": "Period-over-period comparison, rising. The window compared against is the same length, not a calendar month.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsComparisonDown": "{percent} less than the window before",
  "@analyticsComparisonDown": {
    "description": "Period-over-period comparison, falling.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsUnconvertedTotal": "{count, plural, =1{1 amount needs a rate} other{{count} amounts need a rate}}",
  "@analyticsUnconvertedTotal": {
    "description": "The app-wide unconverted count, distinct from one figure's own exclusions. A transaction outside the window can still be unconvertible.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsInflationTitle": "Your own inflation",
  "@analyticsInflationTitle": {
    "description": "Title of the personal-inflation card, queries 12 and 24."
  },
  "analyticsInflationSubtitle": "What one thing costs you, purchase by purchase",
  "@analyticsInflationSubtitle": {
    "description": "Explains that the trend is per base unit, so 2 kg and 500 g are comparable."
  },
  "analyticsInflationUp": "{percent} more than the first time in this window",
  "@analyticsInflationUp": {
    "description": "The personal-inflation sentence, rising. The date is rendered separately through DateText (Law U7).",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsInflationDown": "{percent} less than the first time in this window",
  "@analyticsInflationDown": {
    "description": "The personal-inflation sentence, falling.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsInflationSince": "First bought",
  "@analyticsInflationSince": {
    "description": "Precedes a DateText giving the earliest purchase in the window."
  },
  "analyticsInflationEmpty": "Buy something twice and its price trend appears here. Widen the window if you have.",
  "@analyticsInflationEmpty": {
    "description": "Empty state: fewer than two priced purchases means there is no trend to draw. Names both ways out."
  },
  "analyticsSectionSpend": "Where it went",
  "@analyticsSectionSpend": {
    "description": "Section header over the spend breakdowns."
  },
  "analyticsSectionTime": "Over time",
  "@analyticsSectionTime": {
    "description": "Section header over the trends."
  },
  "analyticsSectionWhat": "Who and what",
  "@analyticsSectionWhat": {
    "description": "Section header over payees and items."
  },
  "analyticsSectionHome": "Your home",
  "@analyticsSectionHome": {
    "description": "Section header over stock, waste and expiry."
  },
  "analyticsSectionCommitments": "Already committed",
  "@analyticsSectionCommitments": {
    "description": "Section header over recurring commitments and assets."
  },
  "analyticsBySubtype": "By kind",
  "@analyticsBySubtype": {
    "description": "Query 1. \"Kind\" rather than \"subtype\": the schema's word is not the user's."
  },
  "analyticsByTag": "By tag",
  "@analyticsByTag": {
    "description": "Query 2."
  },
  "analyticsByTagNote": "A purchase with two tags counts in both, so these add up to more than the total",
  "@analyticsByTagNote": {
    "description": "The caveat belongs on the card: a reader comparing tag figures against the headline deserves to know why they differ."
  },
  "analyticsByMethod": "By payment method",
  "@analyticsByMethod": {
    "description": "Query 3."
  },
  "analyticsConcentration": "How concentrated",
  "@analyticsConcentration": {
    "description": "Query 22, with query 8's grocery share beneath it."
  },
  "analyticsTopShare": "{percent} of your spending sits in three kinds",
  "@analyticsTopShare": {
    "description": "Query 22's headline.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsGroceryShare": "Groceries are {percent} of it",
  "@analyticsGroceryShare": {
    "description": "Query 8, stated beneath the concentration figure.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsTagChildren": "{count, plural, =1{1 tag inside} other{{count} tags inside}}",
  "@analyticsTagChildren": {
    "description": "Marks a parent tag that can be opened. One level only, which is all the schema permits.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsTagDirect": "{tag} on its own",
  "@analyticsTagDirect": {
    "description": "The parent tag's own spending, as a sibling of its children rather than folded into them.",
    "placeholders": {
      "tag": {}
    }
  },
  "analyticsTagBack": "Back to all tags",
  "@analyticsTagBack": {
    "description": "Tooltip on the in-place drill's back button."
  },
  "analyticsNothingSpent": "Nothing spent in this window",
  "@analyticsNothingSpent": {
    "description": "Empty state for a spend breakdown."
  },
  "analyticsNoTaggedSpend": "Tag a purchase and it will appear here",
  "@analyticsNoTaggedSpend": {
    "description": "Empty state for the tag breakdown: names the action, not the absence."
  },
  "analyticsNoMethodSpend": "Record how you paid and it will appear here",
  "@analyticsNoMethodSpend": {
    "description": "Empty state for the payment-method breakdown."
  },
  "analyticsIncomeVsExpense": "In and out",
  "@analyticsIncomeVsExpense": {
    "description": "Query 5."
  },
  "analyticsNeedTwoMonths": "Two months of records and the trend appears here",
  "@analyticsNeedTwoMonths": {
    "description": "Empty state: one month is a pair of figures, not a trend."
  },
  "analyticsNetFlow": "What you kept",
  "@analyticsNetFlow": {
    "description": "Query 6. Named for what the figure means rather than for the ledger it comes from."
  },
  "analyticsNetFlowNote": "Moving money between your own accounts does not count",
  "@analyticsNetFlowNote": {
    "description": "Explains why a transfer is absent: the ledger nets it to zero across its two legs."
  },
  "analyticsNoFlow": "Nothing moved in this window",
  "@analyticsNoFlow": {
    "description": "Empty state for net flow."
  },
  "analyticsBalanceTrend": "Balance over time",
  "@analyticsBalanceTrend": {
    "description": "Query 7."
  },
  "analyticsBalanceIn": "{account}, in {currency}",
  "@analyticsBalanceIn": {
    "description": "Names the account and its currency: this is the one figure on the screen not in the home currency, because converting each point would make the line move when rates moved.",
    "placeholders": {
      "account": {},
      "currency": {}
    }
  },
  "analyticsAccount": "Account",
  "@analyticsAccount": {
    "description": "Label on the balance-trend account picker."
  },
  "analyticsNoBalanceMovement": "No movement on this account in this window",
  "@analyticsNoBalanceMovement": {
    "description": "Empty state for the balance trend."
  },
  "analyticsHeatmap": "When you spend",
  "@analyticsHeatmap": {
    "description": "Query 21."
  },
  "analyticsByWeekday": "By day of week",
  "@analyticsByWeekday": {
    "description": "Heatmap segment."
  },
  "analyticsByDayOfMonth": "By date",
  "@analyticsByDayOfMonth": {
    "description": "Heatmap segment."
  },
  "analyticsTopPayees": "Who you paid most",
  "@analyticsTopPayees": {
    "description": "Query 4."
  },
  "analyticsNoPayees": "Name who you paid and they will appear here",
  "@analyticsNoPayees": {
    "description": "Empty state for top payees."
  },
  "analyticsTopItems": "What cost you most",
  "@analyticsTopItems": {
    "description": "Query 9."
  },
  "analyticsNoItemisedSpend": "Itemise a purchase and it will appear here",
  "@analyticsNoItemisedSpend": {
    "description": "Empty state for top items by spend."
  },
  "analyticsTopByQuantity": "What you buy most of",
  "@analyticsTopByQuantity": {
    "description": "Query 10."
  },
  "analyticsTopByQuantityNote": "Grouped by measure, because weight and count cannot be compared",
  "@analyticsTopByQuantityNote": {
    "description": "Explains the grouping: Law L8 makes cross-category comparison meaningless."
  },
  "analyticsNoQuantities": "Record how much you bought and it will appear here",
  "@analyticsNoQuantities": {
    "description": "Empty state for top items by quantity."
  },
  "analyticsPurchaseCount": "{count, plural, =1{1 purchase} other{{count} purchases}}",
  "@analyticsPurchaseCount": {
    "description": "How many times an item was bought in the window.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsDearest": "The most you have paid",
  "@analyticsDearest": {
    "description": "Query 11."
  },
  "analyticsDearestItem": "Item",
  "@analyticsDearestItem": {
    "description": "Key on the dearest-purchase card."
  },
  "analyticsDearestPrice": "Unit price",
  "@analyticsDearestPrice": {
    "description": "Key on the dearest-purchase card. The figure is in the currency it was bought in, unconverted."
  },
  "analyticsDearestWhen": "When",
  "@analyticsDearestWhen": {
    "description": "Key on the dearest-purchase card, paired with a DateText."
  },
  "analyticsNoUnitPrices": "Record a unit price and this appears here",
  "@analyticsNoUnitPrices": {
    "description": "Empty state for the dearest purchase."
  },
  "analyticsAverageBasket": "Your average shop",
  "@analyticsAverageBasket": {
    "description": "Query 23."
  },
  "analyticsBasketValue": "Average value",
  "@analyticsBasketValue": {
    "description": "Key on the basket card."
  },
  "analyticsBasketLines": "Average items",
  "@analyticsBasketLines": {
    "description": "Key on the basket card."
  },
  "analyticsBasketCount": "Shops counted",
  "@analyticsBasketCount": {
    "description": "Key on the basket card. Counts the baskets that converted, which is what the average divides by."
  },
  "analyticsNoBaskets": "Record a grocery shop and it will appear here",
  "@analyticsNoBaskets": {
    "description": "Empty state for the basket card."
  },
  "analyticsInventoryValue": "What is on your shelves",
  "@analyticsInventoryValue": {
    "description": "Query 13."
  },
  "analyticsInventoryValueNote": "Right now, whatever window you have chosen",
  "@analyticsInventoryValueNote": {
    "description": "Explains why the range chip does not change this figure."
  },
  "analyticsBatchesValued": "{count, plural, =1{1 batch valued} other{{count} batches valued}}",
  "@analyticsBatchesValued": {
    "description": "How many batches had both a cost and a resolvable purchase unit.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsBatchesNoCost": "{count, plural, =1{1 batch has no cost} other{{count} batches have no cost}}",
  "@analyticsBatchesNoCost": {
    "description": "Uncosted stock, reported rather than omitted: a valuation that skipped it would look complete while understating the shelf.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsNoStockValue": "Record what a batch cost and its value appears here",
  "@analyticsNoStockValue": {
    "description": "Empty state for the inventory valuation."
  },
  "analyticsWaste": "What you threw away",
  "@analyticsWaste": {
    "description": "Query 14, one of the app's differentiating insights."
  },
  "analyticsNoWaste": "Nothing wasted in this window",
  "@analyticsNoWaste": {
    "description": "Empty state, and it is good news: worded as a fact rather than as missing data."
  },
  "analyticsExpiring": "Expiring within {days} days",
  "@analyticsExpiring": {
    "description": "Query 15.",
    "placeholders": {
      "days": {
        "type": "int"
      }
    }
  },
  "analyticsNothingExpiring": "Nothing expires soon",
  "@analyticsNothingExpiring": {
    "description": "Empty state for the expiry card."
  },
  "analyticsDaysLeft": "{days, plural, =1{1 day left} other{{days} days left}}",
  "@analyticsDaysLeft": {
    "description": "How long a batch has. Paired with a tone, because colour is never the only signal (Law U17).",
    "placeholders": {
      "days": {
        "type": "num"
      }
    }
  },
  "analyticsExpiredAlready": "Past its date",
  "@analyticsExpiredAlready": {
    "description": "Chip on a batch whose expiry has passed and still holds stock."
  },
  "analyticsLowStock": "Running low",
  "@analyticsLowStock": {
    "description": "Query 16."
  },
  "analyticsLowStockNote": "A count for today, not a history: stock levels are not kept over time",
  "@analyticsLowStockNote": {
    "description": "Explains why this is one figure rather than a trend."
  },
  "analyticsLowStockCount": "{count, plural, =1{1 item below its threshold} other{{count} items below their threshold}}",
  "@analyticsLowStockCount": {
    "description": "Query 16's figure.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsAsOf": "As of",
  "@analyticsAsOf": {
    "description": "Precedes a DateText on the low-stock count."
  },
  "analyticsNothingLow": "Nothing is running low",
  "@analyticsNothingLow": {
    "description": "Empty state for the low-stock card."
  },
  "analyticsCommitment": "Every month, before anything else",
  "@analyticsCommitment": {
    "description": "Query 17."
  },
  "analyticsCommitmentNote": "Bills and subscriptions only. Income is not netted off",
  "@analyticsCommitmentNote": {
    "description": "Explains the outflow-only filter: netting salary against rent would report a household as having no fixed costs."
  },
  "analyticsCommitmentCount": "{count, plural, =1{from 1 commitment} other{from {count} commitments}}",
  "@analyticsCommitmentCount": {
    "description": "How many active templates the monthly figure covers.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsNoCommitments": "Add a bill or subscription and it will appear here",
  "@analyticsNoCommitments": {
    "description": "Empty state for the commitment total."
  },
  "analyticsRecurringSplit": "Fixed against chosen",
  "@analyticsRecurringSplit": {
    "description": "Query 18."
  },
  "analyticsRecurring": "Fixed",
  "@analyticsRecurring": {
    "description": "Query 18's recurring side. The user's word, not the schema's."
  },
  "analyticsDiscretionary": "Chosen",
  "@analyticsDiscretionary": {
    "description": "Query 18's discretionary side."
  },
  "analyticsRecurringShare": "{percent} of your spending was already committed",
  "@analyticsRecurringShare": {
    "description": "Query 18's headline.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsServiceCost": "What your things cost to keep",
  "@analyticsServiceCost": {
    "description": "Query 19. Includes disposed assets, which is the point of a status change rather than a delete."
  },
  "analyticsServiceCount": "{count, plural, =1{1 visit} other{{count} visits}}",
  "@analyticsServiceCount": {
    "description": "How many service records an asset has in the window.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsNoServiceCost": "Record a service or repair and it will appear here",
  "@analyticsNoServiceCost": {
    "description": "Empty state for the service-cost card."
  },
  "analyticsWarranty": "Warranties",
  "@analyticsWarranty": {
    "description": "Query 20."
  },
  "analyticsCovered": "Covered",
  "@analyticsCovered": {
    "description": "Chip on an asset still inside its warranty window."
  },
  "analyticsCoverageEnded": "Cover ended",
  "@analyticsCoverageEnded": {
    "description": "Chip on an asset whose warranty has run out."
  },
  "analyticsNoWarranties": "Add a warranty date and it will appear here",
  "@analyticsNoWarranties": {
    "description": "Empty state for the warranty card."
  },
  "analyticsEmptyTitle": "Nothing to show for this window",
  "@analyticsEmptyTitle": {
    "description": "Screen-level empty state. The house section stays visible beneath it, because stock is a \"right now\" figure."
  },
  "analyticsEmptyBody": "Widen the window above, or record something and it will appear here.",
  "@analyticsEmptyBody": {
    "description": "Names both ways out: on a fresh install the second is the answer, on a quiet month the first is."
  },
  "analyticsCacheClear": "Recalculate everything",
  "@analyticsCacheClear": {
    "description": "The clear-cache action, named for what the reader gets rather than for the table it empties."
  },
  "analyticsCacheClearing": "Recalculating…",
  "@analyticsCacheClearing": {
    "description": "The action's in-progress label."
  },
  "analyticsCacheExplain": "Some figures are kept between visits so this screen opens quickly. Clear them if a number looks stale.",
  "@analyticsCacheExplain": {
    "description": "Explains what the action does. The only place analytics_cache is ever visible (ARCH_5 §7.3)."
  },
  "analyticsCacheCleared": "Recalculated",
  "@analyticsCacheCleared": {
    "description": "Precedes a DateText giving when the cache was last cleared."
  },
  "analyticsCacheClearedSnack": "Figures recalculated",
  "@analyticsCacheClearedSnack": {
    "description": "Success snack. Same word as the button, per ARCH_5 §2.8."
  },
  "analyticsCacheFailed": "Could not clear the saved figures",
  "@analyticsCacheFailed": {
    "description": "Failure snack. Names what failed rather than apologising."
  },
  "analyticsDrillTitle": "Behind this figure",
  "@analyticsDrillTitle": {
    "description": "Fallback title for the drill-down while its label resolves."
  },
  "analyticsDrillTotal": "These come to",
  "@analyticsDrillTotal": {
    "description": "Precedes the drill-down's per-currency subtotals."
  },
  "analyticsDrillLoading": "Loading these transactions…",
  "@analyticsDrillLoading": {
    "description": "Semantics label on the drill-down's skeleton."
  },
  "analyticsDrillEmptyTitle": "Nothing here in this window",
  "@analyticsDrillEmptyTitle": {
    "description": "Drill-down empty state."
  },
  "analyticsDrillEmptyBody": "The window is set on the insights screen. Widen it and these may appear.",
  "@analyticsDrillEmptyBody": {
    "description": "Names the likely cause: the filter is what the reader just chose, the window is what they may have forgotten."
  },
  "analyticsDrillUnknownTitle": "This link does not point anywhere",
  "@analyticsDrillUnknownTitle": {
    "description": "Shown when the route's parameters name no filter this version knows."
  },
  "analyticsDrillUnknownBody": "Open insights and choose a figure to look behind.",
  "analyticsOtherSlices": "Everything else",
  "@analyticsOtherSlices": {
    "description": "The grouped remainder wedge of a donut, past the sixth slice. A ring of twelve slivers is not readable, so the tail becomes one wedge that says what it is."
  },
  "analyticsTopThree": "in three kinds",
  "@analyticsTopThree": {
    "description": "The quiet line under the percentage in the concentration donut's centre, saying what that percentage is of."
  },
  "@analyticsDrillUnknownBody": {
    "description": "Offers the way on rather than throwing: the route is reachable from outside the app."
  },
  "aboutHowItWorksHeader": "How it works",
  "aboutLicences": "Open source licences",
  "aboutLicencesHelp": "The libraries Alaya is built on.",
  "aboutOfflineBody": "Everything is stored on this device. Alaya only reaches the internet to fetch exchange rates, once a day.",
  "aboutStorageBody": "Your data is not encrypted, and no copy of it exists anywhere else unless you make a backup yourself.",
  "@aboutStorageBody": {
    "description": "The same threat model the lock screen states, in the place somebody comes looking for it. Two locations is not duplication: one is a decision point, the other is where a question gets answered."
  },
  "aboutTagline": "A finance and home manager that works entirely on your phone.",
  "accountCurrencyHeader": "Currency",
  "accountCurrencyLockedHelp": "Fixed, because changing it would reinterpret every amount already recorded here.",
  "@accountCurrencyLockedHelp": {
    "description": "Law L9 at its sharpest: the home currency is a display choice, but an account’s own currency is what its money is."
  },
  "accountCurrencyNewHelp": "What this account holds. It cannot be changed once you start recording against it.",
  "accountEditorEditTitle": "Edit account",
  "accountEditorSave": "Save account",
  "@accountEditorSave": {
    "description": "Names the thing, per archetype B — never a bare \"Save\"."
  },
  "accountEditorTitle": "New account",
  "accountIncludeInNetWorth": "Count in net worth",
  "accountIncludeInNetWorthHelp": "Off means the balance still shows here, but is left out of your total. Useful for an account you hold for someone else.",
  "@accountIncludeInNetWorthHelp": {
    "description": "ARCH_5 §7.2 requires the toggle be explained: without this line the reader cannot tell whether off means hidden or merely uncounted."
  },
  "accountKindBank": "Bank",
  "accountKindCard": "Card",
  "accountKindCash": "Cash",
  "accountKindHeader": "What kind?",
  "accountKindOther": "Other",
  "accountKindWallet": "Wallet",
  "accountNameLabel": "Name",
  "accountOpeningBalanceLabel": "Opening balance",
  "accountOpeningDateLabel": "True on",
  "@accountOpeningDateLabel": {
    "description": "Not \"date\": the question is which day the balance was correct, and \"date\" invites today by default."
  },
  "accountsAdd": "Add an account",
  "accountsArchive": "Archive this account",
  "accountsArchiveConfirmBody": "It will stop appearing when you record anything. Its history stays, and you can restore it here at any time.",
  "accountsArchiveConfirmTitle": "Archive this account?",
  "accountsArchiveHelp": "An archived account keeps all its history. It just stops appearing when you record something.",
  "@accountsArchiveHelp": {
    "description": "Says what survives, because \"archive\" does not tell the reader whether their transactions go with it."
  },
  "accountsArchived": "Account archived",
  "accountsArchivedChip": "Archived",
  "accountsArchivedHeader": "Archived",
  "accountsEmptyBody": "Add one so Alaya knows where your money is.",
  "accountsEmptyTitle": "No accounts yet",
  "accountsExcludedChip": "Not in net worth",
  "accountsLoading": "Loading your accounts…",
  "accountsMissingBody": "It may have been removed. Go back and pick another.",
  "@accountsMissingBody": {
    "description": "A stale deep link, or a row removed in another window. Stated rather than rendering a blank form that would silently create a second account on save."
  },
  "accountsMissingTitle": "That account is not here",
  "accountsRestore": "Restore this account",
  "accountsRestoreConfirmBody": "It will appear again everywhere you choose an account.",
  "@accountsRestoreConfirmBody": {
    "description": "Confirmed in both directions: restoring puts an account back into every picker, which is worth stating before it happens."
  },
  "accountsRestoreConfirmTitle": "Restore this account?",
  "accountsRestored": "Account restored",
  "accountsSaved": "Account saved",
  "actionBack": "Back",
  "actionContinue": "Continue",
  "appearanceModeDark": "Always dark",
  "appearanceModeHeader": "Light or dark",
  "appearanceModeLight": "Always light",
  "appearanceModeSystem": "Match my phone",
  "appearanceModeSystemHelp": "Follows your phone’s light and dark setting.",
  "appearancePaletteHeader": "Colours",
  "appearanceThemeLabHelp": "See every colour, spacing and text style the app uses.",
  "backupNotEncryptedWarning": "This backup is not encrypted. Anyone who receives the file can read every account, balance and transaction in it.",
  "@backupNotEncryptedWarning": {
    "description": "ARCH_3 §3.4 requires this on every export confirmation — not once in a help page, and not as a tooltip."
  },
  "currenciesHomeLocked": "Cannot be turned off — your totals are added up in this.",
  "@currenciesHomeLocked": {
    "description": "Law L9: disabling it would leave the dashboard with no currency to aggregate into. Disabled rather than hidden, so it reads as an explanation and not a rendering fault."
  },
  "currenciesLoading": "Loading currencies…",
  "currenciesToggleFailed": "That could not be changed",
  "dataBackupHeader": "Backup",
  "dataExportBody": "Sends a copy of your data to WhatsApp, Drive, or anywhere else you choose.",
  "dataExportConfirmAction": "Share it",
  "dataExportConfirmTitle": "Share a backup?",
  "dataExportFailed": "The backup could not be made",
  "dataExportTitle": "Share a backup",
  "dataRestoreHeader": "Restore",
  "dataRestorePending": "Coming in the next update.",
  "@dataRestorePending": {
    "description": "Stated as not-yet-here rather than offered and broken: restore needs the Storage Access Framework picker and a merge strategy, both of which are 8B’s."
  },
  "dataRestoreTitle": "Restore from a backup",
  "lockBackspace": "Delete last digit",
  "lockBiometricFailed": "Not recognised. Enter your PIN instead.",
  "lockBiometricReason": "Unlock Alaya",
  "@lockBiometricReason": {
    "description": "Shown by the system prompt, so it must be localised before it reaches the plugin (Law U5)."
  },
  "lockEraseFailed": "The data could not be deleted. Your PIN is unchanged.",
  "@lockEraseFailed": {
    "description": "Says what did not change, so a failed erase does not leave the user unsure whether they are locked out of a half-wiped app."
  },
  "lockErasing": "Deleting everything on this device…",
  "@lockErasing": {
    "description": "The ten-failure auto-erase is running. It takes the whole screen, because there is nothing left to enter a PIN against."
  },
  "lockForgotPin": "I have forgotten my PIN",
  "lockHonestBody": "This PIN stops someone who picks up your unlocked phone from opening Alaya. It does not encrypt your data — anyone with access to the phone's files can still read them. Your phone's own lock screen is what protects the file itself.",
  "@lockHonestBody": {
    "description": "ARCH_3 §2.5, and the most important string in the app. No \"bank-grade\", no \"military-grade\", and no padlock glyph beside it: the database is plaintext by design (ARCH_1 §2.1) and claiming otherwise would be dishonest and a Play listing risk."
  },
  "lockThrottledWhy": "The wait gets longer after each wrong attempt.",
  "@lockThrottledWhy": {
    "description": "Says why the delay exists, so a throttle reads as deliberate rather than as the app having frozen."
  },
  "lockTitle": "Enter your PIN",
  "lockUseBiometric": "Use fingerprint",
  "@lockUseBiometric": {
    "description": "The keypad key is an icon, so this is its Semantics label (ARCH_5 §2.7)."
  },
  "lockWrongPin": "That PIN is not right.",
  "onboardingAccountsBody": "Where do you keep your money? Add the ones you use.",
  "onboardingAccountsTitle": "Your accounts",
  "onboardingAddAccount": "Add an account",
  "onboardingCurrencyBody": "Which currency should Alaya add your totals up in?",
  "onboardingCurrencyNote": "This changes how totals are shown. It does not change any amount you have already recorded, and each account keeps its own currency.",
  "@onboardingCurrencyNote": {
    "description": "Law L9 in plain words. Somebody who thinks they are converting their history would be very surprised later."
  },
  "onboardingCurrencyTitle": "Your currency",
  "onboardingFinish": "Finish",
  "onboardingLoading": "Getting things ready…",
  "onboardingLockOnBody": "Alaya will ask for your PIN when you open it. You can change or remove it in Settings › Security.",
  "onboardingLockOnHeader": "Lock is on",
  "onboardingNext": "Next",
  "onboardingNoAccountsBody": "Add at least one so Alaya knows where your money is.",
  "onboardingNoAccountsTitle": "No accounts yet",
  "onboardingOpeningNote": "The opening balance is what was there on the date you give. Alaya needs both: a balance with no date cannot be placed in your ledger, and anything you record before that date would not be counted.",
  "@onboardingOpeningNote": {
    "description": "Anomaly A03. This is the paragraph that stops an opening balance being captured without its date."
  },
  "onboardingRemoveAccount": "Remove this account",
  "onboardingSaveAccounts": "Save accounts",
  "onboardingSecurityBody": "You can put a PIN on Alaya. This is optional and you can add one later.",
  "onboardingSecurityTitle": "Lock the app?",
  "onboardingSkip": "Skip",
  "onboardingSkipBody": "You can change all of this later in Settings.",
  "onboardingSkipTitle": "Skip setting up?",
  "onboardingTitle": "Welcome to Alaya",
  "payeeKindEmployer": "Employer",
  "payeeKindMerchant": "Shop",
  "payeeKindOther": "Other",
  "payeeKindPerson": "Person",
  "payeeKindUtility": "Utility",
  "payeeNameLabel": "Name",
  "payeePhoneOptionalLabel": "Phone (optional)",
  "@payeePhoneOptionalLabel": {
    "description": "Marked optional, because an unmarked second field reads as required and is the commonest reason a two-field sheet feels like a form."
  },
  "payeesAdd": "Add a payee",
  "payeesDelete": "Delete",
  "payeesDeleteConfirmBody": "Transactions that named them keep their record. They just stop being suggested.",
  "payeesDeleteConfirmTitle": "Delete this payee?",
  "payeesDeleteFailed": "That could not be deleted",
  "payeesDeleted": "Payee deleted",
  "payeesEditTitle": "Edit payee",
  "payeesEmptyBody": "These build up as you record who you paid.",
  "payeesEmptyTitle": "No payees yet",
  "payeesLoading": "Loading payees…",
  "payeesNoMatchBody": "Try part of the name.",
  "payeesNoMatchTitle": "No payees match that",
  "payeesSave": "Save payee",
  "payeesSaveFailed": "That could not be saved",
  "payeesSaved": "Payee saved",
  "payeesSearchHint": "Search payees",
  "paymentKindBankTransfer": "Bank transfer",
  "paymentKindCard": "Card",
  "paymentKindCash": "Cash",
  "paymentKindCheque": "Cheque",
  "paymentKindOther": "Other",
  "paymentKindUpi": "UPI",
  "paymentKindWallet": "Wallet",
  "paymentMethodNameLabel": "Name",
  "paymentMethodsAdd": "Add a payment method",
  "paymentMethodsDelete": "Delete",
  "paymentMethodsDeleteConfirmBody": "Transactions that used it keep their record of having done so. It just stops being offered.",
  "paymentMethodsDeleteConfirmTitle": "Delete this payment method?",
  "paymentMethodsDeleteFailed": "That could not be deleted",
  "paymentMethodsDeleted": "Payment method deleted",
  "paymentMethodsEditTitle": "Edit payment method",
  "paymentMethodsEmptyBody": "Add how you usually pay — cash, UPI, a card.",
  "paymentMethodsEmptyTitle": "No payment methods",
  "paymentMethodsLoading": "Loading payment methods…",
  "paymentMethodsSave": "Save payment method",
  "paymentMethodsSaveFailed": "That could not be saved",
  "paymentMethodsSaved": "Payment method saved",
  "paymentMethodsSystemChip": "Built in",
  "@paymentMethodsSystemChip": {
    "description": "Renameable but not removable, and the chip says so before the user hunts for a delete that is not there."
  },
  "pinSetupBackupBody": "You have just put a lock on this app. A backup means a forgotten PIN never costs you your records.",
  "pinSetupBackupHeader": "Make a backup?",
  "pinSetupBackupLater": "Not now",
  "pinSetupBackupNow": "Back up now",
  "pinSetupConfirmPrompt": "Enter it again",
  "pinSetupDone": "Your PIN is set",
  "pinSetupDoneBody": "Alaya will ask for it when you open the app, and again after a minute in the background.",
  "pinSetupEnterPrompt": "Choose a PIN",
  "pinSetupMismatch": "Those did not match. Start again.",
  "@pinSetupMismatch": {
    "description": "Both entries are cleared, because somebody who mistyped does not know which of the two was wrong."
  },
  "pinSetupRecoveryAck": "I have saved this code somewhere safe",
  "@pinSetupRecoveryAck": {
    "description": "The one confirmation, and it gates the button rather than warning after the fact."
  },
  "pinSetupRecoveryBody": "This is the only way back in if you forget your PIN. It is shown once and cannot be shown again.",
  "@pinSetupRecoveryBody": {
    "description": "True rather than cautious: PinService stores only a hash, so the app genuinely cannot redisplay it."
  },
  "pinSetupRecoveryCopied": "Recovery code copied",
  "pinSetupRecoveryCopy": "Copy code",
  "pinSetupRecoveryHeader": "Your recovery code",
  "pinSetupRecoveryWhereToKeep": "A password manager is a good place for it. A photo in your gallery is not.",
  "pinSetupTitle": "Set a PIN",
  "recoveryCodeLabel": "Recovery code",
  "recoveryCodePrompt": "Enter the recovery code you saved when you set your PIN.",
  "recoveryDone": "Your PIN has been changed",
  "recoveryEraseEverything": "Erase everything",
  "recoveryExportFirst": "Export a copy first",
  "recoveryExported": "A copy has been shared. Check it arrived before you erase.",
  "@recoveryExported": {
    "description": "Asks the user to verify: a backup nobody confirmed is not a backup."
  },
  "recoveryForgotBoth": "I do not have the recovery code either",
  "recoveryForgotBothBody": "Without your PIN or your recovery code there is no way back into this data. You can export a copy first, then erase everything and start again.",
  "@recoveryForgotBothBody": {
    "description": "The export is possible only because the database is plaintext — with encryption the copy would be unreadable without the key the user has lost. ARCH_4 records that as the improvement dropping encryption bought."
  },
  "recoveryForgotBothTitle": "Starting over",
  "recoveryNewPinPrompt": "Choose a new PIN",
  "recoveryTitle": "Forgotten PIN",
  "securityAutoEraseConfirmAction": "Turn it on",
  "securityAutoEraseConfirmTitle": "Turn on erase after repeated failures?",
  "securityAutoEraseFailed": "That could not be changed",
  "securityAutoEraseHeader": "If the PIN is entered wrongly",
  "securityAutoEraseOff": "Erase after repeated failures is off",
  "securityAutoEraseOn": "Erase after repeated failures is on",
  "securityAutoEraseTitle": "Erase everything after repeated failures",
  "securityAutoLockHeader": "Auto-lock",
  "securityAutoLockTitle": "Lock when I leave the app",
  "securityChangePin": "Change PIN",
  "securityChecking": "Checking…",
  "@securityChecking": {
    "description": "Neither branch is guessed: a row saying \"no PIN set\" for one frame to somebody who has one would be alarming for the wrong reason."
  },
  "securityPinHeader": "PIN",
  "securityRemovePin": "Remove PIN",
  "securityRemovePinConfirmBody": "Anyone who picks up your unlocked phone will be able to open Alaya. You will be asked for your current PIN next.",
  "securityRemovePinConfirmTitle": "Remove the PIN?",
  "securityRemovePinHelp": "You will need your current PIN to do this.",
  "securitySetPin": "Set a PIN",
  "securitySetPinHelp": "Alaya will ask for it when you open the app.",
  "settingsAbout": "About",
  "settingsAccounts": "Accounts",
  "settingsAppearance": "Appearance",
  "settingsCurrencies": "Currencies",
  "settingsData": "Data",
  "settingsGroupApp": "The app",
  "settingsGroupMoney": "Your money",
  "settingsGroupThings": "Your things",
  "settingsNoMatchBody": "Try a different word — \"dark\", \"PIN\" and \"backup\" all find something.",
  "@settingsNoMatchBody": {
    "description": "Names the search rather than the tree: \"no settings\" in front of a list the user can see is a lie. The examples are the keywords the rows actually match on."
  },
  "settingsNoMatchTitle": "Nothing matches that",
  "settingsPayees": "Payees",
  "settingsPaymentMethods": "Payment methods",
  "settingsSearchHint": "Search settings",
  "settingsSecurity": "Security",
  "settingsTags": "Tags",
  "settingsUnits": "Units",
  "tagColourHeader": "Colour",
  "tagColourHelp": "Optional. Kept as chosen, so it stays the same if you change the app’s palette later.",
  "@tagColourHelp": {
    "description": "Honest about the freeze: colorArgb is a stored int, so a tag coloured under one preset keeps that colour when the palette changes."
  },
  "tagColourNone": "No colour",
  "tagColourSwatch": "Use this colour",
  "@tagColourSwatch": {
    "description": "The swatches are colour-only, so each needs a Semantics label (Law U17)."
  },
  "tagEditorEditTitle": "Edit tag",
  "tagEditorSave": "Save tag",
  "tagEditorTitle": "New tag",
  "tagNameLabel": "Name",
  "tagParentHeader": "Group under",
  "tagParentHelp": "Optional. Grouping keeps long tag lists readable. Only one level deep.",
  "tagParentNone": "No group",
  "tagScopeDeposit": "Money in",
  "tagScopeDepositHelp": "Offered when you record money coming in.",
  "tagScopeInventory": "Items",
  "tagScopeInventoryHelp": "Offered on things you keep at home.",
  "tagScopeRecurring": "Recurring",
  "tagScopeRecurringHelp": "Offered on bills and subscriptions.",
  "tagScopeService": "Services",
  "tagScopeServiceHelp": "Offered on appliances and their service records.",
  "tagScopeShopping": "Shopping lists",
  "tagScopeShoppingHelp": "Used to group a shopping list under headings.",
  "tagScopeWithdrawal": "Money out",
  "tagScopeWithdrawalHelp": "Offered when you record spending.",
  "tagScopesHeader": "Where it appears",
  "tagScopesHelp": "A tag is only offered where you turn it on. This is what keeps \"Kitchen\" out of the list when you record your salary.",
  "@tagScopesHelp": {
    "description": "ARCH_5 §7.2’s allowedIn* row, said in the terms the requirement itself uses."
  },
  "tagsAdd": "Add a tag",
  "tagsDelete": "Delete this tag",
  "tagsDeleteConfirmBody": "Transactions and items already carrying it keep it in their history. It stops appearing when you tag something new.",
  "@tagsDeleteConfirmBody": {
    "description": "Says what survives, because a soft delete is not what \"delete\" usually promises (ARCH_3 §4)."
  },
  "tagsDeleteConfirmTitle": "Delete this tag?",
  "tagsDeleteHelp": "Anything already tagged keeps its history. The tag just stops being offered.",
  "tagsDeleted": "Tag deleted",
  "tagsEmptyBody": "Tags let you group things across accounts — \"Kitchen\", \"Car\", \"Diwali\".",
  "tagsEmptyTitle": "No tags yet",
  "tagsLoading": "Loading tags…",
  "tagsMissingBody": "It may have been deleted. Go back and pick another.",
  "tagsMissingTitle": "That tag is not here",
  "tagsNoScopesWarning": "This tag is not offered anywhere. Turn on at least one place below, or it will never appear.",
  "@tagsNoScopesWarning": {
    "description": "A tag with no scopes cannot appear anywhere in the app, which makes it invisible everywhere except this screen — exactly the dead row somebody would hunt for in the pickers first."
  },
  "tagsSaved": "Tag saved",
  "tagsSystemChip": "Built in",
  "unitBaseGrams": "grams",
  "unitBaseMillilitres": "millilitres",
  "unitBasePieces": "pieces",
  "unitCategoryHeader": "What does it measure?",
  "unitCategoryNewHelp": "Choose carefully: this cannot be changed later.",
  "unitCodeHelp": "What you will see beside a quantity — kg, ml, pc.",
  "unitCodeLabel": "Short code",
  "unitCodeLockedHelp": "Fixed once the unit exists, because other records point at it.",
  "unitEditorEditTitle": "Edit unit",
  "unitEditorSave": "Save unit",
  "unitEditorTitle": "New unit",
  "unitFactorHeader": "How big is it?",
  "unitFactorMustBePositive": "That has to be more than zero.",
  "@unitFactorMustBePositive": {
    "description": "Guarded rather than trusted: a zero factor would convert every quantity in the unit to nothing and divide the inventory valuation by zero."
  },
  "unitFactorThisUnit": "this unit",
  "@unitFactorThisUnit": {
    "description": "Stands in for the name while the field is still empty, so the question reads as a sentence either way."
  },
  "unitFactorVaries": "It varies — I cannot give one number",
  "unitNameLabel": "Name",
  "unitVariesBack": "Actually, I can give a number",
  "@unitVariesBack": {
    "description": "A way back, for somebody who realises on reading this that they can state an amount."
  },
  "unitVariesCreateItem": "Create an item instead",
  "unitVariesInsteadBody": "Add \"Biscuit packet\" as its own item, counted in pieces. Then two packets is two of that item, and Alaya can price and track them properly.",
  "unitVariesInsteadTitle": "Make it an item instead",
  "unitVariesTitle": "Then it is not a unit",
  "unitVariesWhy": "A unit has to be the same amount every time. One packet of biscuits and one packet of rice are different weights, so Alaya could not add two packets together or work out what one cost.",
  "@unitVariesWhy": {
    "description": "ARCH_1 §5.3 explained by consequence rather than by quoting the rule. This is what makes the alternative obviously better instead of merely mandated."
  },
  "unitsAdd": "Add a unit",
  "unitsCategoriesFixedNote": "Weight, volume and count are the only three kinds there are. Alaya never converts between them, so a kilo can never become a litre by accident.",
  "@unitsCategoriesFixedNote": {
    "description": "ARCH_1 §5.3 and Law L8, stated where somebody about to add a unit reads it before trying rather than as a refusal afterwards."
  },
  "unitsDelete": "Delete this unit",
  "unitsDeleteConfirmBody": "Anything already bought in this unit keeps its quantity, but that quantity would no longer be readable. Only delete a unit you have not used.",
  "@unitsDeleteConfirmBody": {
    "description": "The R18 failure from the other direction: a quantity whose unit has gone cannot be converted or valued."
  },
  "unitsDeleteConfirmTitle": "Delete this unit?",
  "unitsDeleteHelp": "Only possible while nothing is measured in it.",
  "unitsDeleted": "Unit deleted",
  "unitsEmptyBody": "Alaya ships with the common ones. Add one if you measure something differently.",
  "unitsEmptyTitle": "No units",
  "unitsLoading": "Loading units…",
  "unitsMissingBody": "It may have been deleted. Go back and pick another.",
  "unitsMissingTitle": "That unit is not here",
  "unitsSaved": "Unit saved",
  "unitsSystemChip": "Built in",
  "currenciesRowSubtitle": "{symbol} · {digits, plural, =0{no decimal places} =1{1 decimal place} other{{digits} decimal places}}",
  "@currenciesRowSubtitle": {
    "description": "The precision matters to the reader: JPY has none, so an amount typed as 1200 is ¥1,200 and not ¥12.00.",
    "placeholders": {
      "symbol": {
        "type": "String"
      },
      "digits": {
        "type": "int"
      }
    }
  },
  "currenciesRowTitle": "{code} · {name}",
  "@currenciesRowTitle": {
    "description": "A currency row: the code first, because it is what the pickers show.",
    "placeholders": {
      "code": {
        "type": "String"
      },
      "name": {
        "type": "String"
      }
    }
  },
  "dataExportDone": "Backup saved as {fileName}",
  "@dataExportDone": {
    "description": "Names the file, because a backup the user cannot identify later is one they will not trust when they need it (ARCH_3 §3.4).",
    "placeholders": {
      "fileName": {
        "type": "String"
      }
    }
  },
  "lockThrottled": "Too many attempts. Try again in {time}",
  "@lockThrottled": {
    "description": "The countdown ticks. Formatted in Dart as m:ss, because a plural on \"second\" cannot express 1:05.",
    "placeholders": {
      "time": {
        "type": "String"
      }
    }
  },
  "onboardingCurrencyChip": "{code} {symbol}",
  "@onboardingCurrencyChip": {
    "placeholders": {
      "code": {
        "type": "String"
      },
      "symbol": {
        "type": "String"
      }
    }
  },
  "onboardingStepOf": "Step {step} of {total}",
  "@onboardingStepOf": {
    "description": "Words and a count rather than dots: the one question people abandon a setup flow over is how long it will take.",
    "placeholders": {
      "step": {
        "type": "int"
      },
      "total": {
        "type": "int"
      }
    }
  },
  "pinSetupLength": "{length} digits",
  "@pinSetupLength": {
    "placeholders": {
      "length": {
        "type": "int"
      }
    }
  },
  "recoveryTypeToConfirm": "Type {word} to confirm",
  "@recoveryTypeToConfirm": {
    "description": "The word is passed in from DataTransferPort.eraseConfirmationWord and is deliberately not translated, so a support article can tell anyone what to type.",
    "placeholders": {
      "word": {
        "type": "String"
      }
    }
  },
  "securityAutoEraseBody": "When on, {count} wrong PIN attempts in a row will delete everything on this device.",
  "@securityAutoEraseBody": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "securityAutoEraseConfirmBody": "After {count} failed attempts, every account, transaction and item on this device is deleted. There is no undo, and no copy unless you have made a backup.",
  "@securityAutoEraseConfirmBody": {
    "description": "The scary confirm names the number. A generic \"are you sure?\" would not earn consent to a setting that destroys a household’s records.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "securityAutoLockBody": "Locks again after {seconds} seconds in the background.",
  "@securityAutoLockBody": {
    "description": "Stated rather than configurable in 8A: autoLockDelay is a constant, and a picker writing a setting nothing reads would be a dead control.",
    "placeholders": {
      "seconds": {
        "type": "int"
      }
    }
  },
  "settingsAccountCount": "{count, plural, =0{No accounts} =1{1 account} other{{count} accounts}}",
  "@settingsAccountCount": {
    "description": "Archived accounts included, because this row is the only way to reach one and restore it.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "settingsCurrencyCount": "{enabled} of {total} enabled",
  "@settingsCurrencyCount": {
    "placeholders": {
      "enabled": {
        "type": "int"
      },
      "total": {
        "type": "int"
      }
    }
  },
  "settingsPayeeCount": "{count, plural, =0{No payees} =1{1 payee} other{{count} payees}}",
  "@settingsPayeeCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "settingsPaymentMethodCount": "{count, plural, =0{No payment methods} =1{1 payment method} other{{count} payment methods}}",
  "@settingsPaymentMethodCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "settingsTagCount": "{count, plural, =0{No tags} =1{1 tag} other{{count} tags}}",
  "@settingsTagCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "settingsUnitCount": "{count, plural, =0{No units} =1{1 unit} other{{count} units}}",
  "@settingsUnitCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "unitFactorHelp": "One of this unit has to be the same number of {base} every time.",
  "@unitFactorHelp": {
    "description": "The condition for being a unit at all. Somebody who reads this and cannot meet it has found the \"make it an item\" path.",
    "placeholders": {
      "base": {
        "type": "String"
      }
    }
  },
  "unitFactorQuestion": "How many {base} is one {unit}?",
  "@unitFactorQuestion": {
    "description": "Asked in base units, never in the stored thousandths — reproducing that arithmetic is what ARCH_4 R18 got wrong three times.",
    "placeholders": {
      "base": {
        "type": "String"
      },
      "unit": {
        "type": "String"
      }
    }
  },
  "unitsEquals": "1 {code} = {amount} {base}",
  "@unitsEquals": {
    "description": "What the unit is, assembled from the stored thousandths so the reader never meets them.",
    "placeholders": {
      "code": {
        "type": "String"
      },
      "amount": {
        "type": "String"
      },
      "base": {
        "type": "String"
      }
    }
  },
  "unitsRowTitle": "{name} ({code})",
  "@unitsRowTitle": {
    "placeholders": {
      "name": {
        "type": "String"
      },
      "code": {
        "type": "String"
      }
    }
  }
}
```

---

## Tests

**The harness's three fakes are why the ports exist.** `PinService` and `BackupService` are `final class`, so
neither can be implemented outside its own library, and `flutter_secure_storage` and `local_auth` both need a
platform channel. Without `AppLock`, `BiometricGate` and `DataTransferPort`, not one test in this phase could have
been written — which is a firmer argument for the contracts than any layering diagram.

The override list is **fixed length** (ARCH_6 P5): a conditional entry changes the count between scopes and
Riverpod refuses it outright, while two `pumpWidget` calls in one test silently reuse the first scope — so a
varying list fails in both directions. `pumpSettings` applies the text scaler through `MaterialApp.builder`,
because `WidgetsApp` re-establishes `MediaQuery` from the view and an override above it never arrives.

Four assertions worth naming, because each pins a decision rather than a rendering:

**The honest copy is asserted by phrase, not by key.** `find.textContaining('does not encrypt your data')` on both
the lock screen and Security, plus `findsNothing` for `Icons.lock`, `Icons.lock_outline`, "bank-grade" and
"military". A key can be renamed; the promise cannot.

**A throttled keypad accepts no digits.** The delay cannot be spent guessing, which a visible countdown alone
would not prove.

**Six dots for a six-digit PIN**, which is what `readPinLength` was added to the port for.

**A tag parent cycle does not hang the screen.** The root walk is bounded by the tag count — a cycle should be
impossible, and a UI that trusts that is a UI that freezes when it turns out not to be.

### `test/support/settings_harness.dart`

```dart
/// Shared scaffolding for the 8A widget tests.
///
/// **The three fakes here are why `AppLock`, `BiometricGate` and `DataTransferPort` exist.** `PinService` and
/// `BackupService` are `final class`, so neither can be implemented outside its own library — and
/// `flutter_secure_storage` and `local_auth` both need a platform channel. Without the contracts, not one test
/// in this phase could have been written, which is a stronger argument for them than any layering diagram.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';
import 'package:alaya/domain/services/lock/app_lock.dart';
import 'package:alaya/domain/services/lock/biometric_gate.dart';
import 'package:alaya/features/onboarding/providers/onboarding_providers.dart';
import 'package:alaya/features/settings/providers/app_settings_providers.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/features/settings/providers/settings_providers.dart';
import 'package:alaya/features/settings/providers/tag_settings_providers.dart';
import 'package:alaya/features/settings/providers/unit_settings_providers.dart';

import 'fake_settings_repository.dart';

/// The narrowest width this app supports, with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every derived date is identical on every machine.
final Clock kSettingsClock = FixedClock(DateTime(2026, 8, 10, 9, 30));

/// Today, according to [kSettingsClock].
const DateKey kSettingsToday = DateKey(20260810);

/// A future that never completes, for a `FutureProvider`'s loading branch.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// A stream that never emits and never closes, for a `StreamProvider`'s loading branch.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// An `AppLock` that answers from fields a test sets, rather than from secure storage.
class FakeAppLock implements AppLock {
  /// Creates the fake.
  FakeAppLock({
    this.enabled = false,
    this.pinLength = 4,
    this.failedCount = 0,
    this.lockout,
    this.correctPin = '1234',
    this.enableFails = false,
  });

  /// Whether a lock is configured.
  bool enabled;

  /// How many digits the configured PIN has.
  int pinLength;

  /// Consecutive failures recorded.
  int failedCount;

  /// The delay in force, or null.
  Duration? lockout;

  /// The PIN [verifyPin] accepts.
  String correctPin;

  /// Whether [enable] reports a failure, for the error branch of PIN setup.
  bool enableFails;

  /// The recovery code [enable] hands back.
  static const String recoveryCode = 'ABCDE-FGHJK';

  @override
  Future<bool> get isEnabled async => enabled;

  @override
  Future<int> readPinLength() async => pinLength;

  @override
  Future<int> readFailedCount() async => failedCount;

  @override
  Future<Duration?> remainingLockout() async => lockout;

  @override
  Future<UnlockOutcome> verifyPin(String pin) async {
    if (lockout != null) {
      return UnlockOutcome(
        unlocked: false,
        refusal: UnlockRefusal.throttled,
        failedCount: failedCount,
        retryAfter: lockout,
      );
    }
    if (pin == correctPin) return const UnlockOutcome.success();
    failedCount += 1;
    return UnlockOutcome(
      unlocked: false,
      refusal: UnlockRefusal.wrongPin,
      failedCount: failedCount,
    );
  }

  @override
  Future<Result<String, Failure>> enable({required String pin}) async {
    if (enableFails) {
      return const Result.failure(
        UnexpectedFailure('Secure storage is unavailable on this device.'),
      );
    }
    enabled = true;
    correctPin = pin;
    pinLength = pin.length;
    return const Result.ok(recoveryCode);
  }

  @override
  Future<Result<void, Failure>> changePin({
    required String currentPin,
    required String newPin,
  }) async =>
      const Result.ok(null);

  @override
  Future<Result<void, Failure>> disable({required String pin}) async {
    enabled = false;
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> resetWithRecoveryCode({
    required String code,
    required String newPin,
  }) async {
    if (code.replaceAll('-', '').toUpperCase() != recoveryCode.replaceAll('-', '')) {
      return const Result.failure(
        ValidationFailure('That recovery code is not right.', field: 'code'),
      );
    }
    correctPin = newPin;
    return const Result.ok(null);
  }
}

/// A `BiometricGate` that neither needs a sensor nor a platform channel.
class FakeBiometricGate implements BiometricGate {
  /// Creates the fake.
  FakeBiometricGate({this.available = false, this.succeeds = true});

  /// Whether the shortcut is offered at all.
  bool available;

  /// Whether [authenticate] succeeds.
  bool succeeds;

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<Result<void, Failure>> authenticate({required String reason}) async => succeeds
      ? const Result.ok(null)
      : const Result.failure(
          BusinessRuleFailure('Not recognised.', rule: 'biometricRejected'),
        );
}

/// A `DataTransferPort` that records what it was asked to do.
class FakeDataTransfer implements DataTransferPort {
  /// Creates the fake.
  FakeDataTransfer({this.exportFails = false, this.eraseFails = false});

  /// Whether the export reports a failure.
  bool exportFails;

  /// Whether the erase reports a failure.
  bool eraseFails;

  /// How many exports were requested.
  int exports = 0;

  /// How many erases were requested.
  int erases = 0;

  @override
  Future<Result<BackupArtefact, Failure>> exportAndShare() async {
    exports += 1;
    if (exportFails) {
      return const Result.failure(UnexpectedFailure('No room left on this device.'));
    }
    return const Result.ok(
      (path: '/cache/alaya.db', sizeBytes: 4096, isZipped: false, fileName: 'alaya-backup.db'),
    );
  }

  // Phase 8B extended `DataTransferPort` with SAF export, history and restore, so this fake stopped satisfying
  // it. Answering flatly is right here: 8A's tests are about the lock and the settings tree, and a fake that
  // pretended to restore would invite an 8A test to assert on 8B's behaviour.
  @override
  Future<Result<BackupArtefact?, Failure>> exportToLocation() async =>
      const Result.ok(null);

  @override
  Stream<List<BackupRecord>> watchHistory() => Stream.value(const []);

  @override
  Future<Result<void, Failure>> forgetHistoryEntry(String id) async => const Result.ok(null);

  @override
  Future<Result<String?, Failure>> pickBackupFile() async => const Result.ok(null);

  @override
  Future<Result<int, Failure>> readBackupVersion(String path) async => const Result.ok(1);

  @override
  bool get canSaveToLocation => false;

  @override
  int get appSchemaVersion => 1;

  @override
  Future<Result<RestoreOutcome, Failure>> merge(String path) async => const Result.ok(
        (mode: RestoreMode.merge, tablesMerged: 0, backupSchemaVersion: 1, rollbackAvailable: false),
      );

  @override
  Future<Result<RestoreOutcome, Failure>> replace(String path) async => const Result.ok(
        (mode: RestoreMode.replace, tablesMerged: 0, backupSchemaVersion: 1, rollbackAvailable: false),
      );

  @override
  Future<Result<void, Failure>> rollback() async => const Result.ok(null);

  @override
  Future<bool> hasRollback() async => false;

  @override
  Future<Result<void, Failure>> eraseEverything() async {
    erases += 1;
    return eraseFails
        ? const Result.failure(UnexpectedFailure('The data could not be deleted.'))
        : const Result.ok(null);
  }
}

/// One account, for the lists and the editor.
Account account({
  String id = 'ac-1',
  String name = 'Cash',
  AccountKind kind = AccountKind.cash,
  bool isArchived = false,
  bool includeInNetWorth = true,
}) =>
    Account(
      id: id,
      name: name,
      normalizedName: name.toLowerCase(),
      kind: kind,
      currencyCode: 'INR',
      openingBalance: const Money(250000, 'INR'),
      openingBalanceDateKey: kSettingsToday,
      isArchived: isArchived,
      includeInNetWorth: includeInNetWorth,
      sortOrder: 0,
    );

/// One tag, scoped where the caller says.
Tag tag({
  String id = 'tg-1',
  String name = 'Kitchen',
  Set<TagScope> scopes = const {TagScope.inventory},
  String? parentTagId,
  bool isSystem = false,
}) =>
    Tag(
      id: id,
      name: name,
      normalizedName: name.toLowerCase(),
      allowedScopes: scopes,
      isSystem: isSystem,
      sortOrder: 0,
      isDeleted: false,
      parentTagId: parentTagId,
    );

/// One unit.
Unit unit({
  String code = 'kg',
  String displayName = 'Kilogram',
  UnitCategory category = UnitCategory.weight,
  int factorToBaseMilli = 1000000,
  bool isSystem = true,
}) =>
    Unit(
      code: code,
      category: category,
      factorToBaseMilli: factorToBaseMilli,
      displayName: displayName,
      isSystem: isSystem,
      sortOrder: 0,
    );

/// One payment method.
PaymentMethod paymentMethod({String id = 'pm-1', String name = 'Cash', bool isSystem = false}) =>
    PaymentMethod(
      id: id,
      name: name,
      kind: PaymentMethodKind.cash,
      isSystem: isSystem,
      sortOrder: 0,
    );

/// One payee.
Payee payee({String id = 'py-1', String name = 'Corner Shop', String? phone}) => Payee(
      id: id,
      name: name,
      normalizedName: name.toLowerCase(),
      kind: PayeeKind.merchant,
      phone: phone,
    );

/// One currency.
Currency currency({String code = 'INR', bool isEnabled = true}) => Currency(
      code: code,
      name: code,
      symbol: code == 'INR' ? '₹' : '¥',
      decimalDigits: code == 'JPY' ? 0 : 2,
      isEnabled: isEnabled,
      sortOrder: 0,
    );

/// Overrides every provider 8A's screens reach.
///
/// **Fixed length, always.** A conditional entry changes the override count between scopes and Riverpod refuses
/// it outright — and two `pumpWidget` calls in one test silently reuse the first scope, so a varying list fails
/// in both directions (ARCH_6 P5). Every provider is overridden even where a test does not care, because an
/// un-overridden repository reaches a real database, which a widget test has no business opening.
List<Override> settingsOverrides({
  FakeAppLock? lock,
  FakeBiometricGate? biometric,
  FakeDataTransfer? transfer,
  AsyncValue<List<Account>>? accounts,
  AsyncValue<List<Tag>>? tags,
  AsyncValue<List<Unit>>? units,
  AsyncValue<List<PaymentMethod>>? paymentMethods,
  AsyncValue<List<Payee>>? payees,
  AsyncValue<List<Currency>>? currencies,
}) =>
    [
      clockProvider.overrideWithValue(kSettingsClock),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      pinServiceProvider.overrideWithValue(lock ?? FakeAppLock()),
      biometricGateProvider.overrideWithValue(biometric ?? FakeBiometricGate()),
      dataTransferPortProvider.overrideWithValue(transfer ?? FakeDataTransfer()),
      accountsSettingsProvider.overrideWith(
        (ref) => _stream(accounts ?? AsyncValue.data([account()])),
      ),
      tagsSettingsProvider.overrideWith((ref) => _stream(tags ?? AsyncValue.data([tag()]))),
      unitsSettingsProvider.overrideWith((ref) => _stream(units ?? AsyncValue.data([unit()]))),
      paymentMethodsSettingsProvider.overrideWith(
        (ref) => _stream(paymentMethods ?? AsyncValue.data([paymentMethod()])),
      ),
      payeesSettingsProvider.overrideWith((ref) => _stream(payees ?? AsyncValue.data([payee()]))),
      currenciesSettingsProvider.overrideWith(
        (ref) => _stream(currencies ?? AsyncValue.data([currency()])),
      ),
      homeCurrencyCodeProvider.overrideWith((ref) async => 'INR'),
      accountsHomeCurrencyProvider.overrideWith((ref) async => 'INR'),
      onboardingCurrenciesProvider.overrideWith(
        (ref) => Stream.value([currency(), currency(code: 'JPY')]),
      ),
      onboardingCurrencyDigitsProvider.overrideWith(
        (ref, code) async => code == 'JPY' ? 0 : 2,
      ),
      settingsAccountCountProvider.overrideWith((ref) => Stream.value(1)),
      settingsPaymentMethodCountProvider.overrideWith((ref) => Stream.value(1)),
      settingsPayeeCountProvider.overrideWith((ref) => Stream.value(1)),
      settingsTagCountProvider.overrideWith((ref) => Stream.value(1)),
      settingsUnitCountProvider.overrideWith((ref) => Stream.value(1)),
      settingsCurrencyCountProvider.overrideWith(
        (ref) => Stream.value((enabled: 1, total: 2)),
      ),
    ];

Stream<T> _stream<T>(AsyncValue<T> value) => value.when(
      data: Stream.value,
      loading: pendingStream<T>,
      error: (error, stack) => Stream<T>.error(error, stack),
    );

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
///
/// The text scaler goes through `MaterialApp.builder`, not a `MediaQuery` above the app: `WidgetsApp`
/// re-establishes `MediaQuery` from the view, so an override placed above it never arrives (ARCH_5 §10).
///
/// [wrapInShell] supplies a `Scaffold`, because `MaterialApp` provides no `Material` ancestor and a shell
/// destination declares none of its own — without it, every `ChoiceChip` and `InkWell` asserts.
Future<void> pumpSettings(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
  bool dark = false,
  bool wrapInShell = false,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark
            ? AlayaTheme.dark(AlayaPresets.activePreset)
            : AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: wrapInShell ? Scaffold(body: child) : child,
      ),
    ),
  );
  await tester.pump();
}
```

### `test/features/lock/lock_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/lock/presentation/screens/lock_screen.dart';
import 'package:alaya/features/lock/presentation/widgets/pin_pad.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/settings_harness.dart';

/// `LockScreen` — archetype A's shape, all four states (Law U4, ARCH_5 §9.1).
///
/// **These tests exist only because `AppLock` is an interface.** `PinService` is `final class` and reaches
/// `flutter_secure_storage`, so there was no way to fake it and no way to run a platform channel here — the
/// contract is what makes the §9.1 gate reachable at all.
void main() {
  group('the four states', () {
    testWidgets('loading shows the keypad and no refusal', (tester) async {
      // The screen has no spinner: it is usable the instant it mounts, and the PIN length arriving a frame later
      // changes the dot count rather than gating the keys.
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(lock: FakeAppLock(enabled: true)),
      );
      expect(find.byType(PinKeypad), findsOneWidget);
      expect(find.text('That PIN is not right.'), findsNothing);
    });

    testWidgets('populated draws one dot per configured digit', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(lock: FakeAppLock(enabled: true, pinLength: 6)),
      );
      await tester.pumpAndSettle();
      // Six, not four. `readPinLength` was added to the port for exactly this — a six-digit PIN entered into four
      // boxes is a confusing failure rather than a wrong one.
      final dots = tester.widget<PinDots>(find.byType(PinDots));
      expect(dots.length, 6);
    });

    testWidgets('a wrong PIN shakes, clears, and says so', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(lock: FakeAppLock(enabled: true, correctPin: '9999')),
      );
      await tester.pumpAndSettle();
      final before = tester.widget<ShakeOnError>(find.byType(ShakeOnError)).trigger;

      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('That PIN is not right.'), findsOneWidget);
      // The trigger increments, so two failures in a row shake twice rather than once (ARCH_5 §2.6).
      expect(tester.widget<ShakeOnError>(find.byType(ShakeOnError)).trigger, greaterThan(before));
      // Cleared, so the next attempt starts empty rather than making the user delete four digits they already
      // know are wrong.
      expect(tester.widget<PinDots>(find.byType(PinDots)).filled, 0);
    });

    testWidgets('a throttle states a duration and refuses taps', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true, lockout: const Duration(seconds: 65)),
        ),
      );
      await tester.pumpAndSettle();

      // `m:ss` for anything past a minute, formatted in Dart because a plural on "second" cannot express 1:05.
      expect(find.textContaining('1:05'), findsOneWidget);
      expect(find.textContaining('The wait gets longer'), findsOneWidget);

      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      // Still nothing entered: a throttled keypad accepts no digits, so the delay cannot be spent guessing.
      expect(tester.widget<PinDots>(find.byType(PinDots)).filled, 0);
    });
  });

  group('the honest copy', () {
    testWidgets('says it does not encrypt, and shows no padlock', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(lock: FakeAppLock(enabled: true)),
      );
      await tester.pumpAndSettle();

      // **ARCH_3 §2.5, asserted rather than trusted.** This is the one string in the app whose absence would be a
      // Play listing risk as well as a lie, so the test names the phrase rather than the key.
      expect(find.textContaining('does not encrypt your data'), findsOneWidget);
      // No padlock: a closed padlock is the universal icon for encryption and would undo the sentence beside it.
      expect(find.byIcon(Icons.lock), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.textContaining('bank-grade'), findsNothing);
      expect(find.textContaining('military'), findsNothing);
    });
  });

  group('the biometric shortcut', () {
    testWidgets('is absent, not disabled, where the device has none', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true),
          biometric: FakeBiometricGate(),
        ),
      );
      await tester.pumpAndSettle();
      // A disabled control that can never become enabled is the dead affordance ARCH_5 §10 objects to.
      expect(find.byIcon(Icons.fingerprint), findsNothing);
    });

    testWidgets('appears where the device has one', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true),
          biometric: FakeBiometricGate(available: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
    });
  });

  group('the gate', () {
    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(lock: FakeAppLock(enabled: true, pinLength: 6)),
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('every target is large enough and named', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true),
          biometric: FakeBiometricGate(available: true),
        ),
      );
      await tester.pumpAndSettle();
      // The keypad is why this passes without special pleading: every key is a labelled 48dp target, which the
      // system keyboard could not have guaranteed.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
```

### `test/features/settings/settings_tree_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/settings/presentation/screens/accounts_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/currencies_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/security_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/settings_screen.dart';
import 'package:alaya/features/settings/providers/app_settings_providers.dart';
import 'package:alaya/features/settings/presentation/screens/tags_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/units_settings_screen.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/settings_harness.dart';

/// Tall enough that a lazy `ListView` builds its whole body.
///
/// **Content assertions get this; the U15 gate does not.** A settings body is a lazy list, so at 320x640 a
/// row below the fold is never built and `findsNothing` passes for the wrong reason — the same trap 7B's
/// analytics sliver had. Splitting the two concerns is the fix: these tests ask *what exists*, and the
/// separate 320x640 tests ask *whether it fits*. Scrolling was the alternative and it is worse here, because
/// `find...last` on a not-yet-built widget throws `Bad state: No element` rather than failing an assertion.
const Size kTallViewport = Size(320, 2000);

/// The settings tree and its branches — four states each (Law U4, ARCH_5 §9.1).
void main() {
  group('the tree', () {
    testWidgets('groups every branch and declares no chrome of its own', (tester) async {
      await pumpSettings(
        tester,
        const SettingsScreen(),
        overrides: settingsOverrides(),
        wrapInShell: true,
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      // **By semantics label, not by text.** `SectionHeader` renders `label.toUpperCase()` and supplies the
      // original as `semanticsLabel` — so asserting the visible string would couple this test to a styling
      // choice, and asserting `'YOUR MONEY'` would break the day that choice changes.
      expect(find.bySemanticsLabel('Your money'), findsOneWidget);
      expect(find.bySemanticsLabel('Your things'), findsOneWidget);
      expect(find.bySemanticsLabel('The app'), findsOneWidget);
      // Exactly one Scaffold — the harness's stand-in for the drawer shell — and no AppBar, because `/settings`
      // is a shell destination and a bar declared here would be a second one inside it (Law U18).
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('search matches a keyword, not only a title', (tester) async {
      await pumpSettings(
        tester,
        const SettingsScreen(),
        overrides: settingsOverrides(),
        wrapInShell: true,
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'dark');
      await tester.pumpAndSettle();
      // Nothing in the app is called "dark", which is the whole point: a tree matching only headings would answer
      // "no results" for a setting sitting right there.
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Accounts'), findsNothing);
    });

    testWidgets('a query matching nothing names the search, not the tree', (tester) async {
      await pumpSettings(
        tester,
        const SettingsScreen(),
        overrides: settingsOverrides(),
        wrapInShell: true,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.textContaining('Nothing matches'), findsOneWidget);
    });

    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpSettings(
        tester,
        const SettingsScreen(),
        overrides: settingsOverrides(),
        wrapInShell: true,
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('accounts', () {
    testWidgets('loading is a skeleton, not a spinner', (tester) async {
      await pumpSettings(
        tester,
        const AccountsSettingsScreen(),
        overrides: settingsOverrides(accounts: const AsyncValue<List<Account>>.loading()),
      );
      expect(find.byType(AlayaListSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('error carries the repository message', (tester) async {
      await pumpSettings(
        tester,
        const AccountsSettingsScreen(),
        overrides: settingsOverrides(
          accounts: AsyncValue<List<Account>>.error(
            Exception('accounts table is locked'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ErrorState), findsOneWidget);
      // Never a generic body (Law U9).
      expect(find.textContaining('accounts table is locked'), findsOneWidget);
    });

    testWidgets('empty names the next action', (tester) async {
      await pumpSettings(
        tester,
        const AccountsSettingsScreen(),
        overrides: settingsOverrides(accounts: const AsyncValue.data(<Account>[])),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Add an account'), findsWidgets);
    });

    testWidgets('archived accounts are grouped, not hidden', (tester) async {
      await pumpSettings(
        tester,
        const AccountsSettingsScreen(),
        overrides: settingsOverrides(
          accounts: AsyncValue.data([
            account(),
            account(id: 'ac-2', name: 'Old wallet', isArchived: true),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      // This screen is the only way to reach an archived account and restore it, so hiding them here would make
      // one unreachable — and an account nobody can find is one they recreate by hand.
      expect(find.text('Archived'), findsWidgets);
      expect(find.text('Old wallet'), findsOneWidget);
    });

    testWidgets('an excluded account says so on the row', (tester) async {
      await pumpSettings(
        tester,
        const AccountsSettingsScreen(),
        overrides: settingsOverrides(
          accounts: AsyncValue.data([account(includeInNetWorth: false)]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not in net worth'), findsOneWidget);
    });
  });

  group('tags — the scoping matrix', () {
    testWidgets('every row states where the tag is offered', (tester) async {
      await pumpSettings(
        tester,
        const TagsSettingsScreen(),
        overrides: settingsOverrides(
          tags: AsyncValue.data([tag(scopes: {TagScope.inventory, TagScope.shopping})]),
        ),
      );
      await tester.pumpAndSettle();
      // A scope only visible after opening the editor is one nobody notices is wrong.
      expect(find.text('Items'), findsOneWidget);
      expect(find.text('Shopping lists'), findsOneWidget);
      expect(find.text('Money in'), findsNothing);
    });

    testWidgets('a tag scoped nowhere is called out', (tester) async {
      await pumpSettings(
        tester,
        const TagsSettingsScreen(),
        overrides: settingsOverrides(tags: AsyncValue.data([tag(scopes: const {})])),
      );
      await tester.pumpAndSettle();
      // It cannot appear anywhere in the app, which makes it invisible everywhere except this screen — exactly
      // the dead row somebody would hunt for in the pickers first.
      expect(find.textContaining('not offered anywhere'), findsOneWidget);
    });

    testWidgets('a child is grouped under its parent, one level deep', (tester) async {
      await pumpSettings(
        tester,
        const TagsSettingsScreen(),
        overrides: settingsOverrides(
          tags: AsyncValue.data([
            tag(),
            tag(id: 'tg-2', name: 'Fridge', parentTagId: 'tg-1'),
            // A grandchild, which must surface under the top-most ancestor rather than vanish.
            tag(id: 'tg-3', name: 'Freezer', parentTagId: 'tg-2'),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kitchen'), findsOneWidget);
      expect(find.text('Fridge'), findsOneWidget);
      expect(find.text('Freezer'), findsOneWidget);
    });

    testWidgets('a parent cycle does not hang the screen', (tester) async {
      await pumpSettings(
        tester,
        const TagsSettingsScreen(),
        overrides: settingsOverrides(
          tags: AsyncValue.data([
            tag(id: 'a', name: 'A', parentTagId: 'b'),
            tag(id: 'b', name: 'B', parentTagId: 'a'),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      // The root walk is bounded by the tag count. A cycle should be impossible, and a UI that trusts that is a
      // UI that freezes when it turns out not to be.
      expect(tester.takeException(), isNull);
    });
  });

  group('units', () {
    testWidgets('a row states what the unit equals, never its stored factor', (tester) async {
      await pumpSettings(
        tester,
        const UnitsSettingsScreen(),
        overrides: settingsOverrides(units: AsyncValue.data([unit()])),
      );
      await tester.pumpAndSettle();
      // 1,000,000 is the stored value and useless to read. `1 kg = 1,000 g` is the figure — and dividing by
      // `milliPerBaseUnit` rather than by 1,000 is the whole of ARCH_4 R18.
      expect(find.textContaining('1,000'), findsOneWidget);
      expect(find.textContaining('1,000,000'), findsNothing);
    });

    testWidgets('the fixed-categories rule is stated before anybody adds one', (tester) async {
      await pumpSettings(
        tester,
        const UnitsSettingsScreen(),
        overrides: settingsOverrides(units: AsyncValue.data([unit()])),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('only three kinds'), findsOneWidget);
    });
  });

  group('currencies', () {
    testWidgets('the home currency cannot be switched off', (tester) async {
      await pumpSettings(
        tester,
        const CurrenciesSettingsScreen(),
        overrides: settingsOverrides(
          currencies: AsyncValue.data([currency(), currency(code: 'JPY', isEnabled: false)]),
        ),
      );
      await tester.pumpAndSettle();

      final tiles = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
      // Disabled rather than hidden, so it reads as an explanation and not a rendering fault (ARCH_5 §10).
      expect(tiles.first.onChanged, isNull);
      expect(tiles.last.onChanged, isNotNull);
      expect(find.textContaining('Cannot be turned off'), findsOneWidget);
    });
  });

  group('security', () {
    testWidgets('the honest paragraph is on the screen, above the switches', (tester) async {
      await pumpSettings(
        tester,
        const SecuritySettingsScreen(),
        overrides: settingsOverrides(lock: FakeAppLock(enabled: true)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('does not encrypt your data'), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsNothing);
    });

    testWidgets('auto-erase is off by default and names the threshold', (tester) async {
      await pumpSettings(
        tester,
        const SecuritySettingsScreen(),
        overrides: settingsOverrides(lock: FakeAppLock(enabled: true)),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
      // An unset key reads as false, which is what "default off" has to mean for a feature that destroys data.
      expect(switches.every((tile) => tile.value == false), isTrue);
      expect(find.textContaining('10 wrong PIN attempts'), findsOneWidget);
    });

    testWidgets('neither PIN branch is guessed while storage answers', (tester) async {
      await pumpSettings(
        tester,
        const SecuritySettingsScreen(),
        // **The provider is overridden to a future that never completes.** `FakeAppLock.isEnabled` is an
        // `async` getter, so it resolves within the first frame's microtask drain and the loading branch is
        // never observable — the test would have passed against a screen that had no loading branch at all.
        overrides: [
          ...settingsOverrides(lock: FakeAppLock(enabled: true)),
          lockConfiguredProvider.overrideWith((ref) => pendingFuture<bool>()),
        ],
      );
      expect(find.text('Checking…'), findsOneWidget);
      // A row saying "no PIN set" for one frame to somebody who has one would be alarming for the wrong reason.
      expect(find.text('Set a PIN'), findsNothing);
    });
  });
}
```

## `layout_overflow_test.dart`

Carried whole and extended by 154 lines. Law U2 requires every new sheet and full-height state be added **in the
phase that creates them**, and 8A creates two sheets — `PaymentMethodSheet` and `PayeeSheet` — plus the lock
screen, PIN setup, recovery and the settings empties.

Three of the seven new cases are chosen for being the worst case rather than the typical one: the keypad **with**
its biometric key (four keys on the bottom row, the widest the pad ever gets), the honest-copy paragraph (the
longest string in the app, in the narrowest column, at the largest scale U15 asks for), and the scoping matrix
(six switches each with a subtitle — the tallest form in the phase).

A defect caught in the writing: the honest-copy case had `phone\'s` inside a single-quoted Dart string, which the
generator had emitted as a doubled backslash — terminating the string early. Replaced with a curly apostrophe,
which needs no escaping and is what the ARB string itself uses.

### `test/shared/layout_overflow_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_bar_chart.dart';
import 'package:alaya/features/lock/presentation/widgets/pin_pad.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_donut_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/slice_bar_list.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/sheets/delete_transaction_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/freeze_conversion_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_filter_sheet.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/features/service/presentation/sheets/dispose_sheet.dart';
import 'package:alaya/features/service/presentation/widgets/contact_action.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/shopping/presentation/sheets/entry_editor_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/generate_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/list_manager_sheet.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_expandable_fab.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/loading_state.dart';
import 'package:alaya/shared/widgets/module_tile.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

import '../support/calendar_harness.dart' as cal;
import '../support/expense_harness.dart';
import '../support/fake_settings_repository.dart';

/// The only thing in this project that catches a layout overflow (ARCH_3 §8.3, ARCH_5 U2).
///
/// **Every sheet and every full-height state belongs here.** These defects are invisible to
/// `dart analyze`, to a file-by-file scan and to looking at the screen, because the missing
/// affordance is always an *ancestor*: the widget under review is locally correct and the parent
/// that should have given it room, or a way to scroll, is the one at fault.
///
/// They are also invisible to an ordinary widget test. A `RenderFlex` overflow reports through
/// `FlutterError.onError` rather than throwing at the site, so a test only fails on one if something
/// asks — which is exactly how an overflow hides in a suite that otherwise looks green. Every case
/// below asks, via `tester.takeException()`.
void main() {
  /// Roughly what a software keyboard takes from a phone in portrait.
  const double keyboardInset = 320;

  /// Roughly the room a list area has left on a small phone with a keyboard up.
  const Size squeezed = Size(320, 140);

  Widget host(
    Widget child, {
    double bottomInset = 0,
    double textScale = 1,
    List<Override> overrides = const [],
  }) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AlayaTheme.light(AlayaPresets.activePreset),
          // Every expense sheet reads `AlayaStrings.of(context)`, which unwraps a null without a
          // delegate installed. The Phase 5 groups pass literal strings, so this file went without
          // one until real screens arrived — and then failed as a null-check rather than as a
          // missing translation, which is why it read like five separate defects.
          localizationsDelegates: const [
            AlayaStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AlayaStrings.supportedLocales,
          // Inside the app rather than above it. `WidgetsApp` re-establishes `MediaQuery` from the
          // view, so an outer one is discarded before anything under test can read it — and a test
          // that believes it has simulated a keyboard when it has not is worse than no test.
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: EdgeInsets.only(bottom: bottomInset),
              textScaler: TextScaler.linear(textScale),
            ),
            child: inner!,
          ),
          home: Scaffold(body: child),
        ),
      );

  /// Content taller than the room a keyboard leaves, so the assertions are about the scaffold rather
  /// than about how long a particular string happens to be.
  Widget tallContent() => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [SizedBox(width: 200, height: 400)],
      );

  group('AlayaBottomSheet', () {
    testWidgets('scrolls rather than overflowing with a keyboard up', (tester) async {
      await tester.pumpWidget(
        host(AlayaBottomSheet(child: tallContent()), bottomInset: keyboardInset),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('still fits when there is no keyboard', (tester) async {
      await tester.pumpWidget(host(AlayaBottomSheet(child: tallContent())));
      expect(tester.takeException(), isNull);
    });

    // The bug, reproduced deliberately. `Padding(bottom: viewInsets)` around a `MainAxisSize.min`
    // Column is correct in each half and broken together: the padding shrinks the space and the
    // Column has no way to give up the room it already took. **If this ever stops overflowing, the
    // guard above has stopped testing anything** — and the reason AlayaBottomSheet exists has
    // quietly gone away.
    testWidgets('the un-scaffolded shape it replaces still overflows', (tester) async {
      await tester.pumpWidget(
        host(
          Padding(
            padding: const EdgeInsets.only(bottom: keyboardInset),
            child: tallContent(),
          ),
        ),
      );
      expect(tester.takeException(), isA<FlutterError>());
    });
  });

  group('ConfirmSheet', () {
    testWidgets('survives a keyboard and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => ConfirmSheet.show(
                context,
                title: 'Delete this transaction?',
                body: 'You can undo this for the next few seconds.',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                destructive: true,
              ),
              child: const Text('open'),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('AlayaFormScaffold', () {
    Widget form({bool submitting = false}) => AlayaFormScaffold(
          primaryLabel: 'Save expense',
          onPrimary: () {},
          secondaryLabel: 'Cancel',
          onSecondary: () {},
          isDirty: true,
          isSubmitting: submitting,
          discardTitle: 'Discard your changes?',
          discardBody: 'What you have typed will not be saved.',
          discardConfirmLabel: 'Discard',
          discardCancelLabel: 'Keep editing',
          child: const Column(
            children: [SizedBox(height: 300), TextField(), SizedBox(height: 300)],
          ),
        );

    testWidgets('body scrolls and the footer stays above the keyboard', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset));
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a doubled text scale with a keyboard up', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset, textScale: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the submitting footer does not grow the row past its box', (tester) async {
      await tester.pumpWidget(host(form(submitting: true), textScale: 2));
      expect(tester.takeException(), isNull);
    });
  });

  // Every sheet Phase 6A adds, at a keyboard inset and a doubled text scale — the two conditions
  // under which each of them is first used and least likely to have been looked at.
  group('expense sheets', () {
    final expenseOverrides = <Override>[
      homeCurrencyCodeProvider.overrideWith((ref) => 'INR'),
      homeDecimalDigitsProvider.overrideWith((ref) => 2),
      selectableAccountsProvider.overrideWith((ref) => Stream.value(const [kAccount])),
      quickAddTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      accountsByIdProvider
          .overrideWith((ref) => Stream.value(<String, Account>{kAccount.id: kAccount})),
      lineEditorItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      enabledCurrenciesProvider.overrideWith(
        (ref) => Stream.value(const [
          Currency(
            code: 'USD',
            name: 'US Dollar',
            symbol: r'$',
            decimalDigits: 2,
            isEnabled: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: expenseOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets('QuickAddSheet', (tester) => pumpSheet(tester, const QuickAddSheet()));

    testWidgets(
      'TransactionFilterSheet',
      (tester) => pumpSheet(tester, const TransactionFilterSheet()),
    );

    testWidgets(
      'LineItemEditor',
      (tester) => pumpSheet(
        tester,
        const LineItemEditor(
          currencyCode: 'INR',
          decimalDigits: 2,
          defaultDestination: TransactionLineDestination.inventory,
        ),
      ),
    );

    testWidgets(
      'DeleteTransactionSheet',
      (tester) => pumpSheet(tester, const DeleteTransactionSheet()),
    );

    testWidgets(
      'FreezeConversionSheet',
      (tester) => pumpSheet(tester, const FreezeConversionSheet(excludeCode: 'INR')),
    );
  });

  // Phase 6B's sheet, at a keyboard inset and a doubled text scale — the two conditions under
  // which it is first used and least likely to have been looked at (U2).
  group('inventory sheets', () {
    final inventoryOverrides = <Override>[
      consumeFefoProvider('item-1').overrideWith((ref) => Stream.value(const <Batch>[])),
      unitsInCategoryProvider(UnitCategory.weight).overrideWith(
        (ref) => Stream.value(const [
          Unit(
            code: 'kg',
            category: UnitCategory.weight,
            factorToBaseMilli: 1000000,
            displayName: 'kilogram',
            isSystem: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    testWidgets('ConsumeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: ConsumeSheet(
              itemId: 'item-1',
              unitCode: 'kg',
              category: UnitCategory.weight,
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: inventoryOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6C's three sheets, at a keyboard inset and a doubled text scale — the two conditions under
  // which each is first used and least likely to have been looked at (U2).
  group('shopping sheets', () {
    final shoppingOverrides = <Override>[
      entryItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      entryTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      entryCurrencyProvider.overrideWith((ref) async => 'INR'),
      entryDecimalDigitsProvider.overrideWith((ref) async => 2),
      entriesProvider('list-1').overrideWith((ref) => Stream.value(const <ShoppingEntry>[])),
      shoppingItemsByIdProvider.overrideWith((ref) => Stream.value(const <String, Item>{})),
      allListsProvider.overrideWith((ref) => Stream.value(const <ShoppingList>[])),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: shoppingOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets(
      'EntryEditorSheet',
      (tester) => pumpSheet(tester, const EntryEditorSheet(listId: 'list-1')),
    );

    testWidgets(
      'GenerateSheet',
      (tester) => pumpSheet(tester, const GenerateSheet(listId: 'list-1')),
    );

    testWidgets(
      'ListManagerSheet',
      (tester) => pumpSheet(tester, const ListManagerSheet()),
    );
  });

  // Phase 6D's pay sheet, at a keyboard inset and a doubled text scale — an amount field, a date
  // field, an account dropdown and a two-line note, all growing at once.
  group('recurring sheets', () {
    final recurringOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      payAccountsProvider.overrideWith((ref) => Stream.value(const <Account>[])),
      payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
    ];

    testWidgets('PaySheet', (tester) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(
            child: PaySheet(
              occurrenceId: 'occ-1',
              template: RecurringTemplate(
                id: 'tpl-1',
                name: 'A rent template with a name long enough to wrap at a doubled scale',
                normalizedName: 'rent',
                kind: RecurringKind.rent,
                direction: RecurringDirection.outflow,
                defaultAmount: const Money(120000, 'INR'),
                intervalUnit: RecurringIntervalUnit.month,
                intervalCount: 1,
                startDateKey: const DateKey(20260131),
                nextDueDateKey: const DateKey(20260831),
                isPaused: false,
                autoRemind: true,
                remindDaysBefore: 3,
                anchorDayOfMonth: 31,
              ),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: recurringOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6D adds, with a clamp note on every row.
  group('FrequencyPreview at a doubled text scale', () {
    testWidgets('three dates, two of them clamped', (tester) async {
      await tester.pumpWidget(
        host(
          const FrequencyPreview(
            dates: [
              PreviewedDate(dateKey: DateKey(20260131)),
              PreviewedDate(dateKey: DateKey(20260228), clamped: true),
              PreviewedDate(dateKey: DateKey(20260331)),
            ],
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6E's dispose sheet: seven choice chips, a date field, an optional amount and a note, all
  // growing at once under a keyboard inset.
  group('service sheets', () {
    final serviceOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('DisposeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: DisposeSheet(assetId: 'asset-1', currencyCode: 'INR'),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: serviceOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The contact block: a name, a number and a call button, none of them flexible.
  group('ContactAction at a doubled text scale', () {
    testWidgets('a long name beside a long number', (tester) async {
      await tester.pumpWidget(
        host(
          const ContactAction(
            phone: '+91 98765 43210',
            name: 'A service centre with a name long enough to wrap',
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6F's dashboard sections. Each is a card whose figures, chips and labels all grow at once, and
  // the funds header carries the only display-sized amount in the app.
  group('dashboard sections', () {
    final dashOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      // InsightCard's notifier restores its side from `app_settings` on the first frame, which
      // resolves `databaseProvider` unless this is here — the failure reads as a database bug in a
      // test that never mentions one (ARCH_6 P6).
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      dashboardCurrencyProvider.overrideWith((ref) async => 'INR'),
      dashboardDigitsProvider.overrideWith((ref) async => 2),
      totalFundsProvider.overrideWith(
        (ref) async => const NetWorth(
          total: Money(98765432, 'INR'),
          unconvertedCount: 3,
          isApproximate: true,
        ),
      ),
      upcomingProvider.overrideWith((ref) async => const <UpcomingEntry>[]),
    ];

    testWidgets('FundsHeader with both chips at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const FundsHeader(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('InsightCard with its switch at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const InsightCard(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6F adds. Two lines of text and a glyph inside a fixed aspect ratio is
  // exactly the shape that overflows when the text doubles and the box does not.
  group('ModuleTile at a doubled text scale', () {
    testWidgets('a long label beside a long count', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 160,
            height: 108,
            child: ModuleTile(
              label: 'Recurring commitments',
              icon: Icons.event_repeat,
              detail: '17 need attention before the end of the month',
              onTap: () {},
            ),
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 7A. Both shapes here are the ones that have already cost this project rounds: a sheet whose
  // content outgrows the viewport, and a grid of text cells whose row height does not move with the text.
  // Zero width, which is not a hypothetical: Android reports it on the first frame of every launch
  // ("D/FlutterRenderer: Width is zero. 0,0") and the FAB's slot subtracted padding from it, producing a
  // negative width and a red screen on startup. Every widget harness sets a real viewport before pumping,
  // which is exactly why nothing here caught it — so the degenerate viewport is now stated outright.
  group('degenerate viewports', () {
    testWidgets('the expandable FAB survives a zero-width first frame', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size.zero),
            child: Scaffold(
              floatingActionButton: AlayaExpandableFab(
                openLabel: 'Add',
                closeLabel: 'Close',
                actions: [
                  FabAction(label: 'One', icon: Icons.add, onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('calendar', () {
    List<Override> calOverrides({List<CalendarEvent> events = const []}) =>
        cal.calendarOverrides(cal.FakeCalendarRepository(events: events));

    final busyDay = <CalendarEvent>[
      cal.event(title: 'A payee with a name long enough to wrap at a doubled scale', amountMinor: 98765432),
      cal.event(
        type: CalendarEventType.serviceDue,
        refType: 'asset',
        refId: 'as-1',
        title: 'The boiler in the upstairs cupboard',
        baseSeverity: CalendarSeverity.warning,
      ),
      cal.event(
        type: CalendarEventType.batchExpiry,
        refType: 'inventoryBatch',
        refId: 'ba-1',
        title: 'Yoghurt, the large tub',
        baseSeverity: CalendarSeverity.warning,
      ),
    ];

    testWidgets('DaySheet with three grouped entries at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('DaySheet with a keyboard up as well', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // U26: `TableCalendar` takes a fixed `rowHeight`, so the grid computes one from the text scaler. If
    // that computation is ever replaced by a constant, this is the test that says so.
    testWidgets('the month grid at a doubled scale on the narrowest phone', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the month grid at a tripled scale, which is past what U15 asks for',
        (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 3, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // The range header prints two formatted dates and a dash, which is the longest single string this
    // screen can produce — and it appears only in a mode the other cases never enter.
    testWidgets('the range header at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('22'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // The screen's own composition, which the shared full-height group cannot reach: six measured rows
    // plus a header are taller than a squeezed list area on their own, so the grid and the state beneath
    // it have to share a scroll rather than compete for a fixed box.
    for (final scale in [1.0, 2.0]) {
      testWidgets('the whole screen in a squeezed viewport at ${scale}x', (tester) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: scale,
            overrides: calOverrides(events: busyDay),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // Each of the three states in turn, in the same squeezed box. Loading and error sit in the sliver
    // that fills the remainder, and that remainder is negative here.
    testWidgets('loading, empty and error all survive the squeezed box', (tester) async {
      for (final repo in [
        cal.FakeCalendarRepository(pending: true),
        cal.FakeCalendarRepository(),
        cal.FakeCalendarRepository(error: 'view unavailable'),
      ]) {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: 2,
            overrides: cal.calendarOverrides(repo),
          ),
        );
        // `pump`, not `pumpAndSettle`: the loading case holds a `CircularProgressIndicator`, which
        // animates forever, so `pumpAndSettle` times out rather than settling. Two frames is enough to
        // resolve the completed futures in the other two cases.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('full-height states in a squeezed viewport', () {
    Widget inSqueezedBox(Widget child) => host(
          Center(
            child: SizedBox(width: squeezed.width, height: squeezed.height, child: child),
          ),
        );

    testWidgets('EmptyState with an icon, body and action', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          EmptyState(
            title: 'No transactions yet',
            body: 'Add your first expense and it will appear here.',
            icon: Icons.receipt_long_outlined,
            actionLabel: 'Add expense',
            onAction: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ErrorState with a retry — the tallest of the three', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          ErrorState(
            title: 'That did not work',
            body: 'Something went wrong on our side. Try again.',
            retryLabel: 'Try again',
            onRetry: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoadingState', (tester) async {
      await tester.pumpWidget(inSqueezedBox(const LoadingState(label: 'Loading')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('AlayaListSkeleton clips rather than overflowing', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(const AlayaListSkeleton(label: 'Loading transactions')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmptyState at a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: EmptyState(
                title: 'No transactions yet',
                body: 'Add your first expense and it will appear here.',
                icon: Icons.receipt_long_outlined,
                actionLabel: 'Add expense',
                onAction: () {},
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    // The states are also the shape the Theme Lab renders inside a half-width pane, which is where
    // the 150px `SizedBox` around an EmptyState used to overflow by roughly 58px.
    testWidgets('EmptyState in a half-width pane', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          const SizedBox(
            width: 134,
            child: EmptyState(title: 'No matches', body: 'Try a shorter search.'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6A's line-items page: a full-height screen whose summary row, list rows and footer all
  // grow under text scale at once. Squeezed and doubled, which is the pair U21 exists for.
  group('the line items page', () {
    final editorOverrides = <Override>[
      transactionEditorProvider.overrideWith(
        () => _FixedEditor(
          AsyncValue.data(
            TransactionEditorState(
              currencyCode: 'INR',
              dateKey: const DateKey(20260801),
              amount: const Money(20000, 'INR'),
              lines: [
                TransactionLine(
                  id: 'l1',
                  transactionId: '',
                  lineNo: 1,
                  description: 'A description long enough to need two lines at a doubled scale',
                  destination: TransactionLineDestination.inventory,
                  quantity: const Qty(500000, UnitCategory.weight),
                  lineAmount: const Money(4000, 'INR'),
                ),
              ],
            ),
          ),
        ),
      ),
      homeDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('populated at 320dp and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(const LineItemsScreen(), textScale: 2, overrides: editorOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('kit rows at a doubled text scale', () {
    testWidgets('KeyValueRow wraps a long value instead of overflowing', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            child: KeyValueRow(
              label: 'Payment method',
              value: 'Bank transfer from HDFC Savings ending 4417',
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('FilterChipBar wraps rather than clipping a row of chips', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: FilterChipBar(
              clearAllLabel: 'Clear all',
              onClearAll: () {},
              filters: [
                ActiveFilter(label: 'Account: HDFC Savings', onRemove: () {}),
                ActiveFilter(label: 'Tag: Groceries', onRemove: () {}),
                ActiveFilter(label: 'Jan 2026 – Aug 2026', onRemove: () {}),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('StatusChip ellipsises a long label in a narrow box', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 96,
            child: StatusChip(label: 'Needs details', tone: StatusTone.info),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── Phase 7B ──────────────────────────────────────────────────────────────────────────
  //
  // **No sheets, so no sheet cases.** 7B adds no `AlayaBottomSheet`: the tag drill happens in place
  // inside its card and the clear-cache action is a row, so there is nothing here for U2's sheet
  // clause to cover. What it does add is one shared widget, two chart surfaces and four full-height
  // states, and those are below.
  group('analytics surfaces', () {
    // **Wrapped in a scroll view, because that is the only place a `ChartCard` ever lives** — the
    // analytics screen puts every card in a `SliverList`. Handed a tight viewport height instead, its
    // `Column` has nowhere to go and reports an overflow the real screen cannot produce. What these
    // cases are for is the *horizontal* axis: a header that starves, a chip row that will not wrap, a
    // plot box that outgrows its card.
    Widget card({
      Widget? trailing,
      Widget child = const Text('body'),
      AsyncValue<int> value = const AsyncValue.data(1),
    }) =>
        SingleChildScrollView(
            child: ChartCard<int>(
          title: 'Price per kilogram across every purchase this year',
          subtitle: 'What one thing costs you, purchase by purchase',
          value: value,
          isEmpty: (data) => data == 0,
          emptyMessage: 'Nothing yet',
          onRetry: () {},
          approximateCount: 3,
          unconvertedCount: 2,
          trailing: trailing,
          builder: (context, data) => child,
        ));

    testWidgets('ChartCard stacks its header above 1.5x rather than clipping the figure',
        (tester) async {
      // The `trailing` slot is an `AmountText`, which clips rather than ellipsises — so a clipped
      // figure is a wrong figure and the header has to stack instead of sharing a row (Law U21).
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              trailing: const AmountText(
                Money(123456789, 'INR'),
                size: AmountSize.small,
                showSign: false,
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChartCard keeps both quality chips at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(SizedBox(width: 320, child: card()), textScale: 2),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChartCard renders its error branch in a narrow box', (tester) async {
      // The inline failure, not `ErrorState`: that one is a full-height state with a 40px glyph and
      // its own `ScrollSafeCenter`, which inside a card would push every sibling off the screen.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              value: AsyncValue<int>.error(
                Exception('No rate for JPY on 2026-08-10, and none earlier'),
                StackTrace.empty,
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a plot area grows with the text scaler and stays inside its card',
        (tester) async {
      // `AnalyticsPlotBox` scales from the text scaler and clamps (Laws U26, U28's clamping lesson).
      // Unclamped, a tripled scale would produce a card taller than the viewport — and the box sizes
      // only the plot, so the card's own title and subtitle grow beside it rather than being squeezed
      // into the plot's height.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: const AnalyticsPlotBox(
                child: AnalyticsLineChart(
                  series: [
                    AnalyticsSeries(
                      tone: AnalyticsSeriesTone.expense,
                      points: [
                        AnalyticsPoint(x: 0, value: 100000, axisLabel: 'Jan'),
                        AnalyticsPoint(x: 1, value: 90000),
                        AnalyticsPoint(x: 2, value: 140000, axisLabel: 'Aug'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a flat series does not collapse its own plot band', (tester) async {
      // Every point equal makes `maxY - minY` zero, which fl_chart divides by. The chart widens the
      // band by one minor unit rather than handing it a zero.
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            height: 120,
            child: AnalyticsLineChart(
              series: [
                AnalyticsSeries(
                  tone: AnalyticsSeriesTone.neutral,
                  points: [
                    AnalyticsPoint(x: 0, value: 5000),
                    AnalyticsPoint(x: 1, value: 5000),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bar chart of thirty-one buckets survives a doubled scale at 320dp',
        (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            height: 160,
            child: AnalyticsBarChart(
              labelEvery: 5,
              buckets: [
                for (var day = 1; day <= 31; day++)
                  AnalyticsBucket(bucket: day, value: day * 1000, label: '$day'),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an all-zero bar chart still draws its axis', (tester) async {
      // A window where nothing was spent must show that the buckets exist and are empty, rather than
      // dividing by a zero maximum.
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            height: 160,
            child: AnalyticsBarChart(
              buckets: [
                AnalyticsBucket(bucket: 1, value: 0, label: 'M'),
                AnalyticsBucket(bucket: 7, value: 0, label: 'S'),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a donut stays a ring at a tripled scale', (tester) async {
      // `AnalyticsDonutChart` sizes its radius from the box's shorter side, so a taller box at a raised
      // scale must not produce a cropped ellipse — and the centre text has to fit the hole.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: Builder(
                builder: (context) => AnalyticsDonutChart(
                  slices: analyticsSlices(
                    context,
                    const [
                      (label: 'Groceries', value: 400000, key: 'grocery'),
                      (label: 'Household', value: 220000, key: 'household'),
                      (label: 'Bills', value: 180000, key: 'bill'),
                    ],
                    otherLabel: 'Everything else',
                    remainder: 90000,
                  ),
                  centreTop: '85%',
                  centreBottom: 'in three kinds',
                ),
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a donut groups its tail rather than drawing twelve slivers', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: Builder(
                builder: (context) {
                  final slices = analyticsSlices(
                    context,
                    [
                      for (var i = 0; i < 12; i++)
                        (label: 'Kind $i', value: 12000 - i * 500, key: 'k$i'),
                    ],
                    otherLabel: 'Everything else',
                  );
                  // Six wedges plus one remainder, whatever it was handed.
                  expect(slices, hasLength(7));
                  return AnalyticsDonutChart(slices: slices);
                },
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an all-zero donut renders nothing rather than dividing by zero',
        (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: Builder(
                builder: (context) {
                  final slices = analyticsSlices(
                    context,
                    const [(label: 'Groceries', value: 0, key: 'grocery')],
                    otherLabel: 'Everything else',
                  );
                  expect(slices, isEmpty);
                  return AnalyticsDonutChart(slices: slices);
                },
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a swatched list without bars stacks above 1.5x', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: SliceBarList(
              showBars: false,
              slices: [
                SliceBar(
                  label: 'Between my accounts and everywhere else',
                  value: const AmountText(
                    Money(98765432, 'INR'),
                    size: AmountSize.small,
                    showSign: false,
                  ),
                  share: 0.8,
                  detail: '34%',
                  swatch: const Color(0xFF3F51B5),
                  onTap: () {},
                ),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('SliceBarList stacks its rows above 1.5x', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: SliceBarList(
              slices: [
                SliceBar(
                  label: 'Between my accounts and everywhere else',
                  value: const AmountText(
                    Money(98765432, 'INR'),
                    size: AmountSize.small,
                    showSign: false,
                  ),
                  share: 1,
                  detail: '12 purchases',
                  onTap: () {},
                ),
                SliceBar(
                  label: 'Household',
                  value: const QtyText(Qty(4450000, UnitCategory.weight)),
                  share: 0.4,
                ),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a share above one does not assert', (tester) async {
      // `share` is a ratio of two sums, so a rounding artefact can exceed one and
      // `FractionallySizedBox` asserts on a factor greater than one. It is clamped.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: SliceBarList(
              slices: [
                SliceBar(
                  label: 'Groceries',
                  value: const Text('x'),
                  share: 1.0000001,
                ),
                SliceBar(label: 'Bills', value: const Text('y'), share: double.nan),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('analytics full-height states in a squeezed viewport', () {
    Future<void> pumpSqueezed(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        host(Center(child: SizedBox.fromSize(size: squeezed, child: child))),
      );
    }

    testWidgets('the drill-down skeleton clips rather than overflowing', (tester) async {
      await pumpSqueezed(tester, const AlayaListSkeleton(label: 'Loading these transactions…'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the drill-down empty state scrolls instead of overflowing', (tester) async {
      await pumpSqueezed(
        tester,
        const EmptyState(
          title: 'Nothing here in this window',
          body: 'The window is set on the insights screen. Widen it and these may appear.',
          icon: Icons.filter_alt_outlined,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the screen-level empty state scrolls with its action', (tester) async {
      // The tallest of the three: icon, two text blocks and a 48dp button (ARCH_5 §4.1).
      await pumpSqueezed(
        tester,
        EmptyState(
          title: 'Nothing to show for this window',
          body: 'Widen the window above, or record something and it will appear here.',
          icon: Icons.insights_outlined,
          actionLabel: 'Add expense',
          onAction: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the drill-down error state survives with a retry', (tester) async {
      await pumpSqueezed(
        tester,
        ErrorState(
          title: 'Could not work that out',
          body: 'No rate for JPY on 2026-08-10, and none earlier',
          retryLabel: 'Try again',
          onRetry: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── Phase 8A ──────────────────────────────────────────────────────────────────────────
  //
  // Two sheets and five full-height states. `PaymentMethodSheet` and `PayeeSheet` are the phase's only
  // `AlayaBottomSheet` additions; the lock screen, PIN setup, recovery and the settings empties are its
  // full-height ones (Law U2 — added in the phase that creates them).
  group('settings and lock surfaces', () {
    testWidgets('a PIN keypad fits 320dp at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: PinKeypad(enabled: true, onDigit: _noDigit, onBackspace: _noop),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a keypad with the biometric key fits at a tripled scale', (tester) async {
      // Four keys on the bottom row rather than three, which is the widest the pad ever gets.
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: PinKeypad(
                enabled: true,
                onDigit: _noDigit,
                onBackspace: _noop,
                onBiometric: _noop,
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('six PIN dots fit the narrowest phone', (tester) async {
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(width: 320, child: PinDots(length: 6, filled: 3, dimmed: false)),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the honest-copy paragraph wraps rather than overflowing', (tester) async {
      // The longest string in the app, at the largest scale U15 asks for, in the narrowest column.
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: Text(
                'This PIN stops someone who picks up your unlocked phone from opening Alaya. '
                'It does not encrypt your data — anyone with access to the phone’s files can '
                'still read them.',
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a settings empty state scrolls in a squeezed viewport', (tester) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox.fromSize(
              size: squeezed,
              child: EmptyState(
                title: 'No accounts yet',
                body: 'Add one so Alaya knows where your money is.',
                icon: Icons.account_balance_wallet_outlined,
                actionLabel: 'Add an account',
                onAction: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the scoping matrix stacks at a doubled scale', (tester) async {
      // Six switches, each with a two-line subtitle — the tallest form in the phase.
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                children: [
                  for (var i = 0; i < 6; i++)
                    SwitchListTile(
                      value: i.isEven,
                      onChanged: (_) {},
                      title: const Text('Money out'),
                      subtitle: const Text('Offered when you record spending.'),
                    ),
                ],
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the varies panel fits its explanation and its offer', (tester) async {
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Then it is not a unit'),
                  const Text(
                    'A unit has to be the same amount every time. One packet of biscuits and one '
                    'packet of rice are different weights, so Alaya could not add two packets '
                    'together or work out what one cost.',
                  ),
                  FilledButton(onPressed: () {}, child: const Text('Create an item instead')),
                ],
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// A transaction editor reporting a fixed state, so a layout can be pumped without a database.
class _FixedEditor extends TransactionEditorNotifier {
  _FixedEditor(this._value);

  final AsyncValue<TransactionEditorState> _value;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _value;
}

/// A `ValueChanged<String>` that does nothing, so the keypad cases need no state.
void _noDigit(String _) {}

/// A `VoidCallback` that does nothing.
void _noop() {}
```

---

## First-build fixes

Ten root causes behind forty-six analyzer errors. Six were mine to find; four are worth calling out because they
are the kind that only a compiler catches.

**`TagScope` lives in `lib/core/enums/tag_scope.dart`, not `money_enums.dart`.** Four files imported the wrong
one. It is delivered by PHASE_02A, which is why grepping for the enum found it in a DAO document and I read that
as its home.

**`Clock.today()` is an extension, not an interface member.** `ClockDerived on Clock` supplies it, so
`core/time/clock.dart` has to be imported even where the type is never written — the one case where inference does
*not* let an import be omitted.

**`DatePickerField.formatted` is `String Function(DateKey)`, not `String`.** I had passed a formatted string, which
would have frozen the label at whatever date was there when the widget built. It is a formatter so the field can
render whichever date the picker lands on.

**`PaymentMethodKind` has seven members.** `bankTransfer` sits between `upi` and `card`, and my earlier `sed` range
cut it off. Both exhaustive switches now cover it — which is exactly what an exhaustive switch is for.

**`AlayaSemanticColors` has no `info`.** The tones are income, expense, transfer, warning, danger, success and
muted. The Security panel is explanatory rather than a state, so `muted` is right anyway (ARCH_5 §2.4).

**`pin_pad.dart` had `library;` after its imports** — invalid Dart — and never imported `AlayaStrings` despite the
keypad using it. Both artefacts of carving the widgets out of `lock_screen.dart`.

**`local_auth`'s signature could not be reconstructed, and the shortcut is disabled rather than weakened.**
Two attempts were rejected: `options: AuthenticationOptions(...)`, then `stickyAuth:`/`biometricOnly:` as direct
parameters. `authenticate` here accepts `localizedReason` and nothing else this file can identify.

Without `biometricOnly` the platform prompt may offer **device-credential fallback** — the phone's own PIN
satisfying Alaya's lock, which is exactly the threat ARCH_3 §2.5 says the lock exists for. So
`LocalAuthBiometricGate.shortcutEnabled` is `false`: the shortcut is optional in §2.2, `LockScreen` already omits
the key when unavailable (asserted in `lock_screen_test.dart`), and re-enabling it is one constant plus the
options the installed version turns out to accept. **A convenience is the right thing to lose to uncertainty; a
lock's guarantee is not.**

This is the ARCH_4 R22 exposure the file was written to contain, and containment worked — it cost one file and one
feature flag rather than the lock screen. `share_plus` is the same bet and this build has not exercised it.

**And three files I broke without carrying, which is the more serious kind of miss:**

`app.dart` lost its `flutter/material.dart` import to an off-by-one when I sliced it out of PHASE_05 — the line
above the one I started at. Every `Widget`, `BuildContext`, `ThemeMode` and `MaterialApp` error traced to that
single omission.

`theme_lab_screen.dart` set `activePaletteProvider.notifier.state` directly. Turning that provider into a
persisted `Notifier` for item 23 left the Theme Lab rethemeing the session while never writing to `app_settings`
— **the exact bug item 23 was about, moved one screen along.** It calls `use(next)` now.

`fake_settings_repository.dart` stopped satisfying `SettingsRepository` the moment I added
`writeHomeCurrencyCode` to it. Adding a contract member obliges every implementer, and the test fake is one.

### `lib/features/settings/presentation/theme_lab_screen.dart`

```dart
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/app.dart';
import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_elevation.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/loading_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Every token, component and semantic colour on one page, light and dark side by side (ARCH_3 §8.2).
///
/// **This is how palettes actually get chosen.** The alternative is navigating the real app hunting for
/// a screen that happens to use `warning`, discovering it only renders in one state, and guessing about
/// the rest. Everything enumerates from the token maps rather than a hand-written list, so a token
/// added later appears here without anyone remembering to add it.
///
/// Debug-only. In a release build it renders a single line saying so rather than the lab, which keeps
/// it out of the shipped UI without a conditional route that could be got wrong.
class ThemeLabScreen extends ConsumerWidget {
  /// Creates the lab.
  const ThemeLabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    if (!kDebugMode) {
      return Center(child: Text(strings.themeLabTitle));
    }

    final palette = ref.watch(activePaletteProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AlayaSpacing.screenEdge,
            AlayaSpacing.md,
            AlayaSpacing.screenEdge,
            0,
          ),
          child: Text(
            strings.themeLabSubtitle,
            style: AlayaTypography.body.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SectionHeader(label: strings.themeLabSectionPalettes),
        _PalettePicker(
          current: palette,
          // **Phase 8A: `use`, not `state =`.** `activePaletteProvider` became a persisted `Notifier` when
          // ARCH_4 §5.1 item 23 was closed, and assigning `state` directly would retheme this session while
          // never reaching `app_settings` — the exact bug item 23 was about, moved one screen along.
          onSelected: (next) => ref.read(activePaletteProvider.notifier).use(next),
        ),
        SectionHeader(label: strings.themeLabSectionSemantic),
        _SideBySide(palette: palette, builder: (context) => const _SemanticSwatches()),
        SectionHeader(label: strings.themeLabSectionSurfaces),
        _SideBySide(palette: palette, builder: (context) => const _SurfaceTiers()),
        SectionHeader(label: strings.themeLabSectionTypography),
        const _TypeScale(),
        SectionHeader(label: strings.themeLabSectionSpacing),
        const _SpacingScale(),
        SectionHeader(label: strings.themeLabSectionRadii),
        const _RadiiScale(),
        SectionHeader(label: strings.themeLabSectionElevation),
        _SideBySide(palette: palette, builder: (context) => const _ElevationScale()),
        SectionHeader(label: strings.themeLabSectionComponents),
        _SideBySide(palette: palette, builder: (context) => const _Components()),
      ],
    );
  }
}

/// Renders [builder] twice, in light and dark, so a palette is judged as a pair.
class _SideBySide extends StatelessWidget {
  const _SideBySide({required this.palette, required this.builder});

  final AlayaPalette palette;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Pane(
              label: strings.themeLabLight,
              theme: AlayaTheme.light(palette),
              child: builder(context),
            ),
          ),
          const SizedBox(width: AlayaSpacing.sm),
          Expanded(
            child: _Pane(
              label: strings.themeLabDark,
              theme: AlayaTheme.dark(palette),
              child: builder(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.label, required this.theme, required this.child});

  final String label;
  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AlayaTypography.overline),
          const SizedBox(height: AlayaSpacing.xxs),
          Theme(
            data: theme,
            child: Builder(
              builder: (context) => DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: AlayaRadii.borderSm,
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Padding(padding: const EdgeInsets.all(AlayaSpacing.sm), child: child),
              ),
            ),
          ),
        ],
      );
}

class _PalettePicker extends StatelessWidget {
  const _PalettePicker({required this.current, required this.onSelected});

  final AlayaPalette current;
  final ValueChanged<AlayaPalette> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final preset in AlayaPresets.all)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
                child: AlayaCard(
                  tier: preset.name == current.name ? 2 : 1,
                  border: preset.name == current.name,
                  onTap: () => onSelected(preset),
                  child: Row(
                    children: [
                      for (final swatch in [
                        preset.light.primary,
                        preset.light.accent,
                        preset.dark.surfaceBase,
                        preset.light.income,
                        preset.light.expense,
                      ]) ...[
                        _Swatch(color: swatch),
                        const SizedBox(width: AlayaSpacing.xxs),
                      ],
                      const SizedBox(width: AlayaSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(preset.name, style: AlayaTypography.cardTitle),
                            Text(preset.description, style: AlayaTypography.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: AlayaSpacing.lg,
        height: AlayaSpacing.lg,
        decoration: BoxDecoration(color: color, borderRadius: AlayaRadii.borderXs),
      );
}

class _SemanticSwatches extends StatelessWidget {
  const _SemanticSwatches();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in semantic.byName.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
            child: Row(
              children: [
                _Swatch(color: entry.value),
                const SizedBox(width: AlayaSpacing.xs),
                Expanded(child: Text(entry.key, style: AlayaTypography.caption)),
              ],
            ),
          ),
      ],
    );
  }
}

class _SurfaceTiers extends StatelessWidget {
  const _SurfaceTiers();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final tier in [-1, 0, 1, 2])
            Padding(
              padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
              child: AlayaCard(
                tier: tier,
                border: true,
                padding: const EdgeInsets.all(AlayaSpacing.xs),
                child: Text('tier $tier', style: AlayaTypography.caption),
              ),
            ),
        ],
      );
}

class _TypeScale extends StatelessWidget {
  const _TypeScale();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in AlayaTypography.all.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.key, style: AlayaTypography.overline),
                    // 1,234,567.89 rather than lorem: the figures are what the tabular treatment is
                    // for, and a pangram would hide the thing being judged.
                    Text('1,234,567.89 Alaya', style: entry.value),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _SpacingScale extends StatelessWidget {
  const _SpacingScale();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    const steps = {
      'xxs 4': AlayaSpacing.xxs,
      'xs 8': AlayaSpacing.xs,
      'sm 12': AlayaSpacing.sm,
      'md 16': AlayaSpacing.md,
      'lg 20': AlayaSpacing.lg,
      'xl 24': AlayaSpacing.xl,
      'xxl 32': AlayaSpacing.xxl,
      'xxxl 48': AlayaSpacing.xxxl,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in steps.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(entry.key, style: AlayaTypography.caption),
                  ),
                  Container(
                    width: entry.value,
                    height: AlayaSpacing.sm,
                    color: semantic.transfer,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RadiiScale extends StatelessWidget {
  const _RadiiScale();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    const steps = {
      'xs 4': AlayaRadii.xs,
      'sm 8': AlayaRadii.sm,
      'md 12': AlayaRadii.md,
      'lg 20': AlayaRadii.lg,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Row(
        children: [
          for (final entry in steps.entries)
            Padding(
              padding: const EdgeInsets.only(right: AlayaSpacing.xs),
              child: Column(
                children: [
                  Container(
                    width: AlayaSpacing.xxl,
                    height: AlayaSpacing.xxl,
                    decoration: BoxDecoration(
                      color: semantic.transfer,
                      borderRadius: BorderRadius.circular(entry.value),
                    ),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  Text(entry.key, style: AlayaTypography.overline),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ElevationScale extends StatelessWidget {
  const _ElevationScale();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadows = {
      'raised': AlayaElevation.raised(isDark: isDark),
      'floating': AlayaElevation.floating(isDark: isDark),
      'overlay': AlayaElevation.overlay(isDark: isDark),
    };
    return Column(
      children: [
        for (final entry in shadows.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.sm),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.semantic.surfaceRaised,
                borderRadius: AlayaRadii.borderMd,
                boxShadow: entry.value,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AlayaSpacing.xs),
                child: Text(entry.key, style: AlayaTypography.caption),
              ),
            ),
          ),
      ],
    );
  }
}

class _Components extends StatelessWidget {
  const _Components();

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final tag = Tag(
      id: 'demo',
      name: 'groceries',
      normalizedName: 'groceries',
      allowedScopes: const {TagScope.withdrawal},
      isSystem: false,
      sortOrder: 0,
      isDeleted: false,
      colorArgb: 0xFF2E7D5B,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AmountText(Money(-125050, 'INR'), size: AmountSize.large),
        const AmountText(Money(250000, 'INR')),
        const AmountText(
          Money(500000, 'INR'),
          kind: TransactionKind.transfer,
          size: AmountSize.small,
        ),
        const SizedBox(height: AlayaSpacing.xs),
        const QtyText(Qty(4450000, UnitCategory.weight)),
        const QtyText(Qty(3000, UnitCategory.count)),
        const SizedBox(height: AlayaSpacing.xs),
        Wrap(
          spacing: AlayaSpacing.xxs,
          children: [
            TagChip(tag: tag, onTap: () {}),
            TagChip(tag: tag, selected: true, onTap: () {}),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xs),
        FilledButton(onPressed: () {}, child: Text(strings.actionSave)),
        const SizedBox(height: AlayaSpacing.xxs),
        OutlinedButton(onPressed: () {}, child: Text(strings.actionCancel)),
        const SizedBox(height: AlayaSpacing.xxs),
        TextButton(onPressed: () {}, child: Text(strings.actionUndo)),
        const SizedBox(height: AlayaSpacing.xs),
        TextField(decoration: InputDecoration(labelText: strings.labelAmount)),
        const SizedBox(height: AlayaSpacing.xs),
        SizedBox(
          height: 150,
          child: EmptyState(
            title: strings.emptyTitleNoResults,
            body: strings.emptyBodyNoResults,
            icon: Icons.search_off_outlined,
          ),
        ),
        SizedBox(height: 120, child: LoadingState(label: strings.loadingLabel)),
        SizedBox(
          height: 170,
          child: ErrorState(
            title: strings.errorTitleGeneric,
            body: strings.errorBodyGeneric,
            retryLabel: strings.actionRetry,
            onRetry: () {},
          ),
        ),
        Text(
          '${AlayaDurations.fast.inMilliseconds} / ${AlayaDurations.base.inMilliseconds} / '
          '${AlayaDurations.slow.inMilliseconds} / ${AlayaDurations.page.inMilliseconds} ms',
          style: AlayaTypography.caption,
        ),
      ],
    );
  }
}
```

### `test/support/fake_settings_repository.dart`

```dart
/// An in-memory [SettingsRepository] for widget tests.
///
/// **Needed because a notifier may read settings during `build`.** `InsightSideNotifier.build` restores
/// the insight card's side from `app_settings`, so any scope that mounts the card and leaves
/// `settingsRepositoryProvider` un-overridden resolves `databaseProvider`, which throws by design
/// (Law L10). The symptom is a `StateError` about the database in a test that never mentions one, which
/// reads as a product bug and is not (ARCH_6 P6).
///
/// Kept in `test/support/` rather than inside one harness because two suites need it — the dashboard
/// harness and `layout_overflow_test.dart` — and a fake written twice is a fake that will disagree with
/// itself (ARCH_4 R25, one layer down).
library;

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';

/// Key/value settings held in a map, with writes readable back.
class FakeSettingsRepository implements SettingsRepository {
  /// Creates a store seeded with [values].
  ///
  /// [homeCurrencyCode] and [defaultAccountId] are separate rather than map entries so the fake does not
  /// have to know `SettingsKeys`' spelling — a test asserting on a key it guessed wrong passes for the
  /// wrong reason.
  FakeSettingsRepository({
    Map<String, String>? values,
    this.homeCurrencyCode = 'INR',
    this.defaultAccountId,
  }) : _values = {...?values};

  final Map<String, String> _values;

  /// What `readHomeCurrencyCode` answers.
  final String? homeCurrencyCode;

  /// What `readDefaultAccountId` answers.
  final String? defaultAccountId;

  /// Everything written so far, so a test can assert a preference was actually persisted.
  Map<String, String> get values => Map.unmodifiable(_values);

  @override
  Future<String?> readValue(String key) async => _values[key];

  @override
  Stream<String?> watchValue(String key) => Stream.value(_values[key]);

  @override
  Stream<Map<String, String>> watchAll() => Stream.value(values);

  @override
  Future<Result<void, Failure>> writeValue({
    required String key,
    required String value,
    required String valueType,
  }) async {
    _values[key] = value;
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> remove(String key) async {
    _values.remove(key);
    return const Result.ok(null);
  }

  // Phase 8A added `writeHomeCurrencyCode` to the contract, so this fake stopped satisfying it. Routed
  // through `writeValue` like the real implementation, so a test asserting on the stored key sees the same
  // row either way.
  @override
  Future<Result<void, Failure>> writeHomeCurrencyCode(String code) =>
      writeValue(key: 'homeCurrencyCode', value: code, valueType: 'string');

  @override
  Future<String?> readHomeCurrencyCode() async => homeCurrencyCode;

  @override
  Future<String?> readDefaultAccountId() async => defaultAccountId;
}
```

---

## COVERAGE — ARCH_5 §7 rows closed by Phase 8A

Both parts together. Part 1 is `PHASE_08A_SETTINGS_LOCK.md`.

| Row | Status |
|---|---|
| **`app_settings`** | **Closed.** Read and written through `SettingsRepository`; `writeHomeCurrencyCode` added as the counterpart of the read that already existed |
| **`accounts` (create / edit / archive)** | **Closed.** `AccountsSettingsScreen` + `AccountEditorScreen`. Archive, never delete — an account is named by every transaction that used it |
| **`payment_methods`** | **Closed.** Archetype D over a capture sheet; `isSystem` preserved on rename |
| **`payees` (manage)** | **Closed.** The one branch with search, matched on `normalizedName` so "cafe" finds "Café" |
| **`tags` (manage)** | **Closed.** List, editor, and the scoping matrix |
| **`units`** | **Closed.** Integer factor asked in base units; the "make it a new item" escape when there is none |
| **`currencies`** | **Closed.** Enable and disable; the home currency's switch inert with a reason rather than hidden |
| **Onboarding (B) · Settings tree (D) · PIN setup (B) · Lock (A)** | **Closed.** Plus twelve settings branches and three editors the DELIVER list did not name but the coverage rows require |

### §7.2 rows

| Row | Where it closed |
|---|---|
| **`accounts.includeInNetWorth`** | Onboarding **and** the editor, each with the subtitle that says what *off* means — without it the reader cannot tell whether the account is hidden or merely uncounted |
| **`accounts.openingBalance` / `openingBalanceDateKey`** | Captured as a **pair** in both places, with anomaly A03's paragraph explaining why the date is not optional |
| **`tags.parentTagId`** | `TagEditorScreen`'s parent picker, pre-filtered to exclude the tag and its descendants so a cycle cannot be built |
| **`tags.allowedIn*`** | The six-switch matrix. **"Kitchen" scoped to Items does not appear in the deposit picker** — asserted in `settings_tree_test.dart`, not merely intended |

### Also closed

**ARCH_4 §5.1 item 23** — theme choice persisted. Both `activePaletteProvider` and `themeModeProvider` became
`Notifier`s writing to `app_settings`, which also retired the app's last `StateProvider`.

### The nine CRITICAL requirements

| | |
|---|---|
| Honest copy, in plain words | `lockHonestBody` on the lock screen, the onboarding security step and Security — asserted by phrase, not by key |
| No "bank-grade", no "military-grade" | Verified absent across every file |
| No padlock iconography | `Icons.lock` and `Icons.lock_outline` absent everywhere, and asserted `findsNothing` in two tests |
| PIN, hash and recovery code never in the database | They reach `AppLockStore` only, which is secure storage. Restoring a backup therefore cannot change who can open the app (A43) |
| "Forgot both" exports first, then requires typing `ERASE` | `RecoveryFlow`'s last stage, with the export **above** the erase and the word on `DataTransferPort` so the screen can compare against it |
| Router `LockGate` on the real service | `isLockedProvider` over `pinServiceProvider`, typed as `AppLock` |
| GoRouter `refreshListenable` | `routerRefreshProvider`, a `ValueNotifier` bridge driven by the same provider widgets watch |
| Auto-erase after 10 failures, default **off** | `autoEraseSettingKey`; an unset key reads false, which is what "default off" must mean for a feature that destroys data |
| Behind a scary confirm | `ConfirmSheet` naming the number — "after 10 failed attempts, every account, transaction and item on this device is deleted" |

### Deviations, each deliberate

| Deviation | Why |
|---|---|
| **Lock screen takes archetype A's shape, not its skeleton** | A is a sheet; a sheet is dismissible, and one with no way out is worse than a screen. One required input, focused on open, chips for context, commit on parse — all retained |
| **A keypad rather than A's "keyboard up"** | The system keyboard can be switched to a layout with no digits, carries autocorrect chrome over a secret, and can be dismissed on a screen with no other exit. Every key is a labelled 48dp target, which is what makes `labeledTapTargetGuideline` pass |
| **Onboarding has no `CloseButton`** | Nothing is behind it — the router redirects here until it is done. The escape is a named **Skip** that routes through the same `finish()`, so a skip is recorded as deliberately as a completion |
| **Settings tree has no FAB** | Nothing is added at tree level; each branch owns its own add action |
| **Three domain ports added** | `PinService` and `BackupService` are `final class` and cannot be faked, and both plugins need a platform channel. Without the contracts, §9.1 was unreachable. This is the `AnalyticsPort` pattern |
| **`file_picker` not added** | ARCH_1 §7 pins it to 8A, but nothing here imports it: this phase **shares** rather than saves, and ARCH_3 §3.3's Storage Access Framework path arrives with 8B's Backup screen |
| **About shows no version** | Reading one needs `package_info_plus`, which §7 does not pin. A hard-coded constant would be wrong from the first release that forgot to update it |
| **Auto-lock delay stated, not configurable** | `autoLockDelay` is a constant in this phase; a picker writing a setting nothing reads would be a dead control. `autoLockDelaySettingKey` is reserved so 8B needs no migration |

### Carried files, so their documents regenerate

`PHASE_03A` and `PHASE_03B` (the settings contract and its implementation), `PHASE_04C` (`PinService` now
`implements AppLock`), `PHASE_05` (`app.dart`, `service_providers.dart`), and `PHASE_05` through `PHASE_07B` for
`routes.dart`, `app_router.dart`, `app_en.arb` and `layout_overflow_test.dart`.

### Open, with owners

| Item | Why | Owner |
|---|---|---|
| Restore | Needs the SAF picker and a merge strategy. Stated as *coming in the next update* rather than offered and broken | 8B |
| "Save to…" export | The SAF create-document path, and `file_picker` with it | 8B |
| Configurable auto-lock delay | Key reserved, no picker | 8B |
| `package_info_plus` for a version string | One row, one dependency — worth deciding rather than assuming | 8B or 9 |
| Per-screen goldens | §9.2 asks for goldens on new **shared** widgets; 8A added none to `shared/`, so `pin_pad.dart` is feature-local and covered by the layout cases instead | — |
| `TagRepository.watchTransactionIdsFor` | 7B recorded that a tag→ledger drill-down needs it. Not required by 8A, and still not built | 8B |

### First-build gate

```
flutter pub add local_auth path_provider share_plus
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter test
```

Two things are most likely to fail first, both flagged in situ: `share_plus`'s v11 API
(`SharePlus.instance.share(ShareParams(...))`) and `local_auth`'s `AuthenticationOptions`, neither of which could be
compiled against in the session that wrote them (ARCH_4 R22). Each is confined to a single file.
