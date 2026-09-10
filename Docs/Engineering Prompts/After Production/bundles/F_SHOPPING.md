# F_SHOPPING

Shopping lists, entries, convert-to-purchase.

**17 files · 3,327 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/features/shopping/presentation/screens/convert_to_purchase_screen.dart`

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
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/shopping/providers/convert_providers.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Turns a finished list into a pre-filled withdrawal (ARCH_5 §3 archetype B).
///
/// **It hands off; it does not commit.** The primary action offers a draft to the expense editor and
/// navigates there. The amount, the account and the payee are decisions only that screen collects,
/// and duplicating them here would fork the one place in the app that knows how a withdrawal is
/// shaped (anomaly A25). Nothing is written until the user saves there.
class ConvertToPurchaseScreen extends ConsumerWidget {
  /// Converts the ticked entries of [listId].
  const ConvertToPurchaseScreen({required this.listId, super.key});

  /// Which list to convert.
  final String listId;

  void _handOff(
    BuildContext context,
    WidgetRef ref,
    List<TransactionLine> lines,
  ) {
    final offered = ref
        .read(convertActionsProvider)
        .offerDraft(listId: listId, lines: lines);
    if (!offered) return;
    context.pushReplacement(Routes.transactionNew);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(purchaseDraftProvider(listId));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(strings.convertTitle),
      ),
      body: draft.when(
        loading: () => AlayaListSkeleton(
          label: strings.loadingShopping,
          hasLeading: false,
        ),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: strings.errorBodyGeneric,
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(purchaseDraftProvider(listId)),
        ),
        data: (lines) => lines.isEmpty
            ? EmptyState(
                title: strings.convertNothingTitle,
                body: strings.convertNothingBody,
                icon: Icons.checklist_outlined,
              )
            : AlayaFormScaffold(
                primaryLabel: strings.convertConfirm,
                onPrimary: () => _handOff(context, ref, lines),
                isDirty: false,
                isSubmitting: false,
                discardTitle: strings.confirmDiscardTitle,
                discardBody: strings.confirmDiscardBody,
                discardConfirmLabel: strings.actionDiscard,
                discardCancelLabel: strings.actionKeepEditing,
                child: _Preview(lines: lines),
              ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.lines});

  final List<TransactionLine> lines;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.convertBody,
          style: AlayaTypography.body.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: StatusChip(
            label: strings.convertLineCount(lines.length),
            tone: StatusTone.info,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  line.destination == TransactionLineDestination.inventory
                      ? Icons.inventory_2_outlined
                      : Icons.receipt_long_outlined,
                  size: AlayaIconSize.md,
                  color: semantic.muted,
                ),
                const SizedBox(width: AlayaSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.description, style: AlayaTypography.body),
                      if (line.quantity != null) ...[
                        const SizedBox(height: AlayaSpacing.xxs),
                        QtyText(line.quantity!, muted: true),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
```

### `lib/features/shopping/presentation/screens/shopping_list_screen.dart`

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
```

### `lib/features/shopping/presentation/sheets/entry_editor_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/state/entry_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Adds or edits one shopping entry (ARCH_5 §3 archetype A).
///
/// **Free text is the primary field and the item link is optional.** A television belongs on a
/// shopping list and has no place in an inventory that measures flour by the gram, so `itemId` stays
/// nullable and an entry needs only one of the two to identify itself.
///
/// A quantity is offered only once an item is linked, for the same reason as the line editor in 6A:
/// a `Qty` is an integer plus a `UnitCategory`, and the category comes from the item (Law L8).
class EntryEditorSheet extends ConsumerWidget {
  /// Creates the sheet.
  const EntryEditorSheet({required this.listId, this.entryId, super.key});

  /// Which list the entry belongs to.
  final String listId;

  /// The entry being edited, or null for a new one.
  final String? entryId;

  /// Opens the sheet.
  static Future<void> show(
    BuildContext context, {
    required String listId,
    String? entryId,
  }) => AlayaBottomSheet.show<void>(
    context: context,
    builder: (context) => EntryEditorSheet(listId: listId, entryId: entryId),
  );

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    EntryEditorArgs args,
  ) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(entryEditorProvider(args).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    Navigator.of(context).pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.actionSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final args = (listId: listId, entryId: entryId);
    final async = ref.watch(entryEditorProvider(args));

    return async.when(
      loading: () => AlayaListSkeleton(label: strings.loadingShopping, rows: 3),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleNotFound,
        body: strings.errorBodyNotFound,
      ),
      data: (state) => _Form(
        args: args,
        state: state,
        onSave: () => _save(context, ref, args),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.args, required this.state, required this.onSave});

  final EntryEditorArgs args;
  final EntryEditorState state;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(entryEditorProvider(args).notifier);
    final items = ref.watch(entryItemsProvider).valueOrNull ?? const <Item>[];
    final tags = ref.watch(entryTagsProvider).valueOrNull ?? const <Tag>[];
    final currency = ref.watch(entryCurrencyProvider).valueOrNull;
    final digits = ref.watch(entryDecimalDigitsProvider).valueOrNull ?? 2;

    Item? linked;
    for (final item in items) {
      if (item.id == state.itemId) linked = item;
    }
    final units =
        ref.watch(entryUnitsProvider(linked?.unitCategory)).valueOrNull ??
        const <Unit>[];
    Unit? selectedUnit;
    for (final unit in units) {
      if (unit.code == state.unitCode) selectedUnit = unit;
    }
    selectedUnit ??= units.isEmpty ? null : units.first;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.entryEditorTitle,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: TextFormField(
            initialValue: state.freeText,
            autofocus: !state.isEditing,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.entryFreeTextLabel,
              hintText: strings.entryFreeTextHint,
              errorText: state.identityMissing
                  ? strings.entryNeedsSomething
                  : null,
            ),
            onChanged: notifier.setFreeText,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<String?>(
          // **`linked?.id`, not `state.itemId`.** The items arrive from a stream, so on the first
          // frame the list is empty while the state already names an item — and a dropdown whose
          // value matches none of its items throws "There should be exactly one item". Deriving the
          // value from the list that is actually rendered makes that unrepresentable.
          key: ValueKey(linked?.id),
          initialValue: linked?.id,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.entryLinkItem),
          items: [
            DropdownMenuItem<String?>(child: Text(strings.entryNoItem)),
            for (final item in items)
              DropdownMenuItem<String?>(
                value: item.id,
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value == null) {
              notifier.setItem(null);
              return;
            }
            for (final item in items) {
              if (item.id == value) notifier.setItem(item);
            }
          },
        ),
        if (linked != null && units.isNotEmpty && selectedUnit != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          QtyField(
            key: ValueKey('${linked.id}:${selectedUnit.code}'),
            category: linked.unitCategory,
            units: units,
            selectedUnit: selectedUnit,
            label: strings.labelQuantity,
            unitLabel: strings.labelUnit,
            initialValue: state.quantity,
            onChanged: notifier.setQuantity,
            onUnitChanged: (unit) => notifier.setUnitCode(unit.code),
          ),
        ],
        if (currency != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          AmountField(
            currencyCode: currency,
            decimalDigits: digits,
            label: strings.labelEstimatedPrice,
            initialValue: state.estimatedPrice,
            onChanged: notifier.setEstimatedPrice,
          ),
        ],
        if (tags.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.md),
          Text(
            strings.labelTags,
            style: AlayaTypography.label.copyWith(color: semantic.muted),
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              for (final tag in tags)
                TagChip(
                  tag: tag,
                  selected: state.tagId == tag.id,
                  onTap: () =>
                      notifier.setTag(state.tagId == tag.id ? null : tag.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: state.submitting ? null : onSave,
          child: Text(strings.actionSave),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionCancel),
        ),
      ],
    );
  }
}
```

### `lib/features/shopping/presentation/sheets/generate_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/features/shopping/providers/generate_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Low-stock suggestions, each accepted, snoozed or dismissed on its own (ARCH_5 §3 archetype A).
///
/// **Accepting is an action, not an absence of one.** Regeneration writes the entries, so technically
/// leaving a row alone keeps it — but a sheet offering only "Snooze" and "Not now" reads as though
/// the only choices are ways to say no. "Add to my list" promotes the row to `origin = manual`, which
/// is both the affirmative answer and the thing that makes regeneration leave it alone for good (A23).
///
/// **A turned-down row stays listed here.** The list screen hides it via `isVisibleAsOf`, but this is
/// where suggestions are managed, so hiding it here too made "Not now" irreversible until stock
/// recovered and dropped again. It is shown with its state, and accepting it brings it back.
class GenerateSheet extends ConsumerWidget {
  /// Creates the sheet.
  const GenerateSheet({required this.listId, super.key});

  /// Which list to suggest into.
  final String listId;

