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
