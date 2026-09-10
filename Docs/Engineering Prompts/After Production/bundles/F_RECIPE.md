# F_RECIPE

Recipes, ingredients, steps, the cookability engine and cooking.

**12 files · 3,655 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/features/recipe/amount_format.dart`

```dart
/// Which units are vessels rather than dimensions.
library;

/// The unit codes that correspond to a physical measuring spoon or cup.
///
/// **This is about vessels, not dimensions.** Millilitres and litres are volumes too, but nobody owns a
/// "half-litre spoon" — you read those off a jug in whole numbers. A teaspoon, tablespoon and cup are
/// things in a drawer, and they come in fractions, which is why only these three get the quick amounts
/// and the fraction hint.
///
/// A user who adds their own `dessertspoon` will not get the chips. That is a small loss against
/// hard-coding a guess about what any future unit means.
const Set<String> kSpoonAndCupCodes = {'tsp', 'tbsp', 'cup'};

// **Three things were deleted from this file, and each had become a duplicate rather than dead weight.**
//
// `parseAmountMilli` accepted `1 1/2`, `3/4` and `.5` and had **no callers anywhere** — written,
// documented at length, and never wired to the field it was written for, which is why typing a fraction
// did nothing and the module read as strict. `core/quantity/measure_parser.dart` is that parser, wired,
// and it additionally reads the vulgar-fraction characters a pasted recipe carries.
//
// `renderAmount` matched a remainder against nine hardcoded thousandths and fell back to a decimal for
// anything else — so `1/16` displayed as `0.062` and the five-chip list was never the real ceiling.
// `MeasureFormatter` derives recognition from a round trip instead, and needs no table to extend.
//
// `kStandardFractions` held five thousandths as bare ints. `kMeasuringSet` in
// `core/quantity/fraction.dart` holds the same vocabulary as `Fraction` values, with the eighth this
// list was missing, and states why it cannot be computed from the `units` table.
```

### `lib/features/recipe/presentation/screens/recipe_detail_screen.dart`

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
```

### `lib/features/recipe/presentation/screens/recipe_editor_screen.dart`

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
import 'package:alaya/core/quantity/fraction.dart';
import 'package:alaya/core/quantity/measure.dart';
import 'package:alaya/core/quantity/measure_formatter.dart';
import 'package:alaya/core/quantity/measure_parser.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/recipe/amount_format.dart';
import 'package:alaya/features/recipe/providers/recipe_editor_providers.dart';
import 'package:alaya/features/recipe/state/recipe_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Creating or editing a recipe (ARCH_5 §3 archetype B).
///
/// **Ingredients are rows in the form, not a separate screen.** A recipe is its ingredient list;
/// pushing that list behind another route would mean the thing being edited is not on the screen
/// editing it.
///
/// An ingredient may be typed as free text or linked to an inventory item, and **typing is the
/// default**. Requiring a catalogue entry for every ingredient would make adding a recipe a data-entry
/// exercise; the link is an upgrade the user makes when they want cookability to notice.
class RecipeEditorScreen extends ConsumerWidget {
  /// Creates the screen. [recipeId] is empty for a new recipe.
  const RecipeEditorScreen({required this.recipeId, super.key});

