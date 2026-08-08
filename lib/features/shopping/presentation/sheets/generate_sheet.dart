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
