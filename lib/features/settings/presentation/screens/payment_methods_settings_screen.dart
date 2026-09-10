import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/features/settings/presentation/sheets/payment_method_sheet.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Settings › Payment methods (ARCH_5 §3 archetype D, outside the shell).
///
/// **Edited in a sheet, not a route.** A payment method is a name and a kind — two fields — and archetype A
/// exists for exactly that: one required field, the keyboard already up, commit as soon as it parses. A
/// full-screen editor for two fields would cost a navigation each way for less work than the transition.
class PaymentMethodsSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const PaymentMethodsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final methods = ref.watch(paymentMethodsSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsPaymentMethods)),
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            PaymentMethodSheet.show(context, existing: null, nextSortOrder: 0),
        tooltip: strings.paymentMethodsAdd,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
      body: methods.when(
        loading: () => AlayaListSkeleton(label: strings.paymentMethodsLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(paymentMethodsSettingsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return EmptyState(
              title: strings.paymentMethodsEmptyTitle,
              body: strings.paymentMethodsEmptyBody,
              icon: Icons.credit_card_outlined,
              actionLabel: strings.paymentMethodsAdd,
              onAction: () => PaymentMethodSheet.show(
                context,
                existing: null,
                nextSortOrder: 0,
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
            itemCount: rows.length,
            itemBuilder: (context, index) => _MethodRow(
              method: rows[index],
              nextSortOrder: rows.length,
            ),
          );
        },
      ),
    );
  }
}

class _MethodRow extends ConsumerWidget {
  const _MethodRow({required this.method, required this.nextSortOrder});

  final PaymentMethod method;
  final int nextSortOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return ListTile(
      leading: Icon(
        _icon(method.kind),
        size: AlayaIconSize.lg,
        color: semantic.muted,
      ),
      title: Text(method.name, style: AlayaTypography.cardTitle),
      subtitle: Text(
        paymentMethodKindLabel(strings, method.kind),
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
      trailing: method.isSystem
          // A system method is renameable but not removable, and the chip says so before the user goes looking
          // for a delete that is not there.
          ? StatusChip(
              label: strings.paymentMethodsSystemChip,
              tone: StatusTone.neutral,
            )
          : IconButton(
              onPressed: () => _delete(context, ref, strings),
              tooltip: strings.paymentMethodsDelete,
              icon: Icon(
                Icons.delete_outline,
                size: AlayaIconSize.md,
                color: semantic.danger,
              ),
            ),
      onTap: () => PaymentMethodSheet.show(
        context,
        existing: method,
        nextSortOrder: nextSortOrder,
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.paymentMethodsDeleteConfirmTitle,
      // Says what survives: a transaction that used this method keeps its record of having done so.
      body: strings.paymentMethodsDeleteConfirmBody,
      confirmLabel: strings.paymentMethodsDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref
        .read(paymentMethodEditorProvider.notifier)
        .delete(method.id);
    if (!context.mounted) return;
    if (ok) {
      showResultSnack(context, message: strings.paymentMethodsDeleted);
    } else {
      showFailureSnack(context, message: strings.paymentMethodsDeleteFailed);
    }
  }

  IconData _icon(PaymentMethodKind kind) => switch (kind) {
    PaymentMethodKind.cash => Icons.payments_outlined,
    PaymentMethodKind.upi => Icons.qr_code_2_outlined,
    PaymentMethodKind.bankTransfer => Icons.account_balance_outlined,
    PaymentMethodKind.card => Icons.credit_card_outlined,
    PaymentMethodKind.cheque => Icons.receipt_long_outlined,
    PaymentMethodKind.wallet => Icons.account_balance_wallet_outlined,
    PaymentMethodKind.other => Icons.more_horiz,
  };
}

/// The name of each payment-method kind.
///
/// Exhaustive without a `default`, so a seventh kind fails to compile here rather than rendering blank.
String paymentMethodKindLabel(AlayaStrings strings, PaymentMethodKind kind) =>
    switch (kind) {
      PaymentMethodKind.cash => strings.paymentKindCash,
      PaymentMethodKind.upi => strings.paymentKindUpi,
      PaymentMethodKind.bankTransfer => strings.paymentKindBankTransfer,
      PaymentMethodKind.card => strings.paymentKindCard,
      PaymentMethodKind.cheque => strings.paymentKindCheque,
      PaymentMethodKind.wallet => strings.paymentKindWallet,
      PaymentMethodKind.other => strings.paymentKindOther,
    };
