import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/inventory/state/consume_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/qty_field.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Takes stock off an item (ARCH_5 §3 archetype A).
///
/// **FEFO is pre-selected and named, not silent.** The sheet says which batch it will draw from and
/// offers the alternatives as chips, because "use some flour" and "use the jar that expires on
/// Tuesday" are the same gesture to the user and completely different rows in the ledger.
///
/// **A consume that spans batches says so before committing.** The preview walks the same FEFO
/// ordering the repository does and reports how many movements the write will append, so a user who
/// takes 3 kg from three 1 kg jars is told three entries are coming rather than discovering it in the
/// history afterwards.
///
/// Used, thrown away and expired are three distinct `StockMovementKind`s rather than one kind with a
/// reason, because Phase 7B's waste insight aggregates on the column and cannot read prose.
class ConsumeSheet extends ConsumerWidget {
  /// Creates the sheet.
  const ConsumeSheet({
    required this.itemId,
    required this.unitCode,
    required this.category,
    super.key,
  });

  /// Which item is being drawn down.
  final String itemId;

  /// The unit the quantity field starts in.
  final String unitCode;

  /// The item's measure, so the unit picker never offers a cross-category unit (Law L8).
  final UnitCategory category;

  /// Opens the sheet.
  static Future<void> show(
    BuildContext context, {
    required String itemId,
    required String unitCode,
    required UnitCategory category,
  }) => AlayaBottomSheet.show<void>(
    context: context,
    builder: (context) => ConsumeSheet(
      itemId: itemId,
      unitCode: unitCode,
      category: category,
    ),
  );

  static String _kindChipLabel(AlayaStrings strings, StockMovementKind kind) =>
      switch (kind) {
        StockMovementKind.waste => strings.consumeKindWaste,
        StockMovementKind.expired => strings.consumeKindExpired,
        _ => strings.consumeKindConsume,
      };

  static String _commitLabel(AlayaStrings strings, StockMovementKind kind) =>
      switch (kind) {
        StockMovementKind.waste => strings.consumeCommitWaste,
        StockMovementKind.expired => strings.consumeCommitExpired,
        _ => strings.consumeCommitUsed,
      };

  Future<void> _commit(
    BuildContext context,
    WidgetRef ref,
    ConsumeArgs args,
  ) async {
    final strings = AlayaStrings.of(context);
    final written = await ref.read(consumeProvider(args).notifier).commit();
    if (!context.mounted) return;
    if (written == null) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    Navigator.of(context).pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.consumeRecorded);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final args = (itemId: itemId, unitCode: unitCode);
    final state = ref.watch(consumeProvider(args));
    final notifier = ref.read(consumeProvider(args).notifier);
    final fefo = ref.watch(consumeFefoProvider(itemId));
    final units =
        ref.watch(unitsInCategoryProvider(category)).valueOrNull ??
        const <Unit>[];

    Unit? selected;
    for (final unit in units) {
      if (unit.code == state.unitCode) selected = unit;
    }

