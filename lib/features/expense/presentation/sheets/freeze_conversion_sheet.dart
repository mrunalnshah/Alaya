import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// Picks the currency to freeze a converted snapshot into (ARCH_5 §3 archetype A).
///
/// **A frozen snapshot, not a rewrite.** The original amount and its currency are immutable once
/// saved (Law L9); freezing writes `convertedAmountMinor`, `conversionRate`, `conversionRateRaw` and
/// `conversionDateKey` alongside them as a separate artefact that is never recomputed. The raw rate
/// string is stored so a figure the user later questions can be reproduced exactly.
///
/// The rate used is the one for the transaction's own date, resolved by the greatest
/// `rateDateKey <= D` rule — never interpolated, and marked approximate when only an earlier rate
/// exists (ARCH_3 §1.3).
class FreezeConversionSheet extends ConsumerWidget {
  /// Creates the sheet. Prefer [show].
  const FreezeConversionSheet({required this.excludeCode, super.key});

  /// The transaction's own currency, which is never offered as a target.
  final String excludeCode;

  /// Opens the sheet, resolving to the chosen currency code or null.
  static Future<String?> show(
    BuildContext context, {
    required String excludeCode,
  }) => AlayaBottomSheet.show<String>(
    context: context,
    builder: (context) => FreezeConversionSheet(excludeCode: excludeCode),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final currencies = ref.watch(enabledCurrenciesProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.actionFreezeConversion,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        currencies.when(
          loading: () => AlayaListSkeleton(
            label: strings.loadingLabel,
            rows: 3,
            hasTrailing: false,
          ),
          error: (error, stack) => ErrorState(
            title: strings.errorTitleGeneric,
            body: strings.errorBodyGeneric,
            retryLabel: strings.actionRetry,
            onRetry: () => ref.invalidate(enabledCurrenciesProvider),
          ),
          data: (rows) {
            final options = rows.where((c) => c.code != excludeCode).toList();
            if (options.isEmpty) {
              return EmptyState(
                title: strings.emptyTitleNoResults,
                body: strings.errorBodyGeneric,
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final currency in options)
                  ListTile(
                    title: Text(currency.name),
                    trailing: Text(currency.code, style: AlayaTypography.label),
                    onTap: () => Navigator.of(context).pop(currency.code),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
