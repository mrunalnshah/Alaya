import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/features/settings/providers/app_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// Settings › Currencies (ARCH_5 §3 archetype D, outside the shell).
///
/// **Enabling and disabling only — nothing here creates a currency.** The list is the ISO set the seeder
/// installed, and a user-invented currency would have no rate source, so every amount in it would be
/// permanently unconvertible (ARCH_3 §1). Disabling is what keeps the pickers short.
///
/// **The home currency cannot be disabled, and the switch says why rather than vanishing.** Law L9 makes it the
/// unit every total is aggregated into; disabling it would leave the dashboard with no currency to add up in.
class CurrenciesSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const CurrenciesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final currencies = ref.watch(currenciesSettingsProvider);
    final home = ref.watch(homeCurrencyCodeProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsCurrencies)),
      body: currencies.when(
        loading: () => AlayaListSkeleton(label: strings.currenciesLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(currenciesSettingsProvider),
        ),
        // No empty state, and that is not an omission: `currencies` is seeded by Phase 1C and nothing in the
        // app can delete a row from it, so an empty list is unreachable rather than merely unlikely.
        data: (rows) => ListView.builder(
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
          itemCount: rows.length,
          itemBuilder: (context, index) => _CurrencyRow(
            currency: rows[index],
            isHome: rows[index].code == home,
          ),
        ),
      ),
    );
  }
}

class _CurrencyRow extends ConsumerWidget {
  const _CurrencyRow({required this.currency, required this.isHome});

  final Currency currency;
  final bool isHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return SwitchListTile(
      value: currency.isEnabled || isHome,
      // Disabled rather than hidden: a switch that is missing looks like a rendering fault, while one that is
      // present and inert with a reason beside it is an explanation (ARCH_5 §10).
      onChanged: isHome
          ? null
          : (value) => _toggle(context, ref, strings, value: value),
      // **No chip, and no leading icon.** A `SwitchListTile` reserves room for the switch, so `secondary`
      // plus a chip left the title 172dp — enough to overflow by 2.8px at scale 1 and far worse at two.
      // Both were redundant anyway: every row here is a currency, so an icon says nothing, and the
      // subtitle states in words what the chip said as a badge (Law U17 — words, never only a badge).
      title: Text(
        strings.currenciesRowTitle(currency.code, currency.name),
        style: AlayaTypography.cardTitle,
      ),
      subtitle: Text(
        isHome
            ? strings.currenciesHomeLocked
            : strings.currenciesRowSubtitle(
                currency.symbol,
                currency.decimalDigits,
              ),
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings, {
    required bool value,
  }) async {
    final ok = await ref
        .read(currencyToggleProvider.notifier)
        .setEnabled(code: currency.code, isEnabled: value);
    if (!context.mounted || ok) return;
    showFailureSnack(context, message: strings.currenciesToggleFailed);
  }
}
