import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/sheets/delete_transaction_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/freeze_conversion_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// One transaction in full (ARCH_5 §3 archetype E).
///
/// Routed **outside** the drawer shell, so it gets a back arrow rather than a hamburger: `AppBar`
/// resolves `hasDrawer` before `canPop`, and a detail screen inside the shell leaves the system
/// gesture as the only way out (Law U18).
///
/// The hero answers the question the user opened the screen with. Everything below is a
/// [KeyValueRow], and a row with no value renders nothing at all — a screen of dashes reads as
/// broken data rather than as a record with optional fields.
///
/// **Delete is treated as the non-reversible tier of ARCH_5 §5.5**, which is a contract limitation
/// rather than a design choice: `TransactionRepository` exposes no `restore`, and `update()` cannot
/// stand in because it reads through `v_active_transactions` and so cannot see a deleted row. The
/// sheet therefore acts as the confirmation and captures the optional reason. When `restore` lands
/// with Phase 8B's trash, this becomes an immediate delete with an Undo snack.
class TransactionDetailScreen extends ConsumerWidget {
  /// Shows the transaction with [transactionId].
  const TransactionDetailScreen({required this.transactionId, super.key});

  /// Which transaction to show.
  final String transactionId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final reason = await DeleteTransactionSheet.show(context);
    if (reason == null) return;
    final detached = await ref
        .read(transactionActionsProvider)
        .delete(transactionId, reason: reason);
    if (!context.mounted) return;
    if (detached == null) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.transactionDeleted);
  }

  Future<void> _freeze(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
  ) async {
    final strings = AlayaStrings.of(context);
    final code = await FreezeConversionSheet.show(
      context,
      excludeCode: transaction.originalAmount.currencyCode,
    );
    if (code == null || !context.mounted) return;
    final ok = await ref
        .read(transactionActionsProvider)
        .freezeConversion(
          transaction: transaction,
          toCurrencyCode: code,
        );
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.actionSaved)
        : showFailureSnack(context, message: strings.errorBodyGeneric);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(transactionByIdProvider(transactionId));

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.navExpenses),
        actions: [
          IconButton(
            onPressed: () =>
                context.push(Routes.transactionEdit(transactionId)),
            tooltip: strings.actionEdit,
            icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.lg),
          ),
        ],
      ),
      body: async.when(
        loading: () =>
            AlayaListSkeleton(label: strings.loadingLabel, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: strings.errorBodyGeneric,
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(transactionByIdProvider(transactionId)),
        ),
        data: (transaction) => transaction == null
            ? EmptyState(
                title: strings.errorTitleNotFound,
                body: strings.errorBodyNotFound,
                icon: Icons.search_off_outlined,
              )
            : _Body(
                transaction: transaction,
                onDelete: () => _delete(context, ref),
                onFreeze: () => _freeze(context, ref, transaction),
              ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.transaction,
    required this.onDelete,
    required this.onFreeze,
  });

  final Transaction transaction;
  final VoidCallback onDelete;
  final VoidCallback onFreeze;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts =
        ref.watch(accountsByIdProvider).valueOrNull ??
        const <String, Account>{};
    final payees =
        ref.watch(payeesByIdProvider).valueOrNull ?? const <String, Payee>{};
    final methods =
        ref.watch(paymentMethodsByIdProvider).valueOrNull ??
        const <String, PaymentMethod>{};
    final tags =
        ref.watch(transactionTagsProvider(transaction.id)).valueOrNull ??
        const [];
    final allocation = ref
        .watch(transactionAllocationProvider(transaction.id))
        .valueOrNull;
    final lines = ref.watch(transactionLinesProvider(transaction.id));
    final clock = ref.watch(clockProvider);

    final from = transaction.fromAccountId;
    final to = transaction.toAccountId;
    final payeeId = transaction.payeeId;
    final methodId = transaction.paymentMethodId;
    final frozen = transaction.frozenConversion;

    // `CustomScrollView`, not `ListView(children: [...])`. The lines list is fed by a repository
    // stream and U13 admits no row-count exemption — an itemised grocery receipt runs to dozens of
    // rows, so it is a `SliverList.builder` and the fixed sections around it are adapters.
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
            child: AlayaCard(
              tier: 2,
              padding: const EdgeInsets.all(AlayaSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AmountText(
                    transaction.signedAmount,
                    kind: transaction.kind,
                    size: AmountSize.large,
                    decimalDigits: digits,
                  ),
                  if (frozen != null) ...[
                    const SizedBox(height: AlayaSpacing.xxs),
                    AmountText(
                      frozen,
                      size: AmountSize.small,
                      showSign: false,
                      muted: true,
                    ),
                  ],
                  const SizedBox(height: AlayaSpacing.xs),
                  DateText.relative(transaction.dateKey, clock: clock),
                  if (transaction.needsReview ||
                      (allocation?.hasMismatch ?? false) ||
                      frozen != null) ...[
                    const SizedBox(height: AlayaSpacing.sm),
                    Wrap(
                      spacing: AlayaSpacing.xs,
                      runSpacing: AlayaSpacing.xs,
                      children: [
                        if (transaction.needsReview)
                          StatusChip(
                            label: strings.statusNeedsReview,
                            tone: StatusTone.info,
                          ),
                        if (allocation != null && allocation.hasMismatch)
                          StatusChip(
                            label: strings.statusUnallocated,
                            tone: StatusTone.warning,
                            trailing: AmountText(
                              allocation.unallocated.abs(),
                              size: AmountSize.small,
                              showSign: false,
                              decimalDigits: digits,
                            ),
                          ),
                        if (frozen != null)
                          StatusChip(label: strings.statusApproximate),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        SliverList.list(
          children: [
            SectionHeader(label: strings.detailSectionDetails),
            KeyValueRow(
              label: strings.labelKind,
              value: TransactionRow.kindLabel(strings, transaction.kind),
            ),
            KeyValueRow(
              label: strings.labelSubtype,
              value: TransactionRow.subtypeLabel(strings, transaction.subtype),
            ),
            KeyValueRow(
              label: strings.labelDate,
              valueWidget: DateText(
                transaction.dateKey,
                style: DateTextStyle.full,
              ),
            ),
            if (transaction.kind == TransactionKind.transfer) ...[
              KeyValueRow(
                label: strings.labelFrom,
                value: from == null ? null : accounts[from]?.name,
              ),
              KeyValueRow(
                label: strings.labelTo,
                value: to == null ? null : accounts[to]?.name,
              ),
            ] else
              KeyValueRow(
                label: strings.labelAccount,
                value: accounts[from ?? to ?? '']?.name,
              ),
            KeyValueRow(
              label: strings.labelPaymentMethod,
              value: methodId == null ? null : methods[methodId]?.name,
            ),
            KeyValueRow(
              label: strings.labelPayee,
              value: payeeId == null ? null : payees[payeeId]?.name,
            ),
            KeyValueRow(label: strings.labelNote, value: transaction.note),
            if (frozen != null)
              KeyValueRow(
                label: strings.actionFreezeConversion,
                value: strings.frozenConversionNote(
                  transaction.frozenConversionDateKey?.toIso() ?? '',
                  transaction.frozenConversionRateRaw ?? '',
                ),
              ),
            if (tags.isNotEmpty) ...[
              SectionHeader(label: strings.labelTags),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.screenEdge,
                ),
                child: Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [for (final tag in tags) TagChip(tag: tag)],
                ),
              ),
            ],
            SectionHeader(label: strings.detailSectionLines),
          ],
        ),
        lines.when(
          loading: () => SliverToBoxAdapter(
            child: AlayaListSkeleton(label: strings.loadingLabel, rows: 2),
          ),
          error: (error, stack) => SliverToBoxAdapter(
            child: ErrorState(
              title: strings.errorTitleGeneric,
              body: strings.errorBodyGeneric,
            ),
          ),
          data: (rows) => rows.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AlayaSpacing.screenEdge,
                      vertical: AlayaSpacing.xs,
                    ),
                    child: Text(
                      strings.emptyBodyNoResults,
                      style: AlayaTypography.caption.copyWith(
                        color: semantic.muted,
                      ),
                    ),
                  ),
                )
              : SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) =>
                      _LineRow(line: rows[index], decimalDigits: digits),
                ),
        ),
        SliverList.list(
          children: [
            const SizedBox(height: AlayaSpacing.xxl),
            if (frozen == null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.screenEdge,
                ),
                child: OutlinedButton(
                  onPressed: onFreeze,
                  child: Text(strings.actionFreezeConversion),
                ),
              ),
            const SizedBox(height: AlayaSpacing.sm),
            // Destructive last, quiet, and never a filled button: a red button at the top of a detail
            // screen is a mis-tap waiting to happen.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
              ),
              child: TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(foregroundColor: semantic.danger),
                child: Text(strings.actionDeleteTransaction),
              ),
            ),
            const SizedBox(height: AlayaSpacing.xxxl),
          ],
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.decimalDigits});

  final TransactionLine line;
  final int decimalDigits;

  /// Where this line's artefact lives, or null when it created nothing.
  ///
  /// Surfaces `transaction_lines.created*Id` (ARCH_5 §7.2): a purchase that produced a television
  /// or two kilos of potatoes should say so, and let the user walk to it.
  String? _artefactRoute() {
    final itemId = line.itemId;
    if (line.createdBatchId != null && itemId != null)
      return Routes.itemDetail(itemId);
    final assetId = line.createdAssetId;
    if (assetId != null) return Routes.assetDetail(assetId);
    final templateId = line.createdRecurringTemplateId;
    if (templateId != null) return Routes.recurringDetail(templateId);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final route = _artefactRoute();
    final quantity = line.quantity;
    final amount = line.lineAmount;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.screenEdge,
        vertical: AlayaSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.description,
                  style: AlayaTypography.body.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (quantity != null) ...[
                  const SizedBox(height: AlayaSpacing.xxs),
                  QtyText(quantity, muted: true),
                ],
                if (route != null) ...[
                  const SizedBox(height: AlayaSpacing.xxs),
                  InkWell(
                    onTap: () => context.push(route),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AlayaSpacing.xxs,
                      ),
                      child: Text(
                        strings.lineCreatedLink(line.description),
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.transfer,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (amount != null) ...[
            const SizedBox(width: AlayaSpacing.sm),
            AmountText(
              amount,
              size: AmountSize.small,
              showSign: false,
              decimalDigits: decimalDigits,
            ),
          ],
        ],
      ),
    );
  }
}
