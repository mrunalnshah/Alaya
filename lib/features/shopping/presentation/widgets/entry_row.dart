import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One shopping row: a tick, what to buy, and what it is expected to cost.
///
/// **A suggested row is marked as suggested.** `origin = autoLowStock` means the app put it there,
/// not the user, and the snooze and dismiss actions only make sense against something the app
/// proposed — offering them on a row someone typed would read as the app second-guessing them.
///
/// Stacks above 1.5x text scale: the estimate is not flexible, so at a doubled scale it starves the
/// label beside it, and `AmountText` clips rather than ellipsises (Law U15).
class EntryRow extends StatelessWidget {
  /// Creates the row.
  const EntryRow({
    required this.entry,
    required this.item,
    required this.decimalDigits,
    required this.onToggle,
    required this.onTap,
    this.onSnooze,
    this.onDismiss,
    this.onDelete,
    super.key,
  });

  /// The entry.
  final ShoppingEntry entry;

  /// The catalogued item it restocks, if any.
  final Item? item;

  /// The home currency's precision.
  final int decimalDigits;

  /// Ticks or unticks it.
  final ValueChanged<bool> onToggle;

  /// Opens the entry editor.
  final VoidCallback onTap;

  /// Hides a suggestion for a week.
  final VoidCallback? onSnooze;

  /// Dismisses a suggestion until stock recovers and drops again.
  final VoidCallback? onDismiss;

  /// Removes the entry, with the caller responsible for offering an undo.
  ///
  /// Null makes the row undismissable, which is how the convert-to-purchase screen reuses it — deleting
  /// a line mid-checkout would change what you are about to pay for.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final delete = onDelete;
    if (delete == null) return _content(context);

    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    return Dismissible(
      // Keyed on the entry, not the position. A list that reorders while a swipe is in flight would
      // otherwise delete whichever row slid into that index.
      key: ValueKey<String>('shopping-entry-${entry.id}'),
      // **`endToStart`, not "left".** It means the trailing edge, so the gesture stays natural when the
      // locale flips — and Alaya's 1,100 ARB keys exist because RTL is on the table.
      direction: DismissDirection.endToStart,
      // No confirmation dialog. The caller offers an undo instead, which costs one tap to reverse rather
      // than one tap to authorise — and the thing being removed is a line on a shopping list, not money.
      onDismissed: (_) => delete(),
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(
          horizontal: AlayaSpacing.screenEdge,
        ),
        // `surfaceSunken` behind `danger` content, rather than a saturated red panel. The swipe should
        // read as an action being revealed, not as an alarm — and `dangerSurface` was a token I invented;
        // the palette has `danger` and the four surfaces, nothing between them.
        color: semantic.surfaceSunken,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline,
              size: AlayaIconSize.md,
              color: semantic.danger,
            ),
            const SizedBox(width: AlayaSpacing.xs),
            Text(
              strings.actionDelete,
              style: AlayaTypography.button.copyWith(color: semantic.danger),
            ),
          ],
        ),
      ),
      child: _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final label = entry.freeText ?? item?.name ?? strings.labelItem;
    final price = entry.estimatedPrice;
    final quantity = entry.quantity;
    final snoozeUntil = entry.snoozeUntilDateKey;

    final estimate = price == null
        ? const SizedBox.shrink()
        : AmountText(
            price,
            size: AmountSize.small,
            showSign: false,
            decimalDigits: decimalDigits,
            muted: entry.isChecked,
            textAlign: stacked ? TextAlign.start : TextAlign.end,
          );

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
            vertical: AlayaSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A bare `Checkbox` announces a checked state and nothing else — a screen reader hears
              // "tick box" with no idea which row it belongs to. The label is the entry's own name,
              // which is exactly what a sighted user reads beside it (U16).
              Semantics(
                label: label,
                child: Checkbox(
                  value: entry.isChecked,
                  onChanged: (value) => onToggle(value ?? false),
                ),
              ),
              const SizedBox(width: AlayaSpacing.xxs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: AlayaSpacing.sm),
                      child: Text(
                        label,
                        style: AlayaTypography.body.copyWith(
                          color: entry.isChecked
                              ? semantic.muted
                              : theme.colorScheme.onSurface,
                          decoration: entry.isChecked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (quantity != null) ...[
                      const SizedBox(height: AlayaSpacing.xxs),
                      QtyText(quantity, muted: true),
                    ],
                    if (stacked && price != null) ...[
                      const SizedBox(height: AlayaSpacing.xxs),
                      estimate,
                    ],
                    if (entry.origin == ShoppingEntryOrigin.autoLowStock) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      Wrap(
                        spacing: AlayaSpacing.xs,
                        runSpacing: AlayaSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusChip(
                            label: strings.originAutoLowStock,
                            tone: StatusTone.info,
                            icon: Icons.auto_awesome_outlined,
                          ),
                          if (entry.autoState ==
                                  ShoppingEntryAutoState.snoozed &&
                              snoozeUntil != null)
                            StatusChip(
                              label: strings.snoozedUntilLabel,
                              trailing: DateText(
                                snoozeUntil,
                                style: DateTextStyle.dayMonth,
                                muted: true,
                              ),
                            ),
                          if (onSnooze != null)
                            TextButton(
                              onPressed: onSnooze,
                              child: Text(strings.actionSnooze),
                            ),
                          if (onDismiss != null)
                            TextButton(
                              onPressed: onDismiss,
                              child: Text(strings.actionDismiss),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (!stacked && price != null) ...[
                const SizedBox(width: AlayaSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(top: AlayaSpacing.sm),
                  child: estimate,
                ),
              ],
              if (item != null)
                Padding(
                  padding: const EdgeInsets.only(top: AlayaSpacing.sm),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: AlayaIconSize.sm,
                    color: semantic.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