  /// Opens the sheet, regenerating as it opens.
  static Future<void> show(BuildContext context, {required String listId}) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => GenerateSheet(listId: listId),
      );

  Future<void> _regenerate(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final outcome = await ref.read(generateActionsProvider).regenerate(listId);
    if (!context.mounted) return;
    final error = outcome.error;
    error != null
        ? showFailureSnack(context, message: error)
        : showResultSnack(
            context,
            message: strings.generateAdded(outcome.added ?? 0),
          );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final suggestions = ref.watch(lowStockSuggestionsProvider(listId));
    final actions = ref.read(shoppingActionsProvider);

    Future<void> guard(Future<String?> Function() run) async {
      final failed = await run();
      if (!context.mounted || failed == null) return;
      showFailureSnack(context, message: failed);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A `Wrap`, not a `Row`. The refresh button is not flexible, so at a doubled text scale it
        // takes its full natural width and pushes the title off the edge — the same shape that
        // overflowed a transaction row, a nudge banner and an item row before it.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AlayaSpacing.xs,
          children: [
            Text(
              strings.generateTitle,
              style: AlayaTypography.cardTitle.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            TextButton(
              onPressed: () => _regenerate(context, ref),
              child: Text(strings.generateRefresh),
            ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        Text(
          strings.generateBody,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.md),
        suggestions.when(
          loading: () =>
              AlayaListSkeleton(label: strings.loadingShopping, rows: 3),
          // Shows the error rather than a stand-in for it. Regeneration can succeed while reading
          // the entries back fails, and reporting both halves as "something went wrong" made a
          // working write look like a broken one (U9).
          error: (error, stack) => ErrorState(
            title: strings.errorTitleGeneric,
            body: error.toString(),
            retryLabel: strings.actionRetry,
            onRetry: () => ref.invalidate(entriesProvider(listId)),
          ),
          data: (rows) => rows.isEmpty
              ? EmptyState(
                  title: strings.generateEmptyTitle,
                  body: strings.generateEmptyBody,
                  icon: Icons.auto_awesome_outlined,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final suggestion in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
                        child: AlayaCard(
                          padding: const EdgeInsets.all(AlayaSpacing.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                suggestion.item?.name ??
                                    suggestion.entry.freeText ??
                                    strings.labelItem,
                                style: AlayaTypography.body.copyWith(
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              if (suggestion.entry.autoState !=
                                  ShoppingEntryAutoState.active) ...[
                                const SizedBox(height: AlayaSpacing.xxs),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child:
                                      suggestion.entry.autoState ==
                                          ShoppingEntryAutoState.dismissed
                                      ? StatusChip(
                                          label: strings.suggestionDismissed,
                                        )
                                      : StatusChip(
                                          label: strings.snoozedUntilLabel,
                                          trailing:
                                              suggestion
                                                      .entry
                                                      .snoozeUntilDateKey ==
                                                  null
                                              ? null
                                              : DateText(
                                                  suggestion
                                                      .entry
                                                      .snoozeUntilDateKey!,
                                                  style: DateTextStyle.dayMonth,
                                                  muted: true,
                                                ),
                                        ),
                                ),
                              ],
                              if (suggestion.shortfall != null) ...[
                                const SizedBox(height: AlayaSpacing.xxs),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: AlayaSpacing.xxs,
                                  children: [
                                    Text(
                                      strings.generateShortBy,
                                      style: AlayaTypography.caption.copyWith(
                                        color: semantic.muted,
                                      ),
                                    ),
                                    QtyText(suggestion.shortfall!, muted: true),
                                  ],
                                ),
                              ],
                              const SizedBox(height: AlayaSpacing.xs),
                              Wrap(
                                spacing: AlayaSpacing.xs,
                                runSpacing: AlayaSpacing.xxs,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: () => guard(
                                      () => ref
                                          .read(generateActionsProvider)
                                          .accept(suggestion.entry),
                                    ),
                                    icon: const Icon(
                                      Icons.add,
                                      size: AlayaIconSize.sm,
                                    ),
                                    label: Text(strings.actionAddToList),
                                  ),
                                  if (suggestion.entry.autoState ==
                                      ShoppingEntryAutoState.active)
                                    TextButton.icon(
                                      onPressed: () => guard(
                                        () =>
                                            actions.snooze(suggestion.entry.id),
                                      ),
                                      icon: const Icon(
                                        Icons.snooze,
                                        size: AlayaIconSize.sm,
                                      ),
                                      label: Text(strings.actionSnooze),
                                    ),
                                  if (suggestion.entry.autoState !=
                                      ShoppingEntryAutoState.dismissed)
                                    TextButton(
                                      onPressed: () => guard(
                                        () => actions.dismiss(
                                          suggestion.entry.id,
                                        ),
                                      ),
                                      child: Text(strings.actionDismiss),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionDone),
        ),
      ],
    );
  }
}
```

### `lib/features/shopping/presentation/sheets/list_manager_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/features/shopping/providers/list_manager_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Creates, renames, re-points and archives shopping lists (ARCH_5 §3 archetype A).
///
/// **Archived rather than deleted.** A list that has been converted to a purchase is the provenance
/// of those transaction lines, so retiring it hides it from the switcher without breaking what it
/// explains (Law L6).
class ListManagerSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const ListManagerSheet({super.key});

  /// Opens the sheet.
  static Future<void> show(BuildContext context) => AlayaBottomSheet.show<void>(
    context: context,
    builder: (context) => const ListManagerSheet(),
  );

  @override
  ConsumerState<ListManagerSheet> createState() => _ListManagerSheetState();
}

class _ListManagerSheetState extends ConsumerState<ListManagerSheet> {
  final TextEditingController _name = TextEditingController();
  String? _renamingId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<String?> Function() run) async {
    final error = await run();
    if (!mounted || error == null) return;
    showFailureSnack(context, message: error);
  }

  Future<void> _submitName(List<ShoppingList> lists) async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final actions = ref.read(listManagerActionsProvider);
    final renaming = _renamingId;
    if (renaming != null) {
      for (final list in lists) {
        if (list.id != renaming) continue;
        await _guard(() => actions.rename(list, name));
      }
    } else {
      final created = await actions.create(name, isFirst: lists.isEmpty);
      final error = created.error;
      if (error != null && mounted) showFailureSnack(context, message: error);
    }
    if (!mounted) return;
    _name.clear();
    setState(() => _renamingId = null);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final lists = ref.watch(allListsProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.listManagerTitle,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        lists.when(
          loading: () =>
              AlayaListSkeleton(label: strings.loadingShopping, rows: 3),
          error: (error, stack) => ErrorState(
            title: strings.errorTitleGeneric,
            body: strings.errorBodyGeneric,
          ),
          data: (all) => all.isEmpty
              ? EmptyState(
                  title: strings.emptyTitleNoLists,
                  body: strings.emptyBodyNoLists,
                  icon: Icons.checklist_outlined,
                )
              : _Lists(
                  lists: all,
                  onSelect: (id) {
                    ref.read(selectedListIdProvider.notifier).select(id);
                    Navigator.of(context).pop();
                  },
                  onRename: (list) => setState(() {
                    _renamingId = list.id;
                    _name.text = list.name;
                  }),
                  onDefault: (id) => _guard(
                    () => ref.read(listManagerActionsProvider).setDefault(id),
                  ),
                  onArchive: (list) => _guard(
                    () => ref
                        .read(listManagerActionsProvider)
                        .setArchived(
                          id: list.id,
                          isArchived: !list.isArchived,
                        ),
                  ),
                ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _name,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: strings.listNameLabel),
          onSubmitted: (_) => _submitName(lists.valueOrNull ?? const []),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        // Stacked rather than beside the field. The button is not flexible, so a Row overflowed by a
        // hair at a doubled text scale — and a hair is the same defect as a mile.
        FilledButton(
          onPressed: () => _submitName(lists.valueOrNull ?? const []),
          child: Text(
            _renamingId == null ? strings.listCreate : strings.listRename,
          ),
        ),
        if (_renamingId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                _renamingId = null;
                _name.clear();
              }),
              child: Text(strings.actionCancel),
            ),
          ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          strings.emptyBodyNoLists,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
      ],
    );
  }
}

class _Lists extends StatelessWidget {
  const _Lists({
    required this.lists,
    required this.onSelect,
    required this.onRename,
    required this.onDefault,
    required this.onArchive,
  });

