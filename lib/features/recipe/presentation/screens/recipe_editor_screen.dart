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