  /// Which recipe to edit, or the empty string.
  final String recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(recipeEditorProvider(recipeId));
    final notifier = ref.read(recipeEditorProvider(recipeId).notifier);
    final semantic = context.semantic;

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(
          recipeId.isEmpty ? strings.recipeNewTitle : strings.recipeEditTitle,
        ),
        actions: [
          IconButton(
            onPressed: notifier.toggleFavourite,
            tooltip: strings.recipeFavouriteToggle,
            icon: Icon(
              state.isFavorite ? Icons.star : Icons.star_border,
              size: AlayaIconSize.md,
              color: state.isFavorite ? semantic.warning : null,
            ),
          ),
        ],
      ),
      body: AlayaFormScaffold(
        primaryLabel: strings.actionSave,
        onPrimary: state.canSave && !state.isSaving
            ? () => _save(context, ref)
            : null,
        isDirty: state.isDirty,
        isSubmitting: state.isSaving,
        discardTitle: strings.confirmDiscardTitle,
        discardBody: strings.confirmDiscardBody,
        discardConfirmLabel: strings.actionDiscard,
        discardCancelLabel: strings.actionKeepEditing,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              initialValue: state.name,
              decoration: InputDecoration(labelText: strings.recipeNameLabel),
              textCapitalization: TextCapitalization.sentences,
              onChanged: notifier.setName,
            ),
            const SizedBox(height: AlayaSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: '${state.servings}',
                    decoration: InputDecoration(
                      labelText: strings.recipeServingsLabel,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) =>
                        notifier.setServings(int.tryParse(v) ?? state.servings),
                  ),
                ),
                const SizedBox(width: AlayaSpacing.sm),
                Expanded(
                  child: TextFormField(
                    initialValue: state.prepMinutes?.toString() ?? '',
                    decoration: InputDecoration(
                      labelText: strings.recipePrepLabel,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => notifier.setPrepMinutes(int.tryParse(v)),
                  ),
                ),
                const SizedBox(width: AlayaSpacing.sm),
                Expanded(
                  child: TextFormField(
                    initialValue: state.cookMinutes?.toString() ?? '',
                    decoration: InputDecoration(
                      labelText: strings.recipeCookLabel,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => notifier.setCookMinutes(int.tryParse(v)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: AlayaSpacing.lg),
            SectionHeader(label: strings.recipeIngredientsHeader),
            const SizedBox(height: AlayaSpacing.xs),
            // Not a ListView: this sits inside the form's own scroll, and a list that scrolls inside
            // a scroll is two gestures fighting over one drag (Law U13's companion rule).
            for (var i = 0; i < state.ingredients.length; i++)
              _IngredientRow(
                // Namespaced and identity-based. An ingredient and a step both keyed by their index
                // are siblings in this one Column, so index 0 collided with index 0 — the crash.
                // The id also survives a removal, so a row's text field travels with its row rather
                // than staying put while the data shifts underneath it.
                key: ValueKey<String>('ingredient-${state.ingredients[i].id}'),
                draft: state.ingredients[i],
                onChanged: (d) => notifier.updateIngredient(i, d),
                onRemove: () => notifier.removeIngredient(i),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: notifier.addIngredient,
                icon: const Icon(Icons.add, size: AlayaIconSize.md),
                label: Text(
                  strings.recipeAddIngredient,
                  style: AlayaTypography.button,
                ),
              ),
            ),

            const SizedBox(height: AlayaSpacing.lg),
            SectionHeader(label: strings.recipeMethodHeader),
            const SizedBox(height: AlayaSpacing.xs),
            for (var i = 0; i < state.steps.length; i++)
              _StepRow(
                key: ValueKey<String>('step-${state.steps[i].id}'),
                index: i,
                draft: state.steps[i],
                onChanged: (d) => notifier.updateStep(i, d),
                onRemove: () => notifier.removeStep(i),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: notifier.addStep,
                icon: const Icon(Icons.add, size: AlayaIconSize.md),
                label: Text(
                  strings.recipeAddStep,
                  style: AlayaTypography.button,
                ),
              ),
            ),

            const SizedBox(height: AlayaSpacing.lg),
            TextFormField(
              initialValue: state.notes ?? '',
              decoration: InputDecoration(labelText: strings.recipeNotesHeader),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              onChanged: notifier.setNotes,
            ),

            if (state.failureMessage != null) ...[
              const SizedBox(height: AlayaSpacing.md),
              Text(
                state.failureMessage!,
                style: AlayaTypography.body.copyWith(color: semantic.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final id = await ref.read(recipeEditorProvider(recipeId).notifier).save();
    if (!context.mounted) return;
    if (id == null) {
      showFailureSnack(context, message: strings.recipeSaveFailed);
      return;
    }
    showResultSnack(context, message: strings.recipeSaved);
    // Navigates explicitly rather than waiting for anything to notice — a save is an action, and
    // the screen that performed it knows where the user should land (ARCH_M §7).
    recipeId.isEmpty
        ? context.pushReplacement(Routes.recipeDetailFor(id))
        : context.pop();
  }
}

/// One ingredient line in the form.
///
/// **Two things make an ingredient count: a link to stock, and a measured amount.** Without the
/// link the engine has nothing to compare against; without the amount there is nothing to compare.
/// A line missing either is still valid — "salt, to taste" is a real ingredient — but the module
/// reports it as untracked rather than pretending to know.
class _IngredientRow extends ConsumerWidget {
  const _IngredientRow({
    required this.draft,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final IngredientDraft draft;
  final ValueChanged<IngredientDraft> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final units = ref.watch(editorUnitsProvider).valueOrNull ?? const <Unit>[];
    final items = ref.watch(editorItemsProvider).valueOrNull ?? const <Item>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Autocomplete<Item>(
                  initialValue: TextEditingValue(text: draft.label),
                  displayStringForOption: (item) => item.name,
                  optionsBuilder: (value) {
                    final query = value.text.trim().toLowerCase();
                    if (query.isEmpty) return const Iterable<Item>.empty();
                    return items
                        .where((i) => i.normalizedName.contains(query))
                        .take(6);
                  },
                  // Choosing from the catalogue is what links the line to stock — and it adopts the
                  // item's own dimension, so tomatoes offer grams and never millilitres (Law L8).
                  onSelected: (item) => onChanged(
                    draft.copyWith(
                      itemId: item.id,
                      itemName: item.name,
                      freeText: item.name,
                      category: item.unitCategory,
                      clearQuantity: draft.category != item.unitCategory,
                    ),
                  ),
                  fieldViewBuilder:
                      (
                        context,
                        controller,
                        focusNode,
                        onSubmit,
                      ) => TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: strings.recipeIngredientLabel,
                          helperText: draft.itemId == null
                              ? strings.recipeNotLinkedHelp
                              : null,
                          suffixIcon: draft.itemId == null
                              ? null
                              : Icon(
                                  Icons.link,
                                  size: AlayaIconSize.md,
                                  color: semantic.success,
                                ),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        // Typing away from a chosen item unlinks it: the text and the item cannot both
                        // be the answer, and the repository rejects a line carrying both.
                        onChanged: (v) => onChanged(
                          v == draft.itemName
                              ? draft
                              : draft.copyWith(freeText: v, clearItem: true),
                        ),
                      ),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                tooltip: strings.recipeRemoveIngredient,
                icon: const Icon(Icons.close, size: AlayaIconSize.md),
              ),
            ],
          ),
          const SizedBox(height: AlayaSpacing.xs),
          _AmountAndUnit(
            draft: draft,
            item: _linked(items),
            units: units,
            onChanged: onChanged,
          ),
          Row(
            children: [
              Checkbox(
                value: draft.isOptional,
                onChanged: (v) =>
                    onChanged(draft.copyWith(isOptional: v ?? false)),
              ),
              Expanded(
                child: Text(
                  strings.recipeOptionalLabel,
                  style: AlayaTypography.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The catalogue item this line points at, if any.
  Item? _linked(List<Item> items) {
    final id = draft.itemId;
    if (id == null) return null;
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }
}

/// One step in the form.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.draft,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int index;
  final StepDraft draft;
  final ValueChanged<StepDraft> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextFormField(
              initialValue: draft.instruction,
              decoration: InputDecoration(
                labelText: strings.recipeStepLabel(index + 1),
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (v) => onChanged(draft.copyWith(instruction: v)),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: strings.recipeRemoveStep,
            icon: const Icon(Icons.close, size: AlayaIconSize.md),
          ),
        ],
      ),
    );
  }
}

/// An amount and the unit it is measured in.
///
/// **Read as a cook writes it: a number, then a fraction, then the vessel.** "3 1/2 tablespoons" is
/// three tablespoons and then the half — so the amount is typed and the fraction is tapped, which is the
/// same two actions performed at the counter.
///
/// **The field takes anything a recipe is written in, and that is new.** It used to be
/// `int.tryParse(raw.trim())` — a whole number and nothing else — so `1/2` typed into it was discarded
/// and the only way to reach a fraction was a chip. `MeasureParser` accepts `2`, `0.5`, `.5`, `1/2`,
/// `1 1/2`, `2 3/4` and the `½`/`⅔`/`⅜` characters a pasted recipe carries. A parser that did most of
/// this already existed in this feature and had no callers; it is now `core/quantity/measure_parser.dart`
/// and it is wired.
///
/// **The chips are the drawer plus the present tense.** Six standing fractions — the eighth was missing
/// before, though the old renderer already knew it — and whatever the amount currently is, if it is not
/// one of them. Type `5/16` and a lit `5/16` chip appears, sorted into place, tappable to clear. That is
/// the custom-fraction affordance, and it needs no button, no picker and nothing remembered.
///
/// **Every unit is offered, always.** An earlier version hid spoons until the item declared what a
/// tablespoon of it weighed, which gated writing a recipe on configuring inventory — backwards. When
/// the chosen unit cannot be converted for the linked item, the row says so and names the field that
/// fixes it.
///
/// Purpose-built rather than `QtyField`, which filters to one category by design. Right for inventory
/// (Law L8: never offer millilitres for something you weigh) and wrong for a recipe, where flour is
/// stored by weight and measured by the spoonful.
class _AmountAndUnit extends StatelessWidget {
  const _AmountAndUnit({
    required this.draft,
    required this.item,
    required this.units,
    required this.onChanged,
  });

  final IngredientDraft draft;
  final Item? item;
  final List<Unit> units;
  final ValueChanged<IngredientDraft> onChanged;

  static const QtyFormatter _qtyFormat = QtyFormatter();
  static const MeasureFormatter _measureFormat = MeasureFormatter();
  static const MeasureParser _parser = MeasureParser();

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final unit = _selected();
    final isVessel = unit != null && kSpoonAndCupCodes.contains(unit.code);
    final measure = _measure(unit);
    final localeTag = Localizations.localeOf(context).toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                // Keyed on the unit so switching vessels re-seeds the field. Without it the widget is
                // reused and `initialValue` is ignored, which would leave a stale number beside a new
                // unit — a wrong recipe that looks right.
                key: ValueKey<String>('amount-${draft.id}-${unit?.code}'),
                // **Seeded with what the parser would accept back.** `1 1/2` in, `1 1/2` out: the field
                // shows the same string a cook typed rather than the decimal it became, which is what
                // "0.499" was a symptom of.
                initialValue: measure.isZero
                    ? null
                    : _measureFormat.format(measure, localeTag: localeTag).text,
                // Not `TextInputType.number`: that keyboard has no `/`, so a numeric-only field made
                // every fraction untypeable on the one platform this app ships to.
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  labelText: strings.recipeQuantityLabel,
                  // **`recipeAmountHintVessel` already existed and had no callers**, reading
                  // "1/2, 1, 1 1/2" — written for the field that could not accept any of it. So did
                  // `recipeAmountHint`. Two strings describing a capability nobody wired, in a string
                  // table, which is the same fault as an unreachable method one layer down.
                  hintText: isVessel
                      ? strings.recipeAmountHintVessel
                      : strings.recipeAmountHintPlain,
                ),
                onChanged: (raw) => _setAmount(raw, unit, localeTag),
              ),
            ),
            const SizedBox(width: AlayaSpacing.xs),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                initialValue: unit?.code,
                isExpanded: true,
                decoration: InputDecoration(labelText: strings.labelUnit),
                items: [
                  for (final u in units)
                    DropdownMenuItem<String>(
                      value: u.code,
                      child: Text(
                        u.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (code) => _switchUnit(code, unit),
              ),
            ),
          ],
        ),

        // The fractions in the drawer, plus whatever is set. Tapping the lit one clears it, so "3 1/2"
        // and "3" are one tap apart in both directions.
        if (isVessel)
          Padding(
            padding: const EdgeInsets.only(top: AlayaSpacing.xs),
            child: Wrap(
              spacing: AlayaSpacing.xs,
              runSpacing: AlayaSpacing.xs,
              children: [
                for (final fraction in _measureFormat.chipsFor(measure))
                  ChoiceChip(
                    label: Text(
                      '$fraction',
                      style: AlayaTypography.caption,
                    ),
                    selected: measure.remainderMilli == fraction.milliOfUnit,
                    onSelected: (_) => _setFraction(fraction, unit, measure),
                  ),
              ],
            ),
          ),

        // What will actually be taken. This is the answer to "how much is a tablespoon" — shown for the
        // ingredient in hand rather than as a conversion table the user has to apply themselves.
        if (unit != null && !measure.isZero)
          Padding(
            padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
            child: Text(
              _readout(strings, unit, measure, localeTag),
              style: AlayaTypography.caption.copyWith(
                color: _unconvertible(unit) ? semantic.warning : semantic.muted,
              ),
            ),
          ),
      ],
    );
  }

  /// The line in words: what was written, and what it comes to.
  ///
  /// For a linked item it reports the amount **in the item's own measure**, because that is what leaves
  /// the shelf. For anything else it reports the base measure, which at least says how big a tablespoon
  /// is. When no conversion exists it says which field would provide one.
  String _readout(
    AlayaStrings strings,
    Unit unit,
    Measure measure,
    String localeTag,
  ) {
    if (_unconvertible(unit)) {
      final name = item?.name ?? '';
      return unit.category == UnitCategory.count
          ? strings.recipeNeedsPieceWeight(name)
          : strings.recipeNeedsTbspWeight(name);
    }
    final rendered = _measureFormat.format(measure, localeTag: localeTag);
    final written = '${rendered.text} ${unit.displayName.toLowerCase()}';
    final quantity = _qty(measure, unit);
    final linked = item;
    final converted = linked == null
        ? quantity
        : _bridged(quantity, linked) ?? quantity;
    return strings.recipeAmountReadout(written, _qtyFormat.format(converted));
  }

  /// Converts into the item's own measure, mirroring `CookabilityEngine._bridge`.
  ///
  /// Duplicated rather than shared because the engine's copy is private and this one is cosmetic — if
  /// they ever disagree the badge is authoritative, and a wrong readout is a wrong sentence rather than
  /// a wrong deduction. Worth promoting to the engine if a third caller appears.
  static Qty? _bridged(Qty quantity, Item item) {
    if (item.unitCategory != UnitCategory.weight) return null;
    if (quantity.category == UnitCategory.weight) return quantity;
    final factor = switch (quantity.category) {
      UnitCategory.volume => item.densityMilliGramsPerMl,
      UnitCategory.count => item.milliGramsPerPiece,
      UnitCategory.weight => null,
    };
    if (factor == null) return null;
    return Qty(quantity.milliBase * factor ~/ 1000, UnitCategory.weight);
  }

  Unit? _selected() {
    if (units.isEmpty) return null;
    for (final u in units) {
      if (u.code == draft.unitCode) return u;
    }
    for (final u in units) {
      if (u.code == draft.category.baseUnitCode) return u;
    }
    return units.first;
  }

  /// Whether the engine will be unable to compare this line against stock.
  bool _unconvertible(Unit? unit) {
    final linked = item;
    if (linked == null || unit == null) return false;
    if (linked.unitCategory == unit.category) return false;
    if (linked.unitCategory != UnitCategory.weight) return true;
    return switch (unit.category) {
      UnitCategory.volume => linked.densityMilliGramsPerMl == null,
      UnitCategory.count => linked.milliGramsPerPiece == null,
      UnitCategory.weight => false,
    };
  }

  /// The stored quantity expressed in [unit].
  ///
  /// The rounding that makes this round-trip lives in [Measure] now rather than being spelled out at each
  /// call site — ARCH_M §7 records what truncating here cost, and one implementation cannot disagree with
  /// itself the way two did.
  Measure _measure(Unit? unit) {
    final quantity = draft.quantity;
    if (quantity == null || unit == null) return const Measure.zero();
    return Measure.fromQty(
      quantity,
      factorToBaseMilli: unit.factorToBaseMilli,
    );
  }

  static Qty _qty(Measure measure, Unit unit) => measure.toQty(
    factorToBaseMilli: unit.factorToBaseMilli,
    category: unit.category,
  );

  void _emit(Measure measure, Unit unit) {
    if (measure.isZero) {
      onChanged(draft.copyWith(clearQuantity: true));
      return;
    }
    onChanged(
      draft.copyWith(quantity: _qty(measure, unit), unitCode: unit.code),
    );
  }

  /// Replaces the whole amount from what was typed.
  ///
  /// **A parse failure clears the amount rather than freezing the old one.** Mid-edit the field legally
  /// holds `1 `, `1/` and `.` — none of which is a number — and refusing to react would leave the readout
  /// and the chips describing a value that is no longer on screen. An empty amount is a real state; a
  /// stale one is a lie.
  void _setAmount(String raw, Unit? unit, String localeTag) {
    if (unit == null) return;
    final parsed = _parser.parse(raw, localeTag: localeTag);
    _emit(parsed.valueOrNull ?? const Measure.zero(), unit);
  }

  /// Sets or clears the fraction, keeping the whole part.
  void _setFraction(Fraction fraction, Unit? unit, Measure current) {
    if (unit == null) return;
    final isLit = current.remainderMilli == fraction.milliOfUnit;
    _emit(current.withFraction(isLit ? null : fraction), unit);
  }

  void _switchUnit(String? code, Unit? previous) {
    if (code == null) return;
    final unit = units.firstWhere((u) => u.code == code);
    // The written amount is kept and re-measured: two teaspoons becomes two tablespoons, not two
    // teaspoons' worth expressed in tablespoons. Silently rescaling what somebody typed is how a
    // recipe goes wrong with nobody noticing.
    final measure = _measure(previous);
    onChanged(
      draft.copyWith(
        unitCode: unit.code,
        category: unit.category,
        quantity: _qty(
          measure.isZero ? const Measure(1000) : measure,
          unit,
        ),
      ),
    );
  }
}
```

### `lib/features/recipe/presentation/screens/recipe_list_screen.dart`

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
```

