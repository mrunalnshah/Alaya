import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/settings/presentation/widgets/unit_labels.dart';
import 'package:alaya/features/settings/providers/unit_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Creating or editing one unit (ARCH_5 §3 archetype B).
///
/// **The escape is the point of this screen as much as the form is.** A unit has to be the same amount every
/// time; a "packet" is not, so it cannot have a factor, so it cannot be a unit. `UnitCategory`'s own doc has
/// said since Phase 1A that *"if an amount can't be expressed in one of these, the correct action is a new
/// Item, never a new category"* — this screen is where that rule finally meets a person, and it is offered
/// beside the factor field rather than thrown back as a validation error after they have tried.
///
/// **The question is asked in base units, never in the stored thousandths.** "How many grams is one
/// kilogram?" — 1,000 — and `UnitEditorNotifier` multiplies once. Asking for 1,000,000 would be asking the
/// user to reproduce the arithmetic ARCH_4 R18 got wrong three times.
class UnitEditorScreen extends ConsumerStatefulWidget {
  /// Creates the editor. [unitCode] null means a new unit.
  const UnitEditorScreen({this.unitCode, super.key});

  /// The unit being edited, or null for a new one.
  final String? unitCode;

  @override
  ConsumerState<UnitEditorScreen> createState() => _UnitEditorScreenState();
}

