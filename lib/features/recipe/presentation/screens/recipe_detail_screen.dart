import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/measure.dart';
import 'package:alaya/core/quantity/measure_formatter.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/core/time/date_key_labels.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/services/cookability_engine.dart';
import 'package:alaya/features/recipe/amount_format.dart';
import 'package:alaya/features/recipe/providers/recipe_detail_providers.dart';
import 'package:alaya/features/recipe/providers/recipe_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/measure_text.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// What to call an ingredient, in the one place that decides it.
///
/// **File scope because two things need it and they must agree.** The row and the confirmation sheet both
/// name ingredients, and when the sheet grew its own copy it printed a UUID: a line bound to the catalogue
/// carries no `freeText` — the repository stores exactly one of the two — so `freeText ?? itemId` resolves
/// to the id for every ingredient that actually works.
///
/// That is the second time this exact fallback has shipped. The first put the word "Ingredient" on every
/// working row; this one put `019fffaf-66c8-...` in a confirmation sheet. Both were a lookup somebody meant
/// to write and didn't, so there is now one lookup and no second place to forget it.
///
/// [items] rather than a `WidgetRef`, so a caller holding the map from a `read` and a caller holding it
/// from a `watch` get the same answer. The generic label is a last resort for a line pointing at an item
/// that has since been deleted — rare, and better than a blank.
String ingredientName(
  RecipeIngredient ingredient,
  Map<String, Item> items,
  AlayaStrings strings,
) {
  final itemId = ingredient.itemId;
  if (itemId != null) {
    final name = items[itemId]?.name;
    if (name != null && name.isNotEmpty) return name;
  }
  final typed = ingredient.freeText;
  if (typed != null && typed.isNotEmpty) return typed;
  return strings.recipeLinkedIngredient;
}

/// One recipe, and whether it can be cooked (ARCH_5 §3 archetype B, read mode).
///
/// **The ingredient list is the cookability report.** Rather than a badge at the top and a plain list
/// below, every line carries its own verdict — so "you are short" names *which* thing, and "can't tell"
/// names the ingredient nobody tracks. A single headline would make the user hunt for the reason.
class RecipeDetailScreen extends ConsumerWidget {
  /// Creates the screen.
  const RecipeDetailScreen({required this.recipeId, super.key});