### `lib/features/recipe/providers/recipe_detail_providers.dart`

```dart
/// View-model state for one recipe (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/services/cookability_engine.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/services/recipe_cook_service.dart';
import 'package:alaya/features/recipe/providers/recipe_list_providers.dart';

/// The recipe being viewed.
final recipeProvider = StreamProvider.family<Recipe?, String>(
  (ref, id) => ref.watch(recipeRepositoryProvider).watchById(id),
);

/// Every unit, keyed by code.
///
/// **The detail screen needs this because an ingredient stores a unit code and nothing resolved it.**
/// `RecipeIngredient.unitCode` records the vessel the cook chose; the row had no way to look it up, so it
/// rendered the canonical quantity instead and a line reading "half a tablespoon" displayed as `7 ml`.
///
/// Keyed rather than a list, unlike `editorUnitsProvider`, because the editor populates a picker and this
/// answers "what is `tbsp`". Two projections of one stream is not two sources for one fact — the same
/// pairing `itemsByIdProvider` and `editorItemsProvider` already have.
final unitsByCodeProvider = StreamProvider<Map<String, Unit>>(
  (ref) => ref
      .watch(unitRepositoryProvider)
      .watchAll()
      .map(
        (units) => {for (final unit in units) unit.code: unit},
      ),
);

/// One item's batches, nearest expiry first.
///
/// A family so Riverpod caches per item: two ingredients of the same thing share one subscription, and
/// the underlying query is index-backed on `inventory_batches(expiry_date_key)`.
///
/// Returns full `Batch` entities because that is what the repository returns; the narrowing to
/// [ConsumableBatch] happens once, in [recipeBatchesProvider], rather than at the repository boundary.
final itemBatchesProvider = StreamProvider.family<List<Batch>, String>(
  (ref, itemId) => ref.watch(batchRepositoryProvider).watchByItemFefo(itemId),
);

/// Every batch behind this recipe's linked ingredients, keyed by item id.
///
/// **This is what buys the precise verdict.** `ItemStock.totalRemaining` comes from `v_item_stock`, which
/// sums batches with **no expiry filter**, so a total alone cannot say how much of it is still good — and
/// that is exactly why cooking was deducting expired stock without saying so.
///
/// **[ConsumableBatch], not `Batch`.** The engine plans through `InventoryConsumptionService`, whose input
/// is the deliberately narrow four-field projection — `ConsumableBatch.fromBatch` is the mapping, and
/// doing it here means the engine never sees an entity it has no use for.
///
/// **Only the detail screen pays for this.** `recipeListProvider` deliberately judges without batches: a
/// query per item across forty recipes for a badge would be the most expensive read in the app.
/// `CookabilityEngine.judge` documents the trade.
///
/// Returns null until **every** ingredient's batches have arrived. A partial map would produce a verdict
/// computed from half the shelf — reporting a shortfall for stock that is simply still loading, which is
/// the kind of momentarily-wrong answer a user screenshots.
final recipeBatchesProvider =
    Provider.family<Map<String, List<ConsumableBatch>>?, String>((ref, id) {
      final recipe = ref.watch(recipeProvider(id)).valueOrNull;
      if (recipe == null) return null;
      final batches = <String, List<ConsumableBatch>>{};
      for (final ingredient in recipe.ingredients) {
        final itemId = ingredient.itemId;
        if (itemId == null || batches.containsKey(itemId)) continue;
        final forItem = ref.watch(itemBatchesProvider(itemId)).valueOrNull;
        if (forItem == null) return null;
        batches[itemId] = [
          for (final batch in forItem) ConsumableBatch.fromBatch(batch),
        ];
      }
      return batches;
    });

/// How many servings the user has dialled the detail screen to.
///
/// Defaults to the recipe's own count. Held per recipe id so opening a second recipe does not inherit
/// the first one's scaling.
final servingsProvider =
    NotifierProvider.family<ServingsNotifier, int?, String>(
      ServingsNotifier.new,
    );

/// Holds the chosen serving count.
class ServingsNotifier extends FamilyNotifier<int?, String> {
  @override
  int? build(String arg) => null;

  /// Sets the count, clamped to at least one — the engine divides by it.
  void set(int servings) => state = servings < 1 ? 1 : servings;

  /// Returns to the recipe's own count.
  void reset() => state = null;
}

/// This recipe's cookability at the currently chosen serving count.
///
/// Judged **with batches**, so expiry is accounted for and each check carries the `ConsumptionPlan` a
/// confirmation sheet and the deduction will share.
final recipeCookabilityProvider = Provider.family<Cookability?, String>((
  ref,
  id,
) {
  final recipe = ref.watch(recipeProvider(id)).valueOrNull;
  final stock = ref.watch(stockByItemProvider).valueOrNull;
  final items = ref.watch(itemsByIdProvider).valueOrNull;
  final batches = ref.watch(recipeBatchesProvider(id));
  if (recipe == null || stock == null || items == null || batches == null) {
    return null;
  }
  return const CookabilityEngine().judge(
    recipe,
    stock: stock,
    items: items,
    // Read from the clock provider rather than `DateTime.now()`, so a test overriding it with a
    // `FixedClock` gets a reproducible verdict — the reason `judge` takes a date at all.
    today: ref.watch(clockProvider).today(),
    batchesByItem: batches,
    servings: ref.watch(servingsProvider(id)) ?? recipe.servings,
  );
});

/// Cooking, and what it did.
final cookControllerProvider =
    NotifierProvider<CookController, AsyncValue<CookOutcome?>>(
      CookController.new,
    );

/// Runs a cook and holds its outcome for the screen to report.
class CookController extends Notifier<AsyncValue<CookOutcome?>> {
  @override
  AsyncValue<CookOutcome?> build() => const AsyncData<CookOutcome?>(null);

  /// Cooks [recipe], optionally without touching stock.
  ///
  /// **[allowExpired] is the answer to a question the screen must already have asked.** False is not a
  /// cautious default — it is the correct one: the service refuses rather than quietly drawing on food
  /// past its date, so a caller that forgets to ask gets a refusal instead of a silent deduction. The
  /// screen learns the question is worth putting from `Cookability.needsExpiredConsent`.
  Future<bool> cook(
    Recipe recipe, {
    required int servings,
    required bool deductStock,
    bool allowExpired = false,
  }) async {
    state = const AsyncLoading<CookOutcome?>();
    final stock = ref.read(stockByItemProvider).valueOrNull ?? const {};
    final items = ref.read(itemsByIdProvider).valueOrNull ?? const {};

    final result = await ref
        .read(recipeCookServiceProvider)
        .cook(
          recipe: recipe,
          stock: stock,
          items: items,
          servings: servings,
          deductStock: deductStock,
          allowExpired: allowExpired,
        );
    if (result.isFailure) {
      state = AsyncError<CookOutcome?>(
        result.failureOrNull ?? StateError('cook failed'),
        StackTrace.current,
      );
      return false;
    }
    state = AsyncData<CookOutcome?>(result.valueOrNull);
    return true;
  }
}
```

### `lib/features/recipe/providers/recipe_editor_providers.dart`

