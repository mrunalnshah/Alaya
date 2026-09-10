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
import 'package:alaya/domain/services/cookability_engine.dart';
import 'package:alaya/features/recipe/providers/recipe_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_search_field.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// The recipe catalogue (ARCH_5 §3 archetype D).
///
/// **Every row carries a cookability badge, and the badge tells the truth about what it does not
/// know.** A recipe whose ingredients are partly untracked reads as *"can't tell"* rather than
/// *"can't cook"* — the distinction the whole module is built on.
///
/// Search is a pinned field rather than an app-bar icon, matching the inventory catalogue: the
/// shell above owns the app bar, and a catalogue is searched constantly.
class RecipeListScreen extends ConsumerWidget {
  /// Creates the screen.
  const RecipeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final entries = ref.watch(recipeListProvider);
    final filter = ref.watch(recipeFilterProvider);
    final notifier = ref.read(recipeFilterProvider.notifier);

    return Scaffold(
      // The shell owns the app bar, so the FAB is the screen's own. A catalogue with no way to add
      // to it is the "reachable but unusable" failure ARCH_5 §9.2 asks about, one level in.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.recipeNew),
        icon: const Icon(Icons.add, size: AlayaIconSize.md),
        label: Text(strings.recipeAddAction, style: AlayaTypography.button),
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
              hintText: strings.recipeSearchHint,
              // Required, and it is the screen-reader label for the clear button rather than visible
              // text — an icon button with no label is a stop a blind user cannot identify (§6).
              clearLabel: strings.actionClearSearch,
              onChanged: notifier.setQuery,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.screenEdge,
            ),
            // A `Wrap`, not a `Row`. Two chips already exceed 288dp at scale 1 and overflowed by
            // 434px at scale 2 — `FilterChipBar`'s own doc comment says why: a row has no way to
            // give back space when its children grow, and text scale only ever makes them grow.
            child: Wrap(
              spacing: AlayaSpacing.xs,
              runSpacing: AlayaSpacing.xs,
              children: [
                FilterChip(
                  label: Text(
                    strings.recipeFilterCookable,
                    style: AlayaTypography.button,
                  ),
                  selected: filter.cookableOnly,
                  onSelected: (_) => notifier.toggleCookable(),
                ),
                FilterChip(
                  label: Text(
                    strings.recipeFilterFavourites,
                    style: AlayaTypography.button,
                  ),
                  selected: filter.favouritesOnly,
                  onSelected: (_) => notifier.toggleFavourites(),
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.when(
              loading: () => AlayaListSkeleton(label: strings.recipeLoading),
              error: (error, stack) => ErrorState(
                title: strings.errorTitleGeneric,
                body: error.toString(),
                retryLabel: strings.actionRetry,
                onRetry: () => ref.invalidate(allRecipesProvider),
              ),
              data: (rows) => rows.isEmpty
                  ? EmptyState(
                      title: filter.isActive
                          ? strings.recipeNoMatchTitle
                          : strings.recipeEmptyTitle,
                      body: filter.isActive
                          ? strings.recipeNoMatchBody
                          : strings.recipeEmptyBody,
                      icon: Icons.restaurant_menu_outlined,
                      actionLabel: filter.isActive ? strings.actionClear : null,
                      onAction: filter.isActive ? notifier.clear : null,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
                      itemCount: rows.length,
                      itemBuilder: (context, index) =>
                          _RecipeRow(entry: rows[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One recipe in the catalogue.
///
/// **Not a `ListTile`.** Its `trailing` slot is unbounded, so a text badge grows with the text scale
/// until it consumes the whole tile — Flutter throws *"trailing widget consumes the entire tile
/// width"* at scale 2, and every row below it fails to lay out. `item_row.dart` reached the same
/// conclusion for the same reason; this follows its shape.
class _RecipeRow extends StatelessWidget {
  const _RecipeRow({required this.entry});

  final RecipeListEntry entry;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final recipe = entry.recipe;
    final minutes = recipe.totalMinutes;
    // Above 1.5 the badge and the name cannot share a line on a 320dp phone, so the badge drops
    // below the text instead of squeezing it.
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final badge = _CookabilityBadge(cookability: entry.cookability);

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(recipe.name, style: AlayaTypography.cardTitle),
        const SizedBox(height: AlayaSpacing.xxs),
        Text(
          minutes == null
              ? strings.recipeServes(recipe.servings)
              : strings.recipeServesAndTime(recipe.servings, minutes),
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        if (stacked) ...[
          const SizedBox(height: AlayaSpacing.xs),
          badge,
        ],
      ],
    );

    return InkWell(
      onTap: () => context.push(Routes.recipeDetailFor(recipe.id)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
            vertical: AlayaSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                recipe.isFavorite ? Icons.star : Icons.restaurant_menu_outlined,
                size: AlayaIconSize.lg,
                color: recipe.isFavorite ? semantic.warning : semantic.muted,
              ),
              const SizedBox(width: AlayaSpacing.sm),
              Expanded(child: text),
              if (!stacked) ...[
                const SizedBox(width: AlayaSpacing.sm),
                badge,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The verdict, in one word and one colour.
///
/// **`uncheckable` is its own state with its own colour**, not a shade of "no". A recipe the engine
/// could not judge — because an ingredient is untracked, or measured in a unit that cannot be
/// compared to what the item is counted in — must not read as unavailable. Saying "can't tell" is
/// the honest answer and the reason this module exists in the shape it does.
class _CookabilityBadge extends StatelessWidget {
  const _CookabilityBadge({required this.cookability});

  final Cookability? cookability;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final verdict = cookability;

    // Null means stock has not arrived yet. No badge at all rather than a placeholder that would
    // read as a verdict.
    if (verdict == null) return const SizedBox.shrink();

    final (label, tone) = switch (verdict.status) {
      CookabilityStatus.ready => (strings.recipeReady, semantic.success),
      CookabilityStatus.short => (
        strings.recipeShortBy(verdict.missingCount),
        semantic.warning,
      ),
      CookabilityStatus.blocked => (
        strings.recipeMissingCount(verdict.missingCount),
        semantic.danger,
      ),
      CookabilityStatus.uncheckable => (
        strings.recipeUncheckable,
        semantic.muted,
      ),
      CookabilityStatus.empty => (strings.recipeNoIngredients, semantic.muted),
      // Grouped with `ready` because this screen cannot tell the difference: `recipeListProvider`
      // judges without batches, and expiry needs them, so `readyWithExpired` never arises here. The
      // distinction is the detail screen's, which does supply them.
      CookabilityStatus.readyWithExpired => (
        strings.recipeReady,
        semantic.success,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.sm,
        vertical: AlayaSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: AlayaRadii.borderSm,
      ),
      child: Text(
        label,
        style: AlayaTypography.caption.copyWith(color: tone),
      ),
    );
  }
}