  /// Which recipe to show.
  final String recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final recipe = ref.watch(recipeProvider(recipeId));

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.recipeDetailTitle),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.recipeEditFor(recipeId)),
            tooltip: strings.actionEdit,
            icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.md),
          ),
        ],
      ),
      body: recipe.when(
        loading: () => AlayaListSkeleton(label: strings.recipeLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(recipeProvider(recipeId)),
        ),
        data: (found) => found == null
            ? EmptyState(
                title: strings.recipeGoneTitle,
                body: strings.recipeGoneBody,
                icon: Icons.restaurant_menu_outlined,
              )
            : _Body(recipe: found),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.recipe});

  final Recipe recipe;

  /// How many expired ingredients the sheet names before summarising the rest.
  ///
  /// Three, because a sheet is not a report: past that the user is scrolling a list to reach the button,
  /// and the count carries the remainder without pretending to detail it.
  static const int _namedInSheet = 3;

  static const QtyFormatter _qtyFormat = QtyFormatter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final servings = ref.watch(servingsProvider(recipe.id)) ?? recipe.servings;
    final verdict = ref.watch(recipeCookabilityProvider(recipe.id));
    final working = ref.watch(cookControllerProvider).isLoading;
    final units =
        ref.watch(unitsByCodeProvider).valueOrNull ?? const <String, Unit>{};
    final items =
        ref.watch(itemsByIdProvider).valueOrNull ?? const <String, Item>{};
    // **Scaling is what makes an amount approximate**, so it is also what decides which style the rows
    // render in. At the recipe's own count every amount is the one the cook typed and nothing is snapped;
    // move the dial and the numbers become derived, which the rows then say out loud.
    final isScaled = servings != recipe.servings;

    return ListView(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
      children: [
        Padding(
          padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(recipe.name, style: AlayaTypography.sectionHeader),
              const SizedBox(height: AlayaSpacing.xxs),
              Text(
                recipe.totalMinutes == null
                    ? strings.recipeServes(servings)
                    : strings.recipeServesAndTime(
                        servings,
                        recipe.totalMinutes!,
                      ),
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ],
          ),
        ),

        // Servings scale everything below, so it sits above the ingredients rather than in a menu.
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
          ),
          child: Row(
            children: [
              Text(strings.recipeServingsLabel, style: AlayaTypography.body),
              const Spacer(),
              IconButton(
                onPressed: servings <= 1
                    ? null
                    : () => ref
                          .read(servingsProvider(recipe.id).notifier)
                          .set(servings - 1),
                tooltip: strings.recipeServingsFewer,
                icon: const Icon(
                  Icons.remove_circle_outline,
                  size: AlayaIconSize.md,
                ),
              ),
              Text('$servings', style: AlayaTypography.bodyEmphasis),
              IconButton(
                onPressed: () => ref
                    .read(servingsProvider(recipe.id).notifier)
                    .set(servings + 1),
                tooltip: strings.recipeServingsMore,
                icon: const Icon(
                  Icons.add_circle_outline,
                  size: AlayaIconSize.md,
                ),
              ),
            ],
          ),
        ),

        // **Explains the glyph, and only once it can appear.** A permanent legend for a mark that shows up
        // on one recipe in ten is clutter; a mark nobody can interpret is worse. This appears exactly when
        // the dial has moved, which is the only condition under which a row can be snapped.
        if (isScaled)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AlayaSpacing.screenEdge,
              AlayaSpacing.xxs,
              AlayaSpacing.screenEdge,
              0,
            ),
            child: Text(
              strings.recipeScaledRounding,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ),

        const SizedBox(height: AlayaSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
          ),
          child: SectionHeader(label: strings.recipeIngredientsHeader),
        ),
        if (verdict == null)
          AlayaListSkeleton(label: strings.recipeCheckingStock)
        else
          for (final check in verdict.checks)
            _IngredientRow(
              check: check,
              units: units,
              items: items,
              fromServings: recipe.servings,
              toServings: servings,
              isScaled: isScaled,
            ),

        if (recipe.steps.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.screenEdge,
            ),
            child: SectionHeader(label: strings.recipeMethodHeader),
          ),
          for (final step in recipe.steps)
            ListTile(
              leading: CircleAvatar(
                radius: AlayaIconSize.md * 0.7,
                backgroundColor: semantic.muted.withValues(alpha: 0.16),
                child: Text(
                  '${step.stepNumber}',
                  style: AlayaTypography.caption,
                ),
              ),
              title: Text(step.instruction, style: AlayaTypography.body),
              subtitle: step.durationMinutes == null
                  ? null
                  : Text(
                      strings.recipeStepMinutes(step.durationMinutes!),
                      style: AlayaTypography.caption.copyWith(
                        color: semantic.muted,
                      ),
                    ),
            ),
        ],

        if ((recipe.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.screenEdge,
            ),
            child: SectionHeader(label: strings.recipeNotesHeader),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.screenEdge,
            ),
            child: Text(recipe.notes!, style: AlayaTypography.body),
          ),
        ],

        const SizedBox(height: AlayaSpacing.xl),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
          ),
          child: FilledButton.icon(
            // **Gated on more than `isReady`.** `readyWithExpired` means the food is there and the cook
            // has to decide — greying the button out would take the decision away and leave no way to
            // make it, which is the same fault as gating a recipe on inventory configuration.
            // `uncheckable` still cooks: the app cannot know whether you have salt.
            onPressed: working || verdict == null || !_canAttempt(verdict)
                ? null
                : () => _cook(context, ref, servings, verdict),
            icon: const Icon(
              Icons.local_fire_department_outlined,
              size: AlayaIconSize.md,
            ),
            label: Text(
              working ? strings.recipeCooking : strings.recipeCookAction,
              style: AlayaTypography.button,
            ),
          ),
        ),
        // Says why before the tap rather than after it, so the sheet is expected rather than a surprise.
        if (verdict != null && verdict.needsExpiredConsent)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AlayaSpacing.screenEdge,
              AlayaSpacing.xs,
              AlayaSpacing.screenEdge,
              0,
            ),
            child: Text(
              strings.recipeCookBlockedExpired,
              style: AlayaTypography.caption.copyWith(color: semantic.warning),
            ),
          ),
        if (verdict != null && verdict.uncheckableCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AlayaSpacing.screenEdge,
              AlayaSpacing.xs,
              AlayaSpacing.screenEdge,
              0,
            ),
            child: Text(
              strings.recipeCookWillSkip(verdict.uncheckableCount),
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ),
      ],
    );
  }

  /// Whether tapping Cook could get anywhere.
  ///
  /// Deliberately not `verdict.isReady`: a recipe needing consent is cookable, and the tap is how the
  /// question gets asked.
  static bool _canAttempt(Cookability verdict) =>
      verdict.status != CookabilityStatus.blocked &&
      verdict.status != CookabilityStatus.short &&
      verdict.status != CookabilityStatus.empty;

  Future<void> _cook(
    BuildContext context,
    WidgetRef ref,
    int servings,
    Cookability verdict,
  ) async {
    final strings = AlayaStrings.of(context);

    // **Asked before anything is written, and only when there is something to ask about.** The engine
    // reports `needsExpiredConsent` from the same plan the deduction will execute, so the sheet is not
    // describing a guess — and if the answer is no, nothing happened.
    var allowExpired = false;
    if (verdict.needsExpiredConsent) {
      final items =
          ref.read(itemsByIdProvider).valueOrNull ?? const <String, Item>{};
      allowExpired = await ConfirmSheet.show(
        context,
        title: strings.recipeExpiredTitle,
        body: strings.recipeExpiredBody(
          _expiredDetail(strings, verdict, items),
        ),
        confirmLabel: strings.recipeExpiredConfirm,
        cancelLabel: strings.actionCancel,
      );
      if (!allowExpired || !context.mounted) return;
    }

    final ok = await ref
        .read(cookControllerProvider.notifier)
        .cook(
          recipe,
          servings: servings,
          deductStock: true,
          allowExpired: allowExpired,
        );
    if (!context.mounted) return;
    if (!ok) {
      final failure = ref.read(cookControllerProvider).error;
      showFailureSnack(
        context,
        message: failure?.toString() ?? strings.recipeCookFailed,
      );
      return;
    }
    final outcome = ref.read(cookControllerProvider).valueOrNull;
    showResultSnack(
      context,
      message: outcome == null
          ? strings.recipeCooked
          : strings.recipeCookedDeducted(outcome.deducted.length),
    );
  }

  /// The lines naming what is past its date, and how much of it will be used.
  ///
  /// **Read from `check.plan`, which is the plan the deduction will run.** A sheet that recomputed these
  /// figures could disagree with what actually happens, and asking for consent to something other than
  /// what you then do is the worst version of this whole class of bug.
  ///
  /// Names go through [ingredientName] rather than a local fallback — see its doc for what a local one
  /// printed. A plain string rather than a widget list, because `ConfirmSheet` takes a body, and one
  /// string keeps the sheet's own layout, scrolling and text-scale handling rather than reimplementing
  /// them.
  String _expiredDetail(
    AlayaStrings strings,
    Cookability verdict,
    Map<String, Item> items,
  ) {
    final affected = verdict.checks
        .where(
          (check) =>
              check.availability == IngredientAvailability.needsExpired &&
              check.plan != null,
        )
        .toList();

    final lines = <String>[];
    for (final check in affected.take(_namedInSheet)) {
      lines.add(
        strings.recipeExpiredLine(
          ingredientName(check.ingredient, items, strings),
          _qtyFormat.format(check.plan!.fromExpired),
          _expiryLabel(check.nearestExpiry),
        ),
      );
    }
    if (affected.length > _namedInSheet) {
      lines.add(strings.recipeExpiredMore(affected.length - _namedInSheet));
    }
    return lines.join('\n');
  }

  /// A date for the sheet's body, which takes text rather than widgets.
  ///
  /// **Law U7's one unavoidable exception on this screen, and it uses the sanctioned escape rather than a
  /// new format.** U7 routes a `DateKey` through `DateText`, and `ConfirmSheet` renders a string — so
  /// `DateKeyLabels.fullLabel` from `core/time` is what supplies it. `DateText._format` is private and
  /// there is deliberately no static twin of it; inventing one to reach into a widget would be a worse
  /// deviation than using the label extension that already exists for exactly this.
  ///
  /// `fullLabel` is unlocalised — `10 August 2026` — which is a real limitation and the reason it is
  /// confined to a sheet body. Every date the user reads on the screen behind this still goes through
  /// `DateText`, which is locale-aware.
  static String _expiryLabel(DateKey? on) => on?.fullLabel ?? '';
}

