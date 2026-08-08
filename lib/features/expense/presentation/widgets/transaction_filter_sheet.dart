import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Narrows the transaction list (ARCH_5 §3 archetype A).
///
/// Chips rather than dropdowns throughout. A filter sheet is read at a glance and closed — a column
/// of dropdowns hides the current state behind six taps, which is the opposite of what a sheet whose
/// whole job is "show me what is on" should do.
///
/// **There is no tag filter.** No 3A contract exposes a tag-to-transactions reverse lookup, so it
/// would cost one query per visible row. Recorded as an ARCH_5 §7.3 gap owned by 7B, which builds
/// the analytics read model that needs the same join.
class TransactionFilterSheet extends ConsumerWidget {
  /// Creates the sheet. Prefer [show].
  const TransactionFilterSheet({super.key});

  /// Opens the sheet.
  static Future<void> show(BuildContext context) => AlayaBottomSheet.show<void>(
    context: context,
    builder: (context) => const TransactionFilterSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final filter = ref.watch(transactionFilterProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);
    final accounts =
        ref.watch(accountsByIdProvider).valueOrNull ??
        const <String, Account>{};

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings.filterTitle,
                style: AlayaTypography.cardTitle.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (filter.isNarrowed)
              TextButton(
                onPressed: notifier.clear,
                child: Text(strings.filterReset),
              ),
          ],
        ),
        SectionHeader(
          label: strings.filterDateRange,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.md,
            bottom: AlayaSpacing.xs,
          ),
        ),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final preset in DateRangePreset.values)
              if (preset != DateRangePreset.custom)
                _Choice(
                  label: rangeLabel(strings, preset),
                  selected: filter.preset == preset,
                  onTap: () => notifier.setPreset(preset),
                ),
          ],
        ),
        SectionHeader(
          label: strings.filterKind,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.md,
            bottom: AlayaSpacing.xs,
          ),
        ),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final kind in TransactionKind.values)
              _Choice(
                label: TransactionRow.kindLabel(strings, kind),
                selected: filter.kinds.contains(kind),
                onTap: () => notifier.toggleKind(kind),
              ),
          ],
        ),
        SectionHeader(
          label: strings.filterSubtype,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.md,
            bottom: AlayaSpacing.xs,
          ),
        ),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final subtype in TransactionSubtype.values)
              _Choice(
                label: TransactionRow.subtypeLabel(strings, subtype),
                selected: filter.subtypes.contains(subtype),
                onTap: () => notifier.toggleSubtype(subtype),
              ),
          ],
        ),
        SectionHeader(
          label: strings.labelAccount,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.md,
            bottom: AlayaSpacing.xs,
          ),
        ),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final account in accounts.values)
              _Choice(
                label: account.name,
                selected: filter.accountId == account.id,
                onTap: () => notifier.setAccount(
                  filter.accountId == account.id ? null : account.id,
                ),
              ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.filterApply),
        ),
      ],
    );
  }

  /// The localised name of a range preset. Static so the chip bar reads the same mapping.
  static String rangeLabel(AlayaStrings strings, DateRangePreset preset) =>
      switch (preset) {
        DateRangePreset.today => strings.rangeToday,
        DateRangePreset.last7Days => strings.rangeLast7Days,
        DateRangePreset.last30Days => strings.rangeLast30Days,
        DateRangePreset.thisMonth => strings.rangeThisMonth,
        DateRangePreset.lastMonth => strings.rangeLastMonth,
        DateRangePreset.thisYear => strings.rangeThisYear,
        DateRangePreset.allTime => strings.rangeAllTime,
        DateRangePreset.custom => strings.rangeCustom,
      };
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );
}