```dart
/// View-model state for the recipe editor (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/text/normalizer.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/recipe/providers/recipe_list_providers.dart';
import 'package:alaya/features/recipe/state/recipe_editor_state.dart';

/// Every unit, for the ingredient rows' pickers.
final editorUnitsProvider = StreamProvider<List<Unit>>(
  (ref) => ref.watch(unitRepositoryProvider).watchAll(),
);

/// Every catalogued item, so an ingredient can be linked to stock.
///
/// **Linking is what makes cookability and deduction work at all.** An unlinked line is honest but
/// inert: the engine reports it as untracked and a cook skips it. This list is what turns "tomatoes"
/// the word into tomatoes the thing you have 500 g of.
final editorItemsProvider = StreamProvider<List<Item>>(
  (ref) => ref.watch(itemRepositoryProvider).watchAll(),
);

/// The editor's state for one recipe id, or the empty string for a new one.
final recipeEditorProvider =
    NotifierProvider.family<RecipeEditorNotifier, RecipeEditorState, String>(
      RecipeEditorNotifier.new,
    );

/// Drives every field in the editor.
class RecipeEditorNotifier extends FamilyNotifier<RecipeEditorState, String> {
  @override
  RecipeEditorState build(String arg) {
    if (arg.isEmpty) return const RecipeEditorState();
    // Seeded from whatever the list already holds rather than a fresh read: the catalogue is already
    // watching, so a second query would fetch what is in memory a frame later.
    final entries = ref.read(recipeListProvider).valueOrNull;
    if (entries != null) {
      for (final entry in entries) {
        if (entry.recipe.id == arg) return RecipeEditorState.from(entry.recipe);
      }
    }
    return const RecipeEditorState();
  }

  void _touch(RecipeEditorState next) =>
      state = next.copyWith(isDirty: true, clearFailure: true);

  /// Sets the name.
  void setName(String name) => _touch(state.copyWith(name: name));

  /// Sets the serving count, never below one — the engine divides by it.
  void setServings(int servings) =>
      _touch(state.copyWith(servings: servings < 1 ? 1 : servings));

  /// Sets the hands-on minutes.
  void setPrepMinutes(int? minutes) =>
      _touch(state.copyWith(prepMinutes: minutes));

  /// Sets the minutes on the heat.
  void setCookMinutes(int? minutes) =>
      _touch(state.copyWith(cookMinutes: minutes));

  /// Sets the notes.
  void setNotes(String? notes) => _touch(state.copyWith(notes: notes));

  /// Pins or unpins.
  void toggleFavourite() =>
      _touch(state.copyWith(isFavorite: !state.isFavorite));

  /// Appends an empty ingredient line.
  ///
  /// **The id is generated now, not at save time.** A draft with no id has no stable identity, and
  /// the editor's rows are keyed by it: with positional keys, removing the first row makes the
  /// second row inherit the first row's `TextFormField` element — and `initialValue` only applies on
  /// the first build, so the field keeps showing the deleted row's text.
  void addIngredient() => _touch(
    state.copyWith(
      ingredients: [
        ...state.ingredients,
        IngredientDraft(id: ref.read(uidGeneratorProvider).generate()),
      ],
    ),
  );

  /// Replaces the line at [index].
  void updateIngredient(int index, IngredientDraft draft) {
    final next = [...state.ingredients]..[index] = draft;
    _touch(state.copyWith(ingredients: next));
  }

  /// Removes the line at [index].
  void removeIngredient(int index) {
    final next = [...state.ingredients]..removeAt(index);
    _touch(state.copyWith(ingredients: next));
  }

  /// Appends an empty step. Same identity argument as [addIngredient].
  void addStep() => _touch(
    state.copyWith(
      steps: [
        ...state.steps,
        StepDraft(id: ref.read(uidGeneratorProvider).generate()),
      ],
    ),
  );

  /// Replaces the step at [index].
  void updateStep(int index, StepDraft draft) {
    final next = [...state.steps]..[index] = draft;
    _touch(state.copyWith(steps: next));
  }

  /// Removes the step at [index].
  void removeStep(int index) {
    final next = [...state.steps]..removeAt(index);
    _touch(state.copyWith(steps: next));
  }

  /// Saves, returning the id on success.
  ///
  /// **Quantities are parsed here, once, not on every keystroke.** A field that reformats while you
  /// type fights you; a field that rejects "1." before you have typed "5" is worse. Anything
  /// unparseable becomes a line with no quantity, which the engine already treats as untracked
  /// rather than zero.
  Future<String?> save() async {
    if (!state.canSave) return null;
    state = state.copyWith(isSaving: true, clearFailure: true);

    final uids = ref.read(uidGeneratorProvider);
    final id = state.id.isEmpty ? uids.generate() : state.id;
    final lines = <RecipeIngredient>[];
    for (var i = 0; i < state.ingredients.length; i++) {
      final draft = state.ingredients[i];
      if (!draft.isComplete) continue;
      lines.add(
        RecipeIngredient(
          id: draft.id,
          recipeId: id,
          itemId: draft.itemId,
          // Exactly one, as the repository requires. A linked line carries no free text even if the
          // user typed some before picking an item.
          freeText: draft.itemId == null ? draft.freeText.trim() : null,
          // Straight through. `QtyField` already validated this and handed back a finished `Qty`,
          // so there is no second parse here to disagree with the first — which is exactly what
          // produced a null quantity on every line: the parse needed a `unitCode` nothing set.
          quantity: draft.quantity,
          unitCode: draft.unitCode,
          isOptional: draft.isOptional,
          note: draft.note,
          sortOrder: i,
        ),
      );
    }

    final result = await ref
        .read(recipeRepositoryProvider)
        .save(
          Recipe(
            id: id,
            name: state.name.trim(),
            normalizedName: const Normalizer().normalize(state.name),
            servings: state.servings,
            ingredients: lines,
            steps: [
              for (var i = 0; i < state.steps.length; i++)
                if (state.steps[i].instruction.trim().isNotEmpty)
                  RecipeStep(
                    id: state.steps[i].id,
                    recipeId: id,
                    stepNumber: i + 1,
                    instruction: state.steps[i].instruction.trim(),
                    durationMinutes: state.steps[i].durationMinutes,
                  ),
            ],
            prepMinutes: state.prepMinutes,
            cookMinutes: state.cookMinutes,
            isFavorite: state.isFavorite,
            notes: (state.notes ?? '').trim().isEmpty
                ? null
                : state.notes!.trim(),
          ),
        );

    if (result.isFailure) {
      state = state.copyWith(
        isSaving: false,
        failureMessage: result.failureOrNull?.message,
      );
      return null;
    }
    state = state.copyWith(isSaving: false, isDirty: false);
    return id;
  }
}
```

### `lib/features/recipe/providers/recipe_list_providers.dart`

```dart
/// View-model state for the recipe catalogue (ARCH_5 U19).
library;

import 'package:alaya/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/services/cookability_engine.dart';

/// How the catalogue is filtered.
class RecipeFilter {
  /// Creates a filter.
  const RecipeFilter({
    this.query = '',
    this.favouritesOnly = false,
    this.cookableOnly = false,
  });

  /// Free-text search, already normalized by the notifier.
  final String query;

  /// Only pinned recipes.
  final bool favouritesOnly;

  /// Only recipes the engine reports as cookable.
  ///
  /// Deliberately excludes `uncheckable`. A recipe the engine could not judge is not one it can
  /// promise you can cook, and putting it in this list would make the filter mean "probably".
  ///
  /// **Includes `readyWithExpired`**, because the engine *can* judge those and they *can* be cooked —
  /// they need the cook's permission, not a shopping trip. On this screen the distinction cannot
  /// currently arise, since the list judges without batches and expiry needs them, but the filter
  /// should mean what it says rather than happening to be right.
  final bool cookableOnly;

  /// A copy with the given fields replaced.
  RecipeFilter copyWith({
    String? query,
    bool? favouritesOnly,
    bool? cookableOnly,
  }) => RecipeFilter(
    query: query ?? this.query,
    favouritesOnly: favouritesOnly ?? this.favouritesOnly,
    cookableOnly: cookableOnly ?? this.cookableOnly,
  );

  /// Whether anything is narrowing the list.
  bool get isActive => query.isNotEmpty || favouritesOnly || cookableOnly;
}

/// The catalogue's current filter.
final recipeFilterProvider =
    NotifierProvider<RecipeFilterNotifier, RecipeFilter>(
      RecipeFilterNotifier.new,
    );

/// Drives the search field and the filter chips.
class RecipeFilterNotifier extends Notifier<RecipeFilter> {
  @override
  RecipeFilter build() => const RecipeFilter();

  /// Sets the search term.
  void setQuery(String query) => state = state.copyWith(query: query.trim());

  /// Shows only pinned recipes.
  void toggleFavourites() =>
      state = state.copyWith(favouritesOnly: !state.favouritesOnly);

  /// Shows only recipes that can be cooked right now.
  void toggleCookable() =>
      state = state.copyWith(cookableOnly: !state.cookableOnly);

  /// Clears every filter.
  void clear() => state = const RecipeFilter();
}

/// Every recipe, unfiltered.
final allRecipesProvider = StreamProvider<List<Recipe>>(
  (ref) => ref.watch(recipeRepositoryProvider).watchAll(),
);

/// Stock for every item, keyed by id — the engine's input.
///
/// Public because the detail screen and the cook controller read it too. Two private copies would be
/// two subscriptions computing the same map, and could momentarily disagree about the same stock.
final stockByItemProvider = StreamProvider<Map<String, ItemStock>>(
  (ref) => ref
      .watch(itemRepositoryProvider)
      .watchAllStock()
      .map((rows) => {for (final r in rows) r.itemId: r}),
);

/// Every item, keyed by id — the engine needs `unitCategory` to compare units.
final itemsByIdProvider = StreamProvider<Map<String, Item>>(
  (ref) => ref
      .watch(itemRepositoryProvider)
      .watchAll()
      .map((rows) => {for (final r in rows) r.id: r}),
);

/// One row of the catalogue: a recipe and what the engine could say about it.
class RecipeListEntry {
  /// Creates a row.
  const RecipeListEntry({required this.recipe, this.cookability});

  /// The recipe.
  final Recipe recipe;

  /// Its verdict, or null while stock is still loading.
  final Cookability? cookability;
}

/// The catalogue after the active filter, with a verdict per row.
///
/// One pass over the whole list rather than a `family` per row: a virtualised list rebuilds rows
/// constantly, and a per-row provider would judge the same recipe on every scroll frame.
///
/// **Judged without batches, deliberately.** `judge` answers precisely when given an item's batches,
/// and that costs a query per item — across forty recipes it would be the most expensive read in the
/// app for a badge. The list therefore takes the coarse answer, which cannot report expiry, and the
/// detail screen takes the precise one. `judge`'s own documentation states the trade.
final recipeListProvider = Provider<AsyncValue<List<RecipeListEntry>>>((ref) {
  final recipes = ref.watch(allRecipesProvider);
  final stock = ref.watch(stockByItemProvider);
  final items = ref.watch(itemsByIdProvider);
  final filter = ref.watch(recipeFilterProvider);
  // Read once per rebuild rather than per recipe, so every row in one pass is judged against the same
  // date. Forty rows straddling midnight would otherwise disagree with each other.
  final today = ref.watch(clockProvider).today();

  return recipes.whenData((all) {
    final stockMap = stock.valueOrNull;
    final itemMap = items.valueOrNull;
    const engine = CookabilityEngine();

    final entries = <RecipeListEntry>[];
    for (final recipe in all) {
      if (filter.favouritesOnly && !recipe.isFavorite) continue;
      if (filter.query.isNotEmpty &&
          !recipe.normalizedName.contains(filter.query.toLowerCase())) {
        continue;
      }
      final verdict = (stockMap == null || itemMap == null)
          ? null
          : engine.judge(
              recipe,
              stock: stockMap,
              items: itemMap,
              today: today,
            );
      if (filter.cookableOnly && verdict?.isCookable != true) {
        continue;
      }
      entries.add(RecipeListEntry(recipe: recipe, cookability: verdict));
    }
    return entries;
  });
});

/// How many recipes can be cooked right now, for the dashboard tile and the empty state.
final cookableCountProvider = Provider<int?>((ref) {
  final entries = ref.watch(recipeListProvider).valueOrNull;
  if (entries == null) return null;
  return entries.where((e) => e.cookability?.isCookable ?? false).length;
});

/// One recipe's cookability, for a detail screen.
///
/// **Derived rather than stored.** A cached verdict would be wrong the moment a batch is consumed
/// anywhere else in the app, and Law L3 already refuses to store a figure that can be computed.
final cookabilityProvider = Provider.family<Cookability?, String>((
  ref,
  recipeId,
) {
  // Reuses the list's single pass rather than judging again — the list is already watching the
  // same three streams, so a second computation here would be the same arithmetic twice.
  final entries = ref.watch(recipeListProvider).valueOrNull;
  if (entries == null) return null;
  for (final entry in entries) {
    if (entry.recipe.id == recipeId) return entry.cookability;
  }
  return null;
});
```

