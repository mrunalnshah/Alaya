import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/dispose_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Retires an asset without destroying it (ARCH_5 §3 archetype A).
///
/// **There is no delete anywhere in this module, and this sheet is why.** Disposal sets a status and
/// records a reason; the purchase price, the warranty dates and every service record stay exactly where
/// they were. The ₹45,000 spent on a television still counts in every total after the television has
/// gone to the tip, because the money left the house whether or not the object did (anomaly A30,
/// ARCH_3 §4.1). The body text says so, because a user reaching for this button is entitled to know
/// what it will not do.
class DisposeSheet extends ConsumerWidget {
  /// Creates the sheet.
  const DisposeSheet({
    required this.assetId,
    required this.currencyCode,
    super.key,
  });

  /// Which asset is being retired.
  final String assetId;

  /// The currency a recovered amount is entered in.
  final String currencyCode;

  /// Opens the sheet.
  ///
  /// Resolves to the empty string when the disposal committed, to a message when it failed, and to null
  /// when the user backed out — so a caller can tell "done" from "changed their mind".
  static Future<String?> show(
    BuildContext context, {
    required String assetId,
    required String currencyCode,
  }) => AlayaBottomSheet.show<String>(
    context: context,
    builder: (context) =>
        DisposeSheet(assetId: assetId, currencyCode: currencyCode),
  );

  DisposeArgs get _args => (assetId: assetId, currencyCode: currencyCode);

  /// Resolves an [AssetDisposalReason] to its ARB label.
  static String reasonLabel(AlayaStrings strings, AssetDisposalReason reason) =>
      switch (reason) {
        AssetDisposalReason.sold => strings.disposeReasonSold,
        AssetDisposalReason.expired => strings.disposeReasonExpired,
        AssetDisposalReason.damaged => strings.disposeReasonDamaged,
        AssetDisposalReason.gifted => strings.disposeReasonGifted,
        AssetDisposalReason.lost => strings.disposeReasonLost,
        AssetDisposalReason.replaced => strings.disposeReasonReplaced,
        AssetDisposalReason.other => strings.disposeReasonOther,
      };

  Future<void> _commit(BuildContext context, WidgetRef ref) async {
    final error = await ref.read(disposeProvider(_args).notifier).commit();
    if (!context.mounted) return;
    // A missing reason is a field error the sheet already shows; it must not close over it.
    if (error == 'reasonMissing') return;
    Navigator.of(context).pop(error ?? '');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final state = ref.watch(disposeProvider(_args));
    final notifier = ref.read(disposeProvider(_args).notifier);
    final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2;
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) =>
        DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.disposeTitle,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          strings.disposeBody,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // A `Wrap` of choice chips rather than a dropdown: seven reasons is few enough to read at once,
        // and every one of them reflows independently at a doubled text scale (Law U21).
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              for (final reason in AssetDisposalReason.values)
                ChoiceChip(
                  label: Text(reasonLabel(strings, reason)),
                  selected: state.reason == reason,
                  onSelected: (_) => notifier.setReason(reason),
                ),
            ],
          ),
        ),
        if (state.reasonMissing) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.disposeNeedsReason,
            style: AlayaTypography.caption.copyWith(color: semantic.danger),
          ),
        ],
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.dateKey,
          formatted: format,
          label: strings.labelDisposalDate,
          hint: strings.hintSelectDate,
          onChanged: (date) => date == null ? null : notifier.setDate(date),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // Optional, because most disposals recover nothing — a broken kettle is thrown away, not sold —
        // and requiring a zero would make the common case extra typing.
        AmountField(
          currencyCode: currencyCode,
          decimalDigits: digits,
          label: strings.labelDisposalAmount,
          initialValue: state.amount,
          onChanged: notifier.setAmount,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.note,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: strings.labelNote,
            hintText: strings.hintNote,
          ),
          onChanged: notifier.setNote,
        ),
        if (state.rejection != null) ...[
          const SizedBox(height: AlayaSpacing.sm),
          Text(
            state.rejection!,
            style: AlayaTypography.caption.copyWith(color: semantic.danger),
          ),
        ],
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: state.submitting ? null : () => _commit(context, ref),
          child: Text(strings.disposeCommit),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionCancel),
        ),
      ],
    );
  }
}
