import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/trash/trash_port.dart';
import 'package:alaya/features/trash/providers/trash_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';

/// Settings › Data › Trash (ARCH_5 §3 archetype C, outside the shell).
///
/// **A ledger list rather than a catalogue, because the trash is a record of events.** Things arrive here in the
/// order they were deleted and leave in the order they expire; there is no user axis to group by, which is what
/// separates C from D.
///
/// **Thirty-day retention, stated per row** (ARCH_3 §4.2). A trash that silently empties is one people stop
/// trusting with the thing they deleted by accident, so every row says when it goes.
///
/// **Empty now is the only place a hard delete is reachable from**, and it is confirmed. Purge is the single hard
/// delete in the codebase; this screen is the only door to it.
class TrashScreen extends ConsumerWidget {
  /// Creates the screen.
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final all = ref.watch(trashProvider);
    final filter = ref.watch(trashFilterProvider);
    final rows = ref.watch(filteredTrashProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.trashTitle),
        actions: [
          if (all.valueOrNull?.isNotEmpty ?? false)
            TextButton(
              onPressed: () => _emptyNow(context, ref, strings),
              child: Text(strings.trashEmptyNow, style: AlayaTypography.button),
            ),
        ],
      ),
      body: all.when(
        loading: () => AlayaListSkeleton(label: strings.trashLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(trashProvider),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return EmptyState(
              title: strings.trashEmptyTitle,
              body: strings.trashEmptyBody,
              icon: Icons.delete_outline,
            );
          }
          return Column(
            children: [
              // Active filters stay visible as removable chips, per archetype C — a filter you cannot see is the
              // bug report that begins "my deleted items disappeared".
              if (filter.isNotEmpty)
                FilterChipBar(
                  filters: [
                    for (final kind in filter)
                      ActiveFilter(
                        label: _kindLabel(strings, kind),
                        onRemove: () =>
                            ref.read(trashFilterProvider.notifier).toggle(kind),
                      ),
                  ],
                  clearAllLabel: strings.actionClear,
                  onClearAll: ref.read(trashFilterProvider.notifier).clear,
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.screenEdge,
                  vertical: AlayaSpacing.xs,
                ),
                child: Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    for (final kind in TrashKind.values)
                      if (entries.any((entry) => entry.kind == kind))
                        FilterChip(
                          label: Text(
                            _kindLabel(strings, kind),
                            style: AlayaTypography.button,
                          ),
                          selected: filter.contains(kind),
                          onSelected: (_) => ref
                              .read(trashFilterProvider.notifier)
                              .toggle(kind),
                        ),
                  ],
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? EmptyState(
                        title: strings.trashNoMatchTitle,
                        body: strings.trashNoMatchBody,
                        icon: Icons.filter_alt_off_outlined,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(
                          bottom: AlayaSpacing.xxxl,
                        ),
                        itemCount: rows.length,
                        itemBuilder: (context, index) =>
                            _TrashRow(entry: rows[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _emptyNow(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.trashEmptyNowConfirmTitle,
      // **The only hard delete a user can reach**, so the body says it plainly: this is not the trash, it is gone.
      body: strings.trashEmptyNowConfirmBody,
      confirmLabel: strings.trashEmptyNow,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final controller = ref.read(trashControllerProvider.notifier);
    final ok = await controller.purgeAll();
    if (!context.mounted) return;
    ok
        ? showResultSnack(
            context,
            message: strings.trashPurged(controller.lastPurged),
          )
        : showFailureSnack(context, message: strings.trashPurgeFailed);
  }

  String _kindLabel(AlayaStrings strings, TrashKind kind) => switch (kind) {
    TrashKind.transaction => strings.trashKindTransaction,
    TrashKind.item => strings.trashKindItem,
    TrashKind.asset => strings.trashKindAsset,
    TrashKind.shoppingList => strings.trashKindShoppingList,
    TrashKind.recurringTemplate => strings.trashKindRecurring,
    TrashKind.tag => strings.trashKindTag,
    TrashKind.payee => strings.trashKindPayee,
  };
}

/// One deleted thing.
class _TrashRow extends ConsumerWidget {
  const _TrashRow({required this.entry});

  final TrashEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return ListTile(
      title: Text(entry.label, style: AlayaTypography.cardTitle),
      // **Two lines, not one Row of three pieces.** A `ListTile` gives its subtitle whatever the trailing widget
      // leaves — 142dp at a doubled text scale — and "Deleted", a date and a retention note will not share that.
      // The layout test caught it before a device did.
      isThreeLine: true,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                strings.trashDeletedOn,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              const SizedBox(width: AlayaSpacing.xxs),
              Flexible(
                child: DateText(
                  DateKey.fromDateTime(
                    DateTime.fromMillisecondsSinceEpoch(
                      entry.deletedAtUtcMillis,
                      isUtc: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Text(
            // Says when it goes, because a trash that silently empties is one people stop trusting with the
            // thing they deleted by accident.
            strings.trashGoesOn,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],
      ),
      // **An icon, not a text button.** "Restore" at a doubled scale took most of the row's width and left the
      // subtitle unreadable. The tooltip and the `Semantics` label carry the word for anyone who needs it, which
      // is what ARCH_5 §2.7 asks of an icon that is not one of the six that stand alone.
      trailing: IconButton(
        onPressed: () => _restore(context, ref, strings),
        tooltip: strings.trashRestore,
        icon: Icon(
          Icons.restore_from_trash_outlined,
          size: AlayaIconSize.md,
          color: semantic.muted,
        ),
      ),
      onLongPress: () => _purge(context, ref, strings),
    );
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final ok = await ref.read(trashControllerProvider.notifier).restore(entry);
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.trashRestored)
        : showFailureSnack(context, message: strings.trashRestoreFailed);
  }

  Future<void> _purge(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.trashPurgeConfirmTitle,
      body: strings.trashPurgeConfirmBody,
      confirmLabel: strings.trashPurgeOne,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(trashControllerProvider.notifier).purge(entry);
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.trashPurgedOne)
        : showFailureSnack(context, message: strings.trashPurgeFailed);
  }
}