### `lib/features/recipe/state/recipe_editor_state.dart`

```dart
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/recipe.dart';

/// One ingredient line while it is being edited.
///
/// A draft rather than a [RecipeIngredient] because a half-typed line is not a valid one: the
/// quantity is still text, and the entity's "either an item or free text" invariant is exactly what
/// the user is in the middle of deciding.
class IngredientDraft {
  /// Creates a draft.
  const IngredientDraft({
    this.id = '',
    this.itemId,
    this.itemName,
    this.freeText = '',
    this.quantity,
    this.category = UnitCategory.weight,
    this.unitCode,
    this.isOptional = false,
    this.note,
  });

  /// The row id, empty for a line that has never been saved.
  final String id;

  /// The linked catalogue item, if any.
  final String? itemId;

  /// That item's name, held so the row can render without a lookup.
  final String? itemName;

  /// What the ingredient is, when it is not linked.
  final String freeText;

  /// The measured amount, or null for "to taste".
  ///
  /// **A `Qty`, not text.** `QtyField` parses and validates as the user types and hands back a
  /// finished value, so the editor no longer re-parses on save — which is what made every ingredient
  /// quantity null: the parse depended on a `unitCode` no widget ever set.
  final Qty? quantity;

  /// Which dimension this line is measured in.
  ///
  /// Follows the linked item when there is one — tomatoes are weighed, so their line offers grams
  /// and kilograms and nothing else (Law L8). An unlinked line defaults to weight.
  final UnitCategory category;

  /// The unit the cook reads.
  final String? unitCode;

  /// Excluded from the cookability verdict.
  final bool isOptional;

  /// Preparation note.
  final String? note;

  /// A copy with the given fields replaced.
  IngredientDraft copyWith({
    String? id,
    String? itemId,
    String? itemName,
    String? freeText,
    Qty? quantity,
    UnitCategory? category,
    String? unitCode,
    bool clearQuantity = false,
    bool? isOptional,
    String? note,
    bool clearItem = false,
  }) => IngredientDraft(
    id: id ?? this.id,
    itemId: clearItem ? null : (itemId ?? this.itemId),
    itemName: clearItem ? null : (itemName ?? this.itemName),
    freeText: freeText ?? this.freeText,
    quantity: clearQuantity ? null : (quantity ?? this.quantity),
    category: category ?? this.category,
    unitCode: unitCode ?? this.unitCode,
    isOptional: isOptional ?? this.isOptional,
    note: note ?? this.note,
  );

  /// What the row displays: the linked item's name, or the typed text.
  String get label => itemName ?? freeText;

  /// Whether this line has enough to save.
  bool get isComplete => itemId != null || freeText.trim().isNotEmpty;
}

/// One step while it is being edited.
class StepDraft {
  /// Creates a draft.
  const StepDraft({this.id = '', this.instruction = '', this.durationMinutes});

  /// The row id, empty for a new step.
  final String id;

  /// What to do.
  final String instruction;

  /// How long it takes.
  final int? durationMinutes;

  /// A copy with the given fields replaced.
  StepDraft copyWith({String? id, String? instruction, int? durationMinutes}) =>
      StepDraft(
        id: id ?? this.id,
        instruction: instruction ?? this.instruction,
        durationMinutes: durationMinutes ?? this.durationMinutes,
      );
}

/// The recipe editor's whole state.
class RecipeEditorState {
  /// Creates a state.
  const RecipeEditorState({
    this.id = '',
    this.name = '',
    this.servings = 2,
    this.prepMinutes,
    this.cookMinutes,
    this.notes,
    this.isFavorite = false,
    this.ingredients = const [],
    this.steps = const [],
    this.isDirty = false,
    this.isSaving = false,
    this.failureMessage,
  });

  /// Builds the editor's state from an existing recipe.
  factory RecipeEditorState.from(Recipe recipe) => RecipeEditorState(
    id: recipe.id,
    name: recipe.name,
    servings: recipe.servings,
    prepMinutes: recipe.prepMinutes,
    cookMinutes: recipe.cookMinutes,
    notes: recipe.notes,
    isFavorite: recipe.isFavorite,
    ingredients: [
      for (final line in recipe.ingredients)
        IngredientDraft(
          id: line.id,
          itemId: line.itemId,
          freeText: line.freeText ?? '',
          quantity: line.quantity,
          category: line.quantity?.category ?? UnitCategory.weight,
          unitCode: line.unitCode,
          isOptional: line.isOptional,
          note: line.note,
        ),
    ],
    steps: [
      for (final step in recipe.steps)
        StepDraft(
          id: step.id,
          instruction: step.instruction,
          durationMinutes: step.durationMinutes,
        ),
    ],
  );

  /// The row id, empty for a new recipe.
  final String id;

  /// Display name.
  final String name;

  /// How many servings the quantities describe.
  final int servings;

  /// Hands-on minutes.
  final int? prepMinutes;

  /// Minutes on the heat.
  final int? cookMinutes;

  /// Free-form notes.
  final String? notes;

  /// Pinned.
  final bool isFavorite;

  /// The ingredient lines.
  final List<IngredientDraft> ingredients;

  /// The method.
  final List<StepDraft> steps;

  /// Whether anything has been edited, for the discard guard.
  final bool isDirty;

  /// Whether a save is in flight.
  final bool isSaving;

  /// The repository's own message from the last failure (Law U9).
  final String? failureMessage;

  /// A copy with the given fields replaced.
  RecipeEditorState copyWith({
    String? id,
    String? name,
    int? servings,
    int? prepMinutes,
    int? cookMinutes,
    String? notes,
    bool? isFavorite,
    List<IngredientDraft>? ingredients,
    List<StepDraft>? steps,
    bool? isDirty,
    bool? isSaving,
    String? failureMessage,
    bool clearFailure = false,
  }) => RecipeEditorState(
    id: id ?? this.id,
    name: name ?? this.name,
    servings: servings ?? this.servings,
    prepMinutes: prepMinutes ?? this.prepMinutes,
    cookMinutes: cookMinutes ?? this.cookMinutes,
    notes: notes ?? this.notes,
    isFavorite: isFavorite ?? this.isFavorite,
    ingredients: ingredients ?? this.ingredients,
    steps: steps ?? this.steps,
    isDirty: isDirty ?? this.isDirty,
    isSaving: isSaving ?? this.isSaving,
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
  );

  /// Whether the form can be submitted.
  ///
  /// A name and at least one usable ingredient. A recipe with no ingredients is a note, and the
  /// engine reports it as [CookabilityStatus.empty] — better to refuse it here than to store one.
  bool get canSave =>
      name.trim().isNotEmpty &&
      servings > 0 &&
      ingredients.any((line) => line.isComplete);
}
```

### `test/features/recipe/cookability_engine_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/recipe.dart';
import 'package:alaya/domain/services/cookability_engine.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';

import '../../support/recipe_harness.dart';

