import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/features/split/presentation/sheets/split_group_detail_sheet.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// The groups a split can be filed under — a tab, not a screen.
///
/// **Was `/split/groups`.** A list reached from a tab, containing rows that opened another screen: three
/// levels for content that fits in one. It is a tab now, and a row opens a sheet.
///
/// **Archived groups are shown, greyed, not hidden.** Archiving keeps a group's history and its balances
/// and only removes it from the pickers — the distinction ARCH_3 §4 draws against deleting. Hiding them
/// here would make "where did my flatmates group go" unanswerable from the one place that exists to
/// answer it.
///
/// **Most groups are made on the bill screen rather than here.** Once two people on a split are named,
/// *"Save these 2 as a group"* turns the split you already have into a reusable one — which is what fixed
/// "it is very hard to create groups". This list is where they are reviewed, renamed and archived; the
/// button stays because a group made in advance is still a legitimate thing to want.
class SplitGroupsList extends ConsumerWidget {
  /// Creates the list.
  const SplitGroupsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final groups = ref.watch(splitAllGroupsProvider);

    return groups.when(
      loading: () => AlayaListSkeleton(label: strings.loadingLabel),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(splitAllGroupsProvider),
      ),
      data: (rows) => ListView(
        padding: const EdgeInsets.fromLTRB(
          AlayaSpacing.screenEdge,
          AlayaSpacing.md,
          AlayaSpacing.screenEdge,
          AlayaSpacing.xxxl,
        ),
        children: [
          // **Offered above the list rather than as a floating button.** The tab shares its screen with
          // two others and a FAB belongs to the screen, not to one tab — a create-group button hovering
          // over the balances tab would be the wrong action in the wrong place.
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.splitGroupNew),
            icon: const Icon(Icons.group_add_outlined, size: AlayaIconSize.md),
            label: Text(strings.splitGroupNew),
          ),
          const SizedBox(height: AlayaSpacing.md),

          if (rows.isEmpty)
            EmptyState(
              title: strings.splitNoGroupsTitle,
              body: strings.splitNoGroupsBody,
              icon: Icons.groups_outlined,
            )
          else
            for (final group in rows) _GroupRow(group: group),
        ],
      ),
    );
  }
}

class _GroupRow extends ConsumerWidget {
  const _GroupRow({required this.group});

  final SplitGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return AlayaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.sm,
        vertical: AlayaSpacing.xs,
      ),
      onTap: () => SplitGroupDetailSheet.show(context, groupId: group.id),
      // **A `Wrap`, not a `Row`, and this was a live bug.** A name beside up to two `StatusChip`s is three
      // fixed-width children that cannot shrink — the same shape that overran the split home screen by
      // 215 pixels at a doubled text scale, and worse here because an archived group with custom shares
      // carries both chips at once.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xs,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                group.name,
                style: AlayaTypography.body.copyWith(
                  color: group.isArchived ? semantic.muted : null,
                ),
              ),
              const SizedBox(height: AlayaSpacing.xxs),
              Text(
                strings.splitPerPersonCount(group.members.length),
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ],
          ),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xxs,
            children: [
              // Says what the group will do before it is used. A group carrying 40/30/30 behaves
              // differently from one that splits equally, and that is worth knowing from the list rather
              // than after opening the editor.
              if (group.hasDefaultWeights)
                StatusChip(
                  label: strings.splitHasWeights,
                  tone: StatusTone.info,
                ),
              if (group.isArchived)
                StatusChip(
                  label: strings.splitArchived,
                  tone: StatusTone.neutral,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