    final batches = fefo.valueOrNull ?? const <Batch>[];
    final plan = state.planAgainst(batches);
    final shortfall = state.shortfallAgainst(batches);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.consumeTitle,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (units.isNotEmpty)
          ShakeOnError(
            trigger: state.shakeTrigger,
            child: QtyField(
              category: category,
              units: units,
              selectedUnit: selected ?? units.first,
              label: strings.labelQuantity,
              unitLabel: strings.labelUnit,
              initialValue: state.quantity,
              errorText: state.quantityMissing
                  ? strings.errorQuantityInvalid
                  : shortfall != null
                  ? strings.consumeOverAvailable
                  : null,
              onChanged: notifier.setQuantity,
              onUnitChanged: (unit) => notifier.setUnitCode(unit.code),
            ),
          ),
        const SizedBox(height: AlayaSpacing.md),
        // **Chips above 1.5x, a segmented button below it.** `SegmentedButton` lays its segments out
        // in a Row that cannot wrap, so three labels at a doubled text scale overflow 320dp by about
        // 50px. A `Wrap` of `ChoiceChip`s is the same choice with the same semantics and reflows
        // instead of clipping (Law U15).
        if (MediaQuery.textScalerOf(context).scale(1) >= 1.5)
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              for (final option in const [
                StockMovementKind.consume,
                StockMovementKind.waste,
                StockMovementKind.expired,
              ])
                ChoiceChip(
                  selected: state.kind == option,
                  onSelected: (_) => notifier.setKind(option),
                  label: Text(_kindChipLabel(strings, option)),
                ),
            ],
          )
        else
          SegmentedButton<StockMovementKind>(
            segments: [
              ButtonSegment(
                value: StockMovementKind.consume,
                label: Text(strings.consumeKindConsume),
              ),
              ButtonSegment(
                value: StockMovementKind.waste,
                label: Text(strings.consumeKindWaste),
              ),
              ButtonSegment(
                value: StockMovementKind.expired,
                label: Text(strings.consumeKindExpired),
              ),
            ],
            selected: {state.kind},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                notifier.setKind(selection.first),
          ),
        const SizedBox(height: AlayaSpacing.md),
        _BatchChips(
          batches: batches,
          state: state,
          plan: plan,
          onPick: notifier.setBatch,
        ),
        if (plan.length > 1 || (plan.length == 1 && !state.isOverridden)) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(
              label: strings.consumeSpansBatches(plan.length),
              tone: plan.length > 1 ? StatusTone.info : StatusTone.neutral,
            ),
          ),
        ],
        if (state.kind != StockMovementKind.consume) ...[
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.reason,
            decoration: InputDecoration(
              labelText: strings.labelNote,
              hintText: strings.deleteReasonHint,
            ),
            onChanged: notifier.setReason,
          ),
        ],
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          // Blocked rather than warned (§5.5): the repository would refuse a draw larger than the
          // batches hold, and a button that fails on press teaches the user the app is unreliable.
          onPressed: state.submitting || shortfall != null
              ? null
              : () => _commit(context, ref, args),
          // States the action rather than "Record" (U14), and does it from one ARB key per kind so no
          // separator glyph is glued on in code.
          child: Text(_commitLabel(strings, state.kind)),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionCancel),
        ),
        if (fefo.hasError)
          Padding(
            padding: const EdgeInsets.only(top: AlayaSpacing.xs),
            child: Text(
              strings.errorBodyGeneric,
              style: AlayaTypography.caption.copyWith(color: semantic.danger),
            ),
          ),
      ],
    );
  }
}

class _BatchChips extends StatelessWidget {
  const _BatchChips({
    required this.batches,
    required this.state,
    required this.plan,
    required this.onPick,
  });

  final List<Batch> batches;
  final ConsumeState state;
  final List<ConsumePlanLeg> plan;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    if (batches.isEmpty) return const SizedBox.shrink();

    final fefoId = plan.isEmpty ? batches.first.id : plan.first.batch.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.consumeFromLabel,
          style: AlayaTypography.label.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final batch in batches)
              ChoiceChip(
                selected: state.isOverridden
                    ? state.overrideBatchId == batch.id
                    : batch.id == fefoId,
                onSelected: (_) =>
                    onPick(state.overrideBatchId == batch.id ? null : batch.id),
                label: _BatchChipLabel(batch: batch),
              ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        Text(
          strings.consumeFefoNote,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
      ],
    );
  }
}

class _BatchChipLabel extends StatelessWidget {
  const _BatchChipLabel({required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final expiry = batch.expiryDateKey;
    // A `Wrap`, not a `Row`. A chip constrains its label, and at a doubled text scale a quantity plus
    // a date is about 50px wider than the chip allows — the last overflow left in this sheet after the
    // segmented button was fixed (Law U21).
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AlayaSpacing.xxs,
      children: [
        QtyText(batch.remainingQuantity),
        if (expiry != null)
          DateText(expiry, style: DateTextStyle.dayMonth, muted: true),
      ],
    );
  }
}