/// The engine, from literals. No database, no widget — the whole point of it being pure.
void main() {
  Map<String, Item> items(List<String> ids) => {
    for (final id in ids) id: weightItem(id, id),
  };

  /// The date every verdict below is judged against.
  ///
  /// **Explicit rather than a clock read.** `judge` requires it so a date-sensitive verdict is
  /// reproducible — the same rule `ConsumableBatch.isExpired` and the views follow. Most tests here
  /// supply no batches, so expiry is not consulted and the value is arbitrary; the ones that do supply
  /// batches pick their expiry dates relative to this.
  const today = DateKey(20260814);

  /// A weight batch of [grams], expiring on [expiry] or never.
  ///
  /// Built directly rather than from a `Batch` entity: `ConsumableBatch` is the four-field projection
  /// `InventoryConsumptionService` takes, and a test that constructed twelve fields to use four would
  /// break on every unrelated change to a batch.
  ConsumableBatch batch(
    String id,
    int grams, {
    int? expiry,
    int purchased = 20260701,
  }) => ConsumableBatch(
    batchId: id,
    remaining: Qty(grams * 1000, UnitCategory.weight),
    purchasedDateKey: DateKey(purchased),
    expiryDateKey: expiry == null ? null : DateKey(expiry),
  );

  group('serving scale', () {
    test('rounds up, because rounding down would claim you have enough', () {
      // 200g for 4 servings, scaled to 3, is 150g exactly.
      expect(
        CookabilityEngine.scaleMilli(200000, fromServings: 4, toServings: 3),
        150000,
      );
      // 100g for 3 servings, scaled to 2, is 66.666…g. Down would be 66666, and an engine that said
      // "ready" with 66666 on hand would be wrong.
      expect(
        CookabilityEngine.scaleMilli(100000, fromServings: 3, toServings: 2),
        66667,
      );
    });

    test('is exact when the servings match', () {
      expect(
        CookabilityEngine.scaleMilli(12345, fromServings: 4, toServings: 4),
        12345,
      );
    });

    test('refuses a zero base, which would divide by nothing', () {
      expect(
        () =>
            CookabilityEngine.scaleMilli(1000, fromServings: 0, toServings: 1),
        throwsArgumentError,
      );
    });
  });

  group('the availabilities', () {
    test('enough on hand is sufficient', () {
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 200)]),
        stock: {'flour': stockOf('flour', 500)},
        items: items(['flour']),
        today: today,
      );
      expect(
        verdict.checks.single.availability,
        IngredientAvailability.sufficient,
      );
      expect(verdict.status, CookabilityStatus.ready);
    });

    test(
      'some but not enough is short, with a shortfall a shopping list could use',
      () {
        final verdict = kEngine.judge(
          recipeOf(ingredients: [linked('flour', 200)]),
          stock: {'flour': stockOf('flour', 150)},
          items: items(['flour']),
          today: today,
        );
        final check = verdict.checks.single;
        expect(check.availability, IngredientAvailability.short);
        expect(check.shortfall, Qty(50 * 1000, UnitCategory.weight));
        expect(verdict.status, CookabilityStatus.short);
      },
    );

    test('none at all is blocked, not merely short', () {
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 200)]),
        stock: {'flour': stockOf('flour', 0)},
        items: items(['flour']),
        today: today,
      );
      expect(
        verdict.checks.single.availability,
        IngredientAvailability.outOfStock,
      );
      expect(verdict.status, CookabilityStatus.blocked);
    });

    test('a unit that cannot be compared is unanswerable, NOT zero', () {
      // The recipe asks for 200g; the item is counted in pieces. No factor relates them, so the
      // engine must decline rather than report a shortfall it cannot compute.
      final counted = Item(
        id: 'eggs',
        name: 'Eggs',
        normalizedName: 'eggs',
        unitCategory: UnitCategory.count,
        defaultDisplayUnitCode: 'pc',
        itemKind: ItemKind.food,
        isFavorite: false,
      );
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('eggs', 200)]),
        stock: {
          'eggs': ItemStock(
            itemId: 'eggs',
            totalRemaining: const Qty(6000, UnitCategory.count),
            batchCount: 1,
            isLowStock: false,
          ),
        },
        items: {'eggs': counted},
        today: today,
      );
      expect(
        verdict.checks.single.availability,
        IngredientAvailability.unitMismatch,
      );
      expect(verdict.status, CookabilityStatus.uncheckable);
      expect(verdict.missingCount, 0, reason: 'unanswerable is not missing');
    });

    test('an ingredient nothing tracks is untracked', () {
      final verdict = kEngine.judge(
        recipeOf(ingredients: [untracked('salt')]),
        stock: const {},
        items: const {},
        today: today,
      );
      expect(
        verdict.checks.single.availability,
        IngredientAvailability.untracked,
      );
      expect(verdict.status, CookabilityStatus.uncheckable);
    });

    test('a linked item that no longer exists is untracked, not missing', () {
      // The item was deleted. Inventing a verdict about a row that is gone would be a guess.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('ghost', 200)]),
        stock: const {},
        items: const {},
        today: today,
      );
      expect(
        verdict.checks.single.availability,
        IngredientAvailability.untracked,
      );
    });
  });

  group('the verdict combines its parts', () {
    test('missing and uncheckable are counted apart', () {
      final verdict = kEngine.judge(
        recipeOf(
          ingredients: [
            linked('flour', 200, sortOrder: 0),
            untracked('salt', sortOrder: 1),
          ],
        ),
        stock: {'flour': stockOf('flour', 150)},
        items: items(['flour']),
        today: today,
      );
      expect(verdict.missingCount, 1);
      expect(verdict.uncheckableCount, 1);
      // Short wins the headline: something is definitely missing, which is more actionable than
      // something being unknown.
      expect(verdict.status, CookabilityStatus.short);
    });

    test('an optional ingredient never blocks the verdict', () {
      final verdict = kEngine.judge(
        recipeOf(
          ingredients: [
            linked('flour', 200, sortOrder: 0),
            linked('coriander', 10, sortOrder: 1, optional: true),
          ],
        ),
        stock: {
          'flour': stockOf('flour', 500),
          'coriander': stockOf('coriander', 0),
        },
        items: items(['flour', 'coriander']),
        today: today,
      );
      expect(verdict.status, CookabilityStatus.ready);
      expect(verdict.missingCount, 0);
      expect(verdict.optionalMissingCount, 1, reason: 'still worth saying');
    });

    test('a recipe with no required ingredients is empty, not ready', () {
      final verdict = kEngine.judge(
        recipeOf(),
        stock: const {},
        items: const {},
        today: today,
      );
      expect(verdict.status, CookabilityStatus.empty);
    });

    test('scaling servings can turn ready into short', () {
      final recipe = recipeOf(servings: 2, ingredients: [linked('flour', 200)]);
      final stock = {'flour': stockOf('flour', 250)};
      expect(
        kEngine
            .judge(
              recipe,
              stock: stock,
              items: items(['flour']),
              today: today,
            )
            .status,
        CookabilityStatus.ready,
      );
      // Doubled, the recipe needs 400g and only 250g is on hand.
      expect(
        kEngine
            .judge(
              recipe,
              stock: stock,
              items: items(['flour']),
              today: today,
              servings: 4,
            )
            .status,
        CookabilityStatus.short,
      );
    });
  });

  group('bridging one measure to another', () {
    test('millilitres convert to grams when the item states a density', () {
      // Oil is 0.92 g/ml, so 920 milli-grams per ml. 50 ml is 46 g, and 100 g on hand covers it.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [inVolume('oil', 50)]),
        stock: {'oil': stockOf('oil', 100)},
        items: {'oil': weightItem('oil', 'Oil', densityMilliGramsPerMl: 920)},
        today: today,
      );
      final check = verdict.checks.single;
      expect(check.availability, IngredientAvailability.sufficient);
      expect(
        check.required_,
        Qty(46 * 1000, UnitCategory.weight),
        reason: '50 ml x 0.92 g/ml = 46 g',
      );
      expect(verdict.status, CookabilityStatus.ready);
    });

    test('a converted amount can still fall short, and reports it in grams', () {
      // 200 ml of oil is 184 g; only 100 g is on hand, so the shortfall is 84 g.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [inVolume('oil', 200)]),
        stock: {'oil': stockOf('oil', 100)},
        items: {'oil': weightItem('oil', 'Oil', densityMilliGramsPerMl: 920)},
        today: today,
      );
      final check = verdict.checks.single;
      expect(check.availability, IngredientAvailability.short);
      expect(check.shortfall, Qty(84 * 1000, UnitCategory.weight));
    });

    test('without a density it stays unanswerable, NOT missing', () {
      // The whole design in one assertion: no density means the engine declines rather than
      // reporting a shortfall it cannot compute. A `short` here would be a confident falsehood.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [inVolume('oil', 50)]),
        stock: {'oil': stockOf('oil', 100)},
        items: {'oil': weightItem('oil', 'Oil')},
        today: today,
      );
      expect(
        verdict.checks.single.availability,
        IngredientAvailability.unitMismatch,
      );
      expect(verdict.status, CookabilityStatus.uncheckable);
      expect(verdict.missingCount, 0);
    });

    test('pieces convert to grams when the item states a piece weight', () {
      // An onion is 110 g. Two of them is 220 g, and 500 g on hand covers it.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [inPieces('onion', 2)]),
        stock: {'onion': stockOf('onion', 500)},
        items: {
          'onion': weightItem('onion', 'Onion', milliGramsPerPiece: 110 * 1000),
        },
        today: today,
      );
      expect(
        verdict.checks.single.required_,
        Qty(220 * 1000, UnitCategory.weight),
      );
      expect(verdict.status, CookabilityStatus.ready);
    });

    test('a density does not answer a question asked in pieces', () {
      // The two bridges are independent: knowing what a millilitre weighs says nothing about what
      // one onion weighs, and the engine must not borrow one for the other.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [inPieces('onion', 2)]),
        stock: {'onion': stockOf('onion', 500)},
        items: {
          'onion': weightItem('onion', 'Onion', densityMilliGramsPerMl: 920),
        },
        today: today,
      );
      expect(
        verdict.checks.single.availability,
        IngredientAvailability.unitMismatch,
      );
    });

    test('serving scale applies after the conversion, not before', () {
      // 50 ml at 2 servings, doubled, is 100 ml -> 92 g. Converting first then scaling and scaling
      // first then converting agree here only because both are linear; asserting it pins the order
      // so a future non-linear bridge cannot silently change the answer.
      final verdict = kEngine.judge(
        recipeOf(servings: 2, ingredients: [inVolume('oil', 50)]),
        stock: {'oil': stockOf('oil', 100)},
        items: {'oil': weightItem('oil', 'Oil', densityMilliGramsPerMl: 920)},
        today: today,
        servings: 4,
      );
      expect(
        verdict.checks.single.required_,
        Qty(92 * 1000, UnitCategory.weight),
      );
    });
  });

  group('expiry', () {
    test('reports the soonest expiry among the items it would use', () {
      final verdict = kEngine.judge(
        recipeOf(
          ingredients: [
            linked('flour', 100, sortOrder: 0),
            linked('milk', 100, sortOrder: 1),
          ],
        ),
        stock: {
          'flour': stockOf('flour', 500, expiry: const DateKey(20261201)),
          'milk': stockOf('milk', 500, expiry: const DateKey(20260815)),
        },
        items: items(['flour', 'milk']),
        today: today,
      );
      expect(verdict.soonestExpiryUsed, const DateKey(20260815));
    });

    test('is null when nothing it uses expires', () {
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 100)]),
        stock: {'flour': stockOf('flour', 500)},
        items: items(['flour']),
        today: today,
      );
      expect(verdict.soonestExpiryUsed, isNull);
    });
  });

  group('expiry, with batches — the precise path', () {
    /// 100 g still good, 200 g past its date. `stockOf` carries the total, because `v_item_stock`
    /// sums every batch holding stock with no expiry filter — which is the whole reason a total
    /// alone could not answer this.
    Map<String, List<ConsumableBatch>> mixed() => {
      'flour': [
        batch('good', 100, expiry: 20260901, purchased: 20260801),
        batch('gone', 200, expiry: 20260810),
      ],
    };

    test('needing expired stock is not missing, and does not block cooking', () {
      // **The reported bug, as a verdict.** 200 g needed, 100 g good, 200 g past its date. The recipe
      // is cookable — but only with permission, which is a different answer from both "ready" and
      // "you are short".
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 200)]),
        stock: {'flour': stockOf('flour', 300)},
        items: items(['flour']),
        today: today,
        batchesByItem: mixed(),
      );

      expect(
        verdict.checks.single.availability,
        IngredientAvailability.needsExpired,
      );
      expect(verdict.status, CookabilityStatus.readyWithExpired);
      expect(verdict.expiredCount, 1);
      expect(
        verdict.missingCount,
        0,
        reason: 'nothing needs buying — the food is in the cupboard',
      );
      expect(verdict.isCookable, isTrue);
      expect(verdict.isReady, isFalse);
    });

    test('the plan it carries is the one that would actually run', () {
      // Replanned with permission, so a confirmation sheet and the deduction read the same object.
      // The fresh-only attempt *failed*, so there is no plan on it to hand over — which is why the
      // service refusing rather than returning a partial plan is the better contract.
      final plan = kEngine
          .judge(
            recipeOf(ingredients: [linked('flour', 200)]),
            stock: {'flour': stockOf('flour', 300)},
            items: items(['flour']),
            today: today,
            batchesByItem: mixed(),
          )
          .checks
          .single
          .plan;

      expect(plan, isNotNull);
      expect(plan!.usesExpired, isTrue);
      // Good stock exhausted first, expired only topping it up.
      expect(
        plan.draws.map((draw) => draw.batchId),
        orderedEquals(['good', 'gone']),
      );
      expect(plan.fromExpired, Qty(100 * 1000, UnitCategory.weight));
      // Counts what the permitted policy could reach, which is everything on the shelf.
      expect(plan.totalAvailable, Qty(300 * 1000, UnitCategory.weight));
    });

    test('good stock alone is enough, so nothing is flagged', () {
      // There is expired stock and the plan never reaches it. Prompting here would be a warning
      // about nothing.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 100)]),
        stock: {'flour': stockOf('flour', 300)},
        items: items(['flour']),
        today: today,
        batchesByItem: mixed(),
      );

      final check = verdict.checks.single;
      expect(check.availability, IngredientAvailability.sufficient);
      expect(verdict.status, CookabilityStatus.ready);
      expect(verdict.expiredCount, 0);
      expect(check.plan?.usesExpired, isFalse);
      // The fresh-only policy counts only good stock, so the total it quotes is 100 g not 300 g.
      expect(check.plan?.totalAvailable, Qty(100 * 1000, UnitCategory.weight));
    });

    test('not enough even counting expired stock is short, not needsExpired', () {
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 500)]),
        stock: {'flour': stockOf('flour', 300)},
        items: items(['flour']),
        today: today,
        batchesByItem: mixed(),
      );

      final check = verdict.checks.single;
      expect(check.availability, IngredientAvailability.short);
      expect(verdict.status, CookabilityStatus.short);
      // The gap after everything usable, expired included — what a shopping list needs.
      expect(check.shortfall, Qty(200 * 1000, UnitCategory.weight));
      expect(
        check.plan,
        isNull,
        reason: 'no plan exists when none can be applied',
      );
    });

    test('a cupboard holding only expired stock is not empty', () {
      // `outOfStock` means nothing usable at all. Something past its date is still something.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 500)]),
        stock: {'flour': stockOf('flour', 200)},
        items: items(['flour']),
        today: today,
        batchesByItem: {
          'flour': [batch('gone', 200, expiry: 20260810)],
        },
      );

      final check = verdict.checks.single;
      expect(check.availability, IngredientAvailability.short);
      expect(verdict.status, CookabilityStatus.short);
      expect(check.shortfall, Qty(300 * 1000, UnitCategory.weight));
    });

    test('an empty shelf is out of stock', () {
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 100)]),
        stock: {'flour': stockOf('flour', 0)},
        items: items(['flour']),
        today: today,
        batchesByItem: const {'flour': []},
      );

      expect(
        verdict.checks.single.availability,
        IngredientAvailability.outOfStock,
      );
      expect(verdict.status, CookabilityStatus.blocked);
    });

    test('a batch expiring today is still good today', () {
      // Confirms `ConsumableBatch.isExpired`, which is strict: `expiry < today`. Use-by 14 Aug is
      // usable on 14 Aug, matching what the calendar module already assumes.
      final verdict = kEngine.judge(
        recipeOf(ingredients: [linked('flour', 100)]),
        stock: {'flour': stockOf('flour', 100)},
        items: items(['flour']),
        today: today,
        batchesByItem: {
          'flour': [batch('edge', 100, expiry: 20260814)],
        },
      );

      expect(
        verdict.checks.single.availability,
        IngredientAvailability.sufficient,
      );
    });

    test(
      'batches in a category the requirement was never bridged into are declined',
      () {
        // The consumption service refuses this as a validation error rather than a shortfall, and the
        // engine passes that through as its own "I cannot compare" state. Reporting `short` would be a
        // confident falsehood about stock it never looked at.
        final verdict = kEngine.judge(
          recipeOf(ingredients: [linked('flour', 100)]),
          stock: {'flour': stockOf('flour', 500)},
          items: items(['flour']),
          today: today,
          batchesByItem: {
            'flour': [
              ConsumableBatch(
                batchId: 'wrong',
                remaining: const Qty(500000, UnitCategory.volume),
                purchasedDateKey: const DateKey(20260701),
              ),
            ],
          },
        );

        expect(
          verdict.checks.single.availability,
          IngredientAvailability.unitMismatch,
        );
      },
    );

    test(
      'the same stock without batches reports sufficient — the documented trade',
      () {
        // **Pins the approximation `judge` documents.** Omitting batches keeps the previous behaviour,
        // which is what a list of forty recipes wants and which cannot see expiry. The detail screen
        // supplies batches; the list does not. This assertion is here so nobody "fixes" the coarse path
        // without noticing it was deliberate.
        final verdict = kEngine.judge(
          recipeOf(ingredients: [linked('flour', 200)]),
          stock: {'flour': stockOf('flour', 300)},
          items: items(['flour']),
          today: today,
        );

        expect(
          verdict.checks.single.availability,
          IngredientAvailability.sufficient,
        );
        expect(verdict.checks.single.plan, isNull, reason: 'not computed');
      },
    );
  });
}
```

### `test/features/recipe/recipe_detail_screen_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/quantity/fraction.dart';
import 'package:alaya/core/quantity/measure.dart';
import 'package:alaya/features/recipe/presentation/screens/recipe_detail_screen.dart';