/// One ingredient, with what the engine could say about it.
class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    required this.check,
    required this.units,
    required this.items,
    required this.fromServings,
    required this.toServings,
    required this.isScaled,
  });

  final IngredientCheck check;

  /// Every unit by code, so the vessel the cook chose can be resolved.
  final Map<String, Unit> units;

  /// Every item by id, so a linked ingredient can be named.
  ///
  /// Passed in rather than watched here, because the screen above already watches it and a second watch
  /// would be a second source for one fact. It also drops this row's need for a `WidgetRef` entirely,
  /// which is what turned it back into a plain `StatelessWidget`.
  final Map<String, Item> items;

  /// The recipe's own serving count — what the stored amounts are written for.
  final int fromServings;

  /// The count the screen is dialled to.
  final int toServings;

  /// Whether [toServings] differs from [fromServings], and amounts are therefore derived.
  final bool isScaled;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    final (icon, tone, note) = switch (check.availability) {
      IngredientAvailability.sufficient => (
        Icons.check_circle_outline,
        semantic.success,
        null,
      ),
      // Warning, not danger: food past its date is a judgement call, not a failure.
      IngredientAvailability.needsExpired => (
        Icons.error_outline,
        semantic.warning,
        strings.recipeUsesExpired,
      ),
      IngredientAvailability.short => (
        Icons.remove_circle_outline,
        semantic.warning,
        check.shortfall == null ? null : strings.recipeShortfall,
      ),
      IngredientAvailability.outOfStock => (
        Icons.cancel_outlined,
        semantic.danger,
        strings.recipeNoneLeft,
      ),
      // Both unanswerable states get the muted tone and a plain sentence. Colouring them like a
      // failure would be the lie this module is built to avoid.
      IngredientAvailability.unitMismatch => (
        Icons.help_outline,
        semantic.muted,
        strings.recipeUnitMismatch,
      ),
      IngredientAvailability.untracked => (
        Icons.remove_outlined,
        semantic.muted,
        strings.recipeNotTracked,
      ),
    };

    return ListTile(
      leading: Icon(icon, size: AlayaIconSize.md, color: tone),
      title: Text(
        ingredientName(check.ingredient, items, strings),
        style: AlayaTypography.body,
      ),
      subtitle: note == null
          ? null
          : Text(note, style: AlayaTypography.caption.copyWith(color: tone)),
      trailing: _amount(),
    );
  }

  /// What to measure, in whatever the cook wrote it in.
  ///
  /// **Reads `ingredient.quantity`, not `check.required_`, and the distinction is the bug.** `required_`
  /// is the engine's figure: bridged into the *item's* own dimension, so half a tablespoon of flour comes
  /// out in grams. Rendering that in tablespoons would mean running the density backwards, and the number
  /// it produced would not be the number the cook typed. `quantity` is what they wrote; scaling it is the
  /// only thing servings should do to it.
  ///
  /// **Only vessels take this path.** `kSpoonAndCupCodes` is about things in a drawer rather than about
  /// dimensions — millilitres are a volume too, and nobody owns a half-litre spoon. Everything else keeps
  /// `QtyText`, whose decomposition into `4 kg 450 g` is better than any single unit could be, and which
  /// is what every other screen in the app uses.
  Widget? _amount() {
    final stored = check.ingredient.quantity;
    final code = check.ingredient.unitCode;
    final unit = code == null ? null : units[code];

    if (stored != null &&
        unit != null &&
        kSpoonAndCupCodes.contains(unit.code)) {
      final measure = Measure.fromQty(
        stored,
        factorToBaseMilli: unit.factorToBaseMilli,
      ).scaled(fromServings: fromServings, toServings: toServings);
      return MeasureText(
        measure,
        unit: unit,
        // Kitchen style only once the number is derived. Unscaled, the amount is what was typed and
        // snapping it would round a value the cook chose deliberately.
        style: isScaled ? MeasureStyle.kitchen : MeasureStyle.exact,
      );
    }

    return check.required_ == null ? null : QtyText(check.required_!);
  }
}
