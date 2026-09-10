import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/features/shopping/presentation/sheets/entry_editor_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/generate_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/list_manager_sheet.dart';
import 'package:alaya/features/shopping/presentation/widgets/entry_row.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// A shopping list (ARCH_5 §3 archetype D).
///
/// **The list switcher lives in the body, not the app bar.** The shell owns the app bar for every
/// drawer destination, so a screen inside it cannot add actions there — the same constraint that put
/// search in the body in 6A and 6B.
class ShoppingListScreen extends ConsumerWidget {
  /// Shows [listId], or the default list when null.
  const ShoppingListScreen({this.listId, super.key});

  /// Which list to show.
  final String? listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final active = ref.watch(activeListProvider);

    return Scaffold(
      body: active.when(
        loading: () => AlayaListSkeleton(label: strings.loadingShopping),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(selectableListsProvider),
        ),
        data: (list) => list == null
            ? _NoLists(onCreate: () => ListManagerSheet.show(context))
            : _Body(list: list),
      ),
      floatingActionButton: active.valueOrNull == null
          ? null
          : FloatingActionButton(
              onPressed: () => EntryEditorSheet.show(
                context,
                listId: active.valueOrNull!.id,
              ),
              tooltip: strings.addEntry,
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _NoLists extends StatelessWidget {
  const _NoLists({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return EmptyState(
      title: strings.emptyTitleNoLists,
      body: strings.emptyBodyNoLists,
      icon: Icons.checklist_outlined,
      actionLabel: strings.listCreate,
      onAction: onCreate,
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.list});

  final ShoppingList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final groups = ref.watch(shoppingGroupsProvider(list.id));
    final summary = ref.watch(shoppingSummaryProvider(list.id));

    return Column(
      children: [
        _Header(list: list, summary: summary),
        Expanded(
          child: groups.when(
            loading: () => AlayaListSkeleton(label: strings.loadingShopping),
            error: (error, stack) => ErrorState(
              title: strings.errorTitleGeneric,
              body: error.toString(),
              retryLabel: strings.actionRetry,
              onRetry: () => ref.invalidate(entriesProvider(list.id)),
            ),
            data: (sections) => sections.isEmpty
                ? EmptyState(
                    title: strings.emptyTitleNoEntries,
                    body: strings.emptyBodyNoEntries,
                    icon: Icons.checklist_outlined,
                    actionLabel: strings.generateTitle,
                    onAction: () =>
                        GenerateSheet.show(context, listId: list.id),
                  )
                : _Sections(list: list, sections: sections),
          ),
        ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.list, required this.summary});

  final ShoppingList list;
  final ShoppingSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final digits = ref.watch(entryDecimalDigitsProvider).valueOrNull ?? 2;
    final estimate = summary.estimate;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.sm,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  list.name,
                  style: AlayaTypography.cardTitle.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => ListManagerSheet.show(context),
                tooltip: strings.shoppingSwitchList,
                icon: const Icon(Icons.swap_horiz, size: AlayaIconSize.lg),
              ),
            ],
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  strings.shoppingCheckedCount(summary.checked, summary.total),
                  style: AlayaTypography.caption.copyWith(
                    color: semantic.muted,
                  ),
                ),
              ),
              if (estimate != null) ...[
                Text(
                  strings.shoppingEstimate,
                  style: AlayaTypography.caption.copyWith(
                    color: semantic.muted,
                  ),
                ),
                const SizedBox(width: AlayaSpacing.xxs),
                AmountText(
                  estimate,
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: digits,
                ),
              ],
            ],
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              ActionChip(
                avatar: const Icon(
                  Icons.auto_awesome_outlined,
                  size: AlayaIconSize.sm,
                ),
                label: Text(strings.generateTitle),
                onPressed: () => GenerateSheet.show(context, listId: list.id),
              ),
              ActionChip(
                avatar: const Icon(
                  Icons.receipt_long_outlined,
                  size: AlayaIconSize.sm,
                ),
                label: Text(strings.convertTitle),
                onPressed: summary.hasChecked
                    ? () => context.push(Routes.shoppingConvert(list.id))
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Sections extends ConsumerWidget {
  const _Sections({required this.list, required this.sections});

  final ShoppingList list;
  final List<ShoppingGroup> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final items =
        ref.watch(shoppingItemsByIdProvider).valueOrNull ??
        const <String, Item>{};
    final digits = ref.watch(entryDecimalDigitsProvider).valueOrNull ?? 2;
    final actions = ref.read(shoppingActionsProvider);

    // Reports the repository's own message. "Something went wrong" told the user nothing and told a
    // bug report even less — three unrelated failures arrived as one indistinguishable sentence.
    Future<void> guard(Future<String?> Function() run) async {
      final error = await run();
      if (!context.mounted || error == null) return;
      showFailureSnack(context, message: error);
    }

    return CustomScrollView(
      slivers: [
        for (final section in sections)
          SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AlayaSpacing.screenEdge,
                    AlayaSpacing.md,
                    AlayaSpacing.screenEdge,
                    AlayaSpacing.xs,
                  ),
                  child: Text(
                    section.tag?.name ?? strings.shoppingGroupUntagged,
                    style: AlayaTypography.sectionHeader.copyWith(
                      color: semantic.muted,
                    ),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: section.entries.length,
                itemBuilder: (context, index) {
                  final entry = section.entries[index];
                  return EntryRow(
                    entry: entry,
                    item: entry.itemId == null ? null : items[entry.itemId],
                    decimalDigits: digits,
                    onToggle: (checked) => guard(
                      () =>
                          actions.setChecked(id: entry.id, isChecked: checked),
                    ),
                    onTap: () => EntryEditorSheet.show(
                      context,
                      listId: list.id,
                      entryId: entry.id,
                    ),
                    onSnooze: entry.isAutoGenerated
                        ? () => guard(() => actions.snooze(entry.id))
                        : null,
                    onDismiss: entry.isAutoGenerated
                        ? () => guard(() => actions.dismiss(entry.id))
                        : null,
                    onDelete: () => _delete(context, actions, strings, entry),
                  );
                },
              ),
            ],
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AlayaSpacing.xxxl)),
      ],
    );
  }

  /// Removes an entry and offers it straight back.
  ///
  /// **The undo is why there is no confirmation dialog.** A shopping line is cheap to lose and expensive
  /// to interrupt for — one tap to reverse beats one tap to authorise, and `deleteEntry` is a soft delete
  /// either way, so the row stays recoverable from Trash regardless.
  Future<void> _delete(
    BuildContext context,
    ShoppingActions actions,
    AlayaStrings strings,
    ShoppingEntry entry,
  ) async {
    final error = await actions.delete(entry.id);
    if (!context.mounted) return;
    if (error != null) {
      showFailureSnack(context, message: error);
      return;
    }
    showUndoSnack(
      context,
      message: strings.shoppingEntryDeleted,
      undoLabel: strings.actionUndo,
      onUndo: () async {
        final failure = await actions.restore(entry);
        if (!context.mounted || failure == null) return;
        showFailureSnack(context, message: failure);
      },
    );
  }
}