import '../../support/recipe_harness.dart';

/// The recipe detail screen — **the first widget test it has ever had.**
///
/// That absence is why this bug lasted. `RecipeDetailScreen` appeared in no test file, and it could not
/// have: `recipeProvider` resolves `recipeRepositoryProvider`, which needs a database, and
/// `recipeOverrides` did not cover it. So the screen a cook actually reads while cooking was never
/// pumped, and it rendered `7 ml` for a line that said half a tablespoon — the unit stored, and thrown
/// away at render time — through every green run of the suite.
///
/// The assertions below are the ones whose absence allowed that.
void main() {
  /// Flour, weighed, with a stated tablespoon weight so the engine can judge a spoon against stock.
  ///
  /// 8 g per tablespoon is what a cooking table says, and `densityMilliGramsPerMl` is that figure
  /// divided across a tablespoon's 14.787 ml — the item editor asks the question the human way round and
  /// stores it this way.
  final flour = weightItem('flour', 'Flour', densityMilliGramsPerMl: 541);

  group('a vessel line is shown in its vessel', () {
    testWidgets('half a tablespoon reads as a half tablespoon, not 7 ml', (
      tester,
    ) async {
      // **The regression this whole change exists for.** 1/2 tbsp stores as `Qty(7394, volume)`; the row
      // used to render that canonical figure and the cook read `7 ml`.
      await pumpRecipe(
        tester,
        const RecipeDetailScreen(recipeId: 'r1'),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(
              ingredients: [inVessel('flour', Measure.of(0, Fraction(1, 2)))],
            ),
          ],
          stock: {'flour': stockOf('flour', 500)},
          items: {'flour': flour},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.text('1/2 tbsp'), findsOneWidget);
      // The old rendering, asserted absent by name. Without this the test would pass if the row showed
      // both figures, which is not the fix — it is clutter with the bug still in it.
      expect(find.textContaining('ml'), findsNothing);
    });

    testWidgets('a whole number of cups carries no fraction', (tester) async {
      await pumpRecipe(
        tester,
        const RecipeDetailScreen(recipeId: 'r1'),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(
              ingredients: [
                inVessel('flour', const Measure(2000), code: 'cup'),
              ],
            ),
          ],
          stock: {'flour': stockOf('flour', 5000)},
          items: {'flour': flour},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.text('2 cup'), findsOneWidget);
    });

    testWidgets('a line the engine cannot judge still says what to measure', (
      tester,
    ) async {
      // **An item with no stated tablespoon weight.** The engine reports `unitMismatch` and `required_`
      // is null, so the old row rendered nothing at all — the cook was told a spoonful of something with
      // no indication of how much. The amount comes from what they wrote, which is always available.
      await pumpRecipe(
        tester,
        const RecipeDetailScreen(recipeId: 'r1'),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(
              ingredients: [inVessel('salt', Measure.of(1, Fraction(1, 4)))],
            ),
          ],
          stock: {'salt': stockOf('salt', 200)},
          items: {'salt': weightItem('salt', 'Salt')},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.text('1 1/4 tbsp'), findsOneWidget);
    });
  });

  group('everything else keeps QtyText', () {
    testWidgets('a weight line is unchanged', (tester) async {
      // The narrowing, asserted. Only tsp, tbsp and cup take the new path; grams keep the decomposition
      // every other screen in the app uses, and `200 g` is not `200 g` by accident.
      await pumpRecipe(
        tester,
        const RecipeDetailScreen(recipeId: 'r1'),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(ingredients: [linked('flour', 200)]),
          ],
          stock: {'flour': stockOf('flour', 500)},
          items: {'flour': flour},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('200'), findsWidgets);
      expect(find.textContaining('tbsp'), findsNothing);
    });
  });

  group('scaling, and the glyph that admits it', () {
    testWidgets('an amount no drawer can hold snaps, and says so', (
      tester,
    ) async {
      // Half a cup written for 3 servings, read at 2: 500 x 2 / 3, rounded up, is 334 thousandths.
      // That is not any simple fraction — exact style would render `0.334` — so kitchen style snaps it
      // to the third of a cup that is 1 thousandth away and marks it. This one assertion is the whole
      // design: a derived number, rendered as something measurable, and not passed off as exact.
      await pumpRecipe(
        tester,
        const RecipeDetailScreen(recipeId: 'r1'),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(
              servings: 3,
              ingredients: [
                inVessel('flour', const Measure(500), code: 'cup'),
              ],
            ),
          ],
          stock: {'flour': stockOf('flour', 5000)},
          items: {'flour': flour},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      // Down from 3 servings to 2.
      await tester.tap(find.byTooltip('Fewer servings'));
      await tester.pumpAndSettle();

      expect(find.text('\u2248 1/3 cup'), findsOneWidget);
      // And the legend appears with it, because a mark nobody can interpret is worse than no mark.
      expect(find.textContaining('rounded to the nearest'), findsOneWidget);
    });

    testWidgets('an amount that divides cleanly is not marked', (tester) async {
      // A third of a cup written for 4 servings, read at 3, is exactly a quarter cup. Nothing was
      // approximated, so nothing claims to have been — no glyph, and the legend is the only thing on
      // screen admitting the numbers moved at all.
      await pumpRecipe(
        tester,
        const RecipeDetailScreen(recipeId: 'r1'),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(
              servings: 4,
              ingredients: [
                inVessel('flour', Measure.of(0, Fraction(1, 3)), code: 'cup'),
              ],
            ),
          ],
          stock: {'flour': stockOf('flour', 5000)},
          items: {'flour': flour},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Fewer servings'));
      await tester.pumpAndSettle();

      expect(find.text('1/4 cup'), findsOneWidget);
      // **Scoped to the amount, not the screen.** The legend under the servings dial contains `≈` by
      // design — it is the sentence explaining the mark — so a screen-wide search for the glyph can
      // never come back empty once the dial has moved. What must be absent is the *marked* rendering of
      // this row, which is a different claim and the one worth making.
      //
      // I asserted the screen-wide version first and it failed on its own legend. Worth the comment:
      // the broad finder reads as the stronger assertion and is the one that cannot hold.
      expect(find.text('\u2248 1/4 cup'), findsNothing);
    });

    testWidgets('at the recipe own serving count nothing is marked at all', (
      tester,
    ) async {
      // The condition that must never produce a glyph: an untouched dial. The amount is what the cook
      // typed, and snapping a value they chose deliberately would be the screen overruling them.
      await pumpRecipe(
        tester,
        const RecipeDetailScreen(recipeId: 'r1'),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(
              servings: 3,
              ingredients: [
                inVessel('flour', const Measure(334), code: 'cup'),
              ],
            ),
          ],
          stock: {'flour': stockOf('flour', 5000)},
          items: {'flour': flour},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      // 334 thousandths of a cup has no simple fraction, so exact style renders the decimal rather than
      // pretending. Honest, and unmarked, because nothing was rounded.
      expect(find.text('0.334 cup'), findsOneWidget);
      expect(find.textContaining('\u2248'), findsNothing);
      expect(find.textContaining('rounded to the nearest'), findsNothing);
    });
  });
}
```

### `test/features/recipe/recipe_editor_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/recipe/amount_format.dart';
import 'package:alaya/features/recipe/presentation/screens/recipe_editor_screen.dart';
import 'package:alaya/features/recipe/providers/recipe_editor_providers.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';