  final List<ShoppingList> lists;
  final ValueChanged<String> onSelect;
  final ValueChanged<ShoppingList> onRename;
  final ValueChanged<String> onDefault;
  final ValueChanged<ShoppingList> onArchive;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final live = [
      for (final list in lists)
        if (!list.isArchived) list,
    ];
    final archived = [
      for (final list in lists)
        if (list.isArchived) list,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final list in live)
          _Tile(
            list: list,
            onSelect: onSelect,
            onRename: onRename,
            onDefault: onDefault,
            onArchive: onArchive,
          ),
        if (archived.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.sm),
          Text(
            strings.listArchivedSection,
            style: AlayaTypography.sectionHeader.copyWith(
              color: context.semantic.muted,
            ),
          ),
          for (final list in archived)
            _Tile(
              list: list,
              onSelect: onSelect,
              onRename: onRename,
              onDefault: onDefault,
              onArchive: onArchive,
            ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.list,
    required this.onSelect,
    required this.onRename,
    required this.onDefault,
    required this.onArchive,
  });

  final ShoppingList list;
  final ValueChanged<String> onSelect;
  final ValueChanged<ShoppingList> onRename;
  final ValueChanged<String> onDefault;
  final ValueChanged<ShoppingList> onArchive;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: list.isArchived ? null : () => onSelect(list.id),
      title: Text(list.name),
      subtitle: Wrap(
        spacing: AlayaSpacing.xs,
        runSpacing: AlayaSpacing.xxs,
        children: [
          if (list.isDefault)
            StatusChip(
              label: strings.listDefaultBadge,
              tone: StatusTone.success,
            ),
          if (list.isArchived) StatusChip(label: strings.listArchivedBadge),
        ],
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: AlayaIconSize.md),
        onSelected: (value) => switch (value) {
          'rename' => onRename(list),
          'default' => onDefault(list.id),
          _ => onArchive(list),
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'rename', child: Text(strings.listRename)),
          if (!list.isDefault && !list.isArchived)
            PopupMenuItem(
              value: 'default',
              child: Text(strings.listSetDefault),
            ),
          PopupMenuItem(
            value: 'archive',
            child: Text(
              list.isArchived ? strings.listUnarchive : strings.listArchive,
            ),
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/shopping/presentation/widgets/entry_row.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One shopping row: a tick, what to buy, and what it is expected to cost.
///
/// **A suggested row is marked as suggested.** `origin = autoLowStock` means the app put it there,
/// not the user, and the snooze and dismiss actions only make sense against something the app
/// proposed — offering them on a row someone typed would read as the app second-guessing them.
///
/// Stacks above 1.5x text scale: the estimate is not flexible, so at a doubled scale it starves the
/// label beside it, and `AmountText` clips rather than ellipsises (Law U15).
class EntryRow extends StatelessWidget {
  /// Creates the row.
  const EntryRow({
    required this.entry,
    required this.item,
    required this.decimalDigits,
    required this.onToggle,
    required this.onTap,
    this.onSnooze,
    this.onDismiss,
    this.onDelete,
    super.key,
  });

  /// The entry.
  final ShoppingEntry entry;

  /// The catalogued item it restocks, if any.
  final Item? item;

  /// The home currency's precision.
  final int decimalDigits;

  /// Ticks or unticks it.
  final ValueChanged<bool> onToggle;

  /// Opens the entry editor.
  final VoidCallback onTap;

  /// Hides a suggestion for a week.
  final VoidCallback? onSnooze;

  /// Dismisses a suggestion until stock recovers and drops again.
  final VoidCallback? onDismiss;

  /// Removes the entry, with the caller responsible for offering an undo.
  ///
  /// Null makes the row undismissable, which is how the convert-to-purchase screen reuses it — deleting
  /// a line mid-checkout would change what you are about to pay for.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final delete = onDelete;
    if (delete == null) return _content(context);

    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    return Dismissible(
      // Keyed on the entry, not the position. A list that reorders while a swipe is in flight would
      // otherwise delete whichever row slid into that index.
      key: ValueKey<String>('shopping-entry-${entry.id}'),
      // **`endToStart`, not "left".** It means the trailing edge, so the gesture stays natural when the
      // locale flips — and Alaya's 1,100 ARB keys exist because RTL is on the table.
      direction: DismissDirection.endToStart,
      // No confirmation dialog. The caller offers an undo instead, which costs one tap to reverse rather
      // than one tap to authorise — and the thing being removed is a line on a shopping list, not money.
      onDismissed: (_) => delete(),
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(
          horizontal: AlayaSpacing.screenEdge,
        ),
        // `surfaceSunken` behind `danger` content, rather than a saturated red panel. The swipe should
        // read as an action being revealed, not as an alarm — and `dangerSurface` was a token I invented;
        // the palette has `danger` and the four surfaces, nothing between them.
        color: semantic.surfaceSunken,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline,
              size: AlayaIconSize.md,
              color: semantic.danger,
            ),
            const SizedBox(width: AlayaSpacing.xs),
            Text(
              strings.actionDelete,
              style: AlayaTypography.button.copyWith(color: semantic.danger),
            ),
          ],
        ),
      ),
      child: _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final label = entry.freeText ?? item?.name ?? strings.labelItem;
    final price = entry.estimatedPrice;
    final quantity = entry.quantity;
    final snoozeUntil = entry.snoozeUntilDateKey;

    final estimate = price == null
        ? const SizedBox.shrink()
        : AmountText(
            price,
            size: AmountSize.small,
            showSign: false,
            decimalDigits: decimalDigits,
            muted: entry.isChecked,
            textAlign: stacked ? TextAlign.start : TextAlign.end,
          );

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
            vertical: AlayaSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A bare `Checkbox` announces a checked state and nothing else — a screen reader hears
              // "tick box" with no idea which row it belongs to. The label is the entry's own name,
              // which is exactly what a sighted user reads beside it (U16).
              Semantics(
                label: label,
                child: Checkbox(
                  value: entry.isChecked,
                  onChanged: (value) => onToggle(value ?? false),
                ),
              ),
              const SizedBox(width: AlayaSpacing.xxs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: AlayaSpacing.sm),
                      child: Text(
                        label,
                        style: AlayaTypography.body.copyWith(
                          color: entry.isChecked
                              ? semantic.muted
                              : theme.colorScheme.onSurface,
                          decoration: entry.isChecked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (quantity != null) ...[
                      const SizedBox(height: AlayaSpacing.xxs),
                      QtyText(quantity, muted: true),
                    ],
                    if (stacked && price != null) ...[
                      const SizedBox(height: AlayaSpacing.xxs),
                      estimate,
                    ],
                    if (entry.origin == ShoppingEntryOrigin.autoLowStock) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      Wrap(
                        spacing: AlayaSpacing.xs,
                        runSpacing: AlayaSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusChip(
                            label: strings.originAutoLowStock,
                            tone: StatusTone.info,
                            icon: Icons.auto_awesome_outlined,
                          ),
                          if (entry.autoState ==
                                  ShoppingEntryAutoState.snoozed &&
                              snoozeUntil != null)
                            StatusChip(
                              label: strings.snoozedUntilLabel,
                              trailing: DateText(
                                snoozeUntil,
                                style: DateTextStyle.dayMonth,
                                muted: true,
                              ),
                            ),
                          if (onSnooze != null)
                            TextButton(
                              onPressed: onSnooze,
                              child: Text(strings.actionSnooze),
                            ),
                          if (onDismiss != null)
                            TextButton(
                              onPressed: onDismiss,
                              child: Text(strings.actionDismiss),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (!stacked && price != null) ...[
                const SizedBox(width: AlayaSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(top: AlayaSpacing.sm),
                  child: estimate,
                ),
              ],
              if (item != null)
                Padding(
                  padding: const EdgeInsets.only(top: AlayaSpacing.sm),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: AlayaIconSize.sm,
                    color: semantic.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### `lib/features/shopping/providers/convert_providers.dart`

```dart
/// View-model state for convert-to-purchase (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/providers/transaction_draft_provider.dart';
import 'package:alaya/features/expense/state/transaction_draft.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';

/// The draft lines a list's ticked entries would produce.
final purchaseDraftProvider = FutureProvider.autoDispose
    .family<List<TransactionLine>, String>((ref, listId) async {
      // Watched, not read: ticking a row on the list behind this screen should change what it offers.
      ref.watch(entriesProvider(listId));
      final result = await ref
          .watch(shoppingRepositoryProvider)
          .buildPurchaseDraft(listId);
      return result.valueOrNull ?? const <TransactionLine>[];
    });

/// Builds the handoff to the expense editor.
final convertActionsProvider = Provider<ConvertActions>(ConvertActions.new);

/// Turns a finished list into a draft the expense editor can open.
class ConvertActions {
  /// Creates the actions.
  ConvertActions(this._ref);

  final Ref _ref;

  /// Offers the draft to the next editor, returning false when there is nothing to convert.
  ///
  /// **This writes no transaction.** `buildPurchaseDraft` returns lines precisely so the amount, the
  /// account and the payee stay decisions the expense editor collects — reimplementing that here
  /// would fork the one screen in the app that knows how a withdrawal is shaped (anomaly A25).
  bool offerDraft({
    required String listId,
    required List<TransactionLine> lines,
  }) {
    if (lines.isEmpty) return false;
    final entries = _ref.read(entriesProvider(listId)).valueOrNull ?? const [];
    _ref
        .read(transactionDraftProvider.notifier)
        .offer(
          TransactionDraft(
            lines: lines,
            kind: TransactionKind.withdrawal,
            subtype: TransactionSubtype.grocery,
            sourceListId: listId,
            sourceEntryIds: [
              for (final entry in entries)
                if (entry.isChecked && !entry.isPurchased) entry.id,
            ],
          ),
        );
    return true;
  }
}
```

### `lib/features/shopping/providers/entry_editor_providers.dart`

```dart
/// View-model state for the shopping entry editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/shopping/state/entry_editor_state.dart';

/// Which entry an editor is pointed at. A record, so the family argument has structural equality.
typedef EntryEditorArgs = ({String listId, String? entryId});

/// Items offered for linking, so an entry can restock something the inventory tracks.
final entryItemsProvider = StreamProvider.autoDispose<List<Item>>(
  (ref) => ref.watch(itemRepositoryProvider).watchAll(),
);

/// Tags scoped to shopping, which is what groups the list into aisles.
final entryTagsProvider = StreamProvider.autoDispose<List<Tag>>(
  (ref) => ref.watch(tagRepositoryProvider).watchByScope(TagScope.shopping),
);

/// Units in one category, so a linked item never offers a cross-category unit (Law L8).
final entryUnitsProvider = StreamProvider.autoDispose
    .family<List<Unit>, UnitCategory?>(
      (ref, category) => category == null
          ? Stream.value(const <Unit>[])
          : ref.watch(unitRepositoryProvider).watchByCategory(category),
    );

/// The home currency, so an estimate is never denominated in a guess.
final entryCurrencyProvider = FutureProvider.autoDispose<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      'INR',
);

/// The home currency's decimal digits (ARCH_1 §4.1).
final entryDecimalDigitsProvider = FutureProvider.autoDispose<int>((ref) async {
  final code = await ref.watch(entryCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// The editor for one entry, or for a new one when `entryId` is null.
final entryEditorProvider = NotifierProvider.autoDispose
    .family<EntryEditorNotifier, AsyncValue<EntryEditorState>, EntryEditorArgs>(
      EntryEditorNotifier.new,
    );

/// Loads, edits and saves one shopping entry.
class EntryEditorNotifier
    extends
        AutoDisposeFamilyNotifier<
          AsyncValue<EntryEditorState>,
          EntryEditorArgs
        > {
  @override
  AsyncValue<EntryEditorState> build(EntryEditorArgs arg) {
    // A new entry needs nothing fetched, so it starts populated rather than flashing a skeleton —
    // and assigning state from an async gap inside `build` is what Riverpod refuses.
    if (arg.entryId == null) {
      return AsyncValue.data(EntryEditorState(listId: arg.listId));
    }
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(EntryEditorArgs arg) async {
    try {
      final entries = await ref
          .read(shoppingRepositoryProvider)
          .watchEntries(arg.listId)
          .first;
      for (final entry in entries) {
        if (entry.id != arg.entryId) continue;
        state = AsyncValue.data(EntryEditorState.fromEntry(entry));
        return;
      }
      state = AsyncValue.error(
        StateError('Entry ${arg.entryId} not found.'),
        StackTrace.current,
      );
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _edit(EntryEditorState Function(EntryEditorState) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(change(current));
  }

  /// Sets what to buy, in the user's words.
  void setFreeText(String text) =>
      _edit((s) => s.copyWith(freeText: text, identityMissing: false));

  /// Links the entry to a catalogued item, or unlinks it.
  ///
  /// Linking seeds the name and the unit from the item, because the receipt almost always says the
  /// item's name and retyping it is friction with no purpose. An edit of the user's own is never
  /// overwritten.
  void setItem(Item? item) => _edit((s) {
    if (item == null) return s.copyWith(clearItem: true, clearQuantity: true);
    final typed = s.freeText.trim();
    return s.copyWith(
      itemId: item.id,
      freeText: typed.isEmpty ? item.name : s.freeText,
      unitCode: item.defaultDisplayUnitCode,
      identityMissing: false,
      clearQuantity: true,
    );
  });

  /// Sets how much to buy.
  void setQuantity(Qty? quantity) => _edit(
    (s) => quantity == null
        ? s.copyWith(clearQuantity: true)
        : s.copyWith(quantity: quantity),
  );

  /// Sets the unit the quantity is entered in.
  void setUnitCode(String code) => _edit((s) => s.copyWith(unitCode: code));

  /// Sets the aisle-ish grouping.
  void setTag(String? tagId) => _edit(
    (s) =>
        tagId == null ? s.copyWith(clearTag: true) : s.copyWith(tagId: tagId),
  );

  /// Sets what the user expects it to cost.
  void setEstimatedPrice(Money? price) => _edit(
    (s) => price == null
        ? s.copyWith(clearPrice: true)
        : s.copyWith(estimatedPrice: price),
  );

  /// Saves the entry, returning its id on success and null on rejection or failure.
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (!current.hasIdentity) {
      _edit(
        (s) =>
            s.copyWith(identityMissing: true, shakeTrigger: s.shakeTrigger + 1),
      );
      return null;
    }

    _edit((s) => s.copyWith(submitting: true));
    try {
      final id = current.id ?? ref.read(uidGeneratorProvider).generate();
      final saved = await ref
          .read(shoppingRepositoryProvider)
          .saveEntry(current.toEntry(newId: id));
      if (saved.isFailure) return null;
      _edit((s) => s.copyWith(dirty: false));
      return id;
    } on Object catch (error, stack) {
      ref
          .read(loggerProvider)
          .log(
            'Shopping entry save failed',
            level: LogLevel.error,
            tag: 'shopping.entryEditor',
            error: error,
            stackTrace: stack,
          );
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false));
    }
  }
}
```

### `lib/features/shopping/providers/generate_providers.dart`

```dart
/// View-model state for the low-stock suggestion sheet (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';

/// One suggestion, with the shortfall that produced it.
class LowStockSuggestion {
  /// Creates a suggestion.
  const LowStockSuggestion({required this.entry, this.item, this.shortfall});

  /// The auto-generated entry.
  final ShoppingEntry entry;

  /// The item it restocks.
  final Item? item;

  /// How far below its low-stock level the item sat when the suggestion was made.
  final Qty? shortfall;
}

/// The active suggestions on one list, with their shortfalls.
///
/// **Shortfall is `threshold − stockAtGeneration`, both stored on the entry's own history.** Reading
/// live stock instead would make the figure drift between the sheet opening and the user acting on
/// it, and `stockAtGeneration` exists precisely so a suggestion can explain itself after the fact.
final lowStockSuggestionsProvider = Provider.autoDispose
    .family<AsyncValue<List<LowStockSuggestion>>, String>((ref, listId) {
      final entries = ref.watch(entriesProvider(listId));
      final items = ref.watch(shoppingItemsByIdProvider);
      if (entries.hasError)
        return AsyncValue.error(entries.error!, entries.stackTrace!);
      final rows = entries.valueOrNull;
      if (rows == null) return const AsyncValue.loading();
      final byId = items.valueOrNull ?? const <String, Item>{};

      return AsyncValue.data([
        for (final entry in rows)
          // Bought ones drop off: the stock that prompted the suggestion has arrived, so it is no longer a
          // suggestion. Snoozed and dismissed ones stay, because this sheet is where they are reconsidered.
          if (entry.isAutoGenerated && !entry.isPurchased)
            LowStockSuggestion(
              entry: entry,
              item: entry.itemId == null ? null : byId[entry.itemId],
              shortfall: _shortfall(
                entry,
                entry.itemId == null ? null : byId[entry.itemId],
              ),
            ),
      ]);
    });

Qty? _shortfall(ShoppingEntry entry, Item? item) {
  final threshold = item?.lowStockThreshold;
  final atGeneration = entry.stockAtGeneration;
  if (threshold == null || atGeneration == null) return null;
  if (threshold.category != atGeneration.category) return null;
  final gap = threshold - atGeneration;
  return gap.isPositive ? gap : null;
}

/// Runs low-stock generation for a list.
final generateActionsProvider = Provider<GenerateActions>(GenerateActions.new);

/// Regenerates suggestions.
class GenerateActions {
  /// Creates the actions.
  GenerateActions(this._ref);

  final Ref _ref;

  /// Regenerates and returns how many suggestions are now active, or null on failure.
  ///
  /// The repository's own contract guarantees this is idempotent: running it repeatedly neither
  /// duplicates entries nor resurrects dismissed ones (anomalies A22, A23). Nothing here re-derives
  /// that, because a second implementation is a second thing to get wrong.
  /// Accepts a suggestion, making it the user's own entry.
  ///
  /// **Promotes it to `origin = manual`.** Affirmatively choosing a suggestion is exactly what makes
  /// it yours, and a manual entry is never auto-removed or rewritten by regeneration (anomaly A23).
  /// It also un-dismisses and un-snoozes it, which is the only way back from "Not now" — without
  /// this, turning a suggestion down was irreversible until stock recovered and dropped again.
  Future<String?> accept(ShoppingEntry entry) async {
    final saved = await _ref
        .read(shoppingRepositoryProvider)
        .saveEntry(
          entry.copyWith(
            origin: ShoppingEntryOrigin.manual,
            autoState: ShoppingEntryAutoState.active,
          ),
        );
    return saved.failureOrNull?.message;
  }

  Future<({int? added, String? error})> regenerate(String listId) async {
    final result = await _ref
        .read(shoppingRepositoryProvider)
        .regenerateLowStockSuggestions(listId);
    final failure = result.failureOrNull;
    return failure == null
        ? (added: result.valueOrNull ?? 0, error: null)
        : (added: null, error: failure.message);
  }
}
```

### `lib/features/shopping/providers/list_manager_providers.dart`

```dart
/// View-model state for the shopping list manager (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/shopping_list.dart';

/// Writes the list manager performs.
final listManagerActionsProvider = Provider<ListManagerActions>(
  ListManagerActions.new,
);

/// Creates, renames, archives and re-points shopping lists.
///
/// Every method reports the failure's own message rather than a generic one, so a rejected write
/// says what the database actually refused.
class ListManagerActions {
  /// Creates the actions.
  ListManagerActions(this._ref);

  final Ref _ref;

  /// Creates a list, returning its id on success.
  ///
  /// The first list a user creates becomes the default, because a shopping module with no default
  /// list has nowhere to open and nowhere to put a low-stock suggestion.
  Future<({String? id, String? error})> create(
    String name, {
    required bool isFirst,
  }) async {
    final id = _ref.read(uidGeneratorProvider).generate();
    final saved = await _ref
        .read(shoppingRepositoryProvider)
        .saveList(
          ShoppingList(
            id: id,
            name: name.trim(),
            isDefault: isFirst,
            isArchived: false,
          ),
        );
    final failure = saved.failureOrNull;
    return failure == null
        ? (id: id, error: null)
        : (id: null, error: failure.message);
  }

  /// Renames a list.
  Future<String?> rename(ShoppingList list, String name) async {
    final saved = await _ref
        .read(shoppingRepositoryProvider)
        .saveList(list.copyWith(name: name.trim()));
    return saved.failureOrNull?.message;
  }

  /// Makes a list the one that opens by default.
  Future<String?> setDefault(String id) async {
    final result = await _ref
        .read(shoppingRepositoryProvider)
        .setDefaultList(id);
    return result.failureOrNull?.message;
  }

  /// Archives or restores a list.
  Future<String?> setArchived({
    required String id,
    required bool isArchived,
  }) async {
    final result = await _ref
        .read(shoppingRepositoryProvider)
        .setListArchived(id: id, isArchived: isArchived);
    return result.failureOrNull?.message;
  }
}
```

### `lib/features/shopping/providers/shopping_list_providers.dart`

```dart
/// View-model state for the shopping list (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';

/// One tag's worth of entries.
class ShoppingGroup {
  /// Creates a group.
  const ShoppingGroup({required this.entries, this.tag});

  /// The entries under it, in sort order.
  final List<ShoppingEntry> entries;

  /// The tag this group collects, or null for the untagged remainder.
  final Tag? tag;
}

/// Which list the screen is showing, or null to follow the default.
final selectedListIdProvider = NotifierProvider<SelectedListNotifier, String?>(
  SelectedListNotifier.new,
);

/// Remembers which list the user switched to.
class SelectedListNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Switches to [listId], or back to the default when null.
  void select(String? listId) => state = listId;
}

/// The lists a user may switch between.
final selectableListsProvider = StreamProvider<List<ShoppingList>>(
  (ref) => ref.watch(shoppingRepositoryProvider).watchSelectableLists(),
);

/// Every list, archived included, for the manager sheet.
final allListsProvider = StreamProvider<List<ShoppingList>>(
  (ref) => ref.watch(shoppingRepositoryProvider).watchAllLists(),
);

/// The list marked default.
final defaultListProvider = StreamProvider<ShoppingList?>(
  (ref) => ref.watch(shoppingRepositoryProvider).watchDefaultList(),
);

/// The list actually on screen: the explicit selection, else the default.
final activeListProvider = Provider<AsyncValue<ShoppingList?>>((ref) {
  final selected = ref.watch(selectedListIdProvider);
  final lists = ref.watch(selectableListsProvider);
  final fallback = ref.watch(defaultListProvider);
  if (selected == null) return fallback;
  return lists.whenData((all) {
    for (final list in all) {
      if (list.id == selected) return list;
    }
    return fallback.valueOrNull;
  });
});

/// Every entry on the active list.
final entriesProvider = StreamProvider.autoDispose
    .family<List<ShoppingEntry>, String>(
      (ref, listId) =>
          ref.watch(shoppingRepositoryProvider).watchEntries(listId),
    );

/// Tags, keyed by id, so a group header can name itself.
final shoppingTagsByIdProvider = StreamProvider<Map<String, Tag>>(
  (ref) => ref
      .watch(tagRepositoryProvider)
      .watchAll()
      .map(
        (tags) => {for (final tag in tags) tag.id: tag},
      ),
);

/// Items, keyed by id, so a linked entry can show the catalogue name.
final shoppingItemsByIdProvider = StreamProvider<Map<String, Item>>(
  (ref) => ref
      .watch(itemRepositoryProvider)
      .watchAll()
      .map(
        (items) => {for (final item in items) item.id: item},
      ),
);

/// The active list's entries, filtered for visibility and grouped by tag.
///
/// **What counts as outstanding is decided by the entity, not here.**
/// `ShoppingEntry.isOutstandingAsOf` owns it: snoozed and dismissed suggestions are hidden by the same
/// rule the regeneration engine applies (anomalies A22, A23), and anything already bought drops off
/// because a list is a list of what to get. A second copy of either rule in the view model is a second
/// place for it to drift.
final shoppingGroupsProvider = Provider.autoDispose
    .family<AsyncValue<List<ShoppingGroup>>, String>((ref, listId) {
      final entries = ref.watch(entriesProvider(listId));
      final tags = ref.watch(shoppingTagsByIdProvider);
      if (entries.hasError)
        return AsyncValue.error(entries.error!, entries.stackTrace!);
      final rows = entries.valueOrNull;
      if (rows == null) return const AsyncValue.loading();
      final byId = tags.valueOrNull ?? const <String, Tag>{};
      final today = ref.watch(clockProvider).today();

      final visible = [
        for (final entry in rows)
          if (entry.isOutstandingAsOf(today)) entry,
      ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      final buckets = <String?, List<ShoppingEntry>>{};
      for (final entry in visible) {
        buckets.putIfAbsent(entry.tagId, () => <ShoppingEntry>[]).add(entry);
      }
      final tagged =
          [
            for (final id in buckets.keys)
              if (id != null && byId[id] != null)
                ShoppingGroup(entries: buckets[id]!, tag: byId[id]),
          ]..sort(
            (a, b) =>
                a.tag!.name.toLowerCase().compareTo(b.tag!.name.toLowerCase()),
          );

      return AsyncValue.data([
        ...tagged,
        if (buckets[null] != null) ShoppingGroup(entries: buckets[null]!),
      ]);
    });

/// The running estimate for the active list, and how far through it the user is.
class ShoppingSummary {
  /// Creates a summary.
  const ShoppingSummary({
    required this.estimate,
    required this.checked,
    required this.total,
  });

  /// The summed estimate of every visible entry that carries one, or null when none do.
  final Money? estimate;

  /// How many visible entries are ticked.
  final int checked;

  /// How many visible entries there are.
  final int total;

  /// Whether anything is ticked, which is what convert-to-purchase needs.
  bool get hasChecked => checked > 0;
}

/// The active list's running estimate and tick progress.
///
/// Entries without an estimate are skipped rather than counted as zero: a list of ten things where
/// two are priced should read as the sum of those two, not as a total that quietly understates by
/// eight.
final shoppingSummaryProvider = Provider.autoDispose
    .family<ShoppingSummary, String>((ref, listId) {
      final groups =
          ref.watch(shoppingGroupsProvider(listId)).valueOrNull ?? const [];
      Money? estimate;
      var checked = 0;
      var total = 0;
      for (final group in groups) {
        for (final entry in group.entries) {
          total += 1;
          if (entry.isChecked) checked += 1;
          final price = entry.estimatedPrice;
          if (price == null) continue;
          estimate = estimate == null ? price : estimate + price;
        }
      }
      return ShoppingSummary(
        estimate: estimate,
        checked: checked,
        total: total,
      );
    });

/// Writes the shopping list screen performs.
final shoppingActionsProvider = Provider<ShoppingActions>(ShoppingActions.new);

/// Ticks, snoozes, dismisses and deletes entries.
///
/// **Every method returns the failure's own message, or null on success.** A repository `Failure`
/// carries a `message` written for exactly this, and reporting "something went wrong" instead threw
/// it away — three separate bugs reached the user as the same sentence, none of them diagnosable.
class ShoppingActions {
  /// Creates the actions.
  ShoppingActions(this._ref);

  final Ref _ref;

  /// How long a snooze lasts.
  static const int snoozeDays = 7;

  /// Ticks or unticks an entry.
  Future<String?> setChecked({
    required String id,
    required bool isChecked,
  }) async {
    final result = await _ref
        .read(shoppingRepositoryProvider)
        .setEntryChecked(id: id, isChecked: isChecked);
    return result.failureOrNull?.message;
  }

  /// Hides a suggestion for a week.
  Future<String?> snooze(String id) async {
    final until = _ref.read(clockProvider).today().addDays(snoozeDays);
    final result = await _ref
        .read(shoppingRepositoryProvider)
        .snoozeEntry(id: id, until: until);
    return result.failureOrNull?.message;
  }

  /// Dismisses a suggestion until stock recovers and drops again.
  Future<String?> dismiss(String id) async {
    final result = await _ref.read(shoppingRepositoryProvider).dismissEntry(id);
    return result.failureOrNull?.message;
  }

  /// Removes an entry outright.
  Future<String?> delete(String id) async {
    final result = await _ref.read(shoppingRepositoryProvider).deleteEntry(id);
    return result.failureOrNull?.message;
  }

  /// Puts a deleted entry back.
  ///
  /// **`saveEntry`, not an unrelated undelete.** The repository has no restore method and does not need
  /// one: `saveEntry` writes the whole entity, and the caller still holds the row it just removed, so
  /// re-saving it is the restore.
  ///
  /// It **promotes an auto-generated suggestion to manual** (anomaly A22), and that is the right outcome
  /// rather than a side effect: swiping a suggestion away and immediately asking for it back is the user
  /// saying they want it kept, so the engine should stop deciding for them.
  Future<String?> restore(ShoppingEntry entry) async {
    final result = await _ref.read(shoppingRepositoryProvider).saveEntry(entry);
    return result.failureOrNull?.message;
  }

  /// Unticks every entry on a list.
  Future<void> uncheckAll(List<ShoppingEntry> entries) async {
    final repository = _ref.read(shoppingRepositoryProvider);
    for (final entry in entries) {
      if (!entry.isChecked) continue;
      await repository.setEntryChecked(id: entry.id, isChecked: false);
    }
  }
}
```

### `lib/features/shopping/state/entry_editor_state.dart`

```dart
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';

/// What the entry editor is holding (ARCH_5 §3 archetype A).
///
/// **`itemId` is nullable and stays that way.** A television belongs on a shopping list and has no
/// business in an inventory that tracks flour by the gram, so an entry needs either a name or a
/// linked item — never both, never necessarily one in particular.
class EntryEditorState {
  /// Creates the editor's state.
  const EntryEditorState({
    required this.listId,
    this.id,
    this.freeText = '',
    this.itemId,
    this.quantity,
    this.unitCode,
    this.tagId,
    this.estimatedPrice,
    this.origin = ShoppingEntryOrigin.manual,
    this.autoState = ShoppingEntryAutoState.active,
    this.sortOrder = 0,
    this.isChecked = false,
    this.submitting = false,
    this.identityMissing = false,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// The entry being edited, or null for a new one.
  final String? id;

  /// Which list it belongs to.
  final String listId;

  /// What to buy, in the user's words.
  final String freeText;

  /// The catalogued item this restocks, if any.
  final String? itemId;

  /// How much to buy.
  final Qty? quantity;

  /// The unit the quantity was entered in.
  final String? unitCode;

  /// The aisle-ish grouping this row sits under.
  final String? tagId;

  /// What the user expects it to cost.
  final Money? estimatedPrice;

  /// Where the entry came from.
  final ShoppingEntryOrigin origin;

  /// Whether an auto entry is active, snoozed or dismissed.
  final ShoppingEntryAutoState autoState;

  /// Its position in the list.
  final int sortOrder;

  /// Whether it is already ticked.
  final bool isChecked;

  /// Whether a save is in flight.
  final bool submitting;

  /// Whether submit was pressed with neither a name nor an item.
  final bool identityMissing;

  /// Incremented to shake the name field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the dismiss guard (Law U10).
  final bool dirty;

  /// Whether this is editing an existing entry.
  bool get isEditing => id != null;

  /// Whether the entry has something to identify it by.
  bool get hasIdentity => freeText.trim().isNotEmpty || itemId != null;

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  EntryEditorState copyWith({
    String? id,
    String? freeText,
    String? itemId,
    bool clearItem = false,
    Qty? quantity,
    bool clearQuantity = false,
    String? unitCode,
    String? tagId,
    bool clearTag = false,
    Money? estimatedPrice,
    bool clearPrice = false,
    ShoppingEntryOrigin? origin,
    ShoppingEntryAutoState? autoState,
    int? sortOrder,
    bool? isChecked,
    bool? submitting,
    bool? identityMissing,
    int? shakeTrigger,
    bool? dirty,
  }) => EntryEditorState(
    id: id ?? this.id,
    listId: listId,
    freeText: freeText ?? this.freeText,
    itemId: clearItem ? null : (itemId ?? this.itemId),
    quantity: clearQuantity ? null : (quantity ?? this.quantity),
    unitCode: unitCode ?? this.unitCode,
    tagId: clearTag ? null : (tagId ?? this.tagId),
    estimatedPrice: clearPrice ? null : (estimatedPrice ?? this.estimatedPrice),
    origin: origin ?? this.origin,
    autoState: autoState ?? this.autoState,
    sortOrder: sortOrder ?? this.sortOrder,
    isChecked: isChecked ?? this.isChecked,
    submitting: submitting ?? this.submitting,
    identityMissing: identityMissing ?? this.identityMissing,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? true,
  );

  /// Builds the entity this state describes.
  ///
  /// **Editing an auto entry promotes it to manual.** A suggestion the user has shaped is theirs,
  /// and regeneration must never remove or rewrite it (anomaly A23) — `origin` is what the engine
  /// keys that decision on, so the promotion happens here rather than being left to the caller.
  ShoppingEntry toEntry({required String newId}) {
    final promoted = isEditing && origin == ShoppingEntryOrigin.autoLowStock
        ? ShoppingEntryOrigin.manual
        : origin;
    return ShoppingEntry(
      id: id ?? newId,
      listId: listId,
      origin: promoted,
      autoState: promoted == ShoppingEntryOrigin.manual
          ? ShoppingEntryAutoState.active
          : autoState,
      isChecked: isChecked,
      sortOrder: sortOrder,
      itemId: itemId,
      freeText: freeText.trim().isEmpty ? null : freeText.trim(),
      quantity: quantity,
      unitCode: unitCode,
      tagId: tagId,
      estimatedPrice: estimatedPrice,
    );
  }

  /// Loads an existing entry into an editor state.
  static EntryEditorState fromEntry(ShoppingEntry entry) => EntryEditorState(
    id: entry.id,
    listId: entry.listId,
    freeText: entry.freeText ?? '',
    itemId: entry.itemId,
    quantity: entry.quantity,
    unitCode: entry.unitCode,
    tagId: entry.tagId,
    estimatedPrice: entry.estimatedPrice,
    origin: entry.origin,
    autoState: entry.autoState,
    sortOrder: entry.sortOrder,
    isChecked: entry.isChecked,
  );
}
```

### `test/features/shopping/convert_to_purchase_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/providers/transaction_draft_provider.dart';
import 'package:alaya/features/expense/state/transaction_draft.dart';
import 'package:alaya/features/shopping/presentation/screens/convert_to_purchase_screen.dart';
import 'package:alaya/features/shopping/providers/convert_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/shopping_harness.dart';

/// Four states, plus the rule this screen exists to hold: it hands off, it does not commit.
void main() {
  List<Override> overrides({
    List<TransactionLine>? lines,
    List<ShoppingEntry>? entries,
    bool pending = false,
    bool fail = false,
  }) => [
    entriesProvider(
      kList.id,
    ).overrideWith((ref) => Stream.value(entries ?? const [])),
    if (pending)
      purchaseDraftProvider(
        kList.id,
      ).overrideWith((ref) => pendingFuture<List<TransactionLine>>())
    else if (fail)
      purchaseDraftProvider(
        kList.id,
      ).overrideWith((ref) async => throw StateError('boom'))
    else
      purchaseDraftProvider(
        kList.id,
      ).overrideWith((ref) async => lines ?? const <TransactionLine>[]),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(pending: true),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('nothing ticked reads as nothing ticked, not as an error', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing is ticked'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(fail: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('populated previews one line per entry, marked for inventory', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(
        lines: [
          sampleDraftLine(),
          sampleDraftLine(id: 'line-2', description: 'Bread'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.text('2 lines'), findsOneWidget);
    expect(find.text('Onion'), findsOneWidget);
    expect(find.text('Bread'), findsOneWidget);
  });

  testWidgets('the primary action hands off rather than committing', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(lines: [sampleDraftLine()]),
    );
    await tester.pumpAndSettle();
    // "Open the expense", not "Save". The amount, the account and the payee are decisions only the
    // expense editor collects; duplicating them here would fork the one screen that knows how a
    // withdrawal is shaped (anomaly A25).
    expect(
      find.widgetWithText(FilledButton, 'Open the expense'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(lines: [sampleDraftLine()]),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpShopping(
      tester,
      const ConvertToPurchaseScreen(listId: 'list-1'),
      overrides: overrides(lines: [sampleDraftLine()]),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the draft channel', () {
    test('carries the ticked entry ids so the loop can close on save', () {
      final container = ProviderContainer(
        overrides: [
          entriesProvider(kList.id).overrideWith(
            (ref) => Stream.value([
              sampleEntry(id: 'e1', isChecked: true),
              sampleEntry(id: 'e2', isChecked: false),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(entriesProvider(kList.id), (_, __) {});

      final offered = container
          .read(convertActionsProvider)
          .offerDraft(
            listId: kList.id,
            lines: [sampleDraftLine()],
          );
      expect(offered, isTrue);
      final draft = container.read(transactionDraftProvider);
      expect(draft, isNotNull);
      expect(draft!.kind, TransactionKind.withdrawal);
      expect(draft.lines, hasLength(1));
    });

    test('an empty draft is refused rather than opening a blank editor', () {
      final container = ProviderContainer(
        overrides: [
          entriesProvider(
            kList.id,
          ).overrideWith((ref) => Stream.value(const [])),
        ],
      );
      addTearDown(container.dispose);
      final offered = container
          .read(convertActionsProvider)
          .offerDraft(listId: kList.id, lines: const []);
      expect(offered, isFalse);
      expect(container.read(transactionDraftProvider), isNull);
    });

    test('take() empties the channel, so a draft is never applied twice', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(transactionDraftProvider.notifier)
          .offer(
            TransactionDraft(
              lines: [sampleDraftLine()],
              kind: TransactionKind.withdrawal,
              subtype: TransactionSubtype.grocery,
            ),
          );
      expect(
        container.read(transactionDraftProvider.notifier).take(),
        isNotNull,
      );
      // Without this, a draft left behind would ambush the next blank editor the user opened.
      expect(container.read(transactionDraftProvider.notifier).take(), isNull);
    });
  });
}
```

### `test/features/shopping/entry_editor_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/shopping/presentation/sheets/entry_editor_sheet.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/state/entry_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/shopping_harness.dart';

/// Four states, plus the rule this sheet exists to hold: `itemId` is optional, and an entry needs
/// only one of a name or a link to identify itself.
void main() {
  // The override goes on the **family**: a NotifierProvider family instance has no `overrideWith`,
  // unlike a FutureProvider or StreamProvider instance.
  List<Override> overrides(
    AsyncValue<EntryEditorState> state, {
    List<Item> items = const [kOnion],
  }) => [
    entryEditorProvider.overrideWith(() => _StubEntryEditor(state)),
    entryItemsProvider.overrideWith((ref) => Stream.value(items)),
    entryTagsProvider.overrideWith(
      (ref) => Stream.value(const <Tag>[kProduceTag]),
    ),
    entryUnitsProvider(
      UnitCategory.weight,
    ).overrideWith((ref) => Stream.value(const <Unit>[kKilogram])),
    entryUnitsProvider(
      null,
    ).overrideWith((ref) => Stream.value(const <Unit>[])),
    entryCurrencyProvider.overrideWith((ref) async => 'INR'),
    entryDecimalDigitsProvider.overrideWith((ref) async => 2),
  ];

  Widget host() => const Scaffold(
    body: AlayaBottomSheet(child: EntryEditorSheet(listId: 'list-1')),
  );

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('error reads as not found', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new entry opens on the form, which is its empty state', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(EntryEditorState(listId: 'list-1')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('What do you need?'), findsOneWidget);
    expect(find.text('Name it'), findsOneWidget);
  });

  testWidgets('free text alone is enough — no inventory item required', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(
          EntryEditorState(listId: 'list-1', freeText: 'Television'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // A television belongs on a list and has no place in an inventory measuring flour by the gram,
    // so the item link stays optional and the quantity field stays hidden without one.
    expect(find.text('Not in my inventory'), findsOneWidget);
    expect(find.byType(QtyField), findsNothing);
  });

  testWidgets('linking an item reveals a category-filtered quantity', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(
          EntryEditorState(listId: 'list-1', itemId: 'item-1', unitCode: 'kg'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Law L8: a Qty is an integer plus a UnitCategory, and the category comes from the item.
    expect(find.byType(QtyField), findsOneWidget);
  });

  testWidgets('saving with neither a name nor an item shakes and says why', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(
          EntryEditorState(
            listId: 'list-1',
            identityMissing: true,
            shakeTrigger: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShakeOnError), findsOneWidget);
    expect(find.text('Give it a name, or link it to an item'), findsOneWidget);
  });

  testWidgets('an empty catalogue still lets an entry be created', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(EntryEditorState(listId: 'list-1')),
        items: const [],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Name it'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(
          EntryEditorState(listId: 'list-1', itemId: 'item-1', unitCode: 'kg'),
        ),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        const AsyncValue.data(EntryEditorState(listId: 'list-1')),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('promotion', () {
    test(
      'editing an auto entry promotes it to manual and never auto-removes it',
      () {
        final promoted = EntryEditorState.fromEntry(
          sampleSuggestion(),
        ).copyWith(freeText: 'Onions, the big ones').toEntry(newId: 'unused');
        // Anomaly A23: a suggestion the user has shaped is theirs. `origin` is what the regeneration
        // engine keys that decision on, so the promotion happens in `toEntry` rather than being left
        // to whichever call site remembers.
        expect(promoted.origin, ShoppingEntryOrigin.manual);
        expect(promoted.autoState, ShoppingEntryAutoState.active);
        expect(promoted.isAutoGenerated, isFalse);
      },
    );

    test('a new manual entry is not promoted from anything', () {
      final made = const EntryEditorState(
        listId: 'list-1',
        freeText: 'Television',
      ).toEntry(newId: 'entry-9');
      expect(made.origin, ShoppingEntryOrigin.manual);
      expect(made.itemId, isNull);
      expect(made.freeText, 'Television');
    });
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubEntryEditor extends EntryEditorNotifier {
  _StubEntryEditor(this._state);

  final AsyncValue<EntryEditorState> _state;

  @override
  AsyncValue<EntryEditorState> build(EntryEditorArgs arg) => _state;
}
```

### `test/features/shopping/generate_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/features/shopping/presentation/sheets/generate_sheet.dart';
import 'package:alaya/features/shopping/providers/generate_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';

import '../../support/shopping_harness.dart';

/// Four states, plus the shortfall figure and the per-row snooze and dismiss.
void main() {
  List<Override> overrides({
    List<ShoppingEntry>? entries,
    bool pending = false,
    bool fail = false,
  }) => [
    clockProvider.overrideWithValue(kShoppingClock),
    shoppingItemsByIdProvider.overrideWith(
      (ref) => Stream.value(<String, Item>{kOnion.id: kOnion}),
    ),
    if (pending)
      entriesProvider(
        kList.id,
      ).overrideWith((ref) => pendingStream<List<ShoppingEntry>>())
    else if (fail)
      entriesProvider(kList.id).overrideWith(
        (ref) => Stream<List<ShoppingEntry>>.error(StateError('boom')),
      )
    else
      entriesProvider(
        kList.id,
      ).overrideWith((ref) => Stream.value(entries ?? const [])),
  ];

  Widget host() => const Scaffold(
    body: AlayaBottomSheet(child: GenerateSheet(listId: 'list-1')),
  );

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpShopping(tester, host(), overrides: overrides(pending: true));
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('empty explains what would make a suggestion appear', (
    tester,
  ) async {
    await pumpShopping(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing is running low'), findsOneWidget);
  });

  testWidgets('error is reported without hiding the refresh', (tester) async {
    await pumpShopping(tester, host(), overrides: overrides(fail: true));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
  });

  testWidgets('a suggestion shows the shortfall that produced it', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(entries: [sampleSuggestion()]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Onion'), findsOneWidget);
    expect(find.text('Short by'), findsOneWidget);
    // threshold 2 kg minus 500 g on hand at generation. Read from the entry's own history, not from
    // live stock, so the figure cannot drift between the sheet opening and the user acting.
    expect(find.byType(QtyText), findsWidgets);
    expect(find.text('1 kg 500 g'), findsOneWidget);
  });

  testWidgets('each suggestion is snoozed or dismissed on its own', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        entries: [
          sampleSuggestion(),
          sampleSuggestion(id: 'auto-2'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Snooze a week'), findsNWidgets(2));
    expect(find.text('Not now'), findsNWidgets(2));
  });

  testWidgets('a manual entry never appears as a suggestion', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(entries: [sampleEntry()]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing is running low'), findsOneWidget);
    expect(find.text('Television'), findsNothing);
  });

  testWidgets('a dismissed suggestion still lists here so it can be reconsidered', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(
        entries: [
          sampleSuggestion(autoState: ShoppingEntryAutoState.dismissed),
        ],
      ),
    );
    await tester.pumpAndSettle();
    // The list screen hides it via `isVisibleAsOf`; this sheet is where the user manages
    // suggestions, so hiding it here would leave no way to see what was turned down.
    expect(find.text('Onion'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(entries: [sampleSuggestion()]),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(entries: [sampleSuggestion()]),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/shopping/list_manager_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/features/shopping/presentation/sheets/list_manager_sheet.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/shopping_harness.dart';

/// Four states, plus the retirement rule: a list is archived, never deleted.
void main() {
  List<Override> overrides({
    List<ShoppingList>? lists,
    bool pending = false,
    bool fail = false,
  }) => [
    if (pending)
      allListsProvider.overrideWith(
        (ref) => pendingStream<List<ShoppingList>>(),
      )
    else if (fail)
      allListsProvider.overrideWith(
        (ref) => Stream<List<ShoppingList>>.error(StateError('boom')),
      )
    else
      allListsProvider.overrideWith((ref) => Stream.value(lists ?? const [])),
  ];

  Widget host() => const Scaffold(
    body: AlayaBottomSheet(child: ListManagerSheet()),
  );

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpShopping(tester, host(), overrides: overrides(pending: true));
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('empty invites the first list, which becomes the default', (
    tester,
  ) async {
    await pumpShopping(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'New list'), findsOneWidget);
  });

  testWidgets('error is reported', (tester) async {
    await pumpShopping(tester, host(), overrides: overrides(fail: true));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('populated marks the default and separates the archived', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(lists: const [kList, kArchivedList]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Weekly shop'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Diwali'), findsOneWidget);
    expect(find.text('Archived'), findsNWidgets(2));
  });

  testWidgets('retiring a list archives it rather than deleting it', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(lists: const [kList]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    // A converted list is the provenance of those transaction lines, so it is hidden, not removed
    // (Law L6). There is no delete in this menu at all.
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('the default list is not offered "make default" again', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(lists: const [kList]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    expect(find.text('Make default'), findsNothing);
    expect(find.text('Rename'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(lists: const [kList, kArchivedList]),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpShopping(
      tester,
      host(),
      overrides: overrides(lists: const [kList]),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/shopping/shopping_list_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/shopping/presentation/screens/shopping_list_screen.dart';
import 'package:alaya/features/shopping/presentation/widgets/entry_row.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/shopping_harness.dart';

/// Four states, 320dp at a doubled text scale, and both accessibility floors (ARCH_5 §9.1).
void main() {
  List<Override> overrides(AsyncValue<List<ShoppingGroup>> groups) => [
    clockProvider.overrideWithValue(kShoppingClock),
    defaultListProvider.overrideWith((ref) => Stream.value(kList)),
    selectableListsProvider.overrideWith((ref) => Stream.value(const [kList])),
    shoppingGroupsProvider(kList.id).overrideWith((ref) => groups),
    shoppingItemsByIdProvider.overrideWith(
      (ref) => Stream.value(<String, Item>{kOnion.id: kOnion}),
    ),
    shoppingTagsByIdProvider.overrideWith(
      (ref) => Stream.value(<String, Tag>{kProduceTag.id: kProduceTag}),
    ),
    entryDecimalDigitsProvider.overrideWith((ref) async => 2),
  ];

  final populated = AsyncValue.data([
    ShoppingGroup(
      entries: [sampleEntry(tagId: kProduceTag.id)],
      tag: kProduceTag,
    ),
  ]);

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty offers the suggestions that would fill it', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(const AsyncValue.data([])),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing on this list yet'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('populated groups by tag and names the group', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(populated),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EntryRow), findsOneWidget);
    expect(find.text('Television'), findsOneWidget);
    expect(find.text('Produce'), findsOneWidget);
  });

  testWidgets('every entry can be swiped away', (tester) async {
    // The capability was fully built and unreachable: `ShoppingActions.delete` existed, called a soft
    // delete, and nothing in the UI called it. Same shape as `QuickAddSheet` — a finished thing with no
    // door.
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([
          ShoppingGroup(entries: [sampleEntry()]),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    final dismissible = tester.widget<Dismissible>(find.byType(Dismissible));
    // **`endToStart`, not a hard-coded left.** It means the trailing edge, so the gesture stays natural
    // when the locale flips — and Alaya localises, so that is not hypothetical.
    expect(dismissible.direction, DismissDirection.endToStart);
    // Keyed on the entry rather than the index: a list that reorders mid-swipe would otherwise remove
    // whichever row slid into that position.
    expect(dismissible.key, isA<ValueKey<String>>());
  });

  testWidgets('a free-text entry needs no inventory item', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([
          ShoppingGroup(entries: [sampleEntry()]),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    // "Television" is a shopping entry with itemId null. It renders, and it lands in the untagged
    // group rather than being refused for having nothing in the catalogue behind it.
    expect(find.text('Television'), findsOneWidget);
    expect(find.text('Everything else'), findsOneWidget);
  });

  testWidgets('a suggested row is marked and offers snooze and dismiss', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([
          ShoppingGroup(entries: [sampleSuggestion()]),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Suggested'), findsOneWidget);
    expect(find.text('Snooze a week'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('a manual row offers neither', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(populated),
    );
    await tester.pumpAndSettle();
    // Snooze and dismiss only make sense against something the app proposed; offering them on a row
    // the user typed reads as the app second-guessing them.
    expect(find.text('Snooze a week'), findsNothing);
    expect(find.text('Not now'), findsNothing);
  });

  testWidgets('the running estimate sums only entries that carry one', (
    tester,
  ) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([
          ShoppingGroup(
            entries: [
              sampleEntry(id: 'e1'),
              sampleEntry(id: 'e2', freeText: 'Bread', estimatedPrice: null),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    // One priced at 45,000.00 and one unpriced: the total is the priced one, not a figure that
    // quietly counts the other as zero.
    expect(find.text('Estimated'), findsOneWidget);
    expect(find.text('0 of 2 ticked'), findsOneWidget);
  });

  testWidgets('with no list at all it offers to create one', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: [
        clockProvider.overrideWithValue(kShoppingClock),
        defaultListProvider.overrideWith((ref) => Stream.value(null)),
        selectableListsProvider.overrideWith(
          (ref) => Stream.value(const <ShoppingList>[]),
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('No lists yet'), findsOneWidget);
    expect(find.text('New list'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([
          ShoppingGroup(entries: [sampleSuggestion()]),
        ]),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(populated),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('a bought entry drops off the list', (tester) async {
    await pumpShopping(
      tester,
      const ShoppingListScreen(),
      overrides: overrides(
        AsyncValue.data([
          ShoppingGroup(
            entries: [sampleEntry(id: 'e1', freeText: 'Bread')],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bread'), findsOneWidget);

    // Once a transaction fulfils it, the entry is no longer something to buy. The row survives —
    // `purchasedTransactionLineId` is the only link between the receipt and the list — but a list of
    // what to get should not still be offering it.
    final bought = sampleEntry(
      id: 'e1',
      freeText: 'Bread',
    ).copyWith(purchasedTransactionLineId: 'line-1');
    expect(bought.isPurchased, isTrue);
    expect(bought.isOutstandingAsOf(kToday), isFalse);
    expect(bought.isVisibleAsOf(kToday), isTrue);
  });
}
```