class _UnitEditorScreenState extends ConsumerState<UnitEditorScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  UnitCategory _category = UnitCategory.weight;
  int _sortOrder = 0;
  bool _isSystem = false;
  bool _dirty = false;
  bool _loaded = false;

  /// Whether the user has said the amount varies.
  ///
  /// Local rather than in the notifier: it is a state of the conversation, not of the unit — nothing about it
  /// is ever saved, and a provider holding it would survive a route the user has left.
  bool _varies = false;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _adopt(Unit? unit) {
    if (_loaded) return;
    _loaded = true;
    if (unit == null) return;
    _code.text = unit.code;
    _name.text = unit.displayName;
    _category = unit.category;
    _amount.text = unitBaseAmountLabel(unit).replaceAll(',', '');
    _sortOrder = unit.sortOrder;
    _isSystem = unit.isSystem;
  }

  double? get _baseAmount => double.tryParse(_amount.text.trim());

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(unitDraftProvider(widget.unitCode));
    final editing = ref.watch(unitEditorProvider);

    return draft.when(
      loading: () => _shell(strings, const SizedBox.shrink()),
      error: (error, stack) => _shell(
        strings,
        ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(unitDraftProvider(widget.unitCode)),
        ),
      ),
      data: (unit) {
        if (widget.unitCode != null && unit == null) {
          return _shell(
            strings,
            ErrorState(
              title: strings.unitsMissingTitle,
              body: strings.unitsMissingBody,
              retryLabel: strings.actionBack,
              onRetry: () => context.pop(),
            ),
          );
        }
        _adopt(unit);

        // The escape replaces the form entirely. Leaving the fields visible underneath would invite somebody
        // to type a number they have just been told does not exist.
        if (_varies)
          return _shell(
            strings,
            _VariesPanel(onBack: () => setState(() => _varies = false)),
          );

        final amount = _baseAmount;
        final canSave =
            _code.text.trim().isNotEmpty &&
            _name.text.trim().isNotEmpty &&
            amount != null &&
            amount > 0;

        return _shell(
          strings,
          AlayaFormScaffold(
            primaryLabel: strings.unitEditorSave,
            onPrimary: canSave && !editing.isLoading ? () => _save(unit) : null,
            isDirty: _dirty,
            isSubmitting: editing.isLoading,
            discardTitle: strings.confirmDiscardTitle,
            discardBody: strings.confirmDiscardBody,
            discardConfirmLabel: strings.actionDiscard,
            discardCancelLabel: strings.actionKeepEditing,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  autofocus: unit == null,
                  decoration: InputDecoration(labelText: strings.unitNameLabel),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: AlayaSpacing.md),
                TextField(
                  controller: _code,
                  // The code is a primary key (ARCH_2 §2), so it is fixed once anything references it.
                  enabled: unit == null,
                  decoration: InputDecoration(
                    labelText: strings.unitCodeLabel,
                    helperText: unit == null
                        ? strings.unitCodeHelp
                        : strings.unitCodeLockedHelp,
                  ),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: AlayaSpacing.lg),
                SectionHeader(label: strings.unitCategoryHeader),
                const SizedBox(height: AlayaSpacing.xxs),
                Text(
                  unit == null
                      ? strings.unitCategoryNewHelp
                      : strings.unitCategoryLockedHelp,
                  style: AlayaTypography.caption.copyWith(
                    color: context.semantic.muted,
                  ),
                ),
                const SizedBox(height: AlayaSpacing.xs),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    for (final category in UnitCategory.values)
                      ChoiceChip(
                        label: Text(
                          unitCategoryLabel(strings, category),
                          style: AlayaTypography.button,
                        ),
                        selected: category == _category,
                        // Changing a unit's category after quantities exist would reinterpret every one of
                        // them, so it is offered only while the unit is new — the same rule as an account's
                        // currency, for the same reason.
                        onSelected: unit == null
                            ? (_) => setState(() {
                                _category = category;
                                _dirty = true;
                              })
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: AlayaSpacing.lg),
                SectionHeader(label: strings.unitFactorHeader),
                const SizedBox(height: AlayaSpacing.xs),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    // Three decimals, which is exactly what the milli-precision column can hold. Allowing a
                    // fourth would silently round it away at save.
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,3}'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: strings.unitFactorQuestion(
                      unitBaseUnitName(strings, _category),
                      _name.text.trim().isEmpty
                          ? strings.unitFactorThisUnit
                          : _name.text.trim(),
                    ),
                    helperText: strings.unitFactorHelp(
                      unitBaseUnitName(strings, _category),
                    ),
                  ),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: AlayaSpacing.xs),
                // Offered, not withheld until failure. This is the path for a "packet" or a "bunch", and a
                // user who has that in mind should meet it before typing a number they will have to defend.
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _varies = true),
                    icon: const Icon(
                      Icons.help_outline,
                      size: AlayaIconSize.md,
                    ),
                    label: Text(
                      strings.unitFactorVaries,
                      style: AlayaTypography.button,
                    ),
                  ),
                ),
                if (unit != null && !_isSystem) ...[
                  const SizedBox(height: AlayaSpacing.xl),
                  OutlinedButton(
                    onPressed: editing.isLoading ? null : () => _delete(unit),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.semantic.danger,
                    ),
                    child: Text(
                      strings.unitsDelete,
                      style: AlayaTypography.button,
                    ),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  Text(
                    strings.unitsDeleteHelp,
                    style: AlayaTypography.caption.copyWith(
                      color: context.semantic.muted,
                    ),
                  ),
                ],
                if (editing.hasError) ...[
                  const SizedBox(height: AlayaSpacing.md),
                  Text(
                    // `_ZeroFactor` stringifies to a key rather than a sentence, so the screen owns the words
                    // (Law U5) while the notifier owns the decision.
                    editing.error.toString() == 'factorMustBePositive'
                        ? strings.unitFactorMustBePositive
                        : editing.error.toString(),
                    style: AlayaTypography.body.copyWith(
                      color: context.semantic.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _shell(AlayaStrings strings, Widget body) => Scaffold(
    appBar: AppBar(
      leading: const CloseButton(),
      title: Text(
        widget.unitCode == null
            ? strings.unitEditorTitle
            : strings.unitEditorEditTitle,
      ),
    ),
    body: body,
  );

  Future<void> _save(Unit? existing) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref
        .read(unitEditorProvider.notifier)
        .save(
          code: _code.text,
          displayName: _name.text,
          category: _category,
          baseUnitsPerUnit: _baseAmount!,
          sortOrder: existing?.sortOrder ?? _sortOrder,
          isSystem: _isSystem,
        );
    if (!mounted || !saved) return;
    showResultSnack(context, message: strings.unitsSaved);
    context.pop();
  }

  Future<void> _delete(Unit unit) async {
    final strings = AlayaStrings.of(context);
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.unitsDeleteConfirmTitle,
      // Says what breaks rather than only what goes: a batch bought in this unit keeps its quantity, and
      // deleting the unit is what makes that quantity unreadable — the R18 failure from the other direction.
      body: strings.unitsDeleteConfirmBody,
      confirmLabel: strings.unitsDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final ok = await ref.read(unitEditorProvider.notifier).delete(unit.code);
    if (!mounted || !ok) return;
    showResultSnack(context, message: strings.unitsDeleted);
    context.pop();
  }
}

/// The explanation, and the offer.
///
/// **A refusal with somewhere to go.** ARCH_1 §5.3 says the answer to an unmeasurable amount is a new Item, and
/// this panel says why in terms of what would break — Alaya could not add two packets together or work out what
/// one cost — rather than quoting the rule. Then it offers the thing that does work, one tap away.
class _VariesPanel extends StatelessWidget {
  const _VariesPanel({required this.onBack});

  /// Returns to the form, for somebody who realises they can state a number after all.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AlayaSpacing.md),
            decoration: BoxDecoration(
              color: semantic.warning.withValues(alpha: 0.12),
              borderRadius: AlayaRadii.borderMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.unitVariesTitle,
                  style: AlayaTypography.bodyEmphasis,
                ),
                const SizedBox(height: AlayaSpacing.xs),
                Text(strings.unitVariesWhy, style: AlayaTypography.body),
              ],
            ),
          ),
          const SizedBox(height: AlayaSpacing.lg),
          Text(
            strings.unitVariesInsteadTitle,
            style: AlayaTypography.bodyEmphasis,
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Text(strings.unitVariesInsteadBody, style: AlayaTypography.body),
          const SizedBox(height: AlayaSpacing.lg),
          FilledButton.icon(
            // Straight to the item editor — the offer is only an offer if it goes somewhere.
            onPressed: () => context.push(Routes.itemNew),
            icon: const Icon(Icons.add, size: AlayaIconSize.md),
            label: Text(
              strings.unitVariesCreateItem,
              style: AlayaTypography.button,
            ),
          ),
          const SizedBox(height: AlayaSpacing.xs),
          TextButton(
            onPressed: onBack,
            child: Text(strings.unitVariesBack, style: AlayaTypography.button),
          ),
        ],
      ),
    );
  }
}