import '../../support/recipe_harness.dart';

/// The editor, which is where a recipe becomes something the engine can reason about.
///
/// **Two things make an ingredient count: a link to stock and a measured amount.** For most of this
/// module's life the row offered neither, so every recipe saved as untracked text and every cook
/// deducted nothing. These tests exist to keep that from returning quietly.
void main() {
  group('an ingredient can be linked and measured', () {
    testWidgets('a new recipe starts with no ingredient rows', (tester) async {
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // No unit dropdown until an ingredient exists: the recipe's own fields — name, servings, prep,
      // cook, notes — are all plain text.
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });

    testWidgets('adding a row offers an amount AND a unit', (tester) async {
      // A row without a unit picker cannot produce a Qty, which is precisely how every ingredient
      // came out null. Asserted through what the user sees rather than the widget class: the control
      // behind it has already been swapped once, because a recipe must be able to offer spoons for
      // something stored by weight, and a test naming the class failed on a change that did not alter
      // the behaviour it was written to protect.
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('choosing a spoon offers the sizes a drawer actually has', (
      tester,
    ) async {
      // A cook reaches for the half-teaspoon rather than typing 0.5. The chips are only for spoons and
      // cups, so a grams row must not show them — that distinction is the whole reason the hint used to
      // be confusing.
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(units: kSpoonTestUnits),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();
      // Defaults to grams, so no chips.
      expect(find.byType(ChoiceChip), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tablespoon').last);
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(6));
      expect(find.widgetWithText(ChoiceChip, '1/2'), findsOneWidget);
    });

    testWidgets('every unit is offered, whether or not it can be converted', (
      tester,
    ) async {
      // Writing a recipe is never gated on inventory setup. An earlier version hid spoons until the
      // item declared a tablespoon weight, which made "2 tbsp oil" impossible to write before
      // configuring oil — backwards, and the reason this test exists.
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(
          items: [weightItem('f1', 'Flour')],
          units: kSpoonTestUnits,
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('Tablespoon').last, findsOneWidget);
    });

    testWidgets('typing an ingredient name offers matching catalogue items', (
      tester,
    ) async {
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(items: [weightItem('t1', 'Tomatoes')]),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(4), 'tom');
      await tester.pumpAndSettle();
      // The option is what links the line to stock. Without it the row is free text, which saves
      // fine and can never be checked against inventory.
      expect(find.text('Tomatoes'), findsWidgets);
    });
  });

  group('the form guards itself', () {
    testWidgets('save is disabled until there is a name and an ingredient', (
      tester,
    ) async {
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      // A recipe with no usable ingredient is a note. The engine would report it as `empty`, so the
      // form refuses it rather than storing something the catalogue cannot describe.
      final scaffold = tester.widget<AlayaFormScaffold>(
        find.byType(AlayaFormScaffold),
      );
      expect(scaffold.onPrimary, isNull);
    });

    testWidgets('steps and ingredients do not collide on their keys', (
      tester,
    ) async {
      // Both lists once keyed by position, in the same Column — so ingredient 0 and step 0 were two
      // widgets keyed 0 under one parent, which Flutter refuses outright.
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add step'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('removing a row takes its text with it', (tester) async {
      // The quiet half of the key bug: with positional keys, deleting row 0 left row 1 inheriting
      // row 0's field element, so the deleted row's text stayed on screen.
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(4), 'First');
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(6), 'Second');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
    });
  });

  group('every measuring size survives the round trip', () {
    // The bug this group exists for: a written amount is converted to base-milli units for storage and
    // back again for display. Truncating either way turned 1/2 tbsp into 0.499 — so the field showed a
    // number nobody typed and the 1/2 chip never highlighted, which read as "fractions do not work".
    //
    // Whole numbers passed throughout, because a factor divides 1000 exactly at 1x. That is what made
    // it look like a missing feature instead of an arithmetic error.
    for (final code in ['tsp', 'tbsp', 'cup']) {
      testWidgets('$code keeps each standard size exactly', (tester) async {
        await pumpRecipe(
          tester,
          const RecipeEditorScreen(recipeId: ''),
          overrides: editorOverrides(units: kAllMeasureTestUnits),
          size: kTallViewport,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add ingredient'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(_displayName(code)).last);
        await tester.pumpAndSettle();

        for (final label in ['1/4', '1/3', '1/2', '2/3', '3/4']) {
          await tester.tap(find.widgetWithText(ChoiceChip, label));
          await tester.pumpAndSettle();
          // Selected means the value read back equals the value written. Anything lost in the
          // conversion shows up here and nowhere else.
          final chip = tester.widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, label),
          );
          expect(
            chip.selected,
            isTrue,
            reason: '$label of $code did not round-trip',
          );
        }
      });
    }
  });

  group('a number and a fraction', () {
    testWidgets('3 and a half tablespoons is a number then a tap', (
      tester,
    ) async {
      // What a cook does at the counter: three tablespoons, then the half. Typing `3 1/2` into one
      // field asked them to assemble a string instead.
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(units: kAllMeasureTestUnits),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tablespoon').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(5), '3');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '1/2'));
      await tester.pumpAndSettle();

      // The readout is the proof: 3.5 tbsp is 51.75 ml, and it says so.
      expect(find.textContaining('3 1/2'), findsWidgets);
      final half = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '1/2'),
      );
      expect(half.selected, isTrue);
    });

    testWidgets('tapping the lit fraction clears it, keeping the number', (
      tester,
    ) async {
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(units: kAllMeasureTestUnits),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ingredient'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tablespoon').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(5), '2');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '1/4'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '1/4'));
      await tester.pumpAndSettle();

      // "2 1/4" and "2" are one tap apart in both directions, which is the whole point of a toggle.
      final quarter = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '1/4'),
      );
      expect(quarter.selected, isFalse);
    });
  });

  group('the gate', () {
    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpRecipe(
        tester,
        const RecipeEditorScreen(recipeId: ''),
        overrides: editorOverrides(),
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

/// The display name the seeded unit carries, for tapping a dropdown entry.
String _displayName(String code) => switch (code) {
  'tsp' => 'Teaspoon',
  'tbsp' => 'Tablespoon',
  'cup' => 'Cup',
  _ => code,
};
```

### `test/features/recipe/recipe_list_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/recipe/presentation/screens/recipe_list_screen.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';

import '../../support/recipe_harness.dart';

/// The catalogue's four states, and the badge that has to tell the truth (ARCH_5 §9.1).
void main() {
  group('four states', () {
    testWidgets('loading is a skeleton', (tester) async {
      // A `Stream.value` resolves in the first frame's microtask drain, so the loading branch would
      // be gone before the assertion. The harness holds the stream open instead.
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(loading: true),
      );
      expect(find.byType(AlayaListSkeleton), findsOneWidget);
    });

    testWidgets('empty invites the first recipe', (tester) async {
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('populated lists every recipe', (tester) async {
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(name: 'Dal'),
            recipeOf(id: 'r2', name: 'Pulao'),
          ],
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.text('Dal'), findsOneWidget);
      expect(find.text('Pulao'), findsOneWidget);
    });

    testWidgets('a way in exists — the catalogue can be added to', (
      tester,
    ) async {
      // Four screens in Phase 8B were built, routed, tested and unreachable. A catalogue with no
      // add affordance is the same failure one level in.
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  group('the badge tells the truth', () {
    testWidgets('everything on hand reads as ready', (tester) async {
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(ingredients: [linked('flour', 200)]),
          ],
          stock: {'flour': stockOf('flour', 500)},
          items: {'flour': weightItem('flour', 'Flour')},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.text('Ready'), findsOneWidget);
    });

    testWidgets("an untracked ingredient reads as can't tell, NOT as missing", (
      tester,
    ) async {
      // The distinction the whole module exists for. "Can't cook" would be a confident falsehood.
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(ingredients: [untracked('salt')]),
          ],
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.text("Can't tell"), findsOneWidget);
      expect(find.textContaining('missing'), findsNothing);
    });

    testWidgets('a shortfall says how many, not just that there is one', (
      tester,
    ) async {
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(ingredients: [linked('flour', 200)]),
          ],
          stock: {'flour': stockOf('flour', 150)},
          items: {'flour': weightItem('flour', 'Flour')},
        ),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.text('1 short'), findsOneWidget);
    });

    testWidgets('no badge at all while stock is still arriving', (
      tester,
    ) async {
      // A placeholder would read as a verdict. Better to show nothing than to imply an answer.
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: [
          ...recipeOverrides(recipes: [recipeOf()]),
        ],
        size: kTallViewport,
      );
      await tester.pump();
      expect(find.text('Ready'), findsNothing);
    });
  });

  group('the gate', () {
    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpRecipe(
        tester,
        const RecipeListScreen(),
        overrides: recipeOverrides(
          recipes: [
            recipeOf(
              name: 'A very long recipe name that will wrap at this width',
            ),
            recipeOf(
              id: 'r2',
              name: 'Pulao',
              ingredients: [linked('rice', 300)],
            ),
          ],
          stock: {'rice': stockOf('rice', 100)},
          items: {'rice': weightItem('rice', 'Rice')},
        ),
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
```
