import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/money_formatter.dart';
import 'package:alaya/domain/services/split/split_summary_builder.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/features/split/providers/split_summary_provider.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Shows the shareable summary, and hands it to the system share sheet.
///
/// **This is what stands in for sync.** Nobody else has the app — a recorded decision, not a gap — so
/// the way somebody sees the same numbers is that the user sends them. Every review of every
/// competitor names the opposite arrangement as the friction that kills adoption: splitting a bill
/// with six people needs six installs, and two of them never happen.
///
/// **The summary is composed here, not in a provider.** `SplitSummaryBuilder` needs four sentences
/// from the ARB and `AlayaStrings` needs a `BuildContext`, which no provider has.
///
/// **The text is shown before it is sent.** A share sheet that fires straight into WhatsApp gives no
/// chance to notice a wrong name or a stale amount, and this message names what people owe each other
/// — the most consequential thing this app will ever put in somebody else's hands.
class SplitShareSheet extends ConsumerWidget {
  /// Creates the sheet.
  const SplitShareSheet({this.groupId, super.key});

  /// Restrict to one group, or null for everything outstanding.
  final String? groupId;

  /// Opens the sheet.
  static Future<void> show(BuildContext context, {String? groupId}) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => SplitShareSheet(groupId: groupId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    final balances = ref
        .watch(splitSummaryBalancesProvider(groupId))
        .valueOrNull;
    final digits = ref.watch(splitDecimalDigitsProvider).valueOrNull;

    if (balances == null || digits == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AlayaSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    const formatter = MoneyFormatter();
    final handle = ref.watch(splitPaymentHandleProvider).valueOrNull;
    final summary = const SplitSummaryBuilder().build(
      balances: balances,
      nameOf: (id) =>
          ref.read(splitPayeeNameProvider(id)) ?? strings.splitUnknownPerson,
      // `symbol` takes the currency code, matching what the transaction list already passes. There is
      // no symbol lookup in this app, and inventing one here would be a second answer to a question
      // every other screen has settled.
      formatAmount: (Money amount) => formatter.format(
        amount,
        decimalDigits: digits,
        symbol: amount.currencyCode,
      ),
      labels: SummaryLabels(
        heading: strings.splitShareHeading,
        owesYou: strings.splitShareOwesYou,
        youOwe: strings.splitShareYouOwe,
        payMeAt: strings.splitSharePayMeAt,
      ),
      paymentHandle: handle,
    );

    if (summary.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xl),
        child: Text(
          strings.splitAllSettledBody,
          style: AlayaTypography.body.copyWith(color: semantic.muted),
        ),
      );
    }

    final owedAnything = summary.lines.any((line) => line.theyOweMe);
    final hasHandle = handle != null && handle.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.splitShareTitle, style: AlayaTypography.sectionHeader),
        const SizedBox(height: AlayaSpacing.md),

        Container(
          padding: const EdgeInsets.all(AlayaSpacing.sm),
          decoration: BoxDecoration(
            color: semantic.muted.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AlayaSpacing.xs),
          ),
          child: SelectableText(
            summary.text,
            style: AlayaTypography.caption,
          ),
        ),

        // Offered only when somebody actually owes the user — suggesting they add payment details on a
        // summary of their own debts would be advice about the wrong direction. Named as an
        // opportunity rather than an error: the summary is perfectly useful without one.
        if (!hasHandle && owedAnything) ...[
          const SizedBox(height: AlayaSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.splitShareAddHandle,
                  style: AlayaTypography.caption.copyWith(
                    color: semantic.muted,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push(Routes.settingsSplit),
                child: Text(strings.actionAdd),
              ),
            ],
          ),
        ],

        const SizedBox(height: AlayaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: summary.text));
                  if (!context.mounted) return;
                  showResultSnack(context, message: strings.splitShareCopied);
                },
                icon: const Icon(Icons.copy_outlined, size: AlayaIconSize.md),
                label: Text(strings.actionCopy),
              ),
            ),
            const SizedBox(width: AlayaSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: () =>
                    ref.read(splitShareProvider).shareText(summary.text),
                icon: const Icon(Icons.ios_share, size: AlayaIconSize.md),
                label: Text(strings.actionShare),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
